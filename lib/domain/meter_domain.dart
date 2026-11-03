/// Pure, date-granular meter math. Dates are UTC midnight; quantities are in
/// the meter's displayed unit. No interpolation or tariff calculation.
library;

enum MeterKind { electricity, gas, water }

enum MeterUnit { kilowattHours, cubicMetres, usGallons, therms }

enum UnknownReason { missingBoundary, meterReplaced, unitMismatch }

void _requireDate(DateTime date) {
  if (!date.isUtc || date != DateTime.utc(date.year, date.month, date.day)) {
    throw ArgumentError.value(date, 'date', 'Use a UTC calendar date');
  }
}

void _requireQuantity(double value, String name) {
  if (!value.isFinite || value < 0) {
    throw ArgumentError.value(value, name, 'Must be finite and nonnegative');
  }
}

void _requireText(String value, String name) {
  if (value.trim().isEmpty) throw ArgumentError.value(value, name);
}

class Property {
  Property({required this.id, required this.name}) {
    _requireText(id, 'id');
    _requireText(name, 'name');
  }

  final String id;
  final String name;
}

class Meter {
  Meter({
    required this.id,
    required this.propertyId,
    required this.kind,
    required this.unit,
    this.rolloverModulus,
  }) {
    _requireText(id, 'id');
    _requireText(propertyId, 'propertyId');
    if (rolloverModulus != null &&
        (!rolloverModulus!.isFinite || rolloverModulus! <= 0)) {
      throw ArgumentError.value(rolloverModulus, 'rolloverModulus');
    }
  }

  final String id;
  final String propertyId;
  final MeterKind kind;
  final MeterUnit unit;

  /// Display wraps from modulus back to zero; only use when documented.
  final double? rolloverModulus;
}

class MeterReading {
  MeterReading({
    required this.id,
    required this.meterId,
    required this.seriesId,
    required this.date,
    required this.value,
    required this.unit,
    this.rolloverFromPrevious = false,
    this.supersedesId,
    this.correctionReason,
  }) {
    _requireText(id, 'id');
    _requireText(meterId, 'meterId');
    _requireText(seriesId, 'seriesId');
    _requireDate(date);
    _requireQuantity(value, 'value');
    if (supersedesId == null && correctionReason != null ||
        supersedesId != null &&
            (correctionReason == null || correctionReason!.trim().isEmpty)) {
      throw ArgumentError('Corrections require a target and a reason');
    }
  }

  final String id;
  final String meterId;

  /// Replacement starts a new series; usage never crosses series boundaries.
  final String seriesId;
  final DateTime date;
  final double value;
  final MeterUnit unit;

  /// Explicitly documented rollover since previous reading in this series.
  final bool rolloverFromPrevious;

  /// Original entry stays in journal; correction supersedes it by ID.
  final String? supersedesId;
  final String? correctionReason;
}

class UtilityBill {
  UtilityBill({
    required this.meterId,
    required this.start,
    required this.end,
    required this.quantity,
    required this.unit,
    this.amount,
    this.currency,
  }) {
    _requireText(meterId, 'meterId');
    _requireDate(start);
    _requireDate(end);
    if (!start.isBefore(end)) throw ArgumentError('Bill end must follow start');
    _requireQuantity(quantity, 'quantity');
    if (amount != null) _requireQuantity(amount!, 'amount');
    if ((amount == null) != (currency == null)) {
      throw ArgumentError('Amount and currency must be supplied together');
    }
    if (currency != null) _requireText(currency!, 'currency');
  }

  final String meterId;
  final DateTime start;
  final DateTime end;
  final double quantity;
  final MeterUnit unit;

  /// Recorded for display only; fees, taxes, and tariffs are never inferred.
  final double? amount;
  final String? currency;
}

class IntervalUsage {
  const IntervalUsage.known(this.quantity) : unknownReason = null;
  const IntervalUsage.unknown(this.unknownReason) : quantity = null;

  final double? quantity;
  final UnknownReason? unknownReason;
  bool get isKnown => quantity != null;
}

class BillComparison {
  const BillComparison(this.usage, this.quantityDifference);

  final IntervalUsage usage;

  /// Billed quantity minus recorded usage; null if comparison is unknown.
  final double? quantityDifference;
}

/// Validates the complete append-only journal, then computes exact-date usage.
class MeterJournal {
  MeterJournal({required this.meter, required List<MeterReading> readings})
    : readings = List.unmodifiable(readings) {
    final byId = <String, MeterReading>{};
    final superseded = <String>{};
    for (final reading in this.readings) {
      if (reading.meterId != meter.id || reading.unit != meter.unit) {
        throw ArgumentError('Reading meter or displayed unit mismatch');
      }
      if (meter.rolloverModulus case final modulus?) {
        if (reading.value >= modulus) {
          throw ArgumentError('Reading outside documented display modulus');
        }
      }
      if (byId.containsKey(reading.id)) {
        throw ArgumentError('Duplicate reading ID');
      }
      if (reading.supersedesId case final targetId?) {
        final target = byId[targetId];
        if (target == null ||
            target.date != reading.date ||
            target.seriesId != reading.seriesId ||
            !superseded.add(targetId)) {
          throw ArgumentError('Invalid or forked correction');
        }
      }
      byId[reading.id] = reading;
    }
    _active = List.unmodifiable(
      this.readings
          .where((reading) => !superseded.contains(reading.id))
          .toList()
        ..sort((a, b) => a.date.compareTo(b.date)),
    );
    final seenDates = <DateTime>{};
    final finishedSeries = <String>{};
    String? currentSeries;
    MeterReading? previous;
    for (final reading in _active) {
      if (!seenDates.add(reading.date)) {
        throw ArgumentError('Duplicate reading date');
      }
      if (currentSeries != reading.seriesId) {
        if (currentSeries != null) finishedSeries.add(currentSeries);
        if (finishedSeries.contains(reading.seriesId)) {
          throw ArgumentError('Replacement series cannot resume');
        }
        if (reading.rolloverFromPrevious) {
          throw ArgumentError('First reading of series cannot roll over');
        }
        currentSeries = reading.seriesId;
      } else {
        _delta(previous!, reading);
      }
      previous = reading;
    }
  }

  final Meter meter;

  /// Includes superseded entries for immutable correction history.
  final List<MeterReading> readings;
  late final List<MeterReading> _active;

  double _delta(MeterReading from, MeterReading to) {
    if (to.rolloverFromPrevious) {
      final modulus = meter.rolloverModulus;
      if (modulus == null || to.value >= from.value) {
        throw ArgumentError(
          'Rollover needs known modulus and decreasing display',
        );
      }
      return modulus - from.value + to.value;
    }
    if (to.value < from.value) {
      throw ArgumentError(
        'Decreasing reading needs documented rollover or replacement',
      );
    }
    return to.value - from.value;
  }

  IntervalUsage interval(DateTime start, DateTime end) {
    _requireDate(start);
    _requireDate(end);
    if (!start.isBefore(end)) throw ArgumentError('End must follow start');
    final first = _active.where((r) => r.date == start).firstOrNull;
    final last = _active.where((r) => r.date == end).firstOrNull;
    if (first == null || last == null) {
      return const IntervalUsage.unknown(UnknownReason.missingBoundary);
    }
    if (first.seriesId != last.seriesId) {
      return const IntervalUsage.unknown(UnknownReason.meterReplaced);
    }
    final inside = _active
        .where((r) => !r.date.isBefore(start) && !r.date.isAfter(end))
        .toList();
    var quantity = 0.0;
    for (var i = 1; i < inside.length; i++) {
      if (inside[i].seriesId != first.seriesId) {
        return const IntervalUsage.unknown(UnknownReason.meterReplaced);
      }
      quantity += _delta(inside[i - 1], inside[i]);
    }
    return IntervalUsage.known(quantity);
  }

  BillComparison reconcile(UtilityBill bill) {
    if (bill.meterId != meter.id) throw ArgumentError('Bill meter mismatch');
    if (bill.unit != meter.unit) {
      return const BillComparison(
        IntervalUsage.unknown(UnknownReason.unitMismatch),
        null,
      );
    }
    final usage = interval(bill.start, bill.end);
    return BillComparison(
      usage,
      usage.quantity == null ? null : bill.quantity - usage.quantity!,
    );
  }
}
