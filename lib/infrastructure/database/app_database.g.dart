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
  @override
  List<GeneratedColumn> get $columns => [
    id,
    parentId,
    name,
    messageId,
    createdAt,
    modifiedAt,
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
  const FolderRow({
    required this.id,
    this.parentId,
    required this.name,
    required this.messageId,
    required this.createdAt,
    required this.modifiedAt,
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
    };
  }

  FolderRow copyWith({
    String? id,
    Value<String?> parentId = const Value.absent(),
    String? name,
    int? messageId,
    DateTime? createdAt,
    DateTime? modifiedAt,
  }) => FolderRow(
    id: id ?? this.id,
    parentId: parentId.present ? parentId.value : this.parentId,
    name: name ?? this.name,
    messageId: messageId ?? this.messageId,
    createdAt: createdAt ?? this.createdAt,
    modifiedAt: modifiedAt ?? this.modifiedAt,
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
          ..write('modifiedAt: $modifiedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, parentId, name, messageId, createdAt, modifiedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FolderRow &&
          other.id == this.id &&
          other.parentId == this.parentId &&
          other.name == this.name &&
          other.messageId == this.messageId &&
          other.createdAt == this.createdAt &&
          other.modifiedAt == this.modifiedAt);
}

class FoldersCompanion extends UpdateCompanion<FolderRow> {
  final Value<String> id;
  final Value<String?> parentId;
  final Value<String> name;
  final Value<int> messageId;
  final Value<DateTime> createdAt;
  final Value<DateTime> modifiedAt;
  final Value<int> rowid;
  const FoldersCompanion({
    this.id = const Value.absent(),
    this.parentId = const Value.absent(),
    this.name = const Value.absent(),
    this.messageId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.modifiedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FoldersCompanion.insert({
    required String id,
    this.parentId = const Value.absent(),
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
  static Insertable<FolderRow> custom({
    Expression<String>? id,
    Expression<String>? parentId,
    Expression<String>? name,
    Expression<int>? messageId,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? modifiedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (parentId != null) 'parent_id': parentId,
      if (name != null) 'name': name,
      if (messageId != null) 'message_id': messageId,
      if (createdAt != null) 'created_at': createdAt,
      if (modifiedAt != null) 'modified_at': modifiedAt,
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
    Value<int>? rowid,
  }) {
    return FoldersCompanion(
      id: id ?? this.id,
      parentId: parentId ?? this.parentId,
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
          ..write('takenAt: $takenAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
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
  );
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
          other.takenAt == this.takenAt);
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

  /// TDLib's id for the document. Stable for as long as TDLib's database is.
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

  /// Capture time carried into the manifest (backup uploads).
  final DateTime? takenAt;

  /// Small JPEG sent as the document's thumbnail, so videos get previews.
  final String? thumbnailPath;
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
          ..write('thumbnailPath: $thumbnailPath')
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
          other.thumbnailPath == this.thumbnailPath);
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
  @override
  List<GeneratedColumn> get $columns => [
    assetId,
    state,
    fileId,
    failures,
    updatedAt,
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
  const BackupAssetRow({
    required this.assetId,
    required this.state,
    this.fileId,
    required this.failures,
    required this.updatedAt,
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
    };
  }

  BackupAssetRow copyWith({
    String? assetId,
    BackupAssetState? state,
    Value<String?> fileId = const Value.absent(),
    int? failures,
    DateTime? updatedAt,
  }) => BackupAssetRow(
    assetId: assetId ?? this.assetId,
    state: state ?? this.state,
    fileId: fileId.present ? fileId.value : this.fileId,
    failures: failures ?? this.failures,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  BackupAssetRow copyWithCompanion(BackupAssetsCompanion data) {
    return BackupAssetRow(
      assetId: data.assetId.present ? data.assetId.value : this.assetId,
      state: data.state.present ? data.state.value : this.state,
      fileId: data.fileId.present ? data.fileId.value : this.fileId,
      failures: data.failures.present ? data.failures.value : this.failures,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('BackupAssetRow(')
          ..write('assetId: $assetId, ')
          ..write('state: $state, ')
          ..write('fileId: $fileId, ')
          ..write('failures: $failures, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(assetId, state, fileId, failures, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BackupAssetRow &&
          other.assetId == this.assetId &&
          other.state == this.state &&
          other.fileId == this.fileId &&
          other.failures == this.failures &&
          other.updatedAt == this.updatedAt);
}

class BackupAssetsCompanion extends UpdateCompanion<BackupAssetRow> {
  final Value<String> assetId;
  final Value<BackupAssetState> state;
  final Value<String?> fileId;
  final Value<int> failures;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const BackupAssetsCompanion({
    this.assetId = const Value.absent(),
    this.state = const Value.absent(),
    this.fileId = const Value.absent(),
    this.failures = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  BackupAssetsCompanion.insert({
    required String assetId,
    required BackupAssetState state,
    this.fileId = const Value.absent(),
    this.failures = const Value.absent(),
    required DateTime updatedAt,
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
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (assetId != null) 'asset_id': assetId,
      if (state != null) 'state': state,
      if (fileId != null) 'file_id': fileId,
      if (failures != null) 'failures': failures,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  BackupAssetsCompanion copyWith({
    Value<String>? assetId,
    Value<BackupAssetState>? state,
    Value<String?>? fileId,
    Value<int>? failures,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return BackupAssetsCompanion(
      assetId: assetId ?? this.assetId,
      state: state ?? this.state,
      fileId: fileId ?? this.fileId,
      failures: failures ?? this.failures,
      updatedAt: updatedAt ?? this.updatedAt,
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
  ];
}

typedef $$FoldersTableCreateCompanionBuilder = FoldersCompanion Function({
  required String id,
  Value<String?> parentId,
  required String name,
  required int messageId,
  required DateTime createdAt,
  required DateTime modifiedAt,
  Value<int> rowid,
});
typedef $$FoldersTableUpdateCompanionBuilder = FoldersCompanion Function({
  Value<String> id,
  Value<String?> parentId,
  Value<String> name,
  Value<int> messageId,
  Value<DateTime> createdAt,
  Value<DateTime> modifiedAt,
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
                Value<int> rowid = const Value.absent(),
              }) => FoldersCompanion(
                id: id,
                parentId: parentId,
                name: name,
                messageId: messageId,
                createdAt: createdAt,
                modifiedAt: modifiedAt,
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
                Value<int> rowid = const Value.absent(),
              }) => FoldersCompanion.insert(
                id: id,
                parentId: parentId,
                name: name,
                messageId: messageId,
                createdAt: createdAt,
                modifiedAt: modifiedAt,
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
      Value<int> rowid,
    });
typedef $$BackupAssetsTableUpdateCompanionBuilder =
    BackupAssetsCompanion Function({
      Value<String> assetId,
      Value<BackupAssetState> state,
      Value<String?> fileId,
      Value<int> failures,
      Value<DateTime> updatedAt,
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
                Value<int> rowid = const Value.absent(),
              }) => BackupAssetsCompanion(
                assetId: assetId,
                state: state,
                fileId: fileId,
                failures: failures,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String assetId,
                required BackupAssetState state,
                Value<String?> fileId = const Value.absent(),
                Value<int> failures = const Value.absent(),
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => BackupAssetsCompanion.insert(
                assetId: assetId,
                state: state,
                fileId: fileId,
                failures: failures,
                updatedAt: updatedAt,
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
}
