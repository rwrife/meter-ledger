import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:meterledger/data/meter_store.dart';
import 'package:meterledger/domain/meter_domain.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  final factory = databaseFactoryFfi;
  test('versioned backup round-trips two meters and corrections', () async {
    final source = await MeterStore.open(
      inMemoryDatabasePath,
      factory: factory,
    );
    final target = await MeterStore.open(
      inMemoryDatabasePath,
      factory: factory,
    );
    try {
      await source.addProperty(Property(id: 'p', name: '=Home,"Main"'));
      for (final id in ['water', 'garden']) {
        await source.addMeter(
          Meter(
            id: id,
            propertyId: 'p',
            kind: MeterKind.water,
            unit: MeterUnit.cubicMetres,
          ),
        );
      }
      for (final (id, meter, value, targetId, reason) in [
        ('r1', 'water', 1.0, null, null),
        ('r2', 'water', 2.0, 'r1', 'corrected'),
        ('r3', 'garden', 3.0, null, null),
      ]) {
        await source.addReading(
          MeterReading(
            id: id,
            meterId: meter,
            seriesId: 'series-$meter',
            date: DateTime.utc(2026, 1, 1),
            value: value,
            unit: MeterUnit.cubicMetres,
            supersedesId: targetId,
            correctionReason: reason,
          ),
        );
      }
      await source.addBill(
        'bill',
        UtilityBill(
          meterId: 'water',
          start: DateTime.utc(2026, 1, 1),
          end: DateTime.utc(2026, 2, 1),
          quantity: 2,
          unit: MeterUnit.cubicMetres,
          amount: 12,
          currency: 'USD',
        ),
      );
      final backup = await source.exportJson();
      await target.addProperty(Property(id: 'old', name: 'Old'));
      await target.restoreJson(backup);
      expect(jsonDecode(await target.exportJson()), jsonDecode(backup));
      expect((await target.readings('water')).last.supersedesId, 'r1');
      expect((await target.bills('water')).single.amount, 12);
      expect(await target.readingsCsv(), contains("\"'=Home,\"\"Main\"\"\""));
      expect(await target.readingsCsv(), contains('cubicMetres'));
      for (final mutation in <String Function(Map<String, dynamic>)>[
        (d) {
          d['version'] = 2;
          return jsonEncode(d);
        },
        (d) {
          d['meters'].add(Map.of(d['meters'][0]));
          return jsonEncode(d);
        },
        (d) {
          d['readings'][0]['meter_id'] = 'missing';
          return jsonEncode(d);
        },
        (d) {
          d['readings'][0]['value'] = -1;
          return jsonEncode(d);
        },
        (d) {
          d['bills'][0]['end_date'] = 'invalid';
          return jsonEncode(d);
        },
        (d) {
          d['properties'][0]['name'] = null;
          return jsonEncode(d);
        },
      ]) {
        await expectLater(
          target.restoreJson(mutation(jsonDecode(backup))),
          throwsA(anything),
        );
        expect(jsonDecode(await target.exportJson()), jsonDecode(backup));
      }
      await expectLater(target.restoreJson('{broken'), throwsFormatException);
      await expectLater(
        target.restoreJson('x' * (10 * 1024 * 1024 + 1)),
        throwsFormatException,
      );
      expect(jsonDecode(await target.exportJson()), jsonDecode(backup));
    } finally {
      await source.close();
      await target.close();
    }
  });
}
