import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../data/cover_renderer.dart';
import 'library_controller.dart';

/// Rendering many covers at once (a big grid) would hog the CPU and memory: at most two at a time.
class _RenderQueue {
  int _running = 0;
  final _waiting = <void Function()>[];

  Future<T> run<T>(Future<T> Function() job) async {
    if (_running >= 2) {
      final turn = Completer<void>();
      _waiting.add(turn.complete);
      await turn.future;
    }
    _running++;
    try {
      return await job();
    } finally {
      _running--;
      if (_waiting.isNotEmpty) _waiting.removeAt(0)();
    }
  }
}

final _queue = _RenderQueue();

final coverRendererProvider = Provider<CoverRenderer>(
  (ref) => PdfrxCoverRenderer(),
);

/// First-page image of a book (PNG bytes), rendered once and cached on disk under `<library>/covers/`.
/// Null when it cannot be rendered (the preview then shows a coloured cover instead).
final coverBytesProvider = FutureProvider.autoDispose
    .family<Uint8List?, String>((ref, bookId) async {
      final repo = ref.read(libraryRepositoryProvider);
      final cache = File(p.join(repo.directory.path, 'covers', '$bookId.png'));
      try {
        if (await cache.exists()) return await cache.readAsBytes();
      } catch (_) {}
      final book = await repo.book(bookId);
      if (book == null) return null;
      final file = repo.fileOf(book);
      if (!await file.exists()) return null;
      final renderer = ref.read(coverRendererProvider);
      final bytes = await _queue.run(() => renderer.renderFirstPage(file));
      if (bytes == null) return null;
      try {
        await cache.parent.create(recursive: true);
        await cache.writeAsBytes(bytes, flush: true);
      } catch (_) {
        // caching is an optimisation only
      }
      return bytes;
    });
