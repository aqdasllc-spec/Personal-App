/// Three-way merge for multi-valued fields (multi-select, relations, files).
///
/// Semantics: **add-wins**. An element present in either side's result is kept,
/// except when one side removed it and the other side did not touch it.
/// If one side removed an element the other side *added* (i.e. it is not in [base]),
/// that cannot happen. The remaining ambiguity is "removed on A, kept on B":
/// that is a plain removal (B did not change it), so the element goes.
final class SetMerge<T> {
  const SetMerge(this.merged, this.removedWhileAdded);
  final Set<T> merged;

  /// Elements one side removed that the other side explicitly re-added - impossible
  /// with a shared base, reserved for callers that track per-element clocks.
  final Set<T> removedWhileAdded;
}

SetMerge<T> mergeSets<T>(Set<T> base, Set<T> local, Set<T> remote) {
  final addedLocal = local.difference(base);
  final addedRemote = remote.difference(base);
  final removedLocal = base.difference(local);
  final removedRemote = base.difference(remote);
  final merged = <T>{...base}
    ..removeAll(removedLocal)
    ..removeAll(removedRemote)
    ..addAll(addedLocal)
    ..addAll(addedRemote);
  return SetMerge(merged, const {});
}
