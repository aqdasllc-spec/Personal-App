import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:folio/features/library/application/book_sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/data/local/app_database.dart';
import 'package:folio/features/library/data/cloud_books.dart';
import 'package:folio/features/auth/auth_repository.dart';

import '../../helpers.dart';

Future<void> io(WidgetTester t, {bool untilIdle = true}) async {
  for (var i = 0; i < 300; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 15)));
    for (var k = 0; k < 3; k++) {
      await t.pump(const Duration(milliseconds: 40));
    }
    if (i >= 2 && (!untilIdle || (find.byType(CircularProgressIndicator).evaluate().isEmpty && find.byIcon(Icons.sync).evaluate().isEmpty))) break;
  }
  if (untilIdle) await t.pumpAndSettle();
}

Future<void> end(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 1));
}

const signedIn = SignedInSession(userId: 'u1', email: 'a@b.co');

/// Opens the Library with one imported book. [cloud] null = a build without cloud sync.
Future<(TestEnv, BookRow)> open(WidgetTester t, {FakeCloudBooks? cloud, AppSession session = signedIn}) async {
  t.view.physicalSize = const Size(411, 890);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final env = await TestEnv.create(session: session);
  addTearDown(env.db.close);
  env.cloud = cloud;
  env.picked = [(await t.runAsync(() => env.writePdf('Deep_Work.pdf', 200)))!];
  await t.pumpWidget(env.app);
  await io(t);
  await t.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Library')));
  await io(t);
  await t.tap(find.byKey(const Key('library-add')));
  await io(t);
  final b = (await t.runAsync(() => env.db.select(env.db.books).get()))!.single;
  return (env, b);
}

Finder dot(BookRow b) => find.byKey(Key('cloud-dot-${b.id}'));
Future<String?> state(WidgetTester t, TestEnv e) async => (await t.runAsync(() => e.db.select(e.db.books).get()))!.single.cloudState;

/// What the dot shows: arrows while busy, otherwise red/green from the book's stored state.
Future<bool> dotShows(WidgetTester t, TestEnv e, BookRow b, String start) async {
  final busy = find.descendant(of: dot(b), matching: find.byIcon(Icons.sync)).evaluate().isNotEmpty;
  final cloud = await state(t, e);
  final shown = busy ? 'Syncing' : (cloud == 'synced' ? 'Synced' : 'Only on this device');
  return shown.startsWith(start);
}

/// Pumps (with real time for file/database work) until [cond] holds, at most ~10 s.
Future<void> until(WidgetTester t, Future<bool> Function() cond) async {
  for (var i = 0; i < 200 && !await cond(); i++) {
    await io(t, untilIdle: false);
  }
}

void main() {
  testWidgets('a build without cloud sync shows no dots', (t) async {
    final (_, b) = await open(t);
    expect(dot(b), findsNothing);
    await end(t);
  });

  testWidgets('red dot -> Cancel does nothing; Sync shows rotating arrows, then green with the file in the cloud', (t) async {
    final cloud = FakeCloudBooks();
    final (env, b) = await open(t, cloud: cloud);
    expect(dot(b), findsOneWidget);
    expect(await dotShows(t, env, b, 'Only on this device'), isTrue);

    await t.tap(dot(b));
    await io(t);
    expect(find.text('Sync to cloud?'), findsOneWidget);
    await t.tap(find.byKey(const Key('cloud-cancel')));
    await io(t);
    expect((cloud.uploads, await state(t, env)), (0, 'local'));

    cloud.gate = Completer<void>();
    await t.tap(dot(b));
    await io(t);
    await t.tap(find.byKey(const Key('cloud-confirm')));
    await io(t, untilIdle: false);
    expect(find.descendant(of: dot(b), matching: find.byIcon(Icons.sync)), findsOneWidget, reason: 'rotating arrows while uploading');
    expect(await dotShows(t, env, b, 'Syncing'), isTrue);
    expect(find.descendant(of: dot(b), matching: find.byType(RotationTransition)), findsOneWidget);
    await t.tap(dot(b)); // tapping while busy does nothing
    await io(t, untilIdle: false);
    expect(find.text('Sync to cloud?'), findsNothing);

    cloud.gate!.complete();
    await until(t, () => dotShows(t, env, b, 'Synced'));
    await io(t);
    expect(await dotShows(t, env, b, 'Synced'), isTrue);
    expect((cloud.uploads, String.fromCharCodes(cloud.files[b.id]!), await state(t, env)), (1, 'pages=200', 'synced'));
    expect(cloud.meta[b.id]!.title, 'Deep Work');
    await end(t);
  });

  testWidgets('green dot -> Cancel keeps it; Unsync deletes the cloud copy and the dot goes red; the book stays on the phone', (t) async {
    final cloud = FakeCloudBooks();
    final (env, b) = await open(t, cloud: cloud);
    await t.tap(dot(b));
    await io(t);
    await t.tap(find.byKey(const Key('cloud-confirm')));
    await io(t);
    expect(await dotShows(t, env, b, 'Synced'), isTrue);

    await t.tap(dot(b));
    await io(t);
    expect(find.text('Remove from cloud?'), findsOneWidget);
    expect(find.text('Unsync'), findsOneWidget);
    await t.tap(find.byKey(const Key('cloud-cancel')));
    await io(t);
    expect((cloud.files.length, await state(t, env)), (1, 'synced'));

    await t.tap(dot(b));
    await io(t);
    await t.tap(find.byKey(const Key('cloud-confirm')));
    await io(t);
    expect((cloud.files.length, cloud.meta.length, await state(t, env)), (0, 0, 'local'));
    expect(await dotShows(t, env, b, 'Only on this device'), isTrue);
    expect(File('${env.libraryDir.path}/${b.id}.pdf').existsSync(), isTrue);
    await end(t);
  });

  testWidgets('a failed upload keeps the dot red and says why; a failed unsync keeps it green', (t) async {
    final cloud = FakeCloudBooks();
    final (env, b) = await open(t, cloud: cloud);
    cloud.failWith = 'Can\'t reach the cloud.';
    await t.tap(dot(b));
    await io(t);
    await t.tap(find.byKey(const Key('cloud-confirm')));
    await io(t);
    expect(find.textContaining('Couldn\'t sync "Deep Work"'), findsOneWidget);
    expect((await state(t, env), cloud.files.length), ('local', 0));

    await t.tap(dot(b));
    await io(t);
    await t.tap(find.byKey(const Key('cloud-confirm')));
    await io(t);
    expect(await state(t, env), 'synced');

    cloud.failWith = 'Can\'t reach the cloud.';
    await t.tap(dot(b));
    await io(t);
    await t.tap(find.byKey(const Key('cloud-confirm')));
    await io(t);
    expect(find.textContaining('Couldn\'t remove "Deep Work" from the cloud'), findsOneWidget);
    expect((await state(t, env), cloud.files.length), ('synced', 1));
    await end(t);
  });

  testWidgets('not signed in: the dot explains that an account is needed and uploads nothing', (t) async {
    final cloud = FakeCloudBooks();
    final (_, b) = await open(t, cloud: cloud, session: const LocalOnlySession());
    await t.tap(dot(b));
    await io(t);
    expect(find.text('Sign in to sync'), findsOneWidget);
    await t.tap(find.text('OK'));
    await io(t);
    expect(cloud.uploads, 0);
    await end(t);
  });

  testWidgets('removing a synced book also deletes its cloud copy; if the cloud is unreachable the book stays', (t) async {
    final cloud = FakeCloudBooks();
    final (env, b) = await open(t, cloud: cloud);
    await t.tap(dot(b));
    await io(t);
    await t.tap(find.byKey(const Key('cloud-confirm')));
    await io(t);

    await t.longPress(find.byKey(Key('book-${b.id}')));
    await io(t);
    cloud.failWith = 'Can\'t reach the cloud.';
    await t.ensureVisible(find.byKey(const Key('book-remove')));
    await t.pump();
    await t.tap(find.byKey(const Key('book-remove')));
    await io(t);
    expect(find.text('Can\'t remove it yet'), findsOneWidget);
    await t.tap(find.byKey(const Key('remove-error-ok')));
    await io(t);
    expect((await t.runAsync(() => env.db.select(env.db.books).get()))!.single.deletedAt, isNull, reason: 'kept: the cloud copy could not be deleted');
    expect(cloud.files.length, 1);

    await t.tap(find.byKey(const Key('book-remove')));
    await io(t);
    expect(cloud.files.length, 0);
    expect((await t.runAsync(() => env.db.select(env.db.books).get()))!.single.deletedAt, isNotNull);
    await end(t);
  });

  testWidgets('books that are only in the cloud are offered for download and arrive verified and green', (t) async {
    final cloud = FakeCloudBooks();
    final (env, _) = await open(t, cloud: cloud);
    // another device uploaded a book
    final f = (await t.runAsync(() => env.writePdf('Other.pdf', 9)))!;
    final bytes = File(f).readAsBytesSync();
    cloud.files['remote-1'] = bytes;
    cloud.meta['remote-1'] = CloudBook(id: 'remote-1', title: 'Remote Book', author: 'R. Author', pageCount: 9, sizeBytes: bytes.length, sha256: sha(bytes));
    // the app was reopened / resumed: the banner re-checks the cloud
    ProviderScope.containerOf(t.element(find.byType(NavigationBar))).invalidate(cloudOnlyCountProvider);
    await io(t);
    expect(find.byKey(const Key('cloud-banner')), findsOneWidget);
    expect(find.textContaining('1 book is in your cloud'), findsOneWidget);
    await t.tap(find.byKey(const Key('cloud-download')));
    await until(t, () async => (await t.runAsync(() => env.db.select(env.db.books).get()))!.any((r) => r.id == 'remote-1'));
    await io(t);
    final rows = (await t.runAsync(() => env.db.select(env.db.books).get()))!;
    final remote = rows.firstWhere((r) => r.id == 'remote-1');
    expect((remote.title, remote.author, remote.cloudState, remote.pageCount), ('Remote Book', 'R. Author', 'synced', 9));
    expect(File('${env.libraryDir.path}/remote-1.pdf').readAsBytesSync(), bytes);
    expect(find.byKey(const Key('cloud-banner')), findsNothing);
    await end(t);
  });
}

String sha(List<int> b) => sha256.convert(b).toString();
