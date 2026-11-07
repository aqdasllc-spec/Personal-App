import '../../../data/local/app_database.dart';

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String _marker(String color) => switch (color) {
  'green' => '🟢',
  'blue' => '🔵',
  'pink' => '🟣',
  _ => '🟡',
};

String _quote(String text) => text
    .trim()
    .split(RegExp(r'\r?\n'))
    .map((l) => '> ${l.trim()}'.trimRight())
    .join('\n');

/// Plain-text (Markdown) notes for one book: every highlight with its note, grouped by page, then the bookmarks.
/// Opens fine in any text editor and pastes cleanly into Obsidian, Notion, Word, e-mail...
String buildNotesMarkdown({
  required String title,
  required String author,
  required List<HighlightRow> highlights,
  required List<int> bookmarkPages,
  required DateTime exportedAt,
}) {
  final pages = {...bookmarkPages}.toList()..sort();
  final b = StringBuffer();
  b.writeln('# ${title.trim().isEmpty ? 'Untitled' : title.trim()}');
  b.writeln();
  final facts = <String>[
    if (author.trim().isNotEmpty) author.trim(),
    '${highlights.length} ${highlights.length == 1 ? 'highlight' : 'highlights'}',
    if (pages.isNotEmpty)
      '${pages.length} ${pages.length == 1 ? 'bookmark' : 'bookmarks'}',
    'exported ${exportedAt.day} ${_months[exportedAt.month - 1]} ${exportedAt.year}',
  ];
  b.writeln('_${facts.join(' · ')}_');

  final sorted = [...highlights]
    ..sort(
      (a, c) => a.page != c.page
          ? a.page.compareTo(c.page)
          : a.createdAt.compareTo(c.createdAt),
    );
  int? page;
  for (final h in sorted) {
    if (h.page != page) {
      page = h.page;
      b.writeln();
      b.writeln('## Page ${h.page}');
    }
    b.writeln();
    b.writeln(
      '${_marker(h.color)} ${h.snippet.trim().isEmpty ? '_(no text)_' : ''}'
          .trimRight(),
    );
    if (h.snippet.trim().isNotEmpty) b.writeln(_quote(h.snippet));
    if (h.note.trim().isNotEmpty) {
      b.writeln();
      final lines = h.note.trim().split(RegExp(r'\r?\n'));
      b.writeln('**Note:** ${lines.first}');
      for (final l in lines.skip(1)) {
        b.writeln(l);
      }
    }
  }
  if (pages.isNotEmpty) {
    b.writeln();
    b.writeln('## Bookmarks');
    b.writeln();
    for (final p in pages) {
      b.writeln('- Page $p');
    }
  }
  return b.toString();
}

/// A safe file name for [title] (letters, digits, space, dash, underscore), never empty.
String safeFileName(String title, {String suffix = '-notes.md'}) {
  final cleaned = title
      .replaceAll(RegExp(r'[^A-Za-z0-9 _\-]'), '')
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ');
  final base = cleaned.isEmpty
      ? 'book'
      : (cleaned.length > 60 ? cleaned.substring(0, 60).trim() : cleaned);
  return '$base$suffix';
}
