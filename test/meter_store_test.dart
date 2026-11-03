import 'package:flutter_test/flutter_test.dart';
import 'package:meterledger/domain/meter_domain.dart';
import 'package:meterledger/data/meter_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  final factory = databaseFactoryFfi;
  final date = DateTime.utc(2026, 1, 1);
  final next = DateTime.utc(2026, 2, 1);
  final meter = Meter(
    id: 'm',
    propertyId: 'p',
    kind: MeterKind.water,
    unit: MeterUnit.cubicMetres,
  );

  test('round-trip survives reopen, preserves correction chain and bills', () async {
    final path =
        '${await factory.getDatabasesPath()}/meter-roundtrip-${DateTime.now().microsecondsSinceEpoch}.db';
    final store = await MeterStore.open(path, factory: factory);
    await store.addProperty(Property(id: 'p', name: 'Home'));
    await store.addMeter(meter);
    await store.addReading(
      MeterReading(
        id: 'r1',
        meterId: 'm',
        seriesId: 's',
        date: date,
        value: 10,
        unit: MeterUnit.cubicMetres,
      ),
    );
    await store.addReading(
      MeterReading(
        id: 'r2',
        meterId: 'm',
        seriesId: 's',
        date: next,
        value: 20,
        unit: MeterUnit.cubicMetres,
      ),
    );
    await store.addReading(
      MeterReading(
        id: 'fix',
        meterId: 'm',
        seriesId: 's',
        date: next,
        value: 22,
        unit: MeterUnit.cubicMetres,
        supersedesId: 'r2',
        correctionReason: 'Transcription error',
      ),
    );
    await store.addBill(
      'b',
      UtilityBill(
        meterId: 'm',
        start: date,
        end: next,
        quantity: 11,
        unit: MeterUnit.cubicMetres,
        amount: 45,
        currency: 'USD',
      ),
    );
    await store.close();
    final reopened = await MeterStore.open(path, factory: factory);
    expect((await reopened.properties()).single.name, 'Home');
    expect((await reopened.meters()).single.propertyId, 'p');
    final journal = MeterJournal(
      meter: meter,
      readings: await reopened.readings('m'),
    );
    expect(journal.readings.map((r) => r.id), ['r1', 'r2', 'fix']);
    expect(journal.readings.last.correctionReason, 'Transcription error');
    expect(journal.interval(date, next).quantity, 12);
    expect(
      journal.reconcile((await reopened.bills('m')).single).quantityDifference,
      -1,
    );
    expect((await reopened.bills('m')).single.amount, 45);
    await reopened.close();
    await factory.deleteDatabase(path);
  });

  test(
    'invalid correction and duplicate bill leave prior rows intact',
    () async {
      final store = await MeterStore.open(
        inMemoryDatabasePath,
        factory: factory,
      );
      await store.addProperty(Property(id: 'p', name: 'Home'));
      await store.addMeter(meter);
      await store.addReading(
        MeterReading(
          id: 'r1',
          meterId: 'm',
          seriesId: 's',
          date: date,
          value: 10,
          unit: MeterUnit.cubicMetres,
        ),
      );
      await expectLater(
        store.addReading(
          MeterReading(
            id: 'bad',
            meterId: 'm',
            seriesId: 's',
            date: next,
            value: 2,
            unit: MeterUnit.cubicMetres,
          ),
        ),
        throwsArgumentError,
      );
      expect((await store.readings('m')).map((r) => r.id), ['r1']);
      final bill = UtilityBill(
        meterId: 'm',
        start: date,
        end: next,
        quantity: 4,
        unit: MeterUnit.cubicMetres,
      );
      await store.addBill('b', bill);
      await expectLater(store.addBill('b', bill), throwsException);
      expect((await store.bills('m')).length, 1);
      await store.close();
    },
  );

  test('v1 migration preserves readings and adds correction fields', () async {
    final path =
        '${await factory.getDatabasesPath()}/meter-v1-${DateTime.now().microsecondsSinceEpoch}.db';
    final old = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          await db.execute(
            'CREATE TABLE properties (id TEXT PRIMARY KEY, name TEXT NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE meters (id TEXT PRIMARY KEY, property_id TEXT NOT NULL REFERENCES properties(id), kind TEXT NOT NULL, unit TEXT NOT NULL, rollover_modulus REAL)',
          );
          await db.execute(
            'CREATE TABLE readings (id TEXT PRIMARY KEY, meter_id TEXT NOT NULL REFERENCES meters(id), series_id TEXT NOT NULL, date TEXT NOT NULL, value REAL NOT NULL, unit TEXT NOT NULL, rollover INTEGER NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE bills (id TEXT PRIMARY KEY, meter_id TEXT NOT NULL REFERENCES meters(id), start_date TEXT NOT NULL, end_date TEXT NOT NULL, quantity REAL NOT NULL, unit TEXT NOT NULL, amount REAL, currency TEXT)',
          );
        },
      ),
    );
    await old.insert('properties', {'id': 'p', 'name': 'Existing'});
    await old.insert('meters', {
      'id': 'm',
      'property_id': 'p',
      'kind': 'water',
      'unit': 'cubicMetres',
    });
    await old.insert('readings', {
      'id': 'r1',
      'meter_id': 'm',
      'series_id': 's',
      'date': date.toIso8601String(),
      'value': 10,
      'unit': 'cubicMetres',
      'rollover': 0,
    });
    await old.close();
    final upgraded = await MeterStore.open(path, factory: factory);
    expect((await upgraded.readings('m')).single.value, 10);
    await upgraded.addReading(
      MeterReading(
        id: 'fix',
        meterId: 'm',
        seriesId: 's',
        date: date,
        value: 11,
        unit: MeterUnit.cubicMetres,
        supersedesId: 'r1',
        correctionReason: 'Old reading wrong',
      ),
    );
    expect((await upgraded.readings('m')).last.supersedesId, 'r1');
    await upgraded.close();
    await factory.deleteDatabase(path);
  });
}
