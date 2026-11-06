import 'hlc.dart';

/// Identifies one syncable field: a single cell / column of one row.
final class FieldKey {
  const FieldKey(this.table, this.rowId, this.field);
  final String table;
  final String rowId;
  final String field;

  @override
  bool operator ==(Object other) => other is FieldKey && other.table == table && other.rowId == rowId && other.field == field;
  @override
  int get hashCode => Object.hash(table, rowId, field);
  @override
  String toString() => '$table/$rowId/$field';
}

/// A value together with the clock of the edit that produced it.
final class Versioned {
  const Versioned(this.value, this.hlc);
  final Object? value; // JSON-encodable
  final Hlc hlc;
}

/// One field edit, as stored in the client outbox and the server change log.
final class Change {
  const Change({
    required this.key,
    required this.value,
    required this.hlc,
    required this.baseHlc,
    required this.deviceId,
    required this.changeId,
  });

  final FieldKey key;
  final Object? value;
  final Hlc hlc;

  /// The clock of the value this edit was made *on top of* (null: field was unseen).
  /// Used to decide whether an edit is causal or concurrent.
  final Hlc? baseHlc;
  final String deviceId;

  /// Unique per device; with [deviceId] makes pushes idempotent across retries.
  final String changeId;
}

/// A value that lost a concurrent edit. Kept so the user can review / restore it.
final class Conflict {
  const Conflict({required this.key, required this.lostValue, required this.lostHlc, required this.winnerHlc});
  final FieldKey key;
  final Object? lostValue;
  final Hlc lostHlc;
  final Hlc winnerHlc;
}
