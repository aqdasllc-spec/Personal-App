import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show Value;
import 'package:path/path.dart' as p;

import '../../data/local/app_database.dart';
import '../../data/sync/synced_store.dart';

class BackupException implements Exception {
  BackupException(this.message);
  final String message;
  @override
  String toString() => message;
}

class BackupInfo {
  const BackupInfo({required this.createdAt, required this.tasks, required this.events, required this.books, required this.shelves, required this.files, required this.sizeBytes});
  final DateTime createdAt;
  final int tasks, events, books, shelves, files, sizeBytes;
}

class RestoreResult {
  const RestoreResult({this.tasks = 0, this.events = 0, this.books = 0, this.shelves = 0, this.skipped = 0, this.problems = const []});
  final int tasks, events, books, shelves;

  /// Items already on this device (left untouched).
  final int skipped;

  /// Items that could not be restored, with the reason (e.g. a damaged PDF).
  final List<String> problems;
  int get added => tasks + events + books + shelves;
}

/// One-file backup of everything Folio keeps on this device: tasks, events, shelves, books and the PDFs.
///
/// Format: a zip with `manifest.json`, `data.json` and `files/<bookId>.pdf`. The file is NOT encrypted
/// (documented in the UI). Restore only ever ADDS what is missing; it never deletes or overwrites.
class BackupService {
  BackupService(this._db, this._store, {required this.libraryDir, DateTime Function()? now}) : _now = now ?? DateTime.now;

  static const format = 'folio-backup';
  static const version = 1;

  final AppDatabase _db;
  final SyncedStore _store;
  final Directory libraryDir;
  final DateTime Function() _now;

  /// What a backup would contain right now.
  Future<({int tasks, int events, int books})> summary() async {
    Future<int> n(Future<List<Object?>> f) async => (await f).length;
    return (
      tasks: await n((_db.select(_db.tasks)..where((t) => t.deletedAt.isNull())).get()),
      events: await n((_db.select(_db.events)..where((t) => t.deletedAt.isNull())).get()),
      books: await n((_db.select(_db.books)..where((b) => b.deletedAt.isNull())).get()),
    );
  }

  /// Writes a backup into [into] and returns the file.
  Future<File> create(Directory into) async {
    final now = _now();
    await into.create(recursive: true);
    String two(int n) => n.toString().padLeft(2, '0');
    final name = 'folio-backup-${now.year}${two(now.month)}${two(now.day)}-${two(now.hour)}${two(now.minute)}${two(now.second)}.folio';
    final out = File(p.join(into.path, name));
    final tmp = File('${out.path}.part');
    if (await tmp.exists()) await tmp.delete();

    final tasks = await (_db.select(_db.tasks)..where((t) => t.deletedAt.isNull())).get();
    final events = await (_db.select(_db.events)..where((t) => t.deletedAt.isNull())).get();
    final shelves = await _db.select(_db.shelves).get();
    final books = await (_db.select(_db.books)..where((b) => b.deletedAt.isNull())).get();
    final data = jsonEncode({
      'tasks': [for (final t in tasks) t.toJson()],
      'events': [for (final e in events) e.toJson()],
      'shelves': [for (final s in shelves) s.toJson()],
      'books': [for (final b in books) b.toJson()],
    });
    final present = <BookRow>[for (final b in books) if (await File(p.join(libraryDir.path, '${b.id}.pdf')).exists()) b];
    final manifest = jsonEncode({
      'format': format,
      'version': version,
      'schema': _db.schemaVersion,
      'createdAt': now.millisecondsSinceEpoch,
      'counts': {'tasks': tasks.length, 'events': events.length, 'shelves': shelves.length, 'books': books.length, 'files': present.length},
      'dataSha256': sha256.convert(utf8.encode(data)).toString(),
    });

    final enc = ZipFileEncoder();
    enc.create(tmp.path);
    try {
      enc.addArchiveFile(ArchiveFile.string('manifest.json', manifest));
      enc.addArchiveFile(ArchiveFile.string('data.json', data));
      for (final b in present) {
        await enc.addFile(File(p.join(libraryDir.path, '${b.id}.pdf')), 'files/${b.id}.pdf', ZipFileEncoder.store);
      }
    } finally {
      await enc.close();
    }
    if (await out.exists()) await out.delete();
    await tmp.rename(out.path);
    return out;
  }

  /// Reads and validates [path] without changing anything.
  Future<BackupInfo> inspect(String path) async {
    final (_, manifest, _) = await _open(path, needData: false);
    final c = (manifest['counts'] as Map?) ?? const {};
    return BackupInfo(
      createdAt: DateTime.fromMillisecondsSinceEpoch(manifest['createdAt'] as int),
      tasks: (c['tasks'] as int?) ?? 0,
      events: (c['events'] as int?) ?? 0,
      books: (c['books'] as int?) ?? 0,
      shelves: (c['shelves'] as int?) ?? 0,
      files: (c['files'] as int?) ?? 0,
      sizeBytes: await File(path).length(),
    );
  }

  Future<(Archive, Map<String, dynamic>, Map<String, dynamic>)> _open(String path, {required bool needData}) async {
    final f = File(path);
    if (!await f.exists()) throw BackupException('That file no longer exists.');
    Archive archive;
    try {
      archive = ZipDecoder().decodeStream(InputFileStream(path));
    } catch (_) {
      throw BackupException('This is not a Folio backup (or the file is damaged).');
    }
    ArchiveFile? find(String n) => archive.files.where((x) => x.name == n).firstOrNull;
    final m = find('manifest.json'), d = find('data.json');
    if (m == null || d == null) throw BackupException('This is not a Folio backup (or the file is damaged).');
    final Map<String, dynamic> manifest;
    final Map<String, dynamic> data;
    try {
      manifest = jsonDecode(utf8.decode(m.readBytes()!)) as Map<String, dynamic>;
      final raw = d.readBytes()!;
      if (manifest['format'] != format) throw const FormatException();
      if (sha256.convert(raw).toString() != manifest['dataSha256']) throw BackupException('The backup is damaged (checksum mismatch). Try the file again or an older backup.');
      data = jsonDecode(utf8.decode(raw)) as Map<String, dynamic>;
    } on BackupException {
      rethrow;
    } catch (_) {
      throw BackupException('This is not a Folio backup (or the file is damaged).');
    }
    if ((manifest['version'] as int? ?? 99) > version || (manifest['schema'] as int? ?? 99) > _db.schemaVersion) {
      throw BackupException('This backup was made by a newer version of Folio. Update the app first.');
    }
    return (archive, manifest, data);
  }

  /// Adds everything from the backup that is not already here. Nothing is deleted or overwritten.
  Future<RestoreResult> restore(String path) async {
    final (archive, _, data) = await _open(path, needData: true);
    var tasks = 0, events = 0, books = 0, shelves = 0, skipped = 0;
    final problems = <String>[];
    List<Map<String, dynamic>> list(String k) => [for (final x in (data[k] as List? ?? const [])) (x as Map).cast<String, dynamic>()];

    final haveShelf = {for (final s in await _db.select(_db.shelves).get()) s.id};
    for (final j in list('shelves')) {
      final s = ShelfRow.fromJson(j);
      if (haveShelf.contains(s.id)) {
        skipped++;
        continue;
      }
      await _db.into(_db.shelves).insert(s);
      haveShelf.add(s.id);
      shelves++;
    }

    final haveTask = {for (final t in await _db.select(_db.tasks).get()) t.id};
    for (final j in list('tasks')) {
      final t = TaskRow.fromJson(j);
      if (haveTask.contains(t.id)) {
        skipped++;
        continue;
      }
      await _store.setFields('tasks', t.id, {
        'title': t.title,
        'notes': t.notes,
        'priority': t.priority,
        'due_at': t.dueAt,
        'due_has_time': t.dueHasTime,
        'planned_at': t.plannedAt,
        'planned_minutes': t.plannedMinutes,
        'done_at': t.doneAt,
        'rrule': t.rrule,
        'remind_minutes': t.remindMinutes,
        'sort_key': t.sortKey,
      });
      await (_db.update(_db.tasks)..where((x) => x.id.equals(t.id))).write(TasksCompanion(createdAt: Value(t.createdAt)));
      tasks++;
    }

    final haveEvent = {for (final e in await _db.select(_db.events).get()) e.id};
    for (final j in list('events')) {
      final e = EventRow.fromJson(j);
      if (haveEvent.contains(e.id)) {
        skipped++;
        continue;
      }
      await _store.setFields('events', e.id, {
        'title': e.title,
        'notes': e.notes,
        'start_at': e.startAt,
        'end_at': e.endAt,
        'all_day': e.allDay,
        'rrule': e.rrule,
        'remind_minutes': e.remindMinutes,
        'color': e.color,
      });
      await (_db.update(_db.events)..where((x) => x.id.equals(e.id))).write(EventsCompanion(createdAt: Value(e.createdAt)));
      events++;
    }

    final existing = await _db.select(_db.books).get();
    final haveBook = {for (final b in existing) b.id};
    final haveHash = {for (final b in existing) if (b.deletedAt == null && b.sha256.isNotEmpty) b.sha256};
    await libraryDir.create(recursive: true);
    for (final j in list('books')) {
      final b = BookRow.fromJson({'cloudState': 'local', ...j}); // backups from before cloud sync lack the field
      if (haveBook.contains(b.id) || (b.sha256.isNotEmpty && haveHash.contains(b.sha256))) {
        skipped++;
        continue;
      }
      final entry = archive.files.where((x) => x.name == 'files/${b.id}.pdf').firstOrNull;
      if (entry == null) {
        problems.add('"${b.title}": its PDF is not in the backup');
        continue;
      }
      final dest = File(p.join(libraryDir.path, '${b.id}.pdf'));
      final out = OutputFileStream(dest.path);
      try {
        entry.writeContent(out);
      } finally {
        await out.close();
      }
      if (b.sha256.isNotEmpty && (await sha256.bind(dest.openRead()).first).toString() != b.sha256) {
        await dest.delete();
        problems.add('"${b.title}": the PDF in the backup is damaged');
        continue;
      }
      await _db.into(_db.books).insert(b.copyWith(shelfId: Value(haveShelf.contains(b.shelfId) ? b.shelfId : null), cloudState: 'local'));
      books++;
    }
    return RestoreResult(tasks: tasks, events: events, books: books, shelves: shelves, skipped: skipped, problems: problems);
  }
}
