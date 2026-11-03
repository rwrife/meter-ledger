import 'dart:io';

import 'package:meterledger/domain/meter_domain.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Private SQLite journal. Corrections append; existing readings are never overwritten.
class MeterStore {
  MeterStore._(this._db);

  final Database _db;

  static Future<MeterStore> open(
    String path, {
    DatabaseFactory? factory,
  }) async {
    if (factory == null && (Platform.isWindows || Platform.isLinux)) {
      sqfliteFfiInit();
      factory = databaseFactoryFfi;
    }
    final db = await (factory ?? databaseFactory).openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 2,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, version) async {
          await db.execute(
            'CREATE TABLE properties (id TEXT PRIMARY KEY, name TEXT NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE meters (id TEXT PRIMARY KEY, property_id TEXT NOT NULL REFERENCES properties(id), kind TEXT NOT NULL, unit TEXT NOT NULL, rollover_modulus REAL)',
          );
          await db.execute(
            'CREATE TABLE readings (id TEXT PRIMARY KEY, meter_id TEXT NOT NULL REFERENCES meters(id), series_id TEXT NOT NULL, date TEXT NOT NULL, value REAL NOT NULL, unit TEXT NOT NULL, rollover INTEGER NOT NULL, supersedes_id TEXT REFERENCES readings(id), correction_reason TEXT)',
          );
          await db.execute(
            'CREATE TABLE bills (id TEXT PRIMARY KEY, meter_id TEXT NOT NULL REFERENCES meters(id), start_date TEXT NOT NULL, end_date TEXT NOT NULL, quantity REAL NOT NULL, unit TEXT NOT NULL, amount REAL, currency TEXT)',
          );
        },
        onUpgrade: (db, from, to) async {
          if (from < 2) {
            await db.execute(
              'ALTER TABLE readings ADD COLUMN supersedes_id TEXT REFERENCES readings(id)',
            );
            await db.execute(
              'ALTER TABLE readings ADD COLUMN correction_reason TEXT',
            );
          }
        },
      ),
    );
    return MeterStore._(db);
  }

  Future<void> close() => _db.close();

  Future<void> addProperty(Property property) async {
    await _db.insert('properties', {'id': property.id, 'name': property.name});
  }

  Future<List<Property>> properties() async => [
    for (final row in await _db.query('properties', orderBy: 'rowid'))
      Property(id: row['id'] as String, name: row['name'] as String),
  ];

  Future<void> addMeter(Meter meter) async {
    await _db.insert('meters', {
      'id': meter.id,
      'property_id': meter.propertyId,
      'kind': meter.kind.name,
      'unit': meter.unit.name,
      'rollover_modulus': meter.rolloverModulus,
    });
  }

  Future<List<Meter>> meters() async => [
    for (final row in await _db.query('meters', orderBy: 'rowid'))
      Meter(
        id: row['id'] as String,
        propertyId: row['property_id'] as String,
        kind: MeterKind.values.byName(row['kind'] as String),
        unit: MeterUnit.values.byName(row['unit'] as String),
        rolloverModulus: (row['rollover_modulus'] as num?)?.toDouble(),
      ),
  ];

  Future<List<MeterReading>> readings(String meterId) =>
      _readings(_db, meterId);

  Future<List<MeterReading>> _readings(
    DatabaseExecutor executor,
    String meterId,
  ) async => [
    for (final row in await executor.query(
      'readings',
      where: 'meter_id = ?',
      whereArgs: [meterId],
      orderBy: 'rowid',
    ))
      MeterReading(
        id: row['id'] as String,
        meterId: row['meter_id'] as String,
        seriesId: row['series_id'] as String,
        date: DateTime.parse(row['date'] as String),
        value: (row['value'] as num).toDouble(),
        unit: MeterUnit.values.byName(row['unit'] as String),
        rolloverFromPrevious: row['rollover'] == 1,
        supersedesId: row['supersedes_id'] as String?,
        correctionReason: row['correction_reason'] as String?,
      ),
  ];

  Future<void> addReading(MeterReading reading) async {
    await _db.transaction((tx) async {
      final rows = await tx.query(
        'meters',
        where: 'id = ?',
        whereArgs: [reading.meterId],
      );
      if (rows.isEmpty) throw ArgumentError('Unknown meter');
      final row = rows.single;
      final meter = Meter(
        id: row['id'] as String,
        propertyId: row['property_id'] as String,
        kind: MeterKind.values.byName(row['kind'] as String),
        unit: MeterUnit.values.byName(row['unit'] as String),
        rolloverModulus: (row['rollover_modulus'] as num?)?.toDouble(),
      );
      await tx.insert('readings', {
        'id': reading.id,
        'meter_id': reading.meterId,
        'series_id': reading.seriesId,
        'date': reading.date.toIso8601String(),
        'value': reading.value,
        'unit': reading.unit.name,
        'rollover': reading.rolloverFromPrevious ? 1 : 0,
        'supersedes_id': reading.supersedesId,
        'correction_reason': reading.correctionReason,
      });
      // ponytail: validate whole journal per insert; index/snapshot only if volume demands it.
      MeterJournal(
        meter: meter,
        readings: await _readings(tx, reading.meterId),
      );
    });
  }

  Future<void> addBill(String id, UtilityBill bill) async {
    if (id.trim().isEmpty) throw ArgumentError.value(id, 'id');
    await _db.insert('bills', {
      'id': id,
      'meter_id': bill.meterId,
      'start_date': bill.start.toIso8601String(),
      'end_date': bill.end.toIso8601String(),
      'quantity': bill.quantity,
      'unit': bill.unit.name,
      'amount': bill.amount,
      'currency': bill.currency,
    });
  }

  Future<List<UtilityBill>> bills(String meterId) async => [
    for (final row in await _db.query(
      'bills',
      where: 'meter_id = ?',
      whereArgs: [meterId],
      orderBy: 'rowid',
    ))
      UtilityBill(
        meterId: row['meter_id'] as String,
        start: DateTime.parse(row['start_date'] as String),
        end: DateTime.parse(row['end_date'] as String),
        quantity: (row['quantity'] as num).toDouble(),
        unit: MeterUnit.values.byName(row['unit'] as String),
        amount: (row['amount'] as num?)?.toDouble(),
        currency: row['currency'] as String?,
      ),
  ];
}
