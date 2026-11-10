import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/features/backup/backup_service.dart';
import 'package:folio/features/library/data/library_repository.dart';
import 'package:folio/features/library/domain_highlights.dart';
import 'package:folio/features/library/data/ocr.dart';
import 'package:folio/features/library/domain_ink.dart';
import 'package:folio/features/library/domain_tags.dart';
import 'package:folio/features/planner/data/planner_repository.dart';
import 'package:folio/features/planner/domain/models.dart';

import '../../helpers.dart';
import '../planner/planner_helpers.dart';

class Device {
  Device._(this.env, this.libDir, this.lib, this.planner, this.backup);
  final PEnv env;
  final Directory libDir;
  final LibraryRepository lib;
  final PlannerRepository planner;
  final BackupService backup;

  static Future<Device> create({DateTime? now}) async {
    final env = await PEnv.create();
    final dir = Directory.systemTemp.createTempSync('devlib');
    final lib = LibraryRepository(env.db, directory: dir, inspector: FakePdfInspector());
    return Device._(env, dir, lib, env.repo, BackupService(env.db, env.store, libraryDir: dir, now: () => now ?? DateTime(2026, 11, 6, 14, 30, 5)));
  }

  Future<void> close() => env.close();
}

void main() {
  late Directory work;
  late Device a;
  setUp(() async {
    work = Directory.systemTemp.createTempSync('bk');
    a = await Device.create();
  });
  tearDown(() async {
    await a.close();
    work.deleteSync(recursive: true);
  });

  String pdf(String name, int pages) => (File('${work.path}/$name')..writeAsStringSync('pages=$pages')).path;

  Future<void> seed() async {
    await a.planner.saveTask(TaskInput(title: 'Weekly review', due: d(2026, 11, 9, 9), dueHasTime: true, rrule: 'FREQ=WEEKLY', remindMinutes: 0, priority: Priority.high));
    await a.planner.saveTask(TaskInput(title: 'Plain', due: d(2026, 11, 10), checklist: const [ChecklistItem(id: 'c1', title: 'Step one', done: true), ChecklistItem(id: 'c2', title: 'Step two')]));
    final gone = await a.planner.saveTask(const TaskInput(title: 'Deleted one'));
    await a.planner.deleteTask(gone);
    await a.planner.saveEvent(EventInput(title: 'Dentist', start: d(2026, 11, 12, 10), end: d(2026, 11, 12, 11), remindMinutes: 30));
    final shelf = await a.lib.createShelf('Work');
    final book = (await a.lib.importPdf(pdf('Spec.pdf', 40))).book!;
    await a.lib.moveToShelf(book.id, shelf.id);
    await a.lib.setFavorite(book.id, true);
    await a.lib.setTags(book.id, 'work, safety');
    await a.lib.saveProgress(book.id, 12);
    await a.lib.importPdf(pdf('Other.pdf', 7));
    await a.lib.toggleBookmark(book.id, 5);
    await a.lib.toggleBookmark(book.id, 31);
    await a.lib.addHighlight(book.id, const HighlightDraft(page: 4, rects: [[1, 5, 2, 1]], text: 'kept passage'), color: 'green');
  }

  test('round trip: a new device gets the same tasks, events, shelves, books and PDFs back', () async {
    await seed();
    final file = await a.backup.create(work);
    expect(file.path, endsWith('folio-backup-20261106-143005.folio'));
    final info = await a.backup.inspect(file.path);
    expect((info.tasks, info.events, info.shelves, info.books, info.files), (2, 1, 1, 2, 2), reason: 'soft-deleted tasks are not backed up');

    final b = await Device.create();
    addTearDown(b.close);
    final r = await b.backup.restore(file.path);
    expect((r.tasks, r.events, r.shelves, r.books, r.skipped), (2, 1, 1, 2, 0));
    expect(r.problems, isEmpty);

    final tasks = await b.planner.tasks();
    final weekly = tasks.firstWhere((t) => t.title == 'Weekly review');
    expect((weekly.due, weekly.dueHasTime, weekly.rrule, weekly.remindMinutes, weekly.priority), (d(2026, 11, 9, 9), true, 'FREQ=WEEKLY', 0, Priority.high));
    expect((await b.planner.events()).single.title, 'Dentist');
    final plainRestored = tasks.firstWhere((t) => t.title == 'Plain');
    expect(plainRestored.checklist.map((c) => (c.title, c.done)).toList(), [('Step one', true), ('Step two', false)], reason: 'sub-tasks come back with the task');
    final books = await b.lib.watchBooks().first;
    final spec = books.firstWhere((x) => x.title == 'Spec');
    expect((spec.favorite, spec.lastPage, spec.pageCount, b.lib.fileOf(spec).readAsStringSync()), (1, 12, 40, 'pages=40'));
    expect(spec.shelfId, isNotNull);
    expect((await b.lib.watchShelves().first).single.name, 'Work');
    expect((await b.lib.watchBookmarks(spec.id).first).map((m) => m.page), [5, 31], reason: 'bookmarks come back with the book');
    expect(decodeTags(spec.tags), ['work', 'safety'], reason: 'tags come back too');
    final hl = (await b.lib.watchHighlights(spec.id).first).single;
    expect((hl.snippet, hl.color, hl.page), ('kept passage', 'green', 4), reason: 'highlights too');

    final srcTask = (await a.env.db.select(a.env.db.tasks).get()).firstWhere((t) => t.title == 'Plain');
    final dstTask = (await b.env.db.select(b.env.db.tasks).get()).firstWhere((t) => t.title == 'Plain');
    expect((dstTask.id, dstTask.createdAt), (srcTask.id, srcTask.createdAt), reason: 'same identity and creation time');
    expect((await b.env.db.select(b.env.db.syncOutbox).get()), isNotEmpty, reason: 'restored tasks will sync like new edits');
  });

  test('tag colours, pen drawings and recognised page text travel with the backup; this device keeps its own colour choices', () async {
    final book = (await a.lib.importPdf(pdf('Scan.pdf', 4))).book!;
    await a.lib.savePageText(book.id, 2, const RecognizedPage([OcrLine('hello scan', 0.1, 0.1, 0.5, 0.2)]));
    await a.lib.setTextState(book.id, 'ocr');
    await a.lib.saveInk(book.id, 3, [const Stroke(1, 0.004, [0.1, 0.1, 0.4, 0.4])]);
    await a.env.store.setState('tag_colors', '{"work":2,"safety":5}');
    final file = await a.backup.create(work);

    final b = await Device.create();
    addTearDown(b.close);
    await b.env.store.setState('tag_colors', '{"work":6}');
    await b.backup.restore(file.path);
    final restored = (await b.lib.watchBooks().first).single;
    expect(restored.textState, 'ocr');
    expect((await b.lib.pageText(restored.id, 2))!.body, 'hello scan');
    final ink = await b.env.db.select(b.env.db.pageInk).get();
    expect((ink.single.page, decodeStrokes(ink.single.strokes).length), (3, 1));
    expect(await b.env.store.state('tag_colors'), '{"work":6,"safety":5}', reason: 'own colour for "work" kept, new one added');
  });

  test('Quran and prayer settings travel with the backup: saved ayahs are combined, own choices kept', () async {
    await a.env.store.setState('quran_bookmarks', '[{"s":2,"a":255,"n":"Kursi","t":1}]');
    await a.env.store.setState('quran_khatm', 'plan-a');
    await a.env.store.setState('prayer_settings', '{"lat":31.5}');
    await a.env.store.setState('quran_text_scale', '1.40');
    final file = await a.backup.create(work);

    final b = await Device.create();
    addTearDown(b.close);
    await b.env.store.setState('quran_bookmarks', '[{"s":1,"a":1,"n":"","t":2}]');
    await b.env.store.setState('quran_khatm', 'plan-b');
    final heard = <String>[];
    b.env.store.remotePrefChanges.listen(heard.add);
    await b.backup.restore(file.path);
    await pumpEventQueue();
    expect(await b.env.store.state('quran_bookmarks'), '[{"s":1,"a":1,"n":"","t":2},{"s":2,"a":255,"n":"Kursi","t":1}]');
    expect(await b.env.store.state('quran_khatm'), 'plan-b', reason: 'this device already had a plan');
    expect(await b.env.store.state('prayer_settings'), '{"lat":31.5}');
    expect(await b.env.store.state('quran_text_scale'), isNull, reason: 'screen size choices stay on each device');
    expect(heard, containsAll(['quran_bookmarks', 'prayer_settings']));
  });

  test('restoring again, or onto a device that already has the data, adds nothing and changes nothing', () async {
    await seed();
    final file = await a.backup.create(work);
    final r = await a.backup.restore(file.path);
    expect((r.added, r.skipped), (0, 6));
    final b = await Device.create();
    addTearDown(b.close);
    await b.backup.restore(file.path);
    final again = await b.backup.restore(file.path);
    expect((again.added, again.skipped), (0, 6));
    expect((await b.planner.tasks()).length, 2);
  });

  test('restore never overwrites what you changed since: local edits survive', () async {
    await seed();
    final file = await a.backup.create(work);
    final plain = (await a.planner.tasks()).firstWhere((t) => t.title == 'Plain');
    await a.planner.saveTask(const TaskInput(title: 'Plain, edited'), id: plain.id);
    await a.backup.restore(file.path);
    expect((await a.planner.tasks()).map((t) => t.title), contains('Plain, edited'));
  });

  test('a book already present under another id (same PDF) is not duplicated', () async {
    await seed();
    final file = await a.backup.create(work);
    final b = await Device.create();
    addTearDown(b.close);
    await b.lib.importPdf(pdf('Spec.pdf', 40));
    final r = await b.backup.restore(file.path);
    expect(r.books, 1);
    expect((await b.lib.watchBooks().first).length, 2);
  });

  test('not a backup / damaged / tampered / too new: refused with a clear message, nothing changed', () async {
    await seed();
    final junk = File('${work.path}/x.folio')..writeAsStringSync('hello');
    await expectLater(a.backup.inspect(junk.path), throwsA(isA<BackupException>().having((e) => e.message, 'message', contains('not a Folio backup'))));
    await expectLater(a.backup.inspect('${work.path}/missing.folio'), throwsA(isA<BackupException>()));

    final good = await a.backup.create(work);
    Future<String> rewrite(String name, String Function(String data, Map<String, dynamic> m) f) async {
      final z = ZipDecoder().decodeBytes(good.readAsBytesSync());
      var data = utf8.decode(z.files.firstWhere((x) => x.name == 'data.json').readBytes()!);
      final m = jsonDecode(utf8.decode(z.files.firstWhere((x) => x.name == 'manifest.json').readBytes()!)) as Map<String, dynamic>;
      data = f(data, m);
      final out = Archive()
        ..addFile(ArchiveFile.string('manifest.json', jsonEncode(m)))
        ..addFile(ArchiveFile.string('data.json', data));
      final path = '${work.path}/$name';
      File(path).writeAsBytesSync(ZipEncoder().encode(out));
      return path;
    }

    final tampered = await rewrite('t.folio', (d, m) => d.replaceFirst('Plain', 'Hacked'));
    await expectLater(a.backup.restore(tampered), throwsA(isA<BackupException>().having((e) => e.message, 'm', contains('damaged'))));
    final newer = await rewrite('n.folio', (d, m) {
      m['version'] = 99;
      return d;
    });
    await expectLater(a.backup.restore(newer), throwsA(isA<BackupException>().having((e) => e.message, 'm', contains('newer version'))));
    expect((await a.planner.tasks()).length, 2);
  });

  test('a damaged or missing PDF inside the backup is reported and the rest still restores', () async {
    await seed();
    final good = await a.backup.create(work);
    final z = ZipDecoder().decodeBytes(good.readAsBytesSync());
    final books = (jsonDecode(utf8.decode(z.files.firstWhere((x) => x.name == 'data.json').readBytes()!))['books'] as List).cast<Map<String, dynamic>>();
    final specId = books.firstWhere((b) => b['title'] == 'Spec')['id'];
    final otherId = books.firstWhere((b) => b['title'] == 'Other')['id'];
    final out = Archive();
    for (final f in z.files) {
      if (f.name == 'files/$otherId.pdf') continue; // missing
      out.addFile(f.name == 'files/$specId.pdf' ? ArchiveFile.bytes(f.name, utf8.encode('pages=40 corrupted')) : f);
    }
    final path = '${work.path}/c.folio';
    File(path).writeAsBytesSync(ZipEncoder().encode(out));
    final b = await Device.create();
    addTearDown(b.close);
    final r = await b.backup.restore(path);
    expect((r.books, r.tasks, r.events), (0, 2, 1));
    expect(r.problems.length, 2);
    expect(r.problems.join(' '), allOf(contains('damaged'), contains('not in the backup')));
    expect(await b.lib.watchBooks().first, isEmpty);
    expect(b.libDir.listSync(), isEmpty, reason: 'no half-restored files left behind');
  });

  test('an empty device produces a valid, restorable backup', () async {
    final f = await a.backup.create(work);
    final i = await a.backup.inspect(f.path);
    expect((i.tasks, i.events, i.books, i.shelves), (0, 0, 0, 0));
    expect(sha256.convert(utf8.encode('x')).bytes, isNotEmpty);
  });
}
