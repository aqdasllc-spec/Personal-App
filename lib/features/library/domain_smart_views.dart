import 'dart:convert';

const maxSmartViews = 20;
const maxViewNameLength = 30;

/// A saved Library view: reading status + tags + sort order, under a name ("smart collection").
class SmartView {
  const SmartView({required this.name, this.status = 'all', this.tags = const [], this.sort = 'added'});
  final String name, status, sort;
  final List<String> tags;

  Map<String, Object> toJson() => {'n': name, 's': status, 't': tags, 'o': sort};
}

String encodeViews(List<SmartView> v) => jsonEncode([for (final x in v) x.toJson()]);

/// Forgiving: unreadable data gives no views, a bad entry is skipped.
List<SmartView> decodeViews(String? json) {
  if (json == null || json.isEmpty) return const [];
  try {
    final out = <SmartView>[];
    for (final e in jsonDecode(json) as List) {
      if (e is! Map) continue;
      final n = e['n'], s = e['s'], t = e['t'], o = e['o'];
      if (n is! String || n.trim().isEmpty) continue;
      out.add(SmartView(
        name: n.trim(),
        status: s is String ? s : 'all',
        tags: [if (t is List) for (final x in t) if (x is String && x.trim().isNotEmpty) x],
        sort: o is String ? o : 'added',
      ));
    }
    return out.take(maxSmartViews).toList();
  } catch (_) {
    return const [];
  }
}

/// Adds [view] (same name, ignoring case, replaces the old one). At most [maxSmartViews]; the oldest is dropped.
List<SmartView> withView(List<SmartView> views, SmartView view) {
  final name = view.name.trim().replaceAll(RegExp(r'\s+'), ' ');
  final cut = name.length > maxViewNameLength ? name.substring(0, maxViewNameLength).trim() : name;
  final fixed = SmartView(name: cut, status: view.status, tags: view.tags, sort: view.sort);
  final rest = [for (final v in views) if (v.name.toLowerCase() != cut.toLowerCase()) v];
  final all = [...rest, fixed];
  return all.length > maxSmartViews ? all.sublist(all.length - maxSmartViews) : all;
}

/// A tag was renamed/merged: views that filter by it follow.
List<SmartView> renameTagInViews(List<SmartView> views, String from, String to) => [
  for (final v in views)
    SmartView(
      name: v.name,
      status: v.status,
      sort: v.sort,
      tags: {
        for (final t in v.tags) t.toLowerCase() == from.toLowerCase() ? to : t,
      }.toList(),
    ),
];

/// A tag was deleted everywhere: views stop filtering by it.
List<SmartView> dropTagFromViews(List<SmartView> views, String tag) => [
  for (final v in views)
    SmartView(
      name: v.name,
      status: v.status,
      sort: v.sort,
      tags: [for (final t in v.tags) if (t.toLowerCase() != tag.toLowerCase()) t],
    ),
];
