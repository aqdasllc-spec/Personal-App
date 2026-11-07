import 'dart:io';

/// All PDF files inside [path] and its sub-folders (hidden names skipped), sorted, at most [limit].
/// Null when the folder cannot be read at all (for example no permission).
Future<List<String>?> scanPdfFolder(String path, {int limit = 2000}) async {
  final out = <String>[];
  try {
    await for (final e in Directory(path).list(recursive: true, followLinks: false)) {
      if (e is! File) continue;
      final name = e.uri.pathSegments.isEmpty ? '' : e.uri.pathSegments.last;
      if (name.startsWith('.') || !name.toLowerCase().endsWith('.pdf')) continue;
      if (e.path.split(Platform.pathSeparator).any((p) => p.startsWith('.') && p.length > 1)) continue;
      out.add(e.path);
      if (out.length >= limit) break;
    }
  } catch (_) {
    if (out.isEmpty) return null;
  }
  out.sort();
  return out;
}
