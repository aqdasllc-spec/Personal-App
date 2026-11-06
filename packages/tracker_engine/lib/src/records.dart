import 'property.dart';
import 'values.dart';

class TrackerRecord {
  TrackerRecord({
    required this.id,
    required this.trackerId,
    this.parentId,
    this.sortKey = '',
    Map<String, Value>? cells,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.archived = false,
  })  : cells = cells ?? {},
        createdAt = createdAt ?? DateTime.utc(1970),
        updatedAt = updatedAt ?? DateTime.utc(1970);

  final String id;
  final String trackerId;
  final String? parentId;
  final String sortKey;

  /// propertyId -> stored value (never contains computed/relation properties).
  final Map<String, Value> cells;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool archived;
}

/// Everything needed to evaluate one tracker in memory: the reference implementation that the
/// SQL query layer is tested against, and what formulas/rollups run over.
class TrackerSnapshot {
  TrackerSnapshot({
    required this.trackerId,
    required this.properties,
    required this.records,
    Map<String, Map<String, List<String>>>? links,
    Map<String, TrackerSnapshot>? others,
  })  : links = links ?? {},
        others = others ?? {};

  final String trackerId;
  final List<PropertyDef> properties;
  final List<TrackerRecord> records;

  /// relationPropertyId -> fromRecordId -> ordered target record ids.
  final Map<String, Map<String, List<String>>> links;

  /// Other trackers reachable through relations (for rollups).
  final Map<String, TrackerSnapshot> others;

  PropertyDef? property(String id) {
    for (final p in properties) {
      if (p.id == id) return p;
    }
    return null;
  }

  TrackerRecord? record(String id) {
    for (final r in records) {
      if (r.id == id) return r;
    }
    return null;
  }

  /// The title property: first text property by convention (override via config `isTitle`).
  PropertyDef? get titleProperty {
    for (final p in properties) {
      if (p.config['isTitle'] == true) return p;
    }
    for (final p in properties) {
      if (p.type == PropertyType.text) return p;
    }
    return null;
  }
}
