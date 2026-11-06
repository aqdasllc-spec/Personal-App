/// Property types a user can add to a tracker. Names are persisted - never rename.
enum PropertyType {
  text,
  richText,
  number,
  currency,
  percent,
  checkbox,
  date,
  dateRange,
  url,
  email,
  phone,
  select,
  multiSelect,
  status,
  progress,
  person,
  files,
  image,
  relation,
  rollup,
  formula,
  createdTime,
  lastEditedTime;

  static PropertyType parse(String s) =>
      PropertyType.values.firstWhere((t) => t.name == s, orElse: () => throw FormatException('Unknown property type', s));

  /// Derived on every device from other data; never stored in `cells`, never synced.
  bool get isComputed => this == rollup || this == formula || this == createdTime || this == lastEditedTime;

  /// Edges live in the links table, not in `cells`.
  bool get isRelation => this == relation;

  bool get isStored => !isComputed && !isRelation;

  bool get isOptionBased => this == select || this == multiSelect || this == status;

  bool get isTextLike => this == text || this == richText || this == url || this == email || this == phone;
}

enum StatusGroup { todo, inProgress, complete }

class SelectOption {
  const SelectOption({required this.id, required this.label, this.color = 'gray', this.group});
  final String id;
  final String label;
  final String color;

  /// Only for [PropertyType.status]: drives progress and Kanban column grouping.
  final StatusGroup? group;

  Map<String, Object?> toJson() => {'id': id, 'label': label, 'color': color, if (group != null) 'group': group!.name};

  factory SelectOption.fromJson(Map<String, Object?> j) => SelectOption(
        id: j['id']! as String,
        label: j['label']! as String,
        color: (j['color'] as String?) ?? 'gray',
        group: j['group'] == null ? null : StatusGroup.values.byName(j['group']! as String),
      );
}

/// One column definition. [config] is a JSON map whose shape depends on [type];
/// typed accessors below keep call sites safe. Option ids (not labels) are what cells store,
/// so renaming or recolouring an option never rewrites cell data.
class PropertyDef {
  const PropertyDef({required this.id, required this.name, required this.type, this.config = const {}});
  final String id;
  final String name;
  final PropertyType type;
  final Map<String, Object?> config;

  PropertyDef copyWith({String? name, Map<String, Object?>? config}) =>
      PropertyDef(id: id, name: name ?? this.name, type: type, config: config ?? this.config);

  List<SelectOption> get options =>
      [for (final o in (config['options'] as List?) ?? const []) SelectOption.fromJson(Map<String, Object?>.from(o as Map))];

  SelectOption? option(String? optionId) {
    for (final o in options) {
      if (o.id == optionId) return o;
    }
    return null;
  }

  // number / percent / currency formatting
  int get decimals => (config['decimals'] as int?) ?? (type == PropertyType.currency ? 2 : 0);
  String get prefix => (config['prefix'] as String?) ?? '';
  String get suffix => (config['suffix'] as String?) ?? '';
  String get currencyCode => (config['currency'] as String?) ?? 'USD';
  String get currencySymbol => (config['symbol'] as String?) ?? r'$';

  /// percent: stored as 0..100 (default) or 0..1 when `fraction` is true.
  bool get percentIsFraction => config['fraction'] == true;

  // date
  bool get includeTime => config['includeTime'] == true;

  // relation
  String? get relationTargetTrackerId => config['targetTrackerId'] as String?;
  bool get relationAllowsMany => config['many'] != false;

  // rollup
  String? get rollupRelationId => config['relationPropertyId'] as String?;
  String? get rollupTargetId => config['targetPropertyId'] as String?;
  String get rollupAggregate => (config['aggregate'] as String?) ?? 'count';

  // formula
  String get formulaSource => (config['formula'] as String?) ?? '';

  Map<String, Object?> toJson() => {'id': id, 'name': name, 'type': type.name, 'config': config};

  factory PropertyDef.fromJson(Map<String, Object?> j) => PropertyDef(
        id: j['id']! as String,
        name: j['name']! as String,
        type: PropertyType.parse(j['type']! as String),
        config: Map<String, Object?>.from((j['config'] as Map?) ?? const {}),
      );
}

/// Helpers to build common configs.
abstract final class Cfg {
  static Map<String, Object?> options(List<SelectOption> o) => {'options': [for (final x in o) x.toJson()]};
}
