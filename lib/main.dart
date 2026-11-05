import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'data/meter_store.dart';
import 'domain/meter_domain.dart';

Future<MeterStore> openLocalJournal() async {
  final dir = await getApplicationSupportDirectory();
  await dir.create(recursive: true);
  return MeterStore.open(
    '${dir.path}${Platform.pathSeparator}meter-ledger.sqlite',
  );
}

void main() => runApp(const MeterLedgerApp());

class MeterLedgerApp extends StatefulWidget {
  const MeterLedgerApp({super.key, this.openStore});
  final Future<MeterStore> Function()? openStore;

  @override
  State<MeterLedgerApp> createState() => _AppState();
}

class _AppState extends State<MeterLedgerApp> {
  late final Future<MeterStore> storeFuture =
      (widget.openStore ?? openLocalJournal)();

  @override
  void dispose() {
    storeFuture.then((value) => value.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final body = FutureBuilder<MeterStore>(
      future: storeFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Storage unavailable: ${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: Text('Opening local journal…'));
        }
        return MeterWorkspaceLayout(store: snapshot.data!);
      },
    );
    return switch (defaultTargetPlatform) {
      TargetPlatform.iOS => CupertinoApp(
        title: 'Meter Ledger',
        home: CupertinoPageScaffold(
          navigationBar: const CupertinoNavigationBar(
            middle: Text('Meter Ledger'),
          ),
          child: SafeArea(child: body),
        ),
      ),
      TargetPlatform.windows => WidgetsApp(
        color: const Color(0xff17364a),
        pageRouteBuilder: <T>(settings, builder) => PageRouteBuilder<T>(
          settings: settings,
          pageBuilder: (context, animation, secondaryAnimation) =>
              builder(context),
        ),
        home: Directionality(
          textDirection: TextDirection.ltr,
          child: DefaultTextStyle(
            style: const TextStyle(color: Color(0xff17364a), fontSize: 16),
            child: body,
          ),
        ),
      ),
      _ => MaterialApp(
        title: 'Meter Ledger',
        theme: ThemeData(useMaterial3: true),
        home: Scaffold(
          appBar: AppBar(title: const Text('Meter Ledger')),
          body: body,
        ),
      ),
    };
  }
}

/// Shared workflow; controls retain native look on iOS/Android, desktop chrome on Windows.
class MeterWorkspaceLayout extends StatefulWidget {
  const MeterWorkspaceLayout({super.key, required this.store});
  final MeterStore store;

  @override
  State<MeterWorkspaceLayout> createState() => _WorkspaceState();
}

class _WorkspaceState extends State<MeterWorkspaceLayout> {
  late Future<
    ({
      List<Property> properties,
      List<Meter> meters,
      List<MeterReading> readings,
      List<UtilityBill> bills,
    })
  >
  data = _load();
  String? selectedId;
  String? propertyId;
  String? error;
  String? notice;
  int sequence = 0;
  MeterKind kind = MeterKind.electricity;
  MeterUnit unit = MeterUnit.kilowattHours;
  bool replacement = false;
  bool rollover = false;
  MeterReading? correcting;
  final fields = <String, TextEditingController>{};
  final focusNodes = <String, FocusNode>{};
  FocusNode focus(String key) => focusNodes.putIfAbsent(key, FocusNode.new);
  // ponytail: native pickers, plot and full adaptive layout belong to issue #5.
  TextEditingController field(String key) =>
      fields.putIfAbsent(key, TextEditingController.new);
  String text(String key) => field(key).text.trim();
  String id() => '${DateTime.now().microsecondsSinceEpoch}-${sequence++}';

  Future<
    ({
      List<Property> properties,
      List<Meter> meters,
      List<MeterReading> readings,
      List<UtilityBill> bills,
    })
  >
  _load() async {
    return (
      properties: await widget.store.properties(),
      meters: await widget.store.meters(),
      readings: selectedId == null
          ? <MeterReading>[]
          : await widget.store.readings(selectedId!),
      bills: selectedId == null
          ? <UtilityBill>[]
          : await widget.store.bills(selectedId!),
    );
  }

  void reload() => setState(() => data = _load());

  Future<void> save(Future<void> Function() operation, String message) async {
    try {
      await operation();
      if (!mounted) return;
      setState(() {
        error = null;
        notice = message;
      });
      reload();
    } catch (failure) {
      if (!mounted) return;
      setState(() {
        notice = null;
        error = 'Not saved: $failure';
      });
    }
  }

  DateTime date(String key) {
    final input = text(key);
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(input)) {
      throw const FormatException('Use YYYY-MM-DD');
    }
    final parsed = DateTime.utc(
      int.parse(input.substring(0, 4)),
      int.parse(input.substring(5, 7)),
      int.parse(input.substring(8)),
    );
    if (parsed.toIso8601String().substring(0, 10) != input) {
      throw const FormatException('Invalid calendar date');
    }
    return parsed;
  }

  double number(String key) {
    final value = double.parse(text(key));
    if (!value.isFinite || value < 0) {
      throw const FormatException('Use a finite nonnegative number');
    }
    return value;
  }

  @override
  void dispose() {
    for (final controller in fields.values) {
      controller.dispose();
    }
    for (final node in focusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      FutureBuilder<
        ({
          List<Property> properties,
          List<Meter> meters,
          List<MeterReading> readings,
          List<UtilityBill> bills,
        })
      >(
        future: data,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text('Journal unavailable: ${snapshot.error}'),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: Text('Loading journal…'));
          }
          final state = snapshot.data!;
          final meter = state.meters
              .where((entry) => entry.id == selectedId)
              .firstOrNull;
          MeterJournal? journal;
          try {
            if (meter != null) {
              journal = MeterJournal(meter: meter, readings: state.readings);
            }
          } catch (failure) {
            return Center(child: Text('Journal invalid: $failure'));
          }
          final active =
              state.readings
                  .where(
                    (reading) => !state.readings.any(
                      (later) => later.supersedesId == reading.id,
                    ),
                  )
                  .toList()
                ..sort((a, b) => a.date.compareTo(b.date));
          return SingleChildScrollView(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 960),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (defaultTargetPlatform == TargetPlatform.windows)
                        heading('Meter Ledger'),
                      const Text(
                        'Offline manual journal • exact boundary readings only',
                      ),
                      if (error != null)
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            error!,
                            style: const TextStyle(color: Color(0xffac2424)),
                          ),
                        ),
                      if (notice != null)
                        Semantics(liveRegion: true, child: Text(notice!)),
                      heading('Properties'),
                      for (final property in state.properties)
                        Text(property.name),
                      input('Property name', 'property'),
                      button(
                        'Add property',
                        () => save(() async {
                          await widget.store.addProperty(
                            Property(id: id(), name: text('property')),
                          );
                          field('property').clear();
                        }, 'Property saved'),
                      ),
                      heading('Meters'),
                      for (final entry in state.meters)
                        button(
                          '${entry.id} • ${entry.kind.name} • ${entry.unit.name}${entry.id == selectedId ? " • selected" : ""}',
                          () {
                            selectedId = entry.id;
                            correcting = null;
                            reload();
                          },
                        ),
                      if (state.properties.isNotEmpty) ...[
                        input('Meter identifier', 'meter'),
                        choices(
                          'Property',
                          state.properties.map((e) => e.name).toList(),
                          state.properties
                              .indexWhere((e) => e.id == propertyId)
                              .clamp(0, state.properties.length - 1),
                          (index) => setState(
                            () => propertyId = state.properties[index].id,
                          ),
                        ),
                        choices(
                          'Type',
                          MeterKind.values.map((e) => e.name).toList(),
                          kind.index,
                          (index) => setState(() {
                            kind = MeterKind.values[index];
                            unit = units(kind).first;
                          }),
                        ),
                        choices(
                          'Display unit',
                          units(kind).map((e) => e.name).toList(),
                          units(kind).indexOf(unit),
                          (index) => setState(() => unit = units(kind)[index]),
                        ),
                        input(
                          'Documented rollover modulus (optional)',
                          'modulus',
                          numeric: true,
                        ),
                        button(
                          'Add meter',
                          () => save(() async {
                            if (text('meter').isEmpty) {
                              throw const FormatException(
                                'Enter meter identifier',
                              );
                            }
                            final created = Meter(
                              id: '${text('meter')}-${id()}',
                              propertyId:
                                  propertyId ?? state.properties.first.id,
                              kind: kind,
                              unit: unit,
                              rolloverModulus: text('modulus').isEmpty
                                  ? null
                                  : number('modulus'),
                            );
                            await widget.store.addMeter(created);
                            selectedId = created.id;
                            field('meter').clear();
                            field('modulus').clear();
                          }, 'Meter saved'),
                        ),
                      ] else
                        const Text('Add a property first.'),
                      if (meter != null && journal != null) ...[
                        heading('Readings • ${meter.unit.name}'),
                        for (final reading in active)
                          button(
                            '${day(reading.date)} • ${reading.value} ${reading.unit.name} • ${reading.seriesId}${reading.correctionReason == null ? "" : " • corrected: ${reading.correctionReason}"} (correct)',
                            () => setState(() {
                              correcting = reading;
                              field('readingDate').text = day(reading.date);
                              field('value').text = reading.value.toString();
                            }),
                          ),
                        if (correcting != null)
                          Text(
                            'Correcting ${correcting!.id}; original stays in journal',
                          ),
                        input('Reading date (YYYY-MM-DD)', 'readingDate'),
                        input(
                          'Cumulative display value (${meter.unit.name})',
                          'value',
                          numeric: true,
                        ),
                        if (correcting == null) ...[
                          button(
                            'Replacement: ${replacement ? "new series" : "same series"}',
                            () => setState(() => replacement = !replacement),
                          ),
                          button(
                            'Documented rollover: ${rollover ? "yes" : "no"}',
                            () => setState(() => rollover = !rollover),
                          ),
                        ] else
                          input('Correction reason', 'reason'),
                        button(
                          correcting == null
                              ? 'Save reading'
                              : 'Save correction',
                          () => save(() async {
                            final correction = correcting;
                            final reading = MeterReading(
                              id: id(),
                              meterId: meter.id,
                              seriesId:
                                  correction?.seriesId ??
                                  (replacement || active.isEmpty
                                      ? id()
                                      : active.last.seriesId),
                              date: correction?.date ?? date('readingDate'),
                              value: number('value'),
                              unit: meter.unit,
                              rolloverFromPrevious:
                                  correction?.rolloverFromPrevious ?? rollover,
                              supersedesId: correction?.id,
                              correctionReason: correction == null
                                  ? null
                                  : text('reason'),
                            );
                            await widget.store.addReading(reading);
                            correcting = null;
                            replacement = false;
                            rollover = false;
                            field('reason').clear();
                            field('value').clear();
                          }, 'Reading saved'),
                        ),
                        heading('Usage • ${meter.unit.name}'),
                        const Text(
                          'Only exact date boundaries. No interpolation across missing dates or replacements.',
                        ),
                        for (var i = 1; i < active.length; i++)
                          Text(
                            '${day(active[i - 1].date)} – ${day(active[i].date)}: ${usageLabel(journal.interval(active[i - 1].date, active[i].date), meter.unit)}',
                          ),
                        heading('Bills • ${meter.unit.name}'),
                        for (final bill in state.bills) billLine(journal, bill),
                        input('Bill start (YYYY-MM-DD)', 'start'),
                        input('Bill end (YYYY-MM-DD)', 'end'),
                        input(
                          'Billed quantity (${meter.unit.name})',
                          'quantity',
                          numeric: true,
                        ),
                        input(
                          'Total paid (optional, not a rate)',
                          'amount',
                          numeric: true,
                        ),
                        input('Currency (if total supplied)', 'currency'),
                        button(
                          'Save bill',
                          () => save(() async {
                            final amount = text('amount').isEmpty
                                ? null
                                : number('amount');
                            await widget.store.addBill(
                              id(),
                              UtilityBill(
                                meterId: meter.id,
                                start: date('start'),
                                end: date('end'),
                                quantity: number('quantity'),
                                unit: meter.unit,
                                amount: amount,
                                currency: amount == null
                                    ? null
                                    : text('currency'),
                              ),
                            );
                            for (final key in [
                              'quantity',
                              'amount',
                              'currency',
                            ]) {
                              field(key).clear();
                            }
                          }, 'Bill saved'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );

  static String day(DateTime date) => date.toIso8601String().substring(0, 10);
  static List<MeterUnit> units(MeterKind kind) => switch (kind) {
    MeterKind.electricity => [MeterUnit.kilowattHours],
    MeterKind.gas => [MeterUnit.therms, MeterUnit.cubicMetres],
    MeterKind.water => [MeterUnit.cubicMetres, MeterUnit.usGallons],
  };
  static String usageLabel(IntervalUsage usage, MeterUnit unit) => usage.isKnown
      ? '${usage.quantity} ${unit.name}'
      : 'unknown (${usage.unknownReason!.name})';

  Widget billLine(MeterJournal journal, UtilityBill bill) {
    final comparison = journal.reconcile(bill);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Text(
        '${day(bill.start)} – ${day(bill.end)}: billed ${bill.quantity} ${bill.unit.name}; '
        'recorded ${usageLabel(comparison.usage, bill.unit)}; difference '
        '${comparison.quantityDifference == null ? "unknown" : "${comparison.quantityDifference} ${bill.unit.name}"}'
        '${bill.amount == null ? "" : "; paid ${bill.amount} ${bill.currency} (not a rate)"}',
      ),
    );
  }

  Widget heading(String value) => Padding(
    padding: const EdgeInsets.only(top: 22, bottom: 8),
    child: Text(
      value,
      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
    ),
  );
  Widget choices(
    String title,
    List<String> options,
    int current,
    void Function(int) select,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title),
      Wrap(
        spacing: 8,
        children: [
          for (var index = 0; index < options.length; index++)
            button(
              '${options[index]}${index == current ? " ✓" : ""}',
              () => select(index),
            ),
        ],
      ),
    ],
  );

  Widget input(String label, String key, {bool numeric = false}) {
    final keyboard = numeric
        ? const TextInputType.numberWithOptions(decimal: true)
        : TextInputType.text;
    final controller = field(key);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label),
          switch (defaultTargetPlatform) {
            TargetPlatform.iOS => CupertinoTextField(
              controller: controller,
              placeholder: label,
              keyboardType: keyboard,
            ),
            TargetPlatform.android => TextField(
              controller: controller,
              decoration: InputDecoration(
                labelText: label,
                border: const OutlineInputBorder(),
              ),
              keyboardType: keyboard,
            ),
            _ => Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xffffffff),
                border: Border.all(color: const Color(0xff747b83)),
              ),
              child: EditableText(
                controller: controller,
                focusNode: focus(key),
                style: const TextStyle(fontSize: 16, color: Color(0xff17364a)),
                cursorColor: const Color(0xff005a9e),
                backgroundCursorColor: const Color(0xff8799aa),
                keyboardType: keyboard,
              ),
            ),
          },
        ],
      ),
    );
  }

  Widget button(String title, VoidCallback action) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: switch (defaultTargetPlatform) {
      TargetPlatform.iOS => CupertinoButton(
        onPressed: action,
        child: Text(title),
      ),
      TargetPlatform.android => FilledButton.tonal(
        onPressed: action,
        child: Text(title),
      ),
      _ => _DesktopButton(title: title, action: action),
    },
  );
}

class _DesktopButton extends StatefulWidget {
  const _DesktopButton({required this.title, required this.action});
  final String title;
  final VoidCallback action;
  @override
  State<_DesktopButton> createState() => _DesktopButtonState();
}

class _DesktopButtonState extends State<_DesktopButton> {
  bool hover = false;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: widget.title,
    child: FocusableActionDetector(
      mouseCursor: SystemMouseCursors.click,
      onShowHoverHighlight: (value) => setState(() => hover = value),
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.action();
            return null;
          },
        ),
      },
      child: GestureDetector(
        onTap: widget.action,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: hover ? const Color(0xffdceefb) : const Color(0xfff5f6f7),
            border: Border.all(color: const Color(0xff8799aa)),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(widget.title),
        ),
      ),
    ),
  );
}
