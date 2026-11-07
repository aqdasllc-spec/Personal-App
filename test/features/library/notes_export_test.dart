import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/app/app.dart';
import 'package:folio/data/local/app_database.dart';
import 'package:folio/features/backup/backup_controller.dart';
import 'package:folio/features/library/application/export_notes.dart';
import 'package:folio/features/library/data/highlights_export.dart';
import 'package:folio/features/library/data/library_repository.dart';
import 'package:folio/features/library/domain_highlights.dart';

import '../../helpers.dart';

HighlightRow hl(int page, String text, {String note = '', String color = 'yellow', int at = 0}) => HighlightRow(id: 'h$page$at', bookId: 'b', page: page, rects: '[]', snippet: text, color: color, note: note, createdAt: at);

void main() {
  group('markdown', () {
    test('title, facts, highlights grouped by page in order, notes, bookmarks', () {
      final md = buildNotesMarkdown(
        title: ' Deep Work ',
        author: 'Cal Newport',
        highlights: [
          hl(12, 'Second on page 12', at: 2, color: 'blue'),
          hl(3, 'Clarity about what matters\nprovides clarity about what does not.', note: 'Remember this\nfor the review', color: 'green'),
          hl(12, 'First on page 12', at: 1),
          hl(40, '', note: 'no text but a note', color: 'pink'),
        ],
        bookmarkPages: [40, 5, 5],
        exportedAt: DateTime(2026, 11, 7),
      );
      expect(md, '''# Deep Work

_Cal Newport · 4 highlights · 2 bookmarks · exported 7 Nov 2026_

## Page 3

🟢
> Clarity about what matters
> provides clarity about what does not.

**Note:** Remember this
for the review

## Page 12

🟡
> First on page 12

🔵
> Second on page 12

## Page 40

🟣 _(no text)_

**Note:** no text but a note

## Bookmarks

- Page 5
- Page 40
''');
    });

    test('no author / one highlight / no bookmarks / untitled read naturally', () {
      final md = buildNotesMarkdown(title: '  ', author: '', highlights: [hl(1, 'x')], bookmarkPages: const [], exportedAt: DateTime(2026, 1, 2));
      expect(md.startsWith('# Untitled\n\n_1 highlight · exported 2 Jan 2026_\n'), isTrue);
      expect(md.contains('Bookmarks'), isFalse);
    });

    test('only bookmarks still exports', () {
      final md = buildNotesMarkdown(title: 'T', author: 'A', highlights: const [], bookmarkPages: [7], exportedAt: DateTime(2026, 5, 5));
      expect(md, contains('0 highlights · 1 bookmark ·'));
      expect(md, contains('- Page 7'));
    });

    test('file names are safe and never empty', () {
      expect(safeFileName('JSP for SS No.14: Testing & Commissioning (1)'), 'JSP for SS No14 Testing Commissioning 1-notes.md');
      expect(safeFileName('../../etc/passwd'), 'etcpasswd-notes.md');
      expect(safeFileName('???'), 'book-notes.md');
      expect(safeFileName('x' * 200).length, lessThanOrEqualTo(60 + '-notes.md'.length));
    });
  });

  group('sharing from the app', () {
    late Directory tmp;
    final shared = <(String, String)>[]; // (file content, subject)
    String? copied;

    Future<(TestEnv, BookRow)> open(WidgetTester t, {bool withNotes = true}) async {
      t.view.physicalSize = const Size(411, 890);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      shared.clear();
      copied = null;
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String?;
        return null;
      });
      addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      final env = await TestEnv.create();
      addTearDown(env.db.close);
      late BookRow b;
      await t.runAsync(() async {
        tmp = Directory.systemTemp.createTempSync('notes');
        final repo = LibraryRepository(env.db, directory: env.libraryDir, inspector: FakePdfInspector());
        b = (await repo.importPdf(await env.writePdf('x.pdf', 50))).book!;
        await repo.updateDetails(b.id, title: 'Deep Work', author: 'Cal Newport');
        if (withNotes) {
          final id = await repo.addHighlight(b.id, const HighlightDraft(page: 3, rects: [], text: 'Clarity matters'), color: 'green');
          await repo.setHighlightNote(id, 'for the review');
          await repo.toggleBookmark(b.id, 9);
        }
      });
      await t.pumpWidget(ProviderScope(
        overrides: [
          ...env.overrides,
          backupTempDirProvider.overrideWithValue(() async => tmp),
          shareFileProvider.overrideWithValue((file, subject) async {
            shared.add((file.readAsStringSync(), subject));
            return true;
          }),
        ],
        child: const FolioApp(),
      ));
      await io(t);
      await t.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Library')));
      await io(t);
      return (env, b);
    }

    testWidgets('reader: the notes sheet has Copy and Share for the whole book', (t) async {
      final (_, b) = await open(t);
      await t.tap(find.byKey(Key('book-${b.id}')));
      await io(t);
      await t.tap(find.byKey(const Key('reader-bookmarks')));
      await io(t);
      await t.tap(find.byKey(const Key('export-copy')));
      await io(t);
      expect(copied, contains('# Deep Work'));
      expect(copied, contains('> Clarity matters'));
      expect(copied, contains('**Note:** for the review'));
      expect(copied, contains('- Page 9'));
      expect(find.text('Copied 1 highlight to the clipboard.'), findsOneWidget);

      await t.tap(find.byKey(const Key('export-share')));
      await io(t);
      expect(shared.length, 1);
      expect(shared.single.$2, 'Deep Work - notes');
      expect(shared.single.$1, copied, reason: 'the same text goes into the shared .md file');
      expect(File('${tmp.path}/Deep Work-notes.md').existsSync(), isTrue);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 1));
    });

    testWidgets('reader: with no highlights or bookmarks there is nothing to export (no buttons)', (t) async {
      final (_, b) = await open(t, withNotes: false);
      await t.tap(find.byKey(Key('book-${b.id}')));
      await io(t);
      await t.tap(find.byKey(const Key('reader-bookmarks')));
      await io(t);
      expect(find.byKey(const Key('export-share')), findsNothing);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 1));
    });

    testWidgets('book menu: Share notes works from the Library; an empty book says there is nothing yet', (t) async {
      final (env, b) = await open(t);
      await t.longPress(find.byKey(Key('book-${b.id}')));
      await io(t);
      await t.tap(find.byKey(const Key('peek-more')));
      await io(t);
      await t.tap(find.byKey(const Key('book-export')));
      await io(t);
      expect(shared.single.$1, contains('## Page 3'));
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 1));
      expect(env.db, isNotNull);
    });

    testWidgets('book menu: nothing to export is explained, nothing is shared', (t) async {
      final (_, b) = await open(t, withNotes: false);
      await t.longPress(find.byKey(Key('book-${b.id}')));
      await io(t);
      await t.tap(find.byKey(const Key('peek-more')));
      await io(t);
      await t.tap(find.byKey(const Key('book-export')));
      await io(t);
      expect(find.textContaining('Nothing to export yet'), findsOneWidget);
      expect(shared, isEmpty);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 1));
    });
  });
}

Future<void> io(WidgetTester t, {int rounds = 6}) async {
  for (var i = 0; i < rounds; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    for (var k = 0; k < 3; k++) {
      await t.pump(const Duration(milliseconds: 60));
    }
  }
  await t.pump(const Duration(milliseconds: 300));
}
