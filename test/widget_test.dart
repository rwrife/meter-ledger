import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meterledger/data/meter_store.dart';
import 'package:meterledger/domain/meter_domain.dart';
import 'package:meterledger/main.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  Future<MeterStore> open() =>
      MeterStore.open(inMemoryDatabasePath, factory: databaseFactoryFfi);
  late MeterStore store;
  setUp(() async => store = await open());
  Future<void> flush(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await tester.pumpAndSettle();
    }
  }
  // ponytail: SQLite FFI uses real isolates; flush bridges test fake clock to real async work.

  for (final platform in [
    TargetPlatform.android,
    TargetPlatform.iOS,
    TargetPlatform.windows,
  ]) {
    testWidgets('$platform has native shell and workspace', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      // Reset inside test body; binding checks globals before tearDown.
      await tester.pumpWidget(MeterLedgerApp(openStore: () async => store));
      await flush(tester);
      expect(find.byType(MeterWorkspaceLayout), findsOneWidget);
      expect(find.text('Add property'), findsOneWidget);
      if (platform == TargetPlatform.iOS) {
        expect(find.byType(CupertinoApp), findsOneWidget);
        expect(find.byType(MaterialApp), findsNothing);
        expect(find.byType(CupertinoButton), findsWidgets);
      } else if (platform == TargetPlatform.android) {
        expect(find.byType(MaterialApp), findsOneWidget);
        expect(find.byType(CupertinoApp), findsNothing);
        expect(find.byType(FilledButton), findsWidgets);
      } else {
        expect(find.byType(WidgetsApp), findsOneWidget);
        expect(find.byType(MaterialApp), findsNothing);
        expect(find.byType(CupertinoApp), findsNothing);
      }
      await tester.pumpWidget(const SizedBox());
      await flush(tester);
      debugDefaultTargetPlatformOverride = null;
    });
  }

  testWidgets('manual journal saves and displays unknown exact bill boundary', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await tester.pumpWidget(MeterLedgerApp(openStore: () async => store));
    await flush(tester);
    await tester.enterText(
      find.widgetWithText(TextField, 'Property name'),
      'Home',
    );
    await tester.tap(find.text('Add property'));
    await flush(tester);
    expect((await tester.runAsync(store.properties))!.single.name, 'Home');
    await tester.enterText(
      find.widgetWithText(TextField, 'Meter identifier'),
      'Kitchen',
    );
    await tester.ensureVisible(find.text('Add meter'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add meter'));
    await flush(tester);
    final meter = (await tester.runAsync(store.meters))!.single;
    expect(meter.unit, MeterUnit.kilowattHours);
    await tester.enterText(
      find.widgetWithText(TextField, 'Reading date (YYYY-MM-DD)'),
      '2026-01-01',
    );
    await tester.enterText(
      find.widgetWithText(
        TextField,
        'Cumulative display value (kilowattHours)',
      ),
      '100',
    );
    await tester.ensureVisible(find.text('Save reading'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save reading'));
    await flush(tester);
    expect(
      (await tester.runAsync(() => store.readings(meter.id)))!.single.value,
      100,
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Bill start (YYYY-MM-DD)'),
      '2026-01-01',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Bill end (YYYY-MM-DD)'),
      '2026-02-01',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Billed quantity (kilowattHours)'),
      '12',
    );
    await tester.ensureVisible(find.text('Save bill'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save bill'));
    await flush(tester);
    expect(
      (await tester.runAsync(() => store.bills(meter.id)))!.single.quantity,
      12,
    );
    expect(find.textContaining('recorded unknown'), findsOneWidget);
    expect(find.textContaining('difference unknown'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await flush(tester);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('correction retains prior entry and updates displayed usage', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await tester.pumpWidget(MeterLedgerApp(openStore: () async => store));
    await flush(tester);
    await tester.enterText(
      find.widgetWithText(TextField, 'Property name'),
      'Home',
    );
    await tester.tap(find.text('Add property'));
    await flush(tester);
    await tester.enterText(
      find.widgetWithText(TextField, 'Meter identifier'),
      'Power',
    );
    await tester.ensureVisible(find.text('Add meter'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add meter'));
    await flush(tester);
    final meter = (await tester.runAsync(store.meters))!.single;

    await tester.enterText(
      find.widgetWithText(TextField, 'Reading date (YYYY-MM-DD)'),
      '2026-01-01',
    );
    await tester.enterText(
      find.widgetWithText(
        TextField,
        'Cumulative display value (kilowattHours)',
      ),
      '100',
    );
    await tester.ensureVisible(find.text('Save reading'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save reading'));
    await flush(tester);

    await tester.enterText(
      find.widgetWithText(TextField, 'Reading date (YYYY-MM-DD)'),
      '2026-02-01',
    );
    await tester.enterText(
      find.widgetWithText(
        TextField,
        'Cumulative display value (kilowattHours)',
      ),
      '150',
    );
    await tester.ensureVisible(find.text('Save reading'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save reading'));
    await flush(tester);
    expect(
      find.textContaining('2026-01-01 – 2026-02-01: 50.0 kilowattHours'),
      findsOneWidget,
    );

    await tester.ensureVisible(
      find.textContaining('2026-02-01 • 150.0 kilowattHours'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('2026-02-01 • 150.0 kilowattHours'));
    await flush(tester);
    expect(find.textContaining('Correcting'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(
        TextField,
        'Cumulative display value (kilowattHours)',
      ),
      '160',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Correction reason'),
      'Transposed digits',
    );
    await tester.ensureVisible(find.text('Save correction'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save correction'));
    await flush(tester);

    final readings = (await tester.runAsync(() => store.readings(meter.id)))!;
    expect(readings.length, 3);
    expect(readings.last.correctionReason, 'Transposed digits');
    expect(
      find.textContaining('2026-01-01 – 2026-02-01: 60.0 kilowattHours'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
    await flush(tester);
    debugDefaultTargetPlatformOverride = null;
  });
}
