import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/router.dart';
import '../data/library_repository.dart';
import 'library_controller.dart' show libraryRepositoryProvider;

/// PDFs another app hands to Folio ("Open with" / "Share"), as copies in the app's cache.
abstract class OpenWithPort {
  /// The PDF that started the app, once (null when it was started another way).
  Future<String?> initial();

  /// PDFs handed over while the app runs.
  Stream<String> get opened;
}

class AndroidOpenWith implements OpenWithPort {
  AndroidOpenWith() {
    if (_android) {
      _ch.setMethodCallHandler((call) async {
        if (call.method == 'opened' && call.arguments is String) _opened.add(call.arguments as String);
      });
    }
  }
  static const _ch = MethodChannel('folio/open');
  final _opened = StreamController<String>.broadcast();
  bool get _android => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  Future<String?> initial() async {
    if (!_android) return null;
    try {
      return await _ch.invokeMethod<String>('initial');
    } catch (_) {
      return null;
    }
  }

  @override
  Stream<String> get opened => _opened.stream;
}

final openWithPortProvider = Provider<OpenWithPort>((_) => AndroidOpenWith());

/// Adds a handed-over PDF to the Library (or finds it there already) and opens it.
Future<void> openHandedPdf(WidgetRef ref, String path) async {
  final router = ref.read(routerProvider);
  final r = await ref.read(libraryRepositoryProvider).importPdf(path);
  try {
    await File(path).delete(); // the Library keeps its own copy
  } catch (_) {}
  final book = r.book;
  final messenger = router.routerDelegate.navigatorKey.currentContext;
  if (book == null) {
    if (messenger != null && messenger.mounted) {
      ScaffoldMessenger.maybeOf(messenger)?.showSnackBar(
        SnackBar(content: Text(r.status == ImportStatus.unreadable ? '"${r.fileName}" could not be opened: it is not a readable PDF.' : 'Could not add "${r.fileName}".')),
      );
    }
    return;
  }
  router.go(Routes.library);
  unawaited(router.push('${Routes.library}/read/${book.id}'));
  if (r.status == ImportStatus.duplicate && messenger != null && messenger.mounted) {
    ScaffoldMessenger.maybeOf(messenger)?.showSnackBar(SnackBar(content: Text('"${book.title}" is already in your Library: opened it.')));
  }
}

/// Follows PDFs handed over by other apps (the one that started the app, and later ones).
void followOpenWith(WidgetRef ref) {
  final port = ref.read(openWithPortProvider);
  port.initial().then((p) {
    if (p != null) unawaited(openHandedPdf(ref, p));
  }).catchError((Object _) {});
  port.opened.listen((p) => unawaited(openHandedPdf(ref, p)));
}
