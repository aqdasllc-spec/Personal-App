import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/app/app.dart';
import 'package:folio/features/backup/backup_controller.dart';
import 'package:folio/features/library/data/library_repository.dart';
import 'package:folio/features/planner/data/planner_repository.dart';
import 'package:folio/features/settings/backup_tiles.dart';

import '../../helpers.dart';

Future<void> settleB(WidgetTester t) async {
  for (var i = 0; i < 300; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 15)));
    for (var k = 0; k < 3; k++) {
      await t.pump(const Duration(milliseconds: 40));
    }
    if (i > 3 && find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
  }
  await t.pumpAndSettle();
}

Future<void> end(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 1));
}

class Fakes {
  final shared = <File>[];
  bool dismiss = false;
  String? picked;
}

Future<(TestEnv, Fakes)> open(WidgetTester t, {Future<void> Function(TestEnv)? seed, String start = 'Settings'}) async {
  t.view.physicalSize = const Size(411, 890);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final env = await TestEnv.create();
  addTearDown(env.db.close);
  final f = Fakes();
  final tmp = Directory.systemTemp.createTempSync('bkout');
  if (seed != null) await t.runAsync(() => seed(env));
  await t.pumpWidget(ProviderScope(
    overrides: [
      ...env.overrides,
      backupTempDirProvider.overrideWithValue(() async => tmp),
      backupSharerProvider.overrideWithValue((file) async {
        f.shared.add(file);
        return !f.dismiss;
      }),
      backupPickerProvider.overrideWithValue(() async => f.picked),
    ],
    child: const FolioApp(),
  ));
  await settleB(t);
  await t.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text(start)));
  await settleB(t);
  return (env, f);
}

Future<void> seedData(TestEnv env) async {
  final repo = PlannerRepository(env.store);
  await repo.saveTask(const TaskInput(title: 'Pay rent'));
  final lib = LibraryRepository(env.db, directory: env.libraryDir, inspector: FakePdfInspector());
  await lib.importPdf(await env.writePdf('Alpha.pdf', 12));
}

Future<void> scrollTo(WidgetTester t, Key k) async {
  await t.scrollUntilVisible(find.byKey(k), 300, scrollable: find.byType(Scrollable).first);
  await t.ensureVisible(find.byKey(k));
  await t.pump();
}

void main() {
  test('backup age wording', () {
    final now = DateTime(2026, 11, 6, 12);
    expect(backupAge(null, now), 'Never backed up');
    expect(backupAge(DateTime(2026, 11, 6, 8), now), startsWith('Last backup: today'));
    expect(backupAge(DateTime(2026, 11, 5, 23), now), startsWith('Last backup: yesterday'));
    expect(backupAge(DateTime(2026, 10, 30), now), startsWith('Last backup: 7 days ago'));
  });

  testWidgets('Settings: never backed up -> Back up now creates a file, shares it and records the time', (t) async {
    final (env, f) = await open(t, seed: seedData);
    await scrollTo(t, const Key('backup-status'));
    expect(find.text('Never backed up'), findsOneWidget);
    expect(find.textContaining('1 tasks · 0 events · 1 books'), findsOneWidget);
    await scrollTo(t, const Key('backup-now'));
    await t.tap(find.byKey(const Key('backup-now')));
    await settleB(t);
    expect(f.shared.length, 1);
    expect(f.shared.single.existsSync(), isTrue);
    expect(f.shared.single.path, endsWith('.folio'));
    expect(await t.runAsync(() => env.store.state('last_backup_at')), isNotNull);
    await scrollTo(t, const Key('backup-status'));
    expect(find.textContaining('Last backup: today'), findsOneWidget);
    await end(t);
  });

  testWidgets('dismissing the share sheet does not count as a backup', (t) async {
    final (env, f) = await open(t, seed: seedData);
    f.dismiss = true;
    await scrollTo(t, const Key('backup-now'));
    await t.tap(find.byKey(const Key('backup-now')));
    await settleB(t);
    expect(await t.runAsync(() => env.store.state('last_backup_at')), isNull);
    expect(find.text('Backup cancelled. Nothing was saved.'), findsOneWidget);
    await end(t);
  });

  testWidgets('Restore: pick a file, confirm, see what was added; a bad file shows a plain message', (t) async {
    // make a backup from a "source" device
    final src = await TestEnv.create();
    addTearDown(src.db.close);
    late File backup;
    await t.runAsync(() async {
      await seedData(src);
      final svc = BackupServiceFor(src);
      backup = await svc.create(Directory.systemTemp.createTempSync('srcbk'));
    });
    final (env, f) = await open(t);
    await scrollTo(t, const Key('backup-restore'));

    final junk = File('${Directory.systemTemp.createTempSync('j').path}/x.folio')..writeAsStringSync('nope');
    f.picked = junk.path;
    await t.tap(find.byKey(const Key('backup-restore')));
    await settleB(t);
    expect(find.textContaining('not a Folio backup'), findsOneWidget);

    f.picked = backup.path;
    await scrollTo(t, const Key('backup-restore'));
    await t.tap(find.byKey(const Key('backup-restore')));
    await settleB(t);
    expect(find.text('Restore this backup?'), findsOneWidget);
    expect(find.textContaining('1 tasks · 0 events · 1 books'), findsOneWidget);
    await t.tap(find.byKey(const Key('restore-confirm')));
    await settleB(t);
    expect(find.text('Restore finished'), findsOneWidget);
    expect(find.textContaining('Added 1 tasks, 0 events, 1 books'), findsOneWidget);
    await t.tap(find.text('OK'));
    await settleB(t);
    expect((await t.runAsync(() => env.db.select(env.db.tasks).get()))!.single.title, 'Pay rent');
    expect((await t.runAsync(() => env.db.select(env.db.books).get()))!.length, 1);

    // restoring the same file again says there is nothing to add
    await scrollTo(t, const Key('backup-restore'));
    await t.tap(find.byKey(const Key('backup-restore')));
    await settleB(t);
    await t.tap(find.byKey(const Key('restore-confirm')));
    await settleB(t);
    expect(find.text('Nothing to add'), findsOneWidget);
    await t.tap(find.text('OK'));
    await settleB(t);
    await end(t);
  });

  testWidgets('Home nudges to back up once there is data, and stops after a backup', (t) async {
    final (env, _) = await open(t, seed: seedData, start: 'Home');
    expect(find.byKey(const Key('home-backup-nudge')), findsOneWidget);
    await t.runAsync(() => env.store.setState('last_backup_at', '${DateTime.now().millisecondsSinceEpoch}'));
    await end(t);
    final (_, _) = await open(t, seed: (e) async {
      await seedData(e);
      await e.store.setState('last_backup_at', '${DateTime.now().millisecondsSinceEpoch}');
    }, start: 'Home');
    expect(find.byKey(const Key('home-backup-nudge')), findsNothing);
    await end(t);
  });

  testWidgets('a fresh install has no nudge (nothing to lose yet)', (t) async {
    await open(t, start: 'Home');
    expect(find.byKey(const Key('home-backup-nudge')), findsNothing);
    await end(t);
  });
}
