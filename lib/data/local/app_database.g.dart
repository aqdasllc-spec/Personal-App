// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $TasksTable extends Tasks with TableInfo<$TasksTable, TaskRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TasksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
    'notes',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _priorityMeta = const VerificationMeta(
    'priority',
  );
  @override
  late final GeneratedColumn<String> priority = GeneratedColumn<String>(
    'priority',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _dueAtMeta = const VerificationMeta('dueAt');
  @override
  late final GeneratedColumn<int> dueAt = GeneratedColumn<int>(
    'due_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _dueHasTimeMeta = const VerificationMeta(
    'dueHasTime',
  );
  @override
  late final GeneratedColumn<int> dueHasTime = GeneratedColumn<int>(
    'due_has_time',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _plannedAtMeta = const VerificationMeta(
    'plannedAt',
  );
  @override
  late final GeneratedColumn<int> plannedAt = GeneratedColumn<int>(
    'planned_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _plannedMinutesMeta = const VerificationMeta(
    'plannedMinutes',
  );
  @override
  late final GeneratedColumn<int> plannedMinutes = GeneratedColumn<int>(
    'planned_minutes',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _doneAtMeta = const VerificationMeta('doneAt');
  @override
  late final GeneratedColumn<int> doneAt = GeneratedColumn<int>(
    'done_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _rruleMeta = const VerificationMeta('rrule');
  @override
  late final GeneratedColumn<String> rrule = GeneratedColumn<String>(
    'rrule',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _remindMinutesMeta = const VerificationMeta(
    'remindMinutes',
  );
  @override
  late final GeneratedColumn<int> remindMinutes = GeneratedColumn<int>(
    'remind_minutes',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sortKeyMeta = const VerificationMeta(
    'sortKey',
  );
  @override
  late final GeneratedColumn<String> sortKey = GeneratedColumn<String>(
    'sort_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<int> deletedAt = GeneratedColumn<int>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    title,
    notes,
    priority,
    dueAt,
    dueHasTime,
    plannedAt,
    plannedMinutes,
    doneAt,
    rrule,
    remindMinutes,
    sortKey,
    deletedAt,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'tasks';
  @override
  VerificationContext validateIntegrity(
    Insertable<TaskRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    }
    if (data.containsKey('notes')) {
      context.handle(
        _notesMeta,
        notes.isAcceptableOrUnknown(data['notes']!, _notesMeta),
      );
    }
    if (data.containsKey('priority')) {
      context.handle(
        _priorityMeta,
        priority.isAcceptableOrUnknown(data['priority']!, _priorityMeta),
      );
    }
    if (data.containsKey('due_at')) {
      context.handle(
        _dueAtMeta,
        dueAt.isAcceptableOrUnknown(data['due_at']!, _dueAtMeta),
      );
    }
    if (data.containsKey('due_has_time')) {
      context.handle(
        _dueHasTimeMeta,
        dueHasTime.isAcceptableOrUnknown(
          data['due_has_time']!,
          _dueHasTimeMeta,
        ),
      );
    }
    if (data.containsKey('planned_at')) {
      context.handle(
        _plannedAtMeta,
        plannedAt.isAcceptableOrUnknown(data['planned_at']!, _plannedAtMeta),
      );
    }
    if (data.containsKey('planned_minutes')) {
      context.handle(
        _plannedMinutesMeta,
        plannedMinutes.isAcceptableOrUnknown(
          data['planned_minutes']!,
          _plannedMinutesMeta,
        ),
      );
    }
    if (data.containsKey('done_at')) {
      context.handle(
        _doneAtMeta,
        doneAt.isAcceptableOrUnknown(data['done_at']!, _doneAtMeta),
      );
    }
    if (data.containsKey('rrule')) {
      context.handle(
        _rruleMeta,
        rrule.isAcceptableOrUnknown(data['rrule']!, _rruleMeta),
      );
    }
    if (data.containsKey('remind_minutes')) {
      context.handle(
        _remindMinutesMeta,
        remindMinutes.isAcceptableOrUnknown(
          data['remind_minutes']!,
          _remindMinutesMeta,
        ),
      );
    }
    if (data.containsKey('sort_key')) {
      context.handle(
        _sortKeyMeta,
        sortKey.isAcceptableOrUnknown(data['sort_key']!, _sortKeyMeta),
      );
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TaskRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TaskRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      notes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes'],
      )!,
      priority: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}priority'],
      )!,
      dueAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}due_at'],
      ),
      dueHasTime: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}due_has_time'],
      )!,
      plannedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}planned_at'],
      ),
      plannedMinutes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}planned_minutes'],
      ),
      doneAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}done_at'],
      ),
      rrule: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}rrule'],
      )!,
      remindMinutes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}remind_minutes'],
      ),
      sortKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sort_key'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}deleted_at'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $TasksTable createAlias(String alias) {
    return $TasksTable(attachedDatabase, alias);
  }
}

class TaskRow extends DataClass implements Insertable<TaskRow> {
  final String id;
  final String title;
  final String notes;

  /// '', 'low', 'medium' or 'high'.
  final String priority;

  /// Due date/time, epoch ms. For date-only tasks this is local midnight and [dueHasTime] is 0.
  final int? dueAt;
  final int dueHasTime;

  /// Time block: when the user plans to work on it, and for how long.
  final int? plannedAt;
  final int? plannedMinutes;
  final int? doneAt;

  /// Recurrence rule, e.g. `FREQ=WEEKLY;BYDAY=MO,WE` ('' = does not repeat). See planner/recurrence.dart.
  final String rrule;

  /// Remind this many minutes before the due/planned time (null = no reminder).
  final int? remindMinutes;
  final String sortKey;
  final int? deletedAt;
  final int createdAt;
  const TaskRow({
    required this.id,
    required this.title,
    required this.notes,
    required this.priority,
    this.dueAt,
    required this.dueHasTime,
    this.plannedAt,
    this.plannedMinutes,
    this.doneAt,
    required this.rrule,
    this.remindMinutes,
    required this.sortKey,
    this.deletedAt,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['title'] = Variable<String>(title);
    map['notes'] = Variable<String>(notes);
    map['priority'] = Variable<String>(priority);
    if (!nullToAbsent || dueAt != null) {
      map['due_at'] = Variable<int>(dueAt);
    }
    map['due_has_time'] = Variable<int>(dueHasTime);
    if (!nullToAbsent || plannedAt != null) {
      map['planned_at'] = Variable<int>(plannedAt);
    }
    if (!nullToAbsent || plannedMinutes != null) {
      map['planned_minutes'] = Variable<int>(plannedMinutes);
    }
    if (!nullToAbsent || doneAt != null) {
      map['done_at'] = Variable<int>(doneAt);
    }
    map['rrule'] = Variable<String>(rrule);
    if (!nullToAbsent || remindMinutes != null) {
      map['remind_minutes'] = Variable<int>(remindMinutes);
    }
    map['sort_key'] = Variable<String>(sortKey);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<int>(deletedAt);
    }
    map['created_at'] = Variable<int>(createdAt);
    return map;
  }

  TasksCompanion toCompanion(bool nullToAbsent) {
    return TasksCompanion(
      id: Value(id),
      title: Value(title),
      notes: Value(notes),
      priority: Value(priority),
      dueAt: dueAt == null && nullToAbsent
          ? const Value.absent()
          : Value(dueAt),
      dueHasTime: Value(dueHasTime),
      plannedAt: plannedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(plannedAt),
      plannedMinutes: plannedMinutes == null && nullToAbsent
          ? const Value.absent()
          : Value(plannedMinutes),
      doneAt: doneAt == null && nullToAbsent
          ? const Value.absent()
          : Value(doneAt),
      rrule: Value(rrule),
      remindMinutes: remindMinutes == null && nullToAbsent
          ? const Value.absent()
          : Value(remindMinutes),
      sortKey: Value(sortKey),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      createdAt: Value(createdAt),
    );
  }

  factory TaskRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TaskRow(
      id: serializer.fromJson<String>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      notes: serializer.fromJson<String>(json['notes']),
      priority: serializer.fromJson<String>(json['priority']),
      dueAt: serializer.fromJson<int?>(json['dueAt']),
      dueHasTime: serializer.fromJson<int>(json['dueHasTime']),
      plannedAt: serializer.fromJson<int?>(json['plannedAt']),
      plannedMinutes: serializer.fromJson<int?>(json['plannedMinutes']),
      doneAt: serializer.fromJson<int?>(json['doneAt']),
      rrule: serializer.fromJson<String>(json['rrule']),
      remindMinutes: serializer.fromJson<int?>(json['remindMinutes']),
      sortKey: serializer.fromJson<String>(json['sortKey']),
      deletedAt: serializer.fromJson<int?>(json['deletedAt']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'title': serializer.toJson<String>(title),
      'notes': serializer.toJson<String>(notes),
      'priority': serializer.toJson<String>(priority),
      'dueAt': serializer.toJson<int?>(dueAt),
      'dueHasTime': serializer.toJson<int>(dueHasTime),
      'plannedAt': serializer.toJson<int?>(plannedAt),
      'plannedMinutes': serializer.toJson<int?>(plannedMinutes),
      'doneAt': serializer.toJson<int?>(doneAt),
      'rrule': serializer.toJson<String>(rrule),
      'remindMinutes': serializer.toJson<int?>(remindMinutes),
      'sortKey': serializer.toJson<String>(sortKey),
      'deletedAt': serializer.toJson<int?>(deletedAt),
      'createdAt': serializer.toJson<int>(createdAt),
    };
  }

  TaskRow copyWith({
    String? id,
    String? title,
    String? notes,
    String? priority,
    Value<int?> dueAt = const Value.absent(),
    int? dueHasTime,
    Value<int?> plannedAt = const Value.absent(),
    Value<int?> plannedMinutes = const Value.absent(),
    Value<int?> doneAt = const Value.absent(),
    String? rrule,
    Value<int?> remindMinutes = const Value.absent(),
    String? sortKey,
    Value<int?> deletedAt = const Value.absent(),
    int? createdAt,
  }) => TaskRow(
    id: id ?? this.id,
    title: title ?? this.title,
    notes: notes ?? this.notes,
    priority: priority ?? this.priority,
    dueAt: dueAt.present ? dueAt.value : this.dueAt,
    dueHasTime: dueHasTime ?? this.dueHasTime,
    plannedAt: plannedAt.present ? plannedAt.value : this.plannedAt,
    plannedMinutes: plannedMinutes.present
        ? plannedMinutes.value
        : this.plannedMinutes,
    doneAt: doneAt.present ? doneAt.value : this.doneAt,
    rrule: rrule ?? this.rrule,
    remindMinutes: remindMinutes.present
        ? remindMinutes.value
        : this.remindMinutes,
    sortKey: sortKey ?? this.sortKey,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    createdAt: createdAt ?? this.createdAt,
  );
  TaskRow copyWithCompanion(TasksCompanion data) {
    return TaskRow(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      notes: data.notes.present ? data.notes.value : this.notes,
      priority: data.priority.present ? data.priority.value : this.priority,
      dueAt: data.dueAt.present ? data.dueAt.value : this.dueAt,
      dueHasTime: data.dueHasTime.present
          ? data.dueHasTime.value
          : this.dueHasTime,
      plannedAt: data.plannedAt.present ? data.plannedAt.value : this.plannedAt,
      plannedMinutes: data.plannedMinutes.present
          ? data.plannedMinutes.value
          : this.plannedMinutes,
      doneAt: data.doneAt.present ? data.doneAt.value : this.doneAt,
      rrule: data.rrule.present ? data.rrule.value : this.rrule,
      remindMinutes: data.remindMinutes.present
          ? data.remindMinutes.value
          : this.remindMinutes,
      sortKey: data.sortKey.present ? data.sortKey.value : this.sortKey,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TaskRow(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('notes: $notes, ')
          ..write('priority: $priority, ')
          ..write('dueAt: $dueAt, ')
          ..write('dueHasTime: $dueHasTime, ')
          ..write('plannedAt: $plannedAt, ')
          ..write('plannedMinutes: $plannedMinutes, ')
          ..write('doneAt: $doneAt, ')
          ..write('rrule: $rrule, ')
          ..write('remindMinutes: $remindMinutes, ')
          ..write('sortKey: $sortKey, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    title,
    notes,
    priority,
    dueAt,
    dueHasTime,
    plannedAt,
    plannedMinutes,
    doneAt,
    rrule,
    remindMinutes,
    sortKey,
    deletedAt,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TaskRow &&
          other.id == this.id &&
          other.title == this.title &&
          other.notes == this.notes &&
          other.priority == this.priority &&
          other.dueAt == this.dueAt &&
          other.dueHasTime == this.dueHasTime &&
          other.plannedAt == this.plannedAt &&
          other.plannedMinutes == this.plannedMinutes &&
          other.doneAt == this.doneAt &&
          other.rrule == this.rrule &&
          other.remindMinutes == this.remindMinutes &&
          other.sortKey == this.sortKey &&
          other.deletedAt == this.deletedAt &&
          other.createdAt == this.createdAt);
}

class TasksCompanion extends UpdateCompanion<TaskRow> {
  final Value<String> id;
  final Value<String> title;
  final Value<String> notes;
  final Value<String> priority;
  final Value<int?> dueAt;
  final Value<int> dueHasTime;
  final Value<int?> plannedAt;
  final Value<int?> plannedMinutes;
  final Value<int?> doneAt;
  final Value<String> rrule;
  final Value<int?> remindMinutes;
  final Value<String> sortKey;
  final Value<int?> deletedAt;
  final Value<int> createdAt;
  final Value<int> rowid;
  const TasksCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.notes = const Value.absent(),
    this.priority = const Value.absent(),
    this.dueAt = const Value.absent(),
    this.dueHasTime = const Value.absent(),
    this.plannedAt = const Value.absent(),
    this.plannedMinutes = const Value.absent(),
    this.doneAt = const Value.absent(),
    this.rrule = const Value.absent(),
    this.remindMinutes = const Value.absent(),
    this.sortKey = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TasksCompanion.insert({
    required String id,
    this.title = const Value.absent(),
    this.notes = const Value.absent(),
    this.priority = const Value.absent(),
    this.dueAt = const Value.absent(),
    this.dueHasTime = const Value.absent(),
    this.plannedAt = const Value.absent(),
    this.plannedMinutes = const Value.absent(),
    this.doneAt = const Value.absent(),
    this.rrule = const Value.absent(),
    this.remindMinutes = const Value.absent(),
    this.sortKey = const Value.absent(),
    this.deletedAt = const Value.absent(),
    required int createdAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       createdAt = Value(createdAt);
  static Insertable<TaskRow> custom({
    Expression<String>? id,
    Expression<String>? title,
    Expression<String>? notes,
    Expression<String>? priority,
    Expression<int>? dueAt,
    Expression<int>? dueHasTime,
    Expression<int>? plannedAt,
    Expression<int>? plannedMinutes,
    Expression<int>? doneAt,
    Expression<String>? rrule,
    Expression<int>? remindMinutes,
    Expression<String>? sortKey,
    Expression<int>? deletedAt,
    Expression<int>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (notes != null) 'notes': notes,
      if (priority != null) 'priority': priority,
      if (dueAt != null) 'due_at': dueAt,
      if (dueHasTime != null) 'due_has_time': dueHasTime,
      if (plannedAt != null) 'planned_at': plannedAt,
      if (plannedMinutes != null) 'planned_minutes': plannedMinutes,
      if (doneAt != null) 'done_at': doneAt,
      if (rrule != null) 'rrule': rrule,
      if (remindMinutes != null) 'remind_minutes': remindMinutes,
      if (sortKey != null) 'sort_key': sortKey,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TasksCompanion copyWith({
    Value<String>? id,
    Value<String>? title,
    Value<String>? notes,
    Value<String>? priority,
    Value<int?>? dueAt,
    Value<int>? dueHasTime,
    Value<int?>? plannedAt,
    Value<int?>? plannedMinutes,
    Value<int?>? doneAt,
    Value<String>? rrule,
    Value<int?>? remindMinutes,
    Value<String>? sortKey,
    Value<int?>? deletedAt,
    Value<int>? createdAt,
    Value<int>? rowid,
  }) {
    return TasksCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      notes: notes ?? this.notes,
      priority: priority ?? this.priority,
      dueAt: dueAt ?? this.dueAt,
      dueHasTime: dueHasTime ?? this.dueHasTime,
      plannedAt: plannedAt ?? this.plannedAt,
      plannedMinutes: plannedMinutes ?? this.plannedMinutes,
      doneAt: doneAt ?? this.doneAt,
      rrule: rrule ?? this.rrule,
      remindMinutes: remindMinutes ?? this.remindMinutes,
      sortKey: sortKey ?? this.sortKey,
      deletedAt: deletedAt ?? this.deletedAt,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (priority.present) {
      map['priority'] = Variable<String>(priority.value);
    }
    if (dueAt.present) {
      map['due_at'] = Variable<int>(dueAt.value);
    }
    if (dueHasTime.present) {
      map['due_has_time'] = Variable<int>(dueHasTime.value);
    }
    if (plannedAt.present) {
      map['planned_at'] = Variable<int>(plannedAt.value);
    }
    if (plannedMinutes.present) {
      map['planned_minutes'] = Variable<int>(plannedMinutes.value);
    }
    if (doneAt.present) {
      map['done_at'] = Variable<int>(doneAt.value);
    }
    if (rrule.present) {
      map['rrule'] = Variable<String>(rrule.value);
    }
    if (remindMinutes.present) {
      map['remind_minutes'] = Variable<int>(remindMinutes.value);
    }
    if (sortKey.present) {
      map['sort_key'] = Variable<String>(sortKey.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<int>(deletedAt.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TasksCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('notes: $notes, ')
          ..write('priority: $priority, ')
          ..write('dueAt: $dueAt, ')
          ..write('dueHasTime: $dueHasTime, ')
          ..write('plannedAt: $plannedAt, ')
          ..write('plannedMinutes: $plannedMinutes, ')
          ..write('doneAt: $doneAt, ')
          ..write('rrule: $rrule, ')
          ..write('remindMinutes: $remindMinutes, ')
          ..write('sortKey: $sortKey, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $EventsTable extends Events with TableInfo<$EventsTable, EventRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $EventsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
    'notes',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _startAtMeta = const VerificationMeta(
    'startAt',
  );
  @override
  late final GeneratedColumn<int> startAt = GeneratedColumn<int>(
    'start_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _endAtMeta = const VerificationMeta('endAt');
  @override
  late final GeneratedColumn<int> endAt = GeneratedColumn<int>(
    'end_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _allDayMeta = const VerificationMeta('allDay');
  @override
  late final GeneratedColumn<int> allDay = GeneratedColumn<int>(
    'all_day',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _rruleMeta = const VerificationMeta('rrule');
  @override
  late final GeneratedColumn<String> rrule = GeneratedColumn<String>(
    'rrule',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _remindMinutesMeta = const VerificationMeta(
    'remindMinutes',
  );
  @override
  late final GeneratedColumn<int> remindMinutes = GeneratedColumn<int>(
    'remind_minutes',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _colorMeta = const VerificationMeta('color');
  @override
  late final GeneratedColumn<String> color = GeneratedColumn<String>(
    'color',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<int> deletedAt = GeneratedColumn<int>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    title,
    notes,
    startAt,
    endAt,
    allDay,
    rrule,
    remindMinutes,
    color,
    deletedAt,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'events';
  @override
  VerificationContext validateIntegrity(
    Insertable<EventRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    }
    if (data.containsKey('notes')) {
      context.handle(
        _notesMeta,
        notes.isAcceptableOrUnknown(data['notes']!, _notesMeta),
      );
    }
    if (data.containsKey('start_at')) {
      context.handle(
        _startAtMeta,
        startAt.isAcceptableOrUnknown(data['start_at']!, _startAtMeta),
      );
    }
    if (data.containsKey('end_at')) {
      context.handle(
        _endAtMeta,
        endAt.isAcceptableOrUnknown(data['end_at']!, _endAtMeta),
      );
    }
    if (data.containsKey('all_day')) {
      context.handle(
        _allDayMeta,
        allDay.isAcceptableOrUnknown(data['all_day']!, _allDayMeta),
      );
    }
    if (data.containsKey('rrule')) {
      context.handle(
        _rruleMeta,
        rrule.isAcceptableOrUnknown(data['rrule']!, _rruleMeta),
      );
    }
    if (data.containsKey('remind_minutes')) {
      context.handle(
        _remindMinutesMeta,
        remindMinutes.isAcceptableOrUnknown(
          data['remind_minutes']!,
          _remindMinutesMeta,
        ),
      );
    }
    if (data.containsKey('color')) {
      context.handle(
        _colorMeta,
        color.isAcceptableOrUnknown(data['color']!, _colorMeta),
      );
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  EventRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return EventRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      notes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes'],
      )!,
      startAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}start_at'],
      )!,
      endAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}end_at'],
      )!,
      allDay: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}all_day'],
      )!,
      rrule: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}rrule'],
      )!,
      remindMinutes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}remind_minutes'],
      ),
      color: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}color'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}deleted_at'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $EventsTable createAlias(String alias) {
    return $EventsTable(attachedDatabase, alias);
  }
}

class EventRow extends DataClass implements Insertable<EventRow> {
  final String id;
  final String title;
  final String notes;
  final int startAt;
  final int endAt;

  /// 1 = all-day (start is local midnight, end is the exclusive next midnight).
  final int allDay;
  final String rrule;
  final int? remindMinutes;
  final String color;
  final int? deletedAt;
  final int createdAt;
  const EventRow({
    required this.id,
    required this.title,
    required this.notes,
    required this.startAt,
    required this.endAt,
    required this.allDay,
    required this.rrule,
    this.remindMinutes,
    required this.color,
    this.deletedAt,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['title'] = Variable<String>(title);
    map['notes'] = Variable<String>(notes);
    map['start_at'] = Variable<int>(startAt);
    map['end_at'] = Variable<int>(endAt);
    map['all_day'] = Variable<int>(allDay);
    map['rrule'] = Variable<String>(rrule);
    if (!nullToAbsent || remindMinutes != null) {
      map['remind_minutes'] = Variable<int>(remindMinutes);
    }
    map['color'] = Variable<String>(color);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<int>(deletedAt);
    }
    map['created_at'] = Variable<int>(createdAt);
    return map;
  }

  EventsCompanion toCompanion(bool nullToAbsent) {
    return EventsCompanion(
      id: Value(id),
      title: Value(title),
      notes: Value(notes),
      startAt: Value(startAt),
      endAt: Value(endAt),
      allDay: Value(allDay),
      rrule: Value(rrule),
      remindMinutes: remindMinutes == null && nullToAbsent
          ? const Value.absent()
          : Value(remindMinutes),
      color: Value(color),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      createdAt: Value(createdAt),
    );
  }

  factory EventRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return EventRow(
      id: serializer.fromJson<String>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      notes: serializer.fromJson<String>(json['notes']),
      startAt: serializer.fromJson<int>(json['startAt']),
      endAt: serializer.fromJson<int>(json['endAt']),
      allDay: serializer.fromJson<int>(json['allDay']),
      rrule: serializer.fromJson<String>(json['rrule']),
      remindMinutes: serializer.fromJson<int?>(json['remindMinutes']),
      color: serializer.fromJson<String>(json['color']),
      deletedAt: serializer.fromJson<int?>(json['deletedAt']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'title': serializer.toJson<String>(title),
      'notes': serializer.toJson<String>(notes),
      'startAt': serializer.toJson<int>(startAt),
      'endAt': serializer.toJson<int>(endAt),
      'allDay': serializer.toJson<int>(allDay),
      'rrule': serializer.toJson<String>(rrule),
      'remindMinutes': serializer.toJson<int?>(remindMinutes),
      'color': serializer.toJson<String>(color),
      'deletedAt': serializer.toJson<int?>(deletedAt),
      'createdAt': serializer.toJson<int>(createdAt),
    };
  }

  EventRow copyWith({
    String? id,
    String? title,
    String? notes,
    int? startAt,
    int? endAt,
    int? allDay,
    String? rrule,
    Value<int?> remindMinutes = const Value.absent(),
    String? color,
    Value<int?> deletedAt = const Value.absent(),
    int? createdAt,
  }) => EventRow(
    id: id ?? this.id,
    title: title ?? this.title,
    notes: notes ?? this.notes,
    startAt: startAt ?? this.startAt,
    endAt: endAt ?? this.endAt,
    allDay: allDay ?? this.allDay,
    rrule: rrule ?? this.rrule,
    remindMinutes: remindMinutes.present
        ? remindMinutes.value
        : this.remindMinutes,
    color: color ?? this.color,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    createdAt: createdAt ?? this.createdAt,
  );
  EventRow copyWithCompanion(EventsCompanion data) {
    return EventRow(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      notes: data.notes.present ? data.notes.value : this.notes,
      startAt: data.startAt.present ? data.startAt.value : this.startAt,
      endAt: data.endAt.present ? data.endAt.value : this.endAt,
      allDay: data.allDay.present ? data.allDay.value : this.allDay,
      rrule: data.rrule.present ? data.rrule.value : this.rrule,
      remindMinutes: data.remindMinutes.present
          ? data.remindMinutes.value
          : this.remindMinutes,
      color: data.color.present ? data.color.value : this.color,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('EventRow(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('notes: $notes, ')
          ..write('startAt: $startAt, ')
          ..write('endAt: $endAt, ')
          ..write('allDay: $allDay, ')
          ..write('rrule: $rrule, ')
          ..write('remindMinutes: $remindMinutes, ')
          ..write('color: $color, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    title,
    notes,
    startAt,
    endAt,
    allDay,
    rrule,
    remindMinutes,
    color,
    deletedAt,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is EventRow &&
          other.id == this.id &&
          other.title == this.title &&
          other.notes == this.notes &&
          other.startAt == this.startAt &&
          other.endAt == this.endAt &&
          other.allDay == this.allDay &&
          other.rrule == this.rrule &&
          other.remindMinutes == this.remindMinutes &&
          other.color == this.color &&
          other.deletedAt == this.deletedAt &&
          other.createdAt == this.createdAt);
}

class EventsCompanion extends UpdateCompanion<EventRow> {
  final Value<String> id;
  final Value<String> title;
  final Value<String> notes;
  final Value<int> startAt;
  final Value<int> endAt;
  final Value<int> allDay;
  final Value<String> rrule;
  final Value<int?> remindMinutes;
  final Value<String> color;
  final Value<int?> deletedAt;
  final Value<int> createdAt;
  final Value<int> rowid;
  const EventsCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.notes = const Value.absent(),
    this.startAt = const Value.absent(),
    this.endAt = const Value.absent(),
    this.allDay = const Value.absent(),
    this.rrule = const Value.absent(),
    this.remindMinutes = const Value.absent(),
    this.color = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  EventsCompanion.insert({
    required String id,
    this.title = const Value.absent(),
    this.notes = const Value.absent(),
    this.startAt = const Value.absent(),
    this.endAt = const Value.absent(),
    this.allDay = const Value.absent(),
    this.rrule = const Value.absent(),
    this.remindMinutes = const Value.absent(),
    this.color = const Value.absent(),
    this.deletedAt = const Value.absent(),
    required int createdAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       createdAt = Value(createdAt);
  static Insertable<EventRow> custom({
    Expression<String>? id,
    Expression<String>? title,
    Expression<String>? notes,
    Expression<int>? startAt,
    Expression<int>? endAt,
    Expression<int>? allDay,
    Expression<String>? rrule,
    Expression<int>? remindMinutes,
    Expression<String>? color,
    Expression<int>? deletedAt,
    Expression<int>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (notes != null) 'notes': notes,
      if (startAt != null) 'start_at': startAt,
      if (endAt != null) 'end_at': endAt,
      if (allDay != null) 'all_day': allDay,
      if (rrule != null) 'rrule': rrule,
      if (remindMinutes != null) 'remind_minutes': remindMinutes,
      if (color != null) 'color': color,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  EventsCompanion copyWith({
    Value<String>? id,
    Value<String>? title,
    Value<String>? notes,
    Value<int>? startAt,
    Value<int>? endAt,
    Value<int>? allDay,
    Value<String>? rrule,
    Value<int?>? remindMinutes,
    Value<String>? color,
    Value<int?>? deletedAt,
    Value<int>? createdAt,
    Value<int>? rowid,
  }) {
    return EventsCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      notes: notes ?? this.notes,
      startAt: startAt ?? this.startAt,
      endAt: endAt ?? this.endAt,
      allDay: allDay ?? this.allDay,
      rrule: rrule ?? this.rrule,
      remindMinutes: remindMinutes ?? this.remindMinutes,
      color: color ?? this.color,
      deletedAt: deletedAt ?? this.deletedAt,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (startAt.present) {
      map['start_at'] = Variable<int>(startAt.value);
    }
    if (endAt.present) {
      map['end_at'] = Variable<int>(endAt.value);
    }
    if (allDay.present) {
      map['all_day'] = Variable<int>(allDay.value);
    }
    if (rrule.present) {
      map['rrule'] = Variable<String>(rrule.value);
    }
    if (remindMinutes.present) {
      map['remind_minutes'] = Variable<int>(remindMinutes.value);
    }
    if (color.present) {
      map['color'] = Variable<String>(color.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<int>(deletedAt.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('EventsCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('notes: $notes, ')
          ..write('startAt: $startAt, ')
          ..write('endAt: $endAt, ')
          ..write('allDay: $allDay, ')
          ..write('rrule: $rrule, ')
          ..write('remindMinutes: $remindMinutes, ')
          ..write('color: $color, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $BooksTable extends Books with TableInfo<$BooksTable, BookRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BooksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _authorMeta = const VerificationMeta('author');
  @override
  late final GeneratedColumn<String> author = GeneratedColumn<String>(
    'author',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _fileNameMeta = const VerificationMeta(
    'fileName',
  );
  @override
  late final GeneratedColumn<String> fileName = GeneratedColumn<String>(
    'file_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _pageCountMeta = const VerificationMeta(
    'pageCount',
  );
  @override
  late final GeneratedColumn<int> pageCount = GeneratedColumn<int>(
    'page_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _sizeBytesMeta = const VerificationMeta(
    'sizeBytes',
  );
  @override
  late final GeneratedColumn<int> sizeBytes = GeneratedColumn<int>(
    'size_bytes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _sha256Meta = const VerificationMeta('sha256');
  @override
  late final GeneratedColumn<String> sha256 = GeneratedColumn<String>(
    'sha256',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _shelfIdMeta = const VerificationMeta(
    'shelfId',
  );
  @override
  late final GeneratedColumn<String> shelfId = GeneratedColumn<String>(
    'shelf_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _favoriteMeta = const VerificationMeta(
    'favorite',
  );
  @override
  late final GeneratedColumn<int> favorite = GeneratedColumn<int>(
    'favorite',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lastPageMeta = const VerificationMeta(
    'lastPage',
  );
  @override
  late final GeneratedColumn<int> lastPage = GeneratedColumn<int>(
    'last_page',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lastOpenedAtMeta = const VerificationMeta(
    'lastOpenedAt',
  );
  @override
  late final GeneratedColumn<int> lastOpenedAt = GeneratedColumn<int>(
    'last_opened_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _addedAtMeta = const VerificationMeta(
    'addedAt',
  );
  @override
  late final GeneratedColumn<int> addedAt = GeneratedColumn<int>(
    'added_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<int> deletedAt = GeneratedColumn<int>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    title,
    author,
    fileName,
    pageCount,
    sizeBytes,
    sha256,
    shelfId,
    favorite,
    lastPage,
    lastOpenedAt,
    addedAt,
    deletedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'books';
  @override
  VerificationContext validateIntegrity(
    Insertable<BookRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    }
    if (data.containsKey('author')) {
      context.handle(
        _authorMeta,
        author.isAcceptableOrUnknown(data['author']!, _authorMeta),
      );
    }
    if (data.containsKey('file_name')) {
      context.handle(
        _fileNameMeta,
        fileName.isAcceptableOrUnknown(data['file_name']!, _fileNameMeta),
      );
    }
    if (data.containsKey('page_count')) {
      context.handle(
        _pageCountMeta,
        pageCount.isAcceptableOrUnknown(data['page_count']!, _pageCountMeta),
      );
    }
    if (data.containsKey('size_bytes')) {
      context.handle(
        _sizeBytesMeta,
        sizeBytes.isAcceptableOrUnknown(data['size_bytes']!, _sizeBytesMeta),
      );
    }
    if (data.containsKey('sha256')) {
      context.handle(
        _sha256Meta,
        sha256.isAcceptableOrUnknown(data['sha256']!, _sha256Meta),
      );
    }
    if (data.containsKey('shelf_id')) {
      context.handle(
        _shelfIdMeta,
        shelfId.isAcceptableOrUnknown(data['shelf_id']!, _shelfIdMeta),
      );
    }
    if (data.containsKey('favorite')) {
      context.handle(
        _favoriteMeta,
        favorite.isAcceptableOrUnknown(data['favorite']!, _favoriteMeta),
      );
    }
    if (data.containsKey('last_page')) {
      context.handle(
        _lastPageMeta,
        lastPage.isAcceptableOrUnknown(data['last_page']!, _lastPageMeta),
      );
    }
    if (data.containsKey('last_opened_at')) {
      context.handle(
        _lastOpenedAtMeta,
        lastOpenedAt.isAcceptableOrUnknown(
          data['last_opened_at']!,
          _lastOpenedAtMeta,
        ),
      );
    }
    if (data.containsKey('added_at')) {
      context.handle(
        _addedAtMeta,
        addedAt.isAcceptableOrUnknown(data['added_at']!, _addedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_addedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  BookRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return BookRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      author: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}author'],
      )!,
      fileName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}file_name'],
      )!,
      pageCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}page_count'],
      )!,
      sizeBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}size_bytes'],
      )!,
      sha256: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sha256'],
      )!,
      shelfId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}shelf_id'],
      ),
      favorite: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}favorite'],
      )!,
      lastPage: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_page'],
      )!,
      lastOpenedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_opened_at'],
      ),
      addedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}added_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}deleted_at'],
      ),
    );
  }

  @override
  $BooksTable createAlias(String alias) {
    return $BooksTable(attachedDatabase, alias);
  }
}

class BookRow extends DataClass implements Insertable<BookRow> {
  final String id;
  final String title;
  final String author;
  final String fileName;
  final int pageCount;
  final int sizeBytes;
  final String sha256;
  final String? shelfId;
  final int favorite;

  /// Last page read (1-based; 0 = never opened).
  final int lastPage;
  final int? lastOpenedAt;
  final int addedAt;
  final int? deletedAt;
  const BookRow({
    required this.id,
    required this.title,
    required this.author,
    required this.fileName,
    required this.pageCount,
    required this.sizeBytes,
    required this.sha256,
    this.shelfId,
    required this.favorite,
    required this.lastPage,
    this.lastOpenedAt,
    required this.addedAt,
    this.deletedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['title'] = Variable<String>(title);
    map['author'] = Variable<String>(author);
    map['file_name'] = Variable<String>(fileName);
    map['page_count'] = Variable<int>(pageCount);
    map['size_bytes'] = Variable<int>(sizeBytes);
    map['sha256'] = Variable<String>(sha256);
    if (!nullToAbsent || shelfId != null) {
      map['shelf_id'] = Variable<String>(shelfId);
    }
    map['favorite'] = Variable<int>(favorite);
    map['last_page'] = Variable<int>(lastPage);
    if (!nullToAbsent || lastOpenedAt != null) {
      map['last_opened_at'] = Variable<int>(lastOpenedAt);
    }
    map['added_at'] = Variable<int>(addedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<int>(deletedAt);
    }
    return map;
  }

  BooksCompanion toCompanion(bool nullToAbsent) {
    return BooksCompanion(
      id: Value(id),
      title: Value(title),
      author: Value(author),
      fileName: Value(fileName),
      pageCount: Value(pageCount),
      sizeBytes: Value(sizeBytes),
      sha256: Value(sha256),
      shelfId: shelfId == null && nullToAbsent
          ? const Value.absent()
          : Value(shelfId),
      favorite: Value(favorite),
      lastPage: Value(lastPage),
      lastOpenedAt: lastOpenedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastOpenedAt),
      addedAt: Value(addedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
    );
  }

  factory BookRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return BookRow(
      id: serializer.fromJson<String>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      author: serializer.fromJson<String>(json['author']),
      fileName: serializer.fromJson<String>(json['fileName']),
      pageCount: serializer.fromJson<int>(json['pageCount']),
      sizeBytes: serializer.fromJson<int>(json['sizeBytes']),
      sha256: serializer.fromJson<String>(json['sha256']),
      shelfId: serializer.fromJson<String?>(json['shelfId']),
      favorite: serializer.fromJson<int>(json['favorite']),
      lastPage: serializer.fromJson<int>(json['lastPage']),
      lastOpenedAt: serializer.fromJson<int?>(json['lastOpenedAt']),
      addedAt: serializer.fromJson<int>(json['addedAt']),
      deletedAt: serializer.fromJson<int?>(json['deletedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'title': serializer.toJson<String>(title),
      'author': serializer.toJson<String>(author),
      'fileName': serializer.toJson<String>(fileName),
      'pageCount': serializer.toJson<int>(pageCount),
      'sizeBytes': serializer.toJson<int>(sizeBytes),
      'sha256': serializer.toJson<String>(sha256),
      'shelfId': serializer.toJson<String?>(shelfId),
      'favorite': serializer.toJson<int>(favorite),
      'lastPage': serializer.toJson<int>(lastPage),
      'lastOpenedAt': serializer.toJson<int?>(lastOpenedAt),
      'addedAt': serializer.toJson<int>(addedAt),
      'deletedAt': serializer.toJson<int?>(deletedAt),
    };
  }

  BookRow copyWith({
    String? id,
    String? title,
    String? author,
    String? fileName,
    int? pageCount,
    int? sizeBytes,
    String? sha256,
    Value<String?> shelfId = const Value.absent(),
    int? favorite,
    int? lastPage,
    Value<int?> lastOpenedAt = const Value.absent(),
    int? addedAt,
    Value<int?> deletedAt = const Value.absent(),
  }) => BookRow(
    id: id ?? this.id,
    title: title ?? this.title,
    author: author ?? this.author,
    fileName: fileName ?? this.fileName,
    pageCount: pageCount ?? this.pageCount,
    sizeBytes: sizeBytes ?? this.sizeBytes,
    sha256: sha256 ?? this.sha256,
    shelfId: shelfId.present ? shelfId.value : this.shelfId,
    favorite: favorite ?? this.favorite,
    lastPage: lastPage ?? this.lastPage,
    lastOpenedAt: lastOpenedAt.present ? lastOpenedAt.value : this.lastOpenedAt,
    addedAt: addedAt ?? this.addedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
  );
  BookRow copyWithCompanion(BooksCompanion data) {
    return BookRow(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      author: data.author.present ? data.author.value : this.author,
      fileName: data.fileName.present ? data.fileName.value : this.fileName,
      pageCount: data.pageCount.present ? data.pageCount.value : this.pageCount,
      sizeBytes: data.sizeBytes.present ? data.sizeBytes.value : this.sizeBytes,
      sha256: data.sha256.present ? data.sha256.value : this.sha256,
      shelfId: data.shelfId.present ? data.shelfId.value : this.shelfId,
      favorite: data.favorite.present ? data.favorite.value : this.favorite,
      lastPage: data.lastPage.present ? data.lastPage.value : this.lastPage,
      lastOpenedAt: data.lastOpenedAt.present
          ? data.lastOpenedAt.value
          : this.lastOpenedAt,
      addedAt: data.addedAt.present ? data.addedAt.value : this.addedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('BookRow(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('author: $author, ')
          ..write('fileName: $fileName, ')
          ..write('pageCount: $pageCount, ')
          ..write('sizeBytes: $sizeBytes, ')
          ..write('sha256: $sha256, ')
          ..write('shelfId: $shelfId, ')
          ..write('favorite: $favorite, ')
          ..write('lastPage: $lastPage, ')
          ..write('lastOpenedAt: $lastOpenedAt, ')
          ..write('addedAt: $addedAt, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    title,
    author,
    fileName,
    pageCount,
    sizeBytes,
    sha256,
    shelfId,
    favorite,
    lastPage,
    lastOpenedAt,
    addedAt,
    deletedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BookRow &&
          other.id == this.id &&
          other.title == this.title &&
          other.author == this.author &&
          other.fileName == this.fileName &&
          other.pageCount == this.pageCount &&
          other.sizeBytes == this.sizeBytes &&
          other.sha256 == this.sha256 &&
          other.shelfId == this.shelfId &&
          other.favorite == this.favorite &&
          other.lastPage == this.lastPage &&
          other.lastOpenedAt == this.lastOpenedAt &&
          other.addedAt == this.addedAt &&
          other.deletedAt == this.deletedAt);
}

class BooksCompanion extends UpdateCompanion<BookRow> {
  final Value<String> id;
  final Value<String> title;
  final Value<String> author;
  final Value<String> fileName;
  final Value<int> pageCount;
  final Value<int> sizeBytes;
  final Value<String> sha256;
  final Value<String?> shelfId;
  final Value<int> favorite;
  final Value<int> lastPage;
  final Value<int?> lastOpenedAt;
  final Value<int> addedAt;
  final Value<int?> deletedAt;
  final Value<int> rowid;
  const BooksCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.author = const Value.absent(),
    this.fileName = const Value.absent(),
    this.pageCount = const Value.absent(),
    this.sizeBytes = const Value.absent(),
    this.sha256 = const Value.absent(),
    this.shelfId = const Value.absent(),
    this.favorite = const Value.absent(),
    this.lastPage = const Value.absent(),
    this.lastOpenedAt = const Value.absent(),
    this.addedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  BooksCompanion.insert({
    required String id,
    this.title = const Value.absent(),
    this.author = const Value.absent(),
    this.fileName = const Value.absent(),
    this.pageCount = const Value.absent(),
    this.sizeBytes = const Value.absent(),
    this.sha256 = const Value.absent(),
    this.shelfId = const Value.absent(),
    this.favorite = const Value.absent(),
    this.lastPage = const Value.absent(),
    this.lastOpenedAt = const Value.absent(),
    required int addedAt,
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       addedAt = Value(addedAt);
  static Insertable<BookRow> custom({
    Expression<String>? id,
    Expression<String>? title,
    Expression<String>? author,
    Expression<String>? fileName,
    Expression<int>? pageCount,
    Expression<int>? sizeBytes,
    Expression<String>? sha256,
    Expression<String>? shelfId,
    Expression<int>? favorite,
    Expression<int>? lastPage,
    Expression<int>? lastOpenedAt,
    Expression<int>? addedAt,
    Expression<int>? deletedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (author != null) 'author': author,
      if (fileName != null) 'file_name': fileName,
      if (pageCount != null) 'page_count': pageCount,
      if (sizeBytes != null) 'size_bytes': sizeBytes,
      if (sha256 != null) 'sha256': sha256,
      if (shelfId != null) 'shelf_id': shelfId,
      if (favorite != null) 'favorite': favorite,
      if (lastPage != null) 'last_page': lastPage,
      if (lastOpenedAt != null) 'last_opened_at': lastOpenedAt,
      if (addedAt != null) 'added_at': addedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  BooksCompanion copyWith({
    Value<String>? id,
    Value<String>? title,
    Value<String>? author,
    Value<String>? fileName,
    Value<int>? pageCount,
    Value<int>? sizeBytes,
    Value<String>? sha256,
    Value<String?>? shelfId,
    Value<int>? favorite,
    Value<int>? lastPage,
    Value<int?>? lastOpenedAt,
    Value<int>? addedAt,
    Value<int?>? deletedAt,
    Value<int>? rowid,
  }) {
    return BooksCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      author: author ?? this.author,
      fileName: fileName ?? this.fileName,
      pageCount: pageCount ?? this.pageCount,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      sha256: sha256 ?? this.sha256,
      shelfId: shelfId ?? this.shelfId,
      favorite: favorite ?? this.favorite,
      lastPage: lastPage ?? this.lastPage,
      lastOpenedAt: lastOpenedAt ?? this.lastOpenedAt,
      addedAt: addedAt ?? this.addedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (author.present) {
      map['author'] = Variable<String>(author.value);
    }
    if (fileName.present) {
      map['file_name'] = Variable<String>(fileName.value);
    }
    if (pageCount.present) {
      map['page_count'] = Variable<int>(pageCount.value);
    }
    if (sizeBytes.present) {
      map['size_bytes'] = Variable<int>(sizeBytes.value);
    }
    if (sha256.present) {
      map['sha256'] = Variable<String>(sha256.value);
    }
    if (shelfId.present) {
      map['shelf_id'] = Variable<String>(shelfId.value);
    }
    if (favorite.present) {
      map['favorite'] = Variable<int>(favorite.value);
    }
    if (lastPage.present) {
      map['last_page'] = Variable<int>(lastPage.value);
    }
    if (lastOpenedAt.present) {
      map['last_opened_at'] = Variable<int>(lastOpenedAt.value);
    }
    if (addedAt.present) {
      map['added_at'] = Variable<int>(addedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<int>(deletedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BooksCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('author: $author, ')
          ..write('fileName: $fileName, ')
          ..write('pageCount: $pageCount, ')
          ..write('sizeBytes: $sizeBytes, ')
          ..write('sha256: $sha256, ')
          ..write('shelfId: $shelfId, ')
          ..write('favorite: $favorite, ')
          ..write('lastPage: $lastPage, ')
          ..write('lastOpenedAt: $lastOpenedAt, ')
          ..write('addedAt: $addedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ShelvesTable extends Shelves with TableInfo<$ShelvesTable, ShelfRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ShelvesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, name, createdAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'shelves';
  @override
  VerificationContext validateIntegrity(
    Insertable<ShelfRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ShelfRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ShelfRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $ShelvesTable createAlias(String alias) {
    return $ShelvesTable(attachedDatabase, alias);
  }
}

class ShelfRow extends DataClass implements Insertable<ShelfRow> {
  final String id;
  final String name;
  final int createdAt;
  const ShelfRow({
    required this.id,
    required this.name,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['created_at'] = Variable<int>(createdAt);
    return map;
  }

  ShelvesCompanion toCompanion(bool nullToAbsent) {
    return ShelvesCompanion(
      id: Value(id),
      name: Value(name),
      createdAt: Value(createdAt),
    );
  }

  factory ShelfRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ShelfRow(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'createdAt': serializer.toJson<int>(createdAt),
    };
  }

  ShelfRow copyWith({String? id, String? name, int? createdAt}) => ShelfRow(
    id: id ?? this.id,
    name: name ?? this.name,
    createdAt: createdAt ?? this.createdAt,
  );
  ShelfRow copyWithCompanion(ShelvesCompanion data) {
    return ShelfRow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ShelfRow(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ShelfRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.createdAt == this.createdAt);
}

class ShelvesCompanion extends UpdateCompanion<ShelfRow> {
  final Value<String> id;
  final Value<String> name;
  final Value<int> createdAt;
  final Value<int> rowid;
  const ShelvesCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ShelvesCompanion.insert({
    required String id,
    required String name,
    required int createdAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       createdAt = Value(createdAt);
  static Insertable<ShelfRow> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<int>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ShelvesCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<int>? createdAt,
    Value<int>? rowid,
  }) {
    return ShelvesCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ShelvesCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $FieldMetaTable extends FieldMeta
    with TableInfo<$FieldMetaTable, FieldMetaData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FieldMetaTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _tblMeta = const VerificationMeta('tbl');
  @override
  late final GeneratedColumn<String> tbl = GeneratedColumn<String>(
    'tbl',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _rowIdMeta = const VerificationMeta('rowId');
  @override
  late final GeneratedColumn<String> rowId = GeneratedColumn<String>(
    'row_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fieldMeta = const VerificationMeta('field');
  @override
  late final GeneratedColumn<String> field = GeneratedColumn<String>(
    'field',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _hlcMeta = const VerificationMeta('hlc');
  @override
  late final GeneratedColumn<String> hlc = GeneratedColumn<String>(
    'hlc',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [tbl, rowId, field, hlc];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'field_meta';
  @override
  VerificationContext validateIntegrity(
    Insertable<FieldMetaData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('tbl')) {
      context.handle(
        _tblMeta,
        tbl.isAcceptableOrUnknown(data['tbl']!, _tblMeta),
      );
    } else if (isInserting) {
      context.missing(_tblMeta);
    }
    if (data.containsKey('row_id')) {
      context.handle(
        _rowIdMeta,
        rowId.isAcceptableOrUnknown(data['row_id']!, _rowIdMeta),
      );
    } else if (isInserting) {
      context.missing(_rowIdMeta);
    }
    if (data.containsKey('field')) {
      context.handle(
        _fieldMeta,
        field.isAcceptableOrUnknown(data['field']!, _fieldMeta),
      );
    } else if (isInserting) {
      context.missing(_fieldMeta);
    }
    if (data.containsKey('hlc')) {
      context.handle(
        _hlcMeta,
        hlc.isAcceptableOrUnknown(data['hlc']!, _hlcMeta),
      );
    } else if (isInserting) {
      context.missing(_hlcMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {tbl, rowId, field};
  @override
  FieldMetaData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FieldMetaData(
      tbl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tbl'],
      )!,
      rowId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}row_id'],
      )!,
      field: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}field'],
      )!,
      hlc: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}hlc'],
      )!,
    );
  }

  @override
  $FieldMetaTable createAlias(String alias) {
    return $FieldMetaTable(attachedDatabase, alias);
  }
}

class FieldMetaData extends DataClass implements Insertable<FieldMetaData> {
  final String tbl;
  final String rowId;
  final String field;
  final String hlc;
  const FieldMetaData({
    required this.tbl,
    required this.rowId,
    required this.field,
    required this.hlc,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['tbl'] = Variable<String>(tbl);
    map['row_id'] = Variable<String>(rowId);
    map['field'] = Variable<String>(field);
    map['hlc'] = Variable<String>(hlc);
    return map;
  }

  FieldMetaCompanion toCompanion(bool nullToAbsent) {
    return FieldMetaCompanion(
      tbl: Value(tbl),
      rowId: Value(rowId),
      field: Value(field),
      hlc: Value(hlc),
    );
  }

  factory FieldMetaData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FieldMetaData(
      tbl: serializer.fromJson<String>(json['tbl']),
      rowId: serializer.fromJson<String>(json['rowId']),
      field: serializer.fromJson<String>(json['field']),
      hlc: serializer.fromJson<String>(json['hlc']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'tbl': serializer.toJson<String>(tbl),
      'rowId': serializer.toJson<String>(rowId),
      'field': serializer.toJson<String>(field),
      'hlc': serializer.toJson<String>(hlc),
    };
  }

  FieldMetaData copyWith({
    String? tbl,
    String? rowId,
    String? field,
    String? hlc,
  }) => FieldMetaData(
    tbl: tbl ?? this.tbl,
    rowId: rowId ?? this.rowId,
    field: field ?? this.field,
    hlc: hlc ?? this.hlc,
  );
  FieldMetaData copyWithCompanion(FieldMetaCompanion data) {
    return FieldMetaData(
      tbl: data.tbl.present ? data.tbl.value : this.tbl,
      rowId: data.rowId.present ? data.rowId.value : this.rowId,
      field: data.field.present ? data.field.value : this.field,
      hlc: data.hlc.present ? data.hlc.value : this.hlc,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FieldMetaData(')
          ..write('tbl: $tbl, ')
          ..write('rowId: $rowId, ')
          ..write('field: $field, ')
          ..write('hlc: $hlc')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(tbl, rowId, field, hlc);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FieldMetaData &&
          other.tbl == this.tbl &&
          other.rowId == this.rowId &&
          other.field == this.field &&
          other.hlc == this.hlc);
}

class FieldMetaCompanion extends UpdateCompanion<FieldMetaData> {
  final Value<String> tbl;
  final Value<String> rowId;
  final Value<String> field;
  final Value<String> hlc;
  final Value<int> rowid;
  const FieldMetaCompanion({
    this.tbl = const Value.absent(),
    this.rowId = const Value.absent(),
    this.field = const Value.absent(),
    this.hlc = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FieldMetaCompanion.insert({
    required String tbl,
    required String rowId,
    required String field,
    required String hlc,
    this.rowid = const Value.absent(),
  }) : tbl = Value(tbl),
       rowId = Value(rowId),
       field = Value(field),
       hlc = Value(hlc);
  static Insertable<FieldMetaData> custom({
    Expression<String>? tbl,
    Expression<String>? rowId,
    Expression<String>? field,
    Expression<String>? hlc,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (tbl != null) 'tbl': tbl,
      if (rowId != null) 'row_id': rowId,
      if (field != null) 'field': field,
      if (hlc != null) 'hlc': hlc,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FieldMetaCompanion copyWith({
    Value<String>? tbl,
    Value<String>? rowId,
    Value<String>? field,
    Value<String>? hlc,
    Value<int>? rowid,
  }) {
    return FieldMetaCompanion(
      tbl: tbl ?? this.tbl,
      rowId: rowId ?? this.rowId,
      field: field ?? this.field,
      hlc: hlc ?? this.hlc,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (tbl.present) {
      map['tbl'] = Variable<String>(tbl.value);
    }
    if (rowId.present) {
      map['row_id'] = Variable<String>(rowId.value);
    }
    if (field.present) {
      map['field'] = Variable<String>(field.value);
    }
    if (hlc.present) {
      map['hlc'] = Variable<String>(hlc.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FieldMetaCompanion(')
          ..write('tbl: $tbl, ')
          ..write('rowId: $rowId, ')
          ..write('field: $field, ')
          ..write('hlc: $hlc, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncOutboxTable extends SyncOutbox
    with TableInfo<$SyncOutboxTable, SyncOutboxData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncOutboxTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _tblMeta = const VerificationMeta('tbl');
  @override
  late final GeneratedColumn<String> tbl = GeneratedColumn<String>(
    'tbl',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _rowIdMeta = const VerificationMeta('rowId');
  @override
  late final GeneratedColumn<String> rowId = GeneratedColumn<String>(
    'row_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fieldMeta = const VerificationMeta('field');
  @override
  late final GeneratedColumn<String> field = GeneratedColumn<String>(
    'field',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueJsonMeta = const VerificationMeta(
    'valueJson',
  );
  @override
  late final GeneratedColumn<String> valueJson = GeneratedColumn<String>(
    'value_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _hlcMeta = const VerificationMeta('hlc');
  @override
  late final GeneratedColumn<String> hlc = GeneratedColumn<String>(
    'hlc',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _baseHlcMeta = const VerificationMeta(
    'baseHlc',
  );
  @override
  late final GeneratedColumn<String> baseHlc = GeneratedColumn<String>(
    'base_hlc',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _changeIdMeta = const VerificationMeta(
    'changeId',
  );
  @override
  late final GeneratedColumn<String> changeId = GeneratedColumn<String>(
    'change_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _attemptsMeta = const VerificationMeta(
    'attempts',
  );
  @override
  late final GeneratedColumn<int> attempts = GeneratedColumn<int>(
    'attempts',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lastErrorMeta = const VerificationMeta(
    'lastError',
  );
  @override
  late final GeneratedColumn<String> lastError = GeneratedColumn<String>(
    'last_error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    tbl,
    rowId,
    field,
    valueJson,
    hlc,
    baseHlc,
    changeId,
    attempts,
    lastError,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_outbox';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncOutboxData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('tbl')) {
      context.handle(
        _tblMeta,
        tbl.isAcceptableOrUnknown(data['tbl']!, _tblMeta),
      );
    } else if (isInserting) {
      context.missing(_tblMeta);
    }
    if (data.containsKey('row_id')) {
      context.handle(
        _rowIdMeta,
        rowId.isAcceptableOrUnknown(data['row_id']!, _rowIdMeta),
      );
    } else if (isInserting) {
      context.missing(_rowIdMeta);
    }
    if (data.containsKey('field')) {
      context.handle(
        _fieldMeta,
        field.isAcceptableOrUnknown(data['field']!, _fieldMeta),
      );
    } else if (isInserting) {
      context.missing(_fieldMeta);
    }
    if (data.containsKey('value_json')) {
      context.handle(
        _valueJsonMeta,
        valueJson.isAcceptableOrUnknown(data['value_json']!, _valueJsonMeta),
      );
    }
    if (data.containsKey('hlc')) {
      context.handle(
        _hlcMeta,
        hlc.isAcceptableOrUnknown(data['hlc']!, _hlcMeta),
      );
    } else if (isInserting) {
      context.missing(_hlcMeta);
    }
    if (data.containsKey('base_hlc')) {
      context.handle(
        _baseHlcMeta,
        baseHlc.isAcceptableOrUnknown(data['base_hlc']!, _baseHlcMeta),
      );
    }
    if (data.containsKey('change_id')) {
      context.handle(
        _changeIdMeta,
        changeId.isAcceptableOrUnknown(data['change_id']!, _changeIdMeta),
      );
    } else if (isInserting) {
      context.missing(_changeIdMeta);
    }
    if (data.containsKey('attempts')) {
      context.handle(
        _attemptsMeta,
        attempts.isAcceptableOrUnknown(data['attempts']!, _attemptsMeta),
      );
    }
    if (data.containsKey('last_error')) {
      context.handle(
        _lastErrorMeta,
        lastError.isAcceptableOrUnknown(data['last_error']!, _lastErrorMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SyncOutboxData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncOutboxData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      tbl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tbl'],
      )!,
      rowId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}row_id'],
      )!,
      field: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}field'],
      )!,
      valueJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value_json'],
      ),
      hlc: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}hlc'],
      )!,
      baseHlc: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}base_hlc'],
      ),
      changeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}change_id'],
      )!,
      attempts: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempts'],
      )!,
      lastError: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $SyncOutboxTable createAlias(String alias) {
    return $SyncOutboxTable(attachedDatabase, alias);
  }
}

class SyncOutboxData extends DataClass implements Insertable<SyncOutboxData> {
  final int id;
  final String tbl;
  final String rowId;
  final String field;
  final String? valueJson;
  final String hlc;
  final String? baseHlc;
  final String changeId;
  final int attempts;
  final String? lastError;
  final int createdAt;
  const SyncOutboxData({
    required this.id,
    required this.tbl,
    required this.rowId,
    required this.field,
    this.valueJson,
    required this.hlc,
    this.baseHlc,
    required this.changeId,
    required this.attempts,
    this.lastError,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['tbl'] = Variable<String>(tbl);
    map['row_id'] = Variable<String>(rowId);
    map['field'] = Variable<String>(field);
    if (!nullToAbsent || valueJson != null) {
      map['value_json'] = Variable<String>(valueJson);
    }
    map['hlc'] = Variable<String>(hlc);
    if (!nullToAbsent || baseHlc != null) {
      map['base_hlc'] = Variable<String>(baseHlc);
    }
    map['change_id'] = Variable<String>(changeId);
    map['attempts'] = Variable<int>(attempts);
    if (!nullToAbsent || lastError != null) {
      map['last_error'] = Variable<String>(lastError);
    }
    map['created_at'] = Variable<int>(createdAt);
    return map;
  }

  SyncOutboxCompanion toCompanion(bool nullToAbsent) {
    return SyncOutboxCompanion(
      id: Value(id),
      tbl: Value(tbl),
      rowId: Value(rowId),
      field: Value(field),
      valueJson: valueJson == null && nullToAbsent
          ? const Value.absent()
          : Value(valueJson),
      hlc: Value(hlc),
      baseHlc: baseHlc == null && nullToAbsent
          ? const Value.absent()
          : Value(baseHlc),
      changeId: Value(changeId),
      attempts: Value(attempts),
      lastError: lastError == null && nullToAbsent
          ? const Value.absent()
          : Value(lastError),
      createdAt: Value(createdAt),
    );
  }

  factory SyncOutboxData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncOutboxData(
      id: serializer.fromJson<int>(json['id']),
      tbl: serializer.fromJson<String>(json['tbl']),
      rowId: serializer.fromJson<String>(json['rowId']),
      field: serializer.fromJson<String>(json['field']),
      valueJson: serializer.fromJson<String?>(json['valueJson']),
      hlc: serializer.fromJson<String>(json['hlc']),
      baseHlc: serializer.fromJson<String?>(json['baseHlc']),
      changeId: serializer.fromJson<String>(json['changeId']),
      attempts: serializer.fromJson<int>(json['attempts']),
      lastError: serializer.fromJson<String?>(json['lastError']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'tbl': serializer.toJson<String>(tbl),
      'rowId': serializer.toJson<String>(rowId),
      'field': serializer.toJson<String>(field),
      'valueJson': serializer.toJson<String?>(valueJson),
      'hlc': serializer.toJson<String>(hlc),
      'baseHlc': serializer.toJson<String?>(baseHlc),
      'changeId': serializer.toJson<String>(changeId),
      'attempts': serializer.toJson<int>(attempts),
      'lastError': serializer.toJson<String?>(lastError),
      'createdAt': serializer.toJson<int>(createdAt),
    };
  }

  SyncOutboxData copyWith({
    int? id,
    String? tbl,
    String? rowId,
    String? field,
    Value<String?> valueJson = const Value.absent(),
    String? hlc,
    Value<String?> baseHlc = const Value.absent(),
    String? changeId,
    int? attempts,
    Value<String?> lastError = const Value.absent(),
    int? createdAt,
  }) => SyncOutboxData(
    id: id ?? this.id,
    tbl: tbl ?? this.tbl,
    rowId: rowId ?? this.rowId,
    field: field ?? this.field,
    valueJson: valueJson.present ? valueJson.value : this.valueJson,
    hlc: hlc ?? this.hlc,
    baseHlc: baseHlc.present ? baseHlc.value : this.baseHlc,
    changeId: changeId ?? this.changeId,
    attempts: attempts ?? this.attempts,
    lastError: lastError.present ? lastError.value : this.lastError,
    createdAt: createdAt ?? this.createdAt,
  );
  SyncOutboxData copyWithCompanion(SyncOutboxCompanion data) {
    return SyncOutboxData(
      id: data.id.present ? data.id.value : this.id,
      tbl: data.tbl.present ? data.tbl.value : this.tbl,
      rowId: data.rowId.present ? data.rowId.value : this.rowId,
      field: data.field.present ? data.field.value : this.field,
      valueJson: data.valueJson.present ? data.valueJson.value : this.valueJson,
      hlc: data.hlc.present ? data.hlc.value : this.hlc,
      baseHlc: data.baseHlc.present ? data.baseHlc.value : this.baseHlc,
      changeId: data.changeId.present ? data.changeId.value : this.changeId,
      attempts: data.attempts.present ? data.attempts.value : this.attempts,
      lastError: data.lastError.present ? data.lastError.value : this.lastError,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncOutboxData(')
          ..write('id: $id, ')
          ..write('tbl: $tbl, ')
          ..write('rowId: $rowId, ')
          ..write('field: $field, ')
          ..write('valueJson: $valueJson, ')
          ..write('hlc: $hlc, ')
          ..write('baseHlc: $baseHlc, ')
          ..write('changeId: $changeId, ')
          ..write('attempts: $attempts, ')
          ..write('lastError: $lastError, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    tbl,
    rowId,
    field,
    valueJson,
    hlc,
    baseHlc,
    changeId,
    attempts,
    lastError,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncOutboxData &&
          other.id == this.id &&
          other.tbl == this.tbl &&
          other.rowId == this.rowId &&
          other.field == this.field &&
          other.valueJson == this.valueJson &&
          other.hlc == this.hlc &&
          other.baseHlc == this.baseHlc &&
          other.changeId == this.changeId &&
          other.attempts == this.attempts &&
          other.lastError == this.lastError &&
          other.createdAt == this.createdAt);
}

class SyncOutboxCompanion extends UpdateCompanion<SyncOutboxData> {
  final Value<int> id;
  final Value<String> tbl;
  final Value<String> rowId;
  final Value<String> field;
  final Value<String?> valueJson;
  final Value<String> hlc;
  final Value<String?> baseHlc;
  final Value<String> changeId;
  final Value<int> attempts;
  final Value<String?> lastError;
  final Value<int> createdAt;
  const SyncOutboxCompanion({
    this.id = const Value.absent(),
    this.tbl = const Value.absent(),
    this.rowId = const Value.absent(),
    this.field = const Value.absent(),
    this.valueJson = const Value.absent(),
    this.hlc = const Value.absent(),
    this.baseHlc = const Value.absent(),
    this.changeId = const Value.absent(),
    this.attempts = const Value.absent(),
    this.lastError = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  SyncOutboxCompanion.insert({
    this.id = const Value.absent(),
    required String tbl,
    required String rowId,
    required String field,
    this.valueJson = const Value.absent(),
    required String hlc,
    this.baseHlc = const Value.absent(),
    required String changeId,
    this.attempts = const Value.absent(),
    this.lastError = const Value.absent(),
    required int createdAt,
  }) : tbl = Value(tbl),
       rowId = Value(rowId),
       field = Value(field),
       hlc = Value(hlc),
       changeId = Value(changeId),
       createdAt = Value(createdAt);
  static Insertable<SyncOutboxData> custom({
    Expression<int>? id,
    Expression<String>? tbl,
    Expression<String>? rowId,
    Expression<String>? field,
    Expression<String>? valueJson,
    Expression<String>? hlc,
    Expression<String>? baseHlc,
    Expression<String>? changeId,
    Expression<int>? attempts,
    Expression<String>? lastError,
    Expression<int>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (tbl != null) 'tbl': tbl,
      if (rowId != null) 'row_id': rowId,
      if (field != null) 'field': field,
      if (valueJson != null) 'value_json': valueJson,
      if (hlc != null) 'hlc': hlc,
      if (baseHlc != null) 'base_hlc': baseHlc,
      if (changeId != null) 'change_id': changeId,
      if (attempts != null) 'attempts': attempts,
      if (lastError != null) 'last_error': lastError,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  SyncOutboxCompanion copyWith({
    Value<int>? id,
    Value<String>? tbl,
    Value<String>? rowId,
    Value<String>? field,
    Value<String?>? valueJson,
    Value<String>? hlc,
    Value<String?>? baseHlc,
    Value<String>? changeId,
    Value<int>? attempts,
    Value<String?>? lastError,
    Value<int>? createdAt,
  }) {
    return SyncOutboxCompanion(
      id: id ?? this.id,
      tbl: tbl ?? this.tbl,
      rowId: rowId ?? this.rowId,
      field: field ?? this.field,
      valueJson: valueJson ?? this.valueJson,
      hlc: hlc ?? this.hlc,
      baseHlc: baseHlc ?? this.baseHlc,
      changeId: changeId ?? this.changeId,
      attempts: attempts ?? this.attempts,
      lastError: lastError ?? this.lastError,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (tbl.present) {
      map['tbl'] = Variable<String>(tbl.value);
    }
    if (rowId.present) {
      map['row_id'] = Variable<String>(rowId.value);
    }
    if (field.present) {
      map['field'] = Variable<String>(field.value);
    }
    if (valueJson.present) {
      map['value_json'] = Variable<String>(valueJson.value);
    }
    if (hlc.present) {
      map['hlc'] = Variable<String>(hlc.value);
    }
    if (baseHlc.present) {
      map['base_hlc'] = Variable<String>(baseHlc.value);
    }
    if (changeId.present) {
      map['change_id'] = Variable<String>(changeId.value);
    }
    if (attempts.present) {
      map['attempts'] = Variable<int>(attempts.value);
    }
    if (lastError.present) {
      map['last_error'] = Variable<String>(lastError.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncOutboxCompanion(')
          ..write('id: $id, ')
          ..write('tbl: $tbl, ')
          ..write('rowId: $rowId, ')
          ..write('field: $field, ')
          ..write('valueJson: $valueJson, ')
          ..write('hlc: $hlc, ')
          ..write('baseHlc: $baseHlc, ')
          ..write('changeId: $changeId, ')
          ..write('attempts: $attempts, ')
          ..write('lastError: $lastError, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $SyncStateTable extends SyncState
    with TableInfo<$SyncStateTable, SyncStateData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncStateTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_state';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncStateData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  SyncStateData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncStateData(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  $SyncStateTable createAlias(String alias) {
    return $SyncStateTable(attachedDatabase, alias);
  }
}

class SyncStateData extends DataClass implements Insertable<SyncStateData> {
  final String key;
  final String value;
  const SyncStateData({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  SyncStateCompanion toCompanion(bool nullToAbsent) {
    return SyncStateCompanion(key: Value(key), value: Value(value));
  }

  factory SyncStateData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncStateData(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  SyncStateData copyWith({String? key, String? value}) =>
      SyncStateData(key: key ?? this.key, value: value ?? this.value);
  SyncStateData copyWithCompanion(SyncStateCompanion data) {
    return SyncStateData(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncStateData(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncStateData &&
          other.key == this.key &&
          other.value == this.value);
}

class SyncStateCompanion extends UpdateCompanion<SyncStateData> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const SyncStateCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncStateCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<SyncStateData> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncStateCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return SyncStateCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncStateCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalConflictsTable extends LocalConflicts
    with TableInfo<$LocalConflictsTable, LocalConflict> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalConflictsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _serverIdMeta = const VerificationMeta(
    'serverId',
  );
  @override
  late final GeneratedColumn<int> serverId = GeneratedColumn<int>(
    'server_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _tblMeta = const VerificationMeta('tbl');
  @override
  late final GeneratedColumn<String> tbl = GeneratedColumn<String>(
    'tbl',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _rowIdMeta = const VerificationMeta('rowId');
  @override
  late final GeneratedColumn<String> rowId = GeneratedColumn<String>(
    'row_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fieldMeta = const VerificationMeta('field');
  @override
  late final GeneratedColumn<String> field = GeneratedColumn<String>(
    'field',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lostValueJsonMeta = const VerificationMeta(
    'lostValueJson',
  );
  @override
  late final GeneratedColumn<String> lostValueJson = GeneratedColumn<String>(
    'lost_value_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lostHlcMeta = const VerificationMeta(
    'lostHlc',
  );
  @override
  late final GeneratedColumn<String> lostHlc = GeneratedColumn<String>(
    'lost_hlc',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _winnerHlcMeta = const VerificationMeta(
    'winnerHlc',
  );
  @override
  late final GeneratedColumn<String> winnerHlc = GeneratedColumn<String>(
    'winner_hlc',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _resolvedAtMeta = const VerificationMeta(
    'resolvedAt',
  );
  @override
  late final GeneratedColumn<int> resolvedAt = GeneratedColumn<int>(
    'resolved_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    serverId,
    tbl,
    rowId,
    field,
    lostValueJson,
    lostHlc,
    winnerHlc,
    createdAt,
    resolvedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_conflicts';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalConflict> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('server_id')) {
      context.handle(
        _serverIdMeta,
        serverId.isAcceptableOrUnknown(data['server_id']!, _serverIdMeta),
      );
    }
    if (data.containsKey('tbl')) {
      context.handle(
        _tblMeta,
        tbl.isAcceptableOrUnknown(data['tbl']!, _tblMeta),
      );
    } else if (isInserting) {
      context.missing(_tblMeta);
    }
    if (data.containsKey('row_id')) {
      context.handle(
        _rowIdMeta,
        rowId.isAcceptableOrUnknown(data['row_id']!, _rowIdMeta),
      );
    } else if (isInserting) {
      context.missing(_rowIdMeta);
    }
    if (data.containsKey('field')) {
      context.handle(
        _fieldMeta,
        field.isAcceptableOrUnknown(data['field']!, _fieldMeta),
      );
    } else if (isInserting) {
      context.missing(_fieldMeta);
    }
    if (data.containsKey('lost_value_json')) {
      context.handle(
        _lostValueJsonMeta,
        lostValueJson.isAcceptableOrUnknown(
          data['lost_value_json']!,
          _lostValueJsonMeta,
        ),
      );
    }
    if (data.containsKey('lost_hlc')) {
      context.handle(
        _lostHlcMeta,
        lostHlc.isAcceptableOrUnknown(data['lost_hlc']!, _lostHlcMeta),
      );
    } else if (isInserting) {
      context.missing(_lostHlcMeta);
    }
    if (data.containsKey('winner_hlc')) {
      context.handle(
        _winnerHlcMeta,
        winnerHlc.isAcceptableOrUnknown(data['winner_hlc']!, _winnerHlcMeta),
      );
    } else if (isInserting) {
      context.missing(_winnerHlcMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('resolved_at')) {
      context.handle(
        _resolvedAtMeta,
        resolvedAt.isAcceptableOrUnknown(data['resolved_at']!, _resolvedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LocalConflict map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalConflict(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      serverId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}server_id'],
      ),
      tbl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tbl'],
      )!,
      rowId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}row_id'],
      )!,
      field: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}field'],
      )!,
      lostValueJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}lost_value_json'],
      ),
      lostHlc: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}lost_hlc'],
      )!,
      winnerHlc: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}winner_hlc'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      resolvedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}resolved_at'],
      ),
    );
  }

  @override
  $LocalConflictsTable createAlias(String alias) {
    return $LocalConflictsTable(attachedDatabase, alias);
  }
}

class LocalConflict extends DataClass implements Insertable<LocalConflict> {
  final int id;
  final int? serverId;
  final String tbl;
  final String rowId;
  final String field;
  final String? lostValueJson;
  final String lostHlc;
  final String winnerHlc;
  final int createdAt;
  final int? resolvedAt;
  const LocalConflict({
    required this.id,
    this.serverId,
    required this.tbl,
    required this.rowId,
    required this.field,
    this.lostValueJson,
    required this.lostHlc,
    required this.winnerHlc,
    required this.createdAt,
    this.resolvedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    if (!nullToAbsent || serverId != null) {
      map['server_id'] = Variable<int>(serverId);
    }
    map['tbl'] = Variable<String>(tbl);
    map['row_id'] = Variable<String>(rowId);
    map['field'] = Variable<String>(field);
    if (!nullToAbsent || lostValueJson != null) {
      map['lost_value_json'] = Variable<String>(lostValueJson);
    }
    map['lost_hlc'] = Variable<String>(lostHlc);
    map['winner_hlc'] = Variable<String>(winnerHlc);
    map['created_at'] = Variable<int>(createdAt);
    if (!nullToAbsent || resolvedAt != null) {
      map['resolved_at'] = Variable<int>(resolvedAt);
    }
    return map;
  }

  LocalConflictsCompanion toCompanion(bool nullToAbsent) {
    return LocalConflictsCompanion(
      id: Value(id),
      serverId: serverId == null && nullToAbsent
          ? const Value.absent()
          : Value(serverId),
      tbl: Value(tbl),
      rowId: Value(rowId),
      field: Value(field),
      lostValueJson: lostValueJson == null && nullToAbsent
          ? const Value.absent()
          : Value(lostValueJson),
      lostHlc: Value(lostHlc),
      winnerHlc: Value(winnerHlc),
      createdAt: Value(createdAt),
      resolvedAt: resolvedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(resolvedAt),
    );
  }

  factory LocalConflict.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalConflict(
      id: serializer.fromJson<int>(json['id']),
      serverId: serializer.fromJson<int?>(json['serverId']),
      tbl: serializer.fromJson<String>(json['tbl']),
      rowId: serializer.fromJson<String>(json['rowId']),
      field: serializer.fromJson<String>(json['field']),
      lostValueJson: serializer.fromJson<String?>(json['lostValueJson']),
      lostHlc: serializer.fromJson<String>(json['lostHlc']),
      winnerHlc: serializer.fromJson<String>(json['winnerHlc']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      resolvedAt: serializer.fromJson<int?>(json['resolvedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'serverId': serializer.toJson<int?>(serverId),
      'tbl': serializer.toJson<String>(tbl),
      'rowId': serializer.toJson<String>(rowId),
      'field': serializer.toJson<String>(field),
      'lostValueJson': serializer.toJson<String?>(lostValueJson),
      'lostHlc': serializer.toJson<String>(lostHlc),
      'winnerHlc': serializer.toJson<String>(winnerHlc),
      'createdAt': serializer.toJson<int>(createdAt),
      'resolvedAt': serializer.toJson<int?>(resolvedAt),
    };
  }

  LocalConflict copyWith({
    int? id,
    Value<int?> serverId = const Value.absent(),
    String? tbl,
    String? rowId,
    String? field,
    Value<String?> lostValueJson = const Value.absent(),
    String? lostHlc,
    String? winnerHlc,
    int? createdAt,
    Value<int?> resolvedAt = const Value.absent(),
  }) => LocalConflict(
    id: id ?? this.id,
    serverId: serverId.present ? serverId.value : this.serverId,
    tbl: tbl ?? this.tbl,
    rowId: rowId ?? this.rowId,
    field: field ?? this.field,
    lostValueJson: lostValueJson.present
        ? lostValueJson.value
        : this.lostValueJson,
    lostHlc: lostHlc ?? this.lostHlc,
    winnerHlc: winnerHlc ?? this.winnerHlc,
    createdAt: createdAt ?? this.createdAt,
    resolvedAt: resolvedAt.present ? resolvedAt.value : this.resolvedAt,
  );
  LocalConflict copyWithCompanion(LocalConflictsCompanion data) {
    return LocalConflict(
      id: data.id.present ? data.id.value : this.id,
      serverId: data.serverId.present ? data.serverId.value : this.serverId,
      tbl: data.tbl.present ? data.tbl.value : this.tbl,
      rowId: data.rowId.present ? data.rowId.value : this.rowId,
      field: data.field.present ? data.field.value : this.field,
      lostValueJson: data.lostValueJson.present
          ? data.lostValueJson.value
          : this.lostValueJson,
      lostHlc: data.lostHlc.present ? data.lostHlc.value : this.lostHlc,
      winnerHlc: data.winnerHlc.present ? data.winnerHlc.value : this.winnerHlc,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      resolvedAt: data.resolvedAt.present
          ? data.resolvedAt.value
          : this.resolvedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalConflict(')
          ..write('id: $id, ')
          ..write('serverId: $serverId, ')
          ..write('tbl: $tbl, ')
          ..write('rowId: $rowId, ')
          ..write('field: $field, ')
          ..write('lostValueJson: $lostValueJson, ')
          ..write('lostHlc: $lostHlc, ')
          ..write('winnerHlc: $winnerHlc, ')
          ..write('createdAt: $createdAt, ')
          ..write('resolvedAt: $resolvedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    serverId,
    tbl,
    rowId,
    field,
    lostValueJson,
    lostHlc,
    winnerHlc,
    createdAt,
    resolvedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalConflict &&
          other.id == this.id &&
          other.serverId == this.serverId &&
          other.tbl == this.tbl &&
          other.rowId == this.rowId &&
          other.field == this.field &&
          other.lostValueJson == this.lostValueJson &&
          other.lostHlc == this.lostHlc &&
          other.winnerHlc == this.winnerHlc &&
          other.createdAt == this.createdAt &&
          other.resolvedAt == this.resolvedAt);
}

class LocalConflictsCompanion extends UpdateCompanion<LocalConflict> {
  final Value<int> id;
  final Value<int?> serverId;
  final Value<String> tbl;
  final Value<String> rowId;
  final Value<String> field;
  final Value<String?> lostValueJson;
  final Value<String> lostHlc;
  final Value<String> winnerHlc;
  final Value<int> createdAt;
  final Value<int?> resolvedAt;
  const LocalConflictsCompanion({
    this.id = const Value.absent(),
    this.serverId = const Value.absent(),
    this.tbl = const Value.absent(),
    this.rowId = const Value.absent(),
    this.field = const Value.absent(),
    this.lostValueJson = const Value.absent(),
    this.lostHlc = const Value.absent(),
    this.winnerHlc = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.resolvedAt = const Value.absent(),
  });
  LocalConflictsCompanion.insert({
    this.id = const Value.absent(),
    this.serverId = const Value.absent(),
    required String tbl,
    required String rowId,
    required String field,
    this.lostValueJson = const Value.absent(),
    required String lostHlc,
    required String winnerHlc,
    required int createdAt,
    this.resolvedAt = const Value.absent(),
  }) : tbl = Value(tbl),
       rowId = Value(rowId),
       field = Value(field),
       lostHlc = Value(lostHlc),
       winnerHlc = Value(winnerHlc),
       createdAt = Value(createdAt);
  static Insertable<LocalConflict> custom({
    Expression<int>? id,
    Expression<int>? serverId,
    Expression<String>? tbl,
    Expression<String>? rowId,
    Expression<String>? field,
    Expression<String>? lostValueJson,
    Expression<String>? lostHlc,
    Expression<String>? winnerHlc,
    Expression<int>? createdAt,
    Expression<int>? resolvedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (serverId != null) 'server_id': serverId,
      if (tbl != null) 'tbl': tbl,
      if (rowId != null) 'row_id': rowId,
      if (field != null) 'field': field,
      if (lostValueJson != null) 'lost_value_json': lostValueJson,
      if (lostHlc != null) 'lost_hlc': lostHlc,
      if (winnerHlc != null) 'winner_hlc': winnerHlc,
      if (createdAt != null) 'created_at': createdAt,
      if (resolvedAt != null) 'resolved_at': resolvedAt,
    });
  }

  LocalConflictsCompanion copyWith({
    Value<int>? id,
    Value<int?>? serverId,
    Value<String>? tbl,
    Value<String>? rowId,
    Value<String>? field,
    Value<String?>? lostValueJson,
    Value<String>? lostHlc,
    Value<String>? winnerHlc,
    Value<int>? createdAt,
    Value<int?>? resolvedAt,
  }) {
    return LocalConflictsCompanion(
      id: id ?? this.id,
      serverId: serverId ?? this.serverId,
      tbl: tbl ?? this.tbl,
      rowId: rowId ?? this.rowId,
      field: field ?? this.field,
      lostValueJson: lostValueJson ?? this.lostValueJson,
      lostHlc: lostHlc ?? this.lostHlc,
      winnerHlc: winnerHlc ?? this.winnerHlc,
      createdAt: createdAt ?? this.createdAt,
      resolvedAt: resolvedAt ?? this.resolvedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (serverId.present) {
      map['server_id'] = Variable<int>(serverId.value);
    }
    if (tbl.present) {
      map['tbl'] = Variable<String>(tbl.value);
    }
    if (rowId.present) {
      map['row_id'] = Variable<String>(rowId.value);
    }
    if (field.present) {
      map['field'] = Variable<String>(field.value);
    }
    if (lostValueJson.present) {
      map['lost_value_json'] = Variable<String>(lostValueJson.value);
    }
    if (lostHlc.present) {
      map['lost_hlc'] = Variable<String>(lostHlc.value);
    }
    if (winnerHlc.present) {
      map['winner_hlc'] = Variable<String>(winnerHlc.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (resolvedAt.present) {
      map['resolved_at'] = Variable<int>(resolvedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalConflictsCompanion(')
          ..write('id: $id, ')
          ..write('serverId: $serverId, ')
          ..write('tbl: $tbl, ')
          ..write('rowId: $rowId, ')
          ..write('field: $field, ')
          ..write('lostValueJson: $lostValueJson, ')
          ..write('lostHlc: $lostHlc, ')
          ..write('winnerHlc: $winnerHlc, ')
          ..write('createdAt: $createdAt, ')
          ..write('resolvedAt: $resolvedAt')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $TasksTable tasks = $TasksTable(this);
  late final $EventsTable events = $EventsTable(this);
  late final $BooksTable books = $BooksTable(this);
  late final $ShelvesTable shelves = $ShelvesTable(this);
  late final $FieldMetaTable fieldMeta = $FieldMetaTable(this);
  late final $SyncOutboxTable syncOutbox = $SyncOutboxTable(this);
  late final $SyncStateTable syncState = $SyncStateTable(this);
  late final $LocalConflictsTable localConflicts = $LocalConflictsTable(this);
  late final Index tasksDue = Index(
    'tasks_due',
    'CREATE INDEX tasks_due ON tasks (due_at)',
  );
  late final Index tasksPlanned = Index(
    'tasks_planned',
    'CREATE INDEX tasks_planned ON tasks (planned_at)',
  );
  late final Index eventsStart = Index(
    'events_start',
    'CREATE INDEX events_start ON events (start_at)',
  );
  late final Index booksShelf = Index(
    'books_shelf',
    'CREATE INDEX books_shelf ON books (shelf_id)',
  );
  late final Index booksHash = Index(
    'books_hash',
    'CREATE INDEX books_hash ON books (sha256)',
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    tasks,
    events,
    books,
    shelves,
    fieldMeta,
    syncOutbox,
    syncState,
    localConflicts,
    tasksDue,
    tasksPlanned,
    eventsStart,
    booksShelf,
    booksHash,
  ];
}

typedef $$TasksTableCreateCompanionBuilder = TasksCompanion Function({
  required String id,
  Value<String> title,
  Value<String> notes,
  Value<String> priority,
  Value<int?> dueAt,
  Value<int> dueHasTime,
  Value<int?> plannedAt,
  Value<int?> plannedMinutes,
  Value<int?> doneAt,
  Value<String> rrule,
  Value<int?> remindMinutes,
  Value<String> sortKey,
  Value<int?> deletedAt,
  required int createdAt,
  Value<int> rowid,
});
typedef $$TasksTableUpdateCompanionBuilder = TasksCompanion Function({
  Value<String> id,
  Value<String> title,
  Value<String> notes,
  Value<String> priority,
  Value<int?> dueAt,
  Value<int> dueHasTime,
  Value<int?> plannedAt,
  Value<int?> plannedMinutes,
  Value<int?> doneAt,
  Value<String> rrule,
  Value<int?> remindMinutes,
  Value<String> sortKey,
  Value<int?> deletedAt,
  Value<int> createdAt,
  Value<int> rowid,
});

class $$TasksTableFilterComposer extends Composer<_$AppDatabase, $TasksTable> {
  $$TasksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get priority => $composableBuilder(
    column: $table.priority,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get dueAt => $composableBuilder(
    column: $table.dueAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get dueHasTime => $composableBuilder(
    column: $table.dueHasTime,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get plannedAt => $composableBuilder(
    column: $table.plannedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get plannedMinutes => $composableBuilder(
    column: $table.plannedMinutes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get doneAt => $composableBuilder(
    column: $table.doneAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get rrule => $composableBuilder(
    column: $table.rrule,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get remindMinutes => $composableBuilder(
    column: $table.remindMinutes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sortKey => $composableBuilder(
    column: $table.sortKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$TasksTableOrderingComposer
    extends Composer<_$AppDatabase, $TasksTable> {
  $$TasksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get priority => $composableBuilder(
    column: $table.priority,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get dueAt => $composableBuilder(
    column: $table.dueAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get dueHasTime => $composableBuilder(
    column: $table.dueHasTime,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get plannedAt => $composableBuilder(
    column: $table.plannedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get plannedMinutes => $composableBuilder(
    column: $table.plannedMinutes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get doneAt => $composableBuilder(
    column: $table.doneAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get rrule => $composableBuilder(
    column: $table.rrule,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get remindMinutes => $composableBuilder(
    column: $table.remindMinutes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sortKey => $composableBuilder(
    column: $table.sortKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TasksTableAnnotationComposer
    extends Composer<_$AppDatabase, $TasksTable> {
  $$TasksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumn<String> get priority =>
      $composableBuilder(column: $table.priority, builder: (column) => column);

  GeneratedColumn<int> get dueAt =>
      $composableBuilder(column: $table.dueAt, builder: (column) => column);

  GeneratedColumn<int> get dueHasTime => $composableBuilder(
    column: $table.dueHasTime,
    builder: (column) => column,
  );

  GeneratedColumn<int> get plannedAt =>
      $composableBuilder(column: $table.plannedAt, builder: (column) => column);

  GeneratedColumn<int> get plannedMinutes => $composableBuilder(
    column: $table.plannedMinutes,
    builder: (column) => column,
  );

  GeneratedColumn<int> get doneAt =>
      $composableBuilder(column: $table.doneAt, builder: (column) => column);

  GeneratedColumn<String> get rrule =>
      $composableBuilder(column: $table.rrule, builder: (column) => column);

  GeneratedColumn<int> get remindMinutes => $composableBuilder(
    column: $table.remindMinutes,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sortKey =>
      $composableBuilder(column: $table.sortKey, builder: (column) => column);

  GeneratedColumn<int> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$TasksTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TasksTable,
          TaskRow,
          $$TasksTableFilterComposer,
          $$TasksTableOrderingComposer,
          $$TasksTableAnnotationComposer,
          $$TasksTableCreateCompanionBuilder,
          $$TasksTableUpdateCompanionBuilder,
          (TaskRow, BaseReferences<_$AppDatabase, $TasksTable, TaskRow>),
          TaskRow,
          PrefetchHooks Function()
        > {
  $$TasksTableTableManager(_$AppDatabase db, $TasksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TasksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TasksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TasksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> notes = const Value.absent(),
                Value<String> priority = const Value.absent(),
                Value<int?> dueAt = const Value.absent(),
                Value<int> dueHasTime = const Value.absent(),
                Value<int?> plannedAt = const Value.absent(),
                Value<int?> plannedMinutes = const Value.absent(),
                Value<int?> doneAt = const Value.absent(),
                Value<String> rrule = const Value.absent(),
                Value<int?> remindMinutes = const Value.absent(),
                Value<String> sortKey = const Value.absent(),
                Value<int?> deletedAt = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TasksCompanion(
                id: id,
                title: title,
                notes: notes,
                priority: priority,
                dueAt: dueAt,
                dueHasTime: dueHasTime,
                plannedAt: plannedAt,
                plannedMinutes: plannedMinutes,
                doneAt: doneAt,
                rrule: rrule,
                remindMinutes: remindMinutes,
                sortKey: sortKey,
                deletedAt: deletedAt,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<String> title = const Value.absent(),
                Value<String> notes = const Value.absent(),
                Value<String> priority = const Value.absent(),
                Value<int?> dueAt = const Value.absent(),
                Value<int> dueHasTime = const Value.absent(),
                Value<int?> plannedAt = const Value.absent(),
                Value<int?> plannedMinutes = const Value.absent(),
                Value<int?> doneAt = const Value.absent(),
                Value<String> rrule = const Value.absent(),
                Value<int?> remindMinutes = const Value.absent(),
                Value<String> sortKey = const Value.absent(),
                Value<int?> deletedAt = const Value.absent(),
                required int createdAt,
                Value<int> rowid = const Value.absent(),
              }) => TasksCompanion.insert(
                id: id,
                title: title,
                notes: notes,
                priority: priority,
                dueAt: dueAt,
                dueHasTime: dueHasTime,
                plannedAt: plannedAt,
                plannedMinutes: plannedMinutes,
                doneAt: doneAt,
                rrule: rrule,
                remindMinutes: remindMinutes,
                sortKey: sortKey,
                deletedAt: deletedAt,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$TasksTable, TaskRow>(table),
                  BaseReferences<_$AppDatabase, $TasksTable, TaskRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$TasksTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TasksTable,
      TaskRow,
      $$TasksTableFilterComposer,
      $$TasksTableOrderingComposer,
      $$TasksTableAnnotationComposer,
      $$TasksTableCreateCompanionBuilder,
      $$TasksTableUpdateCompanionBuilder,
      (TaskRow, BaseReferences<_$AppDatabase, $TasksTable, TaskRow>),
      TaskRow,
      PrefetchHooks Function()
    >;
typedef $$EventsTableCreateCompanionBuilder = EventsCompanion Function({
  required String id,
  Value<String> title,
  Value<String> notes,
  Value<int> startAt,
  Value<int> endAt,
  Value<int> allDay,
  Value<String> rrule,
  Value<int?> remindMinutes,
  Value<String> color,
  Value<int?> deletedAt,
  required int createdAt,
  Value<int> rowid,
});
typedef $$EventsTableUpdateCompanionBuilder = EventsCompanion Function({
  Value<String> id,
  Value<String> title,
  Value<String> notes,
  Value<int> startAt,
  Value<int> endAt,
  Value<int> allDay,
  Value<String> rrule,
  Value<int?> remindMinutes,
  Value<String> color,
  Value<int?> deletedAt,
  Value<int> createdAt,
  Value<int> rowid,
});

class $$EventsTableFilterComposer
    extends Composer<_$AppDatabase, $EventsTable> {
  $$EventsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get startAt => $composableBuilder(
    column: $table.startAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get endAt => $composableBuilder(
    column: $table.endAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get allDay => $composableBuilder(
    column: $table.allDay,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get rrule => $composableBuilder(
    column: $table.rrule,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get remindMinutes => $composableBuilder(
    column: $table.remindMinutes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$EventsTableOrderingComposer
    extends Composer<_$AppDatabase, $EventsTable> {
  $$EventsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get startAt => $composableBuilder(
    column: $table.startAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get endAt => $composableBuilder(
    column: $table.endAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get allDay => $composableBuilder(
    column: $table.allDay,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get rrule => $composableBuilder(
    column: $table.rrule,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get remindMinutes => $composableBuilder(
    column: $table.remindMinutes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$EventsTableAnnotationComposer
    extends Composer<_$AppDatabase, $EventsTable> {
  $$EventsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumn<int> get startAt =>
      $composableBuilder(column: $table.startAt, builder: (column) => column);

  GeneratedColumn<int> get endAt =>
      $composableBuilder(column: $table.endAt, builder: (column) => column);

  GeneratedColumn<int> get allDay =>
      $composableBuilder(column: $table.allDay, builder: (column) => column);

  GeneratedColumn<String> get rrule =>
      $composableBuilder(column: $table.rrule, builder: (column) => column);

  GeneratedColumn<int> get remindMinutes => $composableBuilder(
    column: $table.remindMinutes,
    builder: (column) => column,
  );

  GeneratedColumn<String> get color =>
      $composableBuilder(column: $table.color, builder: (column) => column);

  GeneratedColumn<int> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$EventsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $EventsTable,
          EventRow,
          $$EventsTableFilterComposer,
          $$EventsTableOrderingComposer,
          $$EventsTableAnnotationComposer,
          $$EventsTableCreateCompanionBuilder,
          $$EventsTableUpdateCompanionBuilder,
          (EventRow, BaseReferences<_$AppDatabase, $EventsTable, EventRow>),
          EventRow,
          PrefetchHooks Function()
        > {
  $$EventsTableTableManager(_$AppDatabase db, $EventsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$EventsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$EventsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$EventsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> notes = const Value.absent(),
                Value<int> startAt = const Value.absent(),
                Value<int> endAt = const Value.absent(),
                Value<int> allDay = const Value.absent(),
                Value<String> rrule = const Value.absent(),
                Value<int?> remindMinutes = const Value.absent(),
                Value<String> color = const Value.absent(),
                Value<int?> deletedAt = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => EventsCompanion(
                id: id,
                title: title,
                notes: notes,
                startAt: startAt,
                endAt: endAt,
                allDay: allDay,
                rrule: rrule,
                remindMinutes: remindMinutes,
                color: color,
                deletedAt: deletedAt,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<String> title = const Value.absent(),
                Value<String> notes = const Value.absent(),
                Value<int> startAt = const Value.absent(),
                Value<int> endAt = const Value.absent(),
                Value<int> allDay = const Value.absent(),
                Value<String> rrule = const Value.absent(),
                Value<int?> remindMinutes = const Value.absent(),
                Value<String> color = const Value.absent(),
                Value<int?> deletedAt = const Value.absent(),
                required int createdAt,
                Value<int> rowid = const Value.absent(),
              }) => EventsCompanion.insert(
                id: id,
                title: title,
                notes: notes,
                startAt: startAt,
                endAt: endAt,
                allDay: allDay,
                rrule: rrule,
                remindMinutes: remindMinutes,
                color: color,
                deletedAt: deletedAt,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$EventsTable, EventRow>(table),
                  BaseReferences<_$AppDatabase, $EventsTable, EventRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$EventsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $EventsTable,
      EventRow,
      $$EventsTableFilterComposer,
      $$EventsTableOrderingComposer,
      $$EventsTableAnnotationComposer,
      $$EventsTableCreateCompanionBuilder,
      $$EventsTableUpdateCompanionBuilder,
      (EventRow, BaseReferences<_$AppDatabase, $EventsTable, EventRow>),
      EventRow,
      PrefetchHooks Function()
    >;
typedef $$BooksTableCreateCompanionBuilder = BooksCompanion Function({
  required String id,
  Value<String> title,
  Value<String> author,
  Value<String> fileName,
  Value<int> pageCount,
  Value<int> sizeBytes,
  Value<String> sha256,
  Value<String?> shelfId,
  Value<int> favorite,
  Value<int> lastPage,
  Value<int?> lastOpenedAt,
  required int addedAt,
  Value<int?> deletedAt,
  Value<int> rowid,
});
typedef $$BooksTableUpdateCompanionBuilder = BooksCompanion Function({
  Value<String> id,
  Value<String> title,
  Value<String> author,
  Value<String> fileName,
  Value<int> pageCount,
  Value<int> sizeBytes,
  Value<String> sha256,
  Value<String?> shelfId,
  Value<int> favorite,
  Value<int> lastPage,
  Value<int?> lastOpenedAt,
  Value<int> addedAt,
  Value<int?> deletedAt,
  Value<int> rowid,
});

class $$BooksTableFilterComposer extends Composer<_$AppDatabase, $BooksTable> {
  $$BooksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get author => $composableBuilder(
    column: $table.author,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fileName => $composableBuilder(
    column: $table.fileName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get pageCount => $composableBuilder(
    column: $table.pageCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sizeBytes => $composableBuilder(
    column: $table.sizeBytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sha256 => $composableBuilder(
    column: $table.sha256,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get shelfId => $composableBuilder(
    column: $table.shelfId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get favorite => $composableBuilder(
    column: $table.favorite,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastPage => $composableBuilder(
    column: $table.lastPage,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastOpenedAt => $composableBuilder(
    column: $table.lastOpenedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$BooksTableOrderingComposer
    extends Composer<_$AppDatabase, $BooksTable> {
  $$BooksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get author => $composableBuilder(
    column: $table.author,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fileName => $composableBuilder(
    column: $table.fileName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get pageCount => $composableBuilder(
    column: $table.pageCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sizeBytes => $composableBuilder(
    column: $table.sizeBytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sha256 => $composableBuilder(
    column: $table.sha256,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get shelfId => $composableBuilder(
    column: $table.shelfId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get favorite => $composableBuilder(
    column: $table.favorite,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastPage => $composableBuilder(
    column: $table.lastPage,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastOpenedAt => $composableBuilder(
    column: $table.lastOpenedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$BooksTableAnnotationComposer
    extends Composer<_$AppDatabase, $BooksTable> {
  $$BooksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get author =>
      $composableBuilder(column: $table.author, builder: (column) => column);

  GeneratedColumn<String> get fileName =>
      $composableBuilder(column: $table.fileName, builder: (column) => column);

  GeneratedColumn<int> get pageCount =>
      $composableBuilder(column: $table.pageCount, builder: (column) => column);

  GeneratedColumn<int> get sizeBytes =>
      $composableBuilder(column: $table.sizeBytes, builder: (column) => column);

  GeneratedColumn<String> get sha256 =>
      $composableBuilder(column: $table.sha256, builder: (column) => column);

  GeneratedColumn<String> get shelfId =>
      $composableBuilder(column: $table.shelfId, builder: (column) => column);

  GeneratedColumn<int> get favorite =>
      $composableBuilder(column: $table.favorite, builder: (column) => column);

  GeneratedColumn<int> get lastPage =>
      $composableBuilder(column: $table.lastPage, builder: (column) => column);

  GeneratedColumn<int> get lastOpenedAt => $composableBuilder(
    column: $table.lastOpenedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get addedAt =>
      $composableBuilder(column: $table.addedAt, builder: (column) => column);

  GeneratedColumn<int> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);
}

class $$BooksTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $BooksTable,
          BookRow,
          $$BooksTableFilterComposer,
          $$BooksTableOrderingComposer,
          $$BooksTableAnnotationComposer,
          $$BooksTableCreateCompanionBuilder,
          $$BooksTableUpdateCompanionBuilder,
          (BookRow, BaseReferences<_$AppDatabase, $BooksTable, BookRow>),
          BookRow,
          PrefetchHooks Function()
        > {
  $$BooksTableTableManager(_$AppDatabase db, $BooksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BooksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$BooksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$BooksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> author = const Value.absent(),
                Value<String> fileName = const Value.absent(),
                Value<int> pageCount = const Value.absent(),
                Value<int> sizeBytes = const Value.absent(),
                Value<String> sha256 = const Value.absent(),
                Value<String?> shelfId = const Value.absent(),
                Value<int> favorite = const Value.absent(),
                Value<int> lastPage = const Value.absent(),
                Value<int?> lastOpenedAt = const Value.absent(),
                Value<int> addedAt = const Value.absent(),
                Value<int?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BooksCompanion(
                id: id,
                title: title,
                author: author,
                fileName: fileName,
                pageCount: pageCount,
                sizeBytes: sizeBytes,
                sha256: sha256,
                shelfId: shelfId,
                favorite: favorite,
                lastPage: lastPage,
                lastOpenedAt: lastOpenedAt,
                addedAt: addedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<String> title = const Value.absent(),
                Value<String> author = const Value.absent(),
                Value<String> fileName = const Value.absent(),
                Value<int> pageCount = const Value.absent(),
                Value<int> sizeBytes = const Value.absent(),
                Value<String> sha256 = const Value.absent(),
                Value<String?> shelfId = const Value.absent(),
                Value<int> favorite = const Value.absent(),
                Value<int> lastPage = const Value.absent(),
                Value<int?> lastOpenedAt = const Value.absent(),
                required int addedAt,
                Value<int?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BooksCompanion.insert(
                id: id,
                title: title,
                author: author,
                fileName: fileName,
                pageCount: pageCount,
                sizeBytes: sizeBytes,
                sha256: sha256,
                shelfId: shelfId,
                favorite: favorite,
                lastPage: lastPage,
                lastOpenedAt: lastOpenedAt,
                addedAt: addedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$BooksTable, BookRow>(table),
                  BaseReferences<_$AppDatabase, $BooksTable, BookRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$BooksTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $BooksTable,
      BookRow,
      $$BooksTableFilterComposer,
      $$BooksTableOrderingComposer,
      $$BooksTableAnnotationComposer,
      $$BooksTableCreateCompanionBuilder,
      $$BooksTableUpdateCompanionBuilder,
      (BookRow, BaseReferences<_$AppDatabase, $BooksTable, BookRow>),
      BookRow,
      PrefetchHooks Function()
    >;
typedef $$ShelvesTableCreateCompanionBuilder = ShelvesCompanion Function({
  required String id,
  required String name,
  required int createdAt,
  Value<int> rowid,
});
typedef $$ShelvesTableUpdateCompanionBuilder = ShelvesCompanion Function({
  Value<String> id,
  Value<String> name,
  Value<int> createdAt,
  Value<int> rowid,
});

class $$ShelvesTableFilterComposer
    extends Composer<_$AppDatabase, $ShelvesTable> {
  $$ShelvesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ShelvesTableOrderingComposer
    extends Composer<_$AppDatabase, $ShelvesTable> {
  $$ShelvesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ShelvesTableAnnotationComposer
    extends Composer<_$AppDatabase, $ShelvesTable> {
  $$ShelvesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$ShelvesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ShelvesTable,
          ShelfRow,
          $$ShelvesTableFilterComposer,
          $$ShelvesTableOrderingComposer,
          $$ShelvesTableAnnotationComposer,
          $$ShelvesTableCreateCompanionBuilder,
          $$ShelvesTableUpdateCompanionBuilder,
          (ShelfRow, BaseReferences<_$AppDatabase, $ShelvesTable, ShelfRow>),
          ShelfRow,
          PrefetchHooks Function()
        > {
  $$ShelvesTableTableManager(_$AppDatabase db, $ShelvesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ShelvesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ShelvesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ShelvesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ShelvesCompanion(
                id: id,
                name: name,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                required int createdAt,
                Value<int> rowid = const Value.absent(),
              }) => ShelvesCompanion.insert(
                id: id,
                name: name,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ShelvesTable, ShelfRow>(table),
                  BaseReferences<_$AppDatabase, $ShelvesTable, ShelfRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ShelvesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ShelvesTable,
      ShelfRow,
      $$ShelvesTableFilterComposer,
      $$ShelvesTableOrderingComposer,
      $$ShelvesTableAnnotationComposer,
      $$ShelvesTableCreateCompanionBuilder,
      $$ShelvesTableUpdateCompanionBuilder,
      (ShelfRow, BaseReferences<_$AppDatabase, $ShelvesTable, ShelfRow>),
      ShelfRow,
      PrefetchHooks Function()
    >;
typedef $$FieldMetaTableCreateCompanionBuilder = FieldMetaCompanion Function({
  required String tbl,
  required String rowId,
  required String field,
  required String hlc,
  Value<int> rowid,
});
typedef $$FieldMetaTableUpdateCompanionBuilder = FieldMetaCompanion Function({
  Value<String> tbl,
  Value<String> rowId,
  Value<String> field,
  Value<String> hlc,
  Value<int> rowid,
});

class $$FieldMetaTableFilterComposer
    extends Composer<_$AppDatabase, $FieldMetaTable> {
  $$FieldMetaTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get tbl => $composableBuilder(
    column: $table.tbl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get rowId => $composableBuilder(
    column: $table.rowId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get field => $composableBuilder(
    column: $table.field,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get hlc => $composableBuilder(
    column: $table.hlc,
    builder: (column) => ColumnFilters(column),
  );
}

class $$FieldMetaTableOrderingComposer
    extends Composer<_$AppDatabase, $FieldMetaTable> {
  $$FieldMetaTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get tbl => $composableBuilder(
    column: $table.tbl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get rowId => $composableBuilder(
    column: $table.rowId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get field => $composableBuilder(
    column: $table.field,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hlc => $composableBuilder(
    column: $table.hlc,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$FieldMetaTableAnnotationComposer
    extends Composer<_$AppDatabase, $FieldMetaTable> {
  $$FieldMetaTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get tbl =>
      $composableBuilder(column: $table.tbl, builder: (column) => column);

  GeneratedColumn<String> get rowId =>
      $composableBuilder(column: $table.rowId, builder: (column) => column);

  GeneratedColumn<String> get field =>
      $composableBuilder(column: $table.field, builder: (column) => column);

  GeneratedColumn<String> get hlc =>
      $composableBuilder(column: $table.hlc, builder: (column) => column);
}

class $$FieldMetaTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $FieldMetaTable,
          FieldMetaData,
          $$FieldMetaTableFilterComposer,
          $$FieldMetaTableOrderingComposer,
          $$FieldMetaTableAnnotationComposer,
          $$FieldMetaTableCreateCompanionBuilder,
          $$FieldMetaTableUpdateCompanionBuilder,
          (
            FieldMetaData,
            BaseReferences<_$AppDatabase, $FieldMetaTable, FieldMetaData>,
          ),
          FieldMetaData,
          PrefetchHooks Function()
        > {
  $$FieldMetaTableTableManager(_$AppDatabase db, $FieldMetaTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FieldMetaTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FieldMetaTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FieldMetaTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> tbl = const Value.absent(),
                Value<String> rowId = const Value.absent(),
                Value<String> field = const Value.absent(),
                Value<String> hlc = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FieldMetaCompanion(
                tbl: tbl,
                rowId: rowId,
                field: field,
                hlc: hlc,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String tbl,
                required String rowId,
                required String field,
                required String hlc,
                Value<int> rowid = const Value.absent(),
              }) => FieldMetaCompanion.insert(
                tbl: tbl,
                rowId: rowId,
                field: field,
                hlc: hlc,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$FieldMetaTable, FieldMetaData>(table),
                  BaseReferences<_$AppDatabase, $FieldMetaTable, FieldMetaData>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$FieldMetaTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $FieldMetaTable,
      FieldMetaData,
      $$FieldMetaTableFilterComposer,
      $$FieldMetaTableOrderingComposer,
      $$FieldMetaTableAnnotationComposer,
      $$FieldMetaTableCreateCompanionBuilder,
      $$FieldMetaTableUpdateCompanionBuilder,
      (
        FieldMetaData,
        BaseReferences<_$AppDatabase, $FieldMetaTable, FieldMetaData>,
      ),
      FieldMetaData,
      PrefetchHooks Function()
    >;
typedef $$SyncOutboxTableCreateCompanionBuilder = SyncOutboxCompanion Function({
  Value<int> id,
  required String tbl,
  required String rowId,
  required String field,
  Value<String?> valueJson,
  required String hlc,
  Value<String?> baseHlc,
  required String changeId,
  Value<int> attempts,
  Value<String?> lastError,
  required int createdAt,
});
typedef $$SyncOutboxTableUpdateCompanionBuilder = SyncOutboxCompanion Function({
  Value<int> id,
  Value<String> tbl,
  Value<String> rowId,
  Value<String> field,
  Value<String?> valueJson,
  Value<String> hlc,
  Value<String?> baseHlc,
  Value<String> changeId,
  Value<int> attempts,
  Value<String?> lastError,
  Value<int> createdAt,
});

class $$SyncOutboxTableFilterComposer
    extends Composer<_$AppDatabase, $SyncOutboxTable> {
  $$SyncOutboxTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tbl => $composableBuilder(
    column: $table.tbl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get rowId => $composableBuilder(
    column: $table.rowId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get field => $composableBuilder(
    column: $table.field,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get valueJson => $composableBuilder(
    column: $table.valueJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get hlc => $composableBuilder(
    column: $table.hlc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get baseHlc => $composableBuilder(
    column: $table.baseHlc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get changeId => $composableBuilder(
    column: $table.changeId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncOutboxTableOrderingComposer
    extends Composer<_$AppDatabase, $SyncOutboxTable> {
  $$SyncOutboxTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tbl => $composableBuilder(
    column: $table.tbl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get rowId => $composableBuilder(
    column: $table.rowId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get field => $composableBuilder(
    column: $table.field,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get valueJson => $composableBuilder(
    column: $table.valueJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hlc => $composableBuilder(
    column: $table.hlc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get baseHlc => $composableBuilder(
    column: $table.baseHlc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get changeId => $composableBuilder(
    column: $table.changeId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncOutboxTableAnnotationComposer
    extends Composer<_$AppDatabase, $SyncOutboxTable> {
  $$SyncOutboxTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get tbl =>
      $composableBuilder(column: $table.tbl, builder: (column) => column);

  GeneratedColumn<String> get rowId =>
      $composableBuilder(column: $table.rowId, builder: (column) => column);

  GeneratedColumn<String> get field =>
      $composableBuilder(column: $table.field, builder: (column) => column);

  GeneratedColumn<String> get valueJson =>
      $composableBuilder(column: $table.valueJson, builder: (column) => column);

  GeneratedColumn<String> get hlc =>
      $composableBuilder(column: $table.hlc, builder: (column) => column);

  GeneratedColumn<String> get baseHlc =>
      $composableBuilder(column: $table.baseHlc, builder: (column) => column);

  GeneratedColumn<String> get changeId =>
      $composableBuilder(column: $table.changeId, builder: (column) => column);

  GeneratedColumn<int> get attempts =>
      $composableBuilder(column: $table.attempts, builder: (column) => column);

  GeneratedColumn<String> get lastError =>
      $composableBuilder(column: $table.lastError, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$SyncOutboxTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SyncOutboxTable,
          SyncOutboxData,
          $$SyncOutboxTableFilterComposer,
          $$SyncOutboxTableOrderingComposer,
          $$SyncOutboxTableAnnotationComposer,
          $$SyncOutboxTableCreateCompanionBuilder,
          $$SyncOutboxTableUpdateCompanionBuilder,
          (
            SyncOutboxData,
            BaseReferences<_$AppDatabase, $SyncOutboxTable, SyncOutboxData>,
          ),
          SyncOutboxData,
          PrefetchHooks Function()
        > {
  $$SyncOutboxTableTableManager(_$AppDatabase db, $SyncOutboxTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncOutboxTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncOutboxTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncOutboxTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> tbl = const Value.absent(),
                Value<String> rowId = const Value.absent(),
                Value<String> field = const Value.absent(),
                Value<String?> valueJson = const Value.absent(),
                Value<String> hlc = const Value.absent(),
                Value<String?> baseHlc = const Value.absent(),
                Value<String> changeId = const Value.absent(),
                Value<int> attempts = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
              }) => SyncOutboxCompanion(
                id: id,
                tbl: tbl,
                rowId: rowId,
                field: field,
                valueJson: valueJson,
                hlc: hlc,
                baseHlc: baseHlc,
                changeId: changeId,
                attempts: attempts,
                lastError: lastError,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String tbl,
                required String rowId,
                required String field,
                Value<String?> valueJson = const Value.absent(),
                required String hlc,
                Value<String?> baseHlc = const Value.absent(),
                required String changeId,
                Value<int> attempts = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                required int createdAt,
              }) => SyncOutboxCompanion.insert(
                id: id,
                tbl: tbl,
                rowId: rowId,
                field: field,
                valueJson: valueJson,
                hlc: hlc,
                baseHlc: baseHlc,
                changeId: changeId,
                attempts: attempts,
                lastError: lastError,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SyncOutboxTable, SyncOutboxData>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $SyncOutboxTable,
                    SyncOutboxData
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncOutboxTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SyncOutboxTable,
      SyncOutboxData,
      $$SyncOutboxTableFilterComposer,
      $$SyncOutboxTableOrderingComposer,
      $$SyncOutboxTableAnnotationComposer,
      $$SyncOutboxTableCreateCompanionBuilder,
      $$SyncOutboxTableUpdateCompanionBuilder,
      (
        SyncOutboxData,
        BaseReferences<_$AppDatabase, $SyncOutboxTable, SyncOutboxData>,
      ),
      SyncOutboxData,
      PrefetchHooks Function()
    >;
typedef $$SyncStateTableCreateCompanionBuilder = SyncStateCompanion Function({
  required String key,
  required String value,
  Value<int> rowid,
});
typedef $$SyncStateTableUpdateCompanionBuilder = SyncStateCompanion Function({
  Value<String> key,
  Value<String> value,
  Value<int> rowid,
});

class $$SyncStateTableFilterComposer
    extends Composer<_$AppDatabase, $SyncStateTable> {
  $$SyncStateTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncStateTableOrderingComposer
    extends Composer<_$AppDatabase, $SyncStateTable> {
  $$SyncStateTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncStateTableAnnotationComposer
    extends Composer<_$AppDatabase, $SyncStateTable> {
  $$SyncStateTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$SyncStateTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SyncStateTable,
          SyncStateData,
          $$SyncStateTableFilterComposer,
          $$SyncStateTableOrderingComposer,
          $$SyncStateTableAnnotationComposer,
          $$SyncStateTableCreateCompanionBuilder,
          $$SyncStateTableUpdateCompanionBuilder,
          (
            SyncStateData,
            BaseReferences<_$AppDatabase, $SyncStateTable, SyncStateData>,
          ),
          SyncStateData,
          PrefetchHooks Function()
        > {
  $$SyncStateTableTableManager(_$AppDatabase db, $SyncStateTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncStateTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncStateTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncStateTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> key = const Value.absent(),
            Value<String> value = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) => SyncStateCompanion(key: key, value: value, rowid: rowid),
          createCompanionCallback: ({
            required String key,
            required String value,
            Value<int> rowid = const Value.absent(),
          }) => SyncStateCompanion.insert(key: key, value: value, rowid: rowid),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SyncStateTable, SyncStateData>(table),
                  BaseReferences<_$AppDatabase, $SyncStateTable, SyncStateData>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncStateTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SyncStateTable,
      SyncStateData,
      $$SyncStateTableFilterComposer,
      $$SyncStateTableOrderingComposer,
      $$SyncStateTableAnnotationComposer,
      $$SyncStateTableCreateCompanionBuilder,
      $$SyncStateTableUpdateCompanionBuilder,
      (
        SyncStateData,
        BaseReferences<_$AppDatabase, $SyncStateTable, SyncStateData>,
      ),
      SyncStateData,
      PrefetchHooks Function()
    >;
typedef $$LocalConflictsTableCreateCompanionBuilder =
    LocalConflictsCompanion Function({
      Value<int> id,
      Value<int?> serverId,
      required String tbl,
      required String rowId,
      required String field,
      Value<String?> lostValueJson,
      required String lostHlc,
      required String winnerHlc,
      required int createdAt,
      Value<int?> resolvedAt,
    });
typedef $$LocalConflictsTableUpdateCompanionBuilder =
    LocalConflictsCompanion Function({
      Value<int> id,
      Value<int?> serverId,
      Value<String> tbl,
      Value<String> rowId,
      Value<String> field,
      Value<String?> lostValueJson,
      Value<String> lostHlc,
      Value<String> winnerHlc,
      Value<int> createdAt,
      Value<int?> resolvedAt,
    });

class $$LocalConflictsTableFilterComposer
    extends Composer<_$AppDatabase, $LocalConflictsTable> {
  $$LocalConflictsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get serverId => $composableBuilder(
    column: $table.serverId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tbl => $composableBuilder(
    column: $table.tbl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get rowId => $composableBuilder(
    column: $table.rowId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get field => $composableBuilder(
    column: $table.field,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lostValueJson => $composableBuilder(
    column: $table.lostValueJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lostHlc => $composableBuilder(
    column: $table.lostHlc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get winnerHlc => $composableBuilder(
    column: $table.winnerHlc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get resolvedAt => $composableBuilder(
    column: $table.resolvedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalConflictsTableOrderingComposer
    extends Composer<_$AppDatabase, $LocalConflictsTable> {
  $$LocalConflictsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get serverId => $composableBuilder(
    column: $table.serverId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tbl => $composableBuilder(
    column: $table.tbl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get rowId => $composableBuilder(
    column: $table.rowId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get field => $composableBuilder(
    column: $table.field,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lostValueJson => $composableBuilder(
    column: $table.lostValueJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lostHlc => $composableBuilder(
    column: $table.lostHlc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get winnerHlc => $composableBuilder(
    column: $table.winnerHlc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get resolvedAt => $composableBuilder(
    column: $table.resolvedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalConflictsTableAnnotationComposer
    extends Composer<_$AppDatabase, $LocalConflictsTable> {
  $$LocalConflictsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get serverId =>
      $composableBuilder(column: $table.serverId, builder: (column) => column);

  GeneratedColumn<String> get tbl =>
      $composableBuilder(column: $table.tbl, builder: (column) => column);

  GeneratedColumn<String> get rowId =>
      $composableBuilder(column: $table.rowId, builder: (column) => column);

  GeneratedColumn<String> get field =>
      $composableBuilder(column: $table.field, builder: (column) => column);

  GeneratedColumn<String> get lostValueJson => $composableBuilder(
    column: $table.lostValueJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lostHlc =>
      $composableBuilder(column: $table.lostHlc, builder: (column) => column);

  GeneratedColumn<String> get winnerHlc =>
      $composableBuilder(column: $table.winnerHlc, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get resolvedAt => $composableBuilder(
    column: $table.resolvedAt,
    builder: (column) => column,
  );
}

class $$LocalConflictsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LocalConflictsTable,
          LocalConflict,
          $$LocalConflictsTableFilterComposer,
          $$LocalConflictsTableOrderingComposer,
          $$LocalConflictsTableAnnotationComposer,
          $$LocalConflictsTableCreateCompanionBuilder,
          $$LocalConflictsTableUpdateCompanionBuilder,
          (
            LocalConflict,
            BaseReferences<_$AppDatabase, $LocalConflictsTable, LocalConflict>,
          ),
          LocalConflict,
          PrefetchHooks Function()
        > {
  $$LocalConflictsTableTableManager(
    _$AppDatabase db,
    $LocalConflictsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalConflictsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalConflictsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalConflictsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int?> serverId = const Value.absent(),
                Value<String> tbl = const Value.absent(),
                Value<String> rowId = const Value.absent(),
                Value<String> field = const Value.absent(),
                Value<String?> lostValueJson = const Value.absent(),
                Value<String> lostHlc = const Value.absent(),
                Value<String> winnerHlc = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int?> resolvedAt = const Value.absent(),
              }) => LocalConflictsCompanion(
                id: id,
                serverId: serverId,
                tbl: tbl,
                rowId: rowId,
                field: field,
                lostValueJson: lostValueJson,
                lostHlc: lostHlc,
                winnerHlc: winnerHlc,
                createdAt: createdAt,
                resolvedAt: resolvedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int?> serverId = const Value.absent(),
                required String tbl,
                required String rowId,
                required String field,
                Value<String?> lostValueJson = const Value.absent(),
                required String lostHlc,
                required String winnerHlc,
                required int createdAt,
                Value<int?> resolvedAt = const Value.absent(),
              }) => LocalConflictsCompanion.insert(
                id: id,
                serverId: serverId,
                tbl: tbl,
                rowId: rowId,
                field: field,
                lostValueJson: lostValueJson,
                lostHlc: lostHlc,
                winnerHlc: winnerHlc,
                createdAt: createdAt,
                resolvedAt: resolvedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$LocalConflictsTable, LocalConflict>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $LocalConflictsTable,
                    LocalConflict
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalConflictsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LocalConflictsTable,
      LocalConflict,
      $$LocalConflictsTableFilterComposer,
      $$LocalConflictsTableOrderingComposer,
      $$LocalConflictsTableAnnotationComposer,
      $$LocalConflictsTableCreateCompanionBuilder,
      $$LocalConflictsTableUpdateCompanionBuilder,
      (
        LocalConflict,
        BaseReferences<_$AppDatabase, $LocalConflictsTable, LocalConflict>,
      ),
      LocalConflict,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$TasksTableTableManager get tasks =>
      $$TasksTableTableManager(_db, _db.tasks);
  $$EventsTableTableManager get events =>
      $$EventsTableTableManager(_db, _db.events);
  $$BooksTableTableManager get books =>
      $$BooksTableTableManager(_db, _db.books);
  $$ShelvesTableTableManager get shelves =>
      $$ShelvesTableTableManager(_db, _db.shelves);
  $$FieldMetaTableTableManager get fieldMeta =>
      $$FieldMetaTableTableManager(_db, _db.fieldMeta);
  $$SyncOutboxTableTableManager get syncOutbox =>
      $$SyncOutboxTableTableManager(_db, _db.syncOutbox);
  $$SyncStateTableTableManager get syncState =>
      $$SyncStateTableTableManager(_db, _db.syncState);
  $$LocalConflictsTableTableManager get localConflicts =>
      $$LocalConflictsTableTableManager(_db, _db.localConflicts);
}
