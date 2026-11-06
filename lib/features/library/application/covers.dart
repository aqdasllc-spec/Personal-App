import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../data/cover_renderer.dart';
import 'library_controller.dart';

final coverRendererProvider = Provider<CoverRenderer>(
  (ref) => PdfrxCoverRenderer(),
);

/// First-page image of a book (PNG bytes), rendered once and cached on disk under `<library>/covers/`.
/// Null when it cannot be rendered (the preview then shows a coloured cover instead).
final coverBytesProvider = FutureProvider.autoDispose.family<Uint8List?, String>((
  ref,
  bookId,
) async {
  final repo = ref.read(libraryRepositoryProvider);
  final cache = File(p.join(repo.directory.path, 'covers', '$bookId.png'));
  try {
    if (await cache.exists()) return await cache.readAsBytes();
  } catch (_) {}
  final book = await repo.book(bookId);
  if (book == null) return null;
  final file = repo.fileOf(book);
  if (!await file.exists()) return null;
  final bytes = await ref.read(coverRendererProvider).renderFirstPage(file);
  if (bytes == null) return null;
  try {
    await cache.parent.create(recursive: true);
    await cache.writeAsBytes(bytes, flush: true);
  } catch (_) {
    // caching is an optimisation only
  }
  return bytes;
});
