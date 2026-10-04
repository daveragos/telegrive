// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $FoldersTable extends Folders with TableInfo<$FoldersTable, FolderRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FoldersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _parentIdMeta = const VerificationMeta(
    'parentId',
  );
  @override
  late final GeneratedColumn<String> parentId = GeneratedColumn<String>(
    'parent_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
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
  static const VerificationMeta _messageIdMeta = const VerificationMeta(
    'messageId',
  );
  @override
  late final GeneratedColumn<int> messageId = GeneratedColumn<int>(
    'message_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _modifiedAtMeta = const VerificationMeta(
    'modifiedAt',
  );
  @override
  late final GeneratedColumn<DateTime> modifiedAt = GeneratedColumn<DateTime>(
    'modified_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _trashedAtMeta = const VerificationMeta(
    'trashedAt',
  );
  @override
  late final GeneratedColumn<DateTime> trashedAt = GeneratedColumn<DateTime>(
    'trashed_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _hiddenMeta = const VerificationMeta('hidden');
  @override
  late final GeneratedColumn<bool> hidden = GeneratedColumn<bool>(
    'hidden',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("hidden" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _manifestExtraMeta = const VerificationMeta(
    'manifestExtra',
  );
  @override
  late final GeneratedColumn<String> manifestExtra = GeneratedColumn<String>(
    'manifest_extra',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _starredMeta = const VerificationMeta(
    'starred',
  );
  @override
  late final GeneratedColumn<bool> starred = GeneratedColumn<bool>(
    'starred',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("starred" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    parentId,
    name,
    messageId,
    createdAt,
    modifiedAt,
    trashedAt,
    hidden,
    manifestExtra,
    starred,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'folders';
  @override
  VerificationContext validateIntegrity(
    Insertable<FolderRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('parent_id')) {
      context.handle(
        _parentIdMeta,
        parentId.isAcceptableOrUnknown(data['parent_id']!, _parentIdMeta),
      );
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('message_id')) {
      context.handle(
        _messageIdMeta,
        messageId.isAcceptableOrUnknown(data['message_id']!, _messageIdMeta),
      );
    } else if (isInserting) {
      context.missing(_messageIdMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('modified_at')) {
      context.handle(
        _modifiedAtMeta,
        modifiedAt.isAcceptableOrUnknown(data['modified_at']!, _modifiedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_modifiedAtMeta);
    }
    if (data.containsKey('trashed_at')) {
      context.handle(
        _trashedAtMeta,
        trashedAt.isAcceptableOrUnknown(data['trashed_at']!, _trashedAtMeta),
      );
    }
    if (data.containsKey('hidden')) {
      context.handle(
        _hiddenMeta,
        hidden.isAcceptableOrUnknown(data['hidden']!, _hiddenMeta),
      );
    }
    if (data.containsKey('manifest_extra')) {
      context.handle(
        _manifestExtraMeta,
        manifestExtra.isAcceptableOrUnknown(
          data['manifest_extra']!,
          _manifestExtraMeta,
        ),
      );
    }
    if (data.containsKey('starred')) {
      context.handle(
        _starredMeta,
        starred.isAcceptableOrUnknown(data['starred']!, _starredMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  FolderRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FolderRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      parentId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}parent_id'],
      ),
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      messageId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}message_id'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      modifiedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}modified_at'],
      )!,
      trashedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}trashed_at'],
      ),
      hidden: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}hidden'],
      )!,
      manifestExtra: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}manifest_extra'],
      ),
      starred: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}starred'],
      )!,
    );
  }

  @override
  $FoldersTable createAlias(String alias) {
    return $FoldersTable(attachedDatabase, alias);
  }
}

class FolderRow extends DataClass implements Insertable<FolderRow> {
  final String id;
  final String? parentId;
  final String name;
  final int messageId;
  final DateTime createdAt;
  final DateTime modifiedAt;

  /// When it was moved to the trash; everything inside goes with it.
  final DateTime? trashedAt;

  /// In the trash, or inside a folder that is: shown nowhere but Trash.
  /// Worked out locally from [trashedAt] up the folder tree.
  final bool hidden;

  /// Manifest keys this version doesn't know, as JSON, so a rename or move
  /// made here writes them back instead of dropping what a newer version
  /// stored. Null when there are none.
  final String? manifestExtra;

  /// Starred like a file is, and kept in the folder's own message, so the
  /// star follows the drive to another phone.
  final bool starred;
  const FolderRow({
    required this.id,
    this.parentId,
    required this.name,
    required this.messageId,
    required this.createdAt,
    required this.modifiedAt,
    this.trashedAt,
    required this.hidden,
    this.manifestExtra,
    required this.starred,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    if (!nullToAbsent || parentId != null) {
      map['parent_id'] = Variable<String>(parentId);
    }
    map['name'] = Variable<String>(name);
    map['message_id'] = Variable<int>(messageId);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['modified_at'] = Variable<DateTime>(modifiedAt);
    if (!nullToAbsent || trashedAt != null) {
      map['trashed_at'] = Variable<DateTime>(trashedAt);
    }
    map['hidden'] = Variable<bool>(hidden);
    if (!nullToAbsent || manifestExtra != null) {
      map['manifest_extra'] = Variable<String>(manifestExtra);
    }
    map['starred'] = Variable<bool>(starred);
    return map;
  }

  FoldersCompanion toCompanion(bool nullToAbsent) {
    return FoldersCompanion(
      id: Value(id),
      parentId: parentId == null && nullToAbsent
          ? const Value.absent()
          : Value(parentId),
      name: Value(name),
      messageId: Value(messageId),
      createdAt: Value(createdAt),
      modifiedAt: Value(modifiedAt),
      trashedAt: trashedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(trashedAt),
      hidden: Value(hidden),
      manifestExtra: manifestExtra == null && nullToAbsent
          ? const Value.absent()
          : Value(manifestExtra),
      starred: Value(starred),
    );
  }

  factory FolderRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FolderRow(
      id: serializer.fromJson<String>(json['id']),
      parentId: serializer.fromJson<String?>(json['parentId']),
      name: serializer.fromJson<String>(json['name']),
      messageId: serializer.fromJson<int>(json['messageId']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      modifiedAt: serializer.fromJson<DateTime>(json['modifiedAt']),
      trashedAt: serializer.fromJson<DateTime?>(json['trashedAt']),
      hidden: serializer.fromJson<bool>(json['hidden']),
      manifestExtra: serializer.fromJson<String?>(json['manifestExtra']),
      starred: serializer.fromJson<bool>(json['starred']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'parentId': serializer.toJson<String?>(parentId),
      'name': serializer.toJson<String>(name),
      'messageId': serializer.toJson<int>(messageId),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'modifiedAt': serializer.toJson<DateTime>(modifiedAt),
      'trashedAt': serializer.toJson<DateTime?>(trashedAt),
      'hidden': serializer.toJson<bool>(hidden),
      'manifestExtra': serializer.toJson<String?>(manifestExtra),
      'starred': serializer.toJson<bool>(starred),
    };
  }

  FolderRow copyWith({
    String? id,
    Value<String?> parentId = const Value.absent(),
    String? name,
    int? messageId,
    DateTime? createdAt,
    DateTime? modifiedAt,
    Value<DateTime?> trashedAt = const Value.absent(),
    bool? hidden,
    Value<String?> manifestExtra = const Value.absent(),
    bool? starred,
  }) => FolderRow(
    id: id ?? this.id,
    parentId: parentId.present ? parentId.value : this.parentId,
    name: name ?? this.name,
    messageId: messageId ?? this.messageId,
    createdAt: createdAt ?? this.createdAt,
    modifiedAt: modifiedAt ?? this.modifiedAt,
    trashedAt: trashedAt.present ? trashedAt.value : this.trashedAt,
    hidden: hidden ?? this.hidden,
    manifestExtra: manifestExtra.present
        ? manifestExtra.value
        : this.manifestExtra,
    starred: starred ?? this.starred,
  );
  FolderRow copyWithCompanion(FoldersCompanion data) {
    return FolderRow(
      id: data.id.present ? data.id.value : this.id,
      parentId: data.parentId.present ? data.parentId.value : this.parentId,
      name: data.name.present ? data.name.value : this.name,
      messageId: data.messageId.present ? data.messageId.value : this.messageId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      modifiedAt: data.modifiedAt.present
          ? data.modifiedAt.value
          : this.modifiedAt,
      trashedAt: data.trashedAt.present ? data.trashedAt.value : this.trashedAt,
      hidden: data.hidden.present ? data.hidden.value : this.hidden,
      manifestExtra: data.manifestExtra.present
          ? data.manifestExtra.value
          : this.manifestExtra,
      starred: data.starred.present ? data.starred.value : this.starred,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FolderRow(')
          ..write('id: $id, ')
          ..write('parentId: $parentId, ')
          ..write('name: $name, ')
          ..write('messageId: $messageId, ')
          ..write('createdAt: $createdAt, ')
          ..write('modifiedAt: $modifiedAt, ')
          ..write('trashedAt: $trashedAt, ')
          ..write('hidden: $hidden, ')
          ..write('manifestExtra: $manifestExtra, ')
          ..write('starred: $starred')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    parentId,
    name,
    messageId,
    createdAt,
    modifiedAt,
    trashedAt,
    hidden,
    manifestExtra,
    starred,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FolderRow &&
          other.id == this.id &&
          other.parentId == this.parentId &&
          other.name == this.name &&
          other.messageId == this.messageId &&
          other.createdAt == this.createdAt &&
          other.modifiedAt == this.modifiedAt &&
          other.trashedAt == this.trashedAt &&
          other.hidden == this.hidden &&
          other.manifestExtra == this.manifestExtra &&
          other.starred == this.starred);
}

class FoldersCompanion extends UpdateCompanion<FolderRow> {
  final Value<String> id;
  final Value<String?> parentId;
  final Value<String> name;
  final Value<int> messageId;
  final Value<DateTime> createdAt;
  final Value<DateTime> modifiedAt;
  final Value<DateTime?> trashedAt;
  final Value<bool> hidden;
  final Value<String?> manifestExtra;
  final Value<bool> starred;
  final Value<int> rowid;
  const FoldersCompanion({
    this.id = const Value.absent(),
    this.parentId = const Value.absent(),
    this.name = const Value.absent(),
    this.messageId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.modifiedAt = const Value.absent(),
    this.trashedAt = const Value.absent(),
    this.hidden = const Value.absent(),
    this.manifestExtra = const Value.absent(),
    this.starred = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FoldersCompanion.insert({
    required String id,
    this.parentId = const Value.absent(),
    required String name,
    required int messageId,
    required DateTime createdAt,
    required DateTime modifiedAt,
    this.trashedAt = const Value.absent(),
    this.hidden = const Value.absent(),
    this.manifestExtra = const Value.absent(),
    this.starred = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       messageId = Value(messageId),
       createdAt = Value(createdAt),
       modifiedAt = Value(modifiedAt);
  static Insertable<FolderRow> custom({
    Expression<String>? id,
    Expression<String>? parentId,
    Expression<String>? name,
    Expression<int>? messageId,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? modifiedAt,
    Expression<DateTime>? trashedAt,
    Expression<bool>? hidden,
    Expression<String>? manifestExtra,
    Expression<bool>? starred,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (parentId != null) 'parent_id': parentId,
      if (name != null) 'name': name,
      if (messageId != null) 'message_id': messageId,
      if (createdAt != null) 'created_at': createdAt,
      if (modifiedAt != null) 'modified_at': modifiedAt,
      if (trashedAt != null) 'trashed_at': trashedAt,
      if (hidden != null) 'hidden': hidden,
      if (manifestExtra != null) 'manifest_extra': manifestExtra,
      if (starred != null) 'starred': starred,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FoldersCompanion copyWith({
    Value<String>? id,
    Value<String?>? parentId,
    Value<String>? name,
    Value<int>? messageId,
    Value<DateTime>? createdAt,
    Value<DateTime>? modifiedAt,
    Value<DateTime?>? trashedAt,
    Value<bool>? hidden,
    Value<String?>? manifestExtra,
    Value<bool>? starred,
    Value<int>? rowid,
  }) {
    return FoldersCompanion(
      id: id ?? this.id,
      parentId: parentId ?? this.parentId,
      name: name ?? this.name,
      messageId: messageId ?? this.messageId,
      createdAt: createdAt ?? this.createdAt,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      trashedAt: trashedAt ?? this.trashedAt,
      hidden: hidden ?? this.hidden,
      manifestExtra: manifestExtra ?? this.manifestExtra,
      starred: starred ?? this.starred,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (parentId.present) {
      map['parent_id'] = Variable<String>(parentId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (messageId.present) {
      map['message_id'] = Variable<int>(messageId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (modifiedAt.present) {
      map['modified_at'] = Variable<DateTime>(modifiedAt.value);
    }
    if (trashedAt.present) {
      map['trashed_at'] = Variable<DateTime>(trashedAt.value);
    }
    if (hidden.present) {
      map['hidden'] = Variable<bool>(hidden.value);
    }
    if (manifestExtra.present) {
      map['manifest_extra'] = Variable<String>(manifestExtra.value);
    }
    if (starred.present) {
      map['starred'] = Variable<bool>(starred.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FoldersCompanion(')
          ..write('id: $id, ')
          ..write('parentId: $parentId, ')
          ..write('name: $name, ')
          ..write('messageId: $messageId, ')
          ..write('createdAt: $createdAt, ')
          ..write('modifiedAt: $modifiedAt, ')
          ..write('trashedAt: $trashedAt, ')
          ..write('hidden: $hidden, ')
          ..write('manifestExtra: $manifestExtra, ')
          ..write('starred: $starred, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DriveFilesTable extends DriveFiles
    with TableInfo<$DriveFilesTable, FileRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DriveFilesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _folderIdMeta = const VerificationMeta(
    'folderId',
  );
  @override
  late final GeneratedColumn<String> folderId = GeneratedColumn<String>(
    'folder_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
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
  static const VerificationMeta _mimeTypeMeta = const VerificationMeta(
    'mimeType',
  );
  @override
  late final GeneratedColumn<String> mimeType = GeneratedColumn<String>(
    'mime_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<FileKind, String> kind =
      GeneratedColumn<String>(
        'kind',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<FileKind>($DriveFilesTable.$converterkind);
  static const VerificationMeta _sizeMeta = const VerificationMeta('size');
  @override
  late final GeneratedColumn<int> size = GeneratedColumn<int>(
    'size',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _modifiedAtMeta = const VerificationMeta(
    'modifiedAt',
  );
  @override
  late final GeneratedColumn<DateTime> modifiedAt = GeneratedColumn<DateTime>(
    'modified_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _partCountMeta = const VerificationMeta(
    'partCount',
  );
  @override
  late final GeneratedColumn<int> partCount = GeneratedColumn<int>(
    'part_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _partsPresentMeta = const VerificationMeta(
    'partsPresent',
  );
  @override
  late final GeneratedColumn<int> partsPresent = GeneratedColumn<int>(
    'parts_present',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _starredMeta = const VerificationMeta(
    'starred',
  );
  @override
  late final GeneratedColumn<bool> starred = GeneratedColumn<bool>(
    'starred',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("starred" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _minithumbnailMeta = const VerificationMeta(
    'minithumbnail',
  );
  @override
  late final GeneratedColumn<String> minithumbnail = GeneratedColumn<String>(
    'minithumbnail',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _thumbnailFileIdMeta = const VerificationMeta(
    'thumbnailFileId',
  );
  @override
  late final GeneratedColumn<int> thumbnailFileId = GeneratedColumn<int>(
    'thumbnail_file_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _takenAtMeta = const VerificationMeta(
    'takenAt',
  );
  @override
  late final GeneratedColumn<DateTime> takenAt = GeneratedColumn<DateTime>(
    'taken_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _trashedAtMeta = const VerificationMeta(
    'trashedAt',
  );
  @override
  late final GeneratedColumn<DateTime> trashedAt = GeneratedColumn<DateTime>(
    'trashed_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _hiddenMeta = const VerificationMeta('hidden');
  @override
  late final GeneratedColumn<bool> hidden = GeneratedColumn<bool>(
    'hidden',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("hidden" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _manifestExtraMeta = const VerificationMeta(
    'manifestExtra',
  );
  @override
  late final GeneratedColumn<String> manifestExtra = GeneratedColumn<String>(
    'manifest_extra',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _durationSecondsMeta = const VerificationMeta(
    'durationSeconds',
  );
  @override
  late final GeneratedColumn<int> durationSeconds = GeneratedColumn<int>(
    'duration_seconds',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _replacedByMeta = const VerificationMeta(
    'replacedBy',
  );
  @override
  late final GeneratedColumn<String> replacedBy = GeneratedColumn<String>(
    'replaced_by',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _adoptedMeta = const VerificationMeta(
    'adopted',
  );
  @override
  late final GeneratedColumn<bool> adopted = GeneratedColumn<bool>(
    'adopted',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("adopted" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _originalSizeMeta = const VerificationMeta(
    'originalSize',
  );
  @override
  late final GeneratedColumn<int> originalSize = GeneratedColumn<int>(
    'original_size',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    folderId,
    name,
    mimeType,
    kind,
    size,
    createdAt,
    modifiedAt,
    partCount,
    partsPresent,
    starred,
    minithumbnail,
    thumbnailFileId,
    takenAt,
    trashedAt,
    hidden,
    manifestExtra,
    durationSeconds,
    replacedBy,
    adopted,
    originalSize,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'drive_files';
  @override
  VerificationContext validateIntegrity(
    Insertable<FileRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('folder_id')) {
      context.handle(
        _folderIdMeta,
        folderId.isAcceptableOrUnknown(data['folder_id']!, _folderIdMeta),
      );
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('mime_type')) {
      context.handle(
        _mimeTypeMeta,
        mimeType.isAcceptableOrUnknown(data['mime_type']!, _mimeTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_mimeTypeMeta);
    }
    if (data.containsKey('size')) {
      context.handle(
        _sizeMeta,
        size.isAcceptableOrUnknown(data['size']!, _sizeMeta),
      );
    } else if (isInserting) {
      context.missing(_sizeMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('modified_at')) {
      context.handle(
        _modifiedAtMeta,
        modifiedAt.isAcceptableOrUnknown(data['modified_at']!, _modifiedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_modifiedAtMeta);
    }
    if (data.containsKey('part_count')) {
      context.handle(
        _partCountMeta,
        partCount.isAcceptableOrUnknown(data['part_count']!, _partCountMeta),
      );
    }
    if (data.containsKey('parts_present')) {
      context.handle(
        _partsPresentMeta,
        partsPresent.isAcceptableOrUnknown(
          data['parts_present']!,
          _partsPresentMeta,
        ),
      );
    }
    if (data.containsKey('starred')) {
      context.handle(
        _starredMeta,
        starred.isAcceptableOrUnknown(data['starred']!, _starredMeta),
      );
    }
    if (data.containsKey('minithumbnail')) {
      context.handle(
        _minithumbnailMeta,
        minithumbnail.isAcceptableOrUnknown(
          data['minithumbnail']!,
          _minithumbnailMeta,
        ),
      );
    }
    if (data.containsKey('thumbnail_file_id')) {
      context.handle(
        _thumbnailFileIdMeta,
        thumbnailFileId.isAcceptableOrUnknown(
          data['thumbnail_file_id']!,
          _thumbnailFileIdMeta,
        ),
      );
    }
    if (data.containsKey('taken_at')) {
      context.handle(
        _takenAtMeta,
        takenAt.isAcceptableOrUnknown(data['taken_at']!, _takenAtMeta),
      );
    }
    if (data.containsKey('trashed_at')) {
      context.handle(
        _trashedAtMeta,
        trashedAt.isAcceptableOrUnknown(data['trashed_at']!, _trashedAtMeta),
      );
    }
    if (data.containsKey('hidden')) {
      context.handle(
        _hiddenMeta,
        hidden.isAcceptableOrUnknown(data['hidden']!, _hiddenMeta),
      );
    }
    if (data.containsKey('manifest_extra')) {
      context.handle(
        _manifestExtraMeta,
        manifestExtra.isAcceptableOrUnknown(
          data['manifest_extra']!,
          _manifestExtraMeta,
        ),
      );
    }
    if (data.containsKey('duration_seconds')) {
      context.handle(
        _durationSecondsMeta,
        durationSeconds.isAcceptableOrUnknown(
          data['duration_seconds']!,
          _durationSecondsMeta,
        ),
      );
    }
    if (data.containsKey('replaced_by')) {
      context.handle(
        _replacedByMeta,
        replacedBy.isAcceptableOrUnknown(data['replaced_by']!, _replacedByMeta),
      );
    }
    if (data.containsKey('adopted')) {
      context.handle(
        _adoptedMeta,
        adopted.isAcceptableOrUnknown(data['adopted']!, _adoptedMeta),
      );
    }
    if (data.containsKey('original_size')) {
      context.handle(
        _originalSizeMeta,
        originalSize.isAcceptableOrUnknown(
          data['original_size']!,
          _originalSizeMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  FileRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FileRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      folderId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}folder_id'],
      ),
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      mimeType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mime_type'],
      )!,
      kind: $DriveFilesTable.$converterkind.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}kind'],
        )!,
      ),
      size: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}size'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      modifiedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}modified_at'],
      )!,
      partCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}part_count'],
      )!,
      partsPresent: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}parts_present'],
      )!,
      starred: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}starred'],
      )!,
      minithumbnail: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}minithumbnail'],
      ),
      thumbnailFileId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}thumbnail_file_id'],
      ),
      takenAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}taken_at'],
      ),
      trashedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}trashed_at'],
      ),
      hidden: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}hidden'],
      )!,
      manifestExtra: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}manifest_extra'],
      ),
      durationSeconds: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_seconds'],
      ),
      replacedBy: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}replaced_by'],
      ),
      adopted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}adopted'],
      )!,
      originalSize: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}original_size'],
      ),
    );
  }

  @override
  $DriveFilesTable createAlias(String alias) {
    return $DriveFilesTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<FileKind, String, String> $converterkind =
      const EnumNameConverter<FileKind>(FileKind.values);
}

class FileRow extends DataClass implements Insertable<FileRow> {
  final String id;
  final String? folderId;
  final String name;
  final String mimeType;
  final FileKind kind;
  final int size;
  final DateTime createdAt;
  final DateTime modifiedAt;
  final int partCount;
  final int partsPresent;
  final bool starred;

  /// Telegram's inline blurred preview (base64 JPEG, ~40px), when it has one.
  final String? minithumbnail;

  /// TDLib file id of the server-made thumbnail, downloaded on demand.
  final int? thumbnailFileId;

  /// When a photo or video was captured, for the Photos timeline. Null for
  /// anything that isn't from the camera roll.
  final DateTime? takenAt;

  /// When it was moved to the trash.
  final DateTime? trashedAt;

  /// In the trash itself or inside a trashed folder; see [Folders.hidden].
  final bool hidden;

  /// Manifest keys this version doesn't know; see [Folders.manifestExtra].
  final String? manifestExtra;

  /// Length in seconds for video and audio; from the manifest, or learned
  /// on first play. Null until either happens.
  final int? durationSeconds;

  /// Id of the file that took this one's place when Replace moved it to the
  /// trash. Only meaningful while [trashedAt] is set.
  final String? replacedBy;

  /// Came into the channel without a manifest (forwarded, or sent from
  /// another Telegram app); lives at the root until filed.
  final bool adopted;

  /// Byte size of the original while only a small copy of it is in the
  /// drive: backup sent a reduced photo on mobile data and the full one
  /// follows. [size] stays the copy's own. Null once the original is in,
  /// and for anything that was never a small copy.
  final int? originalSize;
  const FileRow({
    required this.id,
    this.folderId,
    required this.name,
    required this.mimeType,
    required this.kind,
    required this.size,
    required this.createdAt,
    required this.modifiedAt,
    required this.partCount,
    required this.partsPresent,
    required this.starred,
    this.minithumbnail,
    this.thumbnailFileId,
    this.takenAt,
    this.trashedAt,
    required this.hidden,
    this.manifestExtra,
    this.durationSeconds,
    this.replacedBy,
    required this.adopted,
    this.originalSize,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    if (!nullToAbsent || folderId != null) {
      map['folder_id'] = Variable<String>(folderId);
    }
    map['name'] = Variable<String>(name);
    map['mime_type'] = Variable<String>(mimeType);
    {
      map['kind'] = Variable<String>(
        $DriveFilesTable.$converterkind.toSql(kind),
      );
    }
    map['size'] = Variable<int>(size);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['modified_at'] = Variable<DateTime>(modifiedAt);
    map['part_count'] = Variable<int>(partCount);
    map['parts_present'] = Variable<int>(partsPresent);
    map['starred'] = Variable<bool>(starred);
    if (!nullToAbsent || minithumbnail != null) {
      map['minithumbnail'] = Variable<String>(minithumbnail);
    }
    if (!nullToAbsent || thumbnailFileId != null) {
      map['thumbnail_file_id'] = Variable<int>(thumbnailFileId);
    }
    if (!nullToAbsent || takenAt != null) {
      map['taken_at'] = Variable<DateTime>(takenAt);
    }
    if (!nullToAbsent || trashedAt != null) {
      map['trashed_at'] = Variable<DateTime>(trashedAt);
    }
    map['hidden'] = Variable<bool>(hidden);
    if (!nullToAbsent || manifestExtra != null) {
      map['manifest_extra'] = Variable<String>(manifestExtra);
    }
    if (!nullToAbsent || durationSeconds != null) {
      map['duration_seconds'] = Variable<int>(durationSeconds);
    }
    if (!nullToAbsent || replacedBy != null) {
      map['replaced_by'] = Variable<String>(replacedBy);
    }
    map['adopted'] = Variable<bool>(adopted);
    if (!nullToAbsent || originalSize != null) {
      map['original_size'] = Variable<int>(originalSize);
    }
    return map;
  }

  DriveFilesCompanion toCompanion(bool nullToAbsent) {
    return DriveFilesCompanion(
      id: Value(id),
      folderId: folderId == null && nullToAbsent
          ? const Value.absent()
          : Value(folderId),
      name: Value(name),
      mimeType: Value(mimeType),
      kind: Value(kind),
      size: Value(size),
      createdAt: Value(createdAt),
      modifiedAt: Value(modifiedAt),
      partCount: Value(partCount),
      partsPresent: Value(partsPresent),
      starred: Value(starred),
      minithumbnail: minithumbnail == null && nullToAbsent
          ? const Value.absent()
          : Value(minithumbnail),
      thumbnailFileId: thumbnailFileId == null && nullToAbsent
          ? const Value.absent()
          : Value(thumbnailFileId),
      takenAt: takenAt == null && nullToAbsent
          ? const Value.absent()
          : Value(takenAt),
      trashedAt: trashedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(trashedAt),
      hidden: Value(hidden),
      manifestExtra: manifestExtra == null && nullToAbsent
          ? const Value.absent()
          : Value(manifestExtra),
      durationSeconds: durationSeconds == null && nullToAbsent
          ? const Value.absent()
          : Value(durationSeconds),
      replacedBy: replacedBy == null && nullToAbsent
          ? const Value.absent()
          : Value(replacedBy),
      adopted: Value(adopted),
      originalSize: originalSize == null && nullToAbsent
          ? const Value.absent()
          : Value(originalSize),
    );
  }

  factory FileRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FileRow(
      id: serializer.fromJson<String>(json['id']),
      folderId: serializer.fromJson<String?>(json['folderId']),
      name: serializer.fromJson<String>(json['name']),
      mimeType: serializer.fromJson<String>(json['mimeType']),
      kind: $DriveFilesTable.$converterkind.fromJson(
        serializer.fromJson<String>(json['kind']),
      ),
      size: serializer.fromJson<int>(json['size']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      modifiedAt: serializer.fromJson<DateTime>(json['modifiedAt']),
      partCount: serializer.fromJson<int>(json['partCount']),
      partsPresent: serializer.fromJson<int>(json['partsPresent']),
      starred: serializer.fromJson<bool>(json['starred']),
      minithumbnail: serializer.fromJson<String?>(json['minithumbnail']),
      thumbnailFileId: serializer.fromJson<int?>(json['thumbnailFileId']),
      takenAt: serializer.fromJson<DateTime?>(json['takenAt']),
      trashedAt: serializer.fromJson<DateTime?>(json['trashedAt']),
      hidden: serializer.fromJson<bool>(json['hidden']),
      manifestExtra: serializer.fromJson<String?>(json['manifestExtra']),
      durationSeconds: serializer.fromJson<int?>(json['durationSeconds']),
      replacedBy: serializer.fromJson<String?>(json['replacedBy']),
      adopted: serializer.fromJson<bool>(json['adopted']),
      originalSize: serializer.fromJson<int?>(json['originalSize']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'folderId': serializer.toJson<String?>(folderId),
      'name': serializer.toJson<String>(name),
      'mimeType': serializer.toJson<String>(mimeType),
      'kind': serializer.toJson<String>(
        $DriveFilesTable.$converterkind.toJson(kind),
      ),
      'size': serializer.toJson<int>(size),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'modifiedAt': serializer.toJson<DateTime>(modifiedAt),
      'partCount': serializer.toJson<int>(partCount),
      'partsPresent': serializer.toJson<int>(partsPresent),
      'starred': serializer.toJson<bool>(starred),
      'minithumbnail': serializer.toJson<String?>(minithumbnail),
      'thumbnailFileId': serializer.toJson<int?>(thumbnailFileId),
      'takenAt': serializer.toJson<DateTime?>(takenAt),
      'trashedAt': serializer.toJson<DateTime?>(trashedAt),
      'hidden': serializer.toJson<bool>(hidden),
      'manifestExtra': serializer.toJson<String?>(manifestExtra),
      'durationSeconds': serializer.toJson<int?>(durationSeconds),
      'replacedBy': serializer.toJson<String?>(replacedBy),
      'adopted': serializer.toJson<bool>(adopted),
      'originalSize': serializer.toJson<int?>(originalSize),
    };
  }

  FileRow copyWith({
    String? id,
    Value<String?> folderId = const Value.absent(),
    String? name,
    String? mimeType,
    FileKind? kind,
    int? size,
    DateTime? createdAt,
    DateTime? modifiedAt,
    int? partCount,
    int? partsPresent,
    bool? starred,
    Value<String?> minithumbnail = const Value.absent(),
    Value<int?> thumbnailFileId = const Value.absent(),
    Value<DateTime?> takenAt = const Value.absent(),
    Value<DateTime?> trashedAt = const Value.absent(),
    bool? hidden,
    Value<String?> manifestExtra = const Value.absent(),
    Value<int?> durationSeconds = const Value.absent(),
    Value<String?> replacedBy = const Value.absent(),
    bool? adopted,
    Value<int?> originalSize = const Value.absent(),
  }) => FileRow(
    id: id ?? this.id,
    folderId: folderId.present ? folderId.value : this.folderId,
    name: name ?? this.name,
    mimeType: mimeType ?? this.mimeType,
    kind: kind ?? this.kind,
    size: size ?? this.size,
    createdAt: createdAt ?? this.createdAt,
    modifiedAt: modifiedAt ?? this.modifiedAt,
    partCount: partCount ?? this.partCount,
    partsPresent: partsPresent ?? this.partsPresent,
    starred: starred ?? this.starred,
    minithumbnail: minithumbnail.present
        ? minithumbnail.value
        : this.minithumbnail,
    thumbnailFileId: thumbnailFileId.present
        ? thumbnailFileId.value
        : this.thumbnailFileId,
    takenAt: takenAt.present ? takenAt.value : this.takenAt,
    trashedAt: trashedAt.present ? trashedAt.value : this.trashedAt,
    hidden: hidden ?? this.hidden,
    manifestExtra: manifestExtra.present
        ? manifestExtra.value
        : this.manifestExtra,
    durationSeconds: durationSeconds.present
        ? durationSeconds.value
        : this.durationSeconds,
    replacedBy: replacedBy.present ? replacedBy.value : this.replacedBy,
    adopted: adopted ?? this.adopted,
    originalSize: originalSize.present ? originalSize.value : this.originalSize,
  );
  FileRow copyWithCompanion(DriveFilesCompanion data) {
    return FileRow(
      id: data.id.present ? data.id.value : this.id,
      folderId: data.folderId.present ? data.folderId.value : this.folderId,
      name: data.name.present ? data.name.value : this.name,
      mimeType: data.mimeType.present ? data.mimeType.value : this.mimeType,
      kind: data.kind.present ? data.kind.value : this.kind,
      size: data.size.present ? data.size.value : this.size,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      modifiedAt: data.modifiedAt.present
          ? data.modifiedAt.value
          : this.modifiedAt,
      partCount: data.partCount.present ? data.partCount.value : this.partCount,
      partsPresent: data.partsPresent.present
          ? data.partsPresent.value
          : this.partsPresent,
      starred: data.starred.present ? data.starred.value : this.starred,
      minithumbnail: data.minithumbnail.present
          ? data.minithumbnail.value
          : this.minithumbnail,
      thumbnailFileId: data.thumbnailFileId.present
          ? data.thumbnailFileId.value
          : this.thumbnailFileId,
      takenAt: data.takenAt.present ? data.takenAt.value : this.takenAt,
      trashedAt: data.trashedAt.present ? data.trashedAt.value : this.trashedAt,
      hidden: data.hidden.present ? data.hidden.value : this.hidden,
      manifestExtra: data.manifestExtra.present
          ? data.manifestExtra.value
          : this.manifestExtra,
      durationSeconds: data.durationSeconds.present
          ? data.durationSeconds.value
          : this.durationSeconds,
      replacedBy: data.replacedBy.present
          ? data.replacedBy.value
          : this.replacedBy,
      adopted: data.adopted.present ? data.adopted.value : this.adopted,
      originalSize: data.originalSize.present
          ? data.originalSize.value
          : this.originalSize,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FileRow(')
          ..write('id: $id, ')
          ..write('folderId: $folderId, ')
          ..write('name: $name, ')
          ..write('mimeType: $mimeType, ')
          ..write('kind: $kind, ')
          ..write('size: $size, ')
          ..write('createdAt: $createdAt, ')
          ..write('modifiedAt: $modifiedAt, ')
          ..write('partCount: $partCount, ')
          ..write('partsPresent: $partsPresent, ')
          ..write('starred: $starred, ')
          ..write('minithumbnail: $minithumbnail, ')
          ..write('thumbnailFileId: $thumbnailFileId, ')
          ..write('takenAt: $takenAt, ')
          ..write('trashedAt: $trashedAt, ')
          ..write('hidden: $hidden, ')
          ..write('manifestExtra: $manifestExtra, ')
          ..write('durationSeconds: $durationSeconds, ')
          ..write('replacedBy: $replacedBy, ')
          ..write('adopted: $adopted, ')
          ..write('originalSize: $originalSize')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    folderId,
    name,
    mimeType,
    kind,
    size,
    createdAt,
    modifiedAt,
    partCount,
    partsPresent,
    starred,
    minithumbnail,
    thumbnailFileId,
    takenAt,
    trashedAt,
    hidden,
    manifestExtra,
    durationSeconds,
    replacedBy,
    adopted,
    originalSize,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FileRow &&
          other.id == this.id &&
          other.folderId == this.folderId &&
          other.name == this.name &&
          other.mimeType == this.mimeType &&
          other.kind == this.kind &&
          other.size == this.size &&
          other.createdAt == this.createdAt &&
          other.modifiedAt == this.modifiedAt &&
          other.partCount == this.partCount &&
          other.partsPresent == this.partsPresent &&
          other.starred == this.starred &&
          other.minithumbnail == this.minithumbnail &&
          other.thumbnailFileId == this.thumbnailFileId &&
          other.takenAt == this.takenAt &&
          other.trashedAt == this.trashedAt &&
          other.hidden == this.hidden &&
          other.manifestExtra == this.manifestExtra &&
          other.durationSeconds == this.durationSeconds &&
          other.replacedBy == this.replacedBy &&
          other.adopted == this.adopted &&
          other.originalSize == this.originalSize);
}

class DriveFilesCompanion extends UpdateCompanion<FileRow> {
  final Value<String> id;
  final Value<String?> folderId;
  final Value<String> name;
  final Value<String> mimeType;
  final Value<FileKind> kind;
  final Value<int> size;
  final Value<DateTime> createdAt;
  final Value<DateTime> modifiedAt;
  final Value<int> partCount;
  final Value<int> partsPresent;
  final Value<bool> starred;
  final Value<String?> minithumbnail;
  final Value<int?> thumbnailFileId;
  final Value<DateTime?> takenAt;
  final Value<DateTime?> trashedAt;
  final Value<bool> hidden;
  final Value<String?> manifestExtra;
  final Value<int?> durationSeconds;
  final Value<String?> replacedBy;
  final Value<bool> adopted;
  final Value<int?> originalSize;
  final Value<int> rowid;
  const DriveFilesCompanion({
    this.id = const Value.absent(),
    this.folderId = const Value.absent(),
    this.name = const Value.absent(),
    this.mimeType = const Value.absent(),
    this.kind = const Value.absent(),
    this.size = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.modifiedAt = const Value.absent(),
    this.partCount = const Value.absent(),
    this.partsPresent = const Value.absent(),
    this.starred = const Value.absent(),
    this.minithumbnail = const Value.absent(),
    this.thumbnailFileId = const Value.absent(),
    this.takenAt = const Value.absent(),
    this.trashedAt = const Value.absent(),
    this.hidden = const Value.absent(),
    this.manifestExtra = const Value.absent(),
    this.durationSeconds = const Value.absent(),
    this.replacedBy = const Value.absent(),
    this.adopted = const Value.absent(),
    this.originalSize = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DriveFilesCompanion.insert({
    required String id,
    this.folderId = const Value.absent(),
    required String name,
    required String mimeType,
    required FileKind kind,
    required int size,
    required DateTime createdAt,
    required DateTime modifiedAt,
    this.partCount = const Value.absent(),
    this.partsPresent = const Value.absent(),
    this.starred = const Value.absent(),
    this.minithumbnail = const Value.absent(),
    this.thumbnailFileId = const Value.absent(),
    this.takenAt = const Value.absent(),
    this.trashedAt = const Value.absent(),
    this.hidden = const Value.absent(),
    this.manifestExtra = const Value.absent(),
    this.durationSeconds = const Value.absent(),
    this.replacedBy = const Value.absent(),
    this.adopted = const Value.absent(),
    this.originalSize = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       mimeType = Value(mimeType),
       kind = Value(kind),
       size = Value(size),
       createdAt = Value(createdAt),
       modifiedAt = Value(modifiedAt);
  static Insertable<FileRow> custom({
    Expression<String>? id,
    Expression<String>? folderId,
    Expression<String>? name,
    Expression<String>? mimeType,
    Expression<String>? kind,
    Expression<int>? size,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? modifiedAt,
    Expression<int>? partCount,
    Expression<int>? partsPresent,
    Expression<bool>? starred,
    Expression<String>? minithumbnail,
    Expression<int>? thumbnailFileId,
    Expression<DateTime>? takenAt,
    Expression<DateTime>? trashedAt,
    Expression<bool>? hidden,
    Expression<String>? manifestExtra,
    Expression<int>? durationSeconds,
    Expression<String>? replacedBy,
    Expression<bool>? adopted,
    Expression<int>? originalSize,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (folderId != null) 'folder_id': folderId,
      if (name != null) 'name': name,
      if (mimeType != null) 'mime_type': mimeType,
      if (kind != null) 'kind': kind,
      if (size != null) 'size': size,
      if (createdAt != null) 'created_at': createdAt,
      if (modifiedAt != null) 'modified_at': modifiedAt,
      if (partCount != null) 'part_count': partCount,
      if (partsPresent != null) 'parts_present': partsPresent,
      if (starred != null) 'starred': starred,
      if (minithumbnail != null) 'minithumbnail': minithumbnail,
      if (thumbnailFileId != null) 'thumbnail_file_id': thumbnailFileId,
      if (takenAt != null) 'taken_at': takenAt,
      if (trashedAt != null) 'trashed_at': trashedAt,
      if (hidden != null) 'hidden': hidden,
      if (manifestExtra != null) 'manifest_extra': manifestExtra,
      if (durationSeconds != null) 'duration_seconds': durationSeconds,
      if (replacedBy != null) 'replaced_by': replacedBy,
      if (adopted != null) 'adopted': adopted,
      if (originalSize != null) 'original_size': originalSize,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DriveFilesCompanion copyWith({
    Value<String>? id,
    Value<String?>? folderId,
    Value<String>? name,
    Value<String>? mimeType,
    Value<FileKind>? kind,
    Value<int>? size,
    Value<DateTime>? createdAt,
    Value<DateTime>? modifiedAt,
    Value<int>? partCount,
    Value<int>? partsPresent,
    Value<bool>? starred,
    Value<String?>? minithumbnail,
    Value<int?>? thumbnailFileId,
    Value<DateTime?>? takenAt,
    Value<DateTime?>? trashedAt,
    Value<bool>? hidden,
    Value<String?>? manifestExtra,
    Value<int?>? durationSeconds,
    Value<String?>? replacedBy,
    Value<bool>? adopted,
    Value<int?>? originalSize,
    Value<int>? rowid,
  }) {
    return DriveFilesCompanion(
      id: id ?? this.id,
      folderId: folderId ?? this.folderId,
      name: name ?? this.name,
      mimeType: mimeType ?? this.mimeType,
      kind: kind ?? this.kind,
      size: size ?? this.size,
      createdAt: createdAt ?? this.createdAt,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      partCount: partCount ?? this.partCount,
      partsPresent: partsPresent ?? this.partsPresent,
      starred: starred ?? this.starred,
      minithumbnail: minithumbnail ?? this.minithumbnail,
      thumbnailFileId: thumbnailFileId ?? this.thumbnailFileId,
      takenAt: takenAt ?? this.takenAt,
      trashedAt: trashedAt ?? this.trashedAt,
      hidden: hidden ?? this.hidden,
      manifestExtra: manifestExtra ?? this.manifestExtra,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      replacedBy: replacedBy ?? this.replacedBy,
      adopted: adopted ?? this.adopted,
      originalSize: originalSize ?? this.originalSize,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (folderId.present) {
      map['folder_id'] = Variable<String>(folderId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (mimeType.present) {
      map['mime_type'] = Variable<String>(mimeType.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(
        $DriveFilesTable.$converterkind.toSql(kind.value),
      );
    }
    if (size.present) {
      map['size'] = Variable<int>(size.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (modifiedAt.present) {
      map['modified_at'] = Variable<DateTime>(modifiedAt.value);
    }
    if (partCount.present) {
      map['part_count'] = Variable<int>(partCount.value);
    }
    if (partsPresent.present) {
      map['parts_present'] = Variable<int>(partsPresent.value);
    }
    if (starred.present) {
      map['starred'] = Variable<bool>(starred.value);
    }
    if (minithumbnail.present) {
      map['minithumbnail'] = Variable<String>(minithumbnail.value);
    }
    if (thumbnailFileId.present) {
      map['thumbnail_file_id'] = Variable<int>(thumbnailFileId.value);
    }
    if (takenAt.present) {
      map['taken_at'] = Variable<DateTime>(takenAt.value);
    }
    if (trashedAt.present) {
      map['trashed_at'] = Variable<DateTime>(trashedAt.value);
    }
    if (hidden.present) {
      map['hidden'] = Variable<bool>(hidden.value);
    }
    if (manifestExtra.present) {
      map['manifest_extra'] = Variable<String>(manifestExtra.value);
    }
    if (durationSeconds.present) {
      map['duration_seconds'] = Variable<int>(durationSeconds.value);
    }
    if (replacedBy.present) {
      map['replaced_by'] = Variable<String>(replacedBy.value);
    }
    if (adopted.present) {
      map['adopted'] = Variable<bool>(adopted.value);
    }
    if (originalSize.present) {
      map['original_size'] = Variable<int>(originalSize.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DriveFilesCompanion(')
          ..write('id: $id, ')
          ..write('folderId: $folderId, ')
          ..write('name: $name, ')
          ..write('mimeType: $mimeType, ')
          ..write('kind: $kind, ')
          ..write('size: $size, ')
          ..write('createdAt: $createdAt, ')
          ..write('modifiedAt: $modifiedAt, ')
          ..write('partCount: $partCount, ')
          ..write('partsPresent: $partsPresent, ')
          ..write('starred: $starred, ')
          ..write('minithumbnail: $minithumbnail, ')
          ..write('thumbnailFileId: $thumbnailFileId, ')
          ..write('takenAt: $takenAt, ')
          ..write('trashedAt: $trashedAt, ')
          ..write('hidden: $hidden, ')
          ..write('manifestExtra: $manifestExtra, ')
          ..write('durationSeconds: $durationSeconds, ')
          ..write('replacedBy: $replacedBy, ')
          ..write('adopted: $adopted, ')
          ..write('originalSize: $originalSize, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $FilePartsTable extends FileParts
    with TableInfo<$FilePartsTable, PartRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FilePartsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _fileIdMeta = const VerificationMeta('fileId');
  @override
  late final GeneratedColumn<String> fileId = GeneratedColumn<String>(
    'file_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _partIndexMeta = const VerificationMeta(
    'partIndex',
  );
  @override
  late final GeneratedColumn<int> partIndex = GeneratedColumn<int>(
    'part_index',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _messageIdMeta = const VerificationMeta(
    'messageId',
  );
  @override
  late final GeneratedColumn<int> messageId = GeneratedColumn<int>(
    'message_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _tdFileIdMeta = const VerificationMeta(
    'tdFileId',
  );
  @override
  late final GeneratedColumn<int> tdFileId = GeneratedColumn<int>(
    'td_file_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sizeMeta = const VerificationMeta('size');
  @override
  late final GeneratedColumn<int> size = GeneratedColumn<int>(
    'size',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    fileId,
    partIndex,
    messageId,
    tdFileId,
    size,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'file_parts';
  @override
  VerificationContext validateIntegrity(
    Insertable<PartRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('file_id')) {
      context.handle(
        _fileIdMeta,
        fileId.isAcceptableOrUnknown(data['file_id']!, _fileIdMeta),
      );
    } else if (isInserting) {
      context.missing(_fileIdMeta);
    }
    if (data.containsKey('part_index')) {
      context.handle(
        _partIndexMeta,
        partIndex.isAcceptableOrUnknown(data['part_index']!, _partIndexMeta),
      );
    } else if (isInserting) {
      context.missing(_partIndexMeta);
    }
    if (data.containsKey('message_id')) {
      context.handle(
        _messageIdMeta,
        messageId.isAcceptableOrUnknown(data['message_id']!, _messageIdMeta),
      );
    } else if (isInserting) {
      context.missing(_messageIdMeta);
    }
    if (data.containsKey('td_file_id')) {
      context.handle(
        _tdFileIdMeta,
        tdFileId.isAcceptableOrUnknown(data['td_file_id']!, _tdFileIdMeta),
      );
    } else if (isInserting) {
      context.missing(_tdFileIdMeta);
    }
    if (data.containsKey('size')) {
      context.handle(
        _sizeMeta,
        size.isAcceptableOrUnknown(data['size']!, _sizeMeta),
      );
    } else if (isInserting) {
      context.missing(_sizeMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {fileId, partIndex};
  @override
  PartRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PartRow(
      fileId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}file_id'],
      )!,
      partIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}part_index'],
      )!,
      messageId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}message_id'],
      )!,
      tdFileId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}td_file_id'],
      )!,
      size: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}size'],
      )!,
    );
  }

  @override
  $FilePartsTable createAlias(String alias) {
    return $FilePartsTable(attachedDatabase, alias);
  }
}

class PartRow extends DataClass implements Insertable<PartRow> {
  final String fileId;
  final int partIndex;
  final int messageId;

  /// TDLib's id for the document in the run that indexed it. TDLib's file
  /// ids last one run, so the file is read from [messageId] instead.
  final int tdFileId;
  final int size;
  const PartRow({
    required this.fileId,
    required this.partIndex,
    required this.messageId,
    required this.tdFileId,
    required this.size,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['file_id'] = Variable<String>(fileId);
    map['part_index'] = Variable<int>(partIndex);
    map['message_id'] = Variable<int>(messageId);
    map['td_file_id'] = Variable<int>(tdFileId);
    map['size'] = Variable<int>(size);
    return map;
  }

  FilePartsCompanion toCompanion(bool nullToAbsent) {
    return FilePartsCompanion(
      fileId: Value(fileId),
      partIndex: Value(partIndex),
      messageId: Value(messageId),
      tdFileId: Value(tdFileId),
      size: Value(size),
    );
  }

  factory PartRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PartRow(
      fileId: serializer.fromJson<String>(json['fileId']),
      partIndex: serializer.fromJson<int>(json['partIndex']),
      messageId: serializer.fromJson<int>(json['messageId']),
      tdFileId: serializer.fromJson<int>(json['tdFileId']),
      size: serializer.fromJson<int>(json['size']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'fileId': serializer.toJson<String>(fileId),
      'partIndex': serializer.toJson<int>(partIndex),
      'messageId': serializer.toJson<int>(messageId),
      'tdFileId': serializer.toJson<int>(tdFileId),
      'size': serializer.toJson<int>(size),
    };
  }

  PartRow copyWith({
    String? fileId,
    int? partIndex,
    int? messageId,
    int? tdFileId,
    int? size,
  }) => PartRow(
    fileId: fileId ?? this.fileId,
    partIndex: partIndex ?? this.partIndex,
    messageId: messageId ?? this.messageId,
    tdFileId: tdFileId ?? this.tdFileId,
    size: size ?? this.size,
  );
  PartRow copyWithCompanion(FilePartsCompanion data) {
    return PartRow(
      fileId: data.fileId.present ? data.fileId.value : this.fileId,
      partIndex: data.partIndex.present ? data.partIndex.value : this.partIndex,
      messageId: data.messageId.present ? data.messageId.value : this.messageId,
      tdFileId: data.tdFileId.present ? data.tdFileId.value : this.tdFileId,
      size: data.size.present ? data.size.value : this.size,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PartRow(')
          ..write('fileId: $fileId, ')
          ..write('partIndex: $partIndex, ')
          ..write('messageId: $messageId, ')
          ..write('tdFileId: $tdFileId, ')
          ..write('size: $size')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(fileId, partIndex, messageId, tdFileId, size);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PartRow &&
          other.fileId == this.fileId &&
          other.partIndex == this.partIndex &&
          other.messageId == this.messageId &&
          other.tdFileId == this.tdFileId &&
          other.size == this.size);
}

class FilePartsCompanion extends UpdateCompanion<PartRow> {
  final Value<String> fileId;
  final Value<int> partIndex;
  final Value<int> messageId;
  final Value<int> tdFileId;
  final Value<int> size;
  final Value<int> rowid;
  const FilePartsCompanion({
    this.fileId = const Value.absent(),
    this.partIndex = const Value.absent(),
    this.messageId = const Value.absent(),
    this.tdFileId = const Value.absent(),
    this.size = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FilePartsCompanion.insert({
    required String fileId,
    required int partIndex,
    required int messageId,
    required int tdFileId,
    required int size,
    this.rowid = const Value.absent(),
  }) : fileId = Value(fileId),
       partIndex = Value(partIndex),
       messageId = Value(messageId),
       tdFileId = Value(tdFileId),
       size = Value(size);
  static Insertable<PartRow> custom({
    Expression<String>? fileId,
    Expression<int>? partIndex,
    Expression<int>? messageId,
    Expression<int>? tdFileId,
    Expression<int>? size,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (fileId != null) 'file_id': fileId,
      if (partIndex != null) 'part_index': partIndex,
      if (messageId != null) 'message_id': messageId,
      if (tdFileId != null) 'td_file_id': tdFileId,
      if (size != null) 'size': size,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FilePartsCompanion copyWith({
    Value<String>? fileId,
    Value<int>? partIndex,
    Value<int>? messageId,
    Value<int>? tdFileId,
    Value<int>? size,
    Value<int>? rowid,
  }) {
    return FilePartsCompanion(
      fileId: fileId ?? this.fileId,
      partIndex: partIndex ?? this.partIndex,
      messageId: messageId ?? this.messageId,
      tdFileId: tdFileId ?? this.tdFileId,
      size: size ?? this.size,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (fileId.present) {
      map['file_id'] = Variable<String>(fileId.value);
    }
    if (partIndex.present) {
      map['part_index'] = Variable<int>(partIndex.value);
    }
    if (messageId.present) {
      map['message_id'] = Variable<int>(messageId.value);
    }
    if (tdFileId.present) {
      map['td_file_id'] = Variable<int>(tdFileId.value);
    }
    if (size.present) {
      map['size'] = Variable<int>(size.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FilePartsCompanion(')
          ..write('fileId: $fileId, ')
          ..write('partIndex: $partIndex, ')
          ..write('messageId: $messageId, ')
          ..write('tdFileId: $tdFileId, ')
          ..write('size: $size, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TransfersTable extends Transfers
    with TableInfo<$TransfersTable, TransferRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TransfersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<TransferKind, String> kind =
      GeneratedColumn<String>(
        'kind',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<TransferKind>($TransfersTable.$converterkind);
  @override
  late final GeneratedColumnWithTypeConverter<TransferStatus, String> status =
      GeneratedColumn<String>(
        'status',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<TransferStatus>($TransfersTable.$converterstatus);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _mimeTypeMeta = const VerificationMeta(
    'mimeType',
  );
  @override
  late final GeneratedColumn<String> mimeType = GeneratedColumn<String>(
    'mime_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fileIdMeta = const VerificationMeta('fileId');
  @override
  late final GeneratedColumn<String> fileId = GeneratedColumn<String>(
    'file_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _folderIdMeta = const VerificationMeta(
    'folderId',
  );
  @override
  late final GeneratedColumn<String> folderId = GeneratedColumn<String>(
    'folder_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sourcePathMeta = const VerificationMeta(
    'sourcePath',
  );
  @override
  late final GeneratedColumn<String> sourcePath = GeneratedColumn<String>(
    'source_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _ownsSourceMeta = const VerificationMeta(
    'ownsSource',
  );
  @override
  late final GeneratedColumn<bool> ownsSource = GeneratedColumn<bool>(
    'owns_source',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("owns_source" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _resultPathMeta = const VerificationMeta(
    'resultPath',
  );
  @override
  late final GeneratedColumn<String> resultPath = GeneratedColumn<String>(
    'result_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _totalBytesMeta = const VerificationMeta(
    'totalBytes',
  );
  @override
  late final GeneratedColumn<int> totalBytes = GeneratedColumn<int>(
    'total_bytes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _doneBytesMeta = const VerificationMeta(
    'doneBytes',
  );
  @override
  late final GeneratedColumn<int> doneBytes = GeneratedColumn<int>(
    'done_bytes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _partCountMeta = const VerificationMeta(
    'partCount',
  );
  @override
  late final GeneratedColumn<int> partCount = GeneratedColumn<int>(
    'part_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _completedPartsMeta = const VerificationMeta(
    'completedParts',
  );
  @override
  late final GeneratedColumn<int> completedParts = GeneratedColumn<int>(
    'completed_parts',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _errorMeta = const VerificationMeta('error');
  @override
  late final GeneratedColumn<String> error = GeneratedColumn<String>(
    'error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _finishedAtMeta = const VerificationMeta(
    'finishedAt',
  );
  @override
  late final GeneratedColumn<DateTime> finishedAt = GeneratedColumn<DateTime>(
    'finished_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<TransferOrigin, String> origin =
      GeneratedColumn<String>(
        'origin',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: Constant(TransferOrigin.manual.name),
      ).withConverter<TransferOrigin>($TransfersTable.$converterorigin);
  static const VerificationMeta _assetIdMeta = const VerificationMeta(
    'assetId',
  );
  @override
  late final GeneratedColumn<String> assetId = GeneratedColumn<String>(
    'asset_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _takenAtMeta = const VerificationMeta(
    'takenAt',
  );
  @override
  late final GeneratedColumn<DateTime> takenAt = GeneratedColumn<DateTime>(
    'taken_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _thumbnailPathMeta = const VerificationMeta(
    'thumbnailPath',
  );
  @override
  late final GeneratedColumn<String> thumbnailPath = GeneratedColumn<String>(
    'thumbnail_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<SaveTarget?, String> saveTo =
      GeneratedColumn<String>(
        'save_to',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      ).withConverter<SaveTarget?>($TransfersTable.$convertersaveTon);
  static const VerificationMeta _saveFolderMeta = const VerificationMeta(
    'saveFolder',
  );
  @override
  late final GeneratedColumn<String> saveFolder = GeneratedColumn<String>(
    'save_folder',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _wifiOnlyMeta = const VerificationMeta(
    'wifiOnly',
  );
  @override
  late final GeneratedColumn<bool> wifiOnly = GeneratedColumn<bool>(
    'wifi_only',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("wifi_only" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _durationSecondsMeta = const VerificationMeta(
    'durationSeconds',
  );
  @override
  late final GeneratedColumn<int> durationSeconds = GeneratedColumn<int>(
    'duration_seconds',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _replacesFileIdMeta = const VerificationMeta(
    'replacesFileId',
  );
  @override
  late final GeneratedColumn<String> replacesFileId = GeneratedColumn<String>(
    'replaces_file_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sourceChatIdMeta = const VerificationMeta(
    'sourceChatId',
  );
  @override
  late final GeneratedColumn<int> sourceChatId = GeneratedColumn<int>(
    'source_chat_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sourceMessageIdMeta = const VerificationMeta(
    'sourceMessageId',
  );
  @override
  late final GeneratedColumn<int> sourceMessageId = GeneratedColumn<int>(
    'source_message_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    kind,
    status,
    name,
    mimeType,
    fileId,
    folderId,
    sourcePath,
    ownsSource,
    resultPath,
    totalBytes,
    doneBytes,
    partCount,
    completedParts,
    error,
    createdAt,
    finishedAt,
    origin,
    assetId,
    takenAt,
    thumbnailPath,
    saveTo,
    saveFolder,
    wifiOnly,
    durationSeconds,
    replacesFileId,
    sourceChatId,
    sourceMessageId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'transfers';
  @override
  VerificationContext validateIntegrity(
    Insertable<TransferRow> instance, {
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
    if (data.containsKey('mime_type')) {
      context.handle(
        _mimeTypeMeta,
        mimeType.isAcceptableOrUnknown(data['mime_type']!, _mimeTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_mimeTypeMeta);
    }
    if (data.containsKey('file_id')) {
      context.handle(
        _fileIdMeta,
        fileId.isAcceptableOrUnknown(data['file_id']!, _fileIdMeta),
      );
    } else if (isInserting) {
      context.missing(_fileIdMeta);
    }
    if (data.containsKey('folder_id')) {
      context.handle(
        _folderIdMeta,
        folderId.isAcceptableOrUnknown(data['folder_id']!, _folderIdMeta),
      );
    }
    if (data.containsKey('source_path')) {
      context.handle(
        _sourcePathMeta,
        sourcePath.isAcceptableOrUnknown(data['source_path']!, _sourcePathMeta),
      );
    }
    if (data.containsKey('owns_source')) {
      context.handle(
        _ownsSourceMeta,
        ownsSource.isAcceptableOrUnknown(data['owns_source']!, _ownsSourceMeta),
      );
    }
    if (data.containsKey('result_path')) {
      context.handle(
        _resultPathMeta,
        resultPath.isAcceptableOrUnknown(data['result_path']!, _resultPathMeta),
      );
    }
    if (data.containsKey('total_bytes')) {
      context.handle(
        _totalBytesMeta,
        totalBytes.isAcceptableOrUnknown(data['total_bytes']!, _totalBytesMeta),
      );
    } else if (isInserting) {
      context.missing(_totalBytesMeta);
    }
    if (data.containsKey('done_bytes')) {
      context.handle(
        _doneBytesMeta,
        doneBytes.isAcceptableOrUnknown(data['done_bytes']!, _doneBytesMeta),
      );
    }
    if (data.containsKey('part_count')) {
      context.handle(
        _partCountMeta,
        partCount.isAcceptableOrUnknown(data['part_count']!, _partCountMeta),
      );
    }
    if (data.containsKey('completed_parts')) {
      context.handle(
        _completedPartsMeta,
        completedParts.isAcceptableOrUnknown(
          data['completed_parts']!,
          _completedPartsMeta,
        ),
      );
    }
    if (data.containsKey('error')) {
      context.handle(
        _errorMeta,
        error.isAcceptableOrUnknown(data['error']!, _errorMeta),
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
    if (data.containsKey('finished_at')) {
      context.handle(
        _finishedAtMeta,
        finishedAt.isAcceptableOrUnknown(data['finished_at']!, _finishedAtMeta),
      );
    }
    if (data.containsKey('asset_id')) {
      context.handle(
        _assetIdMeta,
        assetId.isAcceptableOrUnknown(data['asset_id']!, _assetIdMeta),
      );
    }
    if (data.containsKey('taken_at')) {
      context.handle(
        _takenAtMeta,
        takenAt.isAcceptableOrUnknown(data['taken_at']!, _takenAtMeta),
      );
    }
    if (data.containsKey('thumbnail_path')) {
      context.handle(
        _thumbnailPathMeta,
        thumbnailPath.isAcceptableOrUnknown(
          data['thumbnail_path']!,
          _thumbnailPathMeta,
        ),
      );
    }
    if (data.containsKey('save_folder')) {
      context.handle(
        _saveFolderMeta,
        saveFolder.isAcceptableOrUnknown(data['save_folder']!, _saveFolderMeta),
      );
    }
    if (data.containsKey('wifi_only')) {
      context.handle(
        _wifiOnlyMeta,
        wifiOnly.isAcceptableOrUnknown(data['wifi_only']!, _wifiOnlyMeta),
      );
    }
    if (data.containsKey('duration_seconds')) {
      context.handle(
        _durationSecondsMeta,
        durationSeconds.isAcceptableOrUnknown(
          data['duration_seconds']!,
          _durationSecondsMeta,
        ),
      );
    }
    if (data.containsKey('replaces_file_id')) {
      context.handle(
        _replacesFileIdMeta,
        replacesFileId.isAcceptableOrUnknown(
          data['replaces_file_id']!,
          _replacesFileIdMeta,
        ),
      );
    }
    if (data.containsKey('source_chat_id')) {
      context.handle(
        _sourceChatIdMeta,
        sourceChatId.isAcceptableOrUnknown(
          data['source_chat_id']!,
          _sourceChatIdMeta,
        ),
      );
    }
    if (data.containsKey('source_message_id')) {
      context.handle(
        _sourceMessageIdMeta,
        sourceMessageId.isAcceptableOrUnknown(
          data['source_message_id']!,
          _sourceMessageIdMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TransferRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TransferRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      kind: $TransfersTable.$converterkind.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}kind'],
        )!,
      ),
      status: $TransfersTable.$converterstatus.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}status'],
        )!,
      ),
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      mimeType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mime_type'],
      )!,
      fileId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}file_id'],
      )!,
      folderId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}folder_id'],
      ),
      sourcePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_path'],
      ),
      ownsSource: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}owns_source'],
      )!,
      resultPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}result_path'],
      ),
      totalBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}total_bytes'],
      )!,
      doneBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}done_bytes'],
      )!,
      partCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}part_count'],
      )!,
      completedParts: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}completed_parts'],
      )!,
      error: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}error'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      finishedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}finished_at'],
      ),
      origin: $TransfersTable.$converterorigin.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}origin'],
        )!,
      ),
      assetId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}asset_id'],
      ),
      takenAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}taken_at'],
      ),
      thumbnailPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}thumbnail_path'],
      ),
      saveTo: $TransfersTable.$convertersaveTon.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}save_to'],
        ),
      ),
      saveFolder: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}save_folder'],
      ),
      wifiOnly: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}wifi_only'],
      )!,
      durationSeconds: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_seconds'],
      ),
      replacesFileId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}replaces_file_id'],
      ),
      sourceChatId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}source_chat_id'],
      ),
      sourceMessageId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}source_message_id'],
      ),
    );
  }

  @override
  $TransfersTable createAlias(String alias) {
    return $TransfersTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<TransferKind, String, String> $converterkind =
      const EnumNameConverter<TransferKind>(TransferKind.values);
  static JsonTypeConverter2<TransferStatus, String, String> $converterstatus =
      const EnumNameConverter<TransferStatus>(TransferStatus.values);
  static JsonTypeConverter2<TransferOrigin, String, String> $converterorigin =
      const EnumNameConverter<TransferOrigin>(TransferOrigin.values);
  static JsonTypeConverter2<SaveTarget, String, String> $convertersaveTo =
      const EnumNameConverter<SaveTarget>(SaveTarget.values);
  static JsonTypeConverter2<SaveTarget?, String?, String?> $convertersaveTon =
      JsonTypeConverter2.asNullable($convertersaveTo);
}

class TransferRow extends DataClass implements Insertable<TransferRow> {
  final String id;
  final TransferKind kind;
  final TransferStatus status;
  final String name;
  final String mimeType;

  /// Drive file this transfer creates (upload) or reads (download).
  final String fileId;
  final String? folderId;

  /// Upload source on disk.
  final String? sourcePath;

  /// True when [sourcePath] is our own temporary copy (the file picker copies
  /// content URIs into the cache) and should be removed once uploaded.
  final bool ownsSource;

  /// Download result on disk.
  final String? resultPath;
  final int totalBytes;
  final int doneBytes;
  final int partCount;
  final int completedParts;
  final String? error;
  final DateTime createdAt;
  final DateTime? finishedAt;
  final TransferOrigin origin;

  /// Camera-roll asset a backup upload came from.
  final String? assetId;

  /// Capture time carried into the manifest (backup uploads). For a copy
  /// from a chat, the original message's date, which becomes the manifest's
  /// created date and, for photos and videos, its capture time.
  final DateTime? takenAt;

  /// Small JPEG sent as the document's thumbnail, so videos get previews.
  final String? thumbnailPath;

  /// Where a download is copied once it arrives (save transfers).
  final SaveTarget? saveTo;

  /// Folders under the save location, `/`-separated, so the drive's layout
  /// carries over; for the gallery, the album it goes back into.
  final String? saveFolder;

  /// Waits for an unmetered network: chosen as "Later, on Wi-Fi", or big and
  /// started on Wi-Fi. A phone's hotspot counts as mobile data.
  final bool wifiOnly;

  /// Length in seconds of a video or audio upload, carried into its
  /// manifest.
  final int? durationSeconds;

  /// Drive file this upload replaces: once it lands, that one goes to the
  /// trash pointing back at the new one.
  final String? replacesFileId;

  /// Chat holding the message a copy from a chat is made from.
  final int? sourceChatId;

  /// That message's id in [sourceChatId], so the copy can be made again, or
  /// found half-done, after a restart.
  final int? sourceMessageId;
  const TransferRow({
    required this.id,
    required this.kind,
    required this.status,
    required this.name,
    required this.mimeType,
    required this.fileId,
    this.folderId,
    this.sourcePath,
    required this.ownsSource,
    this.resultPath,
    required this.totalBytes,
    required this.doneBytes,
    required this.partCount,
    required this.completedParts,
    this.error,
    required this.createdAt,
    this.finishedAt,
    required this.origin,
    this.assetId,
    this.takenAt,
    this.thumbnailPath,
    this.saveTo,
    this.saveFolder,
    required this.wifiOnly,
    this.durationSeconds,
    this.replacesFileId,
    this.sourceChatId,
    this.sourceMessageId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    {
      map['kind'] = Variable<String>(
        $TransfersTable.$converterkind.toSql(kind),
      );
    }
    {
      map['status'] = Variable<String>(
        $TransfersTable.$converterstatus.toSql(status),
      );
    }
    map['name'] = Variable<String>(name);
    map['mime_type'] = Variable<String>(mimeType);
    map['file_id'] = Variable<String>(fileId);
    if (!nullToAbsent || folderId != null) {
      map['folder_id'] = Variable<String>(folderId);
    }
    if (!nullToAbsent || sourcePath != null) {
      map['source_path'] = Variable<String>(sourcePath);
    }
    map['owns_source'] = Variable<bool>(ownsSource);
    if (!nullToAbsent || resultPath != null) {
      map['result_path'] = Variable<String>(resultPath);
    }
    map['total_bytes'] = Variable<int>(totalBytes);
    map['done_bytes'] = Variable<int>(doneBytes);
    map['part_count'] = Variable<int>(partCount);
    map['completed_parts'] = Variable<int>(completedParts);
    if (!nullToAbsent || error != null) {
      map['error'] = Variable<String>(error);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    if (!nullToAbsent || finishedAt != null) {
      map['finished_at'] = Variable<DateTime>(finishedAt);
    }
    {
      map['origin'] = Variable<String>(
        $TransfersTable.$converterorigin.toSql(origin),
      );
    }
    if (!nullToAbsent || assetId != null) {
      map['asset_id'] = Variable<String>(assetId);
    }
    if (!nullToAbsent || takenAt != null) {
      map['taken_at'] = Variable<DateTime>(takenAt);
    }
    if (!nullToAbsent || thumbnailPath != null) {
      map['thumbnail_path'] = Variable<String>(thumbnailPath);
    }
    if (!nullToAbsent || saveTo != null) {
      map['save_to'] = Variable<String>(
        $TransfersTable.$convertersaveTon.toSql(saveTo),
      );
    }
    if (!nullToAbsent || saveFolder != null) {
      map['save_folder'] = Variable<String>(saveFolder);
    }
    map['wifi_only'] = Variable<bool>(wifiOnly);
    if (!nullToAbsent || durationSeconds != null) {
      map['duration_seconds'] = Variable<int>(durationSeconds);
    }
    if (!nullToAbsent || replacesFileId != null) {
      map['replaces_file_id'] = Variable<String>(replacesFileId);
    }
    if (!nullToAbsent || sourceChatId != null) {
      map['source_chat_id'] = Variable<int>(sourceChatId);
    }
    if (!nullToAbsent || sourceMessageId != null) {
      map['source_message_id'] = Variable<int>(sourceMessageId);
    }
    return map;
  }

  TransfersCompanion toCompanion(bool nullToAbsent) {
    return TransfersCompanion(
      id: Value(id),
      kind: Value(kind),
      status: Value(status),
      name: Value(name),
      mimeType: Value(mimeType),
      fileId: Value(fileId),
      folderId: folderId == null && nullToAbsent
          ? const Value.absent()
          : Value(folderId),
      sourcePath: sourcePath == null && nullToAbsent
          ? const Value.absent()
          : Value(sourcePath),
      ownsSource: Value(ownsSource),
      resultPath: resultPath == null && nullToAbsent
          ? const Value.absent()
          : Value(resultPath),
      totalBytes: Value(totalBytes),
      doneBytes: Value(doneBytes),
      partCount: Value(partCount),
      completedParts: Value(completedParts),
      error: error == null && nullToAbsent
          ? const Value.absent()
          : Value(error),
      createdAt: Value(createdAt),
      finishedAt: finishedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(finishedAt),
      origin: Value(origin),
      assetId: assetId == null && nullToAbsent
          ? const Value.absent()
          : Value(assetId),
      takenAt: takenAt == null && nullToAbsent
          ? const Value.absent()
          : Value(takenAt),
      thumbnailPath: thumbnailPath == null && nullToAbsent
          ? const Value.absent()
          : Value(thumbnailPath),
      saveTo: saveTo == null && nullToAbsent
          ? const Value.absent()
          : Value(saveTo),
      saveFolder: saveFolder == null && nullToAbsent
          ? const Value.absent()
          : Value(saveFolder),
      wifiOnly: Value(wifiOnly),
      durationSeconds: durationSeconds == null && nullToAbsent
          ? const Value.absent()
          : Value(durationSeconds),
      replacesFileId: replacesFileId == null && nullToAbsent
          ? const Value.absent()
          : Value(replacesFileId),
      sourceChatId: sourceChatId == null && nullToAbsent
          ? const Value.absent()
          : Value(sourceChatId),
      sourceMessageId: sourceMessageId == null && nullToAbsent
          ? const Value.absent()
          : Value(sourceMessageId),
    );
  }

  factory TransferRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TransferRow(
      id: serializer.fromJson<String>(json['id']),
      kind: $TransfersTable.$converterkind.fromJson(
        serializer.fromJson<String>(json['kind']),
      ),
      status: $TransfersTable.$converterstatus.fromJson(
        serializer.fromJson<String>(json['status']),
      ),
      name: serializer.fromJson<String>(json['name']),
      mimeType: serializer.fromJson<String>(json['mimeType']),
      fileId: serializer.fromJson<String>(json['fileId']),
      folderId: serializer.fromJson<String?>(json['folderId']),
      sourcePath: serializer.fromJson<String?>(json['sourcePath']),
      ownsSource: serializer.fromJson<bool>(json['ownsSource']),
      resultPath: serializer.fromJson<String?>(json['resultPath']),
      totalBytes: serializer.fromJson<int>(json['totalBytes']),
      doneBytes: serializer.fromJson<int>(json['doneBytes']),
      partCount: serializer.fromJson<int>(json['partCount']),
      completedParts: serializer.fromJson<int>(json['completedParts']),
      error: serializer.fromJson<String?>(json['error']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      finishedAt: serializer.fromJson<DateTime?>(json['finishedAt']),
      origin: $TransfersTable.$converterorigin.fromJson(
        serializer.fromJson<String>(json['origin']),
      ),
      assetId: serializer.fromJson<String?>(json['assetId']),
      takenAt: serializer.fromJson<DateTime?>(json['takenAt']),
      thumbnailPath: serializer.fromJson<String?>(json['thumbnailPath']),
      saveTo: $TransfersTable.$convertersaveTon.fromJson(
        serializer.fromJson<String?>(json['saveTo']),
      ),
      saveFolder: serializer.fromJson<String?>(json['saveFolder']),
      wifiOnly: serializer.fromJson<bool>(json['wifiOnly']),
      durationSeconds: serializer.fromJson<int?>(json['durationSeconds']),
      replacesFileId: serializer.fromJson<String?>(json['replacesFileId']),
      sourceChatId: serializer.fromJson<int?>(json['sourceChatId']),
      sourceMessageId: serializer.fromJson<int?>(json['sourceMessageId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'kind': serializer.toJson<String>(
        $TransfersTable.$converterkind.toJson(kind),
      ),
      'status': serializer.toJson<String>(
        $TransfersTable.$converterstatus.toJson(status),
      ),
      'name': serializer.toJson<String>(name),
      'mimeType': serializer.toJson<String>(mimeType),
      'fileId': serializer.toJson<String>(fileId),
      'folderId': serializer.toJson<String?>(folderId),
      'sourcePath': serializer.toJson<String?>(sourcePath),
      'ownsSource': serializer.toJson<bool>(ownsSource),
      'resultPath': serializer.toJson<String?>(resultPath),
      'totalBytes': serializer.toJson<int>(totalBytes),
      'doneBytes': serializer.toJson<int>(doneBytes),
      'partCount': serializer.toJson<int>(partCount),
      'completedParts': serializer.toJson<int>(completedParts),
      'error': serializer.toJson<String?>(error),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'finishedAt': serializer.toJson<DateTime?>(finishedAt),
      'origin': serializer.toJson<String>(
        $TransfersTable.$converterorigin.toJson(origin),
      ),
      'assetId': serializer.toJson<String?>(assetId),
      'takenAt': serializer.toJson<DateTime?>(takenAt),
      'thumbnailPath': serializer.toJson<String?>(thumbnailPath),
      'saveTo': serializer.toJson<String?>(
        $TransfersTable.$convertersaveTon.toJson(saveTo),
      ),
      'saveFolder': serializer.toJson<String?>(saveFolder),
      'wifiOnly': serializer.toJson<bool>(wifiOnly),
      'durationSeconds': serializer.toJson<int?>(durationSeconds),
      'replacesFileId': serializer.toJson<String?>(replacesFileId),
      'sourceChatId': serializer.toJson<int?>(sourceChatId),
      'sourceMessageId': serializer.toJson<int?>(sourceMessageId),
    };
  }

  TransferRow copyWith({
    String? id,
    TransferKind? kind,
    TransferStatus? status,
    String? name,
    String? mimeType,
    String? fileId,
    Value<String?> folderId = const Value.absent(),
    Value<String?> sourcePath = const Value.absent(),
    bool? ownsSource,
    Value<String?> resultPath = const Value.absent(),
    int? totalBytes,
    int? doneBytes,
    int? partCount,
    int? completedParts,
    Value<String?> error = const Value.absent(),
    DateTime? createdAt,
    Value<DateTime?> finishedAt = const Value.absent(),
    TransferOrigin? origin,
    Value<String?> assetId = const Value.absent(),
    Value<DateTime?> takenAt = const Value.absent(),
    Value<String?> thumbnailPath = const Value.absent(),
    Value<SaveTarget?> saveTo = const Value.absent(),
    Value<String?> saveFolder = const Value.absent(),
    bool? wifiOnly,
    Value<int?> durationSeconds = const Value.absent(),
    Value<String?> replacesFileId = const Value.absent(),
    Value<int?> sourceChatId = const Value.absent(),
    Value<int?> sourceMessageId = const Value.absent(),
  }) => TransferRow(
    id: id ?? this.id,
    kind: kind ?? this.kind,
    status: status ?? this.status,
    name: name ?? this.name,
    mimeType: mimeType ?? this.mimeType,
    fileId: fileId ?? this.fileId,
    folderId: folderId.present ? folderId.value : this.folderId,
    sourcePath: sourcePath.present ? sourcePath.value : this.sourcePath,
    ownsSource: ownsSource ?? this.ownsSource,
    resultPath: resultPath.present ? resultPath.value : this.resultPath,
    totalBytes: totalBytes ?? this.totalBytes,
    doneBytes: doneBytes ?? this.doneBytes,
    partCount: partCount ?? this.partCount,
    completedParts: completedParts ?? this.completedParts,
    error: error.present ? error.value : this.error,
    createdAt: createdAt ?? this.createdAt,
    finishedAt: finishedAt.present ? finishedAt.value : this.finishedAt,
    origin: origin ?? this.origin,
    assetId: assetId.present ? assetId.value : this.assetId,
    takenAt: takenAt.present ? takenAt.value : this.takenAt,
    thumbnailPath: thumbnailPath.present
        ? thumbnailPath.value
        : this.thumbnailPath,
    saveTo: saveTo.present ? saveTo.value : this.saveTo,
    saveFolder: saveFolder.present ? saveFolder.value : this.saveFolder,
    wifiOnly: wifiOnly ?? this.wifiOnly,
    durationSeconds: durationSeconds.present
        ? durationSeconds.value
        : this.durationSeconds,
    replacesFileId: replacesFileId.present
        ? replacesFileId.value
        : this.replacesFileId,
    sourceChatId: sourceChatId.present ? sourceChatId.value : this.sourceChatId,
    sourceMessageId: sourceMessageId.present
        ? sourceMessageId.value
        : this.sourceMessageId,
  );
  TransferRow copyWithCompanion(TransfersCompanion data) {
    return TransferRow(
      id: data.id.present ? data.id.value : this.id,
      kind: data.kind.present ? data.kind.value : this.kind,
      status: data.status.present ? data.status.value : this.status,
      name: data.name.present ? data.name.value : this.name,
      mimeType: data.mimeType.present ? data.mimeType.value : this.mimeType,
      fileId: data.fileId.present ? data.fileId.value : this.fileId,
      folderId: data.folderId.present ? data.folderId.value : this.folderId,
      sourcePath: data.sourcePath.present
          ? data.sourcePath.value
          : this.sourcePath,
      ownsSource: data.ownsSource.present
          ? data.ownsSource.value
          : this.ownsSource,
      resultPath: data.resultPath.present
          ? data.resultPath.value
          : this.resultPath,
      totalBytes: data.totalBytes.present
          ? data.totalBytes.value
          : this.totalBytes,
      doneBytes: data.doneBytes.present ? data.doneBytes.value : this.doneBytes,
      partCount: data.partCount.present ? data.partCount.value : this.partCount,
      completedParts: data.completedParts.present
          ? data.completedParts.value
          : this.completedParts,
      error: data.error.present ? data.error.value : this.error,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      finishedAt: data.finishedAt.present
          ? data.finishedAt.value
          : this.finishedAt,
      origin: data.origin.present ? data.origin.value : this.origin,
      assetId: data.assetId.present ? data.assetId.value : this.assetId,
      takenAt: data.takenAt.present ? data.takenAt.value : this.takenAt,
      thumbnailPath: data.thumbnailPath.present
          ? data.thumbnailPath.value
          : this.thumbnailPath,
      saveTo: data.saveTo.present ? data.saveTo.value : this.saveTo,
      saveFolder: data.saveFolder.present
          ? data.saveFolder.value
          : this.saveFolder,
      wifiOnly: data.wifiOnly.present ? data.wifiOnly.value : this.wifiOnly,
      durationSeconds: data.durationSeconds.present
          ? data.durationSeconds.value
          : this.durationSeconds,
      replacesFileId: data.replacesFileId.present
          ? data.replacesFileId.value
          : this.replacesFileId,
      sourceChatId: data.sourceChatId.present
          ? data.sourceChatId.value
          : this.sourceChatId,
      sourceMessageId: data.sourceMessageId.present
          ? data.sourceMessageId.value
          : this.sourceMessageId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TransferRow(')
          ..write('id: $id, ')
          ..write('kind: $kind, ')
          ..write('status: $status, ')
          ..write('name: $name, ')
          ..write('mimeType: $mimeType, ')
          ..write('fileId: $fileId, ')
          ..write('folderId: $folderId, ')
          ..write('sourcePath: $sourcePath, ')
          ..write('ownsSource: $ownsSource, ')
          ..write('resultPath: $resultPath, ')
          ..write('totalBytes: $totalBytes, ')
          ..write('doneBytes: $doneBytes, ')
          ..write('partCount: $partCount, ')
          ..write('completedParts: $completedParts, ')
          ..write('error: $error, ')
          ..write('createdAt: $createdAt, ')
          ..write('finishedAt: $finishedAt, ')
          ..write('origin: $origin, ')
          ..write('assetId: $assetId, ')
          ..write('takenAt: $takenAt, ')
          ..write('thumbnailPath: $thumbnailPath, ')
          ..write('saveTo: $saveTo, ')
          ..write('saveFolder: $saveFolder, ')
          ..write('wifiOnly: $wifiOnly, ')
          ..write('durationSeconds: $durationSeconds, ')
          ..write('replacesFileId: $replacesFileId, ')
          ..write('sourceChatId: $sourceChatId, ')
          ..write('sourceMessageId: $sourceMessageId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    kind,
    status,
    name,
    mimeType,
    fileId,
    folderId,
    sourcePath,
    ownsSource,
    resultPath,
    totalBytes,
    doneBytes,
    partCount,
    completedParts,
    error,
    createdAt,
    finishedAt,
    origin,
    assetId,
    takenAt,
    thumbnailPath,
    saveTo,
    saveFolder,
    wifiOnly,
    durationSeconds,
    replacesFileId,
    sourceChatId,
    sourceMessageId,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TransferRow &&
          other.id == this.id &&
          other.kind == this.kind &&
          other.status == this.status &&
          other.name == this.name &&
          other.mimeType == this.mimeType &&
          other.fileId == this.fileId &&
          other.folderId == this.folderId &&
          other.sourcePath == this.sourcePath &&
          other.ownsSource == this.ownsSource &&
          other.resultPath == this.resultPath &&
          other.totalBytes == this.totalBytes &&
          other.doneBytes == this.doneBytes &&
          other.partCount == this.partCount &&
          other.completedParts == this.completedParts &&
          other.error == this.error &&
          other.createdAt == this.createdAt &&
          other.finishedAt == this.finishedAt &&
          other.origin == this.origin &&
          other.assetId == this.assetId &&
          other.takenAt == this.takenAt &&
          other.thumbnailPath == this.thumbnailPath &&
          other.saveTo == this.saveTo &&
          other.saveFolder == this.saveFolder &&
          other.wifiOnly == this.wifiOnly &&
          other.durationSeconds == this.durationSeconds &&
          other.replacesFileId == this.replacesFileId &&
          other.sourceChatId == this.sourceChatId &&
          other.sourceMessageId == this.sourceMessageId);
}

class TransfersCompanion extends UpdateCompanion<TransferRow> {
  final Value<String> id;
  final Value<TransferKind> kind;
  final Value<TransferStatus> status;
  final Value<String> name;
  final Value<String> mimeType;
  final Value<String> fileId;
  final Value<String?> folderId;
  final Value<String?> sourcePath;
  final Value<bool> ownsSource;
  final Value<String?> resultPath;
  final Value<int> totalBytes;
  final Value<int> doneBytes;
  final Value<int> partCount;
  final Value<int> completedParts;
  final Value<String?> error;
  final Value<DateTime> createdAt;
  final Value<DateTime?> finishedAt;
  final Value<TransferOrigin> origin;
  final Value<String?> assetId;
  final Value<DateTime?> takenAt;
  final Value<String?> thumbnailPath;
  final Value<SaveTarget?> saveTo;
  final Value<String?> saveFolder;
  final Value<bool> wifiOnly;
  final Value<int?> durationSeconds;
  final Value<String?> replacesFileId;
  final Value<int?> sourceChatId;
  final Value<int?> sourceMessageId;
  final Value<int> rowid;
  const TransfersCompanion({
    this.id = const Value.absent(),
    this.kind = const Value.absent(),
    this.status = const Value.absent(),
    this.name = const Value.absent(),
    this.mimeType = const Value.absent(),
    this.fileId = const Value.absent(),
    this.folderId = const Value.absent(),
    this.sourcePath = const Value.absent(),
    this.ownsSource = const Value.absent(),
    this.resultPath = const Value.absent(),
    this.totalBytes = const Value.absent(),
    this.doneBytes = const Value.absent(),
    this.partCount = const Value.absent(),
    this.completedParts = const Value.absent(),
    this.error = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.finishedAt = const Value.absent(),
    this.origin = const Value.absent(),
    this.assetId = const Value.absent(),
    this.takenAt = const Value.absent(),
    this.thumbnailPath = const Value.absent(),
    this.saveTo = const Value.absent(),
    this.saveFolder = const Value.absent(),
    this.wifiOnly = const Value.absent(),
    this.durationSeconds = const Value.absent(),
    this.replacesFileId = const Value.absent(),
    this.sourceChatId = const Value.absent(),
    this.sourceMessageId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TransfersCompanion.insert({
    required String id,
    required TransferKind kind,
    required TransferStatus status,
    required String name,
    required String mimeType,
    required String fileId,
    this.folderId = const Value.absent(),
    this.sourcePath = const Value.absent(),
    this.ownsSource = const Value.absent(),
    this.resultPath = const Value.absent(),
    required int totalBytes,
    this.doneBytes = const Value.absent(),
    this.partCount = const Value.absent(),
    this.completedParts = const Value.absent(),
    this.error = const Value.absent(),
    required DateTime createdAt,
    this.finishedAt = const Value.absent(),
    this.origin = const Value.absent(),
    this.assetId = const Value.absent(),
    this.takenAt = const Value.absent(),
    this.thumbnailPath = const Value.absent(),
    this.saveTo = const Value.absent(),
    this.saveFolder = const Value.absent(),
    this.wifiOnly = const Value.absent(),
    this.durationSeconds = const Value.absent(),
    this.replacesFileId = const Value.absent(),
    this.sourceChatId = const Value.absent(),
    this.sourceMessageId = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       kind = Value(kind),
       status = Value(status),
       name = Value(name),
       mimeType = Value(mimeType),
       fileId = Value(fileId),
       totalBytes = Value(totalBytes),
       createdAt = Value(createdAt);
  static Insertable<TransferRow> custom({
    Expression<String>? id,
    Expression<String>? kind,
    Expression<String>? status,
    Expression<String>? name,
    Expression<String>? mimeType,
    Expression<String>? fileId,
    Expression<String>? folderId,
    Expression<String>? sourcePath,
    Expression<bool>? ownsSource,
    Expression<String>? resultPath,
    Expression<int>? totalBytes,
    Expression<int>? doneBytes,
    Expression<int>? partCount,
    Expression<int>? completedParts,
    Expression<String>? error,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? finishedAt,
    Expression<String>? origin,
    Expression<String>? assetId,
    Expression<DateTime>? takenAt,
    Expression<String>? thumbnailPath,
    Expression<String>? saveTo,
    Expression<String>? saveFolder,
    Expression<bool>? wifiOnly,
    Expression<int>? durationSeconds,
    Expression<String>? replacesFileId,
    Expression<int>? sourceChatId,
    Expression<int>? sourceMessageId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (kind != null) 'kind': kind,
      if (status != null) 'status': status,
      if (name != null) 'name': name,
      if (mimeType != null) 'mime_type': mimeType,
      if (fileId != null) 'file_id': fileId,
      if (folderId != null) 'folder_id': folderId,
      if (sourcePath != null) 'source_path': sourcePath,
      if (ownsSource != null) 'owns_source': ownsSource,
      if (resultPath != null) 'result_path': resultPath,
      if (totalBytes != null) 'total_bytes': totalBytes,
      if (doneBytes != null) 'done_bytes': doneBytes,
      if (partCount != null) 'part_count': partCount,
      if (completedParts != null) 'completed_parts': completedParts,
      if (error != null) 'error': error,
      if (createdAt != null) 'created_at': createdAt,
      if (finishedAt != null) 'finished_at': finishedAt,
      if (origin != null) 'origin': origin,
      if (assetId != null) 'asset_id': assetId,
      if (takenAt != null) 'taken_at': takenAt,
      if (thumbnailPath != null) 'thumbnail_path': thumbnailPath,
      if (saveTo != null) 'save_to': saveTo,
      if (saveFolder != null) 'save_folder': saveFolder,
      if (wifiOnly != null) 'wifi_only': wifiOnly,
      if (durationSeconds != null) 'duration_seconds': durationSeconds,
      if (replacesFileId != null) 'replaces_file_id': replacesFileId,
      if (sourceChatId != null) 'source_chat_id': sourceChatId,
      if (sourceMessageId != null) 'source_message_id': sourceMessageId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TransfersCompanion copyWith({
    Value<String>? id,
    Value<TransferKind>? kind,
    Value<TransferStatus>? status,
    Value<String>? name,
    Value<String>? mimeType,
    Value<String>? fileId,
    Value<String?>? folderId,
    Value<String?>? sourcePath,
    Value<bool>? ownsSource,
    Value<String?>? resultPath,
    Value<int>? totalBytes,
    Value<int>? doneBytes,
    Value<int>? partCount,
    Value<int>? completedParts,
    Value<String?>? error,
    Value<DateTime>? createdAt,
    Value<DateTime?>? finishedAt,
    Value<TransferOrigin>? origin,
    Value<String?>? assetId,
    Value<DateTime?>? takenAt,
    Value<String?>? thumbnailPath,
    Value<SaveTarget?>? saveTo,
    Value<String?>? saveFolder,
    Value<bool>? wifiOnly,
    Value<int?>? durationSeconds,
    Value<String?>? replacesFileId,
    Value<int?>? sourceChatId,
    Value<int?>? sourceMessageId,
    Value<int>? rowid,
  }) {
    return TransfersCompanion(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      status: status ?? this.status,
      name: name ?? this.name,
      mimeType: mimeType ?? this.mimeType,
      fileId: fileId ?? this.fileId,
      folderId: folderId ?? this.folderId,
      sourcePath: sourcePath ?? this.sourcePath,
      ownsSource: ownsSource ?? this.ownsSource,
      resultPath: resultPath ?? this.resultPath,
      totalBytes: totalBytes ?? this.totalBytes,
      doneBytes: doneBytes ?? this.doneBytes,
      partCount: partCount ?? this.partCount,
      completedParts: completedParts ?? this.completedParts,
      error: error ?? this.error,
      createdAt: createdAt ?? this.createdAt,
      finishedAt: finishedAt ?? this.finishedAt,
      origin: origin ?? this.origin,
      assetId: assetId ?? this.assetId,
      takenAt: takenAt ?? this.takenAt,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      saveTo: saveTo ?? this.saveTo,
      saveFolder: saveFolder ?? this.saveFolder,
      wifiOnly: wifiOnly ?? this.wifiOnly,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      replacesFileId: replacesFileId ?? this.replacesFileId,
      sourceChatId: sourceChatId ?? this.sourceChatId,
      sourceMessageId: sourceMessageId ?? this.sourceMessageId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(
        $TransfersTable.$converterkind.toSql(kind.value),
      );
    }
    if (status.present) {
      map['status'] = Variable<String>(
        $TransfersTable.$converterstatus.toSql(status.value),
      );
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (mimeType.present) {
      map['mime_type'] = Variable<String>(mimeType.value);
    }
    if (fileId.present) {
      map['file_id'] = Variable<String>(fileId.value);
    }
    if (folderId.present) {
      map['folder_id'] = Variable<String>(folderId.value);
    }
    if (sourcePath.present) {
      map['source_path'] = Variable<String>(sourcePath.value);
    }
    if (ownsSource.present) {
      map['owns_source'] = Variable<bool>(ownsSource.value);
    }
    if (resultPath.present) {
      map['result_path'] = Variable<String>(resultPath.value);
    }
    if (totalBytes.present) {
      map['total_bytes'] = Variable<int>(totalBytes.value);
    }
    if (doneBytes.present) {
      map['done_bytes'] = Variable<int>(doneBytes.value);
    }
    if (partCount.present) {
      map['part_count'] = Variable<int>(partCount.value);
    }
    if (completedParts.present) {
      map['completed_parts'] = Variable<int>(completedParts.value);
    }
    if (error.present) {
      map['error'] = Variable<String>(error.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (finishedAt.present) {
      map['finished_at'] = Variable<DateTime>(finishedAt.value);
    }
    if (origin.present) {
      map['origin'] = Variable<String>(
        $TransfersTable.$converterorigin.toSql(origin.value),
      );
    }
    if (assetId.present) {
      map['asset_id'] = Variable<String>(assetId.value);
    }
    if (takenAt.present) {
      map['taken_at'] = Variable<DateTime>(takenAt.value);
    }
    if (thumbnailPath.present) {
      map['thumbnail_path'] = Variable<String>(thumbnailPath.value);
    }
    if (saveTo.present) {
      map['save_to'] = Variable<String>(
        $TransfersTable.$convertersaveTon.toSql(saveTo.value),
      );
    }
    if (saveFolder.present) {
      map['save_folder'] = Variable<String>(saveFolder.value);
    }
    if (wifiOnly.present) {
      map['wifi_only'] = Variable<bool>(wifiOnly.value);
    }
    if (durationSeconds.present) {
      map['duration_seconds'] = Variable<int>(durationSeconds.value);
    }
    if (replacesFileId.present) {
      map['replaces_file_id'] = Variable<String>(replacesFileId.value);
    }
    if (sourceChatId.present) {
      map['source_chat_id'] = Variable<int>(sourceChatId.value);
    }
    if (sourceMessageId.present) {
      map['source_message_id'] = Variable<int>(sourceMessageId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TransfersCompanion(')
          ..write('id: $id, ')
          ..write('kind: $kind, ')
          ..write('status: $status, ')
          ..write('name: $name, ')
          ..write('mimeType: $mimeType, ')
          ..write('fileId: $fileId, ')
          ..write('folderId: $folderId, ')
          ..write('sourcePath: $sourcePath, ')
          ..write('ownsSource: $ownsSource, ')
          ..write('resultPath: $resultPath, ')
          ..write('totalBytes: $totalBytes, ')
          ..write('doneBytes: $doneBytes, ')
          ..write('partCount: $partCount, ')
          ..write('completedParts: $completedParts, ')
          ..write('error: $error, ')
          ..write('createdAt: $createdAt, ')
          ..write('finishedAt: $finishedAt, ')
          ..write('origin: $origin, ')
          ..write('assetId: $assetId, ')
          ..write('takenAt: $takenAt, ')
          ..write('thumbnailPath: $thumbnailPath, ')
          ..write('saveTo: $saveTo, ')
          ..write('saveFolder: $saveFolder, ')
          ..write('wifiOnly: $wifiOnly, ')
          ..write('durationSeconds: $durationSeconds, ')
          ..write('replacesFileId: $replacesFileId, ')
          ..write('sourceChatId: $sourceChatId, ')
          ..write('sourceMessageId: $sourceMessageId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $BackupAssetsTable extends BackupAssets
    with TableInfo<$BackupAssetsTable, BackupAssetRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BackupAssetsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _assetIdMeta = const VerificationMeta(
    'assetId',
  );
  @override
  late final GeneratedColumn<String> assetId = GeneratedColumn<String>(
    'asset_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<BackupAssetState, String> state =
      GeneratedColumn<String>(
        'state',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<BackupAssetState>($BackupAssetsTable.$converterstate);
  static const VerificationMeta _fileIdMeta = const VerificationMeta('fileId');
  @override
  late final GeneratedColumn<String> fileId = GeneratedColumn<String>(
    'file_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _failuresMeta = const VerificationMeta(
    'failures',
  );
  @override
  late final GeneratedColumn<int> failures = GeneratedColumn<int>(
    'failures',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _reasonMeta = const VerificationMeta('reason');
  @override
  late final GeneratedColumn<String> reason = GeneratedColumn<String>(
    'reason',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    assetId,
    state,
    fileId,
    failures,
    updatedAt,
    reason,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'backup_assets';
  @override
  VerificationContext validateIntegrity(
    Insertable<BackupAssetRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('asset_id')) {
      context.handle(
        _assetIdMeta,
        assetId.isAcceptableOrUnknown(data['asset_id']!, _assetIdMeta),
      );
    } else if (isInserting) {
      context.missing(_assetIdMeta);
    }
    if (data.containsKey('file_id')) {
      context.handle(
        _fileIdMeta,
        fileId.isAcceptableOrUnknown(data['file_id']!, _fileIdMeta),
      );
    }
    if (data.containsKey('failures')) {
      context.handle(
        _failuresMeta,
        failures.isAcceptableOrUnknown(data['failures']!, _failuresMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('reason')) {
      context.handle(
        _reasonMeta,
        reason.isAcceptableOrUnknown(data['reason']!, _reasonMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {assetId};
  @override
  BackupAssetRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return BackupAssetRow(
      assetId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}asset_id'],
      )!,
      state: $BackupAssetsTable.$converterstate.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}state'],
        )!,
      ),
      fileId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}file_id'],
      ),
      failures: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}failures'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      reason: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reason'],
      ),
    );
  }

  @override
  $BackupAssetsTable createAlias(String alias) {
    return $BackupAssetsTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<BackupAssetState, String, String> $converterstate =
      const EnumNameConverter<BackupAssetState>(BackupAssetState.values);
}

class BackupAssetRow extends DataClass implements Insertable<BackupAssetRow> {
  final String assetId;
  final BackupAssetState state;

  /// Drive file holding the asset, once backed up.
  final String? fileId;
  final int failures;
  final DateTime updatedAt;

  /// Why the last attempt failed, in the sentence the transfer would have
  /// shown, so the Backup screen can say it per photo.
  final String? reason;
  const BackupAssetRow({
    required this.assetId,
    required this.state,
    this.fileId,
    required this.failures,
    required this.updatedAt,
    this.reason,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['asset_id'] = Variable<String>(assetId);
    {
      map['state'] = Variable<String>(
        $BackupAssetsTable.$converterstate.toSql(state),
      );
    }
    if (!nullToAbsent || fileId != null) {
      map['file_id'] = Variable<String>(fileId);
    }
    map['failures'] = Variable<int>(failures);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || reason != null) {
      map['reason'] = Variable<String>(reason);
    }
    return map;
  }

  BackupAssetsCompanion toCompanion(bool nullToAbsent) {
    return BackupAssetsCompanion(
      assetId: Value(assetId),
      state: Value(state),
      fileId: fileId == null && nullToAbsent
          ? const Value.absent()
          : Value(fileId),
      failures: Value(failures),
      updatedAt: Value(updatedAt),
      reason: reason == null && nullToAbsent
          ? const Value.absent()
          : Value(reason),
    );
  }

  factory BackupAssetRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return BackupAssetRow(
      assetId: serializer.fromJson<String>(json['assetId']),
      state: $BackupAssetsTable.$converterstate.fromJson(
        serializer.fromJson<String>(json['state']),
      ),
      fileId: serializer.fromJson<String?>(json['fileId']),
      failures: serializer.fromJson<int>(json['failures']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      reason: serializer.fromJson<String?>(json['reason']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'assetId': serializer.toJson<String>(assetId),
      'state': serializer.toJson<String>(
        $BackupAssetsTable.$converterstate.toJson(state),
      ),
      'fileId': serializer.toJson<String?>(fileId),
      'failures': serializer.toJson<int>(failures),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'reason': serializer.toJson<String?>(reason),
    };
  }

  BackupAssetRow copyWith({
    String? assetId,
    BackupAssetState? state,
    Value<String?> fileId = const Value.absent(),
    int? failures,
    DateTime? updatedAt,
    Value<String?> reason = const Value.absent(),
  }) => BackupAssetRow(
    assetId: assetId ?? this.assetId,
    state: state ?? this.state,
    fileId: fileId.present ? fileId.value : this.fileId,
    failures: failures ?? this.failures,
    updatedAt: updatedAt ?? this.updatedAt,
    reason: reason.present ? reason.value : this.reason,
  );
  BackupAssetRow copyWithCompanion(BackupAssetsCompanion data) {
    return BackupAssetRow(
      assetId: data.assetId.present ? data.assetId.value : this.assetId,
      state: data.state.present ? data.state.value : this.state,
      fileId: data.fileId.present ? data.fileId.value : this.fileId,
      failures: data.failures.present ? data.failures.value : this.failures,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      reason: data.reason.present ? data.reason.value : this.reason,
    );
  }

  @override
  String toString() {
    return (StringBuffer('BackupAssetRow(')
          ..write('assetId: $assetId, ')
          ..write('state: $state, ')
          ..write('fileId: $fileId, ')
          ..write('failures: $failures, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('reason: $reason')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(assetId, state, fileId, failures, updatedAt, reason);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BackupAssetRow &&
          other.assetId == this.assetId &&
          other.state == this.state &&
          other.fileId == this.fileId &&
          other.failures == this.failures &&
          other.updatedAt == this.updatedAt &&
          other.reason == this.reason);
}

class BackupAssetsCompanion extends UpdateCompanion<BackupAssetRow> {
  final Value<String> assetId;
  final Value<BackupAssetState> state;
  final Value<String?> fileId;
  final Value<int> failures;
  final Value<DateTime> updatedAt;
  final Value<String?> reason;
  final Value<int> rowid;
  const BackupAssetsCompanion({
    this.assetId = const Value.absent(),
    this.state = const Value.absent(),
    this.fileId = const Value.absent(),
    this.failures = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.reason = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  BackupAssetsCompanion.insert({
    required String assetId,
    required BackupAssetState state,
    this.fileId = const Value.absent(),
    this.failures = const Value.absent(),
    required DateTime updatedAt,
    this.reason = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : assetId = Value(assetId),
       state = Value(state),
       updatedAt = Value(updatedAt);
  static Insertable<BackupAssetRow> custom({
    Expression<String>? assetId,
    Expression<String>? state,
    Expression<String>? fileId,
    Expression<int>? failures,
    Expression<DateTime>? updatedAt,
    Expression<String>? reason,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (assetId != null) 'asset_id': assetId,
      if (state != null) 'state': state,
      if (fileId != null) 'file_id': fileId,
      if (failures != null) 'failures': failures,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (reason != null) 'reason': reason,
      if (rowid != null) 'rowid': rowid,
    });
  }

  BackupAssetsCompanion copyWith({
    Value<String>? assetId,
    Value<BackupAssetState>? state,
    Value<String?>? fileId,
    Value<int>? failures,
    Value<DateTime>? updatedAt,
    Value<String?>? reason,
    Value<int>? rowid,
  }) {
    return BackupAssetsCompanion(
      assetId: assetId ?? this.assetId,
      state: state ?? this.state,
      fileId: fileId ?? this.fileId,
      failures: failures ?? this.failures,
      updatedAt: updatedAt ?? this.updatedAt,
      reason: reason ?? this.reason,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (assetId.present) {
      map['asset_id'] = Variable<String>(assetId.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(
        $BackupAssetsTable.$converterstate.toSql(state.value),
      );
    }
    if (fileId.present) {
      map['file_id'] = Variable<String>(fileId.value);
    }
    if (failures.present) {
      map['failures'] = Variable<int>(failures.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (reason.present) {
      map['reason'] = Variable<String>(reason.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BackupAssetsCompanion(')
          ..write('assetId: $assetId, ')
          ..write('state: $state, ')
          ..write('fileId: $fileId, ')
          ..write('failures: $failures, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('reason: $reason, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AlbumsTable extends Albums with TableInfo<$AlbumsTable, AlbumRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AlbumsTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _messageIdMeta = const VerificationMeta(
    'messageId',
  );
  @override
  late final GeneratedColumn<int> messageId = GeneratedColumn<int>(
    'message_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _modifiedAtMeta = const VerificationMeta(
    'modifiedAt',
  );
  @override
  late final GeneratedColumn<DateTime> modifiedAt = GeneratedColumn<DateTime>(
    'modified_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    messageId,
    createdAt,
    modifiedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'albums';
  @override
  VerificationContext validateIntegrity(
    Insertable<AlbumRow> instance, {
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
    if (data.containsKey('message_id')) {
      context.handle(
        _messageIdMeta,
        messageId.isAcceptableOrUnknown(data['message_id']!, _messageIdMeta),
      );
    } else if (isInserting) {
      context.missing(_messageIdMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('modified_at')) {
      context.handle(
        _modifiedAtMeta,
        modifiedAt.isAcceptableOrUnknown(data['modified_at']!, _modifiedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_modifiedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AlbumRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AlbumRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      messageId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}message_id'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      modifiedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}modified_at'],
      )!,
    );
  }

  @override
  $AlbumsTable createAlias(String alias) {
    return $AlbumsTable(attachedDatabase, alias);
  }
}

class AlbumRow extends DataClass implements Insertable<AlbumRow> {
  final String id;
  final String name;
  final int messageId;
  final DateTime createdAt;
  final DateTime modifiedAt;
  const AlbumRow({
    required this.id,
    required this.name,
    required this.messageId,
    required this.createdAt,
    required this.modifiedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['message_id'] = Variable<int>(messageId);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['modified_at'] = Variable<DateTime>(modifiedAt);
    return map;
  }

  AlbumsCompanion toCompanion(bool nullToAbsent) {
    return AlbumsCompanion(
      id: Value(id),
      name: Value(name),
      messageId: Value(messageId),
      createdAt: Value(createdAt),
      modifiedAt: Value(modifiedAt),
    );
  }

  factory AlbumRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AlbumRow(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      messageId: serializer.fromJson<int>(json['messageId']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      modifiedAt: serializer.fromJson<DateTime>(json['modifiedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'messageId': serializer.toJson<int>(messageId),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'modifiedAt': serializer.toJson<DateTime>(modifiedAt),
    };
  }

  AlbumRow copyWith({
    String? id,
    String? name,
    int? messageId,
    DateTime? createdAt,
    DateTime? modifiedAt,
  }) => AlbumRow(
    id: id ?? this.id,
    name: name ?? this.name,
    messageId: messageId ?? this.messageId,
    createdAt: createdAt ?? this.createdAt,
    modifiedAt: modifiedAt ?? this.modifiedAt,
  );
  AlbumRow copyWithCompanion(AlbumsCompanion data) {
    return AlbumRow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      messageId: data.messageId.present ? data.messageId.value : this.messageId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      modifiedAt: data.modifiedAt.present
          ? data.modifiedAt.value
          : this.modifiedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AlbumRow(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('messageId: $messageId, ')
          ..write('createdAt: $createdAt, ')
          ..write('modifiedAt: $modifiedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, messageId, createdAt, modifiedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AlbumRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.messageId == this.messageId &&
          other.createdAt == this.createdAt &&
          other.modifiedAt == this.modifiedAt);
}

class AlbumsCompanion extends UpdateCompanion<AlbumRow> {
  final Value<String> id;
  final Value<String> name;
  final Value<int> messageId;
  final Value<DateTime> createdAt;
  final Value<DateTime> modifiedAt;
  final Value<int> rowid;
  const AlbumsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.messageId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.modifiedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AlbumsCompanion.insert({
    required String id,
    required String name,
    required int messageId,
    required DateTime createdAt,
    required DateTime modifiedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       messageId = Value(messageId),
       createdAt = Value(createdAt),
       modifiedAt = Value(modifiedAt);
  static Insertable<AlbumRow> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<int>? messageId,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? modifiedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (messageId != null) 'message_id': messageId,
      if (createdAt != null) 'created_at': createdAt,
      if (modifiedAt != null) 'modified_at': modifiedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AlbumsCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<int>? messageId,
    Value<DateTime>? createdAt,
    Value<DateTime>? modifiedAt,
    Value<int>? rowid,
  }) {
    return AlbumsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      messageId: messageId ?? this.messageId,
      createdAt: createdAt ?? this.createdAt,
      modifiedAt: modifiedAt ?? this.modifiedAt,
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
    if (messageId.present) {
      map['message_id'] = Variable<int>(messageId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (modifiedAt.present) {
      map['modified_at'] = Variable<DateTime>(modifiedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AlbumsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('messageId: $messageId, ')
          ..write('createdAt: $createdAt, ')
          ..write('modifiedAt: $modifiedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AlbumFilesTable extends AlbumFiles
    with TableInfo<$AlbumFilesTable, AlbumFileRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AlbumFilesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _albumIdMeta = const VerificationMeta(
    'albumId',
  );
  @override
  late final GeneratedColumn<String> albumId = GeneratedColumn<String>(
    'album_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fileIdMeta = const VerificationMeta('fileId');
  @override
  late final GeneratedColumn<String> fileId = GeneratedColumn<String>(
    'file_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [albumId, fileId];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'album_files';
  @override
  VerificationContext validateIntegrity(
    Insertable<AlbumFileRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('album_id')) {
      context.handle(
        _albumIdMeta,
        albumId.isAcceptableOrUnknown(data['album_id']!, _albumIdMeta),
      );
    } else if (isInserting) {
      context.missing(_albumIdMeta);
    }
    if (data.containsKey('file_id')) {
      context.handle(
        _fileIdMeta,
        fileId.isAcceptableOrUnknown(data['file_id']!, _fileIdMeta),
      );
    } else if (isInserting) {
      context.missing(_fileIdMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {albumId, fileId};
  @override
  AlbumFileRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AlbumFileRow(
      albumId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}album_id'],
      )!,
      fileId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}file_id'],
      )!,
    );
  }

  @override
  $AlbumFilesTable createAlias(String alias) {
    return $AlbumFilesTable(attachedDatabase, alias);
  }
}

class AlbumFileRow extends DataClass implements Insertable<AlbumFileRow> {
  final String albumId;
  final String fileId;
  const AlbumFileRow({required this.albumId, required this.fileId});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['album_id'] = Variable<String>(albumId);
    map['file_id'] = Variable<String>(fileId);
    return map;
  }

  AlbumFilesCompanion toCompanion(bool nullToAbsent) {
    return AlbumFilesCompanion(albumId: Value(albumId), fileId: Value(fileId));
  }

  factory AlbumFileRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AlbumFileRow(
      albumId: serializer.fromJson<String>(json['albumId']),
      fileId: serializer.fromJson<String>(json['fileId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'albumId': serializer.toJson<String>(albumId),
      'fileId': serializer.toJson<String>(fileId),
    };
  }

  AlbumFileRow copyWith({String? albumId, String? fileId}) => AlbumFileRow(
    albumId: albumId ?? this.albumId,
    fileId: fileId ?? this.fileId,
  );
  AlbumFileRow copyWithCompanion(AlbumFilesCompanion data) {
    return AlbumFileRow(
      albumId: data.albumId.present ? data.albumId.value : this.albumId,
      fileId: data.fileId.present ? data.fileId.value : this.fileId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AlbumFileRow(')
          ..write('albumId: $albumId, ')
          ..write('fileId: $fileId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(albumId, fileId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AlbumFileRow &&
          other.albumId == this.albumId &&
          other.fileId == this.fileId);
}

class AlbumFilesCompanion extends UpdateCompanion<AlbumFileRow> {
  final Value<String> albumId;
  final Value<String> fileId;
  final Value<int> rowid;
  const AlbumFilesCompanion({
    this.albumId = const Value.absent(),
    this.fileId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AlbumFilesCompanion.insert({
    required String albumId,
    required String fileId,
    this.rowid = const Value.absent(),
  }) : albumId = Value(albumId),
       fileId = Value(fileId);
  static Insertable<AlbumFileRow> custom({
    Expression<String>? albumId,
    Expression<String>? fileId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (albumId != null) 'album_id': albumId,
      if (fileId != null) 'file_id': fileId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AlbumFilesCompanion copyWith({
    Value<String>? albumId,
    Value<String>? fileId,
    Value<int>? rowid,
  }) {
    return AlbumFilesCompanion(
      albumId: albumId ?? this.albumId,
      fileId: fileId ?? this.fileId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (albumId.present) {
      map['album_id'] = Variable<String>(albumId.value);
    }
    if (fileId.present) {
      map['file_id'] = Variable<String>(fileId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AlbumFilesCompanion(')
          ..write('albumId: $albumId, ')
          ..write('fileId: $fileId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $OfflinePinsTable extends OfflinePins
    with TableInfo<$OfflinePinsTable, OfflinePinRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OfflinePinsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _itemIdMeta = const VerificationMeta('itemId');
  @override
  late final GeneratedColumn<String> itemId = GeneratedColumn<String>(
    'item_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isFolderMeta = const VerificationMeta(
    'isFolder',
  );
  @override
  late final GeneratedColumn<bool> isFolder = GeneratedColumn<bool>(
    'is_folder',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_folder" IN (0, 1))',
    ),
  );
  static const VerificationMeta _pinnedAtMeta = const VerificationMeta(
    'pinnedAt',
  );
  @override
  late final GeneratedColumn<DateTime> pinnedAt = GeneratedColumn<DateTime>(
    'pinned_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [itemId, isFolder, pinnedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'offline_pins';
  @override
  VerificationContext validateIntegrity(
    Insertable<OfflinePinRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('item_id')) {
      context.handle(
        _itemIdMeta,
        itemId.isAcceptableOrUnknown(data['item_id']!, _itemIdMeta),
      );
    } else if (isInserting) {
      context.missing(_itemIdMeta);
    }
    if (data.containsKey('is_folder')) {
      context.handle(
        _isFolderMeta,
        isFolder.isAcceptableOrUnknown(data['is_folder']!, _isFolderMeta),
      );
    } else if (isInserting) {
      context.missing(_isFolderMeta);
    }
    if (data.containsKey('pinned_at')) {
      context.handle(
        _pinnedAtMeta,
        pinnedAt.isAcceptableOrUnknown(data['pinned_at']!, _pinnedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_pinnedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {itemId};
  @override
  OfflinePinRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OfflinePinRow(
      itemId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}item_id'],
      )!,
      isFolder: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_folder'],
      )!,
      pinnedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}pinned_at'],
      )!,
    );
  }

  @override
  $OfflinePinsTable createAlias(String alias) {
    return $OfflinePinsTable(attachedDatabase, alias);
  }
}

class OfflinePinRow extends DataClass implements Insertable<OfflinePinRow> {
  final String itemId;
  final bool isFolder;
  final DateTime pinnedAt;
  const OfflinePinRow({
    required this.itemId,
    required this.isFolder,
    required this.pinnedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['item_id'] = Variable<String>(itemId);
    map['is_folder'] = Variable<bool>(isFolder);
    map['pinned_at'] = Variable<DateTime>(pinnedAt);
    return map;
  }

  OfflinePinsCompanion toCompanion(bool nullToAbsent) {
    return OfflinePinsCompanion(
      itemId: Value(itemId),
      isFolder: Value(isFolder),
      pinnedAt: Value(pinnedAt),
    );
  }

  factory OfflinePinRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OfflinePinRow(
      itemId: serializer.fromJson<String>(json['itemId']),
      isFolder: serializer.fromJson<bool>(json['isFolder']),
      pinnedAt: serializer.fromJson<DateTime>(json['pinnedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'itemId': serializer.toJson<String>(itemId),
      'isFolder': serializer.toJson<bool>(isFolder),
      'pinnedAt': serializer.toJson<DateTime>(pinnedAt),
    };
  }

  OfflinePinRow copyWith({
    String? itemId,
    bool? isFolder,
    DateTime? pinnedAt,
  }) => OfflinePinRow(
    itemId: itemId ?? this.itemId,
    isFolder: isFolder ?? this.isFolder,
    pinnedAt: pinnedAt ?? this.pinnedAt,
  );
  OfflinePinRow copyWithCompanion(OfflinePinsCompanion data) {
    return OfflinePinRow(
      itemId: data.itemId.present ? data.itemId.value : this.itemId,
      isFolder: data.isFolder.present ? data.isFolder.value : this.isFolder,
      pinnedAt: data.pinnedAt.present ? data.pinnedAt.value : this.pinnedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OfflinePinRow(')
          ..write('itemId: $itemId, ')
          ..write('isFolder: $isFolder, ')
          ..write('pinnedAt: $pinnedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(itemId, isFolder, pinnedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OfflinePinRow &&
          other.itemId == this.itemId &&
          other.isFolder == this.isFolder &&
          other.pinnedAt == this.pinnedAt);
}

class OfflinePinsCompanion extends UpdateCompanion<OfflinePinRow> {
  final Value<String> itemId;
  final Value<bool> isFolder;
  final Value<DateTime> pinnedAt;
  final Value<int> rowid;
  const OfflinePinsCompanion({
    this.itemId = const Value.absent(),
    this.isFolder = const Value.absent(),
    this.pinnedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  OfflinePinsCompanion.insert({
    required String itemId,
    required bool isFolder,
    required DateTime pinnedAt,
    this.rowid = const Value.absent(),
  }) : itemId = Value(itemId),
       isFolder = Value(isFolder),
       pinnedAt = Value(pinnedAt);
  static Insertable<OfflinePinRow> custom({
    Expression<String>? itemId,
    Expression<bool>? isFolder,
    Expression<DateTime>? pinnedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (itemId != null) 'item_id': itemId,
      if (isFolder != null) 'is_folder': isFolder,
      if (pinnedAt != null) 'pinned_at': pinnedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  OfflinePinsCompanion copyWith({
    Value<String>? itemId,
    Value<bool>? isFolder,
    Value<DateTime>? pinnedAt,
    Value<int>? rowid,
  }) {
    return OfflinePinsCompanion(
      itemId: itemId ?? this.itemId,
      isFolder: isFolder ?? this.isFolder,
      pinnedAt: pinnedAt ?? this.pinnedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (itemId.present) {
      map['item_id'] = Variable<String>(itemId.value);
    }
    if (isFolder.present) {
      map['is_folder'] = Variable<bool>(isFolder.value);
    }
    if (pinnedAt.present) {
      map['pinned_at'] = Variable<DateTime>(pinnedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OfflinePinsCompanion(')
          ..write('itemId: $itemId, ')
          ..write('isFolder: $isFolder, ')
          ..write('pinnedAt: $pinnedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $OfflineCopiesTable extends OfflineCopies
    with TableInfo<$OfflineCopiesTable, OfflineCopyRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OfflineCopiesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _fileIdMeta = const VerificationMeta('fileId');
  @override
  late final GeneratedColumn<String> fileId = GeneratedColumn<String>(
    'file_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pathMeta = const VerificationMeta('path');
  @override
  late final GeneratedColumn<String> path = GeneratedColumn<String>(
    'path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sizeMeta = const VerificationMeta('size');
  @override
  late final GeneratedColumn<int> size = GeneratedColumn<int>(
    'size',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [fileId, path, size];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'offline_copies';
  @override
  VerificationContext validateIntegrity(
    Insertable<OfflineCopyRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('file_id')) {
      context.handle(
        _fileIdMeta,
        fileId.isAcceptableOrUnknown(data['file_id']!, _fileIdMeta),
      );
    } else if (isInserting) {
      context.missing(_fileIdMeta);
    }
    if (data.containsKey('path')) {
      context.handle(
        _pathMeta,
        path.isAcceptableOrUnknown(data['path']!, _pathMeta),
      );
    } else if (isInserting) {
      context.missing(_pathMeta);
    }
    if (data.containsKey('size')) {
      context.handle(
        _sizeMeta,
        size.isAcceptableOrUnknown(data['size']!, _sizeMeta),
      );
    } else if (isInserting) {
      context.missing(_sizeMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {fileId};
  @override
  OfflineCopyRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OfflineCopyRow(
      fileId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}file_id'],
      )!,
      path: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}path'],
      )!,
      size: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}size'],
      )!,
    );
  }

  @override
  $OfflineCopiesTable createAlias(String alias) {
    return $OfflineCopiesTable(attachedDatabase, alias);
  }
}

class OfflineCopyRow extends DataClass implements Insertable<OfflineCopyRow> {
  final String fileId;
  final String path;
  final int size;
  const OfflineCopyRow({
    required this.fileId,
    required this.path,
    required this.size,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['file_id'] = Variable<String>(fileId);
    map['path'] = Variable<String>(path);
    map['size'] = Variable<int>(size);
    return map;
  }

  OfflineCopiesCompanion toCompanion(bool nullToAbsent) {
    return OfflineCopiesCompanion(
      fileId: Value(fileId),
      path: Value(path),
      size: Value(size),
    );
  }

  factory OfflineCopyRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OfflineCopyRow(
      fileId: serializer.fromJson<String>(json['fileId']),
      path: serializer.fromJson<String>(json['path']),
      size: serializer.fromJson<int>(json['size']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'fileId': serializer.toJson<String>(fileId),
      'path': serializer.toJson<String>(path),
      'size': serializer.toJson<int>(size),
    };
  }

  OfflineCopyRow copyWith({String? fileId, String? path, int? size}) =>
      OfflineCopyRow(
        fileId: fileId ?? this.fileId,
        path: path ?? this.path,
        size: size ?? this.size,
      );
  OfflineCopyRow copyWithCompanion(OfflineCopiesCompanion data) {
    return OfflineCopyRow(
      fileId: data.fileId.present ? data.fileId.value : this.fileId,
      path: data.path.present ? data.path.value : this.path,
      size: data.size.present ? data.size.value : this.size,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OfflineCopyRow(')
          ..write('fileId: $fileId, ')
          ..write('path: $path, ')
          ..write('size: $size')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(fileId, path, size);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OfflineCopyRow &&
          other.fileId == this.fileId &&
          other.path == this.path &&
          other.size == this.size);
}

class OfflineCopiesCompanion extends UpdateCompanion<OfflineCopyRow> {
  final Value<String> fileId;
  final Value<String> path;
  final Value<int> size;
  final Value<int> rowid;
  const OfflineCopiesCompanion({
    this.fileId = const Value.absent(),
    this.path = const Value.absent(),
    this.size = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  OfflineCopiesCompanion.insert({
    required String fileId,
    required String path,
    required int size,
    this.rowid = const Value.absent(),
  }) : fileId = Value(fileId),
       path = Value(path),
       size = Value(size);
  static Insertable<OfflineCopyRow> custom({
    Expression<String>? fileId,
    Expression<String>? path,
    Expression<int>? size,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (fileId != null) 'file_id': fileId,
      if (path != null) 'path': path,
      if (size != null) 'size': size,
      if (rowid != null) 'rowid': rowid,
    });
  }

  OfflineCopiesCompanion copyWith({
    Value<String>? fileId,
    Value<String>? path,
    Value<int>? size,
    Value<int>? rowid,
  }) {
    return OfflineCopiesCompanion(
      fileId: fileId ?? this.fileId,
      path: path ?? this.path,
      size: size ?? this.size,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (fileId.present) {
      map['file_id'] = Variable<String>(fileId.value);
    }
    if (path.present) {
      map['path'] = Variable<String>(path.value);
    }
    if (size.present) {
      map['size'] = Variable<int>(size.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OfflineCopiesCompanion(')
          ..write('fileId: $fileId, ')
          ..write('path: $path, ')
          ..write('size: $size, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $FileContentsTable extends FileContents
    with TableInfo<$FileContentsTable, FileContentRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FileContentsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _fileIdMeta = const VerificationMeta('fileId');
  @override
  late final GeneratedColumn<String> fileId = GeneratedColumn<String>(
    'file_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _contentMeta = const VerificationMeta(
    'content',
  );
  @override
  late final GeneratedColumn<String> content = GeneratedColumn<String>(
    'content',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _versionMeta = const VerificationMeta(
    'version',
  );
  @override
  late final GeneratedColumn<int> version = GeneratedColumn<int>(
    'version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _indexedAtMeta = const VerificationMeta(
    'indexedAt',
  );
  @override
  late final GeneratedColumn<DateTime> indexedAt = GeneratedColumn<DateTime>(
    'indexed_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [fileId, content, version, indexedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'file_contents';
  @override
  VerificationContext validateIntegrity(
    Insertable<FileContentRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('file_id')) {
      context.handle(
        _fileIdMeta,
        fileId.isAcceptableOrUnknown(data['file_id']!, _fileIdMeta),
      );
    } else if (isInserting) {
      context.missing(_fileIdMeta);
    }
    if (data.containsKey('content')) {
      context.handle(
        _contentMeta,
        content.isAcceptableOrUnknown(data['content']!, _contentMeta),
      );
    } else if (isInserting) {
      context.missing(_contentMeta);
    }
    if (data.containsKey('version')) {
      context.handle(
        _versionMeta,
        version.isAcceptableOrUnknown(data['version']!, _versionMeta),
      );
    } else if (isInserting) {
      context.missing(_versionMeta);
    }
    if (data.containsKey('indexed_at')) {
      context.handle(
        _indexedAtMeta,
        indexedAt.isAcceptableOrUnknown(data['indexed_at']!, _indexedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_indexedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {fileId};
  @override
  FileContentRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FileContentRow(
      fileId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}file_id'],
      )!,
      content: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content'],
      )!,
      version: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}version'],
      )!,
      indexedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}indexed_at'],
      )!,
    );
  }

  @override
  $FileContentsTable createAlias(String alias) {
    return $FileContentsTable(attachedDatabase, alias);
  }
}

class FileContentRow extends DataClass implements Insertable<FileContentRow> {
  final String fileId;
  final String content;

  /// Indexer version that produced it; older entries are redone.
  final int version;
  final DateTime indexedAt;
  const FileContentRow({
    required this.fileId,
    required this.content,
    required this.version,
    required this.indexedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['file_id'] = Variable<String>(fileId);
    map['content'] = Variable<String>(content);
    map['version'] = Variable<int>(version);
    map['indexed_at'] = Variable<DateTime>(indexedAt);
    return map;
  }

  FileContentsCompanion toCompanion(bool nullToAbsent) {
    return FileContentsCompanion(
      fileId: Value(fileId),
      content: Value(content),
      version: Value(version),
      indexedAt: Value(indexedAt),
    );
  }

  factory FileContentRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FileContentRow(
      fileId: serializer.fromJson<String>(json['fileId']),
      content: serializer.fromJson<String>(json['content']),
      version: serializer.fromJson<int>(json['version']),
      indexedAt: serializer.fromJson<DateTime>(json['indexedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'fileId': serializer.toJson<String>(fileId),
      'content': serializer.toJson<String>(content),
      'version': serializer.toJson<int>(version),
      'indexedAt': serializer.toJson<DateTime>(indexedAt),
    };
  }

  FileContentRow copyWith({
    String? fileId,
    String? content,
    int? version,
    DateTime? indexedAt,
  }) => FileContentRow(
    fileId: fileId ?? this.fileId,
    content: content ?? this.content,
    version: version ?? this.version,
    indexedAt: indexedAt ?? this.indexedAt,
  );
  FileContentRow copyWithCompanion(FileContentsCompanion data) {
    return FileContentRow(
      fileId: data.fileId.present ? data.fileId.value : this.fileId,
      content: data.content.present ? data.content.value : this.content,
      version: data.version.present ? data.version.value : this.version,
      indexedAt: data.indexedAt.present ? data.indexedAt.value : this.indexedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FileContentRow(')
          ..write('fileId: $fileId, ')
          ..write('content: $content, ')
          ..write('version: $version, ')
          ..write('indexedAt: $indexedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(fileId, content, version, indexedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FileContentRow &&
          other.fileId == this.fileId &&
          other.content == this.content &&
          other.version == this.version &&
          other.indexedAt == this.indexedAt);
}

class FileContentsCompanion extends UpdateCompanion<FileContentRow> {
  final Value<String> fileId;
  final Value<String> content;
  final Value<int> version;
  final Value<DateTime> indexedAt;
  final Value<int> rowid;
  const FileContentsCompanion({
    this.fileId = const Value.absent(),
    this.content = const Value.absent(),
    this.version = const Value.absent(),
    this.indexedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FileContentsCompanion.insert({
    required String fileId,
    required String content,
    required int version,
    required DateTime indexedAt,
    this.rowid = const Value.absent(),
  }) : fileId = Value(fileId),
       content = Value(content),
       version = Value(version),
       indexedAt = Value(indexedAt);
  static Insertable<FileContentRow> custom({
    Expression<String>? fileId,
    Expression<String>? content,
    Expression<int>? version,
    Expression<DateTime>? indexedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (fileId != null) 'file_id': fileId,
      if (content != null) 'content': content,
      if (version != null) 'version': version,
      if (indexedAt != null) 'indexed_at': indexedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FileContentsCompanion copyWith({
    Value<String>? fileId,
    Value<String>? content,
    Value<int>? version,
    Value<DateTime>? indexedAt,
    Value<int>? rowid,
  }) {
    return FileContentsCompanion(
      fileId: fileId ?? this.fileId,
      content: content ?? this.content,
      version: version ?? this.version,
      indexedAt: indexedAt ?? this.indexedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (fileId.present) {
      map['file_id'] = Variable<String>(fileId.value);
    }
    if (content.present) {
      map['content'] = Variable<String>(content.value);
    }
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    if (indexedAt.present) {
      map['indexed_at'] = Variable<DateTime>(indexedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FileContentsCompanion(')
          ..write('fileId: $fileId, ')
          ..write('content: $content, ')
          ..write('version: $version, ')
          ..write('indexedAt: $indexedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $FileOpensTable extends FileOpens
    with TableInfo<$FileOpensTable, FileOpenRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FileOpensTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _fileIdMeta = const VerificationMeta('fileId');
  @override
  late final GeneratedColumn<String> fileId = GeneratedColumn<String>(
    'file_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _openedAtMeta = const VerificationMeta(
    'openedAt',
  );
  @override
  late final GeneratedColumn<DateTime> openedAt = GeneratedColumn<DateTime>(
    'opened_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [fileId, openedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'file_opens';
  @override
  VerificationContext validateIntegrity(
    Insertable<FileOpenRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('file_id')) {
      context.handle(
        _fileIdMeta,
        fileId.isAcceptableOrUnknown(data['file_id']!, _fileIdMeta),
      );
    } else if (isInserting) {
      context.missing(_fileIdMeta);
    }
    if (data.containsKey('opened_at')) {
      context.handle(
        _openedAtMeta,
        openedAt.isAcceptableOrUnknown(data['opened_at']!, _openedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_openedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {fileId};
  @override
  FileOpenRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FileOpenRow(
      fileId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}file_id'],
      )!,
      openedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}opened_at'],
      )!,
    );
  }

  @override
  $FileOpensTable createAlias(String alias) {
    return $FileOpensTable(attachedDatabase, alias);
  }
}

class FileOpenRow extends DataClass implements Insertable<FileOpenRow> {
  final String fileId;
  final DateTime openedAt;
  const FileOpenRow({required this.fileId, required this.openedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['file_id'] = Variable<String>(fileId);
    map['opened_at'] = Variable<DateTime>(openedAt);
    return map;
  }

  FileOpensCompanion toCompanion(bool nullToAbsent) {
    return FileOpensCompanion(fileId: Value(fileId), openedAt: Value(openedAt));
  }

  factory FileOpenRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FileOpenRow(
      fileId: serializer.fromJson<String>(json['fileId']),
      openedAt: serializer.fromJson<DateTime>(json['openedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'fileId': serializer.toJson<String>(fileId),
      'openedAt': serializer.toJson<DateTime>(openedAt),
    };
  }

  FileOpenRow copyWith({String? fileId, DateTime? openedAt}) => FileOpenRow(
    fileId: fileId ?? this.fileId,
    openedAt: openedAt ?? this.openedAt,
  );
  FileOpenRow copyWithCompanion(FileOpensCompanion data) {
    return FileOpenRow(
      fileId: data.fileId.present ? data.fileId.value : this.fileId,
      openedAt: data.openedAt.present ? data.openedAt.value : this.openedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FileOpenRow(')
          ..write('fileId: $fileId, ')
          ..write('openedAt: $openedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(fileId, openedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FileOpenRow &&
          other.fileId == this.fileId &&
          other.openedAt == this.openedAt);
}

class FileOpensCompanion extends UpdateCompanion<FileOpenRow> {
  final Value<String> fileId;
  final Value<DateTime> openedAt;
  final Value<int> rowid;
  const FileOpensCompanion({
    this.fileId = const Value.absent(),
    this.openedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FileOpensCompanion.insert({
    required String fileId,
    required DateTime openedAt,
    this.rowid = const Value.absent(),
  }) : fileId = Value(fileId),
       openedAt = Value(openedAt);
  static Insertable<FileOpenRow> custom({
    Expression<String>? fileId,
    Expression<DateTime>? openedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (fileId != null) 'file_id': fileId,
      if (openedAt != null) 'opened_at': openedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FileOpensCompanion copyWith({
    Value<String>? fileId,
    Value<DateTime>? openedAt,
    Value<int>? rowid,
  }) {
    return FileOpensCompanion(
      fileId: fileId ?? this.fileId,
      openedAt: openedAt ?? this.openedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (fileId.present) {
      map['file_id'] = Variable<String>(fileId.value);
    }
    if (openedAt.present) {
      map['opened_at'] = Variable<DateTime>(openedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FileOpensCompanion(')
          ..write('fileId: $fileId, ')
          ..write('openedAt: $openedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PlayPositionsTable extends PlayPositions
    with TableInfo<$PlayPositionsTable, PlayPositionRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PlayPositionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _fileIdMeta = const VerificationMeta('fileId');
  @override
  late final GeneratedColumn<String> fileId = GeneratedColumn<String>(
    'file_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _positionMsMeta = const VerificationMeta(
    'positionMs',
  );
  @override
  late final GeneratedColumn<int> positionMs = GeneratedColumn<int>(
    'position_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _durationMsMeta = const VerificationMeta(
    'durationMs',
  );
  @override
  late final GeneratedColumn<int> durationMs = GeneratedColumn<int>(
    'duration_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    fileId,
    positionMs,
    durationMs,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'play_positions';
  @override
  VerificationContext validateIntegrity(
    Insertable<PlayPositionRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('file_id')) {
      context.handle(
        _fileIdMeta,
        fileId.isAcceptableOrUnknown(data['file_id']!, _fileIdMeta),
      );
    } else if (isInserting) {
      context.missing(_fileIdMeta);
    }
    if (data.containsKey('position_ms')) {
      context.handle(
        _positionMsMeta,
        positionMs.isAcceptableOrUnknown(data['position_ms']!, _positionMsMeta),
      );
    } else if (isInserting) {
      context.missing(_positionMsMeta);
    }
    if (data.containsKey('duration_ms')) {
      context.handle(
        _durationMsMeta,
        durationMs.isAcceptableOrUnknown(data['duration_ms']!, _durationMsMeta),
      );
    } else if (isInserting) {
      context.missing(_durationMsMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {fileId};
  @override
  PlayPositionRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PlayPositionRow(
      fileId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}file_id'],
      )!,
      positionMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position_ms'],
      )!,
      durationMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_ms'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $PlayPositionsTable createAlias(String alias) {
    return $PlayPositionsTable(attachedDatabase, alias);
  }
}

class PlayPositionRow extends DataClass implements Insertable<PlayPositionRow> {
  final String fileId;
  final int positionMs;
  final int durationMs;
  final DateTime updatedAt;
  const PlayPositionRow({
    required this.fileId,
    required this.positionMs,
    required this.durationMs,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['file_id'] = Variable<String>(fileId);
    map['position_ms'] = Variable<int>(positionMs);
    map['duration_ms'] = Variable<int>(durationMs);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  PlayPositionsCompanion toCompanion(bool nullToAbsent) {
    return PlayPositionsCompanion(
      fileId: Value(fileId),
      positionMs: Value(positionMs),
      durationMs: Value(durationMs),
      updatedAt: Value(updatedAt),
    );
  }

  factory PlayPositionRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PlayPositionRow(
      fileId: serializer.fromJson<String>(json['fileId']),
      positionMs: serializer.fromJson<int>(json['positionMs']),
      durationMs: serializer.fromJson<int>(json['durationMs']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'fileId': serializer.toJson<String>(fileId),
      'positionMs': serializer.toJson<int>(positionMs),
      'durationMs': serializer.toJson<int>(durationMs),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  PlayPositionRow copyWith({
    String? fileId,
    int? positionMs,
    int? durationMs,
    DateTime? updatedAt,
  }) => PlayPositionRow(
    fileId: fileId ?? this.fileId,
    positionMs: positionMs ?? this.positionMs,
    durationMs: durationMs ?? this.durationMs,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  PlayPositionRow copyWithCompanion(PlayPositionsCompanion data) {
    return PlayPositionRow(
      fileId: data.fileId.present ? data.fileId.value : this.fileId,
      positionMs: data.positionMs.present
          ? data.positionMs.value
          : this.positionMs,
      durationMs: data.durationMs.present
          ? data.durationMs.value
          : this.durationMs,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PlayPositionRow(')
          ..write('fileId: $fileId, ')
          ..write('positionMs: $positionMs, ')
          ..write('durationMs: $durationMs, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(fileId, positionMs, durationMs, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PlayPositionRow &&
          other.fileId == this.fileId &&
          other.positionMs == this.positionMs &&
          other.durationMs == this.durationMs &&
          other.updatedAt == this.updatedAt);
}

class PlayPositionsCompanion extends UpdateCompanion<PlayPositionRow> {
  final Value<String> fileId;
  final Value<int> positionMs;
  final Value<int> durationMs;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const PlayPositionsCompanion({
    this.fileId = const Value.absent(),
    this.positionMs = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PlayPositionsCompanion.insert({
    required String fileId,
    required int positionMs,
    required int durationMs,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : fileId = Value(fileId),
       positionMs = Value(positionMs),
       durationMs = Value(durationMs),
       updatedAt = Value(updatedAt);
  static Insertable<PlayPositionRow> custom({
    Expression<String>? fileId,
    Expression<int>? positionMs,
    Expression<int>? durationMs,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (fileId != null) 'file_id': fileId,
      if (positionMs != null) 'position_ms': positionMs,
      if (durationMs != null) 'duration_ms': durationMs,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PlayPositionsCompanion copyWith({
    Value<String>? fileId,
    Value<int>? positionMs,
    Value<int>? durationMs,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return PlayPositionsCompanion(
      fileId: fileId ?? this.fileId,
      positionMs: positionMs ?? this.positionMs,
      durationMs: durationMs ?? this.durationMs,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (fileId.present) {
      map['file_id'] = Variable<String>(fileId.value);
    }
    if (positionMs.present) {
      map['position_ms'] = Variable<int>(positionMs.value);
    }
    if (durationMs.present) {
      map['duration_ms'] = Variable<int>(durationMs.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PlayPositionsCompanion(')
          ..write('fileId: $fileId, ')
          ..write('positionMs: $positionMs, ')
          ..write('durationMs: $durationMs, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $WatchedFoldersTable extends WatchedFolders
    with TableInfo<$WatchedFoldersTable, WatchedFolderRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $WatchedFoldersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _treeUriMeta = const VerificationMeta(
    'treeUri',
  );
  @override
  late final GeneratedColumn<String> treeUri = GeneratedColumn<String>(
    'tree_uri',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _labelMeta = const VerificationMeta('label');
  @override
  late final GeneratedColumn<String> label = GeneratedColumn<String>(
    'label',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _destinationIdMeta = const VerificationMeta(
    'destinationId',
  );
  @override
  late final GeneratedColumn<String> destinationId = GeneratedColumn<String>(
    'destination_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<WatchFilter, String> filter =
      GeneratedColumn<String>(
        'filter',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<WatchFilter>($WatchedFoldersTable.$converterfilter);
  static const VerificationMeta _subfoldersMeta = const VerificationMeta(
    'subfolders',
  );
  @override
  late final GeneratedColumn<bool> subfolders = GeneratedColumn<bool>(
    'subfolders',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("subfolders" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _checkedAtMeta = const VerificationMeta(
    'checkedAt',
  );
  @override
  late final GeneratedColumn<DateTime> checkedAt = GeneratedColumn<DateTime>(
    'checked_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    treeUri,
    label,
    destinationId,
    filter,
    subfolders,
    createdAt,
    checkedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'watched_folders';
  @override
  VerificationContext validateIntegrity(
    Insertable<WatchedFolderRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('tree_uri')) {
      context.handle(
        _treeUriMeta,
        treeUri.isAcceptableOrUnknown(data['tree_uri']!, _treeUriMeta),
      );
    } else if (isInserting) {
      context.missing(_treeUriMeta);
    }
    if (data.containsKey('label')) {
      context.handle(
        _labelMeta,
        label.isAcceptableOrUnknown(data['label']!, _labelMeta),
      );
    } else if (isInserting) {
      context.missing(_labelMeta);
    }
    if (data.containsKey('destination_id')) {
      context.handle(
        _destinationIdMeta,
        destinationId.isAcceptableOrUnknown(
          data['destination_id']!,
          _destinationIdMeta,
        ),
      );
    }
    if (data.containsKey('subfolders')) {
      context.handle(
        _subfoldersMeta,
        subfolders.isAcceptableOrUnknown(data['subfolders']!, _subfoldersMeta),
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
    if (data.containsKey('checked_at')) {
      context.handle(
        _checkedAtMeta,
        checkedAt.isAcceptableOrUnknown(data['checked_at']!, _checkedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  WatchedFolderRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return WatchedFolderRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      treeUri: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tree_uri'],
      )!,
      label: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}label'],
      )!,
      destinationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}destination_id'],
      ),
      filter: $WatchedFoldersTable.$converterfilter.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}filter'],
        )!,
      ),
      subfolders: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}subfolders'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      checkedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}checked_at'],
      ),
    );
  }

  @override
  $WatchedFoldersTable createAlias(String alias) {
    return $WatchedFoldersTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<WatchFilter, String, String> $converterfilter =
      const EnumNameConverter<WatchFilter>(WatchFilter.values);
}

class WatchedFolderRow extends DataClass
    implements Insertable<WatchedFolderRow> {
  final String id;

  /// The tree URI Android handed over, with persisted read access, which
  /// is how the folder is listed again and how the grant is given back.
  final String treeUri;

  /// The folder's display name, for its row and its default drive folder.
  final String label;

  /// Drive folder the uploads land in. Null until the first upload creates
  /// Auto upload › [label], so an empty folder never makes a drive folder.
  final String? destinationId;
  final WatchFilter filter;
  final bool subfolders;
  final DateTime createdAt;

  /// When the folder was last looked through; null before the first check.
  final DateTime? checkedAt;
  const WatchedFolderRow({
    required this.id,
    required this.treeUri,
    required this.label,
    this.destinationId,
    required this.filter,
    required this.subfolders,
    required this.createdAt,
    this.checkedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['tree_uri'] = Variable<String>(treeUri);
    map['label'] = Variable<String>(label);
    if (!nullToAbsent || destinationId != null) {
      map['destination_id'] = Variable<String>(destinationId);
    }
    {
      map['filter'] = Variable<String>(
        $WatchedFoldersTable.$converterfilter.toSql(filter),
      );
    }
    map['subfolders'] = Variable<bool>(subfolders);
    map['created_at'] = Variable<DateTime>(createdAt);
    if (!nullToAbsent || checkedAt != null) {
      map['checked_at'] = Variable<DateTime>(checkedAt);
    }
    return map;
  }

  WatchedFoldersCompanion toCompanion(bool nullToAbsent) {
    return WatchedFoldersCompanion(
      id: Value(id),
      treeUri: Value(treeUri),
      label: Value(label),
      destinationId: destinationId == null && nullToAbsent
          ? const Value.absent()
          : Value(destinationId),
      filter: Value(filter),
      subfolders: Value(subfolders),
      createdAt: Value(createdAt),
      checkedAt: checkedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(checkedAt),
    );
  }

  factory WatchedFolderRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return WatchedFolderRow(
      id: serializer.fromJson<String>(json['id']),
      treeUri: serializer.fromJson<String>(json['treeUri']),
      label: serializer.fromJson<String>(json['label']),
      destinationId: serializer.fromJson<String?>(json['destinationId']),
      filter: $WatchedFoldersTable.$converterfilter.fromJson(
        serializer.fromJson<String>(json['filter']),
      ),
      subfolders: serializer.fromJson<bool>(json['subfolders']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      checkedAt: serializer.fromJson<DateTime?>(json['checkedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'treeUri': serializer.toJson<String>(treeUri),
      'label': serializer.toJson<String>(label),
      'destinationId': serializer.toJson<String?>(destinationId),
      'filter': serializer.toJson<String>(
        $WatchedFoldersTable.$converterfilter.toJson(filter),
      ),
      'subfolders': serializer.toJson<bool>(subfolders),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'checkedAt': serializer.toJson<DateTime?>(checkedAt),
    };
  }

  WatchedFolderRow copyWith({
    String? id,
    String? treeUri,
    String? label,
    Value<String?> destinationId = const Value.absent(),
    WatchFilter? filter,
    bool? subfolders,
    DateTime? createdAt,
    Value<DateTime?> checkedAt = const Value.absent(),
  }) => WatchedFolderRow(
    id: id ?? this.id,
    treeUri: treeUri ?? this.treeUri,
    label: label ?? this.label,
    destinationId: destinationId.present
        ? destinationId.value
        : this.destinationId,
    filter: filter ?? this.filter,
    subfolders: subfolders ?? this.subfolders,
    createdAt: createdAt ?? this.createdAt,
    checkedAt: checkedAt.present ? checkedAt.value : this.checkedAt,
  );
  WatchedFolderRow copyWithCompanion(WatchedFoldersCompanion data) {
    return WatchedFolderRow(
      id: data.id.present ? data.id.value : this.id,
      treeUri: data.treeUri.present ? data.treeUri.value : this.treeUri,
      label: data.label.present ? data.label.value : this.label,
      destinationId: data.destinationId.present
          ? data.destinationId.value
          : this.destinationId,
      filter: data.filter.present ? data.filter.value : this.filter,
      subfolders: data.subfolders.present
          ? data.subfolders.value
          : this.subfolders,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      checkedAt: data.checkedAt.present ? data.checkedAt.value : this.checkedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('WatchedFolderRow(')
          ..write('id: $id, ')
          ..write('treeUri: $treeUri, ')
          ..write('label: $label, ')
          ..write('destinationId: $destinationId, ')
          ..write('filter: $filter, ')
          ..write('subfolders: $subfolders, ')
          ..write('createdAt: $createdAt, ')
          ..write('checkedAt: $checkedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    treeUri,
    label,
    destinationId,
    filter,
    subfolders,
    createdAt,
    checkedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WatchedFolderRow &&
          other.id == this.id &&
          other.treeUri == this.treeUri &&
          other.label == this.label &&
          other.destinationId == this.destinationId &&
          other.filter == this.filter &&
          other.subfolders == this.subfolders &&
          other.createdAt == this.createdAt &&
          other.checkedAt == this.checkedAt);
}

class WatchedFoldersCompanion extends UpdateCompanion<WatchedFolderRow> {
  final Value<String> id;
  final Value<String> treeUri;
  final Value<String> label;
  final Value<String?> destinationId;
  final Value<WatchFilter> filter;
  final Value<bool> subfolders;
  final Value<DateTime> createdAt;
  final Value<DateTime?> checkedAt;
  final Value<int> rowid;
  const WatchedFoldersCompanion({
    this.id = const Value.absent(),
    this.treeUri = const Value.absent(),
    this.label = const Value.absent(),
    this.destinationId = const Value.absent(),
    this.filter = const Value.absent(),
    this.subfolders = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.checkedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  WatchedFoldersCompanion.insert({
    required String id,
    required String treeUri,
    required String label,
    this.destinationId = const Value.absent(),
    required WatchFilter filter,
    this.subfolders = const Value.absent(),
    required DateTime createdAt,
    this.checkedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       treeUri = Value(treeUri),
       label = Value(label),
       filter = Value(filter),
       createdAt = Value(createdAt);
  static Insertable<WatchedFolderRow> custom({
    Expression<String>? id,
    Expression<String>? treeUri,
    Expression<String>? label,
    Expression<String>? destinationId,
    Expression<String>? filter,
    Expression<bool>? subfolders,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? checkedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (treeUri != null) 'tree_uri': treeUri,
      if (label != null) 'label': label,
      if (destinationId != null) 'destination_id': destinationId,
      if (filter != null) 'filter': filter,
      if (subfolders != null) 'subfolders': subfolders,
      if (createdAt != null) 'created_at': createdAt,
      if (checkedAt != null) 'checked_at': checkedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  WatchedFoldersCompanion copyWith({
    Value<String>? id,
    Value<String>? treeUri,
    Value<String>? label,
    Value<String?>? destinationId,
    Value<WatchFilter>? filter,
    Value<bool>? subfolders,
    Value<DateTime>? createdAt,
    Value<DateTime?>? checkedAt,
    Value<int>? rowid,
  }) {
    return WatchedFoldersCompanion(
      id: id ?? this.id,
      treeUri: treeUri ?? this.treeUri,
      label: label ?? this.label,
      destinationId: destinationId ?? this.destinationId,
      filter: filter ?? this.filter,
      subfolders: subfolders ?? this.subfolders,
      createdAt: createdAt ?? this.createdAt,
      checkedAt: checkedAt ?? this.checkedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (treeUri.present) {
      map['tree_uri'] = Variable<String>(treeUri.value);
    }
    if (label.present) {
      map['label'] = Variable<String>(label.value);
    }
    if (destinationId.present) {
      map['destination_id'] = Variable<String>(destinationId.value);
    }
    if (filter.present) {
      map['filter'] = Variable<String>(
        $WatchedFoldersTable.$converterfilter.toSql(filter.value),
      );
    }
    if (subfolders.present) {
      map['subfolders'] = Variable<bool>(subfolders.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (checkedAt.present) {
      map['checked_at'] = Variable<DateTime>(checkedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('WatchedFoldersCompanion(')
          ..write('id: $id, ')
          ..write('treeUri: $treeUri, ')
          ..write('label: $label, ')
          ..write('destinationId: $destinationId, ')
          ..write('filter: $filter, ')
          ..write('subfolders: $subfolders, ')
          ..write('createdAt: $createdAt, ')
          ..write('checkedAt: $checkedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $WatchedFilesTable extends WatchedFiles
    with TableInfo<$WatchedFilesTable, WatchedFileRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $WatchedFilesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _ruleIdMeta = const VerificationMeta('ruleId');
  @override
  late final GeneratedColumn<String> ruleId = GeneratedColumn<String>(
    'rule_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _documentIdMeta = const VerificationMeta(
    'documentId',
  );
  @override
  late final GeneratedColumn<String> documentId = GeneratedColumn<String>(
    'document_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sizeMeta = const VerificationMeta('size');
  @override
  late final GeneratedColumn<int> size = GeneratedColumn<int>(
    'size',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _modifiedAtMeta = const VerificationMeta(
    'modifiedAt',
  );
  @override
  late final GeneratedColumn<DateTime> modifiedAt = GeneratedColumn<DateTime>(
    'modified_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<WatchedFileState, String> state =
      GeneratedColumn<String>(
        'state',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<WatchedFileState>($WatchedFilesTable.$converterstate);
  static const VerificationMeta _fileIdMeta = const VerificationMeta('fileId');
  @override
  late final GeneratedColumn<String> fileId = GeneratedColumn<String>(
    'file_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _transferIdMeta = const VerificationMeta(
    'transferId',
  );
  @override
  late final GeneratedColumn<String> transferId = GeneratedColumn<String>(
    'transfer_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _failuresMeta = const VerificationMeta(
    'failures',
  );
  @override
  late final GeneratedColumn<int> failures = GeneratedColumn<int>(
    'failures',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    ruleId,
    documentId,
    size,
    modifiedAt,
    state,
    fileId,
    transferId,
    failures,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'watched_files';
  @override
  VerificationContext validateIntegrity(
    Insertable<WatchedFileRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('rule_id')) {
      context.handle(
        _ruleIdMeta,
        ruleId.isAcceptableOrUnknown(data['rule_id']!, _ruleIdMeta),
      );
    } else if (isInserting) {
      context.missing(_ruleIdMeta);
    }
    if (data.containsKey('document_id')) {
      context.handle(
        _documentIdMeta,
        documentId.isAcceptableOrUnknown(data['document_id']!, _documentIdMeta),
      );
    } else if (isInserting) {
      context.missing(_documentIdMeta);
    }
    if (data.containsKey('size')) {
      context.handle(
        _sizeMeta,
        size.isAcceptableOrUnknown(data['size']!, _sizeMeta),
      );
    } else if (isInserting) {
      context.missing(_sizeMeta);
    }
    if (data.containsKey('modified_at')) {
      context.handle(
        _modifiedAtMeta,
        modifiedAt.isAcceptableOrUnknown(data['modified_at']!, _modifiedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_modifiedAtMeta);
    }
    if (data.containsKey('file_id')) {
      context.handle(
        _fileIdMeta,
        fileId.isAcceptableOrUnknown(data['file_id']!, _fileIdMeta),
      );
    }
    if (data.containsKey('transfer_id')) {
      context.handle(
        _transferIdMeta,
        transferId.isAcceptableOrUnknown(data['transfer_id']!, _transferIdMeta),
      );
    }
    if (data.containsKey('failures')) {
      context.handle(
        _failuresMeta,
        failures.isAcceptableOrUnknown(data['failures']!, _failuresMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {ruleId, documentId};
  @override
  WatchedFileRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return WatchedFileRow(
      ruleId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}rule_id'],
      )!,
      documentId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}document_id'],
      )!,
      size: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}size'],
      )!,
      modifiedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}modified_at'],
      )!,
      state: $WatchedFilesTable.$converterstate.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}state'],
        )!,
      ),
      fileId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}file_id'],
      ),
      transferId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}transfer_id'],
      ),
      failures: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}failures'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $WatchedFilesTable createAlias(String alias) {
    return $WatchedFilesTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<WatchedFileState, String, String> $converterstate =
      const EnumNameConverter<WatchedFileState>(WatchedFileState.values);
}

class WatchedFileRow extends DataClass implements Insertable<WatchedFileRow> {
  final String ruleId;
  final String documentId;
  final int size;
  final DateTime modifiedAt;
  final WatchedFileState state;

  /// Drive file holding the document, once uploaded or found already there.
  final String? fileId;

  /// The queued upload, so a restart can tell a transfer still running from
  /// one that is gone.
  final String? transferId;
  final int failures;
  final DateTime updatedAt;
  const WatchedFileRow({
    required this.ruleId,
    required this.documentId,
    required this.size,
    required this.modifiedAt,
    required this.state,
    this.fileId,
    this.transferId,
    required this.failures,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['rule_id'] = Variable<String>(ruleId);
    map['document_id'] = Variable<String>(documentId);
    map['size'] = Variable<int>(size);
    map['modified_at'] = Variable<DateTime>(modifiedAt);
    {
      map['state'] = Variable<String>(
        $WatchedFilesTable.$converterstate.toSql(state),
      );
    }
    if (!nullToAbsent || fileId != null) {
      map['file_id'] = Variable<String>(fileId);
    }
    if (!nullToAbsent || transferId != null) {
      map['transfer_id'] = Variable<String>(transferId);
    }
    map['failures'] = Variable<int>(failures);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  WatchedFilesCompanion toCompanion(bool nullToAbsent) {
    return WatchedFilesCompanion(
      ruleId: Value(ruleId),
      documentId: Value(documentId),
      size: Value(size),
      modifiedAt: Value(modifiedAt),
      state: Value(state),
      fileId: fileId == null && nullToAbsent
          ? const Value.absent()
          : Value(fileId),
      transferId: transferId == null && nullToAbsent
          ? const Value.absent()
          : Value(transferId),
      failures: Value(failures),
      updatedAt: Value(updatedAt),
    );
  }

  factory WatchedFileRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return WatchedFileRow(
      ruleId: serializer.fromJson<String>(json['ruleId']),
      documentId: serializer.fromJson<String>(json['documentId']),
      size: serializer.fromJson<int>(json['size']),
      modifiedAt: serializer.fromJson<DateTime>(json['modifiedAt']),
      state: $WatchedFilesTable.$converterstate.fromJson(
        serializer.fromJson<String>(json['state']),
      ),
      fileId: serializer.fromJson<String?>(json['fileId']),
      transferId: serializer.fromJson<String?>(json['transferId']),
      failures: serializer.fromJson<int>(json['failures']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'ruleId': serializer.toJson<String>(ruleId),
      'documentId': serializer.toJson<String>(documentId),
      'size': serializer.toJson<int>(size),
      'modifiedAt': serializer.toJson<DateTime>(modifiedAt),
      'state': serializer.toJson<String>(
        $WatchedFilesTable.$converterstate.toJson(state),
      ),
      'fileId': serializer.toJson<String?>(fileId),
      'transferId': serializer.toJson<String?>(transferId),
      'failures': serializer.toJson<int>(failures),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  WatchedFileRow copyWith({
    String? ruleId,
    String? documentId,
    int? size,
    DateTime? modifiedAt,
    WatchedFileState? state,
    Value<String?> fileId = const Value.absent(),
    Value<String?> transferId = const Value.absent(),
    int? failures,
    DateTime? updatedAt,
  }) => WatchedFileRow(
    ruleId: ruleId ?? this.ruleId,
    documentId: documentId ?? this.documentId,
    size: size ?? this.size,
    modifiedAt: modifiedAt ?? this.modifiedAt,
    state: state ?? this.state,
    fileId: fileId.present ? fileId.value : this.fileId,
    transferId: transferId.present ? transferId.value : this.transferId,
    failures: failures ?? this.failures,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  WatchedFileRow copyWithCompanion(WatchedFilesCompanion data) {
    return WatchedFileRow(
      ruleId: data.ruleId.present ? data.ruleId.value : this.ruleId,
      documentId: data.documentId.present
          ? data.documentId.value
          : this.documentId,
      size: data.size.present ? data.size.value : this.size,
      modifiedAt: data.modifiedAt.present
          ? data.modifiedAt.value
          : this.modifiedAt,
      state: data.state.present ? data.state.value : this.state,
      fileId: data.fileId.present ? data.fileId.value : this.fileId,
      transferId: data.transferId.present
          ? data.transferId.value
          : this.transferId,
      failures: data.failures.present ? data.failures.value : this.failures,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('WatchedFileRow(')
          ..write('ruleId: $ruleId, ')
          ..write('documentId: $documentId, ')
          ..write('size: $size, ')
          ..write('modifiedAt: $modifiedAt, ')
          ..write('state: $state, ')
          ..write('fileId: $fileId, ')
          ..write('transferId: $transferId, ')
          ..write('failures: $failures, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    ruleId,
    documentId,
    size,
    modifiedAt,
    state,
    fileId,
    transferId,
    failures,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WatchedFileRow &&
          other.ruleId == this.ruleId &&
          other.documentId == this.documentId &&
          other.size == this.size &&
          other.modifiedAt == this.modifiedAt &&
          other.state == this.state &&
          other.fileId == this.fileId &&
          other.transferId == this.transferId &&
          other.failures == this.failures &&
          other.updatedAt == this.updatedAt);
}

class WatchedFilesCompanion extends UpdateCompanion<WatchedFileRow> {
  final Value<String> ruleId;
  final Value<String> documentId;
  final Value<int> size;
  final Value<DateTime> modifiedAt;
  final Value<WatchedFileState> state;
  final Value<String?> fileId;
  final Value<String?> transferId;
  final Value<int> failures;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const WatchedFilesCompanion({
    this.ruleId = const Value.absent(),
    this.documentId = const Value.absent(),
    this.size = const Value.absent(),
    this.modifiedAt = const Value.absent(),
    this.state = const Value.absent(),
    this.fileId = const Value.absent(),
    this.transferId = const Value.absent(),
    this.failures = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  WatchedFilesCompanion.insert({
    required String ruleId,
    required String documentId,
    required int size,
    required DateTime modifiedAt,
    required WatchedFileState state,
    this.fileId = const Value.absent(),
    this.transferId = const Value.absent(),
    this.failures = const Value.absent(),
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : ruleId = Value(ruleId),
       documentId = Value(documentId),
       size = Value(size),
       modifiedAt = Value(modifiedAt),
       state = Value(state),
       updatedAt = Value(updatedAt);
  static Insertable<WatchedFileRow> custom({
    Expression<String>? ruleId,
    Expression<String>? documentId,
    Expression<int>? size,
    Expression<DateTime>? modifiedAt,
    Expression<String>? state,
    Expression<String>? fileId,
    Expression<String>? transferId,
    Expression<int>? failures,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (ruleId != null) 'rule_id': ruleId,
      if (documentId != null) 'document_id': documentId,
      if (size != null) 'size': size,
      if (modifiedAt != null) 'modified_at': modifiedAt,
      if (state != null) 'state': state,
      if (fileId != null) 'file_id': fileId,
      if (transferId != null) 'transfer_id': transferId,
      if (failures != null) 'failures': failures,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  WatchedFilesCompanion copyWith({
    Value<String>? ruleId,
    Value<String>? documentId,
    Value<int>? size,
    Value<DateTime>? modifiedAt,
    Value<WatchedFileState>? state,
    Value<String?>? fileId,
    Value<String?>? transferId,
    Value<int>? failures,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return WatchedFilesCompanion(
      ruleId: ruleId ?? this.ruleId,
      documentId: documentId ?? this.documentId,
      size: size ?? this.size,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      state: state ?? this.state,
      fileId: fileId ?? this.fileId,
      transferId: transferId ?? this.transferId,
      failures: failures ?? this.failures,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (ruleId.present) {
      map['rule_id'] = Variable<String>(ruleId.value);
    }
    if (documentId.present) {
      map['document_id'] = Variable<String>(documentId.value);
    }
    if (size.present) {
      map['size'] = Variable<int>(size.value);
    }
    if (modifiedAt.present) {
      map['modified_at'] = Variable<DateTime>(modifiedAt.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(
        $WatchedFilesTable.$converterstate.toSql(state.value),
      );
    }
    if (fileId.present) {
      map['file_id'] = Variable<String>(fileId.value);
    }
    if (transferId.present) {
      map['transfer_id'] = Variable<String>(transferId.value);
    }
    if (failures.present) {
      map['failures'] = Variable<int>(failures.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('WatchedFilesCompanion(')
          ..write('ruleId: $ruleId, ')
          ..write('documentId: $documentId, ')
          ..write('size: $size, ')
          ..write('modifiedAt: $modifiedAt, ')
          ..write('state: $state, ')
          ..write('fileId: $fileId, ')
          ..write('transferId: $transferId, ')
          ..write('failures: $failures, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PendingEditsTable extends PendingEdits
    with TableInfo<$PendingEditsTable, PendingEditRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PendingEditsTable(this.attachedDatabase, [this._alias]);
  @override
  late final GeneratedColumnWithTypeConverter<EditTarget, String> target =
      GeneratedColumn<String>(
        'target',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<EditTarget>($PendingEditsTable.$convertertarget);
  static const VerificationMeta _itemIdMeta = const VerificationMeta('itemId');
  @override
  late final GeneratedColumn<String> itemId = GeneratedColumn<String>(
    'item_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _patchMeta = const VerificationMeta('patch');
  @override
  late final GeneratedColumn<String> patch = GeneratedColumn<String>(
    'patch',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
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
  @override
  List<GeneratedColumn> get $columns => [
    target,
    itemId,
    patch,
    createdAt,
    updatedAt,
    attempts,
    lastError,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'pending_edits';
  @override
  VerificationContext validateIntegrity(
    Insertable<PendingEditRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('item_id')) {
      context.handle(
        _itemIdMeta,
        itemId.isAcceptableOrUnknown(data['item_id']!, _itemIdMeta),
      );
    } else if (isInserting) {
      context.missing(_itemIdMeta);
    }
    if (data.containsKey('patch')) {
      context.handle(
        _patchMeta,
        patch.isAcceptableOrUnknown(data['patch']!, _patchMeta),
      );
    } else if (isInserting) {
      context.missing(_patchMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
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
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {target, itemId};
  @override
  PendingEditRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PendingEditRow(
      target: $PendingEditsTable.$convertertarget.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}target'],
        )!,
      ),
      itemId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}item_id'],
      )!,
      patch: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}patch'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      attempts: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempts'],
      )!,
      lastError: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error'],
      ),
    );
  }

  @override
  $PendingEditsTable createAlias(String alias) {
    return $PendingEditsTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<EditTarget, String, String> $convertertarget =
      const EnumNameConverter<EditTarget>(EditTarget.values);
}

class PendingEditRow extends DataClass implements Insertable<PendingEditRow> {
  final EditTarget target;
  final String itemId;

  /// JSON keyed by the manifest's short keys, each holding the value before
  /// the change and the value wanted.
  final String patch;
  final DateTime createdAt;

  /// When the patch last changed, so a replay that finishes while a newer
  /// edit comes in keeps the newer part instead of dropping the row.
  final DateTime updatedAt;

  /// Replays that failed for a reason other than the network; after a few,
  /// the row waits for the person to try again.
  final int attempts;

  /// Why the last replay failed, in the sentence the screen shows.
  final String? lastError;
  const PendingEditRow({
    required this.target,
    required this.itemId,
    required this.patch,
    required this.createdAt,
    required this.updatedAt,
    required this.attempts,
    this.lastError,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    {
      map['target'] = Variable<String>(
        $PendingEditsTable.$convertertarget.toSql(target),
      );
    }
    map['item_id'] = Variable<String>(itemId);
    map['patch'] = Variable<String>(patch);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['attempts'] = Variable<int>(attempts);
    if (!nullToAbsent || lastError != null) {
      map['last_error'] = Variable<String>(lastError);
    }
    return map;
  }

  PendingEditsCompanion toCompanion(bool nullToAbsent) {
    return PendingEditsCompanion(
      target: Value(target),
      itemId: Value(itemId),
      patch: Value(patch),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      attempts: Value(attempts),
      lastError: lastError == null && nullToAbsent
          ? const Value.absent()
          : Value(lastError),
    );
  }

  factory PendingEditRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PendingEditRow(
      target: $PendingEditsTable.$convertertarget.fromJson(
        serializer.fromJson<String>(json['target']),
      ),
      itemId: serializer.fromJson<String>(json['itemId']),
      patch: serializer.fromJson<String>(json['patch']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      attempts: serializer.fromJson<int>(json['attempts']),
      lastError: serializer.fromJson<String?>(json['lastError']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'target': serializer.toJson<String>(
        $PendingEditsTable.$convertertarget.toJson(target),
      ),
      'itemId': serializer.toJson<String>(itemId),
      'patch': serializer.toJson<String>(patch),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'attempts': serializer.toJson<int>(attempts),
      'lastError': serializer.toJson<String?>(lastError),
    };
  }

  PendingEditRow copyWith({
    EditTarget? target,
    String? itemId,
    String? patch,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? attempts,
    Value<String?> lastError = const Value.absent(),
  }) => PendingEditRow(
    target: target ?? this.target,
    itemId: itemId ?? this.itemId,
    patch: patch ?? this.patch,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    attempts: attempts ?? this.attempts,
    lastError: lastError.present ? lastError.value : this.lastError,
  );
  PendingEditRow copyWithCompanion(PendingEditsCompanion data) {
    return PendingEditRow(
      target: data.target.present ? data.target.value : this.target,
      itemId: data.itemId.present ? data.itemId.value : this.itemId,
      patch: data.patch.present ? data.patch.value : this.patch,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      attempts: data.attempts.present ? data.attempts.value : this.attempts,
      lastError: data.lastError.present ? data.lastError.value : this.lastError,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PendingEditRow(')
          ..write('target: $target, ')
          ..write('itemId: $itemId, ')
          ..write('patch: $patch, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('attempts: $attempts, ')
          ..write('lastError: $lastError')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    target,
    itemId,
    patch,
    createdAt,
    updatedAt,
    attempts,
    lastError,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PendingEditRow &&
          other.target == this.target &&
          other.itemId == this.itemId &&
          other.patch == this.patch &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.attempts == this.attempts &&
          other.lastError == this.lastError);
}

class PendingEditsCompanion extends UpdateCompanion<PendingEditRow> {
  final Value<EditTarget> target;
  final Value<String> itemId;
  final Value<String> patch;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> attempts;
  final Value<String?> lastError;
  final Value<int> rowid;
  const PendingEditsCompanion({
    this.target = const Value.absent(),
    this.itemId = const Value.absent(),
    this.patch = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.attempts = const Value.absent(),
    this.lastError = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PendingEditsCompanion.insert({
    required EditTarget target,
    required String itemId,
    required String patch,
    required DateTime createdAt,
    required DateTime updatedAt,
    this.attempts = const Value.absent(),
    this.lastError = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : target = Value(target),
       itemId = Value(itemId),
       patch = Value(patch),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<PendingEditRow> custom({
    Expression<String>? target,
    Expression<String>? itemId,
    Expression<String>? patch,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? attempts,
    Expression<String>? lastError,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (target != null) 'target': target,
      if (itemId != null) 'item_id': itemId,
      if (patch != null) 'patch': patch,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (attempts != null) 'attempts': attempts,
      if (lastError != null) 'last_error': lastError,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PendingEditsCompanion copyWith({
    Value<EditTarget>? target,
    Value<String>? itemId,
    Value<String>? patch,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? attempts,
    Value<String?>? lastError,
    Value<int>? rowid,
  }) {
    return PendingEditsCompanion(
      target: target ?? this.target,
      itemId: itemId ?? this.itemId,
      patch: patch ?? this.patch,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      attempts: attempts ?? this.attempts,
      lastError: lastError ?? this.lastError,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (target.present) {
      map['target'] = Variable<String>(
        $PendingEditsTable.$convertertarget.toSql(target.value),
      );
    }
    if (itemId.present) {
      map['item_id'] = Variable<String>(itemId.value);
    }
    if (patch.present) {
      map['patch'] = Variable<String>(patch.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (attempts.present) {
      map['attempts'] = Variable<int>(attempts.value);
    }
    if (lastError.present) {
      map['last_error'] = Variable<String>(lastError.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PendingEditsCompanion(')
          ..write('target: $target, ')
          ..write('itemId: $itemId, ')
          ..write('patch: $patch, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('attempts: $attempts, ')
          ..write('lastError: $lastError, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $FoldersTable folders = $FoldersTable(this);
  late final $DriveFilesTable driveFiles = $DriveFilesTable(this);
  late final $FilePartsTable fileParts = $FilePartsTable(this);
  late final $TransfersTable transfers = $TransfersTable(this);
  late final $BackupAssetsTable backupAssets = $BackupAssetsTable(this);
  late final $AlbumsTable albums = $AlbumsTable(this);
  late final $AlbumFilesTable albumFiles = $AlbumFilesTable(this);
  late final $OfflinePinsTable offlinePins = $OfflinePinsTable(this);
  late final $OfflineCopiesTable offlineCopies = $OfflineCopiesTable(this);
  late final $FileContentsTable fileContents = $FileContentsTable(this);
  late final $FileOpensTable fileOpens = $FileOpensTable(this);
  late final $PlayPositionsTable playPositions = $PlayPositionsTable(this);
  late final $WatchedFoldersTable watchedFolders = $WatchedFoldersTable(this);
  late final $WatchedFilesTable watchedFiles = $WatchedFilesTable(this);
  late final $PendingEditsTable pendingEdits = $PendingEditsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    folders,
    driveFiles,
    fileParts,
    transfers,
    backupAssets,
    albums,
    albumFiles,
    offlinePins,
    offlineCopies,
    fileContents,
    fileOpens,
    playPositions,
    watchedFolders,
    watchedFiles,
    pendingEdits,
  ];
}

typedef $$FoldersTableCreateCompanionBuilder = FoldersCompanion Function({
  required String id,
  Value<String?> parentId,
  required String name,
  required int messageId,
  required DateTime createdAt,
  required DateTime modifiedAt,
  Value<DateTime?> trashedAt,
  Value<bool> hidden,
  Value<String?> manifestExtra,
  Value<bool> starred,
  Value<int> rowid,
});
typedef $$FoldersTableUpdateCompanionBuilder = FoldersCompanion Function({
  Value<String> id,
  Value<String?> parentId,
  Value<String> name,
  Value<int> messageId,
  Value<DateTime> createdAt,
  Value<DateTime> modifiedAt,
  Value<DateTime?> trashedAt,
  Value<bool> hidden,
  Value<String?> manifestExtra,
  Value<bool> starred,
  Value<int> rowid,
});

class $$FoldersTableFilterComposer
    extends Composer<_$AppDatabase, $FoldersTable> {
  $$FoldersTableFilterComposer({
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

  ColumnFilters<String> get parentId => $composableBuilder(
    column: $table.parentId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get messageId => $composableBuilder(
    column: $table.messageId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get modifiedAt => $composableBuilder(
    column: $table.modifiedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get trashedAt => $composableBuilder(
    column: $table.trashedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get hidden => $composableBuilder(
    column: $table.hidden,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get manifestExtra => $composableBuilder(
    column: $table.manifestExtra,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get starred => $composableBuilder(
    column: $table.starred,
    builder: (column) => ColumnFilters(column),
  );
}

class $$FoldersTableOrderingComposer
    extends Composer<_$AppDatabase, $FoldersTable> {
  $$FoldersTableOrderingComposer({
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

  ColumnOrderings<String> get parentId => $composableBuilder(
    column: $table.parentId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get messageId => $composableBuilder(
    column: $table.messageId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get modifiedAt => $composableBuilder(
    column: $table.modifiedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get trashedAt => $composableBuilder(
    column: $table.trashedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get hidden => $composableBuilder(
    column: $table.hidden,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get manifestExtra => $composableBuilder(
    column: $table.manifestExtra,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get starred => $composableBuilder(
    column: $table.starred,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$FoldersTableAnnotationComposer
    extends Composer<_$AppDatabase, $FoldersTable> {
  $$FoldersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get parentId =>
      $composableBuilder(column: $table.parentId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get messageId =>
      $composableBuilder(column: $table.messageId, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get modifiedAt => $composableBuilder(
    column: $table.modifiedAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get trashedAt =>
      $composableBuilder(column: $table.trashedAt, builder: (column) => column);

  GeneratedColumn<bool> get hidden =>
      $composableBuilder(column: $table.hidden, builder: (column) => column);

  GeneratedColumn<String> get manifestExtra => $composableBuilder(
    column: $table.manifestExtra,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get starred =>
      $composableBuilder(column: $table.starred, builder: (column) => column);
}

class $$FoldersTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $FoldersTable,
          FolderRow,
          $$FoldersTableFilterComposer,
          $$FoldersTableOrderingComposer,
          $$FoldersTableAnnotationComposer,
          $$FoldersTableCreateCompanionBuilder,
          $$FoldersTableUpdateCompanionBuilder,
          (FolderRow, BaseReferences<_$AppDatabase, $FoldersTable, FolderRow>),
          FolderRow,
          PrefetchHooks Function()
        > {
  $$FoldersTableTableManager(_$AppDatabase db, $FoldersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FoldersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FoldersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FoldersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String?> parentId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> messageId = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> modifiedAt = const Value.absent(),
                Value<DateTime?> trashedAt = const Value.absent(),
                Value<bool> hidden = const Value.absent(),
                Value<String?> manifestExtra = const Value.absent(),
                Value<bool> starred = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FoldersCompanion(
                id: id,
                parentId: parentId,
                name: name,
                messageId: messageId,
                createdAt: createdAt,
                modifiedAt: modifiedAt,
                trashedAt: trashedAt,
                hidden: hidden,
                manifestExtra: manifestExtra,
                starred: starred,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<String?> parentId = const Value.absent(),
                required String name,
                required int messageId,
                required DateTime createdAt,
                required DateTime modifiedAt,
                Value<DateTime?> trashedAt = const Value.absent(),
                Value<bool> hidden = const Value.absent(),
                Value<String?> manifestExtra = const Value.absent(),
                Value<bool> starred = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FoldersCompanion.insert(
                id: id,
                parentId: parentId,
                name: name,
                messageId: messageId,
                createdAt: createdAt,
                modifiedAt: modifiedAt,
                trashedAt: trashedAt,
                hidden: hidden,
                manifestExtra: manifestExtra,
                starred: starred,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$FoldersTable, FolderRow>(table),
                  BaseReferences<_$AppDatabase, $FoldersTable, FolderRow>(
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

typedef $$FoldersTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $FoldersTable,
      FolderRow,
      $$FoldersTableFilterComposer,
      $$FoldersTableOrderingComposer,
      $$FoldersTableAnnotationComposer,
      $$FoldersTableCreateCompanionBuilder,
      $$FoldersTableUpdateCompanionBuilder,
      (FolderRow, BaseReferences<_$AppDatabase, $FoldersTable, FolderRow>),
      FolderRow,
      PrefetchHooks Function()
    >;
typedef $$DriveFilesTableCreateCompanionBuilder = DriveFilesCompanion Function({
  required String id,
  Value<String?> folderId,
  required String name,
  required String mimeType,
  required FileKind kind,
  required int size,
  required DateTime createdAt,
  required DateTime modifiedAt,
  Value<int> partCount,
  Value<int> partsPresent,
  Value<bool> starred,
  Value<String?> minithumbnail,
  Value<int?> thumbnailFileId,
  Value<DateTime?> takenAt,
  Value<DateTime?> trashedAt,
  Value<bool> hidden,
  Value<String?> manifestExtra,
  Value<int?> durationSeconds,
  Value<String?> replacedBy,
  Value<bool> adopted,
  Value<int?> originalSize,
  Value<int> rowid,
});
typedef $$DriveFilesTableUpdateCompanionBuilder = DriveFilesCompanion Function({
  Value<String> id,
  Value<String?> folderId,
  Value<String> name,
  Value<String> mimeType,
  Value<FileKind> kind,
  Value<int> size,
  Value<DateTime> createdAt,
  Value<DateTime> modifiedAt,
  Value<int> partCount,
  Value<int> partsPresent,
  Value<bool> starred,
  Value<String?> minithumbnail,
  Value<int?> thumbnailFileId,
  Value<DateTime?> takenAt,
  Value<DateTime?> trashedAt,
  Value<bool> hidden,
  Value<String?> manifestExtra,
  Value<int?> durationSeconds,
  Value<String?> replacedBy,
  Value<bool> adopted,
  Value<int?> originalSize,
  Value<int> rowid,
});

class $$DriveFilesTableFilterComposer
    extends Composer<_$AppDatabase, $DriveFilesTable> {
  $$DriveFilesTableFilterComposer({
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

  ColumnFilters<String> get folderId => $composableBuilder(
    column: $table.folderId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mimeType => $composableBuilder(
    column: $table.mimeType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<FileKind, FileKind, String> get kind =>
      $composableBuilder(
        column: $table.kind,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<int> get size => $composableBuilder(
    column: $table.size,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get modifiedAt => $composableBuilder(
    column: $table.modifiedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get partCount => $composableBuilder(
    column: $table.partCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get partsPresent => $composableBuilder(
    column: $table.partsPresent,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get starred => $composableBuilder(
    column: $table.starred,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get minithumbnail => $composableBuilder(
    column: $table.minithumbnail,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get thumbnailFileId => $composableBuilder(
    column: $table.thumbnailFileId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get takenAt => $composableBuilder(
    column: $table.takenAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get trashedAt => $composableBuilder(
    column: $table.trashedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get hidden => $composableBuilder(
    column: $table.hidden,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get manifestExtra => $composableBuilder(
    column: $table.manifestExtra,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationSeconds => $composableBuilder(
    column: $table.durationSeconds,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get replacedBy => $composableBuilder(
    column: $table.replacedBy,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get adopted => $composableBuilder(
    column: $table.adopted,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get originalSize => $composableBuilder(
    column: $table.originalSize,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DriveFilesTableOrderingComposer
    extends Composer<_$AppDatabase, $DriveFilesTable> {
  $$DriveFilesTableOrderingComposer({
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

  ColumnOrderings<String> get folderId => $composableBuilder(
    column: $table.folderId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mimeType => $composableBuilder(
    column: $table.mimeType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get size => $composableBuilder(
    column: $table.size,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get modifiedAt => $composableBuilder(
    column: $table.modifiedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get partCount => $composableBuilder(
    column: $table.partCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get partsPresent => $composableBuilder(
    column: $table.partsPresent,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get starred => $composableBuilder(
    column: $table.starred,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get minithumbnail => $composableBuilder(
    column: $table.minithumbnail,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get thumbnailFileId => $composableBuilder(
    column: $table.thumbnailFileId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get takenAt => $composableBuilder(
    column: $table.takenAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get trashedAt => $composableBuilder(
    column: $table.trashedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get hidden => $composableBuilder(
    column: $table.hidden,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get manifestExtra => $composableBuilder(
    column: $table.manifestExtra,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationSeconds => $composableBuilder(
    column: $table.durationSeconds,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get replacedBy => $composableBuilder(
    column: $table.replacedBy,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get adopted => $composableBuilder(
    column: $table.adopted,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get originalSize => $composableBuilder(
    column: $table.originalSize,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DriveFilesTableAnnotationComposer
    extends Composer<_$AppDatabase, $DriveFilesTable> {
  $$DriveFilesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get folderId =>
      $composableBuilder(column: $table.folderId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get mimeType =>
      $composableBuilder(column: $table.mimeType, builder: (column) => column);

  GeneratedColumnWithTypeConverter<FileKind, String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<int> get size =>
      $composableBuilder(column: $table.size, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get modifiedAt => $composableBuilder(
    column: $table.modifiedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get partCount =>
      $composableBuilder(column: $table.partCount, builder: (column) => column);

  GeneratedColumn<int> get partsPresent => $composableBuilder(
    column: $table.partsPresent,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get starred =>
      $composableBuilder(column: $table.starred, builder: (column) => column);

  GeneratedColumn<String> get minithumbnail => $composableBuilder(
    column: $table.minithumbnail,
    builder: (column) => column,
  );

  GeneratedColumn<int> get thumbnailFileId => $composableBuilder(
    column: $table.thumbnailFileId,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get takenAt =>
      $composableBuilder(column: $table.takenAt, builder: (column) => column);

  GeneratedColumn<DateTime> get trashedAt =>
      $composableBuilder(column: $table.trashedAt, builder: (column) => column);

  GeneratedColumn<bool> get hidden =>
      $composableBuilder(column: $table.hidden, builder: (column) => column);

  GeneratedColumn<String> get manifestExtra => $composableBuilder(
    column: $table.manifestExtra,
    builder: (column) => column,
  );

  GeneratedColumn<int> get durationSeconds => $composableBuilder(
    column: $table.durationSeconds,
    builder: (column) => column,
  );

  GeneratedColumn<String> get replacedBy => $composableBuilder(
    column: $table.replacedBy,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get adopted =>
      $composableBuilder(column: $table.adopted, builder: (column) => column);

  GeneratedColumn<int> get originalSize => $composableBuilder(
    column: $table.originalSize,
    builder: (column) => column,
  );
}

class $$DriveFilesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $DriveFilesTable,
          FileRow,
          $$DriveFilesTableFilterComposer,
          $$DriveFilesTableOrderingComposer,
          $$DriveFilesTableAnnotationComposer,
          $$DriveFilesTableCreateCompanionBuilder,
          $$DriveFilesTableUpdateCompanionBuilder,
          (FileRow, BaseReferences<_$AppDatabase, $DriveFilesTable, FileRow>),
          FileRow,
          PrefetchHooks Function()
        > {
  $$DriveFilesTableTableManager(_$AppDatabase db, $DriveFilesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DriveFilesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DriveFilesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DriveFilesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String?> folderId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> mimeType = const Value.absent(),
                Value<FileKind> kind = const Value.absent(),
                Value<int> size = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> modifiedAt = const Value.absent(),
                Value<int> partCount = const Value.absent(),
                Value<int> partsPresent = const Value.absent(),
                Value<bool> starred = const Value.absent(),
                Value<String?> minithumbnail = const Value.absent(),
                Value<int?> thumbnailFileId = const Value.absent(),
                Value<DateTime?> takenAt = const Value.absent(),
                Value<DateTime?> trashedAt = const Value.absent(),
                Value<bool> hidden = const Value.absent(),
                Value<String?> manifestExtra = const Value.absent(),
                Value<int?> durationSeconds = const Value.absent(),
                Value<String?> replacedBy = const Value.absent(),
                Value<bool> adopted = const Value.absent(),
                Value<int?> originalSize = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DriveFilesCompanion(
                id: id,
                folderId: folderId,
                name: name,
                mimeType: mimeType,
                kind: kind,
                size: size,
                createdAt: createdAt,
                modifiedAt: modifiedAt,
                partCount: partCount,
                partsPresent: partsPresent,
                starred: starred,
                minithumbnail: minithumbnail,
                thumbnailFileId: thumbnailFileId,
                takenAt: takenAt,
                trashedAt: trashedAt,
                hidden: hidden,
                manifestExtra: manifestExtra,
                durationSeconds: durationSeconds,
                replacedBy: replacedBy,
                adopted: adopted,
                originalSize: originalSize,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<String?> folderId = const Value.absent(),
                required String name,
                required String mimeType,
                required FileKind kind,
                required int size,
                required DateTime createdAt,
                required DateTime modifiedAt,
                Value<int> partCount = const Value.absent(),
                Value<int> partsPresent = const Value.absent(),
                Value<bool> starred = const Value.absent(),
                Value<String?> minithumbnail = const Value.absent(),
                Value<int?> thumbnailFileId = const Value.absent(),
                Value<DateTime?> takenAt = const Value.absent(),
                Value<DateTime?> trashedAt = const Value.absent(),
                Value<bool> hidden = const Value.absent(),
                Value<String?> manifestExtra = const Value.absent(),
                Value<int?> durationSeconds = const Value.absent(),
                Value<String?> replacedBy = const Value.absent(),
                Value<bool> adopted = const Value.absent(),
                Value<int?> originalSize = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DriveFilesCompanion.insert(
                id: id,
                folderId: folderId,
                name: name,
                mimeType: mimeType,
                kind: kind,
                size: size,
                createdAt: createdAt,
                modifiedAt: modifiedAt,
                partCount: partCount,
                partsPresent: partsPresent,
                starred: starred,
                minithumbnail: minithumbnail,
                thumbnailFileId: thumbnailFileId,
                takenAt: takenAt,
                trashedAt: trashedAt,
                hidden: hidden,
                manifestExtra: manifestExtra,
                durationSeconds: durationSeconds,
                replacedBy: replacedBy,
                adopted: adopted,
                originalSize: originalSize,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$DriveFilesTable, FileRow>(table),
                  BaseReferences<_$AppDatabase, $DriveFilesTable, FileRow>(
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

typedef $$DriveFilesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $DriveFilesTable,
      FileRow,
      $$DriveFilesTableFilterComposer,
      $$DriveFilesTableOrderingComposer,
      $$DriveFilesTableAnnotationComposer,
      $$DriveFilesTableCreateCompanionBuilder,
      $$DriveFilesTableUpdateCompanionBuilder,
      (FileRow, BaseReferences<_$AppDatabase, $DriveFilesTable, FileRow>),
      FileRow,
      PrefetchHooks Function()
    >;
typedef $$FilePartsTableCreateCompanionBuilder = FilePartsCompanion Function({
  required String fileId,
  required int partIndex,
  required int messageId,
  required int tdFileId,
  required int size,
  Value<int> rowid,
});
typedef $$FilePartsTableUpdateCompanionBuilder = FilePartsCompanion Function({
  Value<String> fileId,
  Value<int> partIndex,
  Value<int> messageId,
  Value<int> tdFileId,
  Value<int> size,
  Value<int> rowid,
});

class $$FilePartsTableFilterComposer
    extends Composer<_$AppDatabase, $FilePartsTable> {
  $$FilePartsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get fileId => $composableBuilder(
    column: $table.fileId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get partIndex => $composableBuilder(
    column: $table.partIndex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get messageId => $composableBuilder(
    column: $table.messageId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get tdFileId => $composableBuilder(
    column: $table.tdFileId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get size => $composableBuilder(
    column: $table.size,
    builder: (column) => ColumnFilters(column),
  );
}

class $$FilePartsTableOrderingComposer
    extends Composer<_$AppDatabase, $FilePartsTable> {
  $$FilePartsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get fileId => $composableBuilder(
    column: $table.fileId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get partIndex => $composableBuilder(
    column: $table.partIndex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get messageId => $composableBuilder(
    column: $table.messageId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get tdFileId => $composableBuilder(
    column: $table.tdFileId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get size => $composableBuilder(
    column: $table.size,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$FilePartsTableAnnotationComposer
    extends Composer<_$AppDatabase, $FilePartsTable> {
  $$FilePartsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get fileId =>
      $composableBuilder(column: $table.fileId, builder: (column) => column);

  GeneratedColumn<int> get partIndex =>
      $composableBuilder(column: $table.partIndex, builder: (column) => column);

  GeneratedColumn<int> get messageId =>
      $composableBuilder(column: $table.messageId, builder: (column) => column);

  GeneratedColumn<int> get tdFileId =>
      $composableBuilder(column: $table.tdFileId, builder: (column) => column);

  GeneratedColumn<int> get size =>
      $composableBuilder(column: $table.size, builder: (column) => column);
}

class $$FilePartsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $FilePartsTable,
          PartRow,
          $$FilePartsTableFilterComposer,
          $$FilePartsTableOrderingComposer,
          $$FilePartsTableAnnotationComposer,
          $$FilePartsTableCreateCompanionBuilder,
          $$FilePartsTableUpdateCompanionBuilder,
          (PartRow, BaseReferences<_$AppDatabase, $FilePartsTable, PartRow>),
          PartRow,
          PrefetchHooks Function()
        > {
  $$FilePartsTableTableManager(_$AppDatabase db, $FilePartsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FilePartsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FilePartsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FilePartsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> fileId = const Value.absent(),
                Value<int> partIndex = const Value.absent(),
                Value<int> messageId = const Value.absent(),
                Value<int> tdFileId = const Value.absent(),
                Value<int> size = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FilePartsCompanion(
                fileId: fileId,
                partIndex: partIndex,
                messageId: messageId,
                tdFileId: tdFileId,
                size: size,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String fileId,
                required int partIndex,
                required int messageId,
                required int tdFileId,
                required int size,
                Value<int> rowid = const Value.absent(),
              }) => FilePartsCompanion.insert(
                fileId: fileId,
                partIndex: partIndex,
                messageId: messageId,
                tdFileId: tdFileId,
                size: size,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$FilePartsTable, PartRow>(table),
                  BaseReferences<_$AppDatabase, $FilePartsTable, PartRow>(
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

typedef $$FilePartsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $FilePartsTable,
      PartRow,
      $$FilePartsTableFilterComposer,
      $$FilePartsTableOrderingComposer,
      $$FilePartsTableAnnotationComposer,
      $$FilePartsTableCreateCompanionBuilder,
      $$FilePartsTableUpdateCompanionBuilder,
      (PartRow, BaseReferences<_$AppDatabase, $FilePartsTable, PartRow>),
      PartRow,
      PrefetchHooks Function()
    >;
typedef $$TransfersTableCreateCompanionBuilder = TransfersCompanion Function({
  required String id,
  required TransferKind kind,
  required TransferStatus status,
  required String name,
  required String mimeType,
  required String fileId,
  Value<String?> folderId,
  Value<String?> sourcePath,
  Value<bool> ownsSource,
  Value<String?> resultPath,
  required int totalBytes,
  Value<int> doneBytes,
  Value<int> partCount,
  Value<int> completedParts,
  Value<String?> error,
  required DateTime createdAt,
  Value<DateTime?> finishedAt,
  Value<TransferOrigin> origin,
  Value<String?> assetId,
  Value<DateTime?> takenAt,
  Value<String?> thumbnailPath,
  Value<SaveTarget?> saveTo,
  Value<String?> saveFolder,
  Value<bool> wifiOnly,
  Value<int?> durationSeconds,
  Value<String?> replacesFileId,
  Value<int?> sourceChatId,
  Value<int?> sourceMessageId,
  Value<int> rowid,
});
typedef $$TransfersTableUpdateCompanionBuilder = TransfersCompanion Function({
  Value<String> id,
  Value<TransferKind> kind,
  Value<TransferStatus> status,
  Value<String> name,
  Value<String> mimeType,
  Value<String> fileId,
  Value<String?> folderId,
  Value<String?> sourcePath,
  Value<bool> ownsSource,
  Value<String?> resultPath,
  Value<int> totalBytes,
  Value<int> doneBytes,
  Value<int> partCount,
  Value<int> completedParts,
  Value<String?> error,
  Value<DateTime> createdAt,
  Value<DateTime?> finishedAt,
  Value<TransferOrigin> origin,
  Value<String?> assetId,
  Value<DateTime?> takenAt,
  Value<String?> thumbnailPath,
  Value<SaveTarget?> saveTo,
  Value<String?> saveFolder,
  Value<bool> wifiOnly,
  Value<int?> durationSeconds,
  Value<String?> replacesFileId,
  Value<int?> sourceChatId,
  Value<int?> sourceMessageId,
  Value<int> rowid,
});

class $$TransfersTableFilterComposer
    extends Composer<_$AppDatabase, $TransfersTable> {
  $$TransfersTableFilterComposer({
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

  ColumnWithTypeConverterFilters<TransferKind, TransferKind, String> get kind =>
      $composableBuilder(
        column: $table.kind,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnWithTypeConverterFilters<TransferStatus, TransferStatus, String>
  get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mimeType => $composableBuilder(
    column: $table.mimeType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fileId => $composableBuilder(
    column: $table.fileId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get folderId => $composableBuilder(
    column: $table.folderId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourcePath => $composableBuilder(
    column: $table.sourcePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get ownsSource => $composableBuilder(
    column: $table.ownsSource,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get resultPath => $composableBuilder(
    column: $table.resultPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get totalBytes => $composableBuilder(
    column: $table.totalBytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get doneBytes => $composableBuilder(
    column: $table.doneBytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get partCount => $composableBuilder(
    column: $table.partCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get completedParts => $composableBuilder(
    column: $table.completedParts,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get error => $composableBuilder(
    column: $table.error,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get finishedAt => $composableBuilder(
    column: $table.finishedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<TransferOrigin, TransferOrigin, String>
  get origin => $composableBuilder(
    column: $table.origin,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<String> get assetId => $composableBuilder(
    column: $table.assetId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get takenAt => $composableBuilder(
    column: $table.takenAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get thumbnailPath => $composableBuilder(
    column: $table.thumbnailPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<SaveTarget?, SaveTarget, String> get saveTo =>
      $composableBuilder(
        column: $table.saveTo,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<String> get saveFolder => $composableBuilder(
    column: $table.saveFolder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get wifiOnly => $composableBuilder(
    column: $table.wifiOnly,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationSeconds => $composableBuilder(
    column: $table.durationSeconds,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get replacesFileId => $composableBuilder(
    column: $table.replacesFileId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sourceChatId => $composableBuilder(
    column: $table.sourceChatId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sourceMessageId => $composableBuilder(
    column: $table.sourceMessageId,
    builder: (column) => ColumnFilters(column),
  );
}

class $$TransfersTableOrderingComposer
    extends Composer<_$AppDatabase, $TransfersTable> {
  $$TransfersTableOrderingComposer({
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

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mimeType => $composableBuilder(
    column: $table.mimeType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fileId => $composableBuilder(
    column: $table.fileId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get folderId => $composableBuilder(
    column: $table.folderId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourcePath => $composableBuilder(
    column: $table.sourcePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get ownsSource => $composableBuilder(
    column: $table.ownsSource,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get resultPath => $composableBuilder(
    column: $table.resultPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get totalBytes => $composableBuilder(
    column: $table.totalBytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get doneBytes => $composableBuilder(
    column: $table.doneBytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get partCount => $composableBuilder(
    column: $table.partCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get completedParts => $composableBuilder(
    column: $table.completedParts,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get error => $composableBuilder(
    column: $table.error,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get finishedAt => $composableBuilder(
    column: $table.finishedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get origin => $composableBuilder(
    column: $table.origin,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get assetId => $composableBuilder(
    column: $table.assetId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get takenAt => $composableBuilder(
    column: $table.takenAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get thumbnailPath => $composableBuilder(
    column: $table.thumbnailPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get saveTo => $composableBuilder(
    column: $table.saveTo,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get saveFolder => $composableBuilder(
    column: $table.saveFolder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get wifiOnly => $composableBuilder(
    column: $table.wifiOnly,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationSeconds => $composableBuilder(
    column: $table.durationSeconds,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get replacesFileId => $composableBuilder(
    column: $table.replacesFileId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sourceChatId => $composableBuilder(
    column: $table.sourceChatId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sourceMessageId => $composableBuilder(
    column: $table.sourceMessageId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TransfersTableAnnotationComposer
    extends Composer<_$AppDatabase, $TransfersTable> {
  $$TransfersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumnWithTypeConverter<TransferKind, String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumnWithTypeConverter<TransferStatus, String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get mimeType =>
      $composableBuilder(column: $table.mimeType, builder: (column) => column);

  GeneratedColumn<String> get fileId =>
      $composableBuilder(column: $table.fileId, builder: (column) => column);

  GeneratedColumn<String> get folderId =>
      $composableBuilder(column: $table.folderId, builder: (column) => column);

  GeneratedColumn<String> get sourcePath => $composableBuilder(
    column: $table.sourcePath,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get ownsSource => $composableBuilder(
    column: $table.ownsSource,
    builder: (column) => column,
  );

  GeneratedColumn<String> get resultPath => $composableBuilder(
    column: $table.resultPath,
    builder: (column) => column,
  );

  GeneratedColumn<int> get totalBytes => $composableBuilder(
    column: $table.totalBytes,
    builder: (column) => column,
  );

  GeneratedColumn<int> get doneBytes =>
      $composableBuilder(column: $table.doneBytes, builder: (column) => column);

  GeneratedColumn<int> get partCount =>
      $composableBuilder(column: $table.partCount, builder: (column) => column);

  GeneratedColumn<int> get completedParts => $composableBuilder(
    column: $table.completedParts,
    builder: (column) => column,
  );

  GeneratedColumn<String> get error =>
      $composableBuilder(column: $table.error, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get finishedAt => $composableBuilder(
    column: $table.finishedAt,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<TransferOrigin, String> get origin =>
      $composableBuilder(column: $table.origin, builder: (column) => column);

  GeneratedColumn<String> get assetId =>
      $composableBuilder(column: $table.assetId, builder: (column) => column);

  GeneratedColumn<DateTime> get takenAt =>
      $composableBuilder(column: $table.takenAt, builder: (column) => column);

  GeneratedColumn<String> get thumbnailPath => $composableBuilder(
    column: $table.thumbnailPath,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<SaveTarget?, String> get saveTo =>
      $composableBuilder(column: $table.saveTo, builder: (column) => column);

  GeneratedColumn<String> get saveFolder => $composableBuilder(
    column: $table.saveFolder,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get wifiOnly =>
      $composableBuilder(column: $table.wifiOnly, builder: (column) => column);

  GeneratedColumn<int> get durationSeconds => $composableBuilder(
    column: $table.durationSeconds,
    builder: (column) => column,
  );

  GeneratedColumn<String> get replacesFileId => $composableBuilder(
    column: $table.replacesFileId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get sourceChatId => $composableBuilder(
    column: $table.sourceChatId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get sourceMessageId => $composableBuilder(
    column: $table.sourceMessageId,
    builder: (column) => column,
  );
}

class $$TransfersTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TransfersTable,
          TransferRow,
          $$TransfersTableFilterComposer,
          $$TransfersTableOrderingComposer,
          $$TransfersTableAnnotationComposer,
          $$TransfersTableCreateCompanionBuilder,
          $$TransfersTableUpdateCompanionBuilder,
          (
            TransferRow,
            BaseReferences<_$AppDatabase, $TransfersTable, TransferRow>,
          ),
          TransferRow,
          PrefetchHooks Function()
        > {
  $$TransfersTableTableManager(_$AppDatabase db, $TransfersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TransfersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TransfersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TransfersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<TransferKind> kind = const Value.absent(),
                Value<TransferStatus> status = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> mimeType = const Value.absent(),
                Value<String> fileId = const Value.absent(),
                Value<String?> folderId = const Value.absent(),
                Value<String?> sourcePath = const Value.absent(),
                Value<bool> ownsSource = const Value.absent(),
                Value<String?> resultPath = const Value.absent(),
                Value<int> totalBytes = const Value.absent(),
                Value<int> doneBytes = const Value.absent(),
                Value<int> partCount = const Value.absent(),
                Value<int> completedParts = const Value.absent(),
                Value<String?> error = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime?> finishedAt = const Value.absent(),
                Value<TransferOrigin> origin = const Value.absent(),
                Value<String?> assetId = const Value.absent(),
                Value<DateTime?> takenAt = const Value.absent(),
                Value<String?> thumbnailPath = const Value.absent(),
                Value<SaveTarget?> saveTo = const Value.absent(),
                Value<String?> saveFolder = const Value.absent(),
                Value<bool> wifiOnly = const Value.absent(),
                Value<int?> durationSeconds = const Value.absent(),
                Value<String?> replacesFileId = const Value.absent(),
                Value<int?> sourceChatId = const Value.absent(),
                Value<int?> sourceMessageId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TransfersCompanion(
                id: id,
                kind: kind,
                status: status,
                name: name,
                mimeType: mimeType,
                fileId: fileId,
                folderId: folderId,
                sourcePath: sourcePath,
                ownsSource: ownsSource,
                resultPath: resultPath,
                totalBytes: totalBytes,
                doneBytes: doneBytes,
                partCount: partCount,
                completedParts: completedParts,
                error: error,
                createdAt: createdAt,
                finishedAt: finishedAt,
                origin: origin,
                assetId: assetId,
                takenAt: takenAt,
                thumbnailPath: thumbnailPath,
                saveTo: saveTo,
                saveFolder: saveFolder,
                wifiOnly: wifiOnly,
                durationSeconds: durationSeconds,
                replacesFileId: replacesFileId,
                sourceChatId: sourceChatId,
                sourceMessageId: sourceMessageId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required TransferKind kind,
                required TransferStatus status,
                required String name,
                required String mimeType,
                required String fileId,
                Value<String?> folderId = const Value.absent(),
                Value<String?> sourcePath = const Value.absent(),
                Value<bool> ownsSource = const Value.absent(),
                Value<String?> resultPath = const Value.absent(),
                required int totalBytes,
                Value<int> doneBytes = const Value.absent(),
                Value<int> partCount = const Value.absent(),
                Value<int> completedParts = const Value.absent(),
                Value<String?> error = const Value.absent(),
                required DateTime createdAt,
                Value<DateTime?> finishedAt = const Value.absent(),
                Value<TransferOrigin> origin = const Value.absent(),
                Value<String?> assetId = const Value.absent(),
                Value<DateTime?> takenAt = const Value.absent(),
                Value<String?> thumbnailPath = const Value.absent(),
                Value<SaveTarget?> saveTo = const Value.absent(),
                Value<String?> saveFolder = const Value.absent(),
                Value<bool> wifiOnly = const Value.absent(),
                Value<int?> durationSeconds = const Value.absent(),
                Value<String?> replacesFileId = const Value.absent(),
                Value<int?> sourceChatId = const Value.absent(),
                Value<int?> sourceMessageId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TransfersCompanion.insert(
                id: id,
                kind: kind,
                status: status,
                name: name,
                mimeType: mimeType,
                fileId: fileId,
                folderId: folderId,
                sourcePath: sourcePath,
                ownsSource: ownsSource,
                resultPath: resultPath,
                totalBytes: totalBytes,
                doneBytes: doneBytes,
                partCount: partCount,
                completedParts: completedParts,
                error: error,
                createdAt: createdAt,
                finishedAt: finishedAt,
                origin: origin,
                assetId: assetId,
                takenAt: takenAt,
                thumbnailPath: thumbnailPath,
                saveTo: saveTo,
                saveFolder: saveFolder,
                wifiOnly: wifiOnly,
                durationSeconds: durationSeconds,
                replacesFileId: replacesFileId,
                sourceChatId: sourceChatId,
                sourceMessageId: sourceMessageId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$TransfersTable, TransferRow>(table),
                  BaseReferences<_$AppDatabase, $TransfersTable, TransferRow>(
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

typedef $$TransfersTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TransfersTable,
      TransferRow,
      $$TransfersTableFilterComposer,
      $$TransfersTableOrderingComposer,
      $$TransfersTableAnnotationComposer,
      $$TransfersTableCreateCompanionBuilder,
      $$TransfersTableUpdateCompanionBuilder,
      (
        TransferRow,
        BaseReferences<_$AppDatabase, $TransfersTable, TransferRow>,
      ),
      TransferRow,
      PrefetchHooks Function()
    >;
typedef $$BackupAssetsTableCreateCompanionBuilder =
    BackupAssetsCompanion Function({
      required String assetId,
      required BackupAssetState state,
      Value<String?> fileId,
      Value<int> failures,
      required DateTime updatedAt,
      Value<String?> reason,
      Value<int> rowid,
    });
typedef $$BackupAssetsTableUpdateCompanionBuilder =
    BackupAssetsCompanion Function({
      Value<String> assetId,
      Value<BackupAssetState> state,
      Value<String?> fileId,
      Value<int> failures,
      Value<DateTime> updatedAt,
      Value<String?> reason,
      Value<int> rowid,
    });

class $$BackupAssetsTableFilterComposer
    extends Composer<_$AppDatabase, $BackupAssetsTable> {
  $$BackupAssetsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get assetId => $composableBuilder(
    column: $table.assetId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<BackupAssetState, BackupAssetState, String>
  get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<String> get fileId => $composableBuilder(
    column: $table.fileId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get failures => $composableBuilder(
    column: $table.failures,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get reason => $composableBuilder(
    column: $table.reason,
    builder: (column) => ColumnFilters(column),
  );
}

class $$BackupAssetsTableOrderingComposer
    extends Composer<_$AppDatabase, $BackupAssetsTable> {
  $$BackupAssetsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get assetId => $composableBuilder(
    column: $table.assetId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fileId => $composableBuilder(
    column: $table.fileId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get failures => $composableBuilder(
    column: $table.failures,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get reason => $composableBuilder(
    column: $table.reason,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$BackupAssetsTableAnnotationComposer
    extends Composer<_$AppDatabase, $BackupAssetsTable> {
  $$BackupAssetsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get assetId =>
      $composableBuilder(column: $table.assetId, builder: (column) => column);

  GeneratedColumnWithTypeConverter<BackupAssetState, String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<String> get fileId =>
      $composableBuilder(column: $table.fileId, builder: (column) => column);

  GeneratedColumn<int> get failures =>
      $composableBuilder(column: $table.failures, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get reason =>
      $composableBuilder(column: $table.reason, builder: (column) => column);
}

class $$BackupAssetsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $BackupAssetsTable,
          BackupAssetRow,
          $$BackupAssetsTableFilterComposer,
          $$BackupAssetsTableOrderingComposer,
          $$BackupAssetsTableAnnotationComposer,
          $$BackupAssetsTableCreateCompanionBuilder,
          $$BackupAssetsTableUpdateCompanionBuilder,
          (
            BackupAssetRow,
            BaseReferences<_$AppDatabase, $BackupAssetsTable, BackupAssetRow>,
          ),
          BackupAssetRow,
          PrefetchHooks Function()
        > {
  $$BackupAssetsTableTableManager(_$AppDatabase db, $BackupAssetsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BackupAssetsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$BackupAssetsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$BackupAssetsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> assetId = const Value.absent(),
                Value<BackupAssetState> state = const Value.absent(),
                Value<String?> fileId = const Value.absent(),
                Value<int> failures = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<String?> reason = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BackupAssetsCompanion(
                assetId: assetId,
                state: state,
                fileId: fileId,
                failures: failures,
                updatedAt: updatedAt,
                reason: reason,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String assetId,
                required BackupAssetState state,
                Value<String?> fileId = const Value.absent(),
                Value<int> failures = const Value.absent(),
                required DateTime updatedAt,
                Value<String?> reason = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BackupAssetsCompanion.insert(
                assetId: assetId,
                state: state,
                fileId: fileId,
                failures: failures,
                updatedAt: updatedAt,
                reason: reason,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$BackupAssetsTable, BackupAssetRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $BackupAssetsTable,
                    BackupAssetRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$BackupAssetsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $BackupAssetsTable,
      BackupAssetRow,
      $$BackupAssetsTableFilterComposer,
      $$BackupAssetsTableOrderingComposer,
      $$BackupAssetsTableAnnotationComposer,
      $$BackupAssetsTableCreateCompanionBuilder,
      $$BackupAssetsTableUpdateCompanionBuilder,
      (
        BackupAssetRow,
        BaseReferences<_$AppDatabase, $BackupAssetsTable, BackupAssetRow>,
      ),
      BackupAssetRow,
      PrefetchHooks Function()
    >;
typedef $$AlbumsTableCreateCompanionBuilder = AlbumsCompanion Function({
  required String id,
  required String name,
  required int messageId,
  required DateTime createdAt,
  required DateTime modifiedAt,
  Value<int> rowid,
});
typedef $$AlbumsTableUpdateCompanionBuilder = AlbumsCompanion Function({
  Value<String> id,
  Value<String> name,
  Value<int> messageId,
  Value<DateTime> createdAt,
  Value<DateTime> modifiedAt,
  Value<int> rowid,
});

class $$AlbumsTableFilterComposer
    extends Composer<_$AppDatabase, $AlbumsTable> {
  $$AlbumsTableFilterComposer({
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

  ColumnFilters<int> get messageId => $composableBuilder(
    column: $table.messageId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get modifiedAt => $composableBuilder(
    column: $table.modifiedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AlbumsTableOrderingComposer
    extends Composer<_$AppDatabase, $AlbumsTable> {
  $$AlbumsTableOrderingComposer({
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

  ColumnOrderings<int> get messageId => $composableBuilder(
    column: $table.messageId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get modifiedAt => $composableBuilder(
    column: $table.modifiedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AlbumsTableAnnotationComposer
    extends Composer<_$AppDatabase, $AlbumsTable> {
  $$AlbumsTableAnnotationComposer({
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

  GeneratedColumn<int> get messageId =>
      $composableBuilder(column: $table.messageId, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get modifiedAt => $composableBuilder(
    column: $table.modifiedAt,
    builder: (column) => column,
  );
}

class $$AlbumsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AlbumsTable,
          AlbumRow,
          $$AlbumsTableFilterComposer,
          $$AlbumsTableOrderingComposer,
          $$AlbumsTableAnnotationComposer,
          $$AlbumsTableCreateCompanionBuilder,
          $$AlbumsTableUpdateCompanionBuilder,
          (AlbumRow, BaseReferences<_$AppDatabase, $AlbumsTable, AlbumRow>),
          AlbumRow,
          PrefetchHooks Function()
        > {
  $$AlbumsTableTableManager(_$AppDatabase db, $AlbumsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AlbumsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AlbumsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AlbumsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> messageId = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> modifiedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AlbumsCompanion(
                id: id,
                name: name,
                messageId: messageId,
                createdAt: createdAt,
                modifiedAt: modifiedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                required int messageId,
                required DateTime createdAt,
                required DateTime modifiedAt,
                Value<int> rowid = const Value.absent(),
              }) => AlbumsCompanion.insert(
                id: id,
                name: name,
                messageId: messageId,
                createdAt: createdAt,
                modifiedAt: modifiedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$AlbumsTable, AlbumRow>(table),
                  BaseReferences<_$AppDatabase, $AlbumsTable, AlbumRow>(
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

typedef $$AlbumsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AlbumsTable,
      AlbumRow,
      $$AlbumsTableFilterComposer,
      $$AlbumsTableOrderingComposer,
      $$AlbumsTableAnnotationComposer,
      $$AlbumsTableCreateCompanionBuilder,
      $$AlbumsTableUpdateCompanionBuilder,
      (AlbumRow, BaseReferences<_$AppDatabase, $AlbumsTable, AlbumRow>),
      AlbumRow,
      PrefetchHooks Function()
    >;
typedef $$AlbumFilesTableCreateCompanionBuilder = AlbumFilesCompanion Function({
  required String albumId,
  required String fileId,
  Value<int> rowid,
});
typedef $$AlbumFilesTableUpdateCompanionBuilder = AlbumFilesCompanion Function({
  Value<String> albumId,
  Value<String> fileId,
  Value<int> rowid,
});

class $$AlbumFilesTableFilterComposer
    extends Composer<_$AppDatabase, $AlbumFilesTable> {
  $$AlbumFilesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get albumId => $composableBuilder(
    column: $table.albumId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fileId => $composableBuilder(
    column: $table.fileId,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AlbumFilesTableOrderingComposer
    extends Composer<_$AppDatabase, $AlbumFilesTable> {
  $$AlbumFilesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get albumId => $composableBuilder(
    column: $table.albumId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fileId => $composableBuilder(
    column: $table.fileId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AlbumFilesTableAnnotationComposer
    extends Composer<_$AppDatabase, $AlbumFilesTable> {
  $$AlbumFilesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get albumId =>
      $composableBuilder(column: $table.albumId, builder: (column) => column);

  GeneratedColumn<String> get fileId =>
      $composableBuilder(column: $table.fileId, builder: (column) => column);
}

class $$AlbumFilesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AlbumFilesTable,
          AlbumFileRow,
          $$AlbumFilesTableFilterComposer,
          $$AlbumFilesTableOrderingComposer,
          $$AlbumFilesTableAnnotationComposer,
          $$AlbumFilesTableCreateCompanionBuilder,
          $$AlbumFilesTableUpdateCompanionBuilder,
          (
            AlbumFileRow,
            BaseReferences<_$AppDatabase, $AlbumFilesTable, AlbumFileRow>,
          ),
          AlbumFileRow,
          PrefetchHooks Function()
        > {
  $$AlbumFilesTableTableManager(_$AppDatabase db, $AlbumFilesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AlbumFilesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AlbumFilesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AlbumFilesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> albumId = const Value.absent(),
                Value<String> fileId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AlbumFilesCompanion(
                albumId: albumId,
                fileId: fileId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String albumId,
                required String fileId,
                Value<int> rowid = const Value.absent(),
              }) => AlbumFilesCompanion.insert(
                albumId: albumId,
                fileId: fileId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$AlbumFilesTable, AlbumFileRow>(table),
                  BaseReferences<_$AppDatabase, $AlbumFilesTable, AlbumFileRow>(
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

typedef $$AlbumFilesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AlbumFilesTable,
      AlbumFileRow,
      $$AlbumFilesTableFilterComposer,
      $$AlbumFilesTableOrderingComposer,
      $$AlbumFilesTableAnnotationComposer,
      $$AlbumFilesTableCreateCompanionBuilder,
      $$AlbumFilesTableUpdateCompanionBuilder,
      (
        AlbumFileRow,
        BaseReferences<_$AppDatabase, $AlbumFilesTable, AlbumFileRow>,
      ),
      AlbumFileRow,
      PrefetchHooks Function()
    >;
typedef $$OfflinePinsTableCreateCompanionBuilder =
    OfflinePinsCompanion Function({
      required String itemId,
      required bool isFolder,
      required DateTime pinnedAt,
      Value<int> rowid,
    });
typedef $$OfflinePinsTableUpdateCompanionBuilder =
    OfflinePinsCompanion Function({
      Value<String> itemId,
      Value<bool> isFolder,
      Value<DateTime> pinnedAt,
      Value<int> rowid,
    });

class $$OfflinePinsTableFilterComposer
    extends Composer<_$AppDatabase, $OfflinePinsTable> {
  $$OfflinePinsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get itemId => $composableBuilder(
    column: $table.itemId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isFolder => $composableBuilder(
    column: $table.isFolder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get pinnedAt => $composableBuilder(
    column: $table.pinnedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$OfflinePinsTableOrderingComposer
    extends Composer<_$AppDatabase, $OfflinePinsTable> {
  $$OfflinePinsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get itemId => $composableBuilder(
    column: $table.itemId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isFolder => $composableBuilder(
    column: $table.isFolder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get pinnedAt => $composableBuilder(
    column: $table.pinnedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$OfflinePinsTableAnnotationComposer
    extends Composer<_$AppDatabase, $OfflinePinsTable> {
  $$OfflinePinsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get itemId =>
      $composableBuilder(column: $table.itemId, builder: (column) => column);

  GeneratedColumn<bool> get isFolder =>
      $composableBuilder(column: $table.isFolder, builder: (column) => column);

  GeneratedColumn<DateTime> get pinnedAt =>
      $composableBuilder(column: $table.pinnedAt, builder: (column) => column);
}

class $$OfflinePinsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $OfflinePinsTable,
          OfflinePinRow,
          $$OfflinePinsTableFilterComposer,
          $$OfflinePinsTableOrderingComposer,
          $$OfflinePinsTableAnnotationComposer,
          $$OfflinePinsTableCreateCompanionBuilder,
          $$OfflinePinsTableUpdateCompanionBuilder,
          (
            OfflinePinRow,
            BaseReferences<_$AppDatabase, $OfflinePinsTable, OfflinePinRow>,
          ),
          OfflinePinRow,
          PrefetchHooks Function()
        > {
  $$OfflinePinsTableTableManager(_$AppDatabase db, $OfflinePinsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OfflinePinsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$OfflinePinsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$OfflinePinsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> itemId = const Value.absent(),
                Value<bool> isFolder = const Value.absent(),
                Value<DateTime> pinnedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => OfflinePinsCompanion(
                itemId: itemId,
                isFolder: isFolder,
                pinnedAt: pinnedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String itemId,
                required bool isFolder,
                required DateTime pinnedAt,
                Value<int> rowid = const Value.absent(),
              }) => OfflinePinsCompanion.insert(
                itemId: itemId,
                isFolder: isFolder,
                pinnedAt: pinnedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$OfflinePinsTable, OfflinePinRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $OfflinePinsTable,
                    OfflinePinRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$OfflinePinsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $OfflinePinsTable,
      OfflinePinRow,
      $$OfflinePinsTableFilterComposer,
      $$OfflinePinsTableOrderingComposer,
      $$OfflinePinsTableAnnotationComposer,
      $$OfflinePinsTableCreateCompanionBuilder,
      $$OfflinePinsTableUpdateCompanionBuilder,
      (
        OfflinePinRow,
        BaseReferences<_$AppDatabase, $OfflinePinsTable, OfflinePinRow>,
      ),
      OfflinePinRow,
      PrefetchHooks Function()
    >;
typedef $$OfflineCopiesTableCreateCompanionBuilder =
    OfflineCopiesCompanion Function({
      required String fileId,
      required String path,
      required int size,
      Value<int> rowid,
    });
typedef $$OfflineCopiesTableUpdateCompanionBuilder =
    OfflineCopiesCompanion Function({
      Value<String> fileId,
      Value<String> path,
      Value<int> size,
      Value<int> rowid,
    });

class $$OfflineCopiesTableFilterComposer
    extends Composer<_$AppDatabase, $OfflineCopiesTable> {
  $$OfflineCopiesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get fileId => $composableBuilder(
    column: $table.fileId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get size => $composableBuilder(
    column: $table.size,
    builder: (column) => ColumnFilters(column),
  );
}

class $$OfflineCopiesTableOrderingComposer
    extends Composer<_$AppDatabase, $OfflineCopiesTable> {
  $$OfflineCopiesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get fileId => $composableBuilder(
    column: $table.fileId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get size => $composableBuilder(
    column: $table.size,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$OfflineCopiesTableAnnotationComposer
    extends Composer<_$AppDatabase, $OfflineCopiesTable> {
  $$OfflineCopiesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get fileId =>
      $composableBuilder(column: $table.fileId, builder: (column) => column);

  GeneratedColumn<String> get path =>
      $composableBuilder(column: $table.path, builder: (column) => column);

  GeneratedColumn<int> get size =>
      $composableBuilder(column: $table.size, builder: (column) => column);
}

class $$OfflineCopiesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $OfflineCopiesTable,
          OfflineCopyRow,
          $$OfflineCopiesTableFilterComposer,
          $$OfflineCopiesTableOrderingComposer,
          $$OfflineCopiesTableAnnotationComposer,
          $$OfflineCopiesTableCreateCompanionBuilder,
          $$OfflineCopiesTableUpdateCompanionBuilder,
          (
            OfflineCopyRow,
            BaseReferences<_$AppDatabase, $OfflineCopiesTable, OfflineCopyRow>,
          ),
          OfflineCopyRow,
          PrefetchHooks Function()
        > {
  $$OfflineCopiesTableTableManager(_$AppDatabase db, $OfflineCopiesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OfflineCopiesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$OfflineCopiesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$OfflineCopiesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> fileId = const Value.absent(),
                Value<String> path = const Value.absent(),
                Value<int> size = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => OfflineCopiesCompanion(
                fileId: fileId,
                path: path,
                size: size,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String fileId,
                required String path,
                required int size,
                Value<int> rowid = const Value.absent(),
              }) => OfflineCopiesCompanion.insert(
                fileId: fileId,
                path: path,
                size: size,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$OfflineCopiesTable, OfflineCopyRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $OfflineCopiesTable,
                    OfflineCopyRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$OfflineCopiesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $OfflineCopiesTable,
      OfflineCopyRow,
      $$OfflineCopiesTableFilterComposer,
      $$OfflineCopiesTableOrderingComposer,
      $$OfflineCopiesTableAnnotationComposer,
      $$OfflineCopiesTableCreateCompanionBuilder,
      $$OfflineCopiesTableUpdateCompanionBuilder,
      (
        OfflineCopyRow,
        BaseReferences<_$AppDatabase, $OfflineCopiesTable, OfflineCopyRow>,
      ),
      OfflineCopyRow,
      PrefetchHooks Function()
    >;
typedef $$FileContentsTableCreateCompanionBuilder =
    FileContentsCompanion Function({
      required String fileId,
      required String content,
      required int version,
      required DateTime indexedAt,
      Value<int> rowid,
    });
typedef $$FileContentsTableUpdateCompanionBuilder =
    FileContentsCompanion Function({
      Value<String> fileId,
      Value<String> content,
      Value<int> version,
      Value<DateTime> indexedAt,
      Value<int> rowid,
    });

class $$FileContentsTableFilterComposer
    extends Composer<_$AppDatabase, $FileContentsTable> {
  $$FileContentsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get fileId => $composableBuilder(
    column: $table.fileId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get indexedAt => $composableBuilder(
    column: $table.indexedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$FileContentsTableOrderingComposer
    extends Composer<_$AppDatabase, $FileContentsTable> {
  $$FileContentsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get fileId => $composableBuilder(
    column: $table.fileId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get indexedAt => $composableBuilder(
    column: $table.indexedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$FileContentsTableAnnotationComposer
    extends Composer<_$AppDatabase, $FileContentsTable> {
  $$FileContentsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get fileId =>
      $composableBuilder(column: $table.fileId, builder: (column) => column);

  GeneratedColumn<String> get content =>
      $composableBuilder(column: $table.content, builder: (column) => column);

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<DateTime> get indexedAt =>
      $composableBuilder(column: $table.indexedAt, builder: (column) => column);
}

class $$FileContentsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $FileContentsTable,
          FileContentRow,
          $$FileContentsTableFilterComposer,
          $$FileContentsTableOrderingComposer,
          $$FileContentsTableAnnotationComposer,
          $$FileContentsTableCreateCompanionBuilder,
          $$FileContentsTableUpdateCompanionBuilder,
          (
            FileContentRow,
            BaseReferences<_$AppDatabase, $FileContentsTable, FileContentRow>,
          ),
          FileContentRow,
          PrefetchHooks Function()
        > {
  $$FileContentsTableTableManager(_$AppDatabase db, $FileContentsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FileContentsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FileContentsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FileContentsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> fileId = const Value.absent(),
                Value<String> content = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<DateTime> indexedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FileContentsCompanion(
                fileId: fileId,
                content: content,
                version: version,
                indexedAt: indexedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String fileId,
                required String content,
                required int version,
                required DateTime indexedAt,
                Value<int> rowid = const Value.absent(),
              }) => FileContentsCompanion.insert(
                fileId: fileId,
                content: content,
                version: version,
                indexedAt: indexedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$FileContentsTable, FileContentRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $FileContentsTable,
                    FileContentRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$FileContentsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $FileContentsTable,
      FileContentRow,
      $$FileContentsTableFilterComposer,
      $$FileContentsTableOrderingComposer,
      $$FileContentsTableAnnotationComposer,
      $$FileContentsTableCreateCompanionBuilder,
      $$FileContentsTableUpdateCompanionBuilder,
      (
        FileContentRow,
        BaseReferences<_$AppDatabase, $FileContentsTable, FileContentRow>,
      ),
      FileContentRow,
      PrefetchHooks Function()
    >;
typedef $$FileOpensTableCreateCompanionBuilder = FileOpensCompanion Function({
  required String fileId,
  required DateTime openedAt,
  Value<int> rowid,
});
typedef $$FileOpensTableUpdateCompanionBuilder = FileOpensCompanion Function({
  Value<String> fileId,
  Value<DateTime> openedAt,
  Value<int> rowid,
});

class $$FileOpensTableFilterComposer
    extends Composer<_$AppDatabase, $FileOpensTable> {
  $$FileOpensTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get fileId => $composableBuilder(
    column: $table.fileId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get openedAt => $composableBuilder(
    column: $table.openedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$FileOpensTableOrderingComposer
    extends Composer<_$AppDatabase, $FileOpensTable> {
  $$FileOpensTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get fileId => $composableBuilder(
    column: $table.fileId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get openedAt => $composableBuilder(
    column: $table.openedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$FileOpensTableAnnotationComposer
    extends Composer<_$AppDatabase, $FileOpensTable> {
  $$FileOpensTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get fileId =>
      $composableBuilder(column: $table.fileId, builder: (column) => column);

  GeneratedColumn<DateTime> get openedAt =>
      $composableBuilder(column: $table.openedAt, builder: (column) => column);
}

class $$FileOpensTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $FileOpensTable,
          FileOpenRow,
          $$FileOpensTableFilterComposer,
          $$FileOpensTableOrderingComposer,
          $$FileOpensTableAnnotationComposer,
          $$FileOpensTableCreateCompanionBuilder,
          $$FileOpensTableUpdateCompanionBuilder,
          (
            FileOpenRow,
            BaseReferences<_$AppDatabase, $FileOpensTable, FileOpenRow>,
          ),
          FileOpenRow,
          PrefetchHooks Function()
        > {
  $$FileOpensTableTableManager(_$AppDatabase db, $FileOpensTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FileOpensTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FileOpensTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FileOpensTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> fileId = const Value.absent(),
                Value<DateTime> openedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FileOpensCompanion(
                fileId: fileId,
                openedAt: openedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String fileId,
                required DateTime openedAt,
                Value<int> rowid = const Value.absent(),
              }) => FileOpensCompanion.insert(
                fileId: fileId,
                openedAt: openedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$FileOpensTable, FileOpenRow>(table),
                  BaseReferences<_$AppDatabase, $FileOpensTable, FileOpenRow>(
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

typedef $$FileOpensTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $FileOpensTable,
      FileOpenRow,
      $$FileOpensTableFilterComposer,
      $$FileOpensTableOrderingComposer,
      $$FileOpensTableAnnotationComposer,
      $$FileOpensTableCreateCompanionBuilder,
      $$FileOpensTableUpdateCompanionBuilder,
      (
        FileOpenRow,
        BaseReferences<_$AppDatabase, $FileOpensTable, FileOpenRow>,
      ),
      FileOpenRow,
      PrefetchHooks Function()
    >;
typedef $$PlayPositionsTableCreateCompanionBuilder =
    PlayPositionsCompanion Function({
      required String fileId,
      required int positionMs,
      required int durationMs,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$PlayPositionsTableUpdateCompanionBuilder =
    PlayPositionsCompanion Function({
      Value<String> fileId,
      Value<int> positionMs,
      Value<int> durationMs,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$PlayPositionsTableFilterComposer
    extends Composer<_$AppDatabase, $PlayPositionsTable> {
  $$PlayPositionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get fileId => $composableBuilder(
    column: $table.fileId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get positionMs => $composableBuilder(
    column: $table.positionMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PlayPositionsTableOrderingComposer
    extends Composer<_$AppDatabase, $PlayPositionsTable> {
  $$PlayPositionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get fileId => $composableBuilder(
    column: $table.fileId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get positionMs => $composableBuilder(
    column: $table.positionMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PlayPositionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $PlayPositionsTable> {
  $$PlayPositionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get fileId =>
      $composableBuilder(column: $table.fileId, builder: (column) => column);

  GeneratedColumn<int> get positionMs => $composableBuilder(
    column: $table.positionMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$PlayPositionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PlayPositionsTable,
          PlayPositionRow,
          $$PlayPositionsTableFilterComposer,
          $$PlayPositionsTableOrderingComposer,
          $$PlayPositionsTableAnnotationComposer,
          $$PlayPositionsTableCreateCompanionBuilder,
          $$PlayPositionsTableUpdateCompanionBuilder,
          (
            PlayPositionRow,
            BaseReferences<_$AppDatabase, $PlayPositionsTable, PlayPositionRow>,
          ),
          PlayPositionRow,
          PrefetchHooks Function()
        > {
  $$PlayPositionsTableTableManager(_$AppDatabase db, $PlayPositionsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PlayPositionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PlayPositionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PlayPositionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> fileId = const Value.absent(),
                Value<int> positionMs = const Value.absent(),
                Value<int> durationMs = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PlayPositionsCompanion(
                fileId: fileId,
                positionMs: positionMs,
                durationMs: durationMs,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String fileId,
                required int positionMs,
                required int durationMs,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => PlayPositionsCompanion.insert(
                fileId: fileId,
                positionMs: positionMs,
                durationMs: durationMs,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$PlayPositionsTable, PlayPositionRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $PlayPositionsTable,
                    PlayPositionRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PlayPositionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PlayPositionsTable,
      PlayPositionRow,
      $$PlayPositionsTableFilterComposer,
      $$PlayPositionsTableOrderingComposer,
      $$PlayPositionsTableAnnotationComposer,
      $$PlayPositionsTableCreateCompanionBuilder,
      $$PlayPositionsTableUpdateCompanionBuilder,
      (
        PlayPositionRow,
        BaseReferences<_$AppDatabase, $PlayPositionsTable, PlayPositionRow>,
      ),
      PlayPositionRow,
      PrefetchHooks Function()
    >;
typedef $$WatchedFoldersTableCreateCompanionBuilder =
    WatchedFoldersCompanion Function({
      required String id,
      required String treeUri,
      required String label,
      Value<String?> destinationId,
      required WatchFilter filter,
      Value<bool> subfolders,
      required DateTime createdAt,
      Value<DateTime?> checkedAt,
      Value<int> rowid,
    });
typedef $$WatchedFoldersTableUpdateCompanionBuilder =
    WatchedFoldersCompanion Function({
      Value<String> id,
      Value<String> treeUri,
      Value<String> label,
      Value<String?> destinationId,
      Value<WatchFilter> filter,
      Value<bool> subfolders,
      Value<DateTime> createdAt,
      Value<DateTime?> checkedAt,
      Value<int> rowid,
    });

class $$WatchedFoldersTableFilterComposer
    extends Composer<_$AppDatabase, $WatchedFoldersTable> {
  $$WatchedFoldersTableFilterComposer({
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

  ColumnFilters<String> get treeUri => $composableBuilder(
    column: $table.treeUri,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get destinationId => $composableBuilder(
    column: $table.destinationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<WatchFilter, WatchFilter, String> get filter =>
      $composableBuilder(
        column: $table.filter,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<bool> get subfolders => $composableBuilder(
    column: $table.subfolders,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get checkedAt => $composableBuilder(
    column: $table.checkedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$WatchedFoldersTableOrderingComposer
    extends Composer<_$AppDatabase, $WatchedFoldersTable> {
  $$WatchedFoldersTableOrderingComposer({
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

  ColumnOrderings<String> get treeUri => $composableBuilder(
    column: $table.treeUri,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get destinationId => $composableBuilder(
    column: $table.destinationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get filter => $composableBuilder(
    column: $table.filter,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get subfolders => $composableBuilder(
    column: $table.subfolders,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get checkedAt => $composableBuilder(
    column: $table.checkedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$WatchedFoldersTableAnnotationComposer
    extends Composer<_$AppDatabase, $WatchedFoldersTable> {
  $$WatchedFoldersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get treeUri =>
      $composableBuilder(column: $table.treeUri, builder: (column) => column);

  GeneratedColumn<String> get label =>
      $composableBuilder(column: $table.label, builder: (column) => column);

  GeneratedColumn<String> get destinationId => $composableBuilder(
    column: $table.destinationId,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<WatchFilter, String> get filter =>
      $composableBuilder(column: $table.filter, builder: (column) => column);

  GeneratedColumn<bool> get subfolders => $composableBuilder(
    column: $table.subfolders,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get checkedAt =>
      $composableBuilder(column: $table.checkedAt, builder: (column) => column);
}

class $$WatchedFoldersTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $WatchedFoldersTable,
          WatchedFolderRow,
          $$WatchedFoldersTableFilterComposer,
          $$WatchedFoldersTableOrderingComposer,
          $$WatchedFoldersTableAnnotationComposer,
          $$WatchedFoldersTableCreateCompanionBuilder,
          $$WatchedFoldersTableUpdateCompanionBuilder,
          (
            WatchedFolderRow,
            BaseReferences<
              _$AppDatabase,
              $WatchedFoldersTable,
              WatchedFolderRow
            >,
          ),
          WatchedFolderRow,
          PrefetchHooks Function()
        > {
  $$WatchedFoldersTableTableManager(
    _$AppDatabase db,
    $WatchedFoldersTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$WatchedFoldersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$WatchedFoldersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$WatchedFoldersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> treeUri = const Value.absent(),
                Value<String> label = const Value.absent(),
                Value<String?> destinationId = const Value.absent(),
                Value<WatchFilter> filter = const Value.absent(),
                Value<bool> subfolders = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime?> checkedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => WatchedFoldersCompanion(
                id: id,
                treeUri: treeUri,
                label: label,
                destinationId: destinationId,
                filter: filter,
                subfolders: subfolders,
                createdAt: createdAt,
                checkedAt: checkedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String treeUri,
                required String label,
                Value<String?> destinationId = const Value.absent(),
                required WatchFilter filter,
                Value<bool> subfolders = const Value.absent(),
                required DateTime createdAt,
                Value<DateTime?> checkedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => WatchedFoldersCompanion.insert(
                id: id,
                treeUri: treeUri,
                label: label,
                destinationId: destinationId,
                filter: filter,
                subfolders: subfolders,
                createdAt: createdAt,
                checkedAt: checkedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$WatchedFoldersTable, WatchedFolderRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $WatchedFoldersTable,
                    WatchedFolderRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$WatchedFoldersTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $WatchedFoldersTable,
      WatchedFolderRow,
      $$WatchedFoldersTableFilterComposer,
      $$WatchedFoldersTableOrderingComposer,
      $$WatchedFoldersTableAnnotationComposer,
      $$WatchedFoldersTableCreateCompanionBuilder,
      $$WatchedFoldersTableUpdateCompanionBuilder,
      (
        WatchedFolderRow,
        BaseReferences<_$AppDatabase, $WatchedFoldersTable, WatchedFolderRow>,
      ),
      WatchedFolderRow,
      PrefetchHooks Function()
    >;
typedef $$WatchedFilesTableCreateCompanionBuilder =
    WatchedFilesCompanion Function({
      required String ruleId,
      required String documentId,
      required int size,
      required DateTime modifiedAt,
      required WatchedFileState state,
      Value<String?> fileId,
      Value<String?> transferId,
      Value<int> failures,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$WatchedFilesTableUpdateCompanionBuilder =
    WatchedFilesCompanion Function({
      Value<String> ruleId,
      Value<String> documentId,
      Value<int> size,
      Value<DateTime> modifiedAt,
      Value<WatchedFileState> state,
      Value<String?> fileId,
      Value<String?> transferId,
      Value<int> failures,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$WatchedFilesTableFilterComposer
    extends Composer<_$AppDatabase, $WatchedFilesTable> {
  $$WatchedFilesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get ruleId => $composableBuilder(
    column: $table.ruleId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get documentId => $composableBuilder(
    column: $table.documentId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get size => $composableBuilder(
    column: $table.size,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get modifiedAt => $composableBuilder(
    column: $table.modifiedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<WatchedFileState, WatchedFileState, String>
  get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<String> get fileId => $composableBuilder(
    column: $table.fileId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get transferId => $composableBuilder(
    column: $table.transferId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get failures => $composableBuilder(
    column: $table.failures,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$WatchedFilesTableOrderingComposer
    extends Composer<_$AppDatabase, $WatchedFilesTable> {
  $$WatchedFilesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get ruleId => $composableBuilder(
    column: $table.ruleId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get documentId => $composableBuilder(
    column: $table.documentId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get size => $composableBuilder(
    column: $table.size,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get modifiedAt => $composableBuilder(
    column: $table.modifiedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fileId => $composableBuilder(
    column: $table.fileId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get transferId => $composableBuilder(
    column: $table.transferId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get failures => $composableBuilder(
    column: $table.failures,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$WatchedFilesTableAnnotationComposer
    extends Composer<_$AppDatabase, $WatchedFilesTable> {
  $$WatchedFilesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get ruleId =>
      $composableBuilder(column: $table.ruleId, builder: (column) => column);

  GeneratedColumn<String> get documentId => $composableBuilder(
    column: $table.documentId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get size =>
      $composableBuilder(column: $table.size, builder: (column) => column);

  GeneratedColumn<DateTime> get modifiedAt => $composableBuilder(
    column: $table.modifiedAt,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<WatchedFileState, String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<String> get fileId =>
      $composableBuilder(column: $table.fileId, builder: (column) => column);

  GeneratedColumn<String> get transferId => $composableBuilder(
    column: $table.transferId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get failures =>
      $composableBuilder(column: $table.failures, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$WatchedFilesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $WatchedFilesTable,
          WatchedFileRow,
          $$WatchedFilesTableFilterComposer,
          $$WatchedFilesTableOrderingComposer,
          $$WatchedFilesTableAnnotationComposer,
          $$WatchedFilesTableCreateCompanionBuilder,
          $$WatchedFilesTableUpdateCompanionBuilder,
          (
            WatchedFileRow,
            BaseReferences<_$AppDatabase, $WatchedFilesTable, WatchedFileRow>,
          ),
          WatchedFileRow,
          PrefetchHooks Function()
        > {
  $$WatchedFilesTableTableManager(_$AppDatabase db, $WatchedFilesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$WatchedFilesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$WatchedFilesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$WatchedFilesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> ruleId = const Value.absent(),
                Value<String> documentId = const Value.absent(),
                Value<int> size = const Value.absent(),
                Value<DateTime> modifiedAt = const Value.absent(),
                Value<WatchedFileState> state = const Value.absent(),
                Value<String?> fileId = const Value.absent(),
                Value<String?> transferId = const Value.absent(),
                Value<int> failures = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => WatchedFilesCompanion(
                ruleId: ruleId,
                documentId: documentId,
                size: size,
                modifiedAt: modifiedAt,
                state: state,
                fileId: fileId,
                transferId: transferId,
                failures: failures,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String ruleId,
                required String documentId,
                required int size,
                required DateTime modifiedAt,
                required WatchedFileState state,
                Value<String?> fileId = const Value.absent(),
                Value<String?> transferId = const Value.absent(),
                Value<int> failures = const Value.absent(),
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => WatchedFilesCompanion.insert(
                ruleId: ruleId,
                documentId: documentId,
                size: size,
                modifiedAt: modifiedAt,
                state: state,
                fileId: fileId,
                transferId: transferId,
                failures: failures,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$WatchedFilesTable, WatchedFileRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $WatchedFilesTable,
                    WatchedFileRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$WatchedFilesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $WatchedFilesTable,
      WatchedFileRow,
      $$WatchedFilesTableFilterComposer,
      $$WatchedFilesTableOrderingComposer,
      $$WatchedFilesTableAnnotationComposer,
      $$WatchedFilesTableCreateCompanionBuilder,
      $$WatchedFilesTableUpdateCompanionBuilder,
      (
        WatchedFileRow,
        BaseReferences<_$AppDatabase, $WatchedFilesTable, WatchedFileRow>,
      ),
      WatchedFileRow,
      PrefetchHooks Function()
    >;
typedef $$PendingEditsTableCreateCompanionBuilder =
    PendingEditsCompanion Function({
      required EditTarget target,
      required String itemId,
      required String patch,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<int> attempts,
      Value<String?> lastError,
      Value<int> rowid,
    });
typedef $$PendingEditsTableUpdateCompanionBuilder =
    PendingEditsCompanion Function({
      Value<EditTarget> target,
      Value<String> itemId,
      Value<String> patch,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> attempts,
      Value<String?> lastError,
      Value<int> rowid,
    });

class $$PendingEditsTableFilterComposer
    extends Composer<_$AppDatabase, $PendingEditsTable> {
  $$PendingEditsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnWithTypeConverterFilters<EditTarget, EditTarget, String> get target =>
      $composableBuilder(
        column: $table.target,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<String> get itemId => $composableBuilder(
    column: $table.itemId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get patch => $composableBuilder(
    column: $table.patch,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
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
}

class $$PendingEditsTableOrderingComposer
    extends Composer<_$AppDatabase, $PendingEditsTable> {
  $$PendingEditsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get target => $composableBuilder(
    column: $table.target,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get itemId => $composableBuilder(
    column: $table.itemId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get patch => $composableBuilder(
    column: $table.patch,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
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
}

class $$PendingEditsTableAnnotationComposer
    extends Composer<_$AppDatabase, $PendingEditsTable> {
  $$PendingEditsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumnWithTypeConverter<EditTarget, String> get target =>
      $composableBuilder(column: $table.target, builder: (column) => column);

  GeneratedColumn<String> get itemId =>
      $composableBuilder(column: $table.itemId, builder: (column) => column);

  GeneratedColumn<String> get patch =>
      $composableBuilder(column: $table.patch, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<int> get attempts =>
      $composableBuilder(column: $table.attempts, builder: (column) => column);

  GeneratedColumn<String> get lastError =>
      $composableBuilder(column: $table.lastError, builder: (column) => column);
}

class $$PendingEditsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PendingEditsTable,
          PendingEditRow,
          $$PendingEditsTableFilterComposer,
          $$PendingEditsTableOrderingComposer,
          $$PendingEditsTableAnnotationComposer,
          $$PendingEditsTableCreateCompanionBuilder,
          $$PendingEditsTableUpdateCompanionBuilder,
          (
            PendingEditRow,
            BaseReferences<_$AppDatabase, $PendingEditsTable, PendingEditRow>,
          ),
          PendingEditRow,
          PrefetchHooks Function()
        > {
  $$PendingEditsTableTableManager(_$AppDatabase db, $PendingEditsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PendingEditsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PendingEditsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PendingEditsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<EditTarget> target = const Value.absent(),
                Value<String> itemId = const Value.absent(),
                Value<String> patch = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> attempts = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PendingEditsCompanion(
                target: target,
                itemId: itemId,
                patch: patch,
                createdAt: createdAt,
                updatedAt: updatedAt,
                attempts: attempts,
                lastError: lastError,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required EditTarget target,
                required String itemId,
                required String patch,
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<int> attempts = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PendingEditsCompanion.insert(
                target: target,
                itemId: itemId,
                patch: patch,
                createdAt: createdAt,
                updatedAt: updatedAt,
                attempts: attempts,
                lastError: lastError,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$PendingEditsTable, PendingEditRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $PendingEditsTable,
                    PendingEditRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PendingEditsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PendingEditsTable,
      PendingEditRow,
      $$PendingEditsTableFilterComposer,
      $$PendingEditsTableOrderingComposer,
      $$PendingEditsTableAnnotationComposer,
      $$PendingEditsTableCreateCompanionBuilder,
      $$PendingEditsTableUpdateCompanionBuilder,
      (
        PendingEditRow,
        BaseReferences<_$AppDatabase, $PendingEditsTable, PendingEditRow>,
      ),
      PendingEditRow,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$FoldersTableTableManager get folders =>
      $$FoldersTableTableManager(_db, _db.folders);
  $$DriveFilesTableTableManager get driveFiles =>
      $$DriveFilesTableTableManager(_db, _db.driveFiles);
  $$FilePartsTableTableManager get fileParts =>
      $$FilePartsTableTableManager(_db, _db.fileParts);
  $$TransfersTableTableManager get transfers =>
      $$TransfersTableTableManager(_db, _db.transfers);
  $$BackupAssetsTableTableManager get backupAssets =>
      $$BackupAssetsTableTableManager(_db, _db.backupAssets);
  $$AlbumsTableTableManager get albums =>
      $$AlbumsTableTableManager(_db, _db.albums);
  $$AlbumFilesTableTableManager get albumFiles =>
      $$AlbumFilesTableTableManager(_db, _db.albumFiles);
  $$OfflinePinsTableTableManager get offlinePins =>
      $$OfflinePinsTableTableManager(_db, _db.offlinePins);
  $$OfflineCopiesTableTableManager get offlineCopies =>
      $$OfflineCopiesTableTableManager(_db, _db.offlineCopies);
  $$FileContentsTableTableManager get fileContents =>
      $$FileContentsTableTableManager(_db, _db.fileContents);
  $$FileOpensTableTableManager get fileOpens =>
      $$FileOpensTableTableManager(_db, _db.fileOpens);
  $$PlayPositionsTableTableManager get playPositions =>
      $$PlayPositionsTableTableManager(_db, _db.playPositions);
  $$WatchedFoldersTableTableManager get watchedFolders =>
      $$WatchedFoldersTableTableManager(_db, _db.watchedFolders);
  $$WatchedFilesTableTableManager get watchedFiles =>
      $$WatchedFilesTableTableManager(_db, _db.watchedFiles);
  $$PendingEditsTableTableManager get pendingEdits =>
      $$PendingEditsTableTableManager(_db, _db.pendingEdits);
}
