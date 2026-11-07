/// A search hit inside a book: the page and a short piece of text around the match.
class BookHit {
  const BookHit({required this.bookId, required this.title, required this.page, required this.snippet});
  final String bookId, title, snippet;
  final int page;
}

String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

/// Pieces of [text] around each place [query] occurs (case and spacing ignored), at most [max], with "…" where cut.
/// Each piece is about [radius] characters either side of the match.
List<String> snippetsIn(String text, String query, {int max = 3, int radius = 50}) {
  final q = _norm(query);
  if (q.isEmpty) return const [];
  final flat = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  final lower = flat.toLowerCase();
  final out = <String>[];
  var from = 0;
  while (out.length < max && from <= lower.length) {
    final at = lower.indexOf(q, from);
    if (at < 0) break;
    final start = (at - radius).clamp(0, flat.length);
    final end = (at + q.length + radius).clamp(0, flat.length);
    out.add('${start > 0 ? '…' : ''}${flat.substring(start, end).trim()}${end < flat.length ? '…' : ''}');
    from = at + q.length + radius; // do not report the same stretch twice
  }
  return out;
}

/// Colour names and their default order.
const highlightColorNames = {'yellow': 'Yellow', 'green': 'Green', 'blue': 'Blue', 'pink': 'Pink'};
