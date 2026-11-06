/// Result of a three-way line merge.
final class TextMerge {
  const TextMerge.clean(this.merged)
      : conflict = false,
        local = null,
        remote = null;
  const TextMerge.conflict({required String this.local, required String this.remote})
      : conflict = true,
        merged = null;

  final bool conflict;

  /// Non-null when [conflict] is false.
  final String? merged;

  /// When [conflict] is true both full versions are kept for the user to resolve.
  final String? local;
  final String? remote;
}

class _Hunk {
  _Hunk(this.start, this.end, this.lines);
  final int start; // base index (inclusive)
  final int end; // base index (exclusive)
  final List<String> lines; // replacement
}

/// Line-based three-way merge (diff3-style). Non-overlapping edits merge cleanly;
/// overlapping edits return [TextMerge.conflict] containing **both** versions.
TextMerge mergeText(String base, String local, String remote) {
  if (local == remote) return TextMerge.clean(local);
  if (local == base) return TextMerge.clean(remote);
  if (remote == base) return TextMerge.clean(local);

  final b = base.split('\n');
  final l = local.split('\n');
  final r = remote.split('\n');
  final hl = _hunks(b, l);
  final hr = _hunks(b, r);

  final all = [
    ...hl.map((h) => (h, 0)),
    ...hr.map((h) => (h, 1)),
  ]..sort((x, y) => x.$1.start != y.$1.start ? x.$1.start.compareTo(y.$1.start) : x.$2.compareTo(y.$2));

  // Conservative overlap rule: whenever two edits from different sides could interact,
  // report a conflict (both versions are kept) instead of guessing - no silent data loss.
  for (var i = 0; i < all.length; i++) {
    for (var j = i + 1; j < all.length; j++) {
      final x = all[i], y = all[j];
      if (x.$2 == y.$2 || _identical(x.$1, y.$1)) continue;
      if (_interacts(x.$1, y.$1)) return TextMerge.conflict(local: local, remote: remote);
    }
  }

  final out = <String>[];
  var pos = 0;
  final applied = <_Hunk>[];
  for (final e in all) {
    final h = e.$1;
    if (applied.any((x) => _identical(x, h))) continue; // same edit from both sides
    if (h.start > pos) out.addAll(b.sublist(pos, h.start));
    out.addAll(h.lines);
    pos = h.end > pos ? h.end : pos;
    applied.add(h);
  }
  if (pos < b.length) out.addAll(b.sublist(pos));
  return TextMerge.clean(out.join('\n'));
}

/// Ranges overlap, or an insertion (empty range) touches/sits inside the other edit.
bool _interacts(_Hunk a, _Hunk c) {
  final aIns = a.start == a.end, cIns = c.start == c.end;
  if (aIns && cIns) return a.start == c.start;
  if (aIns) return a.start >= c.start && a.start <= c.end;
  if (cIns) return c.start >= a.start && c.start <= a.end;
  return a.start < c.end && c.start < a.end;
}

bool _identical(_Hunk a, _Hunk b) =>
    a.start == b.start && a.end == b.end && a.lines.length == b.lines.length &&
    List.generate(a.lines.length, (i) => a.lines[i] == b.lines[i]).every((x) => x);

/// Edits turning [base] into [other], as hunks over base indices, via LCS.
List<_Hunk> _hunks(List<String> base, List<String> other) {
  final n = base.length, m = other.length;
  final lcs = List.generate(n + 1, (_) => List.filled(m + 1, 0));
  for (var i = n - 1; i >= 0; i--) {
    for (var j = m - 1; j >= 0; j--) {
      lcs[i][j] = base[i] == other[j] ? lcs[i + 1][j + 1] + 1 : (lcs[i + 1][j] >= lcs[i][j + 1] ? lcs[i + 1][j] : lcs[i][j + 1]);
    }
  }
  final hunks = <_Hunk>[];
  var i = 0, j = 0;
  int? hs;
  final repl = <String>[];
  void flush(int endBase) {
    if (hs != null) {
      hunks.add(_Hunk(hs!, endBase, List.of(repl)));
      hs = null;
      repl.clear();
    }
  }

  while (i < n || j < m) {
    if (i < n && j < m && base[i] == other[j]) {
      flush(i);
      i++;
      j++;
    } else if (j < m && (i >= n || lcs[i][j + 1] >= lcs[i + 1][j])) {
      hs ??= i;
      repl.add(other[j++]);
    } else {
      hs ??= i;
      i++;
    }
  }
  flush(i);
  return hunks;
}
