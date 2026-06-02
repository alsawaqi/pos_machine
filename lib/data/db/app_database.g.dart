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
  const BranchRow({
    required this.id,
    required this.name,
    this.nameAr,
    this.latitude,
    this.longitude,
    this.geofenceRadiusM,
    this.defaultOrderType,
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
          ..write('status: $status')
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
          other.status == this.status);
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
  const BranchCacheCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.nameAr = const Value.absent(),
    this.latitude = const Value.absent(),
    this.longitude = const Value.absent(),
    this.geofenceRadiusM = const Value.absent(),
    this.defaultOrderType = const Value.absent(),
    this.status = const Value.absent(),
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
          ..write('status: $status')
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
  const CategoryRow({
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

  CategoryRow copyWith({
    int? id,
    String? name,
    Value<String?> nameAr = const Value.absent(),
    int? displayOrder,
    Value<String?> status = const Value.absent(),
  }) => CategoryRow(
    id: id ?? this.id,
    name: name ?? this.name,
    nameAr: nameAr.present ? nameAr.value : this.nameAr,
    displayOrder: displayOrder ?? this.displayOrder,
    status: status.present ? status.value : this.status,
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
    );
  }

  @override
  String toString() {
    return (StringBuffer('CategoryRow(')
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
      (other is CategoryRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.nameAr == this.nameAr &&
          other.displayOrder == this.displayOrder &&
          other.status == this.status);
}

class CategoriesCompanion extends UpdateCompanion<CategoryRow> {
  final Value<int> id;
  final Value<String> name;
  final Value<String?> nameAr;
  final Value<int> displayOrder;
  final Value<String?> status;
  const CategoriesCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.nameAr = const Value.absent(),
    this.displayOrder = const Value.absent(),
    this.status = const Value.absent(),
  });
  CategoriesCompanion.insert({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.nameAr = const Value.absent(),
    this.displayOrder = const Value.absent(),
    this.status = const Value.absent(),
  });
  static Insertable<CategoryRow> custom({
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

  CategoriesCompanion copyWith({
    Value<int>? id,
    Value<String>? name,
    Value<String?>? nameAr,
    Value<int>? displayOrder,
    Value<String?>? status,
  }) {
    return CategoriesCompanion(
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
    return (StringBuffer('CategoriesCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('nameAr: $nameAr, ')
          ..write('displayOrder: $displayOrder, ')
          ..write('status: $status')
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
  const ProductRow({
    required this.id,
    required this.name,
    this.nameAr,
    this.categoryId,
    required this.basePriceBaisas,
    this.branchStockQty,
    this.imageUrl,
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
          ..write('status: $status')
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
          other.status == this.status);
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
  const ProductsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.nameAr = const Value.absent(),
    this.categoryId = const Value.absent(),
    this.basePriceBaisas = const Value.absent(),
    this.branchStockQty = const Value.absent(),
    this.imageUrl = const Value.absent(),
    this.status = const Value.absent(),
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
          ..write('status: $status')
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
  final String? shape;
  final int displayOrder;
  final String? status;
  const TableRow({
    required this.id,
    required this.floorId,
    required this.label,
    required this.seats,
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
    Value<String?> shape = const Value.absent(),
    int? displayOrder,
    Value<String?> status = const Value.absent(),
  }) => TableRow(
    id: id ?? this.id,
    floorId: floorId ?? this.floorId,
    label: label ?? this.label,
    seats: seats ?? this.seats,
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
          ..write('shape: $shape, ')
          ..write('displayOrder: $displayOrder, ')
          ..write('status: $status')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, floorId, label, seats, shape, displayOrder, status);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TableRow &&
          other.id == this.id &&
          other.floorId == this.floorId &&
          other.label == this.label &&
          other.seats == this.seats &&
          other.shape == this.shape &&
          other.displayOrder == this.displayOrder &&
          other.status == this.status);
}

class PosTablesCompanion extends UpdateCompanion<TableRow> {
  final Value<int> id;
  final Value<int> floorId;
  final Value<String> label;
  final Value<int> seats;
  final Value<String?> shape;
  final Value<int> displayOrder;
  final Value<String?> status;
  const PosTablesCompanion({
    this.id = const Value.absent(),
    this.floorId = const Value.absent(),
    this.label = const Value.absent(),
    this.seats = const Value.absent(),
    this.shape = const Value.absent(),
    this.displayOrder = const Value.absent(),
    this.status = const Value.absent(),
  });
  PosTablesCompanion.insert({
    this.id = const Value.absent(),
    required int floorId,
    this.label = const Value.absent(),
    this.seats = const Value.absent(),
    this.shape = const Value.absent(),
    this.displayOrder = const Value.absent(),
    this.status = const Value.absent(),
  }) : floorId = Value(floorId);
  static Insertable<TableRow> custom({
    Expression<int>? id,
    Expression<int>? floorId,
    Expression<String>? label,
    Expression<int>? seats,
    Expression<String>? shape,
    Expression<int>? displayOrder,
    Expression<String>? status,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (floorId != null) 'floor_id': floorId,
      if (label != null) 'label': label,
      if (seats != null) 'seats': seats,
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
    Value<String?>? shape,
    Value<int>? displayOrder,
    Value<String?>? status,
  }) {
    return PosTablesCompanion(
      id: id ?? this.id,
      floorId: floorId ?? this.floorId,
      label: label ?? this.label,
      seats: seats ?? this.seats,
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
  final String? status;
  const AddonGroupRow({
    required this.id,
    required this.name,
    this.nameAr,
    this.selectionMode,
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
      'status': serializer.toJson<String?>(status),
    };
  }

  AddonGroupRow copyWith({
    int? id,
    String? name,
    Value<String?> nameAr = const Value.absent(),
    Value<String?> selectionMode = const Value.absent(),
    Value<String?> status = const Value.absent(),
  }) => AddonGroupRow(
    id: id ?? this.id,
    name: name ?? this.name,
    nameAr: nameAr.present ? nameAr.value : this.nameAr,
    selectionMode: selectionMode.present
        ? selectionMode.value
        : this.selectionMode,
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
          ..write('status: $status')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, nameAr, selectionMode, status);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AddonGroupRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.nameAr == this.nameAr &&
          other.selectionMode == this.selectionMode &&
          other.status == this.status);
}

class AddonGroupsCompanion extends UpdateCompanion<AddonGroupRow> {
  final Value<int> id;
  final Value<String> name;
  final Value<String?> nameAr;
  final Value<String?> selectionMode;
  final Value<String?> status;
  const AddonGroupsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.nameAr = const Value.absent(),
    this.selectionMode = const Value.absent(),
    this.status = const Value.absent(),
  });
  AddonGroupsCompanion.insert({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.nameAr = const Value.absent(),
    this.selectionMode = const Value.absent(),
    this.status = const Value.absent(),
  });
  static Insertable<AddonGroupRow> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<String>? nameAr,
    Expression<String>? selectionMode,
    Expression<String>? status,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (nameAr != null) 'name_ar': nameAr,
      if (selectionMode != null) 'selection_mode': selectionMode,
      if (status != null) 'status': status,
    });
  }

  AddonGroupsCompanion copyWith({
    Value<int>? id,
    Value<String>? name,
    Value<String?>? nameAr,
    Value<String?>? selectionMode,
    Value<String?>? status,
  }) {
    return AddonGroupsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      nameAr: nameAr ?? this.nameAr,
      selectionMode: selectionMode ?? this.selectionMode,
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
    ingredientId,
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
    if (data.containsKey('ingredient_id')) {
      context.handle(
        _ingredientIdMeta,
        ingredientId.isAcceptableOrUnknown(
          data['ingredient_id']!,
          _ingredientIdMeta,
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
      ingredientId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}ingredient_id'],
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
  final int? ingredientId;
  final String? status;
  const AddonRow({
    required this.id,
    required this.addOnGroupId,
    required this.name,
    this.nameAr,
    required this.priceDeltaBaisas,
    this.ingredientId,
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
    if (!nullToAbsent || ingredientId != null) {
      map['ingredient_id'] = Variable<int>(ingredientId);
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
      ingredientId: ingredientId == null && nullToAbsent
          ? const Value.absent()
          : Value(ingredientId),
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
      ingredientId: serializer.fromJson<int?>(json['ingredientId']),
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
      'ingredientId': serializer.toJson<int?>(ingredientId),
      'status': serializer.toJson<String?>(status),
    };
  }

  AddonRow copyWith({
    int? id,
    int? addOnGroupId,
    String? name,
    Value<String?> nameAr = const Value.absent(),
    int? priceDeltaBaisas,
    Value<int?> ingredientId = const Value.absent(),
    Value<String?> status = const Value.absent(),
  }) => AddonRow(
    id: id ?? this.id,
    addOnGroupId: addOnGroupId ?? this.addOnGroupId,
    name: name ?? this.name,
    nameAr: nameAr.present ? nameAr.value : this.nameAr,
    priceDeltaBaisas: priceDeltaBaisas ?? this.priceDeltaBaisas,
    ingredientId: ingredientId.present ? ingredientId.value : this.ingredientId,
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
      ingredientId: data.ingredientId.present
          ? data.ingredientId.value
          : this.ingredientId,
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
          ..write('ingredientId: $ingredientId, ')
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
    ingredientId,
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
          other.ingredientId == this.ingredientId &&
          other.status == this.status);
}

class AddonsCompanion extends UpdateCompanion<AddonRow> {
  final Value<int> id;
  final Value<int> addOnGroupId;
  final Value<String> name;
  final Value<String?> nameAr;
  final Value<int> priceDeltaBaisas;
  final Value<int?> ingredientId;
  final Value<String?> status;
  const AddonsCompanion({
    this.id = const Value.absent(),
    this.addOnGroupId = const Value.absent(),
    this.name = const Value.absent(),
    this.nameAr = const Value.absent(),
    this.priceDeltaBaisas = const Value.absent(),
    this.ingredientId = const Value.absent(),
    this.status = const Value.absent(),
  });
  AddonsCompanion.insert({
    this.id = const Value.absent(),
    required int addOnGroupId,
    this.name = const Value.absent(),
    this.nameAr = const Value.absent(),
    this.priceDeltaBaisas = const Value.absent(),
    this.ingredientId = const Value.absent(),
    this.status = const Value.absent(),
  }) : addOnGroupId = Value(addOnGroupId);
  static Insertable<AddonRow> custom({
    Expression<int>? id,
    Expression<int>? addOnGroupId,
    Expression<String>? name,
    Expression<String>? nameAr,
    Expression<int>? priceDeltaBaisas,
    Expression<int>? ingredientId,
    Expression<String>? status,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (addOnGroupId != null) 'add_on_group_id': addOnGroupId,
      if (name != null) 'name': name,
      if (nameAr != null) 'name_ar': nameAr,
      if (priceDeltaBaisas != null) 'price_delta_baisas': priceDeltaBaisas,
      if (ingredientId != null) 'ingredient_id': ingredientId,
      if (status != null) 'status': status,
    });
  }

  AddonsCompanion copyWith({
    Value<int>? id,
    Value<int>? addOnGroupId,
    Value<String>? name,
    Value<String?>? nameAr,
    Value<int>? priceDeltaBaisas,
    Value<int?>? ingredientId,
    Value<String?>? status,
  }) {
    return AddonsCompanion(
      id: id ?? this.id,
      addOnGroupId: addOnGroupId ?? this.addOnGroupId,
      name: name ?? this.name,
      nameAr: nameAr ?? this.nameAr,
      priceDeltaBaisas: priceDeltaBaisas ?? this.priceDeltaBaisas,
      ingredientId: ingredientId ?? this.ingredientId,
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
    if (ingredientId.present) {
      map['ingredient_id'] = Variable<int>(ingredientId.value);
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
          ..write('ingredientId: $ingredientId, ')
          ..write('status: $status')
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
  @override
  List<GeneratedColumn> get $columns => [
    id,
    companyId,
    branchId,
    lastConfigSyncAt,
    configSchemaVersion,
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
  const SyncMetaRow({
    required this.id,
    this.companyId,
    this.branchId,
    this.lastConfigSyncAt,
    this.configSchemaVersion,
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
    };
  }

  SyncMetaRow copyWith({
    int? id,
    Value<int?> companyId = const Value.absent(),
    Value<int?> branchId = const Value.absent(),
    Value<DateTime?> lastConfigSyncAt = const Value.absent(),
    Value<String?> configSchemaVersion = const Value.absent(),
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
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncMetaRow(')
          ..write('id: $id, ')
          ..write('companyId: $companyId, ')
          ..write('branchId: $branchId, ')
          ..write('lastConfigSyncAt: $lastConfigSyncAt, ')
          ..write('configSchemaVersion: $configSchemaVersion')
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
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncMetaRow &&
          other.id == this.id &&
          other.companyId == this.companyId &&
          other.branchId == this.branchId &&
          other.lastConfigSyncAt == this.lastConfigSyncAt &&
          other.configSchemaVersion == this.configSchemaVersion);
}

class SyncMetaCompanion extends UpdateCompanion<SyncMetaRow> {
  final Value<int> id;
  final Value<int?> companyId;
  final Value<int?> branchId;
  final Value<DateTime?> lastConfigSyncAt;
  final Value<String?> configSchemaVersion;
  const SyncMetaCompanion({
    this.id = const Value.absent(),
    this.companyId = const Value.absent(),
    this.branchId = const Value.absent(),
    this.lastConfigSyncAt = const Value.absent(),
    this.configSchemaVersion = const Value.absent(),
  });
  SyncMetaCompanion.insert({
    this.id = const Value.absent(),
    this.companyId = const Value.absent(),
    this.branchId = const Value.absent(),
    this.lastConfigSyncAt = const Value.absent(),
    this.configSchemaVersion = const Value.absent(),
  });
  static Insertable<SyncMetaRow> custom({
    Expression<int>? id,
    Expression<int>? companyId,
    Expression<int>? branchId,
    Expression<DateTime>? lastConfigSyncAt,
    Expression<String>? configSchemaVersion,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (companyId != null) 'company_id': companyId,
      if (branchId != null) 'branch_id': branchId,
      if (lastConfigSyncAt != null) 'last_config_sync_at': lastConfigSyncAt,
      if (configSchemaVersion != null)
        'config_schema_version': configSchemaVersion,
    });
  }

  SyncMetaCompanion copyWith({
    Value<int>? id,
    Value<int?>? companyId,
    Value<int?>? branchId,
    Value<DateTime?>? lastConfigSyncAt,
    Value<String?>? configSchemaVersion,
  }) {
    return SyncMetaCompanion(
      id: id ?? this.id,
      companyId: companyId ?? this.companyId,
      branchId: branchId ?? this.branchId,
      lastConfigSyncAt: lastConfigSyncAt ?? this.lastConfigSyncAt,
      configSchemaVersion: configSchemaVersion ?? this.configSchemaVersion,
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
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncMetaCompanion(')
          ..write('id: $id, ')
          ..write('companyId: $companyId, ')
          ..write('branchId: $branchId, ')
          ..write('lastConfigSyncAt: $lastConfigSyncAt, ')
          ..write('configSchemaVersion: $configSchemaVersion')
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
  late final $SyncMetaTable syncMeta = $SyncMetaTable(this);
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
    syncMeta,
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
              }) => BranchCacheCompanion(
                id: id,
                name: name,
                nameAr: nameAr,
                latitude: latitude,
                longitude: longitude,
                geofenceRadiusM: geofenceRadiusM,
                defaultOrderType: defaultOrderType,
                status: status,
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
              }) => BranchCacheCompanion.insert(
                id: id,
                name: name,
                nameAr: nameAr,
                latitude: latitude,
                longitude: longitude,
                geofenceRadiusM: geofenceRadiusM,
                defaultOrderType: defaultOrderType,
                status: status,
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
    });
typedef $$CategoriesTableUpdateCompanionBuilder =
    CategoriesCompanion Function({
      Value<int> id,
      Value<String> name,
      Value<String?> nameAr,
      Value<int> displayOrder,
      Value<String?> status,
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
              }) => CategoriesCompanion(
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
              }) => CategoriesCompanion.insert(
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
              }) => ProductsCompanion(
                id: id,
                name: name,
                nameAr: nameAr,
                categoryId: categoryId,
                basePriceBaisas: basePriceBaisas,
                branchStockQty: branchStockQty,
                imageUrl: imageUrl,
                status: status,
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
              }) => ProductsCompanion.insert(
                id: id,
                name: name,
                nameAr: nameAr,
                categoryId: categoryId,
                basePriceBaisas: basePriceBaisas,
                branchStockQty: branchStockQty,
                imageUrl: imageUrl,
                status: status,
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
                Value<String?> shape = const Value.absent(),
                Value<int> displayOrder = const Value.absent(),
                Value<String?> status = const Value.absent(),
              }) => PosTablesCompanion(
                id: id,
                floorId: floorId,
                label: label,
                seats: seats,
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
                Value<String?> shape = const Value.absent(),
                Value<int> displayOrder = const Value.absent(),
                Value<String?> status = const Value.absent(),
              }) => PosTablesCompanion.insert(
                id: id,
                floorId: floorId,
                label: label,
                seats: seats,
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
      Value<String?> status,
    });
typedef $$AddonGroupsTableUpdateCompanionBuilder =
    AddonGroupsCompanion Function({
      Value<int> id,
      Value<String> name,
      Value<String?> nameAr,
      Value<String?> selectionMode,
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
                Value<String?> status = const Value.absent(),
              }) => AddonGroupsCompanion(
                id: id,
                name: name,
                nameAr: nameAr,
                selectionMode: selectionMode,
                status: status,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> nameAr = const Value.absent(),
                Value<String?> selectionMode = const Value.absent(),
                Value<String?> status = const Value.absent(),
              }) => AddonGroupsCompanion.insert(
                id: id,
                name: name,
                nameAr: nameAr,
                selectionMode: selectionMode,
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
      Value<int?> ingredientId,
      Value<String?> status,
    });
typedef $$AddonsTableUpdateCompanionBuilder =
    AddonsCompanion Function({
      Value<int> id,
      Value<int> addOnGroupId,
      Value<String> name,
      Value<String?> nameAr,
      Value<int> priceDeltaBaisas,
      Value<int?> ingredientId,
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

  ColumnFilters<int> get ingredientId => $composableBuilder(
    column: $table.ingredientId,
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

  ColumnOrderings<int> get ingredientId => $composableBuilder(
    column: $table.ingredientId,
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

  GeneratedColumn<int> get ingredientId => $composableBuilder(
    column: $table.ingredientId,
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
                Value<int?> ingredientId = const Value.absent(),
                Value<String?> status = const Value.absent(),
              }) => AddonsCompanion(
                id: id,
                addOnGroupId: addOnGroupId,
                name: name,
                nameAr: nameAr,
                priceDeltaBaisas: priceDeltaBaisas,
                ingredientId: ingredientId,
                status: status,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int addOnGroupId,
                Value<String> name = const Value.absent(),
                Value<String?> nameAr = const Value.absent(),
                Value<int> priceDeltaBaisas = const Value.absent(),
                Value<int?> ingredientId = const Value.absent(),
                Value<String?> status = const Value.absent(),
              }) => AddonsCompanion.insert(
                id: id,
                addOnGroupId: addOnGroupId,
                name: name,
                nameAr: nameAr,
                priceDeltaBaisas: priceDeltaBaisas,
                ingredientId: ingredientId,
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
typedef $$SyncMetaTableCreateCompanionBuilder =
    SyncMetaCompanion Function({
      Value<int> id,
      Value<int?> companyId,
      Value<int?> branchId,
      Value<DateTime?> lastConfigSyncAt,
      Value<String?> configSchemaVersion,
    });
typedef $$SyncMetaTableUpdateCompanionBuilder =
    SyncMetaCompanion Function({
      Value<int> id,
      Value<int?> companyId,
      Value<int?> branchId,
      Value<DateTime?> lastConfigSyncAt,
      Value<String?> configSchemaVersion,
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
              }) => SyncMetaCompanion(
                id: id,
                companyId: companyId,
                branchId: branchId,
                lastConfigSyncAt: lastConfigSyncAt,
                configSchemaVersion: configSchemaVersion,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int?> companyId = const Value.absent(),
                Value<int?> branchId = const Value.absent(),
                Value<DateTime?> lastConfigSyncAt = const Value.absent(),
                Value<String?> configSchemaVersion = const Value.absent(),
              }) => SyncMetaCompanion.insert(
                id: id,
                companyId: companyId,
                branchId: branchId,
                lastConfigSyncAt: lastConfigSyncAt,
                configSchemaVersion: configSchemaVersion,
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
  $$SyncMetaTableTableManager get syncMeta =>
      $$SyncMetaTableTableManager(_db, _db.syncMeta);
}
