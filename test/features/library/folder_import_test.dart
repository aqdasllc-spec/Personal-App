import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/features/library/data/folder_scan.dart';

import '../../helpers.dart';
import 'reader_settings_test.dart' show io;

Directory makeFolder() {
  final root = Directory.systemTemp.createTempSync('folder_import');
  File('${root.path}/a.pdf').writeAsStringSync('pages=3');
  File('${root.path}/Notes.TXT').writeAsStringSync('not a pdf');
  Directory('${root.path}/sub/deeper').createSync(recursive: true);
  File('${root.path}/sub/b.PDF').writeAsStringSync('pages=5');
  File('${root.path}/sub/deeper/c.pdf').writeAsStringSync('pages=7');
  Directory('${root.path}/.hidden').createSync();
  File('${root.path}/.hidden/secret.pdf').writeAsStringSync('pages=9');
  File('${root.path}/.dot.pdf').writeAsStringSync('pages=9');
  return root;
}

/// Real time passes while files are copied: wait (up to ~10 s) until [done] is true, then let the UI catch up.
Future<void> waitUntil(WidgetTester t, Future<bool> Function() done) async {
  for (var i = 0; i < 100; i++) {
    if (await t.runAsync(done) ?? false) break;
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
  }
  await io(t, rounds: 6);
}

void main() {
  group('scanPdfFolder', () {
    test('finds PDFs in sub-folders, ignores other files and hidden ones, sorted', () async {
      final root = makeFolder();
      addTearDown(() => root.deleteSync(recursive: true));
      final found = (await scanPdfFolder(root.path))!.map((p) => p.substring(root.path.length + 1)).toList();
      expect(found, ['a.pdf', 'sub/b.PDF', 'sub/deeper/c.pdf']);
    });

    test('the limit is respected; a missing folder is null, an empty one is empty', () async {
      final root = makeFolder();
      addTearDown(() => root.deleteSync(recursive: true));
      expect((await scanPdfFolder(root.path, limit: 2))!.length, 2);
      expect(await scanPdfFolder('${root.path}/nope'), isNull);
      final empty = Directory.systemTemp.createTempSync('empty_folder');
      addTearDown(() => empty.deleteSync(recursive: true));
      expect(await scanPdfFolder(empty.path), isEmpty);
    });
  });

  group('Library', () {
    Future<TestEnv> openLibrary(WidgetTester t) async {
      t.view.physicalSize = const Size(411, 890);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final env = await TestEnv.create();
      addTearDown(env.db.close);
      await t.pumpWidget(env.app);
      await io(t);
      await t.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Library')));
      await io(t);
      return env;
    }

    Future<void> endIt(WidgetTester t) async {
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 1));
    }

    testWidgets('pick a folder, confirm the count, every PDF is added once', (t) async {
      final root = makeFolder();
      addTearDown(() => root.deleteSync(recursive: true));
      final env = await openLibrary(t);
      env.pickedFolder = root.path;
      await t.tap(find.byKey(const Key('library-add-folder')));
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await io(t, rounds: 3);
      expect(find.textContaining('Found 3 PDF files'), findsOneWidget);
      await t.tap(find.byKey(const Key('folder-add-confirm')));
      await waitUntil(t, () async => (await env.db.select(env.db.books).get()).length == 3);
      expect(find.textContaining('Added 3 books'), findsOneWidget);
      final rows = (await t.runAsync(() => env.db.select(env.db.books).get()))!;
      expect(rows.map((b) => b.pageCount).toSet(), {3, 5, 7});

      // the same folder again: nothing new
      await t.tap(find.byKey(const Key('library-add-folder')));
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await io(t, rounds: 3);
      await t.tap(find.byKey(const Key('folder-add-confirm')));
      await waitUntil(t, () async => false); // nothing new to wait for: just give it time
      expect(find.textContaining('3 already in your library'), findsOneWidget);
      await endIt(t);
    });

    testWidgets('cancelling the picker, an unreadable folder and an empty folder each say what happened', (t) async {
      final env = await openLibrary(t);
      env.pickedFolder = null;
      await t.tap(find.byKey(const Key('library-add-folder')));
      await io(t, rounds: 3);
      expect(find.byType(AlertDialog), findsNothing);

      env.pickedFolder = '${Directory.systemTemp.path}/does-not-exist-${DateTime.now().microsecondsSinceEpoch}';
      await t.tap(find.byKey(const Key('library-add-folder')));
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await io(t, rounds: 3);
      expect(find.textContaining('Could not read that folder'), findsOneWidget);

      final empty = Directory.systemTemp.createTempSync('empty_import');
      addTearDown(() => empty.deleteSync(recursive: true));
      env.pickedFolder = empty.path;
      await t.tap(find.byKey(const Key('library-add-folder')));
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await io(t, rounds: 3);
      expect(find.textContaining('No PDF files in that folder'), findsOneWidget);
      await endIt(t);
    });
  });
}
