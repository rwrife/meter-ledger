import 'package:flutter_test/flutter_test.dart';
import 'package:meterledger/domain/meter_domain.dart';

final meter = Meter(
  id: 'm',
  propertyId: 'p',
  kind: MeterKind.water,
  unit: MeterUnit.cubicMetres,
);
DateTime day(int n) => DateTime.utc(2026, 1, n);
MeterReading reading(
  int n,
  double value, {
  String? id,
  String series = 'original',
  MeterUnit unit = MeterUnit.cubicMetres,
  bool rollover = false,
  String? supersedes,
  String? reason,
}) => MeterReading(
  id: id ?? '$n',
  meterId: 'm',
  seriesId: series,
  date: day(n),
  value: value,
  unit: unit,
  rolloverFromPrevious: rollover,
  supersedesId: supersedes,
  correctionReason: reason,
);
UtilityBill bill({
  MeterUnit unit = MeterUnit.cubicMetres,
  double quantity = 12,
  double? amount,
  String? currency,
}) => UtilityBill(
  meterId: 'm',
  start: day(1),
  end: day(3),
  quantity: quantity,
  unit: unit,
  amount: amount,
  currency: currency,
);
MeterJournal journal(List<MeterReading> entries, {Meter? forMeter}) =>
    MeterJournal(meter: forMeter ?? meter, readings: entries);

void main() {
  test(
    'exact boundaries, intervening dates, bill difference and stored amount',
    () {
      final history = journal([reading(3, 23), reading(1, 10), reading(2, 17)]);
      expect(history.interval(day(1), day(3)).quantity, 13);
      final comparison = history.reconcile(
        bill(amount: 48.20, currency: 'USD'),
      );
      expect(comparison.usage.quantity, 13);
      expect(comparison.quantityDifference, -1);
      expect(bill(amount: 48.20, currency: 'USD').amount, 48.20);
      expect(bill(amount: 48.20, currency: 'USD').currency, 'USD');
      expect(history.interval(day(2), day(3)).quantity, 6);
    },
  );

  test('missing exact boundary is unknown, not extrapolated or zero', () {
    final history = journal([reading(1, 10), reading(2, 15)]);
    expect(
      history.interval(day(1), day(3)).unknownReason,
      UnknownReason.missingBoundary,
    );
    expect(history.reconcile(bill()).quantityDifference, isNull);
    expect(history.interval(day(1), day(2)).quantity, 5);
  });

  test('duplicate date and duplicate ID rejected, even across series', () {
    expect(
      () => journal([reading(1, 10), reading(1, 11, id: 'other')]),
      throwsArgumentError,
    );
    expect(
      () => journal([reading(1, 10), reading(2, 11, id: '1')]),
      throwsArgumentError,
    );
  });

  test('decrease needs known explicit rollover; replacement is unknown', () {
    expect(() => journal([reading(1, 98), reading(3, 2)]), throwsArgumentError);
    expect(
      () => journal([reading(1, 98), reading(3, 2, rollover: true)]),
      throwsArgumentError,
    );
    final known = Meter(
      id: 'm',
      propertyId: 'p',
      kind: MeterKind.water,
      unit: MeterUnit.cubicMetres,
      rolloverModulus: 100,
    );
    final rolled = journal([
      reading(1, 98),
      reading(2, 2, rollover: true),
      reading(3, 5),
    ], forMeter: known);
    expect(rolled.interval(day(1), day(3)).quantity, 7);
    expect(
      () => journal([reading(1, 100)], forMeter: known),
      throwsArgumentError,
    );
    expect(
      () => journal([
        reading(1, 98),
        reading(3, 99, rollover: true),
      ], forMeter: known),
      throwsArgumentError,
    );
    final replaced = journal([
      reading(1, 98),
      reading(3, 2, series: 'replacement'),
    ]);
    expect(
      replaced.interval(day(1), day(3)).unknownReason,
      UnknownReason.meterReplaced,
    );
    expect(replaced.reconcile(bill()).quantityDifference, isNull);
  });

  test('corrections retain original and replace its value with reason', () {
    final history = journal([
      reading(1, 10),
      reading(3, 20),
      reading(3, 25, id: 'fix', supersedes: '3', reason: 'Misread dial'),
    ]);
    expect(history.readings.length, 3);
    expect(history.readings[1].value, 20);
    expect(history.interval(day(1), day(3)).quantity, 15);
    expect(
      () => journal([
        reading(1, 10),
        reading(3, 20),
        reading(3, 25, id: 'fix', supersedes: 'missing', reason: 'Typo'),
      ]),
      throwsArgumentError,
    );
    expect(
      () => journal([
        reading(1, 10),
        reading(3, 20),
        reading(3, 25, id: 'fix', supersedes: '3', reason: 'Typo'),
        reading(3, 26, id: 'fork', supersedes: '3', reason: 'Other'),
      ]),
      throwsArgumentError,
    );
    expect(() => reading(3, 25, supersedes: '3'), throwsArgumentError);
  });

  test('unit and meter mismatches cannot produce misleading usage', () {
    expect(
      () => journal([reading(1, 10, unit: MeterUnit.usGallons)]),
      throwsArgumentError,
    );
    final history = journal([reading(1, 10), reading(3, 20)]);
    final comparison = history.reconcile(bill(unit: MeterUnit.usGallons));
    expect(comparison.usage.unknownReason, UnknownReason.unitMismatch);
    expect(comparison.quantityDifference, isNull);
    expect(
      () => history.reconcile(
        UtilityBill(
          meterId: 'other',
          start: day(1),
          end: day(3),
          quantity: 3,
          unit: MeterUnit.cubicMetres,
        ),
      ),
      throwsArgumentError,
    );
  });

  test('reject invalid dates, values, bill bounds, and malformed amount', () {
    expect(() => reading(1, double.nan), throwsArgumentError);
    expect(() => reading(1, -1), throwsArgumentError);
    expect(
      () => Meter(
        id: 'm',
        propertyId: 'p',
        kind: MeterKind.gas,
        unit: MeterUnit.therms,
        rolloverModulus: 0,
      ),
      throwsArgumentError,
    );
    expect(
      () => MeterReading(
        id: 'bad',
        meterId: 'm',
        seriesId: 'a',
        date: DateTime(2026, 1, 1),
        value: 1,
        unit: MeterUnit.cubicMetres,
      ),
      throwsArgumentError,
    );
    expect(
      () => UtilityBill(
        meterId: 'm',
        start: day(3),
        end: day(1),
        quantity: 1,
        unit: MeterUnit.cubicMetres,
      ),
      throwsArgumentError,
    );
    expect(() => bill(amount: 2), throwsArgumentError);
    expect(() => bill(quantity: double.infinity), throwsArgumentError);
  });
}
