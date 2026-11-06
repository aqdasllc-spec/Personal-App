import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../data/local/app_database.dart';
import '../../auth/auth_repository.dart';
import '../data/cloud_books.dart';
import 'library_controller.dart';

/// The cloud shelf, or null when this build/account has none (local-only mode, not signed in).
final cloudBooksProvider = Provider<CloudBooks?>((ref) => null);

/// Whether per-book cloud sync can be used right now.
final canCloudSyncProvider = Provider<bool>((ref) {
  final session = ref.watch(sessionProvider).value ?? ref.watch(authRepositoryProvider).current;
  return ref.watch(cloudBooksProvider) != null && session is SignedInSession;
});

class BookSyncState {
  const BookSyncState({this.busy = const {}, this.message});

  /// Book ids being uploaded / removed right now (shown as rotating arrows).
  final Set<String> busy;

  /// One-shot message for the UI (errors, results).
  final String? message;
  BookSyncState copyWith({Set<String>? busy, String? message, bool clearMessage = false}) => BookSyncState(busy: busy ?? this.busy, message: clearMessage ? null : (message ?? this.message));
}

class BookSyncController extends Notifier<BookSyncState> {
  @override
  BookSyncState build() => const BookSyncState();

  CloudBooks get _cloud => ref.read(cloudBooksProvider) ?? (throw CloudException('Sign in to use cloud sync.'));
  AppDatabase get _db => ref.read(databaseProvider);

  void clearMessage() => state = state.copyWith(clearMessage: true);

  void _busy(String id, bool on) => state = state.copyWith(busy: on ? {...state.busy, id} : ({...state.busy}..remove(id)));

  Future<void> _setCloud(String id, String s) => (_db.update(_db.books)..where((b) => b.id.equals(id))).write(BooksCompanion(cloudState: Value(s)));

  /// Uploads the book's PDF. The dot turns green only after both file and metadata are in the cloud.
  Future<bool> sync(BookRow b) async {
    if (state.busy.contains(b.id)) return false;
    _busy(b.id, true);
    try {
      final file = ref.read(libraryRepositoryProvider).fileOf(b);
      if (!await file.exists()) throw CloudException('The PDF file is missing on this device.');
      await _cloud.upload(CloudBook(id: b.id, title: b.title, author: b.author, pageCount: b.pageCount, sizeBytes: b.sizeBytes, sha256: b.sha256), file);
      await _setCloud(b.id, 'synced');
      return true;
    } catch (e) {
      state = state.copyWith(message: 'Couldn\'t sync "${b.title}": $e');
      return false;
    } finally {
      _busy(b.id, false);
    }
  }

  /// Deletes the cloud copy (the book stays on this device).
  Future<bool> unsync(BookRow b) async {
    if (state.busy.contains(b.id)) return false;
    _busy(b.id, true);
    try {
      await _cloud.remove(b.id);
      await _setCloud(b.id, 'local');
      return true;
    } catch (e) {
      state = state.copyWith(message: 'Couldn\'t remove "${b.title}" from the cloud: $e');
      return false;
    } finally {
      _busy(b.id, false);
    }
  }

  /// Removes a book from the library; if it has a cloud copy that is deleted too (so no space is wasted).
  /// If the cloud can't be reached the book stays, so nothing is left behind in the cloud.
  Future<bool> removeBook(BookRow b) async {
    if (b.cloudState == 'synced') {
      if (ref.read(cloudBooksProvider) == null) {
        state = state.copyWith(message: 'Sign in to remove "${b.title}" — its cloud copy would be left behind otherwise.');
        return false;
      }
      if (!await unsync(b)) return false;
    }
    await ref.read(libraryRepositoryProvider).remove(b.id);
    return true;
  }

  /// Cloud books that are not on this device yet.
  Future<List<CloudBook>> missingLocally() async {
    final cloud = ref.read(cloudBooksProvider);
    if (cloud == null) return const [];
    final local = await _db.select(_db.books).get();
    final ids = {for (final b in local) if (b.deletedAt == null) b.id};
    final hashes = {for (final b in local) if (b.deletedAt == null && b.sha256.isNotEmpty) b.sha256};
    return [for (final c in await cloud.list()) if (!ids.contains(c.id) && !(c.sha256.isNotEmpty && hashes.contains(c.sha256))) c];
  }

  /// Downloads every cloud book that is missing here. Returns how many arrived.
  Future<int> downloadAll() async {
    if (state.busy.contains('*download')) return 0;
    _busy('*download', true);
    try {
      return await downloadMissing();
    } finally {
      _busy('*download', false);
    }
  }

  Future<int> downloadMissing() async {
    var n = 0;
    final problems = <String>[];
    try {
      final repo = ref.read(libraryRepositoryProvider);
      for (final c in await missingLocally()) {
        final dest = File('${repo.directory.path}/${c.id}.pdf');
        try {
          await repo.directory.create(recursive: true);
          await _cloud.download(c.id, dest);
          if (c.sha256.isNotEmpty && (await sha256.bind(dest.openRead()).first).toString() != c.sha256) {
            await dest.delete();
            problems.add('"${c.title}" arrived damaged');
            continue;
          }
          await repo.addDownloaded(id: c.id, title: c.title, author: c.author, pages: c.pageCount, size: c.sizeBytes, sha256: c.sha256);
          n++;
        } catch (e) {
          if (await dest.exists()) await dest.delete();
          problems.add('"${c.title}": $e');
        }
      }
    } catch (e) {
      problems.add('$e');
    }
    state = state.copyWith(message: [if (n > 0) 'Downloaded $n ${n == 1 ? 'book' : 'books'}.', if (problems.isNotEmpty) 'Problems: ${problems.join('; ')}'].join(' '));
    ref.invalidate(cloudOnlyCountProvider);
    return n;
  }
}

final bookSyncProvider = NotifierProvider<BookSyncController, BookSyncState>(BookSyncController.new);

/// How many cloud books are missing on this device (drives the "Download" banner).
final cloudOnlyCountProvider = FutureProvider.autoDispose<int>((ref) async {
  if (!ref.watch(canCloudSyncProvider)) return 0;
  try {
    return (await ref.read(bookSyncProvider.notifier).missingLocally()).length;
  } catch (_) {
    return 0;
  }
});
