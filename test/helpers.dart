import 'dart:async';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:folio/features/library/application/covers.dart';
import 'package:folio/features/library/data/cover_renderer.dart';
import 'package:folio/features/backup/backup_service.dart';
import 'package:flutter/material.dart';
import 'package:folio/features/library/application/book_sync.dart';
import 'package:folio/features/library/application/library_controller.dart';
import 'package:folio/features/library/data/cloud_books.dart';
import 'package:folio/features/library/data/library_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:folio/app/app.dart';
import 'package:folio/app/providers.dart';
import 'package:folio/app/sync_controller.dart';
import 'package:folio/data/local/app_database.dart';
import 'package:folio/data/local/database_opener.dart';
import 'package:folio/data/sync/in_memory_transport.dart';
import 'package:folio/data/sync/synced_store.dart';
import 'package:folio/data/sync/sync_service.dart';
import 'package:folio/features/auth/auth_repository.dart';
import 'package:folio/features/security/app_lock.dart';
import 'package:sync_engine/sync_engine.dart';

/// Reads "pages=N" from the file's text instead of running a PDF engine.
class FakePdfInspector implements PdfInspector {
  @override
  Future<PdfInfo?> inspect(String path) async {
    final text = await File(path).readAsString();
    final m = RegExp(r'pages=(\d+)').firstMatch(text);
    return m == null ? null : PdfInfo(pageCount: int.parse(m.group(1)!));
  }
}

/// In-memory cloud shelf. Hold uploads with [gate]; make the next call fail with [failWith].
class FakeCloudBooks implements CloudBooks {
  final files = <String, List<int>>{};
  final meta = <String, CloudBook>{};
  Completer<void>? gate;
  String? failWith;
  int uploads = 0, removes = 0;

  Future<void> _maybeFail() async {
    final g = gate;
    if (g != null) await g.future;
    final f = failWith;
    if (f != null) {
      failWith = null;
      throw CloudException(f);
    }
  }

  @override
  Future<void> upload(CloudBook book, File file) async {
    await _maybeFail();
    uploads++;
    files[book.id] = await file.readAsBytes();
    meta[book.id] = book;
  }

  @override
  Future<void> remove(String bookId) async {
    await _maybeFail();
    removes++;
    files.remove(bookId);
    meta.remove(bookId);
  }

  @override
  Future<List<CloudBook>> list() async => meta.values.toList();

  @override
  Future<void> download(String bookId, File destination) async {
    await _maybeFail();
    await destination.writeAsBytes(files[bookId]!);
  }
}

/// A real 1x1 PNG so Image.memory has something valid to decode.
final fakePng = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==');

class FakeCoverRenderer implements CoverRenderer {
  int calls = 0;
  Uint8List? bytes = fakePng;
  @override
  Future<Uint8List?> renderFirstPage(File pdf, {int width = 420}) async {
    calls++;
    return bytes;
  }
}

class FakeAuthenticator implements Authenticator {
  bool available = true;
  bool succeed = true;
  int calls = 0;
  @override
  Future<bool> isAvailable() async => available;
  @override
  Future<bool> authenticate(String reason) async {
    calls++;
    return succeed;
  }
}

class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository([AppSession initial = const SignedOutSession()]) : _current = initial;
  AppSession _current;
  Object? failWith;
  bool confirmationRequired = false;
  final calls = <String>[];
  final _c = StreamController<AppSession>.broadcast();
  @override
  AppSession get current => _current;
  @override
  Stream<AppSession> get changes => _c.stream;
  void _set(AppSession s) {
    _current = s;
    _c.add(s);
  }

  @override
  Future<void> signIn(String email, String password) async {
    calls.add('signIn:$email');
    if (failWith != null) throw failWith!;
    _set(SignedInSession(userId: 'u1', email: email));
  }

  @override
  Future<bool> signUp(String email, String password) async {
    calls.add('signUp:$email');
    if (failWith != null) throw failWith!;
    if (confirmationRequired) return false;
    _set(SignedInSession(userId: 'u1', email: email));
    return true;
  }

  @override
  Future<void> signOut() async => _set(const SignedOutSession());
  @override
  Future<void> continueLocalOnly() async => _set(const LocalOnlySession());
  @override
  bool cloudAvailable = true;
  @override
  Future<void> leaveLocalOnly() async {
    calls.add('leaveLocalOnly');
    _set(const SignedOutSession());
  }
}

/// Tests intentionally create several in-memory databases.
void quietDrift() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

class TestEnv {
  TestEnv._(this.db, this.store, this.authenticator, this.auth, this.sync, this.transport, this.server);
  final AppDatabase db;
  final SyncedStore store;
  final FakeAuthenticator authenticator;
  final FakeAuthRepository auth;
  final SyncService? sync;
  final InMemoryTransport? transport;
  final FakeServer? server;

  static Future<TestEnv> create({AppSession session = const LocalOnlySession(), bool lockEnabled = false, bool withSync = false}) async {
    quietDrift();
    final db = openInMemory();
    final store = await SyncedStore.open(db, deviceId: 'test-device');
    final server = withSync ? FakeServer() : null;
    final transport = withSync ? InMemoryTransport(server!) : null;
    return TestEnv._(db, store, FakeAuthenticator(), FakeAuthRepository(session), withSync ? SyncService(store, transport!) : null, transport, server)
      .._lockEnabled = lockEnabled;
  }

  bool _lockEnabled = false;

  /// Library test doubles: a temp folder, a fake page counter, a fake picker and a stub reader.
  late final Directory libraryDir = Directory.systemTemp.createTempSync('folio_lib');
  List<String> picked = [];

  /// Set to a [FakeCloudBooks] to give the build a cloud shelf (null = build without cloud sync).
  FakeCloudBooks? cloud;

  /// Pages the reader was asked to jump to (bookmarks).
  final jumps = <int>[];
  final searches = <String>[];
  int searchCursor = -1;
  final covers = FakeCoverRenderer();

  /// Writes a fake PDF (the fake inspector reads the page count from its text).
  Future<String> writePdf(String name, int pages) async {
    final dir = await Directory.systemTemp.createTemp('pdf');
    final f = File('${dir.path}/$name');
    await f.writeAsString('pages=$pages');
    return f.path;
  }

  /// Replace the sync controller (e.g. to add sign-in gating).
  SyncController Function()? syncControllerFactory;

  List<Override> get overrides => [
        databaseProvider.overrideWithValue(db),
        syncedStoreProvider.overrideWithValue(store),
        authRepositoryProvider.overrideWithValue(auth),
        syncServiceProvider.overrideWithValue(sync),
        authenticatorProvider.overrideWithValue(authenticator),
        appLockProvider.overrideWith(() => AppLockController(authenticator: authenticator, startEnabled: _lockEnabled)),
        syncControllerProvider.overrideWith(syncControllerFactory ?? () => SyncController(sync, interval: const Duration(days: 1))),
        libraryDirectoryProvider.overrideWithValue(libraryDir),
        cloudBooksProvider.overrideWithValue(cloud),
        coverRendererProvider.overrideWithValue(covers),
        pdfInspectorProvider.overrideWithValue(FakePdfInspector()),
        pdfPickerProvider.overrideWithValue(() async => picked),
        pdfViewBuilderProvider.overrideWithValue((context, file, initial, onPage, control) {
          control.goTo = (p) {
            jumps.add(p);
            onPage(p);
          };
          // canned search results: "permit" has 3 matches (pages 2, 5, 9), anything else none
          const hits = {'permit': [2, 5, 9]};
          void publish(String q) => control.search.value = ReaderSearch(query: q, count: hits[q]?.length ?? 0, index: searchCursor < 0 ? null : searchCursor);
          control.startSearch = (q) {
            searches.add(q);
            searchCursor = hits[q.trim().toLowerCase()] == null ? -1 : 0;
            if (searchCursor == 0) onPage(hits[q.trim().toLowerCase()]![0]);
            publish(q.trim().toLowerCase());
          };
          control.nextMatch = () {
            final h = hits[control.search.value.query]!;
            searchCursor = (searchCursor + 1) % h.length;
            onPage(h[searchCursor]);
            publish(control.search.value.query);
          };
          control.prevMatch = () {
            final h = hits[control.search.value.query]!;
            searchCursor = (searchCursor - 1 + h.length) % h.length;
            onPage(h[searchCursor]);
            publish(control.search.value.query);
          };
          control.stopSearch = () {
            searches.add('<stop>');
            control.search.value = const ReaderSearch();
          };
          return Column(children: [
            Text('PDF view page $initial'),
            TextButton(onPressed: () => onPage(7), child: const Text('go to page 7')),
          ]);
        }),
      ];

  Widget get app => ProviderScope(overrides: overrides, child: const FolioApp());
}

/// Pump a few short frames so debounced work and database futures complete, then settle.
Future<void> settle(WidgetTester t) async {
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 80));
  }
  await t.pumpAndSettle();
}

/// A BackupService over a TestEnv's database (for building backup files in tests).
BackupService backupServiceFor(TestEnv e) => BackupService(e.db, e.store, libraryDir: e.libraryDir);
