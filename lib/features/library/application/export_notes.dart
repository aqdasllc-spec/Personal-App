import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../data/local/app_database.dart';
import '../../backup/backup_controller.dart';
import '../data/highlights_export.dart';
import 'library_controller.dart';

/// Hands a file to the OS share sheet. True unless the user dismissed it. Overridden in tests.
final shareFileProvider =
    Provider<Future<bool> Function(File file, String subject)>(
      (ref) => (file, subject) async {
        final r = await SharePlus.instance.share(
          ShareParams(files: [XFile(file.path)], subject: subject),
        );
        return r.status != ShareResultStatus.dismissed;
      },
    );

/// Builds the notes for [book] and shares them as a .md file (or copies the text). Returns a message for the user.
Future<String> exportBookNotes(
  WidgetRef ref,
  BookRow book, {
  required bool copy,
  DateTime? now,
}) async {
  final repo = ref.read(libraryRepositoryProvider);
  final highlights = await repo.watchHighlights(book.id).first;
  final marks = await repo.watchBookmarks(book.id).first;
  if (highlights.isEmpty && marks.isEmpty) {
    return 'Nothing to export yet: highlight some text or add a bookmark first.';
  }
  final text = buildNotesMarkdown(
    title: book.title,
    author: book.author,
    highlights: highlights,
    bookmarkPages: [for (final m in marks) m.page],
    exportedAt: now ?? DateTime.now(),
  );
  if (copy) {
    await Clipboard.setData(ClipboardData(text: text));
    return 'Copied ${highlights.length} ${highlights.length == 1 ? 'highlight' : 'highlights'} to the clipboard.';
  }
  final dir = await ref.read(backupTempDirProvider)();
  await dir.create(recursive: true);
  final file = File('${dir.path}/${safeFileName(book.title)}');
  await file.writeAsString(text);
  final shared = await ref.read(shareFileProvider)(
    file,
    '${book.title} - notes',
  );
  return shared ? 'Notes ready to share.' : 'Sharing cancelled.';
}
