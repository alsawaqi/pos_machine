// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $BranchCacheTable extends BranchCache
    with TableInfo<$BranchCacheTable, BranchRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BranchCacheTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _nameArMeta = const VerificationMeta('nameAr');
  @override
  late final GeneratedColumn<String> nameAr = GeneratedColumn<String>(
    'name_ar',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _latitudeMeta = const VerificationMeta(
    'latitude',
  );
  @override
  late final GeneratedColumn<double> latitude = GeneratedColumn<double>(
    'latitude',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _longitudeMeta = const VerificationMeta(
    'longitude',
  );
  @override
  late final GeneratedColumn<double> longitude = GeneratedColumn<double>(
    'longitude',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _geofenceRadiusMMeta = const VerificationMeta(
    'geofenceRadiusM',
  );
  @override
  late final GeneratedColumn<int> geofenceRadiusM = GeneratedColumn<int>(
    'geofence_radius_m',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _defaultOrderTypeMeta = const VerificationMeta(
    'defaultOrderType',
  );
  @override
  late final GeneratedColumn<String> defaultOrderType = GeneratedColumn<String>(
    'default_order_type',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _receiptTemplateJsonMeta =
      const VerificationMeta('receiptTemplateJson');
  @override
  late final GeneratedColumn<String> receiptTemplateJson =
      GeneratedColumn<String>(
        'receipt_template_json',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    nameAr,
    latitude,
    longitude,
    geofenceRadiusM,
    defaultOrderType,
    status,
    receiptTemplateJson,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'branch_cache';
  @override
  VerificationContext validateIntegrity(
    Insertable<BranchRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    }
    if (data.containsKey('name_ar')) {
      context.handle(
        _nameArMeta,
        nameAr.isAcceptableOrUnknown(data['name_ar']!, _nameArMeta),
      );
    }
    if (data.containsKey('latitude')) {
      context.handle(
        _latitudeMeta,
        latitude.isAcceptableOrUnknown(data['latitude']!, _latitudeMeta),
      );
    }
    if (data.containsKey('longitude')) {
      context.handle(
        _longitudeMeta,
        longitude.isAcceptableOrUnknown(data['longitude']!, _longitudeMeta),
      );
    }
    if (data.containsKey('geofence_radius_m')) {
      context.handle(
        _geofenceRadiusMMeta,
        geofenceRadiusM.isAcceptableOrUnknown(
          data['geofence_radius_m']!,
          _geofenceRadiusMMeta,
        ),
      );
    }
    if (data.containsKey('default_order_type')) {
      context.handle(
        _defaultOrderTypeMeta,
        defaultOrderType.isAcceptableOrUnknown(
          data['default_order_type']!,
          _defaultOrderTypeMeta,
        ),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('receipt_template_json')) {
      context.handle(
        _receiptTemplateJsonMeta,
        receiptTemplateJson.isAcceptableOrUnknown(
          data['receipt_template_json']!,
          _receiptTemplateJsonMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  BranchRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return BranchRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      nameAr: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name_ar'],
      ),
      latitude: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}latitude'],
      ),
      longitude: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}longitude'],
      ),
      geofenceRadiusM: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}geofence_radius_m'],
      ),
      defaultOrderType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}default_order_type'],
      ),
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      ),
      receiptTemplateJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}receipt_template_json'],
      ),
    );
  }

  @override
  $BranchCacheTable createAlias(String alias) {
    return $BranchCacheTable(attachedDatabase, alias);
  }
}

class BranchRow extends DataClass implements Insertable<BranchRow> {
  final int id;
  final String name;
  final String? nameAr;
  final double? latitude;
  final double? longitude;
  final int? geofenceRadiusM;
  final String? defaultOrderType;
  final String? status;
  final String? receiptTemplateJson;
  const BranchRow({
    required this.id,
    required this.name,
    this.nameAr,
    this.latitude,
    this.longitude,
    this.geofenceRadiusM,
    this.defaultOrderType,
    this.status,
    this.receiptTemplateJson,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || nameAr != null) {
      map['name_ar'] = Variable<String>(nameAr);
    }
    if (!nullToAbsent || latitude != null) {
      map['latitude'] = Variable<double>(latitude);
    }
    if (!nullToAbsent || longitude != null) {
      map['longitude'] = Variable<double>(longitude);
    }
    if (!nullToAbsent || geofenceRadiusM != null) {
      map['geofence_radius_m'] = Variable<int>(geofenceRadiusM);
    }
    if (!nullToAbsent || defaultOrderType != null) {
      map['default_order_type'] = Variable<String>(defaultOrderType);
    }
    if (!nullToAbsent || status != null) {
      map['status'] = Variable<String>(status);
    }
    if (!nullToAbsent || receiptTemplateJson != null) {
      map['receipt_template_json'] = Variable<String>(receiptTemplateJson);
    }
    return map;
  }

  BranchCacheCompanion toCompanion(bool nullToAbsent) {
    return BranchCacheCompanion(
      id: Value(id),
      name: Value(name),
      nameAr: nameAr == null && nullToAbsent
          ? const Value.absent()
          : Value(nameAr),
      latitude: latitude == null && nullToAbsent
          ? const Value.absent()
          : Value(latitude),
      longitude: longitude == null && nullToAbsent
          ? const Value.absent()
          : Value(longitude),
      geofenceRadiusM: geofenceRadiusM == null && nullToAbsent
          ? const Value.absent()
          : Value(geofenceRadiusM),
      defaultOrderType: defaultOrderType == null && nullToAbsent
          ? const Value.absent()
          : Value(defaultOrderType),
      status: status == null && nullToAbsent
          ? const Value.absent()
          : Value(status),
      receiptTemplateJson: receiptTemplateJson == null && nullToAbsent
          ? const Value.absent()
          : Value(receiptTemplateJson),
    );
  }

  factory BranchRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return BranchRow(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      nameAr: serializer.fromJson<String?>(json['nameAr']),
      latitude: serializer.fromJson<double?>(json['latitude']),
      longitude: serializer.fromJson<double?>(json['longitude']),
      geofenceRadiusM: serializer.fromJson<int?>(json['geofenceRadiusM']),
      defaultOrderType: serializer.fromJson<String?>(json['defaultOrderType']),
      status: serializer.fromJson<String?>(json['status']),
      receiptTemplateJson: serializer.fromJson<String?>(
        json['receiptTemplateJson'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'nameAr': serializer.toJson<String?>(nameAr),
      'latitude': serializer.toJson<double?>(latitude),
      'longitude': serializer.toJson<double?>(longitude),
      'geofenceRadiusM': serializer.toJson<int?>(geofenceRadiusM),
      'defaultOrderType': serializer.toJson<String?>(defaultOrderType),
      'status': serializer.toJson<String?>(status),
      'receiptTemplateJson': serializer.toJson<String?>(receiptTemplateJson),
    };
  }

  BranchRow copyWith({
    int? id,
    String? name,
    Value<String?> nameAr = const Value.absent(),
    Value<double?> latitude = const Value.absent(),
    Value<double?> longitude = const Value.absent(),
    Value<int?> geofenceRadiusM = const Value.absent(),
    Value<String?> defaultOrderType = const Value.absent(),
    Value<String?> status = const Value.absent(),
    Value<String?> receiptTemplateJson = const Value.absent(),
  }) => BranchRow(
    id: id ?? this.id,
    name: name ?? this.name,
    nameAr: nameAr.present ? nameAr.value : this.nameAr,
    latitude: latitude.present ? latitude.value : this.latitude,
    longitude: longitude.present ? longitude.value : this.longitude,
    geofenceRadiusM: geofenceRadiusM.present
        ? geofenceRadiusM.value
        : this.geofenceRadiusM,
    defaultOrderType: defaultOrderType.present
        ? defaultOrderType.value
        : this.defaultOrderType,
    status: status.present ? status.value : this.status,
    receiptTemplateJson: receiptTemplateJson.present
        ? receiptTemplateJson.value
        : this.receiptTemplateJson,
  );
  BranchRow copyWithCompanion(BranchCacheCompanion data) {
    return BranchRow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      nameAr: data.nameAr.present ? data.nameAr.value : this.nameAr,
      latitude: data.latitude.present ? data.latitude.value : this.latitude,
      longitude: data.longitude.present ? data.longitude.value : this.longitude,
      geofenceRadiusM: data.geofenceRadiusM.present
          ? data.geofenceRadiusM.value
          : this.geofenceRadiusM,
      defaultOrderType: data.defaultOrderType.present
          ? data.defaultOrderType.value
          : this.defaultOrderType,
      status: data.status.present ? data.status.value : this.status,
      receiptTemplateJson: data.receiptTemplateJson.present
          ? data.receiptTemplateJson.value
          : this.receiptTemplateJson,
    );
  }

  @override
  String toString() {
    return (StringBuffer('BranchRow(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('nameAr: $nameAr, ')
          ..write('latitude: $latitude, ')
          ..write('longitude: $longitude, ')
          ..write('geofenceRadiusM: $geofenceRadiusM, ')
          ..write('defaultOrderType: $defaultOrderType, ')
          ..write('status: $status, ')
          ..write('receiptTemplateJson: $receiptTemplateJson')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    nameAr,
    latitude,
    longitude,
    geofenceRadiusM,
    defaultOrderType,
    status,
    receiptTemplateJson,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BranchRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.nameAr == this.nameAr &&
          other.latitude == this.latitude &&
          other.longitude == this.longitude &&
          other.geofenceRadiusM == this.geofenceRadiusM &&
          other.defaultOrderType == this.defaultOrderType &&
          other.status == this.status &&
          other.receiptTemplateJson == this.receiptTemplateJson);
}

class BranchCacheCompanion extends UpdateCompanion<BranchRow> {
  final Value<int> id;
  final Value<String> name;
  final Value<String?> nameAr;
  final Value<double?> latitude;
  final Value<double?> longitude;
  final Value<int?> geofenceRadiusM;
  final Value<String?> defaultOrderType;
  final Value<String?> status;
  final Value<String?> receiptTemplateJson;
  const BranchCacheCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.nameAr = const Value.absent(),
    this.latitude = const Value.absent(),
    this.longitude = const Value.absent(),
    this.geofenceRadiusM = const Value.absent(),
    this.defaultOrderType = const Value.absent(),
    this.status = const Value.absent(),
    this.receiptTemplateJson = const Value.absent(),
  });
  BranchCacheCompanion.insert({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.nameAr = const Value.absent(),
    this.latitude = const Value.absent(),
    this.longitude = const Value.absent(),
    this.geofenceRadiusM = const Value.absent(),
    this.defaultOrderType = const Value.absent(),
    this.status = const Value.absent(),
    this.receiptTemplateJson = const Value.absent(),
  });
  static Insertable<BranchRow> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<String>? nameAr,
    Expression<double>? latitude,
    Expression<double>? longitude,
    Expression<int>? geofenceRadiusM,
    Expression<String>? defaultOrderType,
    Expression<String>? status,
    Expression<String>? receiptTemplateJson,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (nameAr != null) 'name_ar': nameAr,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (geofenceRadiusM != null) 'geofence_radius_m': geofenceRadiusM,
      if (defaultOrderType != null) 'default_order_type': defaultOrderType,
      if (status != null) 'status': status,
      if (receiptTemplateJson != null)
        'receipt_template_json': receiptTemplateJson,
    });
  }

  BranchCacheCompanion copyWith({
    Value<int>? id,
    Value<String>? name,
    Value<String?>? nameAr,
    Value<double?>? latitude,
    Value<double?>? longitude,
    Value<int?>? geofenceRadiusM,
    Value<String?>? defaultOrderType,
    Value<String?>? status,
    Value<String?>? receiptTemplateJson,
  }) {
    return BranchCacheCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      nameAr: nameAr ?? this.nameAr,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      geofenceRadiusM: geofenceRadiusM ?? this.geofenceRadiusM,
      defaultOrderType: defaultOrderType ?? this.defaultOrderType,
      status: status ?? this.status,
      receiptTemplateJson: receiptTemplateJson ?? this.receiptTemplateJson,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (nameAr.present) {
      map['name_ar'] = Variable<String>(nameAr.value);
    }
    if (latitude.present) {
      map['latitude'] = Variable<double>(latitude.value);
    }
    if (longitude.present) {
      map['longitude'] = Variable<double>(longitude.value);
    }
    if (geofenceRadiusM.present) {
      map['geofence_radius_m'] = Variable<int>(geofenceRadiusM.value);
    }
    if (defaultOrderType.present) {
      map['default_order_type'] = Variable<String>(defaultOrderType.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (receiptTemplateJson.present) {
      map['receipt_template_json'] = Variable<String>(
        receiptTemplateJson.value,
      );
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BranchCacheCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('nameAr: $nameAr, ')
          ..write('latitude: $latitude, ')
          ..write('longitude: $longitude, ')
          ..write('geofenceRadiusM: $geofenceRadiusM, ')
          ..write('defaultOrderType: $defaultOrderType, ')
          ..write('status: $status, ')
          ..write('receiptTemplateJson: $receiptTemplateJson')
          ..write(')'))
        .toString();
  }
}

class $CategoriesTable extends Categories
    with TableInfo<$CategoriesTable, CategoryRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CategoriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _nameArMeta = const VerificationMeta('nameAr');
  @override
  late final GeneratedColumn<String> nameAr = GeneratedColumn<String>(
    'name_ar',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _displayOrderMeta = const VerificationMeta(
    'displayOrder',
  );
  @override
  late final GeneratedColumn<int> displayOrder = GeneratedColumn<int>(
    'display_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _addonGroupIdsJsonMeta = const VerificationMeta(
    'addonGroupIdsJson',
  );
  @override
  late final GeneratedColumn<String> addonGroupIdsJson =
      GeneratedColumn<String>(
        'addon_group_ids_json',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('[]'),
      );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    nameAr,
    displayOrder,
    status,
    addonGroupIdsJson,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'categories';
  @override
  VerificationContext validateIntegrity(
    Insertable<CategoryRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    }
    if (data.containsKey('name_ar')) {
      context.handle(
        _nameArMeta,
        nameAr.isAcceptableOrUnknown(data['name_ar']!, _nameArMeta),
      );
    }
    if (data.containsKey('display_order')) {
      context.handle(
        _displayOrderMeta,
        displayOrder.isAcceptableOrUnknown(
          data['display_order']!,
          _displayOrderMeta,
        ),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('addon_group_ids_json')) {
      context.handle(
        _addonGroupIdsJsonMeta,
        addonGroupIdsJson.isAcceptableOrUnknown(
          data['addon_group_ids_json']!,
          _addonGroupIdsJsonMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CategoryRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CategoryRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      nameAr: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name_ar'],
      ),
      displayOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}display_order'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      ),
      addonGroupIdsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}addon_group_ids_json'],
      )!,
    );
  }

  @override
  $CategoriesTable createAlias(String alias) {
    return $CategoriesTable(attachedDatabase, alias);
  }
}

class CategoryRow extends DataClass implements Insertable<CategoryRow> {
  final int id;
  final String name;
  final String? nameAr;
  final int displayOrder;
  final String? status;
  final String addonGroupIdsJson;
  const CategoryRow({
    required this.id,
    required this.name,
    this.nameAr,
    required this.displayOrder,
    this.status,
    required this.addonGroupIdsJson,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || nameAr != null) {
      map['name_ar'] = Variable<String>(nameAr);
    }
    map['display_order'] = Variable<int>(displayOrder);
    if (!nullToAbsent || status != null) {
      map['status'] = Variable<String>(status);
    }
    map['addon_group_ids_json'] = Variable<String>(addonGroupIdsJson);
    return map;
  }

  CategoriesCompanion toCompanion(bool nullToAbsent) {
    return CategoriesCompanion(
      id: Value(id),
      name: Value(name),
      nameAr: nameAr == null && nullToAbsent
          ? const Value.absent()
          : Value(nameAr),
      displayOrder: Value(displayOrder),
      status: status == null && nullToAbsent
          ? const Value.absent()
          : Value(status),
      addonGroupIdsJson: Value(addonGroupIdsJson),
    );
  }

  factory CategoryRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CategoryRow(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      nameAr: serializer.fromJson<String?>(json['nameAr']),
      displayOrder: serializer.fromJson<int>(json['displayOrder']),
      status: serializer.fromJson<String?>(json['status']),
      addonGroupIdsJson: serializer.fromJson<String>(json['addonGroupIdsJson']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'nameAr': serializer.toJson<String?>(nameAr),
      'displayOrder': serializer.toJson<int>(displayOrder),
      'status': serializer.toJson<String?>(status),
      'addonGroupIdsJson': serializer.toJson<String>(addonGroupIdsJson),
    };
  }

  CategoryRow copyWith({
    int? id,
    String? name,
    Value<String?> nameAr = const Value.absent(),
    int? displayOrder,
    Value<String?> status = const Value.absent(),
    String? addonGroupIdsJson,
  }) => CategoryRow(
    id: id ?? this.id,
    name: name ?? this.name,
    nameAr: nameAr.present ? nameAr.value : this.nameAr,
    displayOrder: displayOrder ?? this.displayOrder,
    status: status.present ? status.value : this.status,
    addonGroupIdsJson: addonGroupIdsJson ?? this.addonGroupIdsJson,
  );
  CategoryRow copyWithCompanion(CategoriesCompanion data) {
    return CategoryRow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      nameAr: data.nameAr.present ? data.nameAr.value : this.nameAr,
      displayOrder: data.displayOrder.present
          ? data.displayOrder.value
          : this.displayOrder,
      status: data.status.present ? data.status.value : this.status,
      addonGroupIdsJson: data.addonGroupIdsJson.present
          ? data.addonGroupIdsJson.value
          : this.addonGroupIdsJson,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CategoryRow(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('nameAr: $nameAr, ')
          ..write('displayOrder: $displayOrder, ')
          ..write('status: $status, ')
          ..write('addonGroupIdsJson: $addonGroupIdsJson')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, name, nameAr, displayOrder, status, addonGroupIdsJson);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CategoryRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.nameAr == this.nameAr &&
          other.displayOrder == this.displayOrder &&
          other.status == this.status &&
          other.addonGroupIdsJson == this.addonGroupIdsJson);
}

class CategoriesCompanion extends UpdateCompanion<CategoryRow> {
  final Value<int> id;
  final Value<String> name;
  final Value<String?> nameAr;
  final Value<int> displayOrder;
  final Value<String?> status;
  final Value<String> addonGroupIdsJson;
  const CategoriesCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.nameAr = const Value.absent(),
    this.displayOrder = const Value.absent(),
    this.status = const Value.absent(),
    this.addonGroupIdsJson = const Value.absent(),
  });
  CategoriesCompanion.insert({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.nameAr = const Value.absent(),
    this.displayOrder = const Value.absent(),
    this.status = const Value.absent(),
    this.addonGroupIdsJson = const Value.absent(),
  });
  static Insertable<CategoryRow> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<String>? nameAr,
    Expression<int>? displayOrder,
    Expression<String>? status,
    Expression<String>? addonGroupIdsJson,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (nameAr != null) 'name_ar': nameAr,
      if (displayOrder != null) 'display_order': displayOrder,
      if (status != null) 'status': status,
      if (addonGroupIdsJson != null) 'addon_group_ids_json': addonGroupIdsJson,
    });
  }

  CategoriesCompanion copyWith({
    Value<int>? id,
    Value<String>? name,
    Value<String?>? nameAr,
    Value<int>? displayOrder,
    Value<String?>? status,
    Value<String>? addonGroupIdsJson,
  }) {
    return CategoriesCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      nameAr: nameAr ?? this.nameAr,
      displayOrder: displayOrder ?? this.displayOrder,
      status: status ?? this.status,
      addonGroupIdsJson: addonGroupIdsJson ?? this.addonGroupIdsJson,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (nameAr.present) {
      map['name_ar'] = Variable<String>(nameAr.value);
    }
    if (displayOrder.present) {
      map['display_order'] = Variable<int>(displayOrder.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (addonGroupIdsJson.present) {
      map['addon_group_ids_json'] = Variable<String>(addonGroupIdsJson.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CategoriesCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('nameAr: $nameAr, ')
          ..write('displayOrder: $displayOrder, ')
          ..write('status: $status, ')
          ..write('addonGroupIdsJson: $addonGroupIdsJson')
          ..write(')'))
        .toString();
  }
}

class $ProductsTable extends Products
    with TableInfo<$ProductsTable, ProductRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProductsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _nameArMeta = const VerificationMeta('nameAr');
  @override
  late final GeneratedColumn<String> nameAr = GeneratedColumn<String>(
    'name_ar',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _categoryIdMeta = const VerificationMeta(
    'categoryId',
  );
  @override
  late final GeneratedColumn<int> categoryId = GeneratedColumn<int>(
    'category_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _basePriceBaisasMeta = const VerificationMeta(
    'basePriceBaisas',
  );
  @override
  late final GeneratedColumn<int> basePriceBaisas = GeneratedColumn<int>(
    'base_price_baisas',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _branchStockQtyMeta = const VerificationMeta(
    'branchStockQty',
  );
  @override
  late final GeneratedColumn<double> branchStockQty = GeneratedColumn<double>(
    'branch_stock_qty',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _imageUrlMeta = const VerificationMeta(
    'imageUrl',
  );
  @override
  late final GeneratedColumn<String> imageUrl = GeneratedColumn<String>(
    'image_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _addonGroupIdsMeta = const VerificationMeta(
    'addonGroupIds',
  );
  @override
  late final GeneratedColumn<String> addonGroupIds = GeneratedColumn<String>(
    'addon_group_ids',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _deliveryPriceBaisasMeta =
      const VerificationMeta('deliveryPriceBaisas');
  @override
  late final GeneratedColumn<int> deliveryPriceBaisas = GeneratedColumn<int>(
    'delivery_price_baisas',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _deliveryPricesJsonMeta =
      const VerificationMeta('deliveryPricesJson');
  @override
  late final GeneratedColumn<String> deliveryPricesJson =
      GeneratedColumn<String>(
        'delivery_prices_json',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('{}'),
      );
  static const VerificationMeta _stockModeMeta = const VerificationMeta(
    'stockMode',
  );
  @override
  late final GeneratedColumn<String> stockMode = GeneratedColumn<String>(
    'stock_mode',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _recipeJsonMeta = const VerificationMeta(
    'recipeJson',
  );
  @override
  late final GeneratedColumn<String> recipeJson = GeneratedColumn<String>(
    'recipe_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _availableFromMeta = const VerificationMeta(
    'availableFrom',
  );
  @override
  late final GeneratedColumn<String> availableFrom = GeneratedColumn<String>(
    'available_from',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _availableUntilMeta = const VerificationMeta(
    'availableUntil',
  );
  @override
  late final GeneratedColumn<String> availableUntil = GeneratedColumn<String>(
    'available_until',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    nameAr,
    categoryId,
    basePriceBaisas,
    branchStockQty,
    imageUrl,
    status,
    addonGroupIds,
    deliveryPriceBaisas,
    deliveryPricesJson,
    stockMode,
    recipeJson,
    availableFrom,
    availableUntil,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'products';
  @override
  VerificationContext validateIntegrity(
    Insertable<ProductRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    }
    if (data.containsKey('name_ar')) {
      context.handle(
        _nameArMeta,
        nameAr.isAcceptableOrUnknown(data['name_ar']!, _nameArMeta),
      );
    }
    if (data.containsKey('category_id')) {
      context.handle(
        _categoryIdMeta,
        categoryId.isAcceptableOrUnknown(data['category_id']!, _categoryIdMeta),
      );
    }
    if (data.containsKey('base_price_baisas')) {
      context.handle(
        _basePriceBaisasMeta,
        basePriceBaisas.isAcceptableOrUnknown(
          data['base_price_baisas']!,
          _basePriceBaisasMeta,
        ),
      );
    }
    if (data.containsKey('branch_stock_qty')) {
      context.handle(
        _branchStockQtyMeta,
        branchStockQty.isAcceptableOrUnknown(
          data['branch_stock_qty']!,
          _branchStockQtyMeta,
        ),
      );
    }
    if (data.containsKey('image_url')) {
      context.handle(
        _imageUrlMeta,
        imageUrl.isAcceptableOrUnknown(data['image_url']!, _imageUrlMeta),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('addon_group_ids')) {
      context.handle(
        _addonGroupIdsMeta,
        addonGroupIds.isAcceptableOrUnknown(
          data['addon_group_ids']!,
          _addonGroupIdsMeta,
        ),
      );
    }
    if (data.containsKey('delivery_price_baisas')) {
      context.handle(
        _deliveryPriceBaisasMeta,
        deliveryPriceBaisas.isAcceptableOrUnknown(
          data['delivery_price_baisas']!,
          _deliveryPriceBaisasMeta,
        ),
      );
    }
    if (data.containsKey('delivery_prices_json')) {
      context.handle(
        _deliveryPricesJsonMeta,
        deliveryPricesJson.isAcceptableOrUnknown(
          data['delivery_prices_json']!,
          _deliveryPricesJsonMeta,
        ),
      );
    }
    if (data.containsKey('stock_mode')) {
      context.handle(
        _stockModeMeta,
        stockMode.isAcceptableOrUnknown(data['stock_mode']!, _stockModeMeta),
      );
    }
    if (data.containsKey('recipe_json')) {
      context.handle(
        _recipeJsonMeta,
        recipeJson.isAcceptableOrUnknown(data['recipe_json']!, _recipeJsonMeta),
      );
    }
    if (data.containsKey('available_from')) {
      context.handle(
        _availableFromMeta,
        availableFrom.isAcceptableOrUnknown(
          data['available_from']!,
          _availableFromMeta,
        ),
      );
    }
    if (data.containsKey('available_until')) {
      context.handle(
        _availableUntilMeta,
        availableUntil.isAcceptableOrUnknown(
          data['available_until']!,
          _availableUntilMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ProductRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ProductRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      nameAr: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name_ar'],
      ),
      categoryId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}category_id'],
      ),
      basePriceBaisas: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}base_price_baisas'],
      )!,
      branchStockQty: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}branch_stock_qty'],
      ),
      imageUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}image_url'],
      ),
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      ),
      addonGroupIds: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}addon_group_ids'],
      )!,
      deliveryPriceBaisas: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}delivery_price_baisas'],
      ),
      deliveryPricesJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}delivery_prices_json'],
      )!,
      stockMode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}stock_mode'],
      ),
      recipeJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}recipe_json'],
      )!,
      availableFrom: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}available_from'],
      ),
      availableUntil: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}available_until'],
      ),
    );
  }

  @override
  $ProductsTable createAlias(String alias) {
    return $ProductsTable(attachedDatabase, alias);
  }
}

class ProductRow extends DataClass implements Insertable<ProductRow> {
  final int id;
  final String name;
  final String? nameAr;
  final int? categoryId;
  final int basePriceBaisas;
  final double? branchStockQty;
  final String? imageUrl;
  final String? status;
  final String addonGroupIds;
  final int? deliveryPriceBaisas;
  final String deliveryPricesJson;
  final String? stockMode;
  final String recipeJson;
  final String? availableFrom;
  final String? availableUntil;
  const ProductRow({
    required this.id,
    required this.name,
    this.nameAr,
    this.categoryId,
    required this.basePriceBaisas,
    this.branchStockQty,
    this.imageUrl,
    this.status,
    required this.addonGroupIds,
    this.deliveryPriceBaisas,
    required this.deliveryPricesJson,
    this.stockMode,
    required this.recipeJson,
    this.availableFrom,
    this.availableUntil,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || nameAr != null) {
      map['name_ar'] = Variable<String>(nameAr);
    }
    if (!nullToAbsent || categoryId != null) {
      map['category_id'] = Variable<int>(categoryId);
    }
    map['base_price_baisas'] = Variable<int>(basePriceBaisas);
    if (!nullToAbsent || branchStockQty != null) {
      map['branch_stock_qty'] = Variable<double>(branchStockQty);
    }
    if (!nullToAbsent || imageUrl != null) {
      map['image_url'] = Variable<String>(imageUrl);
    }
    if (!nullToAbsent || status != null) {
      map['status'] = Variable<String>(status);
    }
    map['addon_group_ids'] = Variable<String>(addonGroupIds);
    if (!nullToAbsent || deliveryPriceBaisas != null) {
      map['delivery_price_baisas'] = Variable<int>(deliveryPriceBaisas);
    }
    map['delivery_prices_json'] = Variable<String>(deliveryPricesJson);
    if (!nullToAbsent || stockMode != null) {
      map['stock_mode'] = Variable<String>(stockMode);
    }
    map['recipe_json'] = Variable<String>(recipeJson);
    if (!nullToAbsent || availableFrom != null) {
      map['available_from'] = Variable<String>(availableFrom);
    }
    if (!nullToAbsent || availableUntil != null) {
      map['available_until'] = Variable<String>(availableUntil);
    }
    return map;
  }

  ProductsCompanion toCompanion(bool nullToAbsent) {
    return ProductsCompanion(
      id: Value(id),
      name: Value(name),
      nameAr: nameAr == null && nullToAbsent
          ? const Value.absent()
          : Value(nameAr),
      categoryId: categoryId == null && nullToAbsent
          ? const Value.absent()
          : Value(categoryId),
      basePriceBaisas: Value(basePriceBaisas),
      branchStockQty: branchStockQty == null && nullToAbsent
          ? const Value.absent()
          : Value(branchStockQty),
      imageUrl: imageUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(imageUrl),
      status: status == null && nullToAbsent
          ? const Value.absent()
          : Value(status),
      addonGroupIds: Value(addonGroupIds),
      deliveryPriceBaisas: deliveryPriceBaisas == null && nullToAbsent
          ? const Value.absent()
          : Value(deliveryPriceBaisas),
      deliveryPricesJson: Value(deliveryPricesJson),
      stockMode: stockMode == null && nullToAbsent
          ? const Value.absent()
          : Value(stockMode),
      recipeJson: Value(recipeJson),
      availableFrom: availableFrom == null && nullToAbsent
          ? const Value.absent()
          : Value(availableFrom),
      availableUntil: availableUntil == null && nullToAbsent
          ? const Value.absent()
          : Value(availableUntil),
    );
  }

  factory ProductRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ProductRow(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      nameAr: serializer.fromJson<String?>(json['nameAr']),
      categoryId: serializer.fromJson<int?>(json['categoryId']),
      basePriceBaisas: serializer.fromJson<int>(json['basePriceBaisas']),
      branchStockQty: serializer.fromJson<double?>(json['branchStockQty']),
      imageUrl: serializer.fromJson<String?>(json['imageUrl']),
      status: serializer.fromJson<String?>(json['status']),
      addonGroupIds: serializer.fromJson<String>(json['addonGroupIds']),
      deliveryPriceBaisas: serializer.fromJson<int?>(
        json['deliveryPriceBaisas'],
      ),
      deliveryPricesJson: serializer.fromJson<String>(
        json['deliveryPricesJson'],
      ),
      stockMode: serializer.fromJson<String?>(json['stockMode']),
      recipeJson: serializer.fromJson<String>(json['recipeJson']),
      availableFrom: serializer.fromJson<String?>(json['availableFrom']),
      availableUntil: serializer.fromJson<String?>(json['availableUntil']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'nameAr': serializer.toJson<String?>(nameAr),
      'categoryId': serializer.toJson<int?>(categoryId),
      'basePriceBaisas': serializer.toJson<int>(basePriceBaisas),
      'branchStockQty': serializer.toJson<double?>(branchStockQty),
      'imageUrl': serializer.toJson<String?>(imageUrl),
      'status': serializer.toJson<String?>(status),
      'addonGroupIds': serializer.toJson<String>(addonGroupIds),
      'deliveryPriceBaisas': serializer.toJson<int?>(deliveryPriceBaisas),
      'deliveryPricesJson': serializer.toJson<String>(deliveryPricesJson),
      'stockMode': serializer.toJson<String?>(stockMode),
      'recipeJson': serializer.toJson<String>(recipeJson),
      'availableFrom': serializer.toJson<String?>(availableFrom),
      'availableUntil': serializer.toJson<String?>(availableUntil),
    };
  }

  ProductRow copyWith({
    int? id,
    String? name,
    Value<String?> nameAr = const Value.absent(),
    Value<int?> categoryId = const Value.absent(),
    int? basePriceBaisas,
    Value<double?> branchStockQty = const Value.absent(),
    Value<String?> imageUrl = const Value.absent(),
    Value<String?> status = const Value.absent(),
    String? addonGroupIds,
    Value<int?> deliveryPriceBaisas = const Value.absent(),
    String? deliveryPricesJson,
    Value<String?> stockMode = const Value.absent(),
    String? recipeJson,
    Value<String?> availableFrom = const Value.absent(),
    Value<String?> availableUntil = const Value.absent(),
  }) => ProductRow(
    id: id ?? this.id,
    name: name ?? this.name,
    nameAr: nameAr.present ? nameAr.value : this.nameAr,
    categoryId: categoryId.present ? categoryId.value : this.categoryId,
    basePriceBaisas: basePriceBaisas ?? this.basePriceBaisas,
    branchStockQty: branchStockQty.present
        ? branchStockQty.value
        : this.branchStockQty,
    imageUrl: imageUrl.present ? imageUrl.value : this.imageUrl,
    status: status.present ? status.value : this.status,
    addonGroupIds: addonGroupIds ?? this.addonGroupIds,
    deliveryPriceBaisas: deliveryPriceBaisas.present
        ? deliveryPriceBaisas.value
        : this.deliveryPriceBaisas,
    deliveryPricesJson: deliveryPricesJson ?? this.deliveryPricesJson,
    stockMode: stockMode.present ? stockMode.value : this.stockMode,
    recipeJson: recipeJson ?? this.recipeJson,
    availableFrom: availableFrom.present
        ? availableFrom.value
        : this.availableFrom,
    availableUntil: availableUntil.present
        ? availableUntil.value
        : this.availableUntil,
  );
  ProductRow copyWithCompanion(ProductsCompanion data) {
    return ProductRow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      nameAr: data.nameAr.present ? data.nameAr.value : this.nameAr,
      categoryId: data.categoryId.present
          ? data.categoryId.value
          : this.categoryId,
      basePriceBaisas: data.basePriceBaisas.present
          ? data.basePriceBaisas.value
          : this.basePriceBaisas,
      branchStockQty: data.branchStockQty.present
          ? data.branchStockQty.value
          : this.branchStockQty,
      imageUrl: data.imageUrl.present ? data.imageUrl.value : this.imageUrl,
      status: data.status.present ? data.status.value : this.status,
      addonGroupIds: data.addonGroupIds.present
          ? data.addonGroupIds.value
          : this.addonGroupIds,
      deliveryPriceBaisas: data.deliveryPriceBaisas.present
          ? data.deliveryPriceBaisas.value
          : this.deliveryPriceBaisas,
      deliveryPricesJson: data.deliveryPricesJson.present
          ? data.deliveryPricesJson.value
          : this.deliveryPricesJson,
      stockMode: data.stockMode.present ? data.stockMode.value : this.stockMode,
      recipeJson: data.recipeJson.present
          ? data.recipeJson.value
          : this.recipeJson,
      availableFrom: data.availableFrom.present
          ? data.availableFrom.value
          : this.availableFrom,
      availableUntil: data.availableUntil.present
          ? data.availableUntil.value
          : this.availableUntil,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ProductRow(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('nameAr: $nameAr, ')
          ..write('categoryId: $categoryId, ')
          ..write('basePriceBaisas: $basePriceBaisas, ')
          ..write('branchStockQty: $branchStockQty, ')
          ..write('imageUrl: $imageUrl, ')
          ..write('status: $status, ')
          ..write('addonGroupIds: $addonGroupIds, ')
          ..write('deliveryPriceBaisas: $deliveryPriceBaisas, ')
          ..write('deliveryPricesJson: $deliveryPricesJson, ')
          ..write('stockMode: $stockMode, ')
          ..write('recipeJson: $recipeJson, ')
          ..write('availableFrom: $availableFrom, ')
          ..write('availableUntil: $availableUntil')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    nameAr,
    categoryId,
    basePriceBaisas,
    branchStockQty,
    imageUrl,
    status,
    addonGroupIds,
    deliveryPriceBaisas,
    deliveryPricesJson,
    stockMode,
    recipeJson,
    availableFrom,
    availableUntil,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ProductRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.nameAr == this.nameAr &&
          other.categoryId == this.categoryId &&
          other.basePriceBaisas == this.basePriceBaisas &&
          other.branchStockQty == this.branchStockQty &&
          other.imageUrl == this.imageUrl &&
          other.status == this.status &&
          other.addonGroupIds == this.addonGroupIds &&
          other.deliveryPriceBaisas == this.deliveryPriceBaisas &&
          other.deliveryPricesJson == this.deliveryPricesJson &&
          other.stockMode == this.stockMode &&
          other.recipeJson == this.recipeJson &&
          other.availableFrom == this.availableFrom &&
          other.availableUntil == this.availableUntil);
}

class ProductsCompanion extends UpdateCompanion<ProductRow> {
  final Value<int> id;
  final Value<String> name;
  final Value<String?> nameAr;
  final Value<int?> categoryId;
  final Value<int> basePriceBaisas;
  final Value<double?> branchStockQty;
  final Value<String?> imageUrl;
  final Value<String?> status;
  final Value<String> addonGroupIds;
  final Value<int?> deliveryPriceBaisas;
  final Value<String> deliveryPricesJson;
  final Value<String?> stockMode;
  final Value<String> recipeJson;
  final Value<String?> availableFrom;
  final Value<String?> availableUntil;
  const ProductsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.nameAr = const Value.absent(),
    this.categoryId = const Value.absent(),
    this.basePriceBaisas = const Value.absent(),
    this.branchStockQty = const Value.absent(),
    this.imageUrl = const Value.absent(),
    this.status = const Value.absent(),
    this.addonGroupIds = const Value.absent(),
    this.deliveryPriceBaisas = const Value.absent(),
    this.deliveryPricesJson = const Value.absent(),
    this.stockMode = const Value.absent(),
    this.recipeJson = const Value.absent(),
    this.availableFrom = const Value.absent(),
    this.availableUntil = const Value.absent(),
  });
  ProductsCompanion.insert({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.nameAr = const Value.absent(),
    this.categoryId = const Value.absent(),
    this.basePriceBaisas = const Value.absent(),
    this.branchStockQty = const Value.absent(),
    this.imageUrl = const Value.absent(),
    this.status = const Value.absent(),
    this.addonGroupIds = const Value.absent(),
    this.deliveryPriceBaisas = const Value.absent(),
    this.deliveryPricesJson = const Value.absent(),
    this.stockMode = const Value.absent(),
    this.recipeJson = const Value.absent(),
    this.availableFrom = const Value.absent(),
    this.availableUntil = const Value.absent(),
  });
  static Insertable<ProductRow> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<String>? nameAr,
    Expression<int>? categoryId,
    Expression<int>? basePriceBaisas,
    Expression<double>? branchStockQty,
    Expression<String>? imageUrl,
    Expression<String>? status,
    Expression<String>? addonGroupIds,
    Expression<int>? deliveryPriceBaisas,
    Expression<String>? deliveryPricesJson,
    Expression<String>? stockMode,
    Expression<String>? recipeJson,
    Expression<String>? availableFrom,
    Expression<String>? availableUntil,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (nameAr != null) 'name_ar': nameAr,
      if (categoryId != null) 'category_id': categoryId,
      if (basePriceBaisas != null) 'base_price_baisas': basePriceBaisas,
      if (branchStockQty != null) 'branch_stock_qty': branchStockQty,
      if (imageUrl != null) 'image_url': imageUrl,
      if (status != null) 'status': status,
      if (addonGroupIds != null) 'addon_group_ids': addonGroupIds,
      if (deliveryPriceBaisas != null)
        'delivery_price_baisas': deliveryPriceBaisas,
      if (deliveryPricesJson != null)
        'delivery_prices_json': deliveryPricesJson,
      if (stockMode != null) 'stock_mode': stockMode,
      if (recipeJson != null) 'recipe_json': recipeJson,
      if (availableFrom != null) 'available_from': availableFrom,
      if (availableUntil != null) 'available_until': availableUntil,
    });
  }

  ProductsCompanion copyWith({
    Value<int>? id,
    Value<String>? name,
    Value<String?>? nameAr,
    Value<int?>? categoryId,
    Value<int>? basePriceBaisas,
    Value<double?>? branchStockQty,
    Value<String?>? imageUrl,
    Value<String?>? status,
    Value<String>? addonGroupIds,
    Value<int?>? deliveryPriceBaisas,
    Value<String>? deliveryPricesJson,
    Value<String?>? stockMode,
    Value<String>? recipeJson,
    Value<String?>? availableFrom,
    Value<String?>? availableUntil,
  }) {
    return ProductsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      nameAr: nameAr ?? this.nameAr,
      categoryId: categoryId ?? this.categoryId,
      basePriceBaisas: basePriceBaisas ?? this.basePriceBaisas,
      branchStockQty: branchStockQty ?? this.branchStockQty,
      imageUrl: imageUrl ?? this.imageUrl,
      status: status ?? this.status,
      addonGroupIds: addonGroupIds ?? this.addonGroupIds,
      deliveryPriceBaisas: deliveryPriceBaisas ?? this.deliveryPriceBaisas,
      deliveryPricesJson: deliveryPricesJson ?? this.deliveryPricesJson,
      stockMode: stockMode ?? this.stockMode,
      recipeJson: recipeJson ?? this.recipeJson,
      availableFrom: availableFrom ?? this.availableFrom,
      availableUntil: availableUntil ?? this.availableUntil,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (nameAr.present) {
      map['name_ar'] = Variable<String>(nameAr.value);
    }
    if (categoryId.present) {
      map['category_id'] = Variable<int>(categoryId.value);
    }
    if (basePriceBaisas.present) {
      map['base_price_baisas'] = Variable<int>(basePriceBaisas.value);
    }
    if (branchStockQty.present) {
      map['branch_stock_qty'] = Variable<double>(branchStockQty.value);
    }
    if (imageUrl.present) {
      map['image_url'] = Variable<String>(imageUrl.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (addonGroupIds.present) {
      map['addon_group_ids'] = Variable<String>(addonGroupIds.value);
    }
    if (deliveryPriceBaisas.present) {
      map['delivery_price_baisas'] = Variable<int>(deliveryPriceBaisas.value);
    }
    if (deliveryPricesJson.present) {
      map['delivery_prices_json'] = Variable<String>(deliveryPricesJson.value);
    }
    if (stockMode.present) {
      map['stock_mode'] = Variable<String>(stockMode.value);
    }
    if (recipeJson.present) {
      map['recipe_json'] = Variable<String>(recipeJson.value);
    }
    if (availableFrom.present) {
      map['available_from'] = Variable<String>(availableFrom.value);
    }
    if (availableUntil.present) {
      map['available_until'] = Variable<String>(availableUntil.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProductsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('nameAr: $nameAr, ')
          ..write('categoryId: $categoryId, ')
          ..write('basePriceBaisas: $basePriceBaisas, ')
          ..write('branchStockQty: $branchStockQty, ')
          ..write('imageUrl: $imageUrl, ')
          ..write('status: $status, ')
          ..write('addonGroupIds: $addonGroupIds, ')
          ..write('deliveryPriceBaisas: $deliveryPriceBaisas, ')
          ..write('deliveryPricesJson: $deliveryPricesJson, ')
          ..write('stockMode: $stockMode, ')
          ..write('recipeJson: $recipeJson, ')
          ..write('availableFrom: $availableFrom, ')
          ..write('availableUntil: $availableUntil')
          ..write(')'))
        .toString();
  }
}

class $FloorsTable extends Floors with TableInfo<$FloorsTable, FloorRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FloorsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _nameArMeta = const VerificationMeta('nameAr');
  @override
  late final GeneratedColumn<String> nameAr = GeneratedColumn<String>(
    'name_ar',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _displayOrderMeta = const VerificationMeta(
    'displayOrder',
  );
  @override
  late final GeneratedColumn<int> displayOrder = GeneratedColumn<int>(
    'display_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    nameAr,
    displayOrder,
    status,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'floors';
  @override
  VerificationContext validateIntegrity(
    Insertable<FloorRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    }
    if (data.containsKey('name_ar')) {
      context.handle(
        _nameArMeta,
        nameAr.isAcceptableOrUnknown(data['name_ar']!, _nameArMeta),
      );
    }
    if (data.containsKey('display_order')) {
      context.handle(
        _displayOrderMeta,
        displayOrder.isAcceptableOrUnknown(
          data['display_order']!,
          _displayOrderMeta,
        ),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  FloorRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FloorRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      nameAr: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name_ar'],
      ),
      displayOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}display_order'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      ),
    );
  }

  @override
  $FloorsTable createAlias(String alias) {
    return $FloorsTable(attachedDatabase, alias);
  }
}

class FloorRow extends DataClass implements Insertable<FloorRow> {
  final int id;
  final String name;
  final String? nameAr;
  final int displayOrder;
  final String? status;
  const FloorRow({
    required this.id,
    required this.name,
    this.nameAr,
    required this.displayOrder,
    this.status,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || nameAr != null) {
      map['name_ar'] = Variable<String>(nameAr);
    }
    map['display_order'] = Variable<int>(displayOrder);
    if (!nullToAbsent || status != null) {
      map['status'] = Variable<String>(status);
    }
    return map;
  }

  FloorsCompanion toCompanion(bool nullToAbsent) {
    return FloorsCompanion(
      id: Value(id),
      name: Value(name),
      nameAr: nameAr == null && nullToAbsent
          ? const Value.absent()
          : Value(nameAr),
      displayOrder: Value(displayOrder),
      status: status == null && nullToAbsent
          ? const Value.absent()
          : Value(status),
    );
  }

  factory FloorRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FloorRow(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      nameAr: serializer.fromJson<String?>(json['nameAr']),
      displayOrder: serializer.fromJson<int>(json['displayOrder']),
      status: serializer.fromJson<String?>(json['status']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'nameAr': serializer.toJson<String?>(nameAr),
      'displayOrder': serializer.toJson<int>(displayOrder),
      'status': serializer.toJson<String?>(status),
    };
  }

  FloorRow copyWith({
    int? id,
    String? name,
    Value<String?> nameAr = const Value.absent(),
    int? displayOrder,
    Value<String?> status = const Value.absent(),
  }) => FloorRow(
    id: id ?? this.id,
    name: name ?? this.name,
    nameAr: nameAr.present ? nameAr.value : this.nameAr,
    displayOrder: displayOrder ?? this.displayOrder,
    status: status.present ? status.value : this.status,
  );
  FloorRow copyWithCompanion(FloorsCompanion data) {
    return FloorRow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      nameAr: data.nameAr.present ? data.nameAr.value : this.nameAr,
      displayOrder: data.displayOrder.present
          ? data.displayOrder.value
          : this.displayOrder,
      status: data.status.present ? data.status.value : this.status,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FloorRow(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('nameAr: $nameAr, ')
          ..write('displayOrder: $displayOrder, ')
          ..write('status: $status')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, nameAr, displayOrder, status);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FloorRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.nameAr == this.nameAr &&
          other.displayOrder == this.displayOrder &&
          other.status == this.status);
}

class FloorsCompanion extends UpdateCompanion<FloorRow> {
  final Value<int> id;
  final Value<String> name;
  final Value<String?> nameAr;
  final Value<int> displayOrder;
  final Value<String?> status;
  const FloorsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.nameAr = const Value.absent(),
    this.displayOrder = const Value.absent(),
    this.status = const Value.absent(),
  });
  FloorsCompanion.insert({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.nameAr = const Value.absent(),
    this.displayOrder = const Value.absent(),
    this.status = const Value.absent(),
  });
  static Insertable<FloorRow> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<String>? nameAr,
    Expression<int>? displayOrder,
    Expression<String>? status,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (nameAr != null) 'name_ar': nameAr,
      if (displayOrder != null) 'display_order': displayOrder,
      if (status != null) 'status': status,
    });
  }

  FloorsCompanion copyWith({
    Value<int>? id,
    Value<String>? name,
    Value<String?>? nameAr,
    Value<int>? displayOrder,
    Value<String?>? status,
  }) {
    return FloorsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      nameAr: nameAr ?? this.nameAr,
      displayOrder: displayOrder ?? this.displayOrder,
      status: status ?? this.status,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (nameAr.present) {
      map['name_ar'] = Variable<String>(nameAr.value);
    }
    if (displayOrder.present) {
      map['display_order'] = Variable<int>(displayOrder.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FloorsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('nameAr: $nameAr, ')
          ..write('displayOrder: $displayOrder, ')
          ..write('status: $status')
          ..write(')'))
        .toString();
  }
}

class $PosTablesTable extends PosTables
    with TableInfo<$PosTablesTable, TableRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PosTablesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _floorIdMeta = const VerificationMeta(
    'floorId',
  );
  @override
  late final GeneratedColumn<int> floorId = GeneratedColumn<int>(
    'floor_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _labelMeta = const VerificationMeta('label');
  @override
  late final GeneratedColumn<String> label = GeneratedColumn<String>(
    'label',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _seatsMeta = const VerificationMeta('seats');
  @override
  late final GeneratedColumn<int> seats = GeneratedColumn<int>(
    'seats',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _positionXMeta = const VerificationMeta(
    'positionX',
  );
  @override
  late final GeneratedColumn<int> positionX = GeneratedColumn<int>(
    'position_x',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _positionYMeta = const VerificationMeta(
    'positionY',
  );
  @override
  late final GeneratedColumn<int> positionY = GeneratedColumn<int>(
    'position_y',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _widthMeta = const VerificationMeta('width');
  @override
  late final GeneratedColumn<int> width = GeneratedColumn<int>(
    'width',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _heightMeta = const VerificationMeta('height');
  @override
  late final GeneratedColumn<int> height = GeneratedColumn<int>(
    'height',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _shapeMeta = const VerificationMeta('shape');
  @override
  late final GeneratedColumn<String> shape = GeneratedColumn<String>(
    'shape',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _displayOrderMeta = const VerificationMeta(
    'displayOrder',
  );
  @override
  late final GeneratedColumn<int> displayOrder = GeneratedColumn<int>(
    'display_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    floorId,
    label,
    seats,
    positionX,
    positionY,
    width,
    height,
    shape,
    displayOrder,
    status,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'pos_tables';
  @override
  VerificationContext validateIntegrity(
    Insertable<TableRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('floor_id')) {
      context.handle(
        _floorIdMeta,
        floorId.isAcceptableOrUnknown(data['floor_id']!, _floorIdMeta),
      );
    } else if (isInserting) {
      context.missing(_floorIdMeta);
    }
    if (data.containsKey('label')) {
      context.handle(
        _labelMeta,
        label.isAcceptableOrUnknown(data['label']!, _labelMeta),
      );
    }
    if (data.containsKey('seats')) {
      context.handle(
        _seatsMeta,
        seats.isAcceptableOrUnknown(data['seats']!, _seatsMeta),
      );
    }
    if (data.containsKey('position_x')) {
      context.handle(
        _positionXMeta,
        positionX.isAcceptableOrUnknown(data['position_x']!, _positionXMeta),
      );
    }
    if (data.containsKey('position_y')) {
      context.handle(
        _positionYMeta,
        positionY.isAcceptableOrUnknown(data['position_y']!, _positionYMeta),
      );
    }
    if (data.containsKey('width')) {
      context.handle(
        _widthMeta,
        width.isAcceptableOrUnknown(data['width']!, _widthMeta),
      );
    }
    if (data.containsKey('height')) {
      context.handle(
        _heightMeta,
        height.isAcceptableOrUnknown(data['height']!, _heightMeta),
      );
    }
    if (data.containsKey('shape')) {
      context.handle(
        _shapeMeta,
        shape.isAcceptableOrUnknown(data['shape']!, _shapeMeta),
      );
    }
    if (data.containsKey('display_order')) {
      context.handle(
        _displayOrderMeta,
        displayOrder.isAcceptableOrUnknown(
          data['display_order']!,
          _displayOrderMeta,
        ),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TableRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TableRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      floorId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}floor_id'],
      )!,
      label: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}label'],
      )!,
      seats: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}seats'],
      )!,
      positionX: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position_x'],
      ),
      positionY: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position_y'],
      ),
      width: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}width'],
      ),
      height: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}height'],
      ),
      shape: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}shape'],
      ),
      displayOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}display_order'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      ),
    );
  }

  @override
  $PosTablesTable createAlias(String alias) {
    return $PosTablesTable(attachedDatabase, alias);
  }
}

class TableRow extends DataClass implements Insertable<TableRow> {
  final int id;
  final int floorId;
  final String label;
  final int seats;
  final int? positionX;
  final int? positionY;
  final int? width;
  final int? height;
  final String? shape;
  final int displayOrder;
  final String? status;
  const TableRow({
    required this.id,
    required this.floorId,
    required this.label,
    required this.seats,
    this.positionX,
    this.positionY,
    this.width,
    this.height,
    this.shape,
    required this.displayOrder,
    this.status,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['floor_id'] = Variable<int>(floorId);
    map['label'] = Variable<String>(label);
    map['seats'] = Variable<int>(seats);
    if (!nullToAbsent || positionX != null) {
      map['position_x'] = Variable<int>(positionX);
    }
    if (!nullToAbsent || positionY != null) {
      map['position_y'] = Variable<int>(positionY);
    }
    if (!nullToAbsent || width != null) {
      map['width'] = Variable<int>(width);
    }
    if (!nullToAbsent || height != null) {
      map['height'] = Variable<int>(height);
    }
    if (!nullToAbsent || shape != null) {
      map['shape'] = Variable<String>(shape);
    }
    map['display_order'] = Variable<int>(displayOrder);
    if (!nullToAbsent || status != null) {
      map['status'] = Variable<String>(status);
    }
    return map;
  }

  PosTablesCompanion toCompanion(bool nullToAbsent) {
    return PosTablesCompanion(
      id: Value(id),
      floorId: Value(floorId),
      label: Value(label),
      seats: Value(seats),
      positionX: positionX == null && nullToAbsent
          ? const Value.absent()
          : Value(positionX),
      positionY: positionY == null && nullToAbsent
          ? const Value.absent()
          : Value(positionY),
      width: width == null && nullToAbsent
          ? const Value.absent()
          : Value(width),
      height: height == null && nullToAbsent
          ? const Value.absent()
          : Value(height),
      shape: shape == null && nullToAbsent
          ? const Value.absent()
          : Value(shape),
      displayOrder: Value(displayOrder),
      status: status == null && nullToAbsent
          ? const Value.absent()
          : Value(status),
    );
  }

  factory TableRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TableRow(
      id: serializer.fromJson<int>(json['id']),
      floorId: serializer.fromJson<int>(json['floorId']),
      label: serializer.fromJson<String>(json['label']),
      seats: serializer.fromJson<int>(json['seats']),
      positionX: serializer.fromJson<int?>(json['positionX']),
      positionY: serializer.fromJson<int?>(json['positionY']),
      width: serializer.fromJson<int?>(json['width']),
      height: serializer.fromJson<int?>(json['height']),
      shape: serializer.fromJson<String?>(json['shape']),
      displayOrder: serializer.fromJson<int>(json['displayOrder']),
      status: serializer.fromJson<String?>(json['status']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'floorId': serializer.toJson<int>(floorId),
      'label': serializer.toJson<String>(label),
      'seats': serializer.toJson<int>(seats),
      'positionX': serializer.toJson<int?>(positionX),
      'positionY': serializer.toJson<int?>(positionY),
      'width': serializer.toJson<int?>(width),
      'height': serializer.toJson<int?>(height),
      'shape': serializer.toJson<String?>(shape),
      'displayOrder': serializer.toJson<int>(displayOrder),
      'status': serializer.toJson<String?>(status),
    };
  }

  TableRow copyWith({
    int? id,
    int? floorId,
    String? label,
    int? seats,
    Value<int?> positionX = const Value.absent(),
    Value<int?> positionY = const Value.absent(),
    Value<int?> width = const Value.absent(),
    Value<int?> height = const Value.absent(),
    Value<String?> shape = const Value.absent(),
    int? displayOrder,
    Value<String?> status = const Value.absent(),
  }) => TableRow(
    id: id ?? this.id,
    floorId: floorId ?? this.floorId,
    label: label ?? this.label,
    seats: seats ?? this.seats,
    positionX: positionX.present ? positionX.value : this.positionX,
    positionY: positionY.present ? positionY.value : this.positionY,
    width: width.present ? width.value : this.width,
    height: height.present ? height.value : this.height,
    shape: shape.present ? shape.value : this.shape,
    displayOrder: displayOrder ?? this.displayOrder,
    status: status.present ? status.value : this.status,
  );
  TableRow copyWithCompanion(PosTablesCompanion data) {
    return TableRow(
      id: data.id.present ? data.id.value : this.id,
      floorId: data.floorId.present ? data.floorId.value : this.floorId,
      label: data.label.present ? data.label.value : this.label,
      seats: data.seats.present ? data.seats.value : this.seats,
      positionX: data.positionX.present ? data.positionX.value : this.positionX,
      positionY: data.positionY.present ? data.positionY.value : this.positionY,
      width: data.width.present ? data.width.value : this.width,
      height: data.height.present ? data.height.value : this.height,
      shape: data.shape.present ? data.shape.value : this.shape,
      displayOrder: data.displayOrder.present
          ? data.displayOrder.value
          : this.displayOrder,
      status: data.status.present ? data.status.value : this.status,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TableRow(')
          ..write('id: $id, ')
          ..write('floorId: $floorId, ')
          ..write('label: $label, ')
          ..write('seats: $seats, ')
          ..write('positionX: $positionX, ')
          ..write('positionY: $positionY, ')
          ..write('width: $width, ')
          ..write('height: $height, ')
          ..write('shape: $shape, ')
          ..write('displayOrder: $displayOrder, ')
          ..write('status: $status')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    floorId,
    label,
    seats,
    positionX,
    positionY,
    width,
    height,
    shape,
    displayOrder,
    status,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TableRow &&
          other.id == this.id &&
          other.floorId == this.floorId &&
          other.label == this.label &&
          other.seats == this.seats &&
          other.positionX == this.positionX &&
          other.positionY == this.positionY &&
          other.width == this.width &&
          other.height == this.height &&
          other.shape == this.shape &&
          other.displayOrder == this.displayOrder &&
          other.status == this.status);
}

class PosTablesCompanion extends UpdateCompanion<TableRow> {
  final Value<int> id;
  final Value<int> floorId;
  final Value<String> label;
  final Value<int> seats;
  final Value<int?> positionX;
  final Value<int?> positionY;
  final Value<int?> width;
  final Value<int?> height;
  final Value<String?> shape;
  final Value<int> displayOrder;
  final Value<String?> status;
  const PosTablesCompanion({
    this.id = const Value.absent(),
    this.floorId = const Value.absent(),
    this.label = const Value.absent(),
    this.seats = const Value.absent(),
    this.positionX = const Value.absent(),
    this.positionY = const Value.absent(),
    this.width = const Value.absent(),
    this.height = const Value.absent(),
    this.shape = const Value.absent(),
    this.displayOrder = const Value.absent(),
    this.status = const Value.absent(),
  });
  PosTablesCompanion.insert({
    this.id = const Value.absent(),
    required int floorId,
    this.label = const Value.absent(),
    this.seats = const Value.absent(),
    this.positionX = const Value.absent(),
    this.positionY = const Value.absent(),
    this.width = const Value.absent(),
    this.height = const Value.absent(),
    this.shape = const Value.absent(),
    this.displayOrder = const Value.absent(),
    this.status = const Value.absent(),
  }) : floorId = Value(floorId);
  static Insertable<TableRow> custom({
    Expression<int>? id,
    Expression<int>? floorId,
    Expression<String>? label,
    Expression<int>? seats,
    Expression<int>? positionX,
    Expression<int>? positionY,
    Expression<int>? width,
    Expression<int>? height,
    Expression<String>? shape,
    Expression<int>? displayOrder,
    Expression<String>? status,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (floorId != null) 'floor_id': floorId,
      if (label != null) 'label': label,
      if (seats != null) 'seats': seats,
      if (positionX != null) 'position_x': positionX,
      if (positionY != null) 'position_y': positionY,
      if (width != null) 'width': width,
      if (height != null) 'height': height,
      if (shape != null) 'shape': shape,
      if (displayOrder != null) 'display_order': displayOrder,
      if (status != null) 'status': status,
    });
  }

  PosTablesCompanion copyWith({
    Value<int>? id,
    Value<int>? floorId,
    Value<String>? label,
    Value<int>? seats,
    Value<int?>? positionX,
    Value<int?>? positionY,
    Value<int?>? width,
    Value<int?>? height,
    Value<String?>? shape,
    Value<int>? displayOrder,
    Value<String?>? status,
  }) {
    return PosTablesCompanion(
      id: id ?? this.id,
      floorId: floorId ?? this.floorId,
      label: label ?? this.label,
      seats: seats ?? this.seats,
      positionX: positionX ?? this.positionX,
      positionY: positionY ?? this.positionY,
      width: width ?? this.width,
      height: height ?? this.height,
      shape: shape ?? this.shape,
      displayOrder: displayOrder ?? this.displayOrder,
      status: status ?? this.status,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (floorId.present) {
      map['floor_id'] = Variable<int>(floorId.value);
    }
    if (label.present) {
      map['label'] = Variable<String>(label.value);
    }
    if (seats.present) {
      map['seats'] = Variable<int>(seats.value);
    }
    if (positionX.present) {
      map['position_x'] = Variable<int>(positionX.value);
    }
    if (positionY.present) {
      map['position_y'] = Variable<int>(positionY.value);
    }
    if (width.present) {
      map['width'] = Variable<int>(width.value);
    }
    if (height.present) {
      map['height'] = Variable<int>(height.value);
    }
    if (shape.present) {
      map['shape'] = Variable<String>(shape.value);
    }
    if (displayOrder.present) {
      map['display_order'] = Variable<int>(displayOrder.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PosTablesCompanion(')
          ..write('id: $id, ')
          ..write('floorId: $floorId, ')
          ..write('label: $label, ')
          ..write('seats: $seats, ')
          ..write('positionX: $positionX, ')
          ..write('positionY: $positionY, ')
          ..write('width: $width, ')
          ..write('height: $height, ')
          ..write('shape: $shape, ')
          ..write('displayOrder: $displayOrder, ')
          ..write('status: $status')
          ..write(')'))
        .toString();
  }
}

class $AddonGroupsTable extends AddonGroups
    with TableInfo<$AddonGroupsTable, AddonGroupRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AddonGroupsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _nameArMeta = const VerificationMeta('nameAr');
  @override
  late final GeneratedColumn<String> nameAr = GeneratedColumn<String>(
    'name_ar',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _selectionModeMeta = const VerificationMeta(
    'selectionMode',
  );
  @override
  late final GeneratedColumn<String> selectionMode = GeneratedColumn<String>(
    'selection_mode',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _minSelectionsMeta = const VerificationMeta(
    'minSelections',
  );
  @override
  late final GeneratedColumn<int> minSelections = GeneratedColumn<int>(
    'min_selections',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _maxSelectionsMeta = const VerificationMeta(
    'maxSelections',
  );
  @override
  late final GeneratedColumn<int> maxSelections = GeneratedColumn<int>(
    'max_selections',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    nameAr,
    selectionMode,
    minSelections,
    maxSelections,
    status,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'addon_groups';
  @override
  VerificationContext validateIntegrity(
    Insertable<AddonGroupRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    }
    if (data.containsKey('name_ar')) {
      context.handle(
        _nameArMeta,
        nameAr.isAcceptableOrUnknown(data['name_ar']!, _nameArMeta),
      );
    }
    if (data.containsKey('selection_mode')) {
      context.handle(
        _selectionModeMeta,
        selectionMode.isAcceptableOrUnknown(
          data['selection_mode']!,
          _selectionModeMeta,
        ),
      );
    }
    if (data.containsKey('min_selections')) {
      context.handle(
        _minSelectionsMeta,
        minSelections.isAcceptableOrUnknown(
          data['min_selections']!,
          _minSelectionsMeta,
        ),
      );
    }
    if (data.containsKey('max_selections')) {
      context.handle(
        _maxSelectionsMeta,
        maxSelections.isAcceptableOrUnknown(
          data['max_selections']!,
          _maxSelectionsMeta,
        ),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AddonGroupRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AddonGroupRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      nameAr: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name_ar'],
      ),
      selectionMode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}selection_mode'],
      ),
      minSelections: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}min_selections'],
      ),
      maxSelections: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}max_selections'],
      ),
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      ),
    );
  }

  @override
  $AddonGroupsTable createAlias(String alias) {
    return $AddonGroupsTable(attachedDatabase, alias);
  }
}

class AddonGroupRow extends DataClass implements Insertable<AddonGroupRow> {
  final int id;
  final String name;
  final String? nameAr;
  final String? selectionMode;
  final int? minSelections;
  final int? maxSelections;
  final String? status;
  const AddonGroupRow({
    required this.id,
    required this.name,
    this.nameAr,
    this.selectionMode,
    this.minSelections,
    this.maxSelections,
    this.status,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || nameAr != null) {
      map['name_ar'] = Variable<String>(nameAr);
    }
    if (!nullToAbsent || selectionMode != null) {
      map['selection_mode'] = Variable<String>(selectionMode);
    }
    if (!nullToAbsent || minSelections != null) {
      map['min_selections'] = Variable<int>(minSelections);
    }
    if (!nullToAbsent || maxSelections != null) {
      map['max_selections'] = Variable<int>(maxSelections);
    }
    if (!nullToAbsent || status != null) {
      map['status'] = Variable<String>(status);
    }
    return map;
  }

  AddonGroupsCompanion toCompanion(bool nullToAbsent) {
    return AddonGroupsCompanion(
      id: Value(id),
      name: Value(name),
      nameAr: nameAr == null && nullToAbsent
          ? const Value.absent()
          : Value(nameAr),
      selectionMode: selectionMode == null && nullToAbsent
          ? const Value.absent()
          : Value(selectionMode),
      minSelections: minSelections == null && nullToAbsent
          ? const Value.absent()
          : Value(minSelections),
      maxSelections: maxSelections == null && nullToAbsent
          ? const Value.absent()
          : Value(maxSelections),
      status: status == null && nullToAbsent
          ? const Value.absent()
          : Value(status),
    );
  }

  factory AddonGroupRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AddonGroupRow(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      nameAr: serializer.fromJson<String?>(json['nameAr']),
      selectionMode: serializer.fromJson<String?>(json['selectionMode']),
      minSelections: serializer.fromJson<int?>(json['minSelections']),
      maxSelections: serializer.fromJson<int?>(json['maxSelections']),
      status: serializer.fromJson<String?>(json['status']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'nameAr': serializer.toJson<String?>(nameAr),
      'selectionMode': serializer.toJson<String?>(selectionMode),
      'minSelections': serializer.toJson<int?>(minSelections),
      'maxSelections': serializer.toJson<int?>(maxSelections),
      'status': serializer.toJson<String?>(status),
    };
  }

  AddonGroupRow copyWith({
    int? id,
    String? name,
    Value<String?> nameAr = const Value.absent(),
    Value<String?> selectionMode = const Value.absent(),
    Value<int?> minSelections = const Value.absent(),
    Value<int?> maxSelections = const Value.absent(),
    Value<String?> status = const Value.absent(),
  }) => AddonGroupRow(
    id: id ?? this.id,
    name: name ?? this.name,
    nameAr: nameAr.present ? nameAr.value : this.nameAr,
    selectionMode: selectionMode.present
        ? selectionMode.value
        : this.selectionMode,
    minSelections: minSelections.present
        ? minSelections.value
        : this.minSelections,
    maxSelections: maxSelections.present
        ? maxSelections.value
        : this.maxSelections,
    status: status.present ? status.value : this.status,
  );
  AddonGroupRow copyWithCompanion(AddonGroupsCompanion data) {
    return AddonGroupRow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      nameAr: data.nameAr.present ? data.nameAr.value : this.nameAr,
      selectionMode: data.selectionMode.present
          ? data.selectionMode.value
          : this.selectionMode,
      minSelections: data.minSelections.present
          ? data.minSelections.value
          : this.minSelections,
      maxSelections: data.maxSelections.present
          ? data.maxSelections.value
          : this.maxSelections,
      status: data.status.present ? data.status.value : this.status,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AddonGroupRow(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('nameAr: $nameAr, ')
          ..write('selectionMode: $selectionMode, ')
          ..write('minSelections: $minSelections, ')
          ..write('maxSelections: $maxSelections, ')
          ..write('status: $status')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    nameAr,
    selectionMode,
    minSelections,
    maxSelections,
    status,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AddonGroupRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.nameAr == this.nameAr &&
          other.selectionMode == this.selectionMode &&
          other.minSelections == this.minSelections &&
          other.maxSelections == this.maxSelections &&
          other.status == this.status);
}

class AddonGroupsCompanion extends UpdateCompanion<AddonGroupRow> {
  final Value<int> id;
  final Value<String> name;
  final Value<String?> nameAr;
  final Value<String?> selectionMode;
  final Value<int?> minSelections;
  final Value<int?> maxSelections;
  final Value<String?> status;
  const AddonGroupsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.nameAr = const Value.absent(),
    this.selectionMode = const Value.absent(),
    this.minSelections = const Value.absent(),
    this.maxSelections = const Value.absent(),
    this.status = const Value.absent(),
  });
  AddonGroupsCompanion.insert({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.nameAr = const Value.absent(),
    this.selectionMode = const Value.absent(),
    this.minSelections = const Value.absent(),
    this.maxSelections = const Value.absent(),
    this.status = const Value.absent(),
  });
  static Insertable<AddonGroupRow> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<String>? nameAr,
    Expression<String>? selectionMode,
    Expression<int>? minSelections,
    Expression<int>? maxSelections,
    Expression<String>? status,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (nameAr != null) 'name_ar': nameAr,
      if (selectionMode != null) 'selection_mode': selectionMode,
      if (minSelections != null) 'min_selections': minSelections,
      if (maxSelections != null) 'max_selections': maxSelections,
      if (status != null) 'status': status,
    });
  }

  AddonGroupsCompanion copyWith({
    Value<int>? id,
    Value<String>? name,
    Value<String?>? nameAr,
    Value<String?>? selectionMode,
    Value<int?>? minSelections,
    Value<int?>? maxSelections,
    Value<String?>? status,
  }) {
    return AddonGroupsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      nameAr: nameAr ?? this.nameAr,
      selectionMode: selectionMode ?? this.selectionMode,
      minSelections: minSelections ?? this.minSelections,
      maxSelections: maxSelections ?? this.maxSelections,
      status: status ?? this.status,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (nameAr.present) {
      map['name_ar'] = Variable<String>(nameAr.value);
    }
    if (selectionMode.present) {
      map['selection_mode'] = Variable<String>(selectionMode.value);
    }
    if (minSelections.present) {
      map['min_selections'] = Variable<int>(minSelections.value);
    }
    if (maxSelections.present) {
      map['max_selections'] = Variable<int>(maxSelections.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AddonGroupsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('nameAr: $nameAr, ')
          ..write('selectionMode: $selectionMode, ')
          ..write('minSelections: $minSelections, ')
          ..write('maxSelections: $maxSelections, ')
          ..write('status: $status')
          ..write(')'))
        .toString();
  }
}

class $AddonsTable extends Addons with TableInfo<$AddonsTable, AddonRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AddonsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _addOnGroupIdMeta = const VerificationMeta(
    'addOnGroupId',
  );
  @override
  late final GeneratedColumn<int> addOnGroupId = GeneratedColumn<int>(
    'add_on_group_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _nameArMeta = const VerificationMeta('nameAr');
  @override
  late final GeneratedColumn<String> nameAr = GeneratedColumn<String>(
    'name_ar',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _priceDeltaBaisasMeta = const VerificationMeta(
    'priceDeltaBaisas',
  );
  @override
  late final GeneratedColumn<int> priceDeltaBaisas = GeneratedColumn<int>(
    'price_delta_baisas',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _isDefaultMeta = const VerificationMeta(
    'isDefault',
  );
  @override
  late final GeneratedColumn<bool> isDefault = GeneratedColumn<bool>(
    'is_default',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_default" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _ingredientIdMeta = const VerificationMeta(
    'ingredientId',
  );
  @override
  late final GeneratedColumn<int> ingredientId = GeneratedColumn<int>(
    'ingredient_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _linkedProductIdMeta = const VerificationMeta(
    'linkedProductId',
  );
  @override
  late final GeneratedColumn<int> linkedProductId = GeneratedColumn<int>(
    'linked_product_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    addOnGroupId,
    name,
    nameAr,
    priceDeltaBaisas,
    isDefault,
    ingredientId,
    linkedProductId,
    status,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'addons';
  @override
  VerificationContext validateIntegrity(
    Insertable<AddonRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('add_on_group_id')) {
      context.handle(
        _addOnGroupIdMeta,
        addOnGroupId.isAcceptableOrUnknown(
          data['add_on_group_id']!,
          _addOnGroupIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_addOnGroupIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    }
    if (data.containsKey('name_ar')) {
      context.handle(
        _nameArMeta,
        nameAr.isAcceptableOrUnknown(data['name_ar']!, _nameArMeta),
      );
    }
    if (data.containsKey('price_delta_baisas')) {
      context.handle(
        _priceDeltaBaisasMeta,
        priceDeltaBaisas.isAcceptableOrUnknown(
          data['price_delta_baisas']!,
          _priceDeltaBaisasMeta,
        ),
      );
    }
    if (data.containsKey('is_default')) {
      context.handle(
        _isDefaultMeta,
        isDefault.isAcceptableOrUnknown(data['is_default']!, _isDefaultMeta),
      );
    }
    if (data.containsKey('ingredient_id')) {
      context.handle(
        _ingredientIdMeta,
        ingredientId.isAcceptableOrUnknown(
          data['ingredient_id']!,
          _ingredientIdMeta,
        ),
      );
    }
    if (data.containsKey('linked_product_id')) {
      context.handle(
        _linkedProductIdMeta,
        linkedProductId.isAcceptableOrUnknown(
          data['linked_product_id']!,
          _linkedProductIdMeta,
        ),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AddonRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AddonRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      addOnGroupId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}add_on_group_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      nameAr: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name_ar'],
      ),
      priceDeltaBaisas: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}price_delta_baisas'],
      )!,
      isDefault: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_default'],
      )!,
      ingredientId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}ingredient_id'],
      ),
      linkedProductId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}linked_product_id'],
      ),
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      ),
    );
  }

  @override
  $AddonsTable createAlias(String alias) {
    return $AddonsTable(attachedDatabase, alias);
  }
}

class AddonRow extends DataClass implements Insertable<AddonRow> {
  final int id;
  final int addOnGroupId;
  final String name;
  final String? nameAr;
  final int priceDeltaBaisas;
  final bool isDefault;
  final int? ingredientId;
  final int? linkedProductId;
  final String? status;
  const AddonRow({
    required this.id,
    required this.addOnGroupId,
    required this.name,
    this.nameAr,
    required this.priceDeltaBaisas,
    required this.isDefault,
    this.ingredientId,
    this.linkedProductId,
    this.status,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['add_on_group_id'] = Variable<int>(addOnGroupId);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || nameAr != null) {
      map['name_ar'] = Variable<String>(nameAr);
    }
    map['price_delta_baisas'] = Variable<int>(priceDeltaBaisas);
    map['is_default'] = Variable<bool>(isDefault);
    if (!nullToAbsent || ingredientId != null) {
      map['ingredient_id'] = Variable<int>(ingredientId);
    }
    if (!nullToAbsent || linkedProductId != null) {
      map['linked_product_id'] = Variable<int>(linkedProductId);
    }
    if (!nullToAbsent || status != null) {
      map['status'] = Variable<String>(status);
    }
    return map;
  }

  AddonsCompanion toCompanion(bool nullToAbsent) {
    return AddonsCompanion(
      id: Value(id),
      addOnGroupId: Value(addOnGroupId),
      name: Value(name),
      nameAr: nameAr == null && nullToAbsent
          ? const Value.absent()
          : Value(nameAr),
      priceDeltaBaisas: Value(priceDeltaBaisas),
      isDefault: Value(isDefault),
      ingredientId: ingredientId == null && nullToAbsent
          ? const Value.absent()
          : Value(ingredientId),
      linkedProductId: linkedProductId == null && nullToAbsent
          ? const Value.absent()
          : Value(linkedProductId),
      status: status == null && nullToAbsent
          ? const Value.absent()
          : Value(status),
    );
  }

  factory AddonRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AddonRow(
      id: serializer.fromJson<int>(json['id']),
      addOnGroupId: serializer.fromJson<int>(json['addOnGroupId']),
      name: serializer.fromJson<String>(json['name']),
      nameAr: serializer.fromJson<String?>(json['nameAr']),
      priceDeltaBaisas: serializer.fromJson<int>(json['priceDeltaBaisas']),
      isDefault: serializer.fromJson<bool>(json['isDefault']),
      ingredientId: serializer.fromJson<int?>(json['ingredientId']),
      linkedProductId: serializer.fromJson<int?>(json['linkedProductId']),
      status: serializer.fromJson<String?>(json['status']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'addOnGroupId': serializer.toJson<int>(addOnGroupId),
      'name': serializer.toJson<String>(name),
      'nameAr': serializer.toJson<String?>(nameAr),
      'priceDeltaBaisas': serializer.toJson<int>(priceDeltaBaisas),
      'isDefault': serializer.toJson<bool>(isDefault),
      'ingredientId': serializer.toJson<int?>(ingredientId),
      'linkedProductId': serializer.toJson<int?>(linkedProductId),
      'status': serializer.toJson<String?>(status),
    };
  }

  AddonRow copyWith({
    int? id,
    int? addOnGroupId,
    String? name,
    Value<String?> nameAr = const Value.absent(),
    int? priceDeltaBaisas,
    bool? isDefault,
    Value<int?> ingredientId = const Value.absent(),
    Value<int?> linkedProductId = const Value.absent(),
    Value<String?> status = const Value.absent(),
  }) => AddonRow(
    id: id ?? this.id,
    addOnGroupId: addOnGroupId ?? this.addOnGroupId,
    name: name ?? this.name,
    nameAr: nameAr.present ? nameAr.value : this.nameAr,
    priceDeltaBaisas: priceDeltaBaisas ?? this.priceDeltaBaisas,
    isDefault: isDefault ?? this.isDefault,
    ingredientId: ingredientId.present ? ingredientId.value : this.ingredientId,
    linkedProductId: linkedProductId.present
        ? linkedProductId.value
        : this.linkedProductId,
    status: status.present ? status.value : this.status,
  );
  AddonRow copyWithCompanion(AddonsCompanion data) {
    return AddonRow(
      id: data.id.present ? data.id.value : this.id,
      addOnGroupId: data.addOnGroupId.present
          ? data.addOnGroupId.value
          : this.addOnGroupId,
      name: data.name.present ? data.name.value : this.name,
      nameAr: data.nameAr.present ? data.nameAr.value : this.nameAr,
      priceDeltaBaisas: data.priceDeltaBaisas.present
          ? data.priceDeltaBaisas.value
          : this.priceDeltaBaisas,
      isDefault: data.isDefault.present ? data.isDefault.value : this.isDefault,
      ingredientId: data.ingredientId.present
          ? data.ingredientId.value
          : this.ingredientId,
      linkedProductId: data.linkedProductId.present
          ? data.linkedProductId.value
          : this.linkedProductId,
      status: data.status.present ? data.status.value : this.status,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AddonRow(')
          ..write('id: $id, ')
          ..write('addOnGroupId: $addOnGroupId, ')
          ..write('name: $name, ')
          ..write('nameAr: $nameAr, ')
          ..write('priceDeltaBaisas: $priceDeltaBaisas, ')
          ..write('isDefault: $isDefault, ')
          ..write('ingredientId: $ingredientId, ')
          ..write('linkedProductId: $linkedProductId, ')
          ..write('status: $status')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    addOnGroupId,
    name,
    nameAr,
    priceDeltaBaisas,
    isDefault,
    ingredientId,
    linkedProductId,
    status,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AddonRow &&
          other.id == this.id &&
          other.addOnGroupId == this.addOnGroupId &&
          other.name == this.name &&
          other.nameAr == this.nameAr &&
          other.priceDeltaBaisas == this.priceDeltaBaisas &&
          other.isDefault == this.isDefault &&
          other.ingredientId == this.ingredientId &&
          other.linkedProductId == this.linkedProductId &&
          other.status == this.status);
}

class AddonsCompanion extends UpdateCompanion<AddonRow> {
  final Value<int> id;
  final Value<int> addOnGroupId;
  final Value<String> name;
  final Value<String?> nameAr;
  final Value<int> priceDeltaBaisas;
  final Value<bool> isDefault;
  final Value<int?> ingredientId;
  final Value<int?> linkedProductId;
  final Value<String?> status;
  const AddonsCompanion({
    this.id = const Value.absent(),
    this.addOnGroupId = const Value.absent(),
    this.name = const Value.absent(),
    this.nameAr = const Value.absent(),
    this.priceDeltaBaisas = const Value.absent(),
    this.isDefault = const Value.absent(),
    this.ingredientId = const Value.absent(),
    this.linkedProductId = const Value.absent(),
    this.status = const Value.absent(),
  });
  AddonsCompanion.insert({
    this.id = const Value.absent(),
    required int addOnGroupId,
    this.name = const Value.absent(),
    this.nameAr = const Value.absent(),
    this.priceDeltaBaisas = const Value.absent(),
    this.isDefault = const Value.absent(),
    this.ingredientId = const Value.absent(),
    this.linkedProductId = const Value.absent(),
    this.status = const Value.absent(),
  }) : addOnGroupId = Value(addOnGroupId);
  static Insertable<AddonRow> custom({
    Expression<int>? id,
    Expression<int>? addOnGroupId,
    Expression<String>? name,
    Expression<String>? nameAr,
    Expression<int>? priceDeltaBaisas,
    Expression<bool>? isDefault,
    Expression<int>? ingredientId,
    Expression<int>? linkedProductId,
    Expression<String>? status,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (addOnGroupId != null) 'add_on_group_id': addOnGroupId,
      if (name != null) 'name': name,
      if (nameAr != null) 'name_ar': nameAr,
      if (priceDeltaBaisas != null) 'price_delta_baisas': priceDeltaBaisas,
      if (isDefault != null) 'is_default': isDefault,
      if (ingredientId != null) 'ingredient_id': ingredientId,
      if (linkedProductId != null) 'linked_product_id': linkedProductId,
      if (status != null) 'status': status,
    });
  }

  AddonsCompanion copyWith({
    Value<int>? id,
    Value<int>? addOnGroupId,
    Value<String>? name,
    Value<String?>? nameAr,
    Value<int>? priceDeltaBaisas,
    Value<bool>? isDefault,
    Value<int?>? ingredientId,
    Value<int?>? linkedProductId,
    Value<String?>? status,
  }) {
    return AddonsCompanion(
      id: id ?? this.id,
      addOnGroupId: addOnGroupId ?? this.addOnGroupId,
      name: name ?? this.name,
      nameAr: nameAr ?? this.nameAr,
      priceDeltaBaisas: priceDeltaBaisas ?? this.priceDeltaBaisas,
      isDefault: isDefault ?? this.isDefault,
      ingredientId: ingredientId ?? this.ingredientId,
      linkedProductId: linkedProductId ?? this.linkedProductId,
      status: status ?? this.status,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (addOnGroupId.present) {
      map['add_on_group_id'] = Variable<int>(addOnGroupId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (nameAr.present) {
      map['name_ar'] = Variable<String>(nameAr.value);
    }
    if (priceDeltaBaisas.present) {
      map['price_delta_baisas'] = Variable<int>(priceDeltaBaisas.value);
    }
    if (isDefault.present) {
      map['is_default'] = Variable<bool>(isDefault.value);
    }
    if (ingredientId.present) {
      map['ingredient_id'] = Variable<int>(ingredientId.value);
    }
    if (linkedProductId.present) {
      map['linked_product_id'] = Variable<int>(linkedProductId.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AddonsCompanion(')
          ..write('id: $id, ')
          ..write('addOnGroupId: $addOnGroupId, ')
          ..write('name: $name, ')
          ..write('nameAr: $nameAr, ')
          ..write('priceDeltaBaisas: $priceDeltaBaisas, ')
          ..write('isDefault: $isDefault, ')
          ..write('ingredientId: $ingredientId, ')
          ..write('linkedProductId: $linkedProductId, ')
          ..write('status: $status')
          ..write(')'))
        .toString();
  }
}

class $TaxCacheTable extends TaxCache with TableInfo<$TaxCacheTable, TaxRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TaxCacheTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _nameArMeta = const VerificationMeta('nameAr');
  @override
  late final GeneratedColumn<String> nameAr = GeneratedColumn<String>(
    'name_ar',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _ratePercentMeta = const VerificationMeta(
    'ratePercent',
  );
  @override
  late final GeneratedColumn<double> ratePercent = GeneratedColumn<double>(
    'rate_percent',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [id, name, nameAr, ratePercent];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'tax_cache';
  @override
  VerificationContext validateIntegrity(
    Insertable<TaxRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    }
    if (data.containsKey('name_ar')) {
      context.handle(
        _nameArMeta,
        nameAr.isAcceptableOrUnknown(data['name_ar']!, _nameArMeta),
      );
    }
    if (data.containsKey('rate_percent')) {
      context.handle(
        _ratePercentMeta,
        ratePercent.isAcceptableOrUnknown(
          data['rate_percent']!,
          _ratePercentMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TaxRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TaxRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      nameAr: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name_ar'],
      ),
      ratePercent: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}rate_percent'],
      )!,
    );
  }

  @override
  $TaxCacheTable createAlias(String alias) {
    return $TaxCacheTable(attachedDatabase, alias);
  }
}

class TaxRow extends DataClass implements Insertable<TaxRow> {
  final int id;
  final String name;
  final String? nameAr;
  final double ratePercent;
  const TaxRow({
    required this.id,
    required this.name,
    this.nameAr,
    required this.ratePercent,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || nameAr != null) {
      map['name_ar'] = Variable<String>(nameAr);
    }
    map['rate_percent'] = Variable<double>(ratePercent);
    return map;
  }

  TaxCacheCompanion toCompanion(bool nullToAbsent) {
    return TaxCacheCompanion(
      id: Value(id),
      name: Value(name),
      nameAr: nameAr == null && nullToAbsent
          ? const Value.absent()
          : Value(nameAr),
      ratePercent: Value(ratePercent),
    );
  }

  factory TaxRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TaxRow(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      nameAr: serializer.fromJson<String?>(json['nameAr']),
      ratePercent: serializer.fromJson<double>(json['ratePercent']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'nameAr': serializer.toJson<String?>(nameAr),
      'ratePercent': serializer.toJson<double>(ratePercent),
    };
  }

  TaxRow copyWith({
    int? id,
    String? name,
    Value<String?> nameAr = const Value.absent(),
    double? ratePercent,
  }) => TaxRow(
    id: id ?? this.id,
    name: name ?? this.name,
    nameAr: nameAr.present ? nameAr.value : this.nameAr,
    ratePercent: ratePercent ?? this.ratePercent,
  );
  TaxRow copyWithCompanion(TaxCacheCompanion data) {
    return TaxRow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      nameAr: data.nameAr.present ? data.nameAr.value : this.nameAr,
      ratePercent: data.ratePercent.present
          ? data.ratePercent.value
          : this.ratePercent,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TaxRow(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('nameAr: $nameAr, ')
          ..write('ratePercent: $ratePercent')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, nameAr, ratePercent);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TaxRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.nameAr == this.nameAr &&
          other.ratePercent == this.ratePercent);
}

class TaxCacheCompanion extends UpdateCompanion<TaxRow> {
  final Value<int> id;
  final Value<String> name;
  final Value<String?> nameAr;
  final Value<double> ratePercent;
  const TaxCacheCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.nameAr = const Value.absent(),
    this.ratePercent = const Value.absent(),
  });
  TaxCacheCompanion.insert({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.nameAr = const Value.absent(),
    this.ratePercent = const Value.absent(),
  });
  static Insertable<TaxRow> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<String>? nameAr,
    Expression<double>? ratePercent,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (nameAr != null) 'name_ar': nameAr,
      if (ratePercent != null) 'rate_percent': ratePercent,
    });
  }

  TaxCacheCompanion copyWith({
    Value<int>? id,
    Value<String>? name,
    Value<String?>? nameAr,
    Value<double>? ratePercent,
  }) {
    return TaxCacheCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      nameAr: nameAr ?? this.nameAr,
      ratePercent: ratePercent ?? this.ratePercent,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (nameAr.present) {
      map['name_ar'] = Variable<String>(nameAr.value);
    }
    if (ratePercent.present) {
      map['rate_percent'] = Variable<double>(ratePercent.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TaxCacheCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('nameAr: $nameAr, ')
          ..write('ratePercent: $ratePercent')
          ..write(')'))
        .toString();
  }
}

class $SyncMetaTable extends SyncMeta
    with TableInfo<$SyncMetaTable, SyncMetaRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncMetaTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _companyIdMeta = const VerificationMeta(
    'companyId',
  );
  @override
  late final GeneratedColumn<int> companyId = GeneratedColumn<int>(
    'company_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _branchIdMeta = const VerificationMeta(
    'branchId',
  );
  @override
  late final GeneratedColumn<int> branchId = GeneratedColumn<int>(
    'branch_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastConfigSyncAtMeta = const VerificationMeta(
    'lastConfigSyncAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastConfigSyncAt =
      GeneratedColumn<DateTime>(
        'last_config_sync_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _configSchemaVersionMeta =
      const VerificationMeta('configSchemaVersion');
  @override
  late final GeneratedColumn<String> configSchemaVersion =
      GeneratedColumn<String>(
        'config_schema_version',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _orderCancelPositionsMeta =
      const VerificationMeta('orderCancelPositions');
  @override
  late final GeneratedColumn<String> orderCancelPositions =
      GeneratedColumn<String>(
        'order_cancel_positions',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _reportsPositionsMeta = const VerificationMeta(
    'reportsPositions',
  );
  @override
  late final GeneratedColumn<String> reportsPositions = GeneratedColumn<String>(
    'reports_positions',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _kitchenPositionsMeta = const VerificationMeta(
    'kitchenPositions',
  );
  @override
  late final GeneratedColumn<String> kitchenPositions = GeneratedColumn<String>(
    'kitchen_positions',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _orderNumberingJsonMeta =
      const VerificationMeta('orderNumberingJson');
  @override
  late final GeneratedColumn<String> orderNumberingJson =
      GeneratedColumn<String>(
        'order_numbering_json',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    companyId,
    branchId,
    lastConfigSyncAt,
    configSchemaVersion,
    orderCancelPositions,
    reportsPositions,
    kitchenPositions,
    orderNumberingJson,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_meta';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncMetaRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('company_id')) {
      context.handle(
        _companyIdMeta,
        companyId.isAcceptableOrUnknown(data['company_id']!, _companyIdMeta),
      );
    }
    if (data.containsKey('branch_id')) {
      context.handle(
        _branchIdMeta,
        branchId.isAcceptableOrUnknown(data['branch_id']!, _branchIdMeta),
      );
    }
    if (data.containsKey('last_config_sync_at')) {
      context.handle(
        _lastConfigSyncAtMeta,
        lastConfigSyncAt.isAcceptableOrUnknown(
          data['last_config_sync_at']!,
          _lastConfigSyncAtMeta,
        ),
      );
    }
    if (data.containsKey('config_schema_version')) {
      context.handle(
        _configSchemaVersionMeta,
        configSchemaVersion.isAcceptableOrUnknown(
          data['config_schema_version']!,
          _configSchemaVersionMeta,
        ),
      );
    }
    if (data.containsKey('order_cancel_positions')) {
      context.handle(
        _orderCancelPositionsMeta,
        orderCancelPositions.isAcceptableOrUnknown(
          data['order_cancel_positions']!,
          _orderCancelPositionsMeta,
        ),
      );
    }
    if (data.containsKey('reports_positions')) {
      context.handle(
        _reportsPositionsMeta,
        reportsPositions.isAcceptableOrUnknown(
          data['reports_positions']!,
          _reportsPositionsMeta,
        ),
      );
    }
    if (data.containsKey('kitchen_positions')) {
      context.handle(
        _kitchenPositionsMeta,
        kitchenPositions.isAcceptableOrUnknown(
          data['kitchen_positions']!,
          _kitchenPositionsMeta,
        ),
      );
    }
    if (data.containsKey('order_numbering_json')) {
      context.handle(
        _orderNumberingJsonMeta,
        orderNumberingJson.isAcceptableOrUnknown(
          data['order_numbering_json']!,
          _orderNumberingJsonMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SyncMetaRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncMetaRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      companyId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}company_id'],
      ),
      branchId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}branch_id'],
      ),
      lastConfigSyncAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_config_sync_at'],
      ),
      configSchemaVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}config_schema_version'],
      ),
      orderCancelPositions: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}order_cancel_positions'],
      ),
      reportsPositions: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reports_positions'],
      ),
      kitchenPositions: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kitchen_positions'],
      ),
      orderNumberingJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}order_numbering_json'],
      ),
    );
  }

  @override
  $SyncMetaTable createAlias(String alias) {
    return $SyncMetaTable(attachedDatabase, alias);
  }
}

class SyncMetaRow extends DataClass implements Insertable<SyncMetaRow> {
  final int id;
  final int? companyId;
  final int? branchId;
  final DateTime? lastConfigSyncAt;
  final String? configSchemaVersion;
  final String? orderCancelPositions;
  final String? reportsPositions;
  final String? kitchenPositions;
  final String? orderNumberingJson;
  const SyncMetaRow({
    required this.id,
    this.companyId,
    this.branchId,
    this.lastConfigSyncAt,
    this.configSchemaVersion,
    this.orderCancelPositions,
    this.reportsPositions,
    this.kitchenPositions,
    this.orderNumberingJson,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    if (!nullToAbsent || companyId != null) {
      map['company_id'] = Variable<int>(companyId);
    }
    if (!nullToAbsent || branchId != null) {
      map['branch_id'] = Variable<int>(branchId);
    }
    if (!nullToAbsent || lastConfigSyncAt != null) {
      map['last_config_sync_at'] = Variable<DateTime>(lastConfigSyncAt);
    }
    if (!nullToAbsent || configSchemaVersion != null) {
      map['config_schema_version'] = Variable<String>(configSchemaVersion);
    }
    if (!nullToAbsent || orderCancelPositions != null) {
      map['order_cancel_positions'] = Variable<String>(orderCancelPositions);
    }
    if (!nullToAbsent || reportsPositions != null) {
      map['reports_positions'] = Variable<String>(reportsPositions);
    }
    if (!nullToAbsent || kitchenPositions != null) {
      map['kitchen_positions'] = Variable<String>(kitchenPositions);
    }
    if (!nullToAbsent || orderNumberingJson != null) {
      map['order_numbering_json'] = Variable<String>(orderNumberingJson);
    }
    return map;
  }

  SyncMetaCompanion toCompanion(bool nullToAbsent) {
    return SyncMetaCompanion(
      id: Value(id),
      companyId: companyId == null && nullToAbsent
          ? const Value.absent()
          : Value(companyId),
      branchId: branchId == null && nullToAbsent
          ? const Value.absent()
          : Value(branchId),
      lastConfigSyncAt: lastConfigSyncAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastConfigSyncAt),
      configSchemaVersion: configSchemaVersion == null && nullToAbsent
          ? const Value.absent()
          : Value(configSchemaVersion),
      orderCancelPositions: orderCancelPositions == null && nullToAbsent
          ? const Value.absent()
          : Value(orderCancelPositions),
      reportsPositions: reportsPositions == null && nullToAbsent
          ? const Value.absent()
          : Value(reportsPositions),
      kitchenPositions: kitchenPositions == null && nullToAbsent
          ? const Value.absent()
          : Value(kitchenPositions),
      orderNumberingJson: orderNumberingJson == null && nullToAbsent
          ? const Value.absent()
          : Value(orderNumberingJson),
    );
  }

  factory SyncMetaRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncMetaRow(
      id: serializer.fromJson<int>(json['id']),
      companyId: serializer.fromJson<int?>(json['companyId']),
      branchId: serializer.fromJson<int?>(json['branchId']),
      lastConfigSyncAt: serializer.fromJson<DateTime?>(
        json['lastConfigSyncAt'],
      ),
      configSchemaVersion: serializer.fromJson<String?>(
        json['configSchemaVersion'],
      ),
      orderCancelPositions: serializer.fromJson<String?>(
        json['orderCancelPositions'],
      ),
      reportsPositions: serializer.fromJson<String?>(json['reportsPositions']),
      kitchenPositions: serializer.fromJson<String?>(json['kitchenPositions']),
      orderNumberingJson: serializer.fromJson<String?>(
        json['orderNumberingJson'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'companyId': serializer.toJson<int?>(companyId),
      'branchId': serializer.toJson<int?>(branchId),
      'lastConfigSyncAt': serializer.toJson<DateTime?>(lastConfigSyncAt),
      'configSchemaVersion': serializer.toJson<String?>(configSchemaVersion),
      'orderCancelPositions': serializer.toJson<String?>(orderCancelPositions),
      'reportsPositions': serializer.toJson<String?>(reportsPositions),
      'kitchenPositions': serializer.toJson<String?>(kitchenPositions),
      'orderNumberingJson': serializer.toJson<String?>(orderNumberingJson),
    };
  }

  SyncMetaRow copyWith({
    int? id,
    Value<int?> companyId = const Value.absent(),
    Value<int?> branchId = const Value.absent(),
    Value<DateTime?> lastConfigSyncAt = const Value.absent(),
    Value<String?> configSchemaVersion = const Value.absent(),
    Value<String?> orderCancelPositions = const Value.absent(),
    Value<String?> reportsPositions = const Value.absent(),
    Value<String?> kitchenPositions = const Value.absent(),
    Value<String?> orderNumberingJson = const Value.absent(),
  }) => SyncMetaRow(
    id: id ?? this.id,
    companyId: companyId.present ? companyId.value : this.companyId,
    branchId: branchId.present ? branchId.value : this.branchId,
    lastConfigSyncAt: lastConfigSyncAt.present
        ? lastConfigSyncAt.value
        : this.lastConfigSyncAt,
    configSchemaVersion: configSchemaVersion.present
        ? configSchemaVersion.value
        : this.configSchemaVersion,
    orderCancelPositions: orderCancelPositions.present
        ? orderCancelPositions.value
        : this.orderCancelPositions,
    reportsPositions: reportsPositions.present
        ? reportsPositions.value
        : this.reportsPositions,
    kitchenPositions: kitchenPositions.present
        ? kitchenPositions.value
        : this.kitchenPositions,
    orderNumberingJson: orderNumberingJson.present
        ? orderNumberingJson.value
        : this.orderNumberingJson,
  );
  SyncMetaRow copyWithCompanion(SyncMetaCompanion data) {
    return SyncMetaRow(
      id: data.id.present ? data.id.value : this.id,
      companyId: data.companyId.present ? data.companyId.value : this.companyId,
      branchId: data.branchId.present ? data.branchId.value : this.branchId,
      lastConfigSyncAt: data.lastConfigSyncAt.present
          ? data.lastConfigSyncAt.value
          : this.lastConfigSyncAt,
      configSchemaVersion: data.configSchemaVersion.present
          ? data.configSchemaVersion.value
          : this.configSchemaVersion,
      orderCancelPositions: data.orderCancelPositions.present
          ? data.orderCancelPositions.value
          : this.orderCancelPositions,
      reportsPositions: data.reportsPositions.present
          ? data.reportsPositions.value
          : this.reportsPositions,
      kitchenPositions: data.kitchenPositions.present
          ? data.kitchenPositions.value
          : this.kitchenPositions,
      orderNumberingJson: data.orderNumberingJson.present
          ? data.orderNumberingJson.value
          : this.orderNumberingJson,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncMetaRow(')
          ..write('id: $id, ')
          ..write('companyId: $companyId, ')
          ..write('branchId: $branchId, ')
          ..write('lastConfigSyncAt: $lastConfigSyncAt, ')
          ..write('configSchemaVersion: $configSchemaVersion, ')
          ..write('orderCancelPositions: $orderCancelPositions, ')
          ..write('reportsPositions: $reportsPositions, ')
          ..write('kitchenPositions: $kitchenPositions, ')
          ..write('orderNumberingJson: $orderNumberingJson')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    companyId,
    branchId,
    lastConfigSyncAt,
    configSchemaVersion,
    orderCancelPositions,
    reportsPositions,
    kitchenPositions,
    orderNumberingJson,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncMetaRow &&
          other.id == this.id &&
          other.companyId == this.companyId &&
          other.branchId == this.branchId &&
          other.lastConfigSyncAt == this.lastConfigSyncAt &&
          other.configSchemaVersion == this.configSchemaVersion &&
          other.orderCancelPositions == this.orderCancelPositions &&
          other.reportsPositions == this.reportsPositions &&
          other.kitchenPositions == this.kitchenPositions &&
          other.orderNumberingJson == this.orderNumberingJson);
}

class SyncMetaCompanion extends UpdateCompanion<SyncMetaRow> {
  final Value<int> id;
  final Value<int?> companyId;
  final Value<int?> branchId;
  final Value<DateTime?> lastConfigSyncAt;
  final Value<String?> configSchemaVersion;
  final Value<String?> orderCancelPositions;
  final Value<String?> reportsPositions;
  final Value<String?> kitchenPositions;
  final Value<String?> orderNumberingJson;
  const SyncMetaCompanion({
    this.id = const Value.absent(),
    this.companyId = const Value.absent(),
    this.branchId = const Value.absent(),
    this.lastConfigSyncAt = const Value.absent(),
    this.configSchemaVersion = const Value.absent(),
    this.orderCancelPositions = const Value.absent(),
    this.reportsPositions = const Value.absent(),
    this.kitchenPositions = const Value.absent(),
    this.orderNumberingJson = const Value.absent(),
  });
  SyncMetaCompanion.insert({
    this.id = const Value.absent(),
    this.companyId = const Value.absent(),
    this.branchId = const Value.absent(),
    this.lastConfigSyncAt = const Value.absent(),
    this.configSchemaVersion = const Value.absent(),
    this.orderCancelPositions = const Value.absent(),
    this.reportsPositions = const Value.absent(),
    this.kitchenPositions = const Value.absent(),
    this.orderNumberingJson = const Value.absent(),
  });
  static Insertable<SyncMetaRow> custom({
    Expression<int>? id,
    Expression<int>? companyId,
    Expression<int>? branchId,
    Expression<DateTime>? lastConfigSyncAt,
    Expression<String>? configSchemaVersion,
    Expression<String>? orderCancelPositions,
    Expression<String>? reportsPositions,
    Expression<String>? kitchenPositions,
    Expression<String>? orderNumberingJson,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (companyId != null) 'company_id': companyId,
      if (branchId != null) 'branch_id': branchId,
      if (lastConfigSyncAt != null) 'last_config_sync_at': lastConfigSyncAt,
      if (configSchemaVersion != null)
        'config_schema_version': configSchemaVersion,
      if (orderCancelPositions != null)
        'order_cancel_positions': orderCancelPositions,
      if (reportsPositions != null) 'reports_positions': reportsPositions,
      if (kitchenPositions != null) 'kitchen_positions': kitchenPositions,
      if (orderNumberingJson != null)
        'order_numbering_json': orderNumberingJson,
    });
  }

  SyncMetaCompanion copyWith({
    Value<int>? id,
    Value<int?>? companyId,
    Value<int?>? branchId,
    Value<DateTime?>? lastConfigSyncAt,
    Value<String?>? configSchemaVersion,
    Value<String?>? orderCancelPositions,
    Value<String?>? reportsPositions,
    Value<String?>? kitchenPositions,
    Value<String?>? orderNumberingJson,
  }) {
    return SyncMetaCompanion(
      id: id ?? this.id,
      companyId: companyId ?? this.companyId,
      branchId: branchId ?? this.branchId,
      lastConfigSyncAt: lastConfigSyncAt ?? this.lastConfigSyncAt,
      configSchemaVersion: configSchemaVersion ?? this.configSchemaVersion,
      orderCancelPositions: orderCancelPositions ?? this.orderCancelPositions,
      reportsPositions: reportsPositions ?? this.reportsPositions,
      kitchenPositions: kitchenPositions ?? this.kitchenPositions,
      orderNumberingJson: orderNumberingJson ?? this.orderNumberingJson,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (companyId.present) {
      map['company_id'] = Variable<int>(companyId.value);
    }
    if (branchId.present) {
      map['branch_id'] = Variable<int>(branchId.value);
    }
    if (lastConfigSyncAt.present) {
      map['last_config_sync_at'] = Variable<DateTime>(lastConfigSyncAt.value);
    }
    if (configSchemaVersion.present) {
      map['config_schema_version'] = Variable<String>(
        configSchemaVersion.value,
      );
    }
    if (orderCancelPositions.present) {
      map['order_cancel_positions'] = Variable<String>(
        orderCancelPositions.value,
      );
    }
    if (reportsPositions.present) {
      map['reports_positions'] = Variable<String>(reportsPositions.value);
    }
    if (kitchenPositions.present) {
      map['kitchen_positions'] = Variable<String>(kitchenPositions.value);
    }
    if (orderNumberingJson.present) {
      map['order_numbering_json'] = Variable<String>(orderNumberingJson.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncMetaCompanion(')
          ..write('id: $id, ')
          ..write('companyId: $companyId, ')
          ..write('branchId: $branchId, ')
          ..write('lastConfigSyncAt: $lastConfigSyncAt, ')
          ..write('configSchemaVersion: $configSchemaVersion, ')
          ..write('orderCancelPositions: $orderCancelPositions, ')
          ..write('reportsPositions: $reportsPositions, ')
          ..write('kitchenPositions: $kitchenPositions, ')
          ..write('orderNumberingJson: $orderNumberingJson')
          ..write(')'))
        .toString();
  }
}

class $OrderOutboxTable extends OrderOutbox
    with TableInfo<$OrderOutboxTable, OrderOutboxRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OrderOutboxTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _orderUuidMeta = const VerificationMeta(
    'orderUuid',
  );
  @override
  late final GeneratedColumn<String> orderUuid = GeneratedColumn<String>(
    'order_uuid',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _eventsJsonMeta = const VerificationMeta(
    'eventsJson',
  );
  @override
  late final GeneratedColumn<String> eventsJson = GeneratedColumn<String>(
    'events_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _orderNumberMeta = const VerificationMeta(
    'orderNumber',
  );
  @override
  late final GeneratedColumn<int> orderNumber = GeneratedColumn<int>(
    'order_number',
    aliasedName,
    true,
    type: DriftSqlType.int,
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
  static const VerificationMeta _syncedAtMeta = const VerificationMeta(
    'syncedAt',
  );
  @override
  late final GeneratedColumn<DateTime> syncedAt = GeneratedColumn<DateTime>(
    'synced_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    orderUuid,
    eventsJson,
    orderNumber,
    createdAt,
    attempts,
    lastError,
    syncedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'order_outbox';
  @override
  VerificationContext validateIntegrity(
    Insertable<OrderOutboxRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('order_uuid')) {
      context.handle(
        _orderUuidMeta,
        orderUuid.isAcceptableOrUnknown(data['order_uuid']!, _orderUuidMeta),
      );
    } else if (isInserting) {
      context.missing(_orderUuidMeta);
    }
    if (data.containsKey('events_json')) {
      context.handle(
        _eventsJsonMeta,
        eventsJson.isAcceptableOrUnknown(data['events_json']!, _eventsJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_eventsJsonMeta);
    }
    if (data.containsKey('order_number')) {
      context.handle(
        _orderNumberMeta,
        orderNumber.isAcceptableOrUnknown(
          data['order_number']!,
          _orderNumberMeta,
        ),
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
    if (data.containsKey('synced_at')) {
      context.handle(
        _syncedAtMeta,
        syncedAt.isAcceptableOrUnknown(data['synced_at']!, _syncedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {orderUuid};
  @override
  OrderOutboxRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OrderOutboxRow(
      orderUuid: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}order_uuid'],
      )!,
      eventsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}events_json'],
      )!,
      orderNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}order_number'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      attempts: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempts'],
      )!,
      lastError: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error'],
      ),
      syncedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}synced_at'],
      ),
    );
  }

  @override
  $OrderOutboxTable createAlias(String alias) {
    return $OrderOutboxTable(attachedDatabase, alias);
  }
}

class OrderOutboxRow extends DataClass implements Insertable<OrderOutboxRow> {
  final String orderUuid;
  final String eventsJson;
  final int? orderNumber;
  final DateTime createdAt;
  final int attempts;
  final String? lastError;
  final DateTime? syncedAt;
  const OrderOutboxRow({
    required this.orderUuid,
    required this.eventsJson,
    this.orderNumber,
    required this.createdAt,
    required this.attempts,
    this.lastError,
    this.syncedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['order_uuid'] = Variable<String>(orderUuid);
    map['events_json'] = Variable<String>(eventsJson);
    if (!nullToAbsent || orderNumber != null) {
      map['order_number'] = Variable<int>(orderNumber);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['attempts'] = Variable<int>(attempts);
    if (!nullToAbsent || lastError != null) {
      map['last_error'] = Variable<String>(lastError);
    }
    if (!nullToAbsent || syncedAt != null) {
      map['synced_at'] = Variable<DateTime>(syncedAt);
    }
    return map;
  }

  OrderOutboxCompanion toCompanion(bool nullToAbsent) {
    return OrderOutboxCompanion(
      orderUuid: Value(orderUuid),
      eventsJson: Value(eventsJson),
      orderNumber: orderNumber == null && nullToAbsent
          ? const Value.absent()
          : Value(orderNumber),
      createdAt: Value(createdAt),
      attempts: Value(attempts),
      lastError: lastError == null && nullToAbsent
          ? const Value.absent()
          : Value(lastError),
      syncedAt: syncedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(syncedAt),
    );
  }

  factory OrderOutboxRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OrderOutboxRow(
      orderUuid: serializer.fromJson<String>(json['orderUuid']),
      eventsJson: serializer.fromJson<String>(json['eventsJson']),
      orderNumber: serializer.fromJson<int?>(json['orderNumber']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      attempts: serializer.fromJson<int>(json['attempts']),
      lastError: serializer.fromJson<String?>(json['lastError']),
      syncedAt: serializer.fromJson<DateTime?>(json['syncedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'orderUuid': serializer.toJson<String>(orderUuid),
      'eventsJson': serializer.toJson<String>(eventsJson),
      'orderNumber': serializer.toJson<int?>(orderNumber),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'attempts': serializer.toJson<int>(attempts),
      'lastError': serializer.toJson<String?>(lastError),
      'syncedAt': serializer.toJson<DateTime?>(syncedAt),
    };
  }

  OrderOutboxRow copyWith({
    String? orderUuid,
    String? eventsJson,
    Value<int?> orderNumber = const Value.absent(),
    DateTime? createdAt,
    int? attempts,
    Value<String?> lastError = const Value.absent(),
    Value<DateTime?> syncedAt = const Value.absent(),
  }) => OrderOutboxRow(
    orderUuid: orderUuid ?? this.orderUuid,
    eventsJson: eventsJson ?? this.eventsJson,
    orderNumber: orderNumber.present ? orderNumber.value : this.orderNumber,
    createdAt: createdAt ?? this.createdAt,
    attempts: attempts ?? this.attempts,
    lastError: lastError.present ? lastError.value : this.lastError,
    syncedAt: syncedAt.present ? syncedAt.value : this.syncedAt,
  );
  OrderOutboxRow copyWithCompanion(OrderOutboxCompanion data) {
    return OrderOutboxRow(
      orderUuid: data.orderUuid.present ? data.orderUuid.value : this.orderUuid,
      eventsJson: data.eventsJson.present
          ? data.eventsJson.value
          : this.eventsJson,
      orderNumber: data.orderNumber.present
          ? data.orderNumber.value
          : this.orderNumber,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      attempts: data.attempts.present ? data.attempts.value : this.attempts,
      lastError: data.lastError.present ? data.lastError.value : this.lastError,
      syncedAt: data.syncedAt.present ? data.syncedAt.value : this.syncedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OrderOutboxRow(')
          ..write('orderUuid: $orderUuid, ')
          ..write('eventsJson: $eventsJson, ')
          ..write('orderNumber: $orderNumber, ')
          ..write('createdAt: $createdAt, ')
          ..write('attempts: $attempts, ')
          ..write('lastError: $lastError, ')
          ..write('syncedAt: $syncedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    orderUuid,
    eventsJson,
    orderNumber,
    createdAt,
    attempts,
    lastError,
    syncedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OrderOutboxRow &&
          other.orderUuid == this.orderUuid &&
          other.eventsJson == this.eventsJson &&
          other.orderNumber == this.orderNumber &&
          other.createdAt == this.createdAt &&
          other.attempts == this.attempts &&
          other.lastError == this.lastError &&
          other.syncedAt == this.syncedAt);
}

class OrderOutboxCompanion extends UpdateCompanion<OrderOutboxRow> {
  final Value<String> orderUuid;
  final Value<String> eventsJson;
  final Value<int?> orderNumber;
  final Value<DateTime> createdAt;
  final Value<int> attempts;
  final Value<String?> lastError;
  final Value<DateTime?> syncedAt;
  final Value<int> rowid;
  const OrderOutboxCompanion({
    this.orderUuid = const Value.absent(),
    this.eventsJson = const Value.absent(),
    this.orderNumber = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.attempts = const Value.absent(),
    this.lastError = const Value.absent(),
    this.syncedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  OrderOutboxCompanion.insert({
    required String orderUuid,
    required String eventsJson,
    this.orderNumber = const Value.absent(),
    required DateTime createdAt,
    this.attempts = const Value.absent(),
    this.lastError = const Value.absent(),
    this.syncedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : orderUuid = Value(orderUuid),
       eventsJson = Value(eventsJson),
       createdAt = Value(createdAt);
  static Insertable<OrderOutboxRow> custom({
    Expression<String>? orderUuid,
    Expression<String>? eventsJson,
    Expression<int>? orderNumber,
    Expression<DateTime>? createdAt,
    Expression<int>? attempts,
    Expression<String>? lastError,
    Expression<DateTime>? syncedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (orderUuid != null) 'order_uuid': orderUuid,
      if (eventsJson != null) 'events_json': eventsJson,
      if (orderNumber != null) 'order_number': orderNumber,
      if (createdAt != null) 'created_at': createdAt,
      if (attempts != null) 'attempts': attempts,
      if (lastError != null) 'last_error': lastError,
      if (syncedAt != null) 'synced_at': syncedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  OrderOutboxCompanion copyWith({
    Value<String>? orderUuid,
    Value<String>? eventsJson,
    Value<int?>? orderNumber,
    Value<DateTime>? createdAt,
    Value<int>? attempts,
    Value<String?>? lastError,
    Value<DateTime?>? syncedAt,
    Value<int>? rowid,
  }) {
    return OrderOutboxCompanion(
      orderUuid: orderUuid ?? this.orderUuid,
      eventsJson: eventsJson ?? this.eventsJson,
      orderNumber: orderNumber ?? this.orderNumber,
      createdAt: createdAt ?? this.createdAt,
      attempts: attempts ?? this.attempts,
      lastError: lastError ?? this.lastError,
      syncedAt: syncedAt ?? this.syncedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (orderUuid.present) {
      map['order_uuid'] = Variable<String>(orderUuid.value);
    }
    if (eventsJson.present) {
      map['events_json'] = Variable<String>(eventsJson.value);
    }
    if (orderNumber.present) {
      map['order_number'] = Variable<int>(orderNumber.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (attempts.present) {
      map['attempts'] = Variable<int>(attempts.value);
    }
    if (lastError.present) {
      map['last_error'] = Variable<String>(lastError.value);
    }
    if (syncedAt.present) {
      map['synced_at'] = Variable<DateTime>(syncedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OrderOutboxCompanion(')
          ..write('orderUuid: $orderUuid, ')
          ..write('eventsJson: $eventsJson, ')
          ..write('orderNumber: $orderNumber, ')
          ..write('createdAt: $createdAt, ')
          ..write('attempts: $attempts, ')
          ..write('lastError: $lastError, ')
          ..write('syncedAt: $syncedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DeliveryProvidersTable extends DeliveryProviders
    with TableInfo<$DeliveryProvidersTable, DeliveryProviderRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DeliveryProvidersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _colorMeta = const VerificationMeta('color');
  @override
  late final GeneratedColumn<String> color = GeneratedColumn<String>(
    'color',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [id, name, color, sortOrder];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'delivery_providers';
  @override
  VerificationContext validateIntegrity(
    Insertable<DeliveryProviderRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    }
    if (data.containsKey('color')) {
      context.handle(
        _colorMeta,
        color.isAcceptableOrUnknown(data['color']!, _colorMeta),
      );
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  DeliveryProviderRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DeliveryProviderRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      color: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}color'],
      ),
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
    );
  }

  @override
  $DeliveryProvidersTable createAlias(String alias) {
    return $DeliveryProvidersTable(attachedDatabase, alias);
  }
}

class DeliveryProviderRow extends DataClass
    implements Insertable<DeliveryProviderRow> {
  final int id;
  final String name;
  final String? color;
  final int sortOrder;
  const DeliveryProviderRow({
    required this.id,
    required this.name,
    this.color,
    required this.sortOrder,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || color != null) {
      map['color'] = Variable<String>(color);
    }
    map['sort_order'] = Variable<int>(sortOrder);
    return map;
  }

  DeliveryProvidersCompanion toCompanion(bool nullToAbsent) {
    return DeliveryProvidersCompanion(
      id: Value(id),
      name: Value(name),
      color: color == null && nullToAbsent
          ? const Value.absent()
          : Value(color),
      sortOrder: Value(sortOrder),
    );
  }

  factory DeliveryProviderRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DeliveryProviderRow(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      color: serializer.fromJson<String?>(json['color']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'color': serializer.toJson<String?>(color),
      'sortOrder': serializer.toJson<int>(sortOrder),
    };
  }

  DeliveryProviderRow copyWith({
    int? id,
    String? name,
    Value<String?> color = const Value.absent(),
    int? sortOrder,
  }) => DeliveryProviderRow(
    id: id ?? this.id,
    name: name ?? this.name,
    color: color.present ? color.value : this.color,
    sortOrder: sortOrder ?? this.sortOrder,
  );
  DeliveryProviderRow copyWithCompanion(DeliveryProvidersCompanion data) {
    return DeliveryProviderRow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      color: data.color.present ? data.color.value : this.color,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DeliveryProviderRow(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('color: $color, ')
          ..write('sortOrder: $sortOrder')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, color, sortOrder);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DeliveryProviderRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.color == this.color &&
          other.sortOrder == this.sortOrder);
}

class DeliveryProvidersCompanion extends UpdateCompanion<DeliveryProviderRow> {
  final Value<int> id;
  final Value<String> name;
  final Value<String?> color;
  final Value<int> sortOrder;
  const DeliveryProvidersCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.color = const Value.absent(),
    this.sortOrder = const Value.absent(),
  });
  DeliveryProvidersCompanion.insert({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.color = const Value.absent(),
    this.sortOrder = const Value.absent(),
  });
  static Insertable<DeliveryProviderRow> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<String>? color,
    Expression<int>? sortOrder,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (color != null) 'color': color,
      if (sortOrder != null) 'sort_order': sortOrder,
    });
  }

  DeliveryProvidersCompanion copyWith({
    Value<int>? id,
    Value<String>? name,
    Value<String?>? color,
    Value<int>? sortOrder,
  }) {
    return DeliveryProvidersCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      color: color ?? this.color,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (color.present) {
      map['color'] = Variable<String>(color.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DeliveryProvidersCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('color: $color, ')
          ..write('sortOrder: $sortOrder')
          ..write(')'))
        .toString();
  }
}

class $ExpenseCategoriesTable extends ExpenseCategories
    with TableInfo<$ExpenseCategoriesTable, ExpenseCategoryRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ExpenseCategoriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _nameArMeta = const VerificationMeta('nameAr');
  @override
  late final GeneratedColumn<String> nameAr = GeneratedColumn<String>(
    'name_ar',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [id, key, name, nameAr, sortOrder];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'expense_categories';
  @override
  VerificationContext validateIntegrity(
    Insertable<ExpenseCategoryRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    }
    if (data.containsKey('name_ar')) {
      context.handle(
        _nameArMeta,
        nameAr.isAcceptableOrUnknown(data['name_ar']!, _nameArMeta),
      );
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ExpenseCategoryRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ExpenseCategoryRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      nameAr: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name_ar'],
      ),
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
    );
  }

  @override
  $ExpenseCategoriesTable createAlias(String alias) {
    return $ExpenseCategoriesTable(attachedDatabase, alias);
  }
}

class ExpenseCategoryRow extends DataClass
    implements Insertable<ExpenseCategoryRow> {
  final int id;
  final String key;
  final String name;
  final String? nameAr;
  final int sortOrder;
  const ExpenseCategoryRow({
    required this.id,
    required this.key,
    required this.name,
    this.nameAr,
    required this.sortOrder,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['key'] = Variable<String>(key);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || nameAr != null) {
      map['name_ar'] = Variable<String>(nameAr);
    }
    map['sort_order'] = Variable<int>(sortOrder);
    return map;
  }

  ExpenseCategoriesCompanion toCompanion(bool nullToAbsent) {
    return ExpenseCategoriesCompanion(
      id: Value(id),
      key: Value(key),
      name: Value(name),
      nameAr: nameAr == null && nullToAbsent
          ? const Value.absent()
          : Value(nameAr),
      sortOrder: Value(sortOrder),
    );
  }

  factory ExpenseCategoryRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ExpenseCategoryRow(
      id: serializer.fromJson<int>(json['id']),
      key: serializer.fromJson<String>(json['key']),
      name: serializer.fromJson<String>(json['name']),
      nameAr: serializer.fromJson<String?>(json['nameAr']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'key': serializer.toJson<String>(key),
      'name': serializer.toJson<String>(name),
      'nameAr': serializer.toJson<String?>(nameAr),
      'sortOrder': serializer.toJson<int>(sortOrder),
    };
  }

  ExpenseCategoryRow copyWith({
    int? id,
    String? key,
    String? name,
    Value<String?> nameAr = const Value.absent(),
    int? sortOrder,
  }) => ExpenseCategoryRow(
    id: id ?? this.id,
    key: key ?? this.key,
    name: name ?? this.name,
    nameAr: nameAr.present ? nameAr.value : this.nameAr,
    sortOrder: sortOrder ?? this.sortOrder,
  );
  ExpenseCategoryRow copyWithCompanion(ExpenseCategoriesCompanion data) {
    return ExpenseCategoryRow(
      id: data.id.present ? data.id.value : this.id,
      key: data.key.present ? data.key.value : this.key,
      name: data.name.present ? data.name.value : this.name,
      nameAr: data.nameAr.present ? data.nameAr.value : this.nameAr,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ExpenseCategoryRow(')
          ..write('id: $id, ')
          ..write('key: $key, ')
          ..write('name: $name, ')
          ..write('nameAr: $nameAr, ')
          ..write('sortOrder: $sortOrder')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, key, name, nameAr, sortOrder);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ExpenseCategoryRow &&
          other.id == this.id &&
          other.key == this.key &&
          other.name == this.name &&
          other.nameAr == this.nameAr &&
          other.sortOrder == this.sortOrder);
}

class ExpenseCategoriesCompanion extends UpdateCompanion<ExpenseCategoryRow> {
  final Value<int> id;
  final Value<String> key;
  final Value<String> name;
  final Value<String?> nameAr;
  final Value<int> sortOrder;
  const ExpenseCategoriesCompanion({
    this.id = const Value.absent(),
    this.key = const Value.absent(),
    this.name = const Value.absent(),
    this.nameAr = const Value.absent(),
    this.sortOrder = const Value.absent(),
  });
  ExpenseCategoriesCompanion.insert({
    this.id = const Value.absent(),
    this.key = const Value.absent(),
    this.name = const Value.absent(),
    this.nameAr = const Value.absent(),
    this.sortOrder = const Value.absent(),
  });
  static Insertable<ExpenseCategoryRow> custom({
    Expression<int>? id,
    Expression<String>? key,
    Expression<String>? name,
    Expression<String>? nameAr,
    Expression<int>? sortOrder,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (key != null) 'key': key,
      if (name != null) 'name': name,
      if (nameAr != null) 'name_ar': nameAr,
      if (sortOrder != null) 'sort_order': sortOrder,
    });
  }

  ExpenseCategoriesCompanion copyWith({
    Value<int>? id,
    Value<String>? key,
    Value<String>? name,
    Value<String?>? nameAr,
    Value<int>? sortOrder,
  }) {
    return ExpenseCategoriesCompanion(
      id: id ?? this.id,
      key: key ?? this.key,
      name: name ?? this.name,
      nameAr: nameAr ?? this.nameAr,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (nameAr.present) {
      map['name_ar'] = Variable<String>(nameAr.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ExpenseCategoriesCompanion(')
          ..write('id: $id, ')
          ..write('key: $key, ')
          ..write('name: $name, ')
          ..write('nameAr: $nameAr, ')
          ..write('sortOrder: $sortOrder')
          ..write(')'))
        .toString();
  }
}

class $BranchIngredientStockTable extends BranchIngredientStock
    with TableInfo<$BranchIngredientStockTable, BranchIngredientStockRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BranchIngredientStockTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _ingredientIdMeta = const VerificationMeta(
    'ingredientId',
  );
  @override
  late final GeneratedColumn<int> ingredientId = GeneratedColumn<int>(
    'ingredient_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _quantityMeta = const VerificationMeta(
    'quantity',
  );
  @override
  late final GeneratedColumn<double> quantity = GeneratedColumn<double>(
    'quantity',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [ingredientId, quantity];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'branch_ingredient_stock';
  @override
  VerificationContext validateIntegrity(
    Insertable<BranchIngredientStockRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('ingredient_id')) {
      context.handle(
        _ingredientIdMeta,
        ingredientId.isAcceptableOrUnknown(
          data['ingredient_id']!,
          _ingredientIdMeta,
        ),
      );
    }
    if (data.containsKey('quantity')) {
      context.handle(
        _quantityMeta,
        quantity.isAcceptableOrUnknown(data['quantity']!, _quantityMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {ingredientId};
  @override
  BranchIngredientStockRow map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return BranchIngredientStockRow(
      ingredientId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}ingredient_id'],
      )!,
      quantity: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}quantity'],
      )!,
    );
  }

  @override
  $BranchIngredientStockTable createAlias(String alias) {
    return $BranchIngredientStockTable(attachedDatabase, alias);
  }
}

class BranchIngredientStockRow extends DataClass
    implements Insertable<BranchIngredientStockRow> {
  final int ingredientId;
  final double quantity;
  const BranchIngredientStockRow({
    required this.ingredientId,
    required this.quantity,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['ingredient_id'] = Variable<int>(ingredientId);
    map['quantity'] = Variable<double>(quantity);
    return map;
  }

  BranchIngredientStockCompanion toCompanion(bool nullToAbsent) {
    return BranchIngredientStockCompanion(
      ingredientId: Value(ingredientId),
      quantity: Value(quantity),
    );
  }

  factory BranchIngredientStockRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return BranchIngredientStockRow(
      ingredientId: serializer.fromJson<int>(json['ingredientId']),
      quantity: serializer.fromJson<double>(json['quantity']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'ingredientId': serializer.toJson<int>(ingredientId),
      'quantity': serializer.toJson<double>(quantity),
    };
  }

  BranchIngredientStockRow copyWith({int? ingredientId, double? quantity}) =>
      BranchIngredientStockRow(
        ingredientId: ingredientId ?? this.ingredientId,
        quantity: quantity ?? this.quantity,
      );
  BranchIngredientStockRow copyWithCompanion(
    BranchIngredientStockCompanion data,
  ) {
    return BranchIngredientStockRow(
      ingredientId: data.ingredientId.present
          ? data.ingredientId.value
          : this.ingredientId,
      quantity: data.quantity.present ? data.quantity.value : this.quantity,
    );
  }

  @override
  String toString() {
    return (StringBuffer('BranchIngredientStockRow(')
          ..write('ingredientId: $ingredientId, ')
          ..write('quantity: $quantity')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(ingredientId, quantity);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BranchIngredientStockRow &&
          other.ingredientId == this.ingredientId &&
          other.quantity == this.quantity);
}

class BranchIngredientStockCompanion
    extends UpdateCompanion<BranchIngredientStockRow> {
  final Value<int> ingredientId;
  final Value<double> quantity;
  const BranchIngredientStockCompanion({
    this.ingredientId = const Value.absent(),
    this.quantity = const Value.absent(),
  });
  BranchIngredientStockCompanion.insert({
    this.ingredientId = const Value.absent(),
    this.quantity = const Value.absent(),
  });
  static Insertable<BranchIngredientStockRow> custom({
    Expression<int>? ingredientId,
    Expression<double>? quantity,
  }) {
    return RawValuesInsertable({
      if (ingredientId != null) 'ingredient_id': ingredientId,
      if (quantity != null) 'quantity': quantity,
    });
  }

  BranchIngredientStockCompanion copyWith({
    Value<int>? ingredientId,
    Value<double>? quantity,
  }) {
    return BranchIngredientStockCompanion(
      ingredientId: ingredientId ?? this.ingredientId,
      quantity: quantity ?? this.quantity,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (ingredientId.present) {
      map['ingredient_id'] = Variable<int>(ingredientId.value);
    }
    if (quantity.present) {
      map['quantity'] = Variable<double>(quantity.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BranchIngredientStockCompanion(')
          ..write('ingredientId: $ingredientId, ')
          ..write('quantity: $quantity')
          ..write(')'))
        .toString();
  }
}

class $DiscountsTable extends Discounts
    with TableInfo<$DiscountsTable, DiscountRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DiscountsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _scopeMeta = const VerificationMeta('scope');
  @override
  late final GeneratedColumn<String> scope = GeneratedColumn<String>(
    'scope',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _amountTypeMeta = const VerificationMeta(
    'amountType',
  );
  @override
  late final GeneratedColumn<String> amountType = GeneratedColumn<String>(
    'amount_type',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _amountBaisasMeta = const VerificationMeta(
    'amountBaisas',
  );
  @override
  late final GeneratedColumn<int> amountBaisas = GeneratedColumn<int>(
    'amount_baisas',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _percentMeta = const VerificationMeta(
    'percent',
  );
  @override
  late final GeneratedColumn<double> percent = GeneratedColumn<double>(
    'percent',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _validityStartMeta = const VerificationMeta(
    'validityStart',
  );
  @override
  late final GeneratedColumn<DateTime> validityStart =
      GeneratedColumn<DateTime>(
        'validity_start',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _validityEndMeta = const VerificationMeta(
    'validityEnd',
  );
  @override
  late final GeneratedColumn<DateTime> validityEnd = GeneratedColumn<DateTime>(
    'validity_end',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _dayofweekMaskMeta = const VerificationMeta(
    'dayofweekMask',
  );
  @override
  late final GeneratedColumn<int> dayofweekMask = GeneratedColumn<int>(
    'dayofweek_mask',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _timeStartMeta = const VerificationMeta(
    'timeStart',
  );
  @override
  late final GeneratedColumn<String> timeStart = GeneratedColumn<String>(
    'time_start',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _timeEndMeta = const VerificationMeta(
    'timeEnd',
  );
  @override
  late final GeneratedColumn<String> timeEnd = GeneratedColumn<String>(
    'time_end',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _branchScopeJsonMeta = const VerificationMeta(
    'branchScopeJson',
  );
  @override
  late final GeneratedColumn<String> branchScopeJson = GeneratedColumn<String>(
    'branch_scope_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _stackableMeta = const VerificationMeta(
    'stackable',
  );
  @override
  late final GeneratedColumn<bool> stackable = GeneratedColumn<bool>(
    'stackable',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("stackable" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _requiresManagerApprovalMeta =
      const VerificationMeta('requiresManagerApproval');
  @override
  late final GeneratedColumn<bool> requiresManagerApproval =
      GeneratedColumn<bool>(
        'requires_manager_approval',
        aliasedName,
        false,
        type: DriftSqlType.bool,
        requiredDuringInsert: false,
        defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("requires_manager_approval" IN (0, 1))',
        ),
        defaultValue: const Constant(false),
      );
  static const VerificationMeta _autoApplyMeta = const VerificationMeta(
    'autoApply',
  );
  @override
  late final GeneratedColumn<bool> autoApply = GeneratedColumn<bool>(
    'auto_apply',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("auto_apply" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _targetsJsonMeta = const VerificationMeta(
    'targetsJson',
  );
  @override
  late final GeneratedColumn<String> targetsJson = GeneratedColumn<String>(
    'targets_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    scope,
    amountType,
    amountBaisas,
    percent,
    validityStart,
    validityEnd,
    dayofweekMask,
    timeStart,
    timeEnd,
    branchScopeJson,
    stackable,
    requiresManagerApproval,
    autoApply,
    status,
    targetsJson,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'discounts';
  @override
  VerificationContext validateIntegrity(
    Insertable<DiscountRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    }
    if (data.containsKey('scope')) {
      context.handle(
        _scopeMeta,
        scope.isAcceptableOrUnknown(data['scope']!, _scopeMeta),
      );
    }
    if (data.containsKey('amount_type')) {
      context.handle(
        _amountTypeMeta,
        amountType.isAcceptableOrUnknown(data['amount_type']!, _amountTypeMeta),
      );
    }
    if (data.containsKey('amount_baisas')) {
      context.handle(
        _amountBaisasMeta,
        amountBaisas.isAcceptableOrUnknown(
          data['amount_baisas']!,
          _amountBaisasMeta,
        ),
      );
    }
    if (data.containsKey('percent')) {
      context.handle(
        _percentMeta,
        percent.isAcceptableOrUnknown(data['percent']!, _percentMeta),
      );
    }
    if (data.containsKey('validity_start')) {
      context.handle(
        _validityStartMeta,
        validityStart.isAcceptableOrUnknown(
          data['validity_start']!,
          _validityStartMeta,
        ),
      );
    }
    if (data.containsKey('validity_end')) {
      context.handle(
        _validityEndMeta,
        validityEnd.isAcceptableOrUnknown(
          data['validity_end']!,
          _validityEndMeta,
        ),
      );
    }
    if (data.containsKey('dayofweek_mask')) {
      context.handle(
        _dayofweekMaskMeta,
        dayofweekMask.isAcceptableOrUnknown(
          data['dayofweek_mask']!,
          _dayofweekMaskMeta,
        ),
      );
    }
    if (data.containsKey('time_start')) {
      context.handle(
        _timeStartMeta,
        timeStart.isAcceptableOrUnknown(data['time_start']!, _timeStartMeta),
      );
    }
    if (data.containsKey('time_end')) {
      context.handle(
        _timeEndMeta,
        timeEnd.isAcceptableOrUnknown(data['time_end']!, _timeEndMeta),
      );
    }
    if (data.containsKey('branch_scope_json')) {
      context.handle(
        _branchScopeJsonMeta,
        branchScopeJson.isAcceptableOrUnknown(
          data['branch_scope_json']!,
          _branchScopeJsonMeta,
        ),
      );
    }
    if (data.containsKey('stackable')) {
      context.handle(
        _stackableMeta,
        stackable.isAcceptableOrUnknown(data['stackable']!, _stackableMeta),
      );
    }
    if (data.containsKey('requires_manager_approval')) {
      context.handle(
        _requiresManagerApprovalMeta,
        requiresManagerApproval.isAcceptableOrUnknown(
          data['requires_manager_approval']!,
          _requiresManagerApprovalMeta,
        ),
      );
    }
    if (data.containsKey('auto_apply')) {
      context.handle(
        _autoApplyMeta,
        autoApply.isAcceptableOrUnknown(data['auto_apply']!, _autoApplyMeta),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('targets_json')) {
      context.handle(
        _targetsJsonMeta,
        targetsJson.isAcceptableOrUnknown(
          data['targets_json']!,
          _targetsJsonMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  DiscountRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DiscountRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      scope: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}scope'],
      ),
      amountType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}amount_type'],
      ),
      amountBaisas: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}amount_baisas'],
      ),
      percent: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}percent'],
      ),
      validityStart: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}validity_start'],
      ),
      validityEnd: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}validity_end'],
      ),
      dayofweekMask: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}dayofweek_mask'],
      ),
      timeStart: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}time_start'],
      ),
      timeEnd: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}time_end'],
      ),
      branchScopeJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}branch_scope_json'],
      ),
      stackable: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}stackable'],
      )!,
      requiresManagerApproval: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}requires_manager_approval'],
      )!,
      autoApply: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}auto_apply'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      ),
      targetsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}targets_json'],
      )!,
    );
  }

  @override
  $DiscountsTable createAlias(String alias) {
    return $DiscountsTable(attachedDatabase, alias);
  }
}

class DiscountRow extends DataClass implements Insertable<DiscountRow> {
  final int id;
  final String name;
  final String? scope;
  final String? amountType;
  final int? amountBaisas;
  final double? percent;
  final DateTime? validityStart;
  final DateTime? validityEnd;
  final int? dayofweekMask;
  final String? timeStart;
  final String? timeEnd;
  final String? branchScopeJson;
  final bool stackable;
  final bool requiresManagerApproval;
  final bool autoApply;
  final String? status;
  final String targetsJson;
  const DiscountRow({
    required this.id,
    required this.name,
    this.scope,
    this.amountType,
    this.amountBaisas,
    this.percent,
    this.validityStart,
    this.validityEnd,
    this.dayofweekMask,
    this.timeStart,
    this.timeEnd,
    this.branchScopeJson,
    required this.stackable,
    required this.requiresManagerApproval,
    required this.autoApply,
    this.status,
    required this.targetsJson,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || scope != null) {
      map['scope'] = Variable<String>(scope);
    }
    if (!nullToAbsent || amountType != null) {
      map['amount_type'] = Variable<String>(amountType);
    }
    if (!nullToAbsent || amountBaisas != null) {
      map['amount_baisas'] = Variable<int>(amountBaisas);
    }
    if (!nullToAbsent || percent != null) {
      map['percent'] = Variable<double>(percent);
    }
    if (!nullToAbsent || validityStart != null) {
      map['validity_start'] = Variable<DateTime>(validityStart);
    }
    if (!nullToAbsent || validityEnd != null) {
      map['validity_end'] = Variable<DateTime>(validityEnd);
    }
    if (!nullToAbsent || dayofweekMask != null) {
      map['dayofweek_mask'] = Variable<int>(dayofweekMask);
    }
    if (!nullToAbsent || timeStart != null) {
      map['time_start'] = Variable<String>(timeStart);
    }
    if (!nullToAbsent || timeEnd != null) {
      map['time_end'] = Variable<String>(timeEnd);
    }
    if (!nullToAbsent || branchScopeJson != null) {
      map['branch_scope_json'] = Variable<String>(branchScopeJson);
    }
    map['stackable'] = Variable<bool>(stackable);
    map['requires_manager_approval'] = Variable<bool>(requiresManagerApproval);
    map['auto_apply'] = Variable<bool>(autoApply);
    if (!nullToAbsent || status != null) {
      map['status'] = Variable<String>(status);
    }
    map['targets_json'] = Variable<String>(targetsJson);
    return map;
  }

  DiscountsCompanion toCompanion(bool nullToAbsent) {
    return DiscountsCompanion(
      id: Value(id),
      name: Value(name),
      scope: scope == null && nullToAbsent
          ? const Value.absent()
          : Value(scope),
      amountType: amountType == null && nullToAbsent
          ? const Value.absent()
          : Value(amountType),
      amountBaisas: amountBaisas == null && nullToAbsent
          ? const Value.absent()
          : Value(amountBaisas),
      percent: percent == null && nullToAbsent
          ? const Value.absent()
          : Value(percent),
      validityStart: validityStart == null && nullToAbsent
          ? const Value.absent()
          : Value(validityStart),
      validityEnd: validityEnd == null && nullToAbsent
          ? const Value.absent()
          : Value(validityEnd),
      dayofweekMask: dayofweekMask == null && nullToAbsent
          ? const Value.absent()
          : Value(dayofweekMask),
      timeStart: timeStart == null && nullToAbsent
          ? const Value.absent()
          : Value(timeStart),
      timeEnd: timeEnd == null && nullToAbsent
          ? const Value.absent()
          : Value(timeEnd),
      branchScopeJson: branchScopeJson == null && nullToAbsent
          ? const Value.absent()
          : Value(branchScopeJson),
      stackable: Value(stackable),
      requiresManagerApproval: Value(requiresManagerApproval),
      autoApply: Value(autoApply),
      status: status == null && nullToAbsent
          ? const Value.absent()
          : Value(status),
      targetsJson: Value(targetsJson),
    );
  }

  factory DiscountRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DiscountRow(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      scope: serializer.fromJson<String?>(json['scope']),
      amountType: serializer.fromJson<String?>(json['amountType']),
      amountBaisas: serializer.fromJson<int?>(json['amountBaisas']),
      percent: serializer.fromJson<double?>(json['percent']),
      validityStart: serializer.fromJson<DateTime?>(json['validityStart']),
      validityEnd: serializer.fromJson<DateTime?>(json['validityEnd']),
      dayofweekMask: serializer.fromJson<int?>(json['dayofweekMask']),
      timeStart: serializer.fromJson<String?>(json['timeStart']),
      timeEnd: serializer.fromJson<String?>(json['timeEnd']),
      branchScopeJson: serializer.fromJson<String?>(json['branchScopeJson']),
      stackable: serializer.fromJson<bool>(json['stackable']),
      requiresManagerApproval: serializer.fromJson<bool>(
        json['requiresManagerApproval'],
      ),
      autoApply: serializer.fromJson<bool>(json['autoApply']),
      status: serializer.fromJson<String?>(json['status']),
      targetsJson: serializer.fromJson<String>(json['targetsJson']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'scope': serializer.toJson<String?>(scope),
      'amountType': serializer.toJson<String?>(amountType),
      'amountBaisas': serializer.toJson<int?>(amountBaisas),
      'percent': serializer.toJson<double?>(percent),
      'validityStart': serializer.toJson<DateTime?>(validityStart),
      'validityEnd': serializer.toJson<DateTime?>(validityEnd),
      'dayofweekMask': serializer.toJson<int?>(dayofweekMask),
      'timeStart': serializer.toJson<String?>(timeStart),
      'timeEnd': serializer.toJson<String?>(timeEnd),
      'branchScopeJson': serializer.toJson<String?>(branchScopeJson),
      'stackable': serializer.toJson<bool>(stackable),
      'requiresManagerApproval': serializer.toJson<bool>(
        requiresManagerApproval,
      ),
      'autoApply': serializer.toJson<bool>(autoApply),
      'status': serializer.toJson<String?>(status),
      'targetsJson': serializer.toJson<String>(targetsJson),
    };
  }

  DiscountRow copyWith({
    int? id,
    String? name,
    Value<String?> scope = const Value.absent(),
    Value<String?> amountType = const Value.absent(),
    Value<int?> amountBaisas = const Value.absent(),
    Value<double?> percent = const Value.absent(),
    Value<DateTime?> validityStart = const Value.absent(),
    Value<DateTime?> validityEnd = const Value.absent(),
    Value<int?> dayofweekMask = const Value.absent(),
    Value<String?> timeStart = const Value.absent(),
    Value<String?> timeEnd = const Value.absent(),
    Value<String?> branchScopeJson = const Value.absent(),
    bool? stackable,
    bool? requiresManagerApproval,
    bool? autoApply,
    Value<String?> status = const Value.absent(),
    String? targetsJson,
  }) => DiscountRow(
    id: id ?? this.id,
    name: name ?? this.name,
    scope: scope.present ? scope.value : this.scope,
    amountType: amountType.present ? amountType.value : this.amountType,
    amountBaisas: amountBaisas.present ? amountBaisas.value : this.amountBaisas,
    percent: percent.present ? percent.value : this.percent,
    validityStart: validityStart.present
        ? validityStart.value
        : this.validityStart,
    validityEnd: validityEnd.present ? validityEnd.value : this.validityEnd,
    dayofweekMask: dayofweekMask.present
        ? dayofweekMask.value
        : this.dayofweekMask,
    timeStart: timeStart.present ? timeStart.value : this.timeStart,
    timeEnd: timeEnd.present ? timeEnd.value : this.timeEnd,
    branchScopeJson: branchScopeJson.present
        ? branchScopeJson.value
        : this.branchScopeJson,
    stackable: stackable ?? this.stackable,
    requiresManagerApproval:
        requiresManagerApproval ?? this.requiresManagerApproval,
    autoApply: autoApply ?? this.autoApply,
    status: status.present ? status.value : this.status,
    targetsJson: targetsJson ?? this.targetsJson,
  );
  DiscountRow copyWithCompanion(DiscountsCompanion data) {
    return DiscountRow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      scope: data.scope.present ? data.scope.value : this.scope,
      amountType: data.amountType.present
          ? data.amountType.value
          : this.amountType,
      amountBaisas: data.amountBaisas.present
          ? data.amountBaisas.value
          : this.amountBaisas,
      percent: data.percent.present ? data.percent.value : this.percent,
      validityStart: data.validityStart.present
          ? data.validityStart.value
          : this.validityStart,
      validityEnd: data.validityEnd.present
          ? data.validityEnd.value
          : this.validityEnd,
      dayofweekMask: data.dayofweekMask.present
          ? data.dayofweekMask.value
          : this.dayofweekMask,
      timeStart: data.timeStart.present ? data.timeStart.value : this.timeStart,
      timeEnd: data.timeEnd.present ? data.timeEnd.value : this.timeEnd,
      branchScopeJson: data.branchScopeJson.present
          ? data.branchScopeJson.value
          : this.branchScopeJson,
      stackable: data.stackable.present ? data.stackable.value : this.stackable,
      requiresManagerApproval: data.requiresManagerApproval.present
          ? data.requiresManagerApproval.value
          : this.requiresManagerApproval,
      autoApply: data.autoApply.present ? data.autoApply.value : this.autoApply,
      status: data.status.present ? data.status.value : this.status,
      targetsJson: data.targetsJson.present
          ? data.targetsJson.value
          : this.targetsJson,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DiscountRow(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('scope: $scope, ')
          ..write('amountType: $amountType, ')
          ..write('amountBaisas: $amountBaisas, ')
          ..write('percent: $percent, ')
          ..write('validityStart: $validityStart, ')
          ..write('validityEnd: $validityEnd, ')
          ..write('dayofweekMask: $dayofweekMask, ')
          ..write('timeStart: $timeStart, ')
          ..write('timeEnd: $timeEnd, ')
          ..write('branchScopeJson: $branchScopeJson, ')
          ..write('stackable: $stackable, ')
          ..write('requiresManagerApproval: $requiresManagerApproval, ')
          ..write('autoApply: $autoApply, ')
          ..write('status: $status, ')
          ..write('targetsJson: $targetsJson')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    scope,
    amountType,
    amountBaisas,
    percent,
    validityStart,
    validityEnd,
    dayofweekMask,
    timeStart,
    timeEnd,
    branchScopeJson,
    stackable,
    requiresManagerApproval,
    autoApply,
    status,
    targetsJson,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DiscountRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.scope == this.scope &&
          other.amountType == this.amountType &&
          other.amountBaisas == this.amountBaisas &&
          other.percent == this.percent &&
          other.validityStart == this.validityStart &&
          other.validityEnd == this.validityEnd &&
          other.dayofweekMask == this.dayofweekMask &&
          other.timeStart == this.timeStart &&
          other.timeEnd == this.timeEnd &&
          other.branchScopeJson == this.branchScopeJson &&
          other.stackable == this.stackable &&
          other.requiresManagerApproval == this.requiresManagerApproval &&
          other.autoApply == this.autoApply &&
          other.status == this.status &&
          other.targetsJson == this.targetsJson);
}

class DiscountsCompanion extends UpdateCompanion<DiscountRow> {
  final Value<int> id;
  final Value<String> name;
  final Value<String?> scope;
  final Value<String?> amountType;
  final Value<int?> amountBaisas;
  final Value<double?> percent;
  final Value<DateTime?> validityStart;
  final Value<DateTime?> validityEnd;
  final Value<int?> dayofweekMask;
  final Value<String?> timeStart;
  final Value<String?> timeEnd;
  final Value<String?> branchScopeJson;
  final Value<bool> stackable;
  final Value<bool> requiresManagerApproval;
  final Value<bool> autoApply;
  final Value<String?> status;
  final Value<String> targetsJson;
  const DiscountsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.scope = const Value.absent(),
    this.amountType = const Value.absent(),
    this.amountBaisas = const Value.absent(),
    this.percent = const Value.absent(),
    this.validityStart = const Value.absent(),
    this.validityEnd = const Value.absent(),
    this.dayofweekMask = const Value.absent(),
    this.timeStart = const Value.absent(),
    this.timeEnd = const Value.absent(),
    this.branchScopeJson = const Value.absent(),
    this.stackable = const Value.absent(),
    this.requiresManagerApproval = const Value.absent(),
    this.autoApply = const Value.absent(),
    this.status = const Value.absent(),
    this.targetsJson = const Value.absent(),
  });
  DiscountsCompanion.insert({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.scope = const Value.absent(),
    this.amountType = const Value.absent(),
    this.amountBaisas = const Value.absent(),
    this.percent = const Value.absent(),
    this.validityStart = const Value.absent(),
    this.validityEnd = const Value.absent(),
    this.dayofweekMask = const Value.absent(),
    this.timeStart = const Value.absent(),
    this.timeEnd = const Value.absent(),
    this.branchScopeJson = const Value.absent(),
    this.stackable = const Value.absent(),
    this.requiresManagerApproval = const Value.absent(),
    this.autoApply = const Value.absent(),
    this.status = const Value.absent(),
    this.targetsJson = const Value.absent(),
  });
  static Insertable<DiscountRow> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<String>? scope,
    Expression<String>? amountType,
    Expression<int>? amountBaisas,
    Expression<double>? percent,
    Expression<DateTime>? validityStart,
    Expression<DateTime>? validityEnd,
    Expression<int>? dayofweekMask,
    Expression<String>? timeStart,
    Expression<String>? timeEnd,
    Expression<String>? branchScopeJson,
    Expression<bool>? stackable,
    Expression<bool>? requiresManagerApproval,
    Expression<bool>? autoApply,
    Expression<String>? status,
    Expression<String>? targetsJson,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (scope != null) 'scope': scope,
      if (amountType != null) 'amount_type': amountType,
      if (amountBaisas != null) 'amount_baisas': amountBaisas,
      if (percent != null) 'percent': percent,
      if (validityStart != null) 'validity_start': validityStart,
      if (validityEnd != null) 'validity_end': validityEnd,
      if (dayofweekMask != null) 'dayofweek_mask': dayofweekMask,
      if (timeStart != null) 'time_start': timeStart,
      if (timeEnd != null) 'time_end': timeEnd,
      if (branchScopeJson != null) 'branch_scope_json': branchScopeJson,
      if (stackable != null) 'stackable': stackable,
      if (requiresManagerApproval != null)
        'requires_manager_approval': requiresManagerApproval,
      if (autoApply != null) 'auto_apply': autoApply,
      if (status != null) 'status': status,
      if (targetsJson != null) 'targets_json': targetsJson,
    });
  }

  DiscountsCompanion copyWith({
    Value<int>? id,
    Value<String>? name,
    Value<String?>? scope,
    Value<String?>? amountType,
    Value<int?>? amountBaisas,
    Value<double?>? percent,
    Value<DateTime?>? validityStart,
    Value<DateTime?>? validityEnd,
    Value<int?>? dayofweekMask,
    Value<String?>? timeStart,
    Value<String?>? timeEnd,
    Value<String?>? branchScopeJson,
    Value<bool>? stackable,
    Value<bool>? requiresManagerApproval,
    Value<bool>? autoApply,
    Value<String?>? status,
    Value<String>? targetsJson,
  }) {
    return DiscountsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      scope: scope ?? this.scope,
      amountType: amountType ?? this.amountType,
      amountBaisas: amountBaisas ?? this.amountBaisas,
      percent: percent ?? this.percent,
      validityStart: validityStart ?? this.validityStart,
      validityEnd: validityEnd ?? this.validityEnd,
      dayofweekMask: dayofweekMask ?? this.dayofweekMask,
      timeStart: timeStart ?? this.timeStart,
      timeEnd: timeEnd ?? this.timeEnd,
      branchScopeJson: branchScopeJson ?? this.branchScopeJson,
      stackable: stackable ?? this.stackable,
      requiresManagerApproval:
          requiresManagerApproval ?? this.requiresManagerApproval,
      autoApply: autoApply ?? this.autoApply,
      status: status ?? this.status,
      targetsJson: targetsJson ?? this.targetsJson,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (scope.present) {
      map['scope'] = Variable<String>(scope.value);
    }
    if (amountType.present) {
      map['amount_type'] = Variable<String>(amountType.value);
    }
    if (amountBaisas.present) {
      map['amount_baisas'] = Variable<int>(amountBaisas.value);
    }
    if (percent.present) {
      map['percent'] = Variable<double>(percent.value);
    }
    if (validityStart.present) {
      map['validity_start'] = Variable<DateTime>(validityStart.value);
    }
    if (validityEnd.present) {
      map['validity_end'] = Variable<DateTime>(validityEnd.value);
    }
    if (dayofweekMask.present) {
      map['dayofweek_mask'] = Variable<int>(dayofweekMask.value);
    }
    if (timeStart.present) {
      map['time_start'] = Variable<String>(timeStart.value);
    }
    if (timeEnd.present) {
      map['time_end'] = Variable<String>(timeEnd.value);
    }
    if (branchScopeJson.present) {
      map['branch_scope_json'] = Variable<String>(branchScopeJson.value);
    }
    if (stackable.present) {
      map['stackable'] = Variable<bool>(stackable.value);
    }
    if (requiresManagerApproval.present) {
      map['requires_manager_approval'] = Variable<bool>(
        requiresManagerApproval.value,
      );
    }
    if (autoApply.present) {
      map['auto_apply'] = Variable<bool>(autoApply.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (targetsJson.present) {
      map['targets_json'] = Variable<String>(targetsJson.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DiscountsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('scope: $scope, ')
          ..write('amountType: $amountType, ')
          ..write('amountBaisas: $amountBaisas, ')
          ..write('percent: $percent, ')
          ..write('validityStart: $validityStart, ')
          ..write('validityEnd: $validityEnd, ')
          ..write('dayofweekMask: $dayofweekMask, ')
          ..write('timeStart: $timeStart, ')
          ..write('timeEnd: $timeEnd, ')
          ..write('branchScopeJson: $branchScopeJson, ')
          ..write('stackable: $stackable, ')
          ..write('requiresManagerApproval: $requiresManagerApproval, ')
          ..write('autoApply: $autoApply, ')
          ..write('status: $status, ')
          ..write('targetsJson: $targetsJson')
          ..write(')'))
        .toString();
  }
}

class $LoyaltyRulesTable extends LoyaltyRules
    with TableInfo<$LoyaltyRulesTable, LoyaltyRuleRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LoyaltyRulesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _configJsonMeta = const VerificationMeta(
    'configJson',
  );
  @override
  late final GeneratedColumn<String> configJson = GeneratedColumn<String>(
    'config_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('{}'),
  );
  static const VerificationMeta _validityStartMeta = const VerificationMeta(
    'validityStart',
  );
  @override
  late final GeneratedColumn<DateTime> validityStart =
      GeneratedColumn<DateTime>(
        'validity_start',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _validityEndMeta = const VerificationMeta(
    'validityEnd',
  );
  @override
  late final GeneratedColumn<DateTime> validityEnd = GeneratedColumn<DateTime>(
    'validity_end',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    type,
    configJson,
    validityStart,
    validityEnd,
    status,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'loyalty_rules';
  @override
  VerificationContext validateIntegrity(
    Insertable<LoyaltyRuleRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    }
    if (data.containsKey('config_json')) {
      context.handle(
        _configJsonMeta,
        configJson.isAcceptableOrUnknown(data['config_json']!, _configJsonMeta),
      );
    }
    if (data.containsKey('validity_start')) {
      context.handle(
        _validityStartMeta,
        validityStart.isAcceptableOrUnknown(
          data['validity_start']!,
          _validityStartMeta,
        ),
      );
    }
    if (data.containsKey('validity_end')) {
      context.handle(
        _validityEndMeta,
        validityEnd.isAcceptableOrUnknown(
          data['validity_end']!,
          _validityEndMeta,
        ),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LoyaltyRuleRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LoyaltyRuleRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      ),
      configJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}config_json'],
      )!,
      validityStart: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}validity_start'],
      ),
      validityEnd: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}validity_end'],
      ),
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      ),
    );
  }

  @override
  $LoyaltyRulesTable createAlias(String alias) {
    return $LoyaltyRulesTable(attachedDatabase, alias);
  }
}

class LoyaltyRuleRow extends DataClass implements Insertable<LoyaltyRuleRow> {
  final int id;
  final String name;
  final String? type;
  final String configJson;
  final DateTime? validityStart;
  final DateTime? validityEnd;
  final String? status;
  const LoyaltyRuleRow({
    required this.id,
    required this.name,
    this.type,
    required this.configJson,
    this.validityStart,
    this.validityEnd,
    this.status,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || type != null) {
      map['type'] = Variable<String>(type);
    }
    map['config_json'] = Variable<String>(configJson);
    if (!nullToAbsent || validityStart != null) {
      map['validity_start'] = Variable<DateTime>(validityStart);
    }
    if (!nullToAbsent || validityEnd != null) {
      map['validity_end'] = Variable<DateTime>(validityEnd);
    }
    if (!nullToAbsent || status != null) {
      map['status'] = Variable<String>(status);
    }
    return map;
  }

  LoyaltyRulesCompanion toCompanion(bool nullToAbsent) {
    return LoyaltyRulesCompanion(
      id: Value(id),
      name: Value(name),
      type: type == null && nullToAbsent ? const Value.absent() : Value(type),
      configJson: Value(configJson),
      validityStart: validityStart == null && nullToAbsent
          ? const Value.absent()
          : Value(validityStart),
      validityEnd: validityEnd == null && nullToAbsent
          ? const Value.absent()
          : Value(validityEnd),
      status: status == null && nullToAbsent
          ? const Value.absent()
          : Value(status),
    );
  }

  factory LoyaltyRuleRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LoyaltyRuleRow(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      type: serializer.fromJson<String?>(json['type']),
      configJson: serializer.fromJson<String>(json['configJson']),
      validityStart: serializer.fromJson<DateTime?>(json['validityStart']),
      validityEnd: serializer.fromJson<DateTime?>(json['validityEnd']),
      status: serializer.fromJson<String?>(json['status']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'type': serializer.toJson<String?>(type),
      'configJson': serializer.toJson<String>(configJson),
      'validityStart': serializer.toJson<DateTime?>(validityStart),
      'validityEnd': serializer.toJson<DateTime?>(validityEnd),
      'status': serializer.toJson<String?>(status),
    };
  }

  LoyaltyRuleRow copyWith({
    int? id,
    String? name,
    Value<String?> type = const Value.absent(),
    String? configJson,
    Value<DateTime?> validityStart = const Value.absent(),
    Value<DateTime?> validityEnd = const Value.absent(),
    Value<String?> status = const Value.absent(),
  }) => LoyaltyRuleRow(
    id: id ?? this.id,
    name: name ?? this.name,
    type: type.present ? type.value : this.type,
    configJson: configJson ?? this.configJson,
    validityStart: validityStart.present
        ? validityStart.value
        : this.validityStart,
    validityEnd: validityEnd.present ? validityEnd.value : this.validityEnd,
    status: status.present ? status.value : this.status,
  );
  LoyaltyRuleRow copyWithCompanion(LoyaltyRulesCompanion data) {
    return LoyaltyRuleRow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      type: data.type.present ? data.type.value : this.type,
      configJson: data.configJson.present
          ? data.configJson.value
          : this.configJson,
      validityStart: data.validityStart.present
          ? data.validityStart.value
          : this.validityStart,
      validityEnd: data.validityEnd.present
          ? data.validityEnd.value
          : this.validityEnd,
      status: data.status.present ? data.status.value : this.status,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LoyaltyRuleRow(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('type: $type, ')
          ..write('configJson: $configJson, ')
          ..write('validityStart: $validityStart, ')
          ..write('validityEnd: $validityEnd, ')
          ..write('status: $status')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    type,
    configJson,
    validityStart,
    validityEnd,
    status,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LoyaltyRuleRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.type == this.type &&
          other.configJson == this.configJson &&
          other.validityStart == this.validityStart &&
          other.validityEnd == this.validityEnd &&
          other.status == this.status);
}

class LoyaltyRulesCompanion extends UpdateCompanion<LoyaltyRuleRow> {
  final Value<int> id;
  final Value<String> name;
  final Value<String?> type;
  final Value<String> configJson;
  final Value<DateTime?> validityStart;
  final Value<DateTime?> validityEnd;
  final Value<String?> status;
  const LoyaltyRulesCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.type = const Value.absent(),
    this.configJson = const Value.absent(),
    this.validityStart = const Value.absent(),
    this.validityEnd = const Value.absent(),
    this.status = const Value.absent(),
  });
  LoyaltyRulesCompanion.insert({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.type = const Value.absent(),
    this.configJson = const Value.absent(),
    this.validityStart = const Value.absent(),
    this.validityEnd = const Value.absent(),
    this.status = const Value.absent(),
  });
  static Insertable<LoyaltyRuleRow> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<String>? type,
    Expression<String>? configJson,
    Expression<DateTime>? validityStart,
    Expression<DateTime>? validityEnd,
    Expression<String>? status,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (type != null) 'type': type,
      if (configJson != null) 'config_json': configJson,
      if (validityStart != null) 'validity_start': validityStart,
      if (validityEnd != null) 'validity_end': validityEnd,
      if (status != null) 'status': status,
    });
  }

  LoyaltyRulesCompanion copyWith({
    Value<int>? id,
    Value<String>? name,
    Value<String?>? type,
    Value<String>? configJson,
    Value<DateTime?>? validityStart,
    Value<DateTime?>? validityEnd,
    Value<String?>? status,
  }) {
    return LoyaltyRulesCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      configJson: configJson ?? this.configJson,
      validityStart: validityStart ?? this.validityStart,
      validityEnd: validityEnd ?? this.validityEnd,
      status: status ?? this.status,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (configJson.present) {
      map['config_json'] = Variable<String>(configJson.value);
    }
    if (validityStart.present) {
      map['validity_start'] = Variable<DateTime>(validityStart.value);
    }
    if (validityEnd.present) {
      map['validity_end'] = Variable<DateTime>(validityEnd.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LoyaltyRulesCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('type: $type, ')
          ..write('configJson: $configJson, ')
          ..write('validityStart: $validityStart, ')
          ..write('validityEnd: $validityEnd, ')
          ..write('status: $status')
          ..write(')'))
        .toString();
  }
}

class $CachedCustomersTable extends CachedCustomers
    with TableInfo<$CachedCustomersTable, CustomerRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedCustomersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _phoneMeta = const VerificationMeta('phone');
  @override
  late final GeneratedColumn<String> phone = GeneratedColumn<String>(
    'phone',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _walletBalanceBaisasMeta =
      const VerificationMeta('walletBalanceBaisas');
  @override
  late final GeneratedColumn<int> walletBalanceBaisas = GeneratedColumn<int>(
    'wallet_balance_baisas',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _loyaltyJsonMeta = const VerificationMeta(
    'loyaltyJson',
  );
  @override
  late final GeneratedColumn<String> loyaltyJson = GeneratedColumn<String>(
    'loyalty_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _platesJsonMeta = const VerificationMeta(
    'platesJson',
  );
  @override
  late final GeneratedColumn<String> platesJson = GeneratedColumn<String>(
    'plates_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    phone,
    walletBalanceBaisas,
    loyaltyJson,
    platesJson,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_customers';
  @override
  VerificationContext validateIntegrity(
    Insertable<CustomerRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    }
    if (data.containsKey('phone')) {
      context.handle(
        _phoneMeta,
        phone.isAcceptableOrUnknown(data['phone']!, _phoneMeta),
      );
    }
    if (data.containsKey('wallet_balance_baisas')) {
      context.handle(
        _walletBalanceBaisasMeta,
        walletBalanceBaisas.isAcceptableOrUnknown(
          data['wallet_balance_baisas']!,
          _walletBalanceBaisasMeta,
        ),
      );
    }
    if (data.containsKey('loyalty_json')) {
      context.handle(
        _loyaltyJsonMeta,
        loyaltyJson.isAcceptableOrUnknown(
          data['loyalty_json']!,
          _loyaltyJsonMeta,
        ),
      );
    }
    if (data.containsKey('plates_json')) {
      context.handle(
        _platesJsonMeta,
        platesJson.isAcceptableOrUnknown(data['plates_json']!, _platesJsonMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CustomerRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CustomerRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      phone: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}phone'],
      ),
      walletBalanceBaisas: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}wallet_balance_baisas'],
      )!,
      loyaltyJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}loyalty_json'],
      )!,
      platesJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}plates_json'],
      )!,
    );
  }

  @override
  $CachedCustomersTable createAlias(String alias) {
    return $CachedCustomersTable(attachedDatabase, alias);
  }
}

class CustomerRow extends DataClass implements Insertable<CustomerRow> {
  final int id;
  final String name;
  final String? phone;
  final int walletBalanceBaisas;
  final String loyaltyJson;
  final String platesJson;
  const CustomerRow({
    required this.id,
    required this.name,
    this.phone,
    required this.walletBalanceBaisas,
    required this.loyaltyJson,
    required this.platesJson,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || phone != null) {
      map['phone'] = Variable<String>(phone);
    }
    map['wallet_balance_baisas'] = Variable<int>(walletBalanceBaisas);
    map['loyalty_json'] = Variable<String>(loyaltyJson);
    map['plates_json'] = Variable<String>(platesJson);
    return map;
  }

  CachedCustomersCompanion toCompanion(bool nullToAbsent) {
    return CachedCustomersCompanion(
      id: Value(id),
      name: Value(name),
      phone: phone == null && nullToAbsent
          ? const Value.absent()
          : Value(phone),
      walletBalanceBaisas: Value(walletBalanceBaisas),
      loyaltyJson: Value(loyaltyJson),
      platesJson: Value(platesJson),
    );
  }

  factory CustomerRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CustomerRow(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      phone: serializer.fromJson<String?>(json['phone']),
      walletBalanceBaisas: serializer.fromJson<int>(
        json['walletBalanceBaisas'],
      ),
      loyaltyJson: serializer.fromJson<String>(json['loyaltyJson']),
      platesJson: serializer.fromJson<String>(json['platesJson']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'phone': serializer.toJson<String?>(phone),
      'walletBalanceBaisas': serializer.toJson<int>(walletBalanceBaisas),
      'loyaltyJson': serializer.toJson<String>(loyaltyJson),
      'platesJson': serializer.toJson<String>(platesJson),
    };
  }

  CustomerRow copyWith({
    int? id,
    String? name,
    Value<String?> phone = const Value.absent(),
    int? walletBalanceBaisas,
    String? loyaltyJson,
    String? platesJson,
  }) => CustomerRow(
    id: id ?? this.id,
    name: name ?? this.name,
    phone: phone.present ? phone.value : this.phone,
    walletBalanceBaisas: walletBalanceBaisas ?? this.walletBalanceBaisas,
    loyaltyJson: loyaltyJson ?? this.loyaltyJson,
    platesJson: platesJson ?? this.platesJson,
  );
  CustomerRow copyWithCompanion(CachedCustomersCompanion data) {
    return CustomerRow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      phone: data.phone.present ? data.phone.value : this.phone,
      walletBalanceBaisas: data.walletBalanceBaisas.present
          ? data.walletBalanceBaisas.value
          : this.walletBalanceBaisas,
      loyaltyJson: data.loyaltyJson.present
          ? data.loyaltyJson.value
          : this.loyaltyJson,
      platesJson: data.platesJson.present
          ? data.platesJson.value
          : this.platesJson,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CustomerRow(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('phone: $phone, ')
          ..write('walletBalanceBaisas: $walletBalanceBaisas, ')
          ..write('loyaltyJson: $loyaltyJson, ')
          ..write('platesJson: $platesJson')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    phone,
    walletBalanceBaisas,
    loyaltyJson,
    platesJson,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CustomerRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.phone == this.phone &&
          other.walletBalanceBaisas == this.walletBalanceBaisas &&
          other.loyaltyJson == this.loyaltyJson &&
          other.platesJson == this.platesJson);
}

class CachedCustomersCompanion extends UpdateCompanion<CustomerRow> {
  final Value<int> id;
  final Value<String> name;
  final Value<String?> phone;
  final Value<int> walletBalanceBaisas;
  final Value<String> loyaltyJson;
  final Value<String> platesJson;
  const CachedCustomersCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.phone = const Value.absent(),
    this.walletBalanceBaisas = const Value.absent(),
    this.loyaltyJson = const Value.absent(),
    this.platesJson = const Value.absent(),
  });
  CachedCustomersCompanion.insert({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.phone = const Value.absent(),
    this.walletBalanceBaisas = const Value.absent(),
    this.loyaltyJson = const Value.absent(),
    this.platesJson = const Value.absent(),
  });
  static Insertable<CustomerRow> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<String>? phone,
    Expression<int>? walletBalanceBaisas,
    Expression<String>? loyaltyJson,
    Expression<String>? platesJson,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (phone != null) 'phone': phone,
      if (walletBalanceBaisas != null)
        'wallet_balance_baisas': walletBalanceBaisas,
      if (loyaltyJson != null) 'loyalty_json': loyaltyJson,
      if (platesJson != null) 'plates_json': platesJson,
    });
  }

  CachedCustomersCompanion copyWith({
    Value<int>? id,
    Value<String>? name,
    Value<String?>? phone,
    Value<int>? walletBalanceBaisas,
    Value<String>? loyaltyJson,
    Value<String>? platesJson,
  }) {
    return CachedCustomersCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      walletBalanceBaisas: walletBalanceBaisas ?? this.walletBalanceBaisas,
      loyaltyJson: loyaltyJson ?? this.loyaltyJson,
      platesJson: platesJson ?? this.platesJson,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (phone.present) {
      map['phone'] = Variable<String>(phone.value);
    }
    if (walletBalanceBaisas.present) {
      map['wallet_balance_baisas'] = Variable<int>(walletBalanceBaisas.value);
    }
    if (loyaltyJson.present) {
      map['loyalty_json'] = Variable<String>(loyaltyJson.value);
    }
    if (platesJson.present) {
      map['plates_json'] = Variable<String>(platesJson.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedCustomersCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('phone: $phone, ')
          ..write('walletBalanceBaisas: $walletBalanceBaisas, ')
          ..write('loyaltyJson: $loyaltyJson, ')
          ..write('platesJson: $platesJson')
          ..write(')'))
        .toString();
  }
}

class $IngredientsTable extends Ingredients
    with TableInfo<$IngredientsTable, IngredientRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $IngredientsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _nameArMeta = const VerificationMeta('nameAr');
  @override
  late final GeneratedColumn<String> nameAr = GeneratedColumn<String>(
    'name_ar',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _unitMeta = const VerificationMeta('unit');
  @override
  late final GeneratedColumn<String> unit = GeneratedColumn<String>(
    'unit',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _pieceUnitLabelMeta = const VerificationMeta(
    'pieceUnitLabel',
  );
  @override
  late final GeneratedColumn<String> pieceUnitLabel = GeneratedColumn<String>(
    'piece_unit_label',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _pieceUnitLabelArMeta = const VerificationMeta(
    'pieceUnitLabelAr',
  );
  @override
  late final GeneratedColumn<String> pieceUnitLabelAr = GeneratedColumn<String>(
    'piece_unit_label_ar',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _unitsPerPieceMeta = const VerificationMeta(
    'unitsPerPiece',
  );
  @override
  late final GeneratedColumn<double> unitsPerPiece = GeneratedColumn<double>(
    'units_per_piece',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _allowFractionalPiecesMeta =
      const VerificationMeta('allowFractionalPieces');
  @override
  late final GeneratedColumn<bool> allowFractionalPieces =
      GeneratedColumn<bool>(
        'allow_fractional_pieces',
        aliasedName,
        false,
        type: DriftSqlType.bool,
        requiredDuringInsert: false,
        defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("allow_fractional_pieces" IN (0, 1))',
        ),
        defaultValue: const Constant(true),
      );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    nameAr,
    unit,
    pieceUnitLabel,
    pieceUnitLabelAr,
    unitsPerPiece,
    allowFractionalPieces,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'ingredients';
  @override
  VerificationContext validateIntegrity(
    Insertable<IngredientRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    }
    if (data.containsKey('name_ar')) {
      context.handle(
        _nameArMeta,
        nameAr.isAcceptableOrUnknown(data['name_ar']!, _nameArMeta),
      );
    }
    if (data.containsKey('unit')) {
      context.handle(
        _unitMeta,
        unit.isAcceptableOrUnknown(data['unit']!, _unitMeta),
      );
    }
    if (data.containsKey('piece_unit_label')) {
      context.handle(
        _pieceUnitLabelMeta,
        pieceUnitLabel.isAcceptableOrUnknown(
          data['piece_unit_label']!,
          _pieceUnitLabelMeta,
        ),
      );
    }
    if (data.containsKey('piece_unit_label_ar')) {
      context.handle(
        _pieceUnitLabelArMeta,
        pieceUnitLabelAr.isAcceptableOrUnknown(
          data['piece_unit_label_ar']!,
          _pieceUnitLabelArMeta,
        ),
      );
    }
    if (data.containsKey('units_per_piece')) {
      context.handle(
        _unitsPerPieceMeta,
        unitsPerPiece.isAcceptableOrUnknown(
          data['units_per_piece']!,
          _unitsPerPieceMeta,
        ),
      );
    }
    if (data.containsKey('allow_fractional_pieces')) {
      context.handle(
        _allowFractionalPiecesMeta,
        allowFractionalPieces.isAcceptableOrUnknown(
          data['allow_fractional_pieces']!,
          _allowFractionalPiecesMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  IngredientRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return IngredientRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      nameAr: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name_ar'],
      ),
      unit: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}unit'],
      ),
      pieceUnitLabel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}piece_unit_label'],
      ),
      pieceUnitLabelAr: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}piece_unit_label_ar'],
      ),
      unitsPerPiece: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}units_per_piece'],
      ),
      allowFractionalPieces: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}allow_fractional_pieces'],
      )!,
    );
  }

  @override
  $IngredientsTable createAlias(String alias) {
    return $IngredientsTable(attachedDatabase, alias);
  }
}

class IngredientRow extends DataClass implements Insertable<IngredientRow> {
  final int id;
  final String name;
  final String? nameAr;
  final String? unit;
  final String? pieceUnitLabel;
  final String? pieceUnitLabelAr;
  final double? unitsPerPiece;
  final bool allowFractionalPieces;
  const IngredientRow({
    required this.id,
    required this.name,
    this.nameAr,
    this.unit,
    this.pieceUnitLabel,
    this.pieceUnitLabelAr,
    this.unitsPerPiece,
    required this.allowFractionalPieces,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || nameAr != null) {
      map['name_ar'] = Variable<String>(nameAr);
    }
    if (!nullToAbsent || unit != null) {
      map['unit'] = Variable<String>(unit);
    }
    if (!nullToAbsent || pieceUnitLabel != null) {
      map['piece_unit_label'] = Variable<String>(pieceUnitLabel);
    }
    if (!nullToAbsent || pieceUnitLabelAr != null) {
      map['piece_unit_label_ar'] = Variable<String>(pieceUnitLabelAr);
    }
    if (!nullToAbsent || unitsPerPiece != null) {
      map['units_per_piece'] = Variable<double>(unitsPerPiece);
    }
    map['allow_fractional_pieces'] = Variable<bool>(allowFractionalPieces);
    return map;
  }

  IngredientsCompanion toCompanion(bool nullToAbsent) {
    return IngredientsCompanion(
      id: Value(id),
      name: Value(name),
      nameAr: nameAr == null && nullToAbsent
          ? const Value.absent()
          : Value(nameAr),
      unit: unit == null && nullToAbsent ? const Value.absent() : Value(unit),
      pieceUnitLabel: pieceUnitLabel == null && nullToAbsent
          ? const Value.absent()
          : Value(pieceUnitLabel),
      pieceUnitLabelAr: pieceUnitLabelAr == null && nullToAbsent
          ? const Value.absent()
          : Value(pieceUnitLabelAr),
      unitsPerPiece: unitsPerPiece == null && nullToAbsent
          ? const Value.absent()
          : Value(unitsPerPiece),
      allowFractionalPieces: Value(allowFractionalPieces),
    );
  }

  factory IngredientRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return IngredientRow(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      nameAr: serializer.fromJson<String?>(json['nameAr']),
      unit: serializer.fromJson<String?>(json['unit']),
      pieceUnitLabel: serializer.fromJson<String?>(json['pieceUnitLabel']),
      pieceUnitLabelAr: serializer.fromJson<String?>(json['pieceUnitLabelAr']),
      unitsPerPiece: serializer.fromJson<double?>(json['unitsPerPiece']),
      allowFractionalPieces: serializer.fromJson<bool>(
        json['allowFractionalPieces'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'nameAr': serializer.toJson<String?>(nameAr),
      'unit': serializer.toJson<String?>(unit),
      'pieceUnitLabel': serializer.toJson<String?>(pieceUnitLabel),
      'pieceUnitLabelAr': serializer.toJson<String?>(pieceUnitLabelAr),
      'unitsPerPiece': serializer.toJson<double?>(unitsPerPiece),
      'allowFractionalPieces': serializer.toJson<bool>(allowFractionalPieces),
    };
  }

  IngredientRow copyWith({
    int? id,
    String? name,
    Value<String?> nameAr = const Value.absent(),
    Value<String?> unit = const Value.absent(),
    Value<String?> pieceUnitLabel = const Value.absent(),
    Value<String?> pieceUnitLabelAr = const Value.absent(),
    Value<double?> unitsPerPiece = const Value.absent(),
    bool? allowFractionalPieces,
  }) => IngredientRow(
    id: id ?? this.id,
    name: name ?? this.name,
    nameAr: nameAr.present ? nameAr.value : this.nameAr,
    unit: unit.present ? unit.value : this.unit,
    pieceUnitLabel: pieceUnitLabel.present
        ? pieceUnitLabel.value
        : this.pieceUnitLabel,
    pieceUnitLabelAr: pieceUnitLabelAr.present
        ? pieceUnitLabelAr.value
        : this.pieceUnitLabelAr,
    unitsPerPiece: unitsPerPiece.present
        ? unitsPerPiece.value
        : this.unitsPerPiece,
    allowFractionalPieces: allowFractionalPieces ?? this.allowFractionalPieces,
  );
  IngredientRow copyWithCompanion(IngredientsCompanion data) {
    return IngredientRow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      nameAr: data.nameAr.present ? data.nameAr.value : this.nameAr,
      unit: data.unit.present ? data.unit.value : this.unit,
      pieceUnitLabel: data.pieceUnitLabel.present
          ? data.pieceUnitLabel.value
          : this.pieceUnitLabel,
      pieceUnitLabelAr: data.pieceUnitLabelAr.present
          ? data.pieceUnitLabelAr.value
          : this.pieceUnitLabelAr,
      unitsPerPiece: data.unitsPerPiece.present
          ? data.unitsPerPiece.value
          : this.unitsPerPiece,
      allowFractionalPieces: data.allowFractionalPieces.present
          ? data.allowFractionalPieces.value
          : this.allowFractionalPieces,
    );
  }

  @override
  String toString() {
    return (StringBuffer('IngredientRow(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('nameAr: $nameAr, ')
          ..write('unit: $unit, ')
          ..write('pieceUnitLabel: $pieceUnitLabel, ')
          ..write('pieceUnitLabelAr: $pieceUnitLabelAr, ')
          ..write('unitsPerPiece: $unitsPerPiece, ')
          ..write('allowFractionalPieces: $allowFractionalPieces')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    nameAr,
    unit,
    pieceUnitLabel,
    pieceUnitLabelAr,
    unitsPerPiece,
    allowFractionalPieces,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is IngredientRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.nameAr == this.nameAr &&
          other.unit == this.unit &&
          other.pieceUnitLabel == this.pieceUnitLabel &&
          other.pieceUnitLabelAr == this.pieceUnitLabelAr &&
          other.unitsPerPiece == this.unitsPerPiece &&
          other.allowFractionalPieces == this.allowFractionalPieces);
}

class IngredientsCompanion extends UpdateCompanion<IngredientRow> {
  final Value<int> id;
  final Value<String> name;
  final Value<String?> nameAr;
  final Value<String?> unit;
  final Value<String?> pieceUnitLabel;
  final Value<String?> pieceUnitLabelAr;
  final Value<double?> unitsPerPiece;
  final Value<bool> allowFractionalPieces;
  const IngredientsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.nameAr = const Value.absent(),
    this.unit = const Value.absent(),
    this.pieceUnitLabel = const Value.absent(),
    this.pieceUnitLabelAr = const Value.absent(),
    this.unitsPerPiece = const Value.absent(),
    this.allowFractionalPieces = const Value.absent(),
  });
  IngredientsCompanion.insert({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.nameAr = const Value.absent(),
    this.unit = const Value.absent(),
    this.pieceUnitLabel = const Value.absent(),
    this.pieceUnitLabelAr = const Value.absent(),
    this.unitsPerPiece = const Value.absent(),
    this.allowFractionalPieces = const Value.absent(),
  });
  static Insertable<IngredientRow> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<String>? nameAr,
    Expression<String>? unit,
    Expression<String>? pieceUnitLabel,
    Expression<String>? pieceUnitLabelAr,
    Expression<double>? unitsPerPiece,
    Expression<bool>? allowFractionalPieces,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (nameAr != null) 'name_ar': nameAr,
      if (unit != null) 'unit': unit,
      if (pieceUnitLabel != null) 'piece_unit_label': pieceUnitLabel,
      if (pieceUnitLabelAr != null) 'piece_unit_label_ar': pieceUnitLabelAr,
      if (unitsPerPiece != null) 'units_per_piece': unitsPerPiece,
      if (allowFractionalPieces != null)
        'allow_fractional_pieces': allowFractionalPieces,
    });
  }

  IngredientsCompanion copyWith({
    Value<int>? id,
    Value<String>? name,
    Value<String?>? nameAr,
    Value<String?>? unit,
    Value<String?>? pieceUnitLabel,
    Value<String?>? pieceUnitLabelAr,
    Value<double?>? unitsPerPiece,
    Value<bool>? allowFractionalPieces,
  }) {
    return IngredientsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      nameAr: nameAr ?? this.nameAr,
      unit: unit ?? this.unit,
      pieceUnitLabel: pieceUnitLabel ?? this.pieceUnitLabel,
      pieceUnitLabelAr: pieceUnitLabelAr ?? this.pieceUnitLabelAr,
      unitsPerPiece: unitsPerPiece ?? this.unitsPerPiece,
      allowFractionalPieces:
          allowFractionalPieces ?? this.allowFractionalPieces,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (nameAr.present) {
      map['name_ar'] = Variable<String>(nameAr.value);
    }
    if (unit.present) {
      map['unit'] = Variable<String>(unit.value);
    }
    if (pieceUnitLabel.present) {
      map['piece_unit_label'] = Variable<String>(pieceUnitLabel.value);
    }
    if (pieceUnitLabelAr.present) {
      map['piece_unit_label_ar'] = Variable<String>(pieceUnitLabelAr.value);
    }
    if (unitsPerPiece.present) {
      map['units_per_piece'] = Variable<double>(unitsPerPiece.value);
    }
    if (allowFractionalPieces.present) {
      map['allow_fractional_pieces'] = Variable<bool>(
        allowFractionalPieces.value,
      );
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('IngredientsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('nameAr: $nameAr, ')
          ..write('unit: $unit, ')
          ..write('pieceUnitLabel: $pieceUnitLabel, ')
          ..write('pieceUnitLabelAr: $pieceUnitLabelAr, ')
          ..write('unitsPerPiece: $unitsPerPiece, ')
          ..write('allowFractionalPieces: $allowFractionalPieces')
          ..write(')'))
        .toString();
  }
}

class $VoidReasonsTable extends VoidReasons
    with TableInfo<$VoidReasonsTable, VoidReasonRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $VoidReasonsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _codeMeta = const VerificationMeta('code');
  @override
  late final GeneratedColumn<String> code = GeneratedColumn<String>(
    'code',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _nameArMeta = const VerificationMeta('nameAr');
  @override
  late final GeneratedColumn<String> nameAr = GeneratedColumn<String>(
    'name_ar',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _affectsInventoryMeta = const VerificationMeta(
    'affectsInventory',
  );
  @override
  late final GeneratedColumn<bool> affectsInventory = GeneratedColumn<bool>(
    'affects_inventory',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("affects_inventory" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _requiresManagerMeta = const VerificationMeta(
    'requiresManager',
  );
  @override
  late final GeneratedColumn<bool> requiresManager = GeneratedColumn<bool>(
    'requires_manager',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("requires_manager" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    code,
    name,
    nameAr,
    affectsInventory,
    requiresManager,
    sortOrder,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'void_reasons';
  @override
  VerificationContext validateIntegrity(
    Insertable<VoidReasonRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('code')) {
      context.handle(
        _codeMeta,
        code.isAcceptableOrUnknown(data['code']!, _codeMeta),
      );
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    }
    if (data.containsKey('name_ar')) {
      context.handle(
        _nameArMeta,
        nameAr.isAcceptableOrUnknown(data['name_ar']!, _nameArMeta),
      );
    }
    if (data.containsKey('affects_inventory')) {
      context.handle(
        _affectsInventoryMeta,
        affectsInventory.isAcceptableOrUnknown(
          data['affects_inventory']!,
          _affectsInventoryMeta,
        ),
      );
    }
    if (data.containsKey('requires_manager')) {
      context.handle(
        _requiresManagerMeta,
        requiresManager.isAcceptableOrUnknown(
          data['requires_manager']!,
          _requiresManagerMeta,
        ),
      );
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  VoidReasonRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return VoidReasonRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      code: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}code'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      nameAr: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name_ar'],
      ),
      affectsInventory: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}affects_inventory'],
      )!,
      requiresManager: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}requires_manager'],
      )!,
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
    );
  }

  @override
  $VoidReasonsTable createAlias(String alias) {
    return $VoidReasonsTable(attachedDatabase, alias);
  }
}

class VoidReasonRow extends DataClass implements Insertable<VoidReasonRow> {
  final int id;
  final String code;
  final String name;
  final String? nameAr;
  final bool affectsInventory;
  final bool requiresManager;
  final int sortOrder;
  const VoidReasonRow({
    required this.id,
    required this.code,
    required this.name,
    this.nameAr,
    required this.affectsInventory,
    required this.requiresManager,
    required this.sortOrder,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['code'] = Variable<String>(code);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || nameAr != null) {
      map['name_ar'] = Variable<String>(nameAr);
    }
    map['affects_inventory'] = Variable<bool>(affectsInventory);
    map['requires_manager'] = Variable<bool>(requiresManager);
    map['sort_order'] = Variable<int>(sortOrder);
    return map;
  }

  VoidReasonsCompanion toCompanion(bool nullToAbsent) {
    return VoidReasonsCompanion(
      id: Value(id),
      code: Value(code),
      name: Value(name),
      nameAr: nameAr == null && nullToAbsent
          ? const Value.absent()
          : Value(nameAr),
      affectsInventory: Value(affectsInventory),
      requiresManager: Value(requiresManager),
      sortOrder: Value(sortOrder),
    );
  }

  factory VoidReasonRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return VoidReasonRow(
      id: serializer.fromJson<int>(json['id']),
      code: serializer.fromJson<String>(json['code']),
      name: serializer.fromJson<String>(json['name']),
      nameAr: serializer.fromJson<String?>(json['nameAr']),
      affectsInventory: serializer.fromJson<bool>(json['affectsInventory']),
      requiresManager: serializer.fromJson<bool>(json['requiresManager']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'code': serializer.toJson<String>(code),
      'name': serializer.toJson<String>(name),
      'nameAr': serializer.toJson<String?>(nameAr),
      'affectsInventory': serializer.toJson<bool>(affectsInventory),
      'requiresManager': serializer.toJson<bool>(requiresManager),
      'sortOrder': serializer.toJson<int>(sortOrder),
    };
  }

  VoidReasonRow copyWith({
    int? id,
    String? code,
    String? name,
    Value<String?> nameAr = const Value.absent(),
    bool? affectsInventory,
    bool? requiresManager,
    int? sortOrder,
  }) => VoidReasonRow(
    id: id ?? this.id,
    code: code ?? this.code,
    name: name ?? this.name,
    nameAr: nameAr.present ? nameAr.value : this.nameAr,
    affectsInventory: affectsInventory ?? this.affectsInventory,
    requiresManager: requiresManager ?? this.requiresManager,
    sortOrder: sortOrder ?? this.sortOrder,
  );
  VoidReasonRow copyWithCompanion(VoidReasonsCompanion data) {
    return VoidReasonRow(
      id: data.id.present ? data.id.value : this.id,
      code: data.code.present ? data.code.value : this.code,
      name: data.name.present ? data.name.value : this.name,
      nameAr: data.nameAr.present ? data.nameAr.value : this.nameAr,
      affectsInventory: data.affectsInventory.present
          ? data.affectsInventory.value
          : this.affectsInventory,
      requiresManager: data.requiresManager.present
          ? data.requiresManager.value
          : this.requiresManager,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
    );
  }

  @override
  String toString() {
    return (StringBuffer('VoidReasonRow(')
          ..write('id: $id, ')
          ..write('code: $code, ')
          ..write('name: $name, ')
          ..write('nameAr: $nameAr, ')
          ..write('affectsInventory: $affectsInventory, ')
          ..write('requiresManager: $requiresManager, ')
          ..write('sortOrder: $sortOrder')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    code,
    name,
    nameAr,
    affectsInventory,
    requiresManager,
    sortOrder,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is VoidReasonRow &&
          other.id == this.id &&
          other.code == this.code &&
          other.name == this.name &&
          other.nameAr == this.nameAr &&
          other.affectsInventory == this.affectsInventory &&
          other.requiresManager == this.requiresManager &&
          other.sortOrder == this.sortOrder);
}

class VoidReasonsCompanion extends UpdateCompanion<VoidReasonRow> {
  final Value<int> id;
  final Value<String> code;
  final Value<String> name;
  final Value<String?> nameAr;
  final Value<bool> affectsInventory;
  final Value<bool> requiresManager;
  final Value<int> sortOrder;
  const VoidReasonsCompanion({
    this.id = const Value.absent(),
    this.code = const Value.absent(),
    this.name = const Value.absent(),
    this.nameAr = const Value.absent(),
    this.affectsInventory = const Value.absent(),
    this.requiresManager = const Value.absent(),
    this.sortOrder = const Value.absent(),
  });
  VoidReasonsCompanion.insert({
    this.id = const Value.absent(),
    this.code = const Value.absent(),
    this.name = const Value.absent(),
    this.nameAr = const Value.absent(),
    this.affectsInventory = const Value.absent(),
    this.requiresManager = const Value.absent(),
    this.sortOrder = const Value.absent(),
  });
  static Insertable<VoidReasonRow> custom({
    Expression<int>? id,
    Expression<String>? code,
    Expression<String>? name,
    Expression<String>? nameAr,
    Expression<bool>? affectsInventory,
    Expression<bool>? requiresManager,
    Expression<int>? sortOrder,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (code != null) 'code': code,
      if (name != null) 'name': name,
      if (nameAr != null) 'name_ar': nameAr,
      if (affectsInventory != null) 'affects_inventory': affectsInventory,
      if (requiresManager != null) 'requires_manager': requiresManager,
      if (sortOrder != null) 'sort_order': sortOrder,
    });
  }

  VoidReasonsCompanion copyWith({
    Value<int>? id,
    Value<String>? code,
    Value<String>? name,
    Value<String?>? nameAr,
    Value<bool>? affectsInventory,
    Value<bool>? requiresManager,
    Value<int>? sortOrder,
  }) {
    return VoidReasonsCompanion(
      id: id ?? this.id,
      code: code ?? this.code,
      name: name ?? this.name,
      nameAr: nameAr ?? this.nameAr,
      affectsInventory: affectsInventory ?? this.affectsInventory,
      requiresManager: requiresManager ?? this.requiresManager,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (code.present) {
      map['code'] = Variable<String>(code.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (nameAr.present) {
      map['name_ar'] = Variable<String>(nameAr.value);
    }
    if (affectsInventory.present) {
      map['affects_inventory'] = Variable<bool>(affectsInventory.value);
    }
    if (requiresManager.present) {
      map['requires_manager'] = Variable<bool>(requiresManager.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('VoidReasonsCompanion(')
          ..write('id: $id, ')
          ..write('code: $code, ')
          ..write('name: $name, ')
          ..write('nameAr: $nameAr, ')
          ..write('affectsInventory: $affectsInventory, ')
          ..write('requiresManager: $requiresManager, ')
          ..write('sortOrder: $sortOrder')
          ..write(')'))
        .toString();
  }
}

class $CompReasonsTable extends CompReasons
    with TableInfo<$CompReasonsTable, CompReasonRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CompReasonsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _codeMeta = const VerificationMeta('code');
  @override
  late final GeneratedColumn<String> code = GeneratedColumn<String>(
    'code',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _nameArMeta = const VerificationMeta('nameAr');
  @override
  late final GeneratedColumn<String> nameAr = GeneratedColumn<String>(
    'name_ar',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _maxAmountBaisasMeta = const VerificationMeta(
    'maxAmountBaisas',
  );
  @override
  late final GeneratedColumn<int> maxAmountBaisas = GeneratedColumn<int>(
    'max_amount_baisas',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    code,
    name,
    nameAr,
    maxAmountBaisas,
    sortOrder,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'comp_reasons';
  @override
  VerificationContext validateIntegrity(
    Insertable<CompReasonRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('code')) {
      context.handle(
        _codeMeta,
        code.isAcceptableOrUnknown(data['code']!, _codeMeta),
      );
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    }
    if (data.containsKey('name_ar')) {
      context.handle(
        _nameArMeta,
        nameAr.isAcceptableOrUnknown(data['name_ar']!, _nameArMeta),
      );
    }
    if (data.containsKey('max_amount_baisas')) {
      context.handle(
        _maxAmountBaisasMeta,
        maxAmountBaisas.isAcceptableOrUnknown(
          data['max_amount_baisas']!,
          _maxAmountBaisasMeta,
        ),
      );
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CompReasonRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CompReasonRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      code: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}code'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      nameAr: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name_ar'],
      ),
      maxAmountBaisas: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}max_amount_baisas'],
      ),
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
    );
  }

  @override
  $CompReasonsTable createAlias(String alias) {
    return $CompReasonsTable(attachedDatabase, alias);
  }
}

class CompReasonRow extends DataClass implements Insertable<CompReasonRow> {
  final int id;
  final String code;
  final String name;
  final String? nameAr;
  final int? maxAmountBaisas;
  final int sortOrder;
  const CompReasonRow({
    required this.id,
    required this.code,
    required this.name,
    this.nameAr,
    this.maxAmountBaisas,
    required this.sortOrder,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['code'] = Variable<String>(code);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || nameAr != null) {
      map['name_ar'] = Variable<String>(nameAr);
    }
    if (!nullToAbsent || maxAmountBaisas != null) {
      map['max_amount_baisas'] = Variable<int>(maxAmountBaisas);
    }
    map['sort_order'] = Variable<int>(sortOrder);
    return map;
  }

  CompReasonsCompanion toCompanion(bool nullToAbsent) {
    return CompReasonsCompanion(
      id: Value(id),
      code: Value(code),
      name: Value(name),
      nameAr: nameAr == null && nullToAbsent
          ? const Value.absent()
          : Value(nameAr),
      maxAmountBaisas: maxAmountBaisas == null && nullToAbsent
          ? const Value.absent()
          : Value(maxAmountBaisas),
      sortOrder: Value(sortOrder),
    );
  }

  factory CompReasonRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CompReasonRow(
      id: serializer.fromJson<int>(json['id']),
      code: serializer.fromJson<String>(json['code']),
      name: serializer.fromJson<String>(json['name']),
      nameAr: serializer.fromJson<String?>(json['nameAr']),
      maxAmountBaisas: serializer.fromJson<int?>(json['maxAmountBaisas']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'code': serializer.toJson<String>(code),
      'name': serializer.toJson<String>(name),
      'nameAr': serializer.toJson<String?>(nameAr),
      'maxAmountBaisas': serializer.toJson<int?>(maxAmountBaisas),
      'sortOrder': serializer.toJson<int>(sortOrder),
    };
  }

  CompReasonRow copyWith({
    int? id,
    String? code,
    String? name,
    Value<String?> nameAr = const Value.absent(),
    Value<int?> maxAmountBaisas = const Value.absent(),
    int? sortOrder,
  }) => CompReasonRow(
    id: id ?? this.id,
    code: code ?? this.code,
    name: name ?? this.name,
    nameAr: nameAr.present ? nameAr.value : this.nameAr,
    maxAmountBaisas: maxAmountBaisas.present
        ? maxAmountBaisas.value
        : this.maxAmountBaisas,
    sortOrder: sortOrder ?? this.sortOrder,
  );
  CompReasonRow copyWithCompanion(CompReasonsCompanion data) {
    return CompReasonRow(
      id: data.id.present ? data.id.value : this.id,
      code: data.code.present ? data.code.value : this.code,
      name: data.name.present ? data.name.value : this.name,
      nameAr: data.nameAr.present ? data.nameAr.value : this.nameAr,
      maxAmountBaisas: data.maxAmountBaisas.present
          ? data.maxAmountBaisas.value
          : this.maxAmountBaisas,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CompReasonRow(')
          ..write('id: $id, ')
          ..write('code: $code, ')
          ..write('name: $name, ')
          ..write('nameAr: $nameAr, ')
          ..write('maxAmountBaisas: $maxAmountBaisas, ')
          ..write('sortOrder: $sortOrder')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, code, name, nameAr, maxAmountBaisas, sortOrder);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CompReasonRow &&
          other.id == this.id &&
          other.code == this.code &&
          other.name == this.name &&
          other.nameAr == this.nameAr &&
          other.maxAmountBaisas == this.maxAmountBaisas &&
          other.sortOrder == this.sortOrder);
}

class CompReasonsCompanion extends UpdateCompanion<CompReasonRow> {
  final Value<int> id;
  final Value<String> code;
  final Value<String> name;
  final Value<String?> nameAr;
  final Value<int?> maxAmountBaisas;
  final Value<int> sortOrder;
  const CompReasonsCompanion({
    this.id = const Value.absent(),
    this.code = const Value.absent(),
    this.name = const Value.absent(),
    this.nameAr = const Value.absent(),
    this.maxAmountBaisas = const Value.absent(),
    this.sortOrder = const Value.absent(),
  });
  CompReasonsCompanion.insert({
    this.id = const Value.absent(),
    this.code = const Value.absent(),
    this.name = const Value.absent(),
    this.nameAr = const Value.absent(),
    this.maxAmountBaisas = const Value.absent(),
    this.sortOrder = const Value.absent(),
  });
  static Insertable<CompReasonRow> custom({
    Expression<int>? id,
    Expression<String>? code,
    Expression<String>? name,
    Expression<String>? nameAr,
    Expression<int>? maxAmountBaisas,
    Expression<int>? sortOrder,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (code != null) 'code': code,
      if (name != null) 'name': name,
      if (nameAr != null) 'name_ar': nameAr,
      if (maxAmountBaisas != null) 'max_amount_baisas': maxAmountBaisas,
      if (sortOrder != null) 'sort_order': sortOrder,
    });
  }

  CompReasonsCompanion copyWith({
    Value<int>? id,
    Value<String>? code,
    Value<String>? name,
    Value<String?>? nameAr,
    Value<int?>? maxAmountBaisas,
    Value<int>? sortOrder,
  }) {
    return CompReasonsCompanion(
      id: id ?? this.id,
      code: code ?? this.code,
      name: name ?? this.name,
      nameAr: nameAr ?? this.nameAr,
      maxAmountBaisas: maxAmountBaisas ?? this.maxAmountBaisas,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (code.present) {
      map['code'] = Variable<String>(code.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (nameAr.present) {
      map['name_ar'] = Variable<String>(nameAr.value);
    }
    if (maxAmountBaisas.present) {
      map['max_amount_baisas'] = Variable<int>(maxAmountBaisas.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CompReasonsCompanion(')
          ..write('id: $id, ')
          ..write('code: $code, ')
          ..write('name: $name, ')
          ..write('nameAr: $nameAr, ')
          ..write('maxAmountBaisas: $maxAmountBaisas, ')
          ..write('sortOrder: $sortOrder')
          ..write(')'))
        .toString();
  }
}

class $OffersTable extends Offers with TableInfo<$OffersTable, OfferRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OffersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _nameArMeta = const VerificationMeta('nameAr');
  @override
  late final GeneratedColumn<String> nameAr = GeneratedColumn<String>(
    'name_ar',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _configJsonMeta = const VerificationMeta(
    'configJson',
  );
  @override
  late final GeneratedColumn<String> configJson = GeneratedColumn<String>(
    'config_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('{}'),
  );
  static const VerificationMeta _autoApplyMeta = const VerificationMeta(
    'autoApply',
  );
  @override
  late final GeneratedColumn<bool> autoApply = GeneratedColumn<bool>(
    'auto_apply',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("auto_apply" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _validityStartMeta = const VerificationMeta(
    'validityStart',
  );
  @override
  late final GeneratedColumn<DateTime> validityStart =
      GeneratedColumn<DateTime>(
        'validity_start',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _validityEndMeta = const VerificationMeta(
    'validityEnd',
  );
  @override
  late final GeneratedColumn<DateTime> validityEnd = GeneratedColumn<DateTime>(
    'validity_end',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _dayofweekMaskMeta = const VerificationMeta(
    'dayofweekMask',
  );
  @override
  late final GeneratedColumn<int> dayofweekMask = GeneratedColumn<int>(
    'dayofweek_mask',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _timeStartMeta = const VerificationMeta(
    'timeStart',
  );
  @override
  late final GeneratedColumn<String> timeStart = GeneratedColumn<String>(
    'time_start',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _timeEndMeta = const VerificationMeta(
    'timeEnd',
  );
  @override
  late final GeneratedColumn<String> timeEnd = GeneratedColumn<String>(
    'time_end',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _branchScopeJsonMeta = const VerificationMeta(
    'branchScopeJson',
  );
  @override
  late final GeneratedColumn<String> branchScopeJson = GeneratedColumn<String>(
    'branch_scope_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _maxPerOrderMeta = const VerificationMeta(
    'maxPerOrder',
  );
  @override
  late final GeneratedColumn<int> maxPerOrder = GeneratedColumn<int>(
    'max_per_order',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    nameAr,
    type,
    configJson,
    autoApply,
    validityStart,
    validityEnd,
    dayofweekMask,
    timeStart,
    timeEnd,
    branchScopeJson,
    maxPerOrder,
    status,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'offers';
  @override
  VerificationContext validateIntegrity(
    Insertable<OfferRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    }
    if (data.containsKey('name_ar')) {
      context.handle(
        _nameArMeta,
        nameAr.isAcceptableOrUnknown(data['name_ar']!, _nameArMeta),
      );
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    }
    if (data.containsKey('config_json')) {
      context.handle(
        _configJsonMeta,
        configJson.isAcceptableOrUnknown(data['config_json']!, _configJsonMeta),
      );
    }
    if (data.containsKey('auto_apply')) {
      context.handle(
        _autoApplyMeta,
        autoApply.isAcceptableOrUnknown(data['auto_apply']!, _autoApplyMeta),
      );
    }
    if (data.containsKey('validity_start')) {
      context.handle(
        _validityStartMeta,
        validityStart.isAcceptableOrUnknown(
          data['validity_start']!,
          _validityStartMeta,
        ),
      );
    }
    if (data.containsKey('validity_end')) {
      context.handle(
        _validityEndMeta,
        validityEnd.isAcceptableOrUnknown(
          data['validity_end']!,
          _validityEndMeta,
        ),
      );
    }
    if (data.containsKey('dayofweek_mask')) {
      context.handle(
        _dayofweekMaskMeta,
        dayofweekMask.isAcceptableOrUnknown(
          data['dayofweek_mask']!,
          _dayofweekMaskMeta,
        ),
      );
    }
    if (data.containsKey('time_start')) {
      context.handle(
        _timeStartMeta,
        timeStart.isAcceptableOrUnknown(data['time_start']!, _timeStartMeta),
      );
    }
    if (data.containsKey('time_end')) {
      context.handle(
        _timeEndMeta,
        timeEnd.isAcceptableOrUnknown(data['time_end']!, _timeEndMeta),
      );
    }
    if (data.containsKey('branch_scope_json')) {
      context.handle(
        _branchScopeJsonMeta,
        branchScopeJson.isAcceptableOrUnknown(
          data['branch_scope_json']!,
          _branchScopeJsonMeta,
        ),
      );
    }
    if (data.containsKey('max_per_order')) {
      context.handle(
        _maxPerOrderMeta,
        maxPerOrder.isAcceptableOrUnknown(
          data['max_per_order']!,
          _maxPerOrderMeta,
        ),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  OfferRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OfferRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      nameAr: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name_ar'],
      ),
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      )!,
      configJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}config_json'],
      )!,
      autoApply: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}auto_apply'],
      )!,
      validityStart: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}validity_start'],
      ),
      validityEnd: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}validity_end'],
      ),
      dayofweekMask: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}dayofweek_mask'],
      ),
      timeStart: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}time_start'],
      ),
      timeEnd: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}time_end'],
      ),
      branchScopeJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}branch_scope_json'],
      ),
      maxPerOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}max_per_order'],
      ),
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      ),
    );
  }

  @override
  $OffersTable createAlias(String alias) {
    return $OffersTable(attachedDatabase, alias);
  }
}

class OfferRow extends DataClass implements Insertable<OfferRow> {
  final int id;
  final String name;
  final String? nameAr;
  final String type;
  final String configJson;
  final bool autoApply;
  final DateTime? validityStart;
  final DateTime? validityEnd;
  final int? dayofweekMask;
  final String? timeStart;
  final String? timeEnd;
  final String? branchScopeJson;
  final int? maxPerOrder;
  final String? status;
  const OfferRow({
    required this.id,
    required this.name,
    this.nameAr,
    required this.type,
    required this.configJson,
    required this.autoApply,
    this.validityStart,
    this.validityEnd,
    this.dayofweekMask,
    this.timeStart,
    this.timeEnd,
    this.branchScopeJson,
    this.maxPerOrder,
    this.status,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || nameAr != null) {
      map['name_ar'] = Variable<String>(nameAr);
    }
    map['type'] = Variable<String>(type);
    map['config_json'] = Variable<String>(configJson);
    map['auto_apply'] = Variable<bool>(autoApply);
    if (!nullToAbsent || validityStart != null) {
      map['validity_start'] = Variable<DateTime>(validityStart);
    }
    if (!nullToAbsent || validityEnd != null) {
      map['validity_end'] = Variable<DateTime>(validityEnd);
    }
    if (!nullToAbsent || dayofweekMask != null) {
      map['dayofweek_mask'] = Variable<int>(dayofweekMask);
    }
    if (!nullToAbsent || timeStart != null) {
      map['time_start'] = Variable<String>(timeStart);
    }
    if (!nullToAbsent || timeEnd != null) {
      map['time_end'] = Variable<String>(timeEnd);
    }
    if (!nullToAbsent || branchScopeJson != null) {
      map['branch_scope_json'] = Variable<String>(branchScopeJson);
    }
    if (!nullToAbsent || maxPerOrder != null) {
      map['max_per_order'] = Variable<int>(maxPerOrder);
    }
    if (!nullToAbsent || status != null) {
      map['status'] = Variable<String>(status);
    }
    return map;
  }

  OffersCompanion toCompanion(bool nullToAbsent) {
    return OffersCompanion(
      id: Value(id),
      name: Value(name),
      nameAr: nameAr == null && nullToAbsent
          ? const Value.absent()
          : Value(nameAr),
      type: Value(type),
      configJson: Value(configJson),
      autoApply: Value(autoApply),
      validityStart: validityStart == null && nullToAbsent
          ? const Value.absent()
          : Value(validityStart),
      validityEnd: validityEnd == null && nullToAbsent
          ? const Value.absent()
          : Value(validityEnd),
      dayofweekMask: dayofweekMask == null && nullToAbsent
          ? const Value.absent()
          : Value(dayofweekMask),
      timeStart: timeStart == null && nullToAbsent
          ? const Value.absent()
          : Value(timeStart),
      timeEnd: timeEnd == null && nullToAbsent
          ? const Value.absent()
          : Value(timeEnd),
      branchScopeJson: branchScopeJson == null && nullToAbsent
          ? const Value.absent()
          : Value(branchScopeJson),
      maxPerOrder: maxPerOrder == null && nullToAbsent
          ? const Value.absent()
          : Value(maxPerOrder),
      status: status == null && nullToAbsent
          ? const Value.absent()
          : Value(status),
    );
  }

  factory OfferRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OfferRow(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      nameAr: serializer.fromJson<String?>(json['nameAr']),
      type: serializer.fromJson<String>(json['type']),
      configJson: serializer.fromJson<String>(json['configJson']),
      autoApply: serializer.fromJson<bool>(json['autoApply']),
      validityStart: serializer.fromJson<DateTime?>(json['validityStart']),
      validityEnd: serializer.fromJson<DateTime?>(json['validityEnd']),
      dayofweekMask: serializer.fromJson<int?>(json['dayofweekMask']),
      timeStart: serializer.fromJson<String?>(json['timeStart']),
      timeEnd: serializer.fromJson<String?>(json['timeEnd']),
      branchScopeJson: serializer.fromJson<String?>(json['branchScopeJson']),
      maxPerOrder: serializer.fromJson<int?>(json['maxPerOrder']),
      status: serializer.fromJson<String?>(json['status']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'nameAr': serializer.toJson<String?>(nameAr),
      'type': serializer.toJson<String>(type),
      'configJson': serializer.toJson<String>(configJson),
      'autoApply': serializer.toJson<bool>(autoApply),
      'validityStart': serializer.toJson<DateTime?>(validityStart),
      'validityEnd': serializer.toJson<DateTime?>(validityEnd),
      'dayofweekMask': serializer.toJson<int?>(dayofweekMask),
      'timeStart': serializer.toJson<String?>(timeStart),
      'timeEnd': serializer.toJson<String?>(timeEnd),
      'branchScopeJson': serializer.toJson<String?>(branchScopeJson),
      'maxPerOrder': serializer.toJson<int?>(maxPerOrder),
      'status': serializer.toJson<String?>(status),
    };
  }

  OfferRow copyWith({
    int? id,
    String? name,
    Value<String?> nameAr = const Value.absent(),
    String? type,
    String? configJson,
    bool? autoApply,
    Value<DateTime?> validityStart = const Value.absent(),
    Value<DateTime?> validityEnd = const Value.absent(),
    Value<int?> dayofweekMask = const Value.absent(),
    Value<String?> timeStart = const Value.absent(),
    Value<String?> timeEnd = const Value.absent(),
    Value<String?> branchScopeJson = const Value.absent(),
    Value<int?> maxPerOrder = const Value.absent(),
    Value<String?> status = const Value.absent(),
  }) => OfferRow(
    id: id ?? this.id,
    name: name ?? this.name,
    nameAr: nameAr.present ? nameAr.value : this.nameAr,
    type: type ?? this.type,
    configJson: configJson ?? this.configJson,
    autoApply: autoApply ?? this.autoApply,
    validityStart: validityStart.present
        ? validityStart.value
        : this.validityStart,
    validityEnd: validityEnd.present ? validityEnd.value : this.validityEnd,
    dayofweekMask: dayofweekMask.present
        ? dayofweekMask.value
        : this.dayofweekMask,
    timeStart: timeStart.present ? timeStart.value : this.timeStart,
    timeEnd: timeEnd.present ? timeEnd.value : this.timeEnd,
    branchScopeJson: branchScopeJson.present
        ? branchScopeJson.value
        : this.branchScopeJson,
    maxPerOrder: maxPerOrder.present ? maxPerOrder.value : this.maxPerOrder,
    status: status.present ? status.value : this.status,
  );
  OfferRow copyWithCompanion(OffersCompanion data) {
    return OfferRow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      nameAr: data.nameAr.present ? data.nameAr.value : this.nameAr,
      type: data.type.present ? data.type.value : this.type,
      configJson: data.configJson.present
          ? data.configJson.value
          : this.configJson,
      autoApply: data.autoApply.present ? data.autoApply.value : this.autoApply,
      validityStart: data.validityStart.present
          ? data.validityStart.value
          : this.validityStart,
      validityEnd: data.validityEnd.present
          ? data.validityEnd.value
          : this.validityEnd,
      dayofweekMask: data.dayofweekMask.present
          ? data.dayofweekMask.value
          : this.dayofweekMask,
      timeStart: data.timeStart.present ? data.timeStart.value : this.timeStart,
      timeEnd: data.timeEnd.present ? data.timeEnd.value : this.timeEnd,
      branchScopeJson: data.branchScopeJson.present
          ? data.branchScopeJson.value
          : this.branchScopeJson,
      maxPerOrder: data.maxPerOrder.present
          ? data.maxPerOrder.value
          : this.maxPerOrder,
      status: data.status.present ? data.status.value : this.status,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OfferRow(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('nameAr: $nameAr, ')
          ..write('type: $type, ')
          ..write('configJson: $configJson, ')
          ..write('autoApply: $autoApply, ')
          ..write('validityStart: $validityStart, ')
          ..write('validityEnd: $validityEnd, ')
          ..write('dayofweekMask: $dayofweekMask, ')
          ..write('timeStart: $timeStart, ')
          ..write('timeEnd: $timeEnd, ')
          ..write('branchScopeJson: $branchScopeJson, ')
          ..write('maxPerOrder: $maxPerOrder, ')
          ..write('status: $status')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    nameAr,
    type,
    configJson,
    autoApply,
    validityStart,
    validityEnd,
    dayofweekMask,
    timeStart,
    timeEnd,
    branchScopeJson,
    maxPerOrder,
    status,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OfferRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.nameAr == this.nameAr &&
          other.type == this.type &&
          other.configJson == this.configJson &&
          other.autoApply == this.autoApply &&
          other.validityStart == this.validityStart &&
          other.validityEnd == this.validityEnd &&
          other.dayofweekMask == this.dayofweekMask &&
          other.timeStart == this.timeStart &&
          other.timeEnd == this.timeEnd &&
          other.branchScopeJson == this.branchScopeJson &&
          other.maxPerOrder == this.maxPerOrder &&
          other.status == this.status);
}

class OffersCompanion extends UpdateCompanion<OfferRow> {
  final Value<int> id;
  final Value<String> name;
  final Value<String?> nameAr;
  final Value<String> type;
  final Value<String> configJson;
  final Value<bool> autoApply;
  final Value<DateTime?> validityStart;
  final Value<DateTime?> validityEnd;
  final Value<int?> dayofweekMask;
  final Value<String?> timeStart;
  final Value<String?> timeEnd;
  final Value<String?> branchScopeJson;
  final Value<int?> maxPerOrder;
  final Value<String?> status;
  const OffersCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.nameAr = const Value.absent(),
    this.type = const Value.absent(),
    this.configJson = const Value.absent(),
    this.autoApply = const Value.absent(),
    this.validityStart = const Value.absent(),
    this.validityEnd = const Value.absent(),
    this.dayofweekMask = const Value.absent(),
    this.timeStart = const Value.absent(),
    this.timeEnd = const Value.absent(),
    this.branchScopeJson = const Value.absent(),
    this.maxPerOrder = const Value.absent(),
    this.status = const Value.absent(),
  });
  OffersCompanion.insert({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.nameAr = const Value.absent(),
    this.type = const Value.absent(),
    this.configJson = const Value.absent(),
    this.autoApply = const Value.absent(),
    this.validityStart = const Value.absent(),
    this.validityEnd = const Value.absent(),
    this.dayofweekMask = const Value.absent(),
    this.timeStart = const Value.absent(),
    this.timeEnd = const Value.absent(),
    this.branchScopeJson = const Value.absent(),
    this.maxPerOrder = const Value.absent(),
    this.status = const Value.absent(),
  });
  static Insertable<OfferRow> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<String>? nameAr,
    Expression<String>? type,
    Expression<String>? configJson,
    Expression<bool>? autoApply,
    Expression<DateTime>? validityStart,
    Expression<DateTime>? validityEnd,
    Expression<int>? dayofweekMask,
    Expression<String>? timeStart,
    Expression<String>? timeEnd,
    Expression<String>? branchScopeJson,
    Expression<int>? maxPerOrder,
    Expression<String>? status,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (nameAr != null) 'name_ar': nameAr,
      if (type != null) 'type': type,
      if (configJson != null) 'config_json': configJson,
      if (autoApply != null) 'auto_apply': autoApply,
      if (validityStart != null) 'validity_start': validityStart,
      if (validityEnd != null) 'validity_end': validityEnd,
      if (dayofweekMask != null) 'dayofweek_mask': dayofweekMask,
      if (timeStart != null) 'time_start': timeStart,
      if (timeEnd != null) 'time_end': timeEnd,
      if (branchScopeJson != null) 'branch_scope_json': branchScopeJson,
      if (maxPerOrder != null) 'max_per_order': maxPerOrder,
      if (status != null) 'status': status,
    });
  }

  OffersCompanion copyWith({
    Value<int>? id,
    Value<String>? name,
    Value<String?>? nameAr,
    Value<String>? type,
    Value<String>? configJson,
    Value<bool>? autoApply,
    Value<DateTime?>? validityStart,
    Value<DateTime?>? validityEnd,
    Value<int?>? dayofweekMask,
    Value<String?>? timeStart,
    Value<String?>? timeEnd,
    Value<String?>? branchScopeJson,
    Value<int?>? maxPerOrder,
    Value<String?>? status,
  }) {
    return OffersCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      nameAr: nameAr ?? this.nameAr,
      type: type ?? this.type,
      configJson: configJson ?? this.configJson,
      autoApply: autoApply ?? this.autoApply,
      validityStart: validityStart ?? this.validityStart,
      validityEnd: validityEnd ?? this.validityEnd,
      dayofweekMask: dayofweekMask ?? this.dayofweekMask,
      timeStart: timeStart ?? this.timeStart,
      timeEnd: timeEnd ?? this.timeEnd,
      branchScopeJson: branchScopeJson ?? this.branchScopeJson,
      maxPerOrder: maxPerOrder ?? this.maxPerOrder,
      status: status ?? this.status,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (nameAr.present) {
      map['name_ar'] = Variable<String>(nameAr.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (configJson.present) {
      map['config_json'] = Variable<String>(configJson.value);
    }
    if (autoApply.present) {
      map['auto_apply'] = Variable<bool>(autoApply.value);
    }
    if (validityStart.present) {
      map['validity_start'] = Variable<DateTime>(validityStart.value);
    }
    if (validityEnd.present) {
      map['validity_end'] = Variable<DateTime>(validityEnd.value);
    }
    if (dayofweekMask.present) {
      map['dayofweek_mask'] = Variable<int>(dayofweekMask.value);
    }
    if (timeStart.present) {
      map['time_start'] = Variable<String>(timeStart.value);
    }
    if (timeEnd.present) {
      map['time_end'] = Variable<String>(timeEnd.value);
    }
    if (branchScopeJson.present) {
      map['branch_scope_json'] = Variable<String>(branchScopeJson.value);
    }
    if (maxPerOrder.present) {
      map['max_per_order'] = Variable<int>(maxPerOrder.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OffersCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('nameAr: $nameAr, ')
          ..write('type: $type, ')
          ..write('configJson: $configJson, ')
          ..write('autoApply: $autoApply, ')
          ..write('validityStart: $validityStart, ')
          ..write('validityEnd: $validityEnd, ')
          ..write('dayofweekMask: $dayofweekMask, ')
          ..write('timeStart: $timeStart, ')
          ..write('timeEnd: $timeEnd, ')
          ..write('branchScopeJson: $branchScopeJson, ')
          ..write('maxPerOrder: $maxPerOrder, ')
          ..write('status: $status')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $BranchCacheTable branchCache = $BranchCacheTable(this);
  late final $CategoriesTable categories = $CategoriesTable(this);
  late final $ProductsTable products = $ProductsTable(this);
  late final $FloorsTable floors = $FloorsTable(this);
  late final $PosTablesTable posTables = $PosTablesTable(this);
  late final $AddonGroupsTable addonGroups = $AddonGroupsTable(this);
  late final $AddonsTable addons = $AddonsTable(this);
  late final $TaxCacheTable taxCache = $TaxCacheTable(this);
  late final $SyncMetaTable syncMeta = $SyncMetaTable(this);
  late final $OrderOutboxTable orderOutbox = $OrderOutboxTable(this);
  late final $DeliveryProvidersTable deliveryProviders =
      $DeliveryProvidersTable(this);
  late final $ExpenseCategoriesTable expenseCategories =
      $ExpenseCategoriesTable(this);
  late final $BranchIngredientStockTable branchIngredientStock =
      $BranchIngredientStockTable(this);
  late final $DiscountsTable discounts = $DiscountsTable(this);
  late final $LoyaltyRulesTable loyaltyRules = $LoyaltyRulesTable(this);
  late final $CachedCustomersTable cachedCustomers = $CachedCustomersTable(
    this,
  );
  late final $IngredientsTable ingredients = $IngredientsTable(this);
  late final $VoidReasonsTable voidReasons = $VoidReasonsTable(this);
  late final $CompReasonsTable compReasons = $CompReasonsTable(this);
  late final $OffersTable offers = $OffersTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    branchCache,
    categories,
    products,
    floors,
    posTables,
    addonGroups,
    addons,
    taxCache,
    syncMeta,
    orderOutbox,
    deliveryProviders,
    expenseCategories,
    branchIngredientStock,
    discounts,
    loyaltyRules,
    cachedCustomers,
    ingredients,
    voidReasons,
    compReasons,
    offers,
  ];
}

typedef $$BranchCacheTableCreateCompanionBuilder =
    BranchCacheCompanion Function({
      Value<int> id,
      Value<String> name,
      Value<String?> nameAr,
      Value<double?> latitude,
      Value<double?> longitude,
      Value<int?> geofenceRadiusM,
      Value<String?> defaultOrderType,
      Value<String?> status,
      Value<String?> receiptTemplateJson,
    });
typedef $$BranchCacheTableUpdateCompanionBuilder =
    BranchCacheCompanion Function({
      Value<int> id,
      Value<String> name,
      Value<String?> nameAr,
      Value<double?> latitude,
      Value<double?> longitude,
      Value<int?> geofenceRadiusM,
      Value<String?> defaultOrderType,
      Value<String?> status,
      Value<String?> receiptTemplateJson,
    });

class $$BranchCacheTableFilterComposer
    extends Composer<_$AppDatabase, $BranchCacheTable> {
  $$BranchCacheTableFilterComposer({
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

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get nameAr => $composableBuilder(
    column: $table.nameAr,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get latitude => $composableBuilder(
    column: $table.latitude,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get longitude => $composableBuilder(
    column: $table.longitude,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get geofenceRadiusM => $composableBuilder(
    column: $table.geofenceRadiusM,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get defaultOrderType => $composableBuilder(
    column: $table.defaultOrderType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get receiptTemplateJson => $composableBuilder(
    column: $table.receiptTemplateJson,
    builder: (column) => ColumnFilters(column),
  );
}

class $$BranchCacheTableOrderingComposer
    extends Composer<_$AppDatabase, $BranchCacheTable> {
  $$BranchCacheTableOrderingComposer({
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

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get nameAr => $composableBuilder(
    column: $table.nameAr,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get latitude => $composableBuilder(
    column: $table.latitude,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get longitude => $composableBuilder(
    column: $table.longitude,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get geofenceRadiusM => $composableBuilder(
    column: $table.geofenceRadiusM,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get defaultOrderType => $composableBuilder(
    column: $table.defaultOrderType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get receiptTemplateJson => $composableBuilder(
    column: $table.receiptTemplateJson,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$BranchCacheTableAnnotationComposer
    extends Composer<_$AppDatabase, $BranchCacheTable> {
  $$BranchCacheTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get nameAr =>
      $composableBuilder(column: $table.nameAr, builder: (column) => column);

  GeneratedColumn<double> get latitude =>
      $composableBuilder(column: $table.latitude, builder: (column) => column);

  GeneratedColumn<double> get longitude =>
      $composableBuilder(column: $table.longitude, builder: (column) => column);

  GeneratedColumn<int> get geofenceRadiusM => $composableBuilder(
    column: $table.geofenceRadiusM,
    builder: (column) => column,
  );

  GeneratedColumn<String> get defaultOrderType => $composableBuilder(
    column: $table.defaultOrderType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get receiptTemplateJson => $composableBuilder(
    column: $table.receiptTemplateJson,
    builder: (column) => column,
  );
}

class $$BranchCacheTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $BranchCacheTable,
          BranchRow,
          $$BranchCacheTableFilterComposer,
          $$BranchCacheTableOrderingComposer,
          $$BranchCacheTableAnnotationComposer,
          $$BranchCacheTableCreateCompanionBuilder,
          $$BranchCacheTableUpdateCompanionBuilder,
          (
            BranchRow,
            BaseReferences<_$AppDatabase, $BranchCacheTable, BranchRow>,
          ),
          BranchRow,
          PrefetchHooks Function()
        > {
  $$BranchCacheTableTableManager(_$AppDatabase db, $BranchCacheTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BranchCacheTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$BranchCacheTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$BranchCacheTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> nameAr = const Value.absent(),
                Value<double?> latitude = const Value.absent(),
                Value<double?> longitude = const Value.absent(),
                Value<int?> geofenceRadiusM = const Value.absent(),
                Value<String?> defaultOrderType = const Value.absent(),
                Value<String?> status = const Value.absent(),
                Value<String?> receiptTemplateJson = const Value.absent(),
              }) => BranchCacheCompanion(
                id: id,
                name: name,
                nameAr: nameAr,
                latitude: latitude,
                longitude: longitude,
                geofenceRadiusM: geofenceRadiusM,
                defaultOrderType: defaultOrderType,
                status: status,
                receiptTemplateJson: receiptTemplateJson,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> nameAr = const Value.absent(),
                Value<double?> latitude = const Value.absent(),
                Value<double?> longitude = const Value.absent(),
                Value<int?> geofenceRadiusM = const Value.absent(),
                Value<String?> defaultOrderType = const Value.absent(),
                Value<String?> status = const Value.absent(),
                Value<String?> receiptTemplateJson = const Value.absent(),
              }) => BranchCacheCompanion.insert(
                id: id,
                name: name,
                nameAr: nameAr,
                latitude: latitude,
                longitude: longitude,
                geofenceRadiusM: geofenceRadiusM,
                defaultOrderType: defaultOrderType,
                status: status,
                receiptTemplateJson: receiptTemplateJson,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$BranchCacheTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $BranchCacheTable,
      BranchRow,
      $$BranchCacheTableFilterComposer,
      $$BranchCacheTableOrderingComposer,
      $$BranchCacheTableAnnotationComposer,
      $$BranchCacheTableCreateCompanionBuilder,
      $$BranchCacheTableUpdateCompanionBuilder,
      (BranchRow, BaseReferences<_$AppDatabase, $BranchCacheTable, BranchRow>),
      BranchRow,
      PrefetchHooks Function()
    >;
typedef $$CategoriesTableCreateCompanionBuilder =
    CategoriesCompanion Function({
      Value<int> id,
      Value<String> name,
      Value<String?> nameAr,
      Value<int> displayOrder,
      Value<String?> status,
      Value<String> addonGroupIdsJson,
    });
typedef $$CategoriesTableUpdateCompanionBuilder =
    CategoriesCompanion Function({
      Value<int> id,
      Value<String> name,
      Value<String?> nameAr,
      Value<int> displayOrder,
      Value<String?> status,
      Value<String> addonGroupIdsJson,
    });

class $$CategoriesTableFilterComposer
    extends Composer<_$AppDatabase, $CategoriesTable> {
  $$CategoriesTableFilterComposer({
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

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get nameAr => $composableBuilder(
    column: $table.nameAr,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get displayOrder => $composableBuilder(
    column: $table.displayOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get addonGroupIdsJson => $composableBuilder(
    column: $table.addonGroupIdsJson,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CategoriesTableOrderingComposer
    extends Composer<_$AppDatabase, $CategoriesTable> {
  $$CategoriesTableOrderingComposer({
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

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get nameAr => $composableBuilder(
    column: $table.nameAr,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get displayOrder => $composableBuilder(
    column: $table.displayOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get addonGroupIdsJson => $composableBuilder(
    column: $table.addonGroupIdsJson,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CategoriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $CategoriesTable> {
  $$CategoriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get nameAr =>
      $composableBuilder(column: $table.nameAr, builder: (column) => column);

  GeneratedColumn<int> get displayOrder => $composableBuilder(
    column: $table.displayOrder,
    builder: (column) => column,
  );

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get addonGroupIdsJson => $composableBuilder(
    column: $table.addonGroupIdsJson,
    builder: (column) => column,
  );
}

class $$CategoriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CategoriesTable,
          CategoryRow,
          $$CategoriesTableFilterComposer,
          $$CategoriesTableOrderingComposer,
          $$CategoriesTableAnnotationComposer,
          $$CategoriesTableCreateCompanionBuilder,
          $$CategoriesTableUpdateCompanionBuilder,
          (
            CategoryRow,
            BaseReferences<_$AppDatabase, $CategoriesTable, CategoryRow>,
          ),
          CategoryRow,
          PrefetchHooks Function()
        > {
  $$CategoriesTableTableManager(_$AppDatabase db, $CategoriesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CategoriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CategoriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CategoriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> nameAr = const Value.absent(),
                Value<int> displayOrder = const Value.absent(),
                Value<String?> status = const Value.absent(),
                Value<String> addonGroupIdsJson = const Value.absent(),
              }) => CategoriesCompanion(
                id: id,
                name: name,
                nameAr: nameAr,
                displayOrder: displayOrder,
                status: status,
                addonGroupIdsJson: addonGroupIdsJson,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> nameAr = const Value.absent(),
                Value<int> displayOrder = const Value.absent(),
                Value<String?> status = const Value.absent(),
                Value<String> addonGroupIdsJson = const Value.absent(),
              }) => CategoriesCompanion.insert(
                id: id,
                name: name,
                nameAr: nameAr,
                displayOrder: displayOrder,
                status: status,
                addonGroupIdsJson: addonGroupIdsJson,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CategoriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CategoriesTable,
      CategoryRow,
      $$CategoriesTableFilterComposer,
      $$CategoriesTableOrderingComposer,
      $$CategoriesTableAnnotationComposer,
      $$CategoriesTableCreateCompanionBuilder,
      $$CategoriesTableUpdateCompanionBuilder,
      (
        CategoryRow,
        BaseReferences<_$AppDatabase, $CategoriesTable, CategoryRow>,
      ),
      CategoryRow,
      PrefetchHooks Function()
    >;
typedef $$ProductsTableCreateCompanionBuilder =
    ProductsCompanion Function({
      Value<int> id,
      Value<String> name,
      Value<String?> nameAr,
      Value<int?> categoryId,
      Value<int> basePriceBaisas,
      Value<double?> branchStockQty,
      Value<String?> imageUrl,
      Value<String?> status,
      Value<String> addonGroupIds,
      Value<int?> deliveryPriceBaisas,
      Value<String> deliveryPricesJson,
      Value<String?> stockMode,
      Value<String> recipeJson,
      Value<String?> availableFrom,
      Value<String?> availableUntil,
    });
typedef $$ProductsTableUpdateCompanionBuilder =
    ProductsCompanion Function({
      Value<int> id,
      Value<String> name,
      Value<String?> nameAr,
      Value<int?> categoryId,
      Value<int> basePriceBaisas,
      Value<double?> branchStockQty,
      Value<String?> imageUrl,
      Value<String?> status,
      Value<String> addonGroupIds,
      Value<int?> deliveryPriceBaisas,
      Value<String> deliveryPricesJson,
      Value<String?> stockMode,
      Value<String> recipeJson,
      Value<String?> availableFrom,
      Value<String?> availableUntil,
    });

class $$ProductsTableFilterComposer
    extends Composer<_$AppDatabase, $ProductsTable> {
  $$ProductsTableFilterComposer({
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

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get nameAr => $composableBuilder(
    column: $table.nameAr,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get categoryId => $composableBuilder(
    column: $table.categoryId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get basePriceBaisas => $composableBuilder(
    column: $table.basePriceBaisas,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get branchStockQty => $composableBuilder(
    column: $table.branchStockQty,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get imageUrl => $composableBuilder(
    column: $table.imageUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get addonGroupIds => $composableBuilder(
    column: $table.addonGroupIds,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get deliveryPriceBaisas => $composableBuilder(
    column: $table.deliveryPriceBaisas,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deliveryPricesJson => $composableBuilder(
    column: $table.deliveryPricesJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get stockMode => $composableBuilder(
    column: $table.stockMode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get recipeJson => $composableBuilder(
    column: $table.recipeJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get availableFrom => $composableBuilder(
    column: $table.availableFrom,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get availableUntil => $composableBuilder(
    column: $table.availableUntil,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ProductsTableOrderingComposer
    extends Composer<_$AppDatabase, $ProductsTable> {
  $$ProductsTableOrderingComposer({
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

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get nameAr => $composableBuilder(
    column: $table.nameAr,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get categoryId => $composableBuilder(
    column: $table.categoryId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get basePriceBaisas => $composableBuilder(
    column: $table.basePriceBaisas,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get branchStockQty => $composableBuilder(
    column: $table.branchStockQty,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get imageUrl => $composableBuilder(
    column: $table.imageUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get addonGroupIds => $composableBuilder(
    column: $table.addonGroupIds,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get deliveryPriceBaisas => $composableBuilder(
    column: $table.deliveryPriceBaisas,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deliveryPricesJson => $composableBuilder(
    column: $table.deliveryPricesJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get stockMode => $composableBuilder(
    column: $table.stockMode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get recipeJson => $composableBuilder(
    column: $table.recipeJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get availableFrom => $composableBuilder(
    column: $table.availableFrom,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get availableUntil => $composableBuilder(
    column: $table.availableUntil,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ProductsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ProductsTable> {
  $$ProductsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get nameAr =>
      $composableBuilder(column: $table.nameAr, builder: (column) => column);

  GeneratedColumn<int> get categoryId => $composableBuilder(
    column: $table.categoryId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get basePriceBaisas => $composableBuilder(
    column: $table.basePriceBaisas,
    builder: (column) => column,
  );

  GeneratedColumn<double> get branchStockQty => $composableBuilder(
    column: $table.branchStockQty,
    builder: (column) => column,
  );

  GeneratedColumn<String> get imageUrl =>
      $composableBuilder(column: $table.imageUrl, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get addonGroupIds => $composableBuilder(
    column: $table.addonGroupIds,
    builder: (column) => column,
  );

  GeneratedColumn<int> get deliveryPriceBaisas => $composableBuilder(
    column: $table.deliveryPriceBaisas,
    builder: (column) => column,
  );

  GeneratedColumn<String> get deliveryPricesJson => $composableBuilder(
    column: $table.deliveryPricesJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get stockMode =>
      $composableBuilder(column: $table.stockMode, builder: (column) => column);

  GeneratedColumn<String> get recipeJson => $composableBuilder(
    column: $table.recipeJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get availableFrom => $composableBuilder(
    column: $table.availableFrom,
    builder: (column) => column,
  );

  GeneratedColumn<String> get availableUntil => $composableBuilder(
    column: $table.availableUntil,
    builder: (column) => column,
  );
}

class $$ProductsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ProductsTable,
          ProductRow,
          $$ProductsTableFilterComposer,
          $$ProductsTableOrderingComposer,
          $$ProductsTableAnnotationComposer,
          $$ProductsTableCreateCompanionBuilder,
          $$ProductsTableUpdateCompanionBuilder,
          (
            ProductRow,
            BaseReferences<_$AppDatabase, $ProductsTable, ProductRow>,
          ),
          ProductRow,
          PrefetchHooks Function()
        > {
  $$ProductsTableTableManager(_$AppDatabase db, $ProductsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProductsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ProductsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ProductsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> nameAr = const Value.absent(),
                Value<int?> categoryId = const Value.absent(),
                Value<int> basePriceBaisas = const Value.absent(),
                Value<double?> branchStockQty = const Value.absent(),
                Value<String?> imageUrl = const Value.absent(),
                Value<String?> status = const Value.absent(),
                Value<String> addonGroupIds = const Value.absent(),
                Value<int?> deliveryPriceBaisas = const Value.absent(),
                Value<String> deliveryPricesJson = const Value.absent(),
                Value<String?> stockMode = const Value.absent(),
                Value<String> recipeJson = const Value.absent(),
                Value<String?> availableFrom = const Value.absent(),
                Value<String?> availableUntil = const Value.absent(),
              }) => ProductsCompanion(
                id: id,
                name: name,
                nameAr: nameAr,
                categoryId: categoryId,
                basePriceBaisas: basePriceBaisas,
                branchStockQty: branchStockQty,
                imageUrl: imageUrl,
                status: status,
                addonGroupIds: addonGroupIds,
                deliveryPriceBaisas: deliveryPriceBaisas,
                deliveryPricesJson: deliveryPricesJson,
                stockMode: stockMode,
                recipeJson: recipeJson,
                availableFrom: availableFrom,
                availableUntil: availableUntil,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> nameAr = const Value.absent(),
                Value<int?> categoryId = const Value.absent(),
                Value<int> basePriceBaisas = const Value.absent(),
                Value<double?> branchStockQty = const Value.absent(),
                Value<String?> imageUrl = const Value.absent(),
                Value<String?> status = const Value.absent(),
                Value<String> addonGroupIds = const Value.absent(),
                Value<int?> deliveryPriceBaisas = const Value.absent(),
                Value<String> deliveryPricesJson = const Value.absent(),
                Value<String?> stockMode = const Value.absent(),
                Value<String> recipeJson = const Value.absent(),
                Value<String?> availableFrom = const Value.absent(),
                Value<String?> availableUntil = const Value.absent(),
              }) => ProductsCompanion.insert(
                id: id,
                name: name,
                nameAr: nameAr,
                categoryId: categoryId,
                basePriceBaisas: basePriceBaisas,
                branchStockQty: branchStockQty,
                imageUrl: imageUrl,
                status: status,
                addonGroupIds: addonGroupIds,
                deliveryPriceBaisas: deliveryPriceBaisas,
                deliveryPricesJson: deliveryPricesJson,
                stockMode: stockMode,
                recipeJson: recipeJson,
                availableFrom: availableFrom,
                availableUntil: availableUntil,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ProductsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ProductsTable,
      ProductRow,
      $$ProductsTableFilterComposer,
      $$ProductsTableOrderingComposer,
      $$ProductsTableAnnotationComposer,
      $$ProductsTableCreateCompanionBuilder,
      $$ProductsTableUpdateCompanionBuilder,
      (ProductRow, BaseReferences<_$AppDatabase, $ProductsTable, ProductRow>),
      ProductRow,
      PrefetchHooks Function()
    >;
typedef $$FloorsTableCreateCompanionBuilder =
    FloorsCompanion Function({
      Value<int> id,
      Value<String> name,
      Value<String?> nameAr,
      Value<int> displayOrder,
      Value<String?> status,
    });
typedef $$FloorsTableUpdateCompanionBuilder =
    FloorsCompanion Function({
      Value<int> id,
      Value<String> name,
      Value<String?> nameAr,
      Value<int> displayOrder,
      Value<String?> status,
    });

class $$FloorsTableFilterComposer
    extends Composer<_$AppDatabase, $FloorsTable> {
  $$FloorsTableFilterComposer({
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

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get nameAr => $composableBuilder(
    column: $table.nameAr,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get displayOrder => $composableBuilder(
    column: $table.displayOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );
}

class $$FloorsTableOrderingComposer
    extends Composer<_$AppDatabase, $FloorsTable> {
  $$FloorsTableOrderingComposer({
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

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get nameAr => $composableBuilder(
    column: $table.nameAr,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get displayOrder => $composableBuilder(
    column: $table.displayOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$FloorsTableAnnotationComposer
    extends Composer<_$AppDatabase, $FloorsTable> {
  $$FloorsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get nameAr =>
      $composableBuilder(column: $table.nameAr, builder: (column) => column);

  GeneratedColumn<int> get displayOrder => $composableBuilder(
    column: $table.displayOrder,
    builder: (column) => column,
  );

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);
}

class $$FloorsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $FloorsTable,
          FloorRow,
          $$FloorsTableFilterComposer,
          $$FloorsTableOrderingComposer,
          $$FloorsTableAnnotationComposer,
          $$FloorsTableCreateCompanionBuilder,
          $$FloorsTableUpdateCompanionBuilder,
          (FloorRow, BaseReferences<_$AppDatabase, $FloorsTable, FloorRow>),
          FloorRow,
          PrefetchHooks Function()
        > {
  $$FloorsTableTableManager(_$AppDatabase db, $FloorsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FloorsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FloorsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FloorsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> nameAr = const Value.absent(),
                Value<int> displayOrder = const Value.absent(),
                Value<String?> status = const Value.absent(),
              }) => FloorsCompanion(
                id: id,
                name: name,
                nameAr: nameAr,
                displayOrder: displayOrder,
                status: status,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> nameAr = const Value.absent(),
                Value<int> displayOrder = const Value.absent(),
                Value<String?> status = const Value.absent(),
              }) => FloorsCompanion.insert(
                id: id,
                name: name,
                nameAr: nameAr,
                displayOrder: displayOrder,
                status: status,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$FloorsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $FloorsTable,
      FloorRow,
      $$FloorsTableFilterComposer,
      $$FloorsTableOrderingComposer,
      $$FloorsTableAnnotationComposer,
      $$FloorsTableCreateCompanionBuilder,
      $$FloorsTableUpdateCompanionBuilder,
      (FloorRow, BaseReferences<_$AppDatabase, $FloorsTable, FloorRow>),
      FloorRow,
      PrefetchHooks Function()
    >;
typedef $$PosTablesTableCreateCompanionBuilder =
    PosTablesCompanion Function({
      Value<int> id,
      required int floorId,
      Value<String> label,
      Value<int> seats,
      Value<int?> positionX,
      Value<int?> positionY,
      Value<int?> width,
      Value<int?> height,
      Value<String?> shape,
      Value<int> displayOrder,
      Value<String?> status,
    });
typedef $$PosTablesTableUpdateCompanionBuilder =
    PosTablesCompanion Function({
      Value<int> id,
      Value<int> floorId,
      Value<String> label,
      Value<int> seats,
      Value<int?> positionX,
      Value<int?> positionY,
      Value<int?> width,
      Value<int?> height,
      Value<String?> shape,
      Value<int> displayOrder,
      Value<String?> status,
    });

class $$PosTablesTableFilterComposer
    extends Composer<_$AppDatabase, $PosTablesTable> {
  $$PosTablesTableFilterComposer({
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

  ColumnFilters<int> get floorId => $composableBuilder(
    column: $table.floorId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get seats => $composableBuilder(
    column: $table.seats,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get positionX => $composableBuilder(
    column: $table.positionX,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get positionY => $composableBuilder(
    column: $table.positionY,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get width => $composableBuilder(
    column: $table.width,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get height => $composableBuilder(
    column: $table.height,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get shape => $composableBuilder(
    column: $table.shape,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get displayOrder => $composableBuilder(
    column: $table.displayOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PosTablesTableOrderingComposer
    extends Composer<_$AppDatabase, $PosTablesTable> {
  $$PosTablesTableOrderingComposer({
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

  ColumnOrderings<int> get floorId => $composableBuilder(
    column: $table.floorId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get seats => $composableBuilder(
    column: $table.seats,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get positionX => $composableBuilder(
    column: $table.positionX,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get positionY => $composableBuilder(
    column: $table.positionY,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get width => $composableBuilder(
    column: $table.width,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get height => $composableBuilder(
    column: $table.height,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get shape => $composableBuilder(
    column: $table.shape,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get displayOrder => $composableBuilder(
    column: $table.displayOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PosTablesTableAnnotationComposer
    extends Composer<_$AppDatabase, $PosTablesTable> {
  $$PosTablesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get floorId =>
      $composableBuilder(column: $table.floorId, builder: (column) => column);

  GeneratedColumn<String> get label =>
      $composableBuilder(column: $table.label, builder: (column) => column);

  GeneratedColumn<int> get seats =>
      $composableBuilder(column: $table.seats, builder: (column) => column);

  GeneratedColumn<int> get positionX =>
      $composableBuilder(column: $table.positionX, builder: (column) => column);

  GeneratedColumn<int> get positionY =>
      $composableBuilder(column: $table.positionY, builder: (column) => column);

  GeneratedColumn<int> get width =>
      $composableBuilder(column: $table.width, builder: (column) => column);

  GeneratedColumn<int> get height =>
      $composableBuilder(column: $table.height, builder: (column) => column);

  GeneratedColumn<String> get shape =>
      $composableBuilder(column: $table.shape, builder: (column) => column);

  GeneratedColumn<int> get displayOrder => $composableBuilder(
    column: $table.displayOrder,
    builder: (column) => column,
  );

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);
}

class $$PosTablesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PosTablesTable,
          TableRow,
          $$PosTablesTableFilterComposer,
          $$PosTablesTableOrderingComposer,
          $$PosTablesTableAnnotationComposer,
          $$PosTablesTableCreateCompanionBuilder,
          $$PosTablesTableUpdateCompanionBuilder,
          (TableRow, BaseReferences<_$AppDatabase, $PosTablesTable, TableRow>),
          TableRow,
          PrefetchHooks Function()
        > {
  $$PosTablesTableTableManager(_$AppDatabase db, $PosTablesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PosTablesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PosTablesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PosTablesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> floorId = const Value.absent(),
                Value<String> label = const Value.absent(),
                Value<int> seats = const Value.absent(),
                Value<int?> positionX = const Value.absent(),
                Value<int?> positionY = const Value.absent(),
                Value<int?> width = const Value.absent(),
                Value<int?> height = const Value.absent(),
                Value<String?> shape = const Value.absent(),
                Value<int> displayOrder = const Value.absent(),
                Value<String?> status = const Value.absent(),
              }) => PosTablesCompanion(
                id: id,
                floorId: floorId,
                label: label,
                seats: seats,
                positionX: positionX,
                positionY: positionY,
                width: width,
                height: height,
                shape: shape,
                displayOrder: displayOrder,
                status: status,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int floorId,
                Value<String> label = const Value.absent(),
                Value<int> seats = const Value.absent(),
                Value<int?> positionX = const Value.absent(),
                Value<int?> positionY = const Value.absent(),
                Value<int?> width = const Value.absent(),
                Value<int?> height = const Value.absent(),
                Value<String?> shape = const Value.absent(),
                Value<int> displayOrder = const Value.absent(),
                Value<String?> status = const Value.absent(),
              }) => PosTablesCompanion.insert(
                id: id,
                floorId: floorId,
                label: label,
                seats: seats,
                positionX: positionX,
                positionY: positionY,
                width: width,
                height: height,
                shape: shape,
                displayOrder: displayOrder,
                status: status,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PosTablesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PosTablesTable,
      TableRow,
      $$PosTablesTableFilterComposer,
      $$PosTablesTableOrderingComposer,
      $$PosTablesTableAnnotationComposer,
      $$PosTablesTableCreateCompanionBuilder,
      $$PosTablesTableUpdateCompanionBuilder,
      (TableRow, BaseReferences<_$AppDatabase, $PosTablesTable, TableRow>),
      TableRow,
      PrefetchHooks Function()
    >;
typedef $$AddonGroupsTableCreateCompanionBuilder =
    AddonGroupsCompanion Function({
      Value<int> id,
      Value<String> name,
      Value<String?> nameAr,
      Value<String?> selectionMode,
      Value<int?> minSelections,
      Value<int?> maxSelections,
      Value<String?> status,
    });
typedef $$AddonGroupsTableUpdateCompanionBuilder =
    AddonGroupsCompanion Function({
      Value<int> id,
      Value<String> name,
      Value<String?> nameAr,
      Value<String?> selectionMode,
      Value<int?> minSelections,
      Value<int?> maxSelections,
      Value<String?> status,
    });

class $$AddonGroupsTableFilterComposer
    extends Composer<_$AppDatabase, $AddonGroupsTable> {
  $$AddonGroupsTableFilterComposer({
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

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get nameAr => $composableBuilder(
    column: $table.nameAr,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get selectionMode => $composableBuilder(
    column: $table.selectionMode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get minSelections => $composableBuilder(
    column: $table.minSelections,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get maxSelections => $composableBuilder(
    column: $table.maxSelections,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AddonGroupsTableOrderingComposer
    extends Composer<_$AppDatabase, $AddonGroupsTable> {
  $$AddonGroupsTableOrderingComposer({
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

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get nameAr => $composableBuilder(
    column: $table.nameAr,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get selectionMode => $composableBuilder(
    column: $table.selectionMode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get minSelections => $composableBuilder(
    column: $table.minSelections,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get maxSelections => $composableBuilder(
    column: $table.maxSelections,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AddonGroupsTableAnnotationComposer
    extends Composer<_$AppDatabase, $AddonGroupsTable> {
  $$AddonGroupsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get nameAr =>
      $composableBuilder(column: $table.nameAr, builder: (column) => column);

  GeneratedColumn<String> get selectionMode => $composableBuilder(
    column: $table.selectionMode,
    builder: (column) => column,
  );

  GeneratedColumn<int> get minSelections => $composableBuilder(
    column: $table.minSelections,
    builder: (column) => column,
  );

  GeneratedColumn<int> get maxSelections => $composableBuilder(
    column: $table.maxSelections,
    builder: (column) => column,
  );

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);
}

class $$AddonGroupsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AddonGroupsTable,
          AddonGroupRow,
          $$AddonGroupsTableFilterComposer,
          $$AddonGroupsTableOrderingComposer,
          $$AddonGroupsTableAnnotationComposer,
          $$AddonGroupsTableCreateCompanionBuilder,
          $$AddonGroupsTableUpdateCompanionBuilder,
          (
            AddonGroupRow,
            BaseReferences<_$AppDatabase, $AddonGroupsTable, AddonGroupRow>,
          ),
          AddonGroupRow,
          PrefetchHooks Function()
        > {
  $$AddonGroupsTableTableManager(_$AppDatabase db, $AddonGroupsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AddonGroupsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AddonGroupsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AddonGroupsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> nameAr = const Value.absent(),
                Value<String?> selectionMode = const Value.absent(),
                Value<int?> minSelections = const Value.absent(),
                Value<int?> maxSelections = const Value.absent(),
                Value<String?> status = const Value.absent(),
              }) => AddonGroupsCompanion(
                id: id,
                name: name,
                nameAr: nameAr,
                selectionMode: selectionMode,
                minSelections: minSelections,
                maxSelections: maxSelections,
                status: status,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> nameAr = const Value.absent(),
                Value<String?> selectionMode = const Value.absent(),
                Value<int?> minSelections = const Value.absent(),
                Value<int?> maxSelections = const Value.absent(),
                Value<String?> status = const Value.absent(),
              }) => AddonGroupsCompanion.insert(
                id: id,
                name: name,
                nameAr: nameAr,
                selectionMode: selectionMode,
                minSelections: minSelections,
                maxSelections: maxSelections,
                status: status,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AddonGroupsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AddonGroupsTable,
      AddonGroupRow,
      $$AddonGroupsTableFilterComposer,
      $$AddonGroupsTableOrderingComposer,
      $$AddonGroupsTableAnnotationComposer,
      $$AddonGroupsTableCreateCompanionBuilder,
      $$AddonGroupsTableUpdateCompanionBuilder,
      (
        AddonGroupRow,
        BaseReferences<_$AppDatabase, $AddonGroupsTable, AddonGroupRow>,
      ),
      AddonGroupRow,
      PrefetchHooks Function()
    >;
typedef $$AddonsTableCreateCompanionBuilder =
    AddonsCompanion Function({
      Value<int> id,
      required int addOnGroupId,
      Value<String> name,
      Value<String?> nameAr,
      Value<int> priceDeltaBaisas,
      Value<bool> isDefault,
      Value<int?> ingredientId,
      Value<int?> linkedProductId,
      Value<String?> status,
    });
typedef $$AddonsTableUpdateCompanionBuilder =
    AddonsCompanion Function({
      Value<int> id,
      Value<int> addOnGroupId,
      Value<String> name,
      Value<String?> nameAr,
      Value<int> priceDeltaBaisas,
      Value<bool> isDefault,
      Value<int?> ingredientId,
      Value<int?> linkedProductId,
      Value<String?> status,
    });

class $$AddonsTableFilterComposer
    extends Composer<_$AppDatabase, $AddonsTable> {
  $$AddonsTableFilterComposer({
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

  ColumnFilters<int> get addOnGroupId => $composableBuilder(
    column: $table.addOnGroupId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get nameAr => $composableBuilder(
    column: $table.nameAr,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get priceDeltaBaisas => $composableBuilder(
    column: $table.priceDeltaBaisas,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isDefault => $composableBuilder(
    column: $table.isDefault,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get ingredientId => $composableBuilder(
    column: $table.ingredientId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get linkedProductId => $composableBuilder(
    column: $table.linkedProductId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AddonsTableOrderingComposer
    extends Composer<_$AppDatabase, $AddonsTable> {
  $$AddonsTableOrderingComposer({
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

  ColumnOrderings<int> get addOnGroupId => $composableBuilder(
    column: $table.addOnGroupId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get nameAr => $composableBuilder(
    column: $table.nameAr,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get priceDeltaBaisas => $composableBuilder(
    column: $table.priceDeltaBaisas,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isDefault => $composableBuilder(
    column: $table.isDefault,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get ingredientId => $composableBuilder(
    column: $table.ingredientId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get linkedProductId => $composableBuilder(
    column: $table.linkedProductId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AddonsTableAnnotationComposer
    extends Composer<_$AppDatabase, $AddonsTable> {
  $$AddonsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get addOnGroupId => $composableBuilder(
    column: $table.addOnGroupId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get nameAr =>
      $composableBuilder(column: $table.nameAr, builder: (column) => column);

  GeneratedColumn<int> get priceDeltaBaisas => $composableBuilder(
    column: $table.priceDeltaBaisas,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isDefault =>
      $composableBuilder(column: $table.isDefault, builder: (column) => column);

  GeneratedColumn<int> get ingredientId => $composableBuilder(
    column: $table.ingredientId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get linkedProductId => $composableBuilder(
    column: $table.linkedProductId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);
}

class $$AddonsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AddonsTable,
          AddonRow,
          $$AddonsTableFilterComposer,
          $$AddonsTableOrderingComposer,
          $$AddonsTableAnnotationComposer,
          $$AddonsTableCreateCompanionBuilder,
          $$AddonsTableUpdateCompanionBuilder,
          (AddonRow, BaseReferences<_$AppDatabase, $AddonsTable, AddonRow>),
          AddonRow,
          PrefetchHooks Function()
        > {
  $$AddonsTableTableManager(_$AppDatabase db, $AddonsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AddonsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AddonsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AddonsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> addOnGroupId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> nameAr = const Value.absent(),
                Value<int> priceDeltaBaisas = const Value.absent(),
                Value<bool> isDefault = const Value.absent(),
                Value<int?> ingredientId = const Value.absent(),
                Value<int?> linkedProductId = const Value.absent(),
                Value<String?> status = const Value.absent(),
              }) => AddonsCompanion(
                id: id,
                addOnGroupId: addOnGroupId,
                name: name,
                nameAr: nameAr,
                priceDeltaBaisas: priceDeltaBaisas,
                isDefault: isDefault,
                ingredientId: ingredientId,
                linkedProductId: linkedProductId,
                status: status,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int addOnGroupId,
                Value<String> name = const Value.absent(),
                Value<String?> nameAr = const Value.absent(),
                Value<int> priceDeltaBaisas = const Value.absent(),
                Value<bool> isDefault = const Value.absent(),
                Value<int?> ingredientId = const Value.absent(),
                Value<int?> linkedProductId = const Value.absent(),
                Value<String?> status = const Value.absent(),
              }) => AddonsCompanion.insert(
                id: id,
                addOnGroupId: addOnGroupId,
                name: name,
                nameAr: nameAr,
                priceDeltaBaisas: priceDeltaBaisas,
                isDefault: isDefault,
                ingredientId: ingredientId,
                linkedProductId: linkedProductId,
                status: status,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AddonsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AddonsTable,
      AddonRow,
      $$AddonsTableFilterComposer,
      $$AddonsTableOrderingComposer,
      $$AddonsTableAnnotationComposer,
      $$AddonsTableCreateCompanionBuilder,
      $$AddonsTableUpdateCompanionBuilder,
      (AddonRow, BaseReferences<_$AppDatabase, $AddonsTable, AddonRow>),
      AddonRow,
      PrefetchHooks Function()
    >;
typedef $$TaxCacheTableCreateCompanionBuilder =
    TaxCacheCompanion Function({
      Value<int> id,
      Value<String> name,
      Value<String?> nameAr,
      Value<double> ratePercent,
    });
typedef $$TaxCacheTableUpdateCompanionBuilder =
    TaxCacheCompanion Function({
      Value<int> id,
      Value<String> name,
      Value<String?> nameAr,
      Value<double> ratePercent,
    });

class $$TaxCacheTableFilterComposer
    extends Composer<_$AppDatabase, $TaxCacheTable> {
  $$TaxCacheTableFilterComposer({
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

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get nameAr => $composableBuilder(
    column: $table.nameAr,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get ratePercent => $composableBuilder(
    column: $table.ratePercent,
    builder: (column) => ColumnFilters(column),
  );
}

class $$TaxCacheTableOrderingComposer
    extends Composer<_$AppDatabase, $TaxCacheTable> {
  $$TaxCacheTableOrderingComposer({
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

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get nameAr => $composableBuilder(
    column: $table.nameAr,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get ratePercent => $composableBuilder(
    column: $table.ratePercent,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TaxCacheTableAnnotationComposer
    extends Composer<_$AppDatabase, $TaxCacheTable> {
  $$TaxCacheTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get nameAr =>
      $composableBuilder(column: $table.nameAr, builder: (column) => column);

  GeneratedColumn<double> get ratePercent => $composableBuilder(
    column: $table.ratePercent,
    builder: (column) => column,
  );
}

class $$TaxCacheTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TaxCacheTable,
          TaxRow,
          $$TaxCacheTableFilterComposer,
          $$TaxCacheTableOrderingComposer,
          $$TaxCacheTableAnnotationComposer,
          $$TaxCacheTableCreateCompanionBuilder,
          $$TaxCacheTableUpdateCompanionBuilder,
          (TaxRow, BaseReferences<_$AppDatabase, $TaxCacheTable, TaxRow>),
          TaxRow,
          PrefetchHooks Function()
        > {
  $$TaxCacheTableTableManager(_$AppDatabase db, $TaxCacheTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TaxCacheTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TaxCacheTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TaxCacheTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> nameAr = const Value.absent(),
                Value<double> ratePercent = const Value.absent(),
              }) => TaxCacheCompanion(
                id: id,
                name: name,
                nameAr: nameAr,
                ratePercent: ratePercent,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> nameAr = const Value.absent(),
                Value<double> ratePercent = const Value.absent(),
              }) => TaxCacheCompanion.insert(
                id: id,
                name: name,
                nameAr: nameAr,
                ratePercent: ratePercent,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$TaxCacheTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TaxCacheTable,
      TaxRow,
      $$TaxCacheTableFilterComposer,
      $$TaxCacheTableOrderingComposer,
      $$TaxCacheTableAnnotationComposer,
      $$TaxCacheTableCreateCompanionBuilder,
      $$TaxCacheTableUpdateCompanionBuilder,
      (TaxRow, BaseReferences<_$AppDatabase, $TaxCacheTable, TaxRow>),
      TaxRow,
      PrefetchHooks Function()
    >;
typedef $$SyncMetaTableCreateCompanionBuilder =
    SyncMetaCompanion Function({
      Value<int> id,
      Value<int?> companyId,
      Value<int?> branchId,
      Value<DateTime?> lastConfigSyncAt,
      Value<String?> configSchemaVersion,
      Value<String?> orderCancelPositions,
      Value<String?> reportsPositions,
      Value<String?> kitchenPositions,
      Value<String?> orderNumberingJson,
    });
typedef $$SyncMetaTableUpdateCompanionBuilder =
    SyncMetaCompanion Function({
      Value<int> id,
      Value<int?> companyId,
      Value<int?> branchId,
      Value<DateTime?> lastConfigSyncAt,
      Value<String?> configSchemaVersion,
      Value<String?> orderCancelPositions,
      Value<String?> reportsPositions,
      Value<String?> kitchenPositions,
      Value<String?> orderNumberingJson,
    });

class $$SyncMetaTableFilterComposer
    extends Composer<_$AppDatabase, $SyncMetaTable> {
  $$SyncMetaTableFilterComposer({
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

  ColumnFilters<int> get companyId => $composableBuilder(
    column: $table.companyId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get branchId => $composableBuilder(
    column: $table.branchId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastConfigSyncAt => $composableBuilder(
    column: $table.lastConfigSyncAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get configSchemaVersion => $composableBuilder(
    column: $table.configSchemaVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get orderCancelPositions => $composableBuilder(
    column: $table.orderCancelPositions,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get reportsPositions => $composableBuilder(
    column: $table.reportsPositions,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kitchenPositions => $composableBuilder(
    column: $table.kitchenPositions,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get orderNumberingJson => $composableBuilder(
    column: $table.orderNumberingJson,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncMetaTableOrderingComposer
    extends Composer<_$AppDatabase, $SyncMetaTable> {
  $$SyncMetaTableOrderingComposer({
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

  ColumnOrderings<int> get companyId => $composableBuilder(
    column: $table.companyId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get branchId => $composableBuilder(
    column: $table.branchId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastConfigSyncAt => $composableBuilder(
    column: $table.lastConfigSyncAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get configSchemaVersion => $composableBuilder(
    column: $table.configSchemaVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get orderCancelPositions => $composableBuilder(
    column: $table.orderCancelPositions,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get reportsPositions => $composableBuilder(
    column: $table.reportsPositions,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kitchenPositions => $composableBuilder(
    column: $table.kitchenPositions,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get orderNumberingJson => $composableBuilder(
    column: $table.orderNumberingJson,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncMetaTableAnnotationComposer
    extends Composer<_$AppDatabase, $SyncMetaTable> {
  $$SyncMetaTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get companyId =>
      $composableBuilder(column: $table.companyId, builder: (column) => column);

  GeneratedColumn<int> get branchId =>
      $composableBuilder(column: $table.branchId, builder: (column) => column);

  GeneratedColumn<DateTime> get lastConfigSyncAt => $composableBuilder(
    column: $table.lastConfigSyncAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get configSchemaVersion => $composableBuilder(
    column: $table.configSchemaVersion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get orderCancelPositions => $composableBuilder(
    column: $table.orderCancelPositions,
    builder: (column) => column,
  );

  GeneratedColumn<String> get reportsPositions => $composableBuilder(
    column: $table.reportsPositions,
    builder: (column) => column,
  );

  GeneratedColumn<String> get kitchenPositions => $composableBuilder(
    column: $table.kitchenPositions,
    builder: (column) => column,
  );

  GeneratedColumn<String> get orderNumberingJson => $composableBuilder(
    column: $table.orderNumberingJson,
    builder: (column) => column,
  );
}

class $$SyncMetaTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SyncMetaTable,
          SyncMetaRow,
          $$SyncMetaTableFilterComposer,
          $$SyncMetaTableOrderingComposer,
          $$SyncMetaTableAnnotationComposer,
          $$SyncMetaTableCreateCompanionBuilder,
          $$SyncMetaTableUpdateCompanionBuilder,
          (
            SyncMetaRow,
            BaseReferences<_$AppDatabase, $SyncMetaTable, SyncMetaRow>,
          ),
          SyncMetaRow,
          PrefetchHooks Function()
        > {
  $$SyncMetaTableTableManager(_$AppDatabase db, $SyncMetaTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncMetaTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncMetaTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncMetaTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int?> companyId = const Value.absent(),
                Value<int?> branchId = const Value.absent(),
                Value<DateTime?> lastConfigSyncAt = const Value.absent(),
                Value<String?> configSchemaVersion = const Value.absent(),
                Value<String?> orderCancelPositions = const Value.absent(),
                Value<String?> reportsPositions = const Value.absent(),
                Value<String?> kitchenPositions = const Value.absent(),
                Value<String?> orderNumberingJson = const Value.absent(),
              }) => SyncMetaCompanion(
                id: id,
                companyId: companyId,
                branchId: branchId,
                lastConfigSyncAt: lastConfigSyncAt,
                configSchemaVersion: configSchemaVersion,
                orderCancelPositions: orderCancelPositions,
                reportsPositions: reportsPositions,
                kitchenPositions: kitchenPositions,
                orderNumberingJson: orderNumberingJson,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int?> companyId = const Value.absent(),
                Value<int?> branchId = const Value.absent(),
                Value<DateTime?> lastConfigSyncAt = const Value.absent(),
                Value<String?> configSchemaVersion = const Value.absent(),
                Value<String?> orderCancelPositions = const Value.absent(),
                Value<String?> reportsPositions = const Value.absent(),
                Value<String?> kitchenPositions = const Value.absent(),
                Value<String?> orderNumberingJson = const Value.absent(),
              }) => SyncMetaCompanion.insert(
                id: id,
                companyId: companyId,
                branchId: branchId,
                lastConfigSyncAt: lastConfigSyncAt,
                configSchemaVersion: configSchemaVersion,
                orderCancelPositions: orderCancelPositions,
                reportsPositions: reportsPositions,
                kitchenPositions: kitchenPositions,
                orderNumberingJson: orderNumberingJson,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncMetaTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SyncMetaTable,
      SyncMetaRow,
      $$SyncMetaTableFilterComposer,
      $$SyncMetaTableOrderingComposer,
      $$SyncMetaTableAnnotationComposer,
      $$SyncMetaTableCreateCompanionBuilder,
      $$SyncMetaTableUpdateCompanionBuilder,
      (SyncMetaRow, BaseReferences<_$AppDatabase, $SyncMetaTable, SyncMetaRow>),
      SyncMetaRow,
      PrefetchHooks Function()
    >;
typedef $$OrderOutboxTableCreateCompanionBuilder =
    OrderOutboxCompanion Function({
      required String orderUuid,
      required String eventsJson,
      Value<int?> orderNumber,
      required DateTime createdAt,
      Value<int> attempts,
      Value<String?> lastError,
      Value<DateTime?> syncedAt,
      Value<int> rowid,
    });
typedef $$OrderOutboxTableUpdateCompanionBuilder =
    OrderOutboxCompanion Function({
      Value<String> orderUuid,
      Value<String> eventsJson,
      Value<int?> orderNumber,
      Value<DateTime> createdAt,
      Value<int> attempts,
      Value<String?> lastError,
      Value<DateTime?> syncedAt,
      Value<int> rowid,
    });

class $$OrderOutboxTableFilterComposer
    extends Composer<_$AppDatabase, $OrderOutboxTable> {
  $$OrderOutboxTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get orderUuid => $composableBuilder(
    column: $table.orderUuid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get eventsJson => $composableBuilder(
    column: $table.eventsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get orderNumber => $composableBuilder(
    column: $table.orderNumber,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
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

  ColumnFilters<DateTime> get syncedAt => $composableBuilder(
    column: $table.syncedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$OrderOutboxTableOrderingComposer
    extends Composer<_$AppDatabase, $OrderOutboxTable> {
  $$OrderOutboxTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get orderUuid => $composableBuilder(
    column: $table.orderUuid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get eventsJson => $composableBuilder(
    column: $table.eventsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get orderNumber => $composableBuilder(
    column: $table.orderNumber,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
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

  ColumnOrderings<DateTime> get syncedAt => $composableBuilder(
    column: $table.syncedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$OrderOutboxTableAnnotationComposer
    extends Composer<_$AppDatabase, $OrderOutboxTable> {
  $$OrderOutboxTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get orderUuid =>
      $composableBuilder(column: $table.orderUuid, builder: (column) => column);

  GeneratedColumn<String> get eventsJson => $composableBuilder(
    column: $table.eventsJson,
    builder: (column) => column,
  );

  GeneratedColumn<int> get orderNumber => $composableBuilder(
    column: $table.orderNumber,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get attempts =>
      $composableBuilder(column: $table.attempts, builder: (column) => column);

  GeneratedColumn<String> get lastError =>
      $composableBuilder(column: $table.lastError, builder: (column) => column);

  GeneratedColumn<DateTime> get syncedAt =>
      $composableBuilder(column: $table.syncedAt, builder: (column) => column);
}

class $$OrderOutboxTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $OrderOutboxTable,
          OrderOutboxRow,
          $$OrderOutboxTableFilterComposer,
          $$OrderOutboxTableOrderingComposer,
          $$OrderOutboxTableAnnotationComposer,
          $$OrderOutboxTableCreateCompanionBuilder,
          $$OrderOutboxTableUpdateCompanionBuilder,
          (
            OrderOutboxRow,
            BaseReferences<_$AppDatabase, $OrderOutboxTable, OrderOutboxRow>,
          ),
          OrderOutboxRow,
          PrefetchHooks Function()
        > {
  $$OrderOutboxTableTableManager(_$AppDatabase db, $OrderOutboxTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OrderOutboxTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$OrderOutboxTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$OrderOutboxTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> orderUuid = const Value.absent(),
                Value<String> eventsJson = const Value.absent(),
                Value<int?> orderNumber = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> attempts = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<DateTime?> syncedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => OrderOutboxCompanion(
                orderUuid: orderUuid,
                eventsJson: eventsJson,
                orderNumber: orderNumber,
                createdAt: createdAt,
                attempts: attempts,
                lastError: lastError,
                syncedAt: syncedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String orderUuid,
                required String eventsJson,
                Value<int?> orderNumber = const Value.absent(),
                required DateTime createdAt,
                Value<int> attempts = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<DateTime?> syncedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => OrderOutboxCompanion.insert(
                orderUuid: orderUuid,
                eventsJson: eventsJson,
                orderNumber: orderNumber,
                createdAt: createdAt,
                attempts: attempts,
                lastError: lastError,
                syncedAt: syncedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$OrderOutboxTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $OrderOutboxTable,
      OrderOutboxRow,
      $$OrderOutboxTableFilterComposer,
      $$OrderOutboxTableOrderingComposer,
      $$OrderOutboxTableAnnotationComposer,
      $$OrderOutboxTableCreateCompanionBuilder,
      $$OrderOutboxTableUpdateCompanionBuilder,
      (
        OrderOutboxRow,
        BaseReferences<_$AppDatabase, $OrderOutboxTable, OrderOutboxRow>,
      ),
      OrderOutboxRow,
      PrefetchHooks Function()
    >;
typedef $$DeliveryProvidersTableCreateCompanionBuilder =
    DeliveryProvidersCompanion Function({
      Value<int> id,
      Value<String> name,
      Value<String?> color,
      Value<int> sortOrder,
    });
typedef $$DeliveryProvidersTableUpdateCompanionBuilder =
    DeliveryProvidersCompanion Function({
      Value<int> id,
      Value<String> name,
      Value<String?> color,
      Value<int> sortOrder,
    });

class $$DeliveryProvidersTableFilterComposer
    extends Composer<_$AppDatabase, $DeliveryProvidersTable> {
  $$DeliveryProvidersTableFilterComposer({
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

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DeliveryProvidersTableOrderingComposer
    extends Composer<_$AppDatabase, $DeliveryProvidersTable> {
  $$DeliveryProvidersTableOrderingComposer({
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

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DeliveryProvidersTableAnnotationComposer
    extends Composer<_$AppDatabase, $DeliveryProvidersTable> {
  $$DeliveryProvidersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get color =>
      $composableBuilder(column: $table.color, builder: (column) => column);

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);
}

class $$DeliveryProvidersTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $DeliveryProvidersTable,
          DeliveryProviderRow,
          $$DeliveryProvidersTableFilterComposer,
          $$DeliveryProvidersTableOrderingComposer,
          $$DeliveryProvidersTableAnnotationComposer,
          $$DeliveryProvidersTableCreateCompanionBuilder,
          $$DeliveryProvidersTableUpdateCompanionBuilder,
          (
            DeliveryProviderRow,
            BaseReferences<
              _$AppDatabase,
              $DeliveryProvidersTable,
              DeliveryProviderRow
            >,
          ),
          DeliveryProviderRow,
          PrefetchHooks Function()
        > {
  $$DeliveryProvidersTableTableManager(
    _$AppDatabase db,
    $DeliveryProvidersTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DeliveryProvidersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DeliveryProvidersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DeliveryProvidersTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> color = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
              }) => DeliveryProvidersCompanion(
                id: id,
                name: name,
                color: color,
                sortOrder: sortOrder,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> color = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
              }) => DeliveryProvidersCompanion.insert(
                id: id,
                name: name,
                color: color,
                sortOrder: sortOrder,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DeliveryProvidersTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $DeliveryProvidersTable,
      DeliveryProviderRow,
      $$DeliveryProvidersTableFilterComposer,
      $$DeliveryProvidersTableOrderingComposer,
      $$DeliveryProvidersTableAnnotationComposer,
      $$DeliveryProvidersTableCreateCompanionBuilder,
      $$DeliveryProvidersTableUpdateCompanionBuilder,
      (
        DeliveryProviderRow,
        BaseReferences<
          _$AppDatabase,
          $DeliveryProvidersTable,
          DeliveryProviderRow
        >,
      ),
      DeliveryProviderRow,
      PrefetchHooks Function()
    >;
typedef $$ExpenseCategoriesTableCreateCompanionBuilder =
    ExpenseCategoriesCompanion Function({
      Value<int> id,
      Value<String> key,
      Value<String> name,
      Value<String?> nameAr,
      Value<int> sortOrder,
    });
typedef $$ExpenseCategoriesTableUpdateCompanionBuilder =
    ExpenseCategoriesCompanion Function({
      Value<int> id,
      Value<String> key,
      Value<String> name,
      Value<String?> nameAr,
      Value<int> sortOrder,
    });

class $$ExpenseCategoriesTableFilterComposer
    extends Composer<_$AppDatabase, $ExpenseCategoriesTable> {
  $$ExpenseCategoriesTableFilterComposer({
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

  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get nameAr => $composableBuilder(
    column: $table.nameAr,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ExpenseCategoriesTableOrderingComposer
    extends Composer<_$AppDatabase, $ExpenseCategoriesTable> {
  $$ExpenseCategoriesTableOrderingComposer({
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

  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get nameAr => $composableBuilder(
    column: $table.nameAr,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ExpenseCategoriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $ExpenseCategoriesTable> {
  $$ExpenseCategoriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get nameAr =>
      $composableBuilder(column: $table.nameAr, builder: (column) => column);

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);
}

class $$ExpenseCategoriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ExpenseCategoriesTable,
          ExpenseCategoryRow,
          $$ExpenseCategoriesTableFilterComposer,
          $$ExpenseCategoriesTableOrderingComposer,
          $$ExpenseCategoriesTableAnnotationComposer,
          $$ExpenseCategoriesTableCreateCompanionBuilder,
          $$ExpenseCategoriesTableUpdateCompanionBuilder,
          (
            ExpenseCategoryRow,
            BaseReferences<
              _$AppDatabase,
              $ExpenseCategoriesTable,
              ExpenseCategoryRow
            >,
          ),
          ExpenseCategoryRow,
          PrefetchHooks Function()
        > {
  $$ExpenseCategoriesTableTableManager(
    _$AppDatabase db,
    $ExpenseCategoriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ExpenseCategoriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ExpenseCategoriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ExpenseCategoriesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> key = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> nameAr = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
              }) => ExpenseCategoriesCompanion(
                id: id,
                key: key,
                name: name,
                nameAr: nameAr,
                sortOrder: sortOrder,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> key = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> nameAr = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
              }) => ExpenseCategoriesCompanion.insert(
                id: id,
                key: key,
                name: name,
                nameAr: nameAr,
                sortOrder: sortOrder,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ExpenseCategoriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ExpenseCategoriesTable,
      ExpenseCategoryRow,
      $$ExpenseCategoriesTableFilterComposer,
      $$ExpenseCategoriesTableOrderingComposer,
      $$ExpenseCategoriesTableAnnotationComposer,
      $$ExpenseCategoriesTableCreateCompanionBuilder,
      $$ExpenseCategoriesTableUpdateCompanionBuilder,
      (
        ExpenseCategoryRow,
        BaseReferences<
          _$AppDatabase,
          $ExpenseCategoriesTable,
          ExpenseCategoryRow
        >,
      ),
      ExpenseCategoryRow,
      PrefetchHooks Function()
    >;
typedef $$BranchIngredientStockTableCreateCompanionBuilder =
    BranchIngredientStockCompanion Function({
      Value<int> ingredientId,
      Value<double> quantity,
    });
typedef $$BranchIngredientStockTableUpdateCompanionBuilder =
    BranchIngredientStockCompanion Function({
      Value<int> ingredientId,
      Value<double> quantity,
    });

class $$BranchIngredientStockTableFilterComposer
    extends Composer<_$AppDatabase, $BranchIngredientStockTable> {
  $$BranchIngredientStockTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get ingredientId => $composableBuilder(
    column: $table.ingredientId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get quantity => $composableBuilder(
    column: $table.quantity,
    builder: (column) => ColumnFilters(column),
  );
}

class $$BranchIngredientStockTableOrderingComposer
    extends Composer<_$AppDatabase, $BranchIngredientStockTable> {
  $$BranchIngredientStockTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get ingredientId => $composableBuilder(
    column: $table.ingredientId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get quantity => $composableBuilder(
    column: $table.quantity,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$BranchIngredientStockTableAnnotationComposer
    extends Composer<_$AppDatabase, $BranchIngredientStockTable> {
  $$BranchIngredientStockTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get ingredientId => $composableBuilder(
    column: $table.ingredientId,
    builder: (column) => column,
  );

  GeneratedColumn<double> get quantity =>
      $composableBuilder(column: $table.quantity, builder: (column) => column);
}

class $$BranchIngredientStockTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $BranchIngredientStockTable,
          BranchIngredientStockRow,
          $$BranchIngredientStockTableFilterComposer,
          $$BranchIngredientStockTableOrderingComposer,
          $$BranchIngredientStockTableAnnotationComposer,
          $$BranchIngredientStockTableCreateCompanionBuilder,
          $$BranchIngredientStockTableUpdateCompanionBuilder,
          (
            BranchIngredientStockRow,
            BaseReferences<
              _$AppDatabase,
              $BranchIngredientStockTable,
              BranchIngredientStockRow
            >,
          ),
          BranchIngredientStockRow,
          PrefetchHooks Function()
        > {
  $$BranchIngredientStockTableTableManager(
    _$AppDatabase db,
    $BranchIngredientStockTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BranchIngredientStockTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$BranchIngredientStockTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$BranchIngredientStockTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> ingredientId = const Value.absent(),
                Value<double> quantity = const Value.absent(),
              }) => BranchIngredientStockCompanion(
                ingredientId: ingredientId,
                quantity: quantity,
              ),
          createCompanionCallback:
              ({
                Value<int> ingredientId = const Value.absent(),
                Value<double> quantity = const Value.absent(),
              }) => BranchIngredientStockCompanion.insert(
                ingredientId: ingredientId,
                quantity: quantity,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$BranchIngredientStockTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $BranchIngredientStockTable,
      BranchIngredientStockRow,
      $$BranchIngredientStockTableFilterComposer,
      $$BranchIngredientStockTableOrderingComposer,
      $$BranchIngredientStockTableAnnotationComposer,
      $$BranchIngredientStockTableCreateCompanionBuilder,
      $$BranchIngredientStockTableUpdateCompanionBuilder,
      (
        BranchIngredientStockRow,
        BaseReferences<
          _$AppDatabase,
          $BranchIngredientStockTable,
          BranchIngredientStockRow
        >,
      ),
      BranchIngredientStockRow,
      PrefetchHooks Function()
    >;
typedef $$DiscountsTableCreateCompanionBuilder =
    DiscountsCompanion Function({
      Value<int> id,
      Value<String> name,
      Value<String?> scope,
      Value<String?> amountType,
      Value<int?> amountBaisas,
      Value<double?> percent,
      Value<DateTime?> validityStart,
      Value<DateTime?> validityEnd,
      Value<int?> dayofweekMask,
      Value<String?> timeStart,
      Value<String?> timeEnd,
      Value<String?> branchScopeJson,
      Value<bool> stackable,
      Value<bool> requiresManagerApproval,
      Value<bool> autoApply,
      Value<String?> status,
      Value<String> targetsJson,
    });
typedef $$DiscountsTableUpdateCompanionBuilder =
    DiscountsCompanion Function({
      Value<int> id,
      Value<String> name,
      Value<String?> scope,
      Value<String?> amountType,
      Value<int?> amountBaisas,
      Value<double?> percent,
      Value<DateTime?> validityStart,
      Value<DateTime?> validityEnd,
      Value<int?> dayofweekMask,
      Value<String?> timeStart,
      Value<String?> timeEnd,
      Value<String?> branchScopeJson,
      Value<bool> stackable,
      Value<bool> requiresManagerApproval,
      Value<bool> autoApply,
      Value<String?> status,
      Value<String> targetsJson,
    });

class $$DiscountsTableFilterComposer
    extends Composer<_$AppDatabase, $DiscountsTable> {
  $$DiscountsTableFilterComposer({
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

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get scope => $composableBuilder(
    column: $table.scope,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get amountType => $composableBuilder(
    column: $table.amountType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get amountBaisas => $composableBuilder(
    column: $table.amountBaisas,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get percent => $composableBuilder(
    column: $table.percent,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get validityStart => $composableBuilder(
    column: $table.validityStart,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get validityEnd => $composableBuilder(
    column: $table.validityEnd,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get dayofweekMask => $composableBuilder(
    column: $table.dayofweekMask,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get timeStart => $composableBuilder(
    column: $table.timeStart,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get timeEnd => $composableBuilder(
    column: $table.timeEnd,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get branchScopeJson => $composableBuilder(
    column: $table.branchScopeJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get stackable => $composableBuilder(
    column: $table.stackable,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get requiresManagerApproval => $composableBuilder(
    column: $table.requiresManagerApproval,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get autoApply => $composableBuilder(
    column: $table.autoApply,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get targetsJson => $composableBuilder(
    column: $table.targetsJson,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DiscountsTableOrderingComposer
    extends Composer<_$AppDatabase, $DiscountsTable> {
  $$DiscountsTableOrderingComposer({
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

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get scope => $composableBuilder(
    column: $table.scope,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get amountType => $composableBuilder(
    column: $table.amountType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get amountBaisas => $composableBuilder(
    column: $table.amountBaisas,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get percent => $composableBuilder(
    column: $table.percent,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get validityStart => $composableBuilder(
    column: $table.validityStart,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get validityEnd => $composableBuilder(
    column: $table.validityEnd,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get dayofweekMask => $composableBuilder(
    column: $table.dayofweekMask,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get timeStart => $composableBuilder(
    column: $table.timeStart,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get timeEnd => $composableBuilder(
    column: $table.timeEnd,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get branchScopeJson => $composableBuilder(
    column: $table.branchScopeJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get stackable => $composableBuilder(
    column: $table.stackable,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get requiresManagerApproval => $composableBuilder(
    column: $table.requiresManagerApproval,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get autoApply => $composableBuilder(
    column: $table.autoApply,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get targetsJson => $composableBuilder(
    column: $table.targetsJson,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DiscountsTableAnnotationComposer
    extends Composer<_$AppDatabase, $DiscountsTable> {
  $$DiscountsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get scope =>
      $composableBuilder(column: $table.scope, builder: (column) => column);

  GeneratedColumn<String> get amountType => $composableBuilder(
    column: $table.amountType,
    builder: (column) => column,
  );

  GeneratedColumn<int> get amountBaisas => $composableBuilder(
    column: $table.amountBaisas,
    builder: (column) => column,
  );

  GeneratedColumn<double> get percent =>
      $composableBuilder(column: $table.percent, builder: (column) => column);

  GeneratedColumn<DateTime> get validityStart => $composableBuilder(
    column: $table.validityStart,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get validityEnd => $composableBuilder(
    column: $table.validityEnd,
    builder: (column) => column,
  );

  GeneratedColumn<int> get dayofweekMask => $composableBuilder(
    column: $table.dayofweekMask,
    builder: (column) => column,
  );

  GeneratedColumn<String> get timeStart =>
      $composableBuilder(column: $table.timeStart, builder: (column) => column);

  GeneratedColumn<String> get timeEnd =>
      $composableBuilder(column: $table.timeEnd, builder: (column) => column);

  GeneratedColumn<String> get branchScopeJson => $composableBuilder(
    column: $table.branchScopeJson,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get stackable =>
      $composableBuilder(column: $table.stackable, builder: (column) => column);

  GeneratedColumn<bool> get requiresManagerApproval => $composableBuilder(
    column: $table.requiresManagerApproval,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get autoApply =>
      $composableBuilder(column: $table.autoApply, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get targetsJson => $composableBuilder(
    column: $table.targetsJson,
    builder: (column) => column,
  );
}

class $$DiscountsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $DiscountsTable,
          DiscountRow,
          $$DiscountsTableFilterComposer,
          $$DiscountsTableOrderingComposer,
          $$DiscountsTableAnnotationComposer,
          $$DiscountsTableCreateCompanionBuilder,
          $$DiscountsTableUpdateCompanionBuilder,
          (
            DiscountRow,
            BaseReferences<_$AppDatabase, $DiscountsTable, DiscountRow>,
          ),
          DiscountRow,
          PrefetchHooks Function()
        > {
  $$DiscountsTableTableManager(_$AppDatabase db, $DiscountsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DiscountsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DiscountsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DiscountsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> scope = const Value.absent(),
                Value<String?> amountType = const Value.absent(),
                Value<int?> amountBaisas = const Value.absent(),
                Value<double?> percent = const Value.absent(),
                Value<DateTime?> validityStart = const Value.absent(),
                Value<DateTime?> validityEnd = const Value.absent(),
                Value<int?> dayofweekMask = const Value.absent(),
                Value<String?> timeStart = const Value.absent(),
                Value<String?> timeEnd = const Value.absent(),
                Value<String?> branchScopeJson = const Value.absent(),
                Value<bool> stackable = const Value.absent(),
                Value<bool> requiresManagerApproval = const Value.absent(),
                Value<bool> autoApply = const Value.absent(),
                Value<String?> status = const Value.absent(),
                Value<String> targetsJson = const Value.absent(),
              }) => DiscountsCompanion(
                id: id,
                name: name,
                scope: scope,
                amountType: amountType,
                amountBaisas: amountBaisas,
                percent: percent,
                validityStart: validityStart,
                validityEnd: validityEnd,
                dayofweekMask: dayofweekMask,
                timeStart: timeStart,
                timeEnd: timeEnd,
                branchScopeJson: branchScopeJson,
                stackable: stackable,
                requiresManagerApproval: requiresManagerApproval,
                autoApply: autoApply,
                status: status,
                targetsJson: targetsJson,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> scope = const Value.absent(),
                Value<String?> amountType = const Value.absent(),
                Value<int?> amountBaisas = const Value.absent(),
                Value<double?> percent = const Value.absent(),
                Value<DateTime?> validityStart = const Value.absent(),
                Value<DateTime?> validityEnd = const Value.absent(),
                Value<int?> dayofweekMask = const Value.absent(),
                Value<String?> timeStart = const Value.absent(),
                Value<String?> timeEnd = const Value.absent(),
                Value<String?> branchScopeJson = const Value.absent(),
                Value<bool> stackable = const Value.absent(),
                Value<bool> requiresManagerApproval = const Value.absent(),
                Value<bool> autoApply = const Value.absent(),
                Value<String?> status = const Value.absent(),
                Value<String> targetsJson = const Value.absent(),
              }) => DiscountsCompanion.insert(
                id: id,
                name: name,
                scope: scope,
                amountType: amountType,
                amountBaisas: amountBaisas,
                percent: percent,
                validityStart: validityStart,
                validityEnd: validityEnd,
                dayofweekMask: dayofweekMask,
                timeStart: timeStart,
                timeEnd: timeEnd,
                branchScopeJson: branchScopeJson,
                stackable: stackable,
                requiresManagerApproval: requiresManagerApproval,
                autoApply: autoApply,
                status: status,
                targetsJson: targetsJson,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DiscountsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $DiscountsTable,
      DiscountRow,
      $$DiscountsTableFilterComposer,
      $$DiscountsTableOrderingComposer,
      $$DiscountsTableAnnotationComposer,
      $$DiscountsTableCreateCompanionBuilder,
      $$DiscountsTableUpdateCompanionBuilder,
      (
        DiscountRow,
        BaseReferences<_$AppDatabase, $DiscountsTable, DiscountRow>,
      ),
      DiscountRow,
      PrefetchHooks Function()
    >;
typedef $$LoyaltyRulesTableCreateCompanionBuilder =
    LoyaltyRulesCompanion Function({
      Value<int> id,
      Value<String> name,
      Value<String?> type,
      Value<String> configJson,
      Value<DateTime?> validityStart,
      Value<DateTime?> validityEnd,
      Value<String?> status,
    });
typedef $$LoyaltyRulesTableUpdateCompanionBuilder =
    LoyaltyRulesCompanion Function({
      Value<int> id,
      Value<String> name,
      Value<String?> type,
      Value<String> configJson,
      Value<DateTime?> validityStart,
      Value<DateTime?> validityEnd,
      Value<String?> status,
    });

class $$LoyaltyRulesTableFilterComposer
    extends Composer<_$AppDatabase, $LoyaltyRulesTable> {
  $$LoyaltyRulesTableFilterComposer({
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

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get configJson => $composableBuilder(
    column: $table.configJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get validityStart => $composableBuilder(
    column: $table.validityStart,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get validityEnd => $composableBuilder(
    column: $table.validityEnd,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LoyaltyRulesTableOrderingComposer
    extends Composer<_$AppDatabase, $LoyaltyRulesTable> {
  $$LoyaltyRulesTableOrderingComposer({
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

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get configJson => $composableBuilder(
    column: $table.configJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get validityStart => $composableBuilder(
    column: $table.validityStart,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get validityEnd => $composableBuilder(
    column: $table.validityEnd,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LoyaltyRulesTableAnnotationComposer
    extends Composer<_$AppDatabase, $LoyaltyRulesTable> {
  $$LoyaltyRulesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get configJson => $composableBuilder(
    column: $table.configJson,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get validityStart => $composableBuilder(
    column: $table.validityStart,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get validityEnd => $composableBuilder(
    column: $table.validityEnd,
    builder: (column) => column,
  );

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);
}

class $$LoyaltyRulesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LoyaltyRulesTable,
          LoyaltyRuleRow,
          $$LoyaltyRulesTableFilterComposer,
          $$LoyaltyRulesTableOrderingComposer,
          $$LoyaltyRulesTableAnnotationComposer,
          $$LoyaltyRulesTableCreateCompanionBuilder,
          $$LoyaltyRulesTableUpdateCompanionBuilder,
          (
            LoyaltyRuleRow,
            BaseReferences<_$AppDatabase, $LoyaltyRulesTable, LoyaltyRuleRow>,
          ),
          LoyaltyRuleRow,
          PrefetchHooks Function()
        > {
  $$LoyaltyRulesTableTableManager(_$AppDatabase db, $LoyaltyRulesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LoyaltyRulesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LoyaltyRulesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LoyaltyRulesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> type = const Value.absent(),
                Value<String> configJson = const Value.absent(),
                Value<DateTime?> validityStart = const Value.absent(),
                Value<DateTime?> validityEnd = const Value.absent(),
                Value<String?> status = const Value.absent(),
              }) => LoyaltyRulesCompanion(
                id: id,
                name: name,
                type: type,
                configJson: configJson,
                validityStart: validityStart,
                validityEnd: validityEnd,
                status: status,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> type = const Value.absent(),
                Value<String> configJson = const Value.absent(),
                Value<DateTime?> validityStart = const Value.absent(),
                Value<DateTime?> validityEnd = const Value.absent(),
                Value<String?> status = const Value.absent(),
              }) => LoyaltyRulesCompanion.insert(
                id: id,
                name: name,
                type: type,
                configJson: configJson,
                validityStart: validityStart,
                validityEnd: validityEnd,
                status: status,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LoyaltyRulesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LoyaltyRulesTable,
      LoyaltyRuleRow,
      $$LoyaltyRulesTableFilterComposer,
      $$LoyaltyRulesTableOrderingComposer,
      $$LoyaltyRulesTableAnnotationComposer,
      $$LoyaltyRulesTableCreateCompanionBuilder,
      $$LoyaltyRulesTableUpdateCompanionBuilder,
      (
        LoyaltyRuleRow,
        BaseReferences<_$AppDatabase, $LoyaltyRulesTable, LoyaltyRuleRow>,
      ),
      LoyaltyRuleRow,
      PrefetchHooks Function()
    >;
typedef $$CachedCustomersTableCreateCompanionBuilder =
    CachedCustomersCompanion Function({
      Value<int> id,
      Value<String> name,
      Value<String?> phone,
      Value<int> walletBalanceBaisas,
      Value<String> loyaltyJson,
      Value<String> platesJson,
    });
typedef $$CachedCustomersTableUpdateCompanionBuilder =
    CachedCustomersCompanion Function({
      Value<int> id,
      Value<String> name,
      Value<String?> phone,
      Value<int> walletBalanceBaisas,
      Value<String> loyaltyJson,
      Value<String> platesJson,
    });

class $$CachedCustomersTableFilterComposer
    extends Composer<_$AppDatabase, $CachedCustomersTable> {
  $$CachedCustomersTableFilterComposer({
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

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get phone => $composableBuilder(
    column: $table.phone,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get walletBalanceBaisas => $composableBuilder(
    column: $table.walletBalanceBaisas,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get loyaltyJson => $composableBuilder(
    column: $table.loyaltyJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get platesJson => $composableBuilder(
    column: $table.platesJson,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedCustomersTableOrderingComposer
    extends Composer<_$AppDatabase, $CachedCustomersTable> {
  $$CachedCustomersTableOrderingComposer({
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

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get phone => $composableBuilder(
    column: $table.phone,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get walletBalanceBaisas => $composableBuilder(
    column: $table.walletBalanceBaisas,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get loyaltyJson => $composableBuilder(
    column: $table.loyaltyJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get platesJson => $composableBuilder(
    column: $table.platesJson,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedCustomersTableAnnotationComposer
    extends Composer<_$AppDatabase, $CachedCustomersTable> {
  $$CachedCustomersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get phone =>
      $composableBuilder(column: $table.phone, builder: (column) => column);

  GeneratedColumn<int> get walletBalanceBaisas => $composableBuilder(
    column: $table.walletBalanceBaisas,
    builder: (column) => column,
  );

  GeneratedColumn<String> get loyaltyJson => $composableBuilder(
    column: $table.loyaltyJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get platesJson => $composableBuilder(
    column: $table.platesJson,
    builder: (column) => column,
  );
}

class $$CachedCustomersTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CachedCustomersTable,
          CustomerRow,
          $$CachedCustomersTableFilterComposer,
          $$CachedCustomersTableOrderingComposer,
          $$CachedCustomersTableAnnotationComposer,
          $$CachedCustomersTableCreateCompanionBuilder,
          $$CachedCustomersTableUpdateCompanionBuilder,
          (
            CustomerRow,
            BaseReferences<_$AppDatabase, $CachedCustomersTable, CustomerRow>,
          ),
          CustomerRow,
          PrefetchHooks Function()
        > {
  $$CachedCustomersTableTableManager(
    _$AppDatabase db,
    $CachedCustomersTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedCustomersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedCustomersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedCustomersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> phone = const Value.absent(),
                Value<int> walletBalanceBaisas = const Value.absent(),
                Value<String> loyaltyJson = const Value.absent(),
                Value<String> platesJson = const Value.absent(),
              }) => CachedCustomersCompanion(
                id: id,
                name: name,
                phone: phone,
                walletBalanceBaisas: walletBalanceBaisas,
                loyaltyJson: loyaltyJson,
                platesJson: platesJson,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> phone = const Value.absent(),
                Value<int> walletBalanceBaisas = const Value.absent(),
                Value<String> loyaltyJson = const Value.absent(),
                Value<String> platesJson = const Value.absent(),
              }) => CachedCustomersCompanion.insert(
                id: id,
                name: name,
                phone: phone,
                walletBalanceBaisas: walletBalanceBaisas,
                loyaltyJson: loyaltyJson,
                platesJson: platesJson,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedCustomersTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CachedCustomersTable,
      CustomerRow,
      $$CachedCustomersTableFilterComposer,
      $$CachedCustomersTableOrderingComposer,
      $$CachedCustomersTableAnnotationComposer,
      $$CachedCustomersTableCreateCompanionBuilder,
      $$CachedCustomersTableUpdateCompanionBuilder,
      (
        CustomerRow,
        BaseReferences<_$AppDatabase, $CachedCustomersTable, CustomerRow>,
      ),
      CustomerRow,
      PrefetchHooks Function()
    >;
typedef $$IngredientsTableCreateCompanionBuilder =
    IngredientsCompanion Function({
      Value<int> id,
      Value<String> name,
      Value<String?> nameAr,
      Value<String?> unit,
      Value<String?> pieceUnitLabel,
      Value<String?> pieceUnitLabelAr,
      Value<double?> unitsPerPiece,
      Value<bool> allowFractionalPieces,
    });
typedef $$IngredientsTableUpdateCompanionBuilder =
    IngredientsCompanion Function({
      Value<int> id,
      Value<String> name,
      Value<String?> nameAr,
      Value<String?> unit,
      Value<String?> pieceUnitLabel,
      Value<String?> pieceUnitLabelAr,
      Value<double?> unitsPerPiece,
      Value<bool> allowFractionalPieces,
    });

class $$IngredientsTableFilterComposer
    extends Composer<_$AppDatabase, $IngredientsTable> {
  $$IngredientsTableFilterComposer({
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

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get nameAr => $composableBuilder(
    column: $table.nameAr,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get unit => $composableBuilder(
    column: $table.unit,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get pieceUnitLabel => $composableBuilder(
    column: $table.pieceUnitLabel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get pieceUnitLabelAr => $composableBuilder(
    column: $table.pieceUnitLabelAr,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get unitsPerPiece => $composableBuilder(
    column: $table.unitsPerPiece,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get allowFractionalPieces => $composableBuilder(
    column: $table.allowFractionalPieces,
    builder: (column) => ColumnFilters(column),
  );
}

class $$IngredientsTableOrderingComposer
    extends Composer<_$AppDatabase, $IngredientsTable> {
  $$IngredientsTableOrderingComposer({
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

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get nameAr => $composableBuilder(
    column: $table.nameAr,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get unit => $composableBuilder(
    column: $table.unit,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get pieceUnitLabel => $composableBuilder(
    column: $table.pieceUnitLabel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get pieceUnitLabelAr => $composableBuilder(
    column: $table.pieceUnitLabelAr,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get unitsPerPiece => $composableBuilder(
    column: $table.unitsPerPiece,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get allowFractionalPieces => $composableBuilder(
    column: $table.allowFractionalPieces,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$IngredientsTableAnnotationComposer
    extends Composer<_$AppDatabase, $IngredientsTable> {
  $$IngredientsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get nameAr =>
      $composableBuilder(column: $table.nameAr, builder: (column) => column);

  GeneratedColumn<String> get unit =>
      $composableBuilder(column: $table.unit, builder: (column) => column);

  GeneratedColumn<String> get pieceUnitLabel => $composableBuilder(
    column: $table.pieceUnitLabel,
    builder: (column) => column,
  );

  GeneratedColumn<String> get pieceUnitLabelAr => $composableBuilder(
    column: $table.pieceUnitLabelAr,
    builder: (column) => column,
  );

  GeneratedColumn<double> get unitsPerPiece => $composableBuilder(
    column: $table.unitsPerPiece,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get allowFractionalPieces => $composableBuilder(
    column: $table.allowFractionalPieces,
    builder: (column) => column,
  );
}

class $$IngredientsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $IngredientsTable,
          IngredientRow,
          $$IngredientsTableFilterComposer,
          $$IngredientsTableOrderingComposer,
          $$IngredientsTableAnnotationComposer,
          $$IngredientsTableCreateCompanionBuilder,
          $$IngredientsTableUpdateCompanionBuilder,
          (
            IngredientRow,
            BaseReferences<_$AppDatabase, $IngredientsTable, IngredientRow>,
          ),
          IngredientRow,
          PrefetchHooks Function()
        > {
  $$IngredientsTableTableManager(_$AppDatabase db, $IngredientsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$IngredientsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$IngredientsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$IngredientsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> nameAr = const Value.absent(),
                Value<String?> unit = const Value.absent(),
                Value<String?> pieceUnitLabel = const Value.absent(),
                Value<String?> pieceUnitLabelAr = const Value.absent(),
                Value<double?> unitsPerPiece = const Value.absent(),
                Value<bool> allowFractionalPieces = const Value.absent(),
              }) => IngredientsCompanion(
                id: id,
                name: name,
                nameAr: nameAr,
                unit: unit,
                pieceUnitLabel: pieceUnitLabel,
                pieceUnitLabelAr: pieceUnitLabelAr,
                unitsPerPiece: unitsPerPiece,
                allowFractionalPieces: allowFractionalPieces,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> nameAr = const Value.absent(),
                Value<String?> unit = const Value.absent(),
                Value<String?> pieceUnitLabel = const Value.absent(),
                Value<String?> pieceUnitLabelAr = const Value.absent(),
                Value<double?> unitsPerPiece = const Value.absent(),
                Value<bool> allowFractionalPieces = const Value.absent(),
              }) => IngredientsCompanion.insert(
                id: id,
                name: name,
                nameAr: nameAr,
                unit: unit,
                pieceUnitLabel: pieceUnitLabel,
                pieceUnitLabelAr: pieceUnitLabelAr,
                unitsPerPiece: unitsPerPiece,
                allowFractionalPieces: allowFractionalPieces,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$IngredientsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $IngredientsTable,
      IngredientRow,
      $$IngredientsTableFilterComposer,
      $$IngredientsTableOrderingComposer,
      $$IngredientsTableAnnotationComposer,
      $$IngredientsTableCreateCompanionBuilder,
      $$IngredientsTableUpdateCompanionBuilder,
      (
        IngredientRow,
        BaseReferences<_$AppDatabase, $IngredientsTable, IngredientRow>,
      ),
      IngredientRow,
      PrefetchHooks Function()
    >;
typedef $$VoidReasonsTableCreateCompanionBuilder =
    VoidReasonsCompanion Function({
      Value<int> id,
      Value<String> code,
      Value<String> name,
      Value<String?> nameAr,
      Value<bool> affectsInventory,
      Value<bool> requiresManager,
      Value<int> sortOrder,
    });
typedef $$VoidReasonsTableUpdateCompanionBuilder =
    VoidReasonsCompanion Function({
      Value<int> id,
      Value<String> code,
      Value<String> name,
      Value<String?> nameAr,
      Value<bool> affectsInventory,
      Value<bool> requiresManager,
      Value<int> sortOrder,
    });

class $$VoidReasonsTableFilterComposer
    extends Composer<_$AppDatabase, $VoidReasonsTable> {
  $$VoidReasonsTableFilterComposer({
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

  ColumnFilters<String> get code => $composableBuilder(
    column: $table.code,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get nameAr => $composableBuilder(
    column: $table.nameAr,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get affectsInventory => $composableBuilder(
    column: $table.affectsInventory,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get requiresManager => $composableBuilder(
    column: $table.requiresManager,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );
}

class $$VoidReasonsTableOrderingComposer
    extends Composer<_$AppDatabase, $VoidReasonsTable> {
  $$VoidReasonsTableOrderingComposer({
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

  ColumnOrderings<String> get code => $composableBuilder(
    column: $table.code,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get nameAr => $composableBuilder(
    column: $table.nameAr,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get affectsInventory => $composableBuilder(
    column: $table.affectsInventory,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get requiresManager => $composableBuilder(
    column: $table.requiresManager,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$VoidReasonsTableAnnotationComposer
    extends Composer<_$AppDatabase, $VoidReasonsTable> {
  $$VoidReasonsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get code =>
      $composableBuilder(column: $table.code, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get nameAr =>
      $composableBuilder(column: $table.nameAr, builder: (column) => column);

  GeneratedColumn<bool> get affectsInventory => $composableBuilder(
    column: $table.affectsInventory,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get requiresManager => $composableBuilder(
    column: $table.requiresManager,
    builder: (column) => column,
  );

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);
}

class $$VoidReasonsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $VoidReasonsTable,
          VoidReasonRow,
          $$VoidReasonsTableFilterComposer,
          $$VoidReasonsTableOrderingComposer,
          $$VoidReasonsTableAnnotationComposer,
          $$VoidReasonsTableCreateCompanionBuilder,
          $$VoidReasonsTableUpdateCompanionBuilder,
          (
            VoidReasonRow,
            BaseReferences<_$AppDatabase, $VoidReasonsTable, VoidReasonRow>,
          ),
          VoidReasonRow,
          PrefetchHooks Function()
        > {
  $$VoidReasonsTableTableManager(_$AppDatabase db, $VoidReasonsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$VoidReasonsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$VoidReasonsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$VoidReasonsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> code = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> nameAr = const Value.absent(),
                Value<bool> affectsInventory = const Value.absent(),
                Value<bool> requiresManager = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
              }) => VoidReasonsCompanion(
                id: id,
                code: code,
                name: name,
                nameAr: nameAr,
                affectsInventory: affectsInventory,
                requiresManager: requiresManager,
                sortOrder: sortOrder,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> code = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> nameAr = const Value.absent(),
                Value<bool> affectsInventory = const Value.absent(),
                Value<bool> requiresManager = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
              }) => VoidReasonsCompanion.insert(
                id: id,
                code: code,
                name: name,
                nameAr: nameAr,
                affectsInventory: affectsInventory,
                requiresManager: requiresManager,
                sortOrder: sortOrder,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$VoidReasonsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $VoidReasonsTable,
      VoidReasonRow,
      $$VoidReasonsTableFilterComposer,
      $$VoidReasonsTableOrderingComposer,
      $$VoidReasonsTableAnnotationComposer,
      $$VoidReasonsTableCreateCompanionBuilder,
      $$VoidReasonsTableUpdateCompanionBuilder,
      (
        VoidReasonRow,
        BaseReferences<_$AppDatabase, $VoidReasonsTable, VoidReasonRow>,
      ),
      VoidReasonRow,
      PrefetchHooks Function()
    >;
typedef $$CompReasonsTableCreateCompanionBuilder =
    CompReasonsCompanion Function({
      Value<int> id,
      Value<String> code,
      Value<String> name,
      Value<String?> nameAr,
      Value<int?> maxAmountBaisas,
      Value<int> sortOrder,
    });
typedef $$CompReasonsTableUpdateCompanionBuilder =
    CompReasonsCompanion Function({
      Value<int> id,
      Value<String> code,
      Value<String> name,
      Value<String?> nameAr,
      Value<int?> maxAmountBaisas,
      Value<int> sortOrder,
    });

class $$CompReasonsTableFilterComposer
    extends Composer<_$AppDatabase, $CompReasonsTable> {
  $$CompReasonsTableFilterComposer({
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

  ColumnFilters<String> get code => $composableBuilder(
    column: $table.code,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get nameAr => $composableBuilder(
    column: $table.nameAr,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get maxAmountBaisas => $composableBuilder(
    column: $table.maxAmountBaisas,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CompReasonsTableOrderingComposer
    extends Composer<_$AppDatabase, $CompReasonsTable> {
  $$CompReasonsTableOrderingComposer({
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

  ColumnOrderings<String> get code => $composableBuilder(
    column: $table.code,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get nameAr => $composableBuilder(
    column: $table.nameAr,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get maxAmountBaisas => $composableBuilder(
    column: $table.maxAmountBaisas,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CompReasonsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CompReasonsTable> {
  $$CompReasonsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get code =>
      $composableBuilder(column: $table.code, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get nameAr =>
      $composableBuilder(column: $table.nameAr, builder: (column) => column);

  GeneratedColumn<int> get maxAmountBaisas => $composableBuilder(
    column: $table.maxAmountBaisas,
    builder: (column) => column,
  );

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);
}

class $$CompReasonsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CompReasonsTable,
          CompReasonRow,
          $$CompReasonsTableFilterComposer,
          $$CompReasonsTableOrderingComposer,
          $$CompReasonsTableAnnotationComposer,
          $$CompReasonsTableCreateCompanionBuilder,
          $$CompReasonsTableUpdateCompanionBuilder,
          (
            CompReasonRow,
            BaseReferences<_$AppDatabase, $CompReasonsTable, CompReasonRow>,
          ),
          CompReasonRow,
          PrefetchHooks Function()
        > {
  $$CompReasonsTableTableManager(_$AppDatabase db, $CompReasonsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CompReasonsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CompReasonsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CompReasonsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> code = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> nameAr = const Value.absent(),
                Value<int?> maxAmountBaisas = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
              }) => CompReasonsCompanion(
                id: id,
                code: code,
                name: name,
                nameAr: nameAr,
                maxAmountBaisas: maxAmountBaisas,
                sortOrder: sortOrder,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> code = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> nameAr = const Value.absent(),
                Value<int?> maxAmountBaisas = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
              }) => CompReasonsCompanion.insert(
                id: id,
                code: code,
                name: name,
                nameAr: nameAr,
                maxAmountBaisas: maxAmountBaisas,
                sortOrder: sortOrder,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CompReasonsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CompReasonsTable,
      CompReasonRow,
      $$CompReasonsTableFilterComposer,
      $$CompReasonsTableOrderingComposer,
      $$CompReasonsTableAnnotationComposer,
      $$CompReasonsTableCreateCompanionBuilder,
      $$CompReasonsTableUpdateCompanionBuilder,
      (
        CompReasonRow,
        BaseReferences<_$AppDatabase, $CompReasonsTable, CompReasonRow>,
      ),
      CompReasonRow,
      PrefetchHooks Function()
    >;
typedef $$OffersTableCreateCompanionBuilder =
    OffersCompanion Function({
      Value<int> id,
      Value<String> name,
      Value<String?> nameAr,
      Value<String> type,
      Value<String> configJson,
      Value<bool> autoApply,
      Value<DateTime?> validityStart,
      Value<DateTime?> validityEnd,
      Value<int?> dayofweekMask,
      Value<String?> timeStart,
      Value<String?> timeEnd,
      Value<String?> branchScopeJson,
      Value<int?> maxPerOrder,
      Value<String?> status,
    });
typedef $$OffersTableUpdateCompanionBuilder =
    OffersCompanion Function({
      Value<int> id,
      Value<String> name,
      Value<String?> nameAr,
      Value<String> type,
      Value<String> configJson,
      Value<bool> autoApply,
      Value<DateTime?> validityStart,
      Value<DateTime?> validityEnd,
      Value<int?> dayofweekMask,
      Value<String?> timeStart,
      Value<String?> timeEnd,
      Value<String?> branchScopeJson,
      Value<int?> maxPerOrder,
      Value<String?> status,
    });

class $$OffersTableFilterComposer
    extends Composer<_$AppDatabase, $OffersTable> {
  $$OffersTableFilterComposer({
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

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get nameAr => $composableBuilder(
    column: $table.nameAr,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get configJson => $composableBuilder(
    column: $table.configJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get autoApply => $composableBuilder(
    column: $table.autoApply,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get validityStart => $composableBuilder(
    column: $table.validityStart,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get validityEnd => $composableBuilder(
    column: $table.validityEnd,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get dayofweekMask => $composableBuilder(
    column: $table.dayofweekMask,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get timeStart => $composableBuilder(
    column: $table.timeStart,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get timeEnd => $composableBuilder(
    column: $table.timeEnd,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get branchScopeJson => $composableBuilder(
    column: $table.branchScopeJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get maxPerOrder => $composableBuilder(
    column: $table.maxPerOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );
}

class $$OffersTableOrderingComposer
    extends Composer<_$AppDatabase, $OffersTable> {
  $$OffersTableOrderingComposer({
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

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get nameAr => $composableBuilder(
    column: $table.nameAr,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get configJson => $composableBuilder(
    column: $table.configJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get autoApply => $composableBuilder(
    column: $table.autoApply,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get validityStart => $composableBuilder(
    column: $table.validityStart,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get validityEnd => $composableBuilder(
    column: $table.validityEnd,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get dayofweekMask => $composableBuilder(
    column: $table.dayofweekMask,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get timeStart => $composableBuilder(
    column: $table.timeStart,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get timeEnd => $composableBuilder(
    column: $table.timeEnd,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get branchScopeJson => $composableBuilder(
    column: $table.branchScopeJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get maxPerOrder => $composableBuilder(
    column: $table.maxPerOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$OffersTableAnnotationComposer
    extends Composer<_$AppDatabase, $OffersTable> {
  $$OffersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get nameAr =>
      $composableBuilder(column: $table.nameAr, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get configJson => $composableBuilder(
    column: $table.configJson,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get autoApply =>
      $composableBuilder(column: $table.autoApply, builder: (column) => column);

  GeneratedColumn<DateTime> get validityStart => $composableBuilder(
    column: $table.validityStart,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get validityEnd => $composableBuilder(
    column: $table.validityEnd,
    builder: (column) => column,
  );

  GeneratedColumn<int> get dayofweekMask => $composableBuilder(
    column: $table.dayofweekMask,
    builder: (column) => column,
  );

  GeneratedColumn<String> get timeStart =>
      $composableBuilder(column: $table.timeStart, builder: (column) => column);

  GeneratedColumn<String> get timeEnd =>
      $composableBuilder(column: $table.timeEnd, builder: (column) => column);

  GeneratedColumn<String> get branchScopeJson => $composableBuilder(
    column: $table.branchScopeJson,
    builder: (column) => column,
  );

  GeneratedColumn<int> get maxPerOrder => $composableBuilder(
    column: $table.maxPerOrder,
    builder: (column) => column,
  );

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);
}

class $$OffersTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $OffersTable,
          OfferRow,
          $$OffersTableFilterComposer,
          $$OffersTableOrderingComposer,
          $$OffersTableAnnotationComposer,
          $$OffersTableCreateCompanionBuilder,
          $$OffersTableUpdateCompanionBuilder,
          (OfferRow, BaseReferences<_$AppDatabase, $OffersTable, OfferRow>),
          OfferRow,
          PrefetchHooks Function()
        > {
  $$OffersTableTableManager(_$AppDatabase db, $OffersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OffersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$OffersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$OffersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> nameAr = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<String> configJson = const Value.absent(),
                Value<bool> autoApply = const Value.absent(),
                Value<DateTime?> validityStart = const Value.absent(),
                Value<DateTime?> validityEnd = const Value.absent(),
                Value<int?> dayofweekMask = const Value.absent(),
                Value<String?> timeStart = const Value.absent(),
                Value<String?> timeEnd = const Value.absent(),
                Value<String?> branchScopeJson = const Value.absent(),
                Value<int?> maxPerOrder = const Value.absent(),
                Value<String?> status = const Value.absent(),
              }) => OffersCompanion(
                id: id,
                name: name,
                nameAr: nameAr,
                type: type,
                configJson: configJson,
                autoApply: autoApply,
                validityStart: validityStart,
                validityEnd: validityEnd,
                dayofweekMask: dayofweekMask,
                timeStart: timeStart,
                timeEnd: timeEnd,
                branchScopeJson: branchScopeJson,
                maxPerOrder: maxPerOrder,
                status: status,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> nameAr = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<String> configJson = const Value.absent(),
                Value<bool> autoApply = const Value.absent(),
                Value<DateTime?> validityStart = const Value.absent(),
                Value<DateTime?> validityEnd = const Value.absent(),
                Value<int?> dayofweekMask = const Value.absent(),
                Value<String?> timeStart = const Value.absent(),
                Value<String?> timeEnd = const Value.absent(),
                Value<String?> branchScopeJson = const Value.absent(),
                Value<int?> maxPerOrder = const Value.absent(),
                Value<String?> status = const Value.absent(),
              }) => OffersCompanion.insert(
                id: id,
                name: name,
                nameAr: nameAr,
                type: type,
                configJson: configJson,
                autoApply: autoApply,
                validityStart: validityStart,
                validityEnd: validityEnd,
                dayofweekMask: dayofweekMask,
                timeStart: timeStart,
                timeEnd: timeEnd,
                branchScopeJson: branchScopeJson,
                maxPerOrder: maxPerOrder,
                status: status,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$OffersTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $OffersTable,
      OfferRow,
      $$OffersTableFilterComposer,
      $$OffersTableOrderingComposer,
      $$OffersTableAnnotationComposer,
      $$OffersTableCreateCompanionBuilder,
      $$OffersTableUpdateCompanionBuilder,
      (OfferRow, BaseReferences<_$AppDatabase, $OffersTable, OfferRow>),
      OfferRow,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$BranchCacheTableTableManager get branchCache =>
      $$BranchCacheTableTableManager(_db, _db.branchCache);
  $$CategoriesTableTableManager get categories =>
      $$CategoriesTableTableManager(_db, _db.categories);
  $$ProductsTableTableManager get products =>
      $$ProductsTableTableManager(_db, _db.products);
  $$FloorsTableTableManager get floors =>
      $$FloorsTableTableManager(_db, _db.floors);
  $$PosTablesTableTableManager get posTables =>
      $$PosTablesTableTableManager(_db, _db.posTables);
  $$AddonGroupsTableTableManager get addonGroups =>
      $$AddonGroupsTableTableManager(_db, _db.addonGroups);
  $$AddonsTableTableManager get addons =>
      $$AddonsTableTableManager(_db, _db.addons);
  $$TaxCacheTableTableManager get taxCache =>
      $$TaxCacheTableTableManager(_db, _db.taxCache);
  $$SyncMetaTableTableManager get syncMeta =>
      $$SyncMetaTableTableManager(_db, _db.syncMeta);
  $$OrderOutboxTableTableManager get orderOutbox =>
      $$OrderOutboxTableTableManager(_db, _db.orderOutbox);
  $$DeliveryProvidersTableTableManager get deliveryProviders =>
      $$DeliveryProvidersTableTableManager(_db, _db.deliveryProviders);
  $$ExpenseCategoriesTableTableManager get expenseCategories =>
      $$ExpenseCategoriesTableTableManager(_db, _db.expenseCategories);
  $$BranchIngredientStockTableTableManager get branchIngredientStock =>
      $$BranchIngredientStockTableTableManager(_db, _db.branchIngredientStock);
  $$DiscountsTableTableManager get discounts =>
      $$DiscountsTableTableManager(_db, _db.discounts);
  $$LoyaltyRulesTableTableManager get loyaltyRules =>
      $$LoyaltyRulesTableTableManager(_db, _db.loyaltyRules);
  $$CachedCustomersTableTableManager get cachedCustomers =>
      $$CachedCustomersTableTableManager(_db, _db.cachedCustomers);
  $$IngredientsTableTableManager get ingredients =>
      $$IngredientsTableTableManager(_db, _db.ingredients);
  $$VoidReasonsTableTableManager get voidReasons =>
      $$VoidReasonsTableTableManager(_db, _db.voidReasons);
  $$CompReasonsTableTableManager get compReasons =>
      $$CompReasonsTableTableManager(_db, _db.compReasons);
  $$OffersTableTableManager get offers =>
      $$OffersTableTableManager(_db, _db.offers);
}
