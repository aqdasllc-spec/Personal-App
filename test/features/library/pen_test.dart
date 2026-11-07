import 'dart:ui';


import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/data/local/app_database.dart';
import 'package:folio/features/library/data/library_repository.dart';
import 'package:folio/features/library/data/pdf_inspector.dart' show InkCapture, paintStroke;
import 'package:folio/features/library/application/library_controller.dart';
import 'package:folio/features/library/domain_ink.dart';

import '../../helpers.dart';
import 'reader_settings_test.dart' show io;

Future<(TestEnv, BookRow)> openBook(WidgetTester t, {Future<void> Function(LibraryRepository, BookRow)? seed}) async {
  t.view.physicalSize = const Size(411, 890);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final env = await TestEnv.create();
  addTearDown(env.db.close);
  late BookRow b;
  await t.runAsync(() async {
    final repo = LibraryRepository(env.db, directory: env.libraryDir, inspector: FakePdfInspector());
    b = (await repo.importPdf(await env.writePdf('x.pdf', 5))).book!;
    if (seed != null) await seed(repo, b);
  });
  await t.pumpWidget(env.app);
  await io(t);
  await t.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Library')));
  await io(t);
  await t.tap(find.byKey(Key('book-${b.id}')));
  await io(t);
  return (env, b);
}

Future<List<PageInkRow>> inkRows(WidgetTester t, TestEnv env) async => (await t.runAsync(() => env.db.select(env.db.pageInk).get()))!;

Future<void> startPen(WidgetTester t) async {
  await t.tap(find.byKey(const Key('reader-pen')));
  await io(t, rounds: 2);
}

void padTest(String name, Future<void> Function(WidgetTester) body) => testWidgets(name, (t) async {
  await body(t);
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 1));
});

void main() {
  group('domain', () {
    test('strokes round trip; bad data is skipped, never an error', () {
      final s = [const Stroke(2, 0.004, [0.1, 0.2, 0.3, 0.4])];
      final back = decodeStrokes(encodeStrokes(s));
      expect(back.length, 1);
      expect((back[0].color, back[0].width), (2, 0.004));
      expect(back[0].points, [0.1, 0.2, 0.3, 0.4]);
      expect(decodeStrokes('nonsense'), isEmpty);
      expect(decodeStrokes('[{"c":99,"w":0.004,"p":[0,0]},{"c":1,"w":0.004,"p":[0,0,1]},{"c":1,"w":0.004,"p":[0.5,2]}]').map((x) => x.points), [
        [0.5, 1.0],
      ], reason: 'bad colour and odd point count dropped; coordinates clamped');
    });

    test('a highlighter stroke keeps its kind through storage; ordinary strokes do not carry the flag', () {
      final back = decodeStrokes(encodeStrokes([const Stroke(3, 0.02, [0, 0, 1, 1], highlighter: true), const Stroke(1, 0.004, [0, 0, 1, 1])]));
      expect(back.map((s) => s.highlighter), [true, false]);
      expect(encodeStrokes([const Stroke(1, 0.004, [0, 0, 1, 1])]).contains('"h"'), isFalse);
    });

    test('erasing: touching a stroke removes it, far away leaves it; dots can be erased too', () {
      const line = Stroke(0, 0.004, [0.1, 0.1, 0.5, 0.5]);
      const dot = Stroke(1, 0.004, [0.8, 0.8]);
      expect(strokeTouches(line, 0.3, 0.3), isTrue);
      expect(strokeTouches(line, 0.3, 0.32), isTrue, reason: 'close counts');
      expect(strokeTouches(line, 0.9, 0.1), isFalse);
      expect(strokeTouches(line, 0.6, 0.6), isFalse, reason: 'beyond the end of the line');
      expect(eraseAt([line, dot], 0.3, 0.3), [dot]);
      expect(eraseAt([line, dot], 0.8, 0.8), [line]);
      expect(eraseAt([line, dot], 0.0, 0.9), [line, dot]);
    });

    test('simplify drops points that are too close but keeps the ends', () {
      final pts = <double>[0, 0, 0.0001, 0, 0.0002, 0, 0.5, 0.5, 0.5001, 0.5, 1, 1];
      final out = simplify(pts);
      expect(out.take(2), [0, 0]);
      expect(out.skip(out.length - 2), [1, 1]);
      expect(out.length, lessThan(pts.length));
      expect(simplify([0.1, 0.1]), [0.1, 0.1]);
    });
  });

  group('repository', () {
    test('saving replaces, empty removes, book erase removes', () async {
      final env = await TestEnv.create();
      addTearDown(env.db.close);
      final repo = LibraryRepository(env.db, directory: env.libraryDir, inspector: FakePdfInspector());
      final b = (await repo.importPdf(await env.writePdf('a.pdf', 3))).book!;
      await repo.saveInk(b.id, 2, [const Stroke(0, 0.004, [0, 0, 1, 1])]);
      await repo.saveInk(b.id, 2, [const Stroke(0, 0.004, [0, 0, 1, 1]), const Stroke(1, 0.002, [0.2, 0.2])]);
      var rows = await env.db.select(env.db.pageInk).get();
      expect(rows.length, 1);
      expect(decodeStrokes(rows.single.strokes).length, 2);
      await repo.saveInk(b.id, 3, [const Stroke(0, 0.004, [0, 0])]);
      await repo.saveInk(b.id, 2, const []);
      rows = await env.db.select(env.db.pageInk).get();
      expect(rows.map((r) => r.page), [3]);
      await repo.remove(b.id);
      await repo.deletePermanently(b.id);
      expect(await env.db.select(env.db.pageInk).get(), isEmpty);
    });
  });

  group('painting and capture', () {
    testWidgets('a drag becomes one stroke in page fractions; a tap becomes a dot', (t) async {
      final got = <Stroke>[];
      await t.pumpWidget(MaterialApp(
        home: Center(
          child: SizedBox(width: 200, height: 400, child: InkCapture(pen: const PenState(on: true, color: 2, width: 2), onStroke: got.add)),
        ),
      ));
      final g = await t.startGesture(t.getTopLeft(find.byKey(const Key('ink-capture'))) + const Offset(20, 40));
      await g.moveBy(const Offset(60, 0));
      await g.moveBy(const Offset(60, 120));
      await g.up();
      await t.pump();
      expect(got.length, 1);
      expect((got[0].color, got[0].width), (2, penWidths[2].$2));
      expect(got[0].points.first, inInclusiveRange(0.1, 0.4)); // starts left of the end
      expect(got[0].points[got[0].points.length - 2], closeTo(0.7, 0.05)); // x: 140 / 200
      expect(got[0].points.last, closeTo(0.4, 0.05)); // y: 160 / 400
    }, skip: false);

    testWidgets('with the highlighter on, a drag becomes a wide highlighter stroke', (t) async {
      final got = <Stroke>[];
      await t.pumpWidget(MaterialApp(
        home: Center(child: SizedBox(width: 200, height: 400, child: InkCapture(pen: const PenState(on: true, width: 1, highlighter: true), onStroke: got.add))),
      ));
      final g = await t.startGesture(t.getTopLeft(find.byKey(const Key('ink-capture'))) + const Offset(20, 20));
      await g.moveBy(const Offset(80, 0));
      await g.up();
      await t.pump();
      expect(got.single.highlighter, isTrue);
      expect(got.single.width, penWidths[1].$2 * highlighterScale);
    });

    testWidgets('two fingers are a zoom, not a stroke: nothing is drawn, and the next single finger draws again', (t) async {
      final got = <Stroke>[];
      await t.pumpWidget(MaterialApp(
        home: Center(child: SizedBox(width: 200, height: 400, child: InkCapture(pen: const PenState(on: true), onStroke: got.add))),
      ));
      final origin = t.getTopLeft(find.byKey(const Key('ink-capture')));
      final a = await t.startGesture(origin + const Offset(40, 40), pointer: 1);
      await a.moveBy(const Offset(10, 10)); // already drawing...
      final b = await t.startGesture(origin + const Offset(120, 200), pointer: 2); // ...the second finger lands
      await a.moveBy(const Offset(30, 30));
      await b.moveBy(const Offset(-30, -30));
      await a.up();
      await b.up();
      await t.pump();
      expect(got, isEmpty);
      final c = await t.startGesture(origin + const Offset(20, 20), pointer: 3);
      await c.moveBy(const Offset(50, 50));
      await c.up();
      await t.pump();
      expect(got.length, 1);
    });

    testWidgets('stylus only: fingers never draw, the stylus does', (t) async {
      final got = <Stroke>[];
      await t.pumpWidget(MaterialApp(
        home: Center(child: SizedBox(width: 200, height: 400, child: InkCapture(pen: const PenState(on: true, stylusOnly: true), onStroke: got.add))),
      ));
      final origin = t.getTopLeft(find.byKey(const Key('ink-capture')));
      final finger = await t.startGesture(origin + const Offset(20, 20), pointer: 1);
      await finger.moveBy(const Offset(80, 80));
      await finger.up();
      await t.pump();
      expect(got, isEmpty);
      final pen = await t.startGesture(origin + const Offset(30, 30), pointer: 2, kind: PointerDeviceKind.stylus);
      await pen.moveBy(const Offset(60, 60));
      await pen.up();
      await t.pump();
      expect(got.length, 1);
    });

    testWidgets('a stylus wins over a resting palm', (t) async {
      final got = <Stroke>[];
      await t.pumpWidget(MaterialApp(
        home: Center(child: SizedBox(width: 200, height: 400, child: InkCapture(pen: const PenState(on: true), onStroke: got.add))),
      ));
      final origin = t.getTopLeft(find.byKey(const Key('ink-capture')));
      final pen = await t.startGesture(origin + const Offset(40, 40), pointer: 1, kind: PointerDeviceKind.stylus);
      final palm = await t.startGesture(origin + const Offset(150, 300), pointer: 2); // a finger touch while the pen is down
      await palm.moveBy(const Offset(10, 10));
      await pen.moveBy(const Offset(60, 60));
      await pen.up();
      await palm.up();
      await t.pump();
      expect(got.length, 1, reason: 'only the stylus drew');
      expect(got.single.points.length, greaterThanOrEqualTo(4));
      expect(got.single.points.last, lessThan(0.5), reason: 'the line is the stylus line (top left), not the palm (bottom right)');
    });

    test('paintStroke draws without error for a dot and a line', () {
      final rec = PictureRecorder();
      final c = Canvas(rec);
      paintStroke(c, const Rect.fromLTWH(0, 0, 100, 200), const Stroke(0, 0.004, [0.5, 0.5]));
      paintStroke(c, const Rect.fromLTWH(0, 0, 100, 200), const Stroke(1, 0.008, [0, 0, 1, 1, 0.5, 0.2]));
      rec.endRecording();
    });
  });

  group('reader', () {
    padTest('pen button shows the tools; a stroke is saved; undo and clear remove it; Done hides the bar', (t) async {
      final (env, _) = await openBook(t);
      expect(find.byKey(const Key('pen-bar')), findsNothing);
      await startPen(t);
      expect(find.byKey(const Key('pen-bar')), findsOneWidget);
      expect(find.text('pen on'), findsOneWidget);

      await t.tap(find.byKey(const Key('pen-style')));
      await io(t, rounds: 2);
      await t.tap(find.byKey(const Key('pen-color-2')));
      await io(t, rounds: 2);
      await t.tap(find.byKey(const Key('pen-style')));
      await io(t, rounds: 2);
      await t.tap(find.byKey(const Key('pen-width-2')));
      await io(t, rounds: 2);
      await t.tap(find.text('draw stroke'));
      await io(t, rounds: 4);
      var rows = await inkRows(t, env);
      expect(rows.single.page, 2);
      final s = decodeStrokes(rows.single.strokes).single;
      expect((s.color, s.width), (2, penWidths[2].$2));
      expect(find.text('ink {2: 1}'), findsOneWidget);

      await t.tap(find.text('draw stroke'));
      await io(t, rounds: 4);
      expect(find.text('ink {2: 2}'), findsOneWidget);
      await t.tap(find.byKey(const Key('pen-undo')));
      await io(t, rounds: 4);
      expect(find.text('ink {2: 1}'), findsOneWidget);
      expect(decodeStrokes((await inkRows(t, env)).single.strokes).length, 1);

      await t.tap(find.byKey(const Key('pen-done')));
      await io(t, rounds: 2);
      expect(find.byKey(const Key('pen-bar')), findsNothing);
      expect(find.text('pen off'), findsOneWidget);
    });

    padTest('eraser: rubbing on a stroke removes only that stroke, elsewhere does nothing, Undo brings it back', (t) async {
      final (env, _) = await openBook(t);
      await startPen(t);
      await t.tap(find.text('draw stroke'));
      await io(t, rounds: 3);
      await t.tap(find.text('draw stroke'));
      await io(t, rounds: 3);
      expect(find.text('ink {2: 2}'), findsOneWidget);
      await t.tap(find.byKey(const Key('pen-eraser')));
      await io(t, rounds: 2);
      await t.tap(find.text('rub elsewhere'));
      await io(t, rounds: 3);
      expect(find.text('ink {2: 2}'), findsOneWidget);
      await t.tap(find.text('rub on stroke'));
      await io(t, rounds: 4);
      expect(await inkRows(t, env), isEmpty, reason: 'both strokes were on the same line');
      await t.tap(find.byKey(const Key('pen-undo')));
      await io(t, rounds: 4);
      expect(decodeStrokes((await inkRows(t, env)).single.strokes).length, 2);
    });

    padTest('highlighter: chosen in the style pop-up, strokes it draws are marked as highlighter', (t) async {
      final (env, _) = await openBook(t);
      await startPen(t);
      await t.tap(find.byKey(const Key('pen-style')));
      await io(t, rounds: 2);
      await t.tap(find.byKey(const Key('pen-tool-highlighter')));
      await io(t, rounds: 2);
      await t.tap(find.text('draw stroke'));
      await io(t, rounds: 4);
      final s = decodeStrokes((await inkRows(t, env)).single.strokes).single;
      expect(s.highlighter, isTrue);
      expect(s.width, greaterThan(0.015));
    });

    padTest('stylus only is chosen in the style pop-up and remembered', (t) async {
      final (env, _) = await openBook(t);
      await startPen(t);
      await t.tap(find.byKey(const Key('pen-style')));
      await io(t, rounds: 2);
      await t.tap(find.byKey(const Key('pen-stylus-only')));
      await io(t, rounds: 3);
      expect(await t.runAsync(() => env.store.state('pen_stylus_only')), '1');
      await t.tap(find.byKey(const Key('pen-style')));
      await io(t, rounds: 2);
      expect(t.widget<FilterChip>(find.byKey(const Key('pen-stylus-only'))).selected, isTrue);
    });

    padTest('Clear removes the drawings of the page you are on', (t) async {
      final (env, _) = await openBook(
        t,
        seed: (repo, b) => repo.saveInk(b.id, 1, [const Stroke(0, 0.004, [0.1, 0.1, 0.2, 0.2])]),
      );
      expect(find.text('ink {1: 1}'), findsOneWidget, reason: 'saved drawings reach the page');
      await startPen(t);
      await t.tap(find.byKey(const Key('pen-clear')));
      await io(t, rounds: 4);
      expect(await inkRows(t, env), isEmpty);
    });

    padTest('drawings come back when the book is reopened', (t) async {
      await openBook(
        t,
        seed: (repo, b) => repo.saveInk(b.id, 4, [const Stroke(3, 0.002, [0.3, 0.3, 0.6, 0.6])]),
      );
      expect(find.text('ink {4: 1}'), findsOneWidget);
    });
  });
}
