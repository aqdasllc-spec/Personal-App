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
import 'package:folio/features/library/application/reader_prefs.dart';
import 'package:folio/features/library/application/ocr_controller.dart';
import 'package:folio/features/library/data/ocr.dart';
import 'package:folio/features/library/presentation/page_thumbs.dart';
import 'package:folio/features/library/application/export_ink.dart';
import 'package:folio/features/library/data/ink_export.dart';
import 'package:folio/features/library/data/media_controls.dart';
import 'package:folio/features/library/application/export_notes.dart' show shareFileProvider;
import 'package:folio/features/backup/backup_controller.dart' show backupTempDirProvider;
import 'package:folio/features/library/data/speech.dart';
import 'package:folio/features/library/application/read_aloud.dart';
import 'package:folio/features/library/domain_highlights.dart';
import 'package:folio/features/library/domain_ink.dart';
import 'package:folio/features/library/data/cloud_books.dart';
import 'package:folio/features/library/data/library_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:folio/app/app.dart';
import 'package:folio/app/quick_actions.dart';
import 'package:folio/app/providers.dart';
import 'package:folio/app/sync_controller.dart';
import 'package:folio/data/local/app_database.dart';
import 'package:folio/data/local/database_opener.dart';
import 'package:folio/data/sync/in_memory_transport.dart';
import 'package:folio/data/sync/synced_store.dart';
import 'package:folio/data/sync/sync_service.dart';
import 'package:folio/features/auth/auth_repository.dart';
import 'package:folio/features/security/app_lock.dart';
import 'package:folio/features/quran/application/quran_audio.dart';
import 'package:folio/features/quran/prayer/battery.dart';
import 'package:folio/features/quran/presentation/quran_style.dart' show QuranTranslation;
import 'package:folio/features/library/application/open_with.dart';
import 'package:folio/features/library/data/pdf_outline.dart';
import 'package:folio/features/library/application/search_all.dart' show BookTextCache, bookTextCacheProvider;
import 'package:folio/features/quran/prayer/prayer_ringer.dart';
import 'package:folio/features/planner/domain/reminders.dart';
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

/// Records what the reader asked of the phone (orientation lock, full screen, screen-on).
class FakeReaderSystem implements ReaderSystem {
  final orientations = <ReaderOrientation>[];
  final immersive = <bool>[];
  int restores = 0;
  @override
  void setOrientation(ReaderOrientation o) => orientations.add(o);
  @override
  void setImmersive(bool on) => immersive.add(on);
  @override
  void restore() => restores++;
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

/// Reads "pages" from a table instead of a picture.
class FakeRecognizer implements PageRecognizer {
  FakeRecognizer(this.pages);
  final Map<int, List<OcrLine>> pages;
  final asked = <int>[];
  Completer<void>? gate; // set to hold recognition until completed
  @override
  Future<RecognizedPage?> recognize(File pdf, int page) async {
    asked.add(page);
    if (gate != null) await gate!.future;
    final l = pages[page];
    return l == null ? null : RecognizedPage(l);
  }

  @override
  Future<void> close() async {}
}

class FakeSpeechEngine implements SpeechEngine {
  final spoken = <String>[];
  final rates = <double>[];
  int stops = 0;
  @override
  Future<void> speak(String text) async {
    spoken.add(text);
    await Future<void>.delayed(Duration.zero);
  }

  @override
  Future<void> stop() async => stops++;
  @override
  Future<void> setRate(double f) async => rates.add(f);
  @override
  Future<void> dispose() async {}

  /// Voices the "phone" offers, and the ones chosen (null = default).
  List<VoiceInfo> installed = const [
    VoiceInfo('en-us-x-aaa-local', 'en-US'),
    VoiceInfo('en-gb-x-bbb-local', 'en-GB'),
    VoiceInfo('hi-in-x-ccc-local', 'hi-IN'),
  ];
  final chosen = <VoiceInfo?>[];
  @override
  Future<List<VoiceInfo>> voices() async => installed;
  @override
  Future<void> setVoice(VoiceInfo? voice) async => chosen.add(voice);
}

/// Quran recitation without sound: remembers the queue and lets a test move through it.
class FakeAyahPlayer implements AyahPlayer {
  List<Uri> queue = const [];
  int current = 0;
  bool playing = false;
  final _index = StreamController<int?>.broadcast();
  final _phase = StreamController<PlayerPhase>.broadcast();

  @override
  Future<void> setQueue(List<Uri> urls, {int start = 0}) async {
    queue = urls;
    current = start;
    _index.add(start);
  }

  @override
  Future<void> play() async {
    playing = true;
    _phase.add(PlayerPhase.playing);
  }

  @override
  Future<void> pause() async {
    playing = false;
    _phase.add(PlayerPhase.paused);
  }

  @override
  Future<void> stop() async {
    playing = false;
    _phase.add(PlayerPhase.idle);
  }

  @override
  Future<void> seekToIndex(int i) async {
    current = i;
    _index.add(i);
  }

  /// The current file finished: the next one starts (or, after the last, playback ends).
  void finishCurrent() {
    if (current + 1 < queue.length) {
      current++;
      _index.add(current);
    } else {
      playing = false;
      _phase.add(PlayerPhase.finished);
    }
  }

  @override
  Stream<int?> get index => _index.stream;
  @override
  Stream<PlayerPhase> get phase => _phase.stream;
  @override
  Future<void> dispose() async {}
}

class FakeMediaControls implements MediaControls {
  /// One entry per update: "title|subtitle|playing"; "hide" when removed.
  final log = <String>[];
  Future<void> Function()? onPlay, onPause, onStop, onNext, onPrevious;
  @override
  Future<void> show({
    required String title,
    required String subtitle,
    required bool playing,
    required Future<void> Function() onPlay,
    required Future<void> Function() onPause,
    required Future<void> Function() onStop,
    required Future<void> Function() onNext,
    required Future<void> Function() onPrevious,
  }) async {
    log.add('$title|$subtitle|${playing ? 'playing' : 'paused'}');
    this.onPlay = onPlay;
    this.onPause = onPause;
    this.onStop = onStop;
    this.onNext = onNext;
    this.onPrevious = onPrevious;
  }

  @override
  Future<void> hide() async => log.add('hide');
}

/// "Draws" every page as the same tiny picture (a 1x1 PNG); pages in [missing] cannot be drawn.
class FakePageImager implements PageImager {
  FakePageImager({this.missing = const {}});
  final Set<int> missing;
  final asked = <int>[];
  static final Uint8List onePixel = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==');
  @override
  Future<Uint8List?> png(File pdf, int page, {int width = 1100}) async {
    asked.add(page);
    return missing.contains(page) ? null : onePixel;
  }

  @override
  Future<void> close() async {}
}

class FakePageTexts implements PageTextReader {
  FakePageTexts(this.pages, {this.byBook = const {}});
  final Map<int, String> pages;

  /// Texts for particular books (by book id, the file is named `<id>.pdf`); other books use [pages].
  final Map<String, Map<int, String>> byBook;
  int reads = 0;
  @override
  Future<String?> textOf(File pdf, int page) async {
    reads++;
    final id = pdf.uri.pathSegments.last.replaceAll('.pdf', '');
    return byBook.containsKey(id) ? byBook[id]![page] : pages[page];
  }
}

class FakeQuickActions implements QuickActionsPort {
  List<QuickAction> items = const [];
  void Function(String)? tap;
  @override
  void start(List<QuickAction> items, void Function(String type) onAction) {
    this.items = items;
    tap = onAction;
  }
}

class FakeProbe implements TextProbe {
  FakeProbe(this.result);
  bool? result;
  @override
  Future<bool?> hasText(File pdf) async => result;
}

class TestEnv {
  TestEnv._(this.db, this.store, this.authenticator, this.auth, this.sync, this.transport, this.server);
  final AppDatabase db;
  final SyncedStore store;
  final FakeAuthenticator authenticator;
  final FakeAuthRepository auth;
  final SyncService? sync;
  final InMemoryTransport? transport;
  final FakeServer? server;

  static Future<TestEnv> create({AppSession session = const LocalOnlySession(), bool lockEnabled = false, bool withSync = false, bool showWelcome = false}) async {
    quietDrift();
    final db = openInMemory();
    final store = await SyncedStore.open(db, deviceId: 'test-device');
    if (!showWelcome) await store.setState('welcome_done', '1'); // the first-run tour would cover every other test
    final server = withSync ? FakeServer() : null;
    final transport = withSync ? InMemoryTransport(server!) : null;
    return TestEnv._(db, store, FakeAuthenticator(), FakeAuthRepository(session), withSync ? SyncService(store, transport!) : null, transport, server)
      .._lockEnabled = lockEnabled;
  }

  bool _lockEnabled = false;

  /// Library test doubles: a temp folder, a fake page counter, a fake picker and a stub reader.
  late final Directory libraryDir = Directory.systemTemp.createTempSync('folio_lib');
  List<String> picked = [];
  String? pickedFolder;

  /// Set to a [FakeCloudBooks] to give the build a cloud shelf (null = build without cloud sync).
  FakeCloudBooks? cloud;
  final readerSystem = FakeReaderSystem();

  /// Scanned-PDF doubles: what the probe says (true = real text) and what the recogniser "reads" (null = none on this device).
  bool? probeResult = true;
  FakeRecognizer? recognizer;
  final quick = FakeQuickActions();
  final speech = FakeSpeechEngine();
  final media = FakeMediaControls();
  final opened = <Uri>[];
  final imager = FakePageImager();

  /// Files handed to the share sheet: (file name, subject, first bytes).
  final sharedFiles = <(String, String, String)>[];
  late final Directory shareDir = Directory.systemTemp.createTempSync('folio_share');

  /// What the voice finds on each page of a book that has real text.
  final pageTextsByBook = <String, Map<int, String>>{};
  final pageTexts = <int, String>{1: 'First page text.', 2: 'Second page text.', 3: 'Third page text.'};
  final awake = <bool>[];

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

  /// The Quran recitation player (no sound in tests).
  final ayahPlayer = FakeAyahPlayer();
  late final pageTextReader = FakePageTexts(pageTexts, byBook: pageTextsByBook);
  final textCache = MemoryTextCache();
  final ringer = FakeRinger();
  final openWith = FakeOpenWith();

  /// The table of contents every PDF has in tests (none unless a test sets it).
  List<PdfChapter> chapters = const [];
  final battery = FakeBattery();

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
        readerSystemProvider.overrideWithValue(readerSystem),
        quickActionsProvider.overrideWithValue(quick),
        speechEngineProvider.overrideWithValue(speech),
        mediaControlsProvider.overrideWithValue(media),
        ayahPlayerFactoryProvider.overrideWithValue(() => ayahPlayer),
        prayerRingerProvider.overrideWithValue(ringer),
        openWithPortProvider.overrideWithValue(openWith),
        pdfOutlineReaderProvider.overrideWithValue((_) async => chapters),
        batteryPortProvider.overrideWithValue(battery),
        pageThumbsBuilderProvider.overrideWithValue((context, {required file, required pageCount, required current, required bookmarked, required drawn, required onPick}) => PageThumbGrid(
              pageCount: pageCount,
              current: current,
              bookmarked: bookmarked,
              drawn: drawn,
              onPick: onPick,
              pictureOf: (p) => Center(child: Text('picture $p')),
            )),
        urlOpenerProvider.overrideWithValue((uri) async {
          opened.add(uri);
          return true;
        }),
        pageImagerProvider.overrideWithValue(imager),

        pageTextReaderProvider.overrideWithValue(pageTextReader),
        bookTextCacheProvider.overrideWithValue(textCache),
        textProbeProvider.overrideWithValue(FakeProbe(probeResult)),
        pageRecognizerProvider.overrideWithValue(recognizer),
        screenAwakeProvider.overrideWithValue(awake.add),
        pdfInspectorProvider.overrideWithValue(FakePdfInspector()),
        pdfPickerProvider.overrideWithValue(() async => picked),
        pdfFolderPickerProvider.overrideWithValue(() async => pickedFolder),
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
          return SingleChildScrollView(child: Column(children: [
            Text('PDF view page $initial'),
            TextButton(onPressed: () => onPage(7), child: const Text('go to page 7')),
            TextButton(onPressed: () => control.onZoneTap?.call(TapZone.left), child: const Text('tap left')),
            TextButton(onPressed: () => control.onZoneTap?.call(TapZone.center), child: const Text('tap center')),
            TextButton(onPressed: () => control.onZoneTap?.call(TapZone.right), child: const Text('tap right')),
            ValueListenableBuilder(valueListenable: control.prefs, builder: (_, v, _) => Text('prefs ${v.theme.name} ${v.scroll.name}')),
            TextButton(
              onPressed: () => control.onHighlight?.call(const HighlightDraft(page: 3, rects: [[10, 100, 80, 90]], text: 'an important passage')),
              child: const Text('select and highlight'),
            ),
            // pen: draws a stroke on page 2 with the chosen colour/width; shows what the page would paint
            TextButton(
              onPressed: () => control.onStroke?.call(2, Stroke(control.pen.value.color, penWidths[control.pen.value.width].$2 * (control.pen.value.highlighter ? highlighterScale : 1), const [0.1, 0.1, 0.5, 0.5], highlighter: control.pen.value.highlighter)),
              child: const Text('draw stroke'),
            ),
            TextButton(onPressed: () => control.onLookUp?.call('  serendipity\n happy accident  '), child: const Text('look up selection')),
            TextButton(onPressed: () => control.onErase?.call(2, 0.3, 0.3), child: const Text('rub on stroke')),
            TextButton(onPressed: () => control.onErase?.call(2, 0.9, 0.1), child: const Text('rub elsewhere')),
            ValueListenableBuilder(
              valueListenable: control.ink,
              builder: (_, v, _) => Text('ink ${{for (final e in v.entries) if (e.value.isNotEmpty) e.key: e.value.length}}'),
            ),
            ValueListenableBuilder(valueListenable: control.pen, builder: (_, v, _) => Text('pen ${v.on ? 'on' : 'off'}')),
            ValueListenableBuilder(valueListenable: control.highlights, builder: (_, v, _) => Text('painting ${v.length} highlights')),
          ]));
        }),
      ];

  /// Overrides for tests that look at what was shared (not in [overrides]: the Backup and notes tests set their own).
  List<Override> get shareOverrides => [
        backupTempDirProvider.overrideWithValue(() async => shareDir),
        shareFileProvider.overrideWithValue((file, subject) async {
          sharedFiles.add((file.uri.pathSegments.last, subject, String.fromCharCodes(file.readAsBytesSync().take(5))));
          return true;
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

/// Records the spoken / own-sound prayer alarms instead of setting real ones.
class FakeRinger implements PrayerRinger {
  List<Reminder> alarms = const [];
  final tests = <Reminder>[];
  final stopped = <int>[];
  bool works = true;
  String? problem;
  final _ringing = StreamController<List<RingingAlarm>>.broadcast();
  void ring(List<RingingAlarm> a) => _ringing.add(a);
  @override
  Future<void> start() async {}
  @override
  Future<RingResult> replace(List<Reminder> a) async {
    if (!works) return const RingResult(ok: false);
    alarms = a;
    return RingResult(problem: problem);
  }

  @override
  Future<RingResult> test(Reminder r) async {
    if (!works) return const RingResult(ok: false);
    tests.add(r);
    return RingResult(problem: problem);
  }

  @override
  Future<Map<int, DateTime>> pending() async => {for (final a in alarms) a.id: a.at};
  @override
  Stream<List<RingingAlarm>> get ringing => _ringing.stream;
  @override
  Future<void> stop(int id) async {
    stopped.add(id);
    _ringing.add(const []);
  }
}

class FakeBattery implements BatteryPort {
  bool? unrestricted = true;
  int asked = 0, opened = 0;
  @override
  Future<bool?> isUnrestricted() async => unrestricted;
  @override
  Future<bool> askUnrestricted() async {
    asked++;
    return true;
  }

  @override
  Future<bool> openAppSettings() async {
    opened++;
    return true;
  }
}

/// PDFs "handed over by another app" in tests.
class FakeOpenWith implements OpenWithPort {
  String? first;
  final _c = StreamController<String>.broadcast();
  void hand(String path) => _c.add(path);
  @override
  Future<String?> initial() async {
    final f = first;
    first = null;
    return f;
  }

  @override
  Stream<String> get opened => _c.stream;
}

class MemoryTextCache implements BookTextCache {
  final kept = <String, Map<int, String>>{};
  @override
  Future<Map<int, String>> load(String bookId) async => {...?kept[bookId]};
  @override
  Future<void> save(String bookId, Map<int, String> pages) async => kept[bookId] = {...pages};
}

/// The text shown by a [Text] (plain or rich) or a [QuranTranslation] found by [f].
String textOf(WidgetTester t, Finder f) {
  final w = t.widget(f);
  if (w is Text) return w.data ?? w.textSpan!.toPlainText();
  if (w is QuranTranslation) return w.text;
  throw ArgumentError('No text in ${w.runtimeType}');
}
