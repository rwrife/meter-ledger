import 'dart:io' show Platform;
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meterledger/data/meter_store.dart';
import 'package:meterledger/domain/meter_domain.dart';
import 'package:meterledger/main.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late MeterStore store;
  setUp(() async {
    store = await MeterStore.open(
      inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    await store.addProperty(Property(id: 'home', name: 'Home'));
    await store.addMeter(
      Meter(
        id: 'power',
        propertyId: 'home',
        kind: MeterKind.electricity,
        unit: MeterUnit.kilowattHours,
      ),
    );
  });
  tearDown(() async {
    await store.close();
  });

  Future<void> flush(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await tester.pumpAndSettle();
    }
  }

  for (final platform in [
    TargetPlatform.iOS,
    TargetPlatform.android,
    TargetPlatform.windows,
  ]) {
    for (final width in [390.0, 820.0, 1440.0]) {
      testWidgets(
        '$platform at ${width.toInt()}px: resize, controls and semantics',
        (tester) async {
          debugDefaultTargetPlatformOverride = platform;
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = Size(width, 900);
          final semantics = tester.ensureSemantics();
          try {
            await tester.pumpWidget(
              MeterLedgerApp(openStore: () async => store),
            );
            await flush(tester);
            expect(tester.takeException(), isNull);
            expect(find.text('Add property'), findsOneWidget);
            expect(
              tester
                  .getSemantics(find.text('Add property'))
                  .getSemanticsData()
                  .label,
              contains('Add property'),
            );
            if (platform == TargetPlatform.windows) {
              expect(find.text('Navigation'), findsOneWidget);
              expect(find.byType(CupertinoButton), findsNothing);
              expect(find.byType(MaterialApp), findsNothing);
            } else if (platform == TargetPlatform.iOS) {
              expect(find.byType(CupertinoTextField), findsWidgets);
              expect(find.byType(FilledButton), findsNothing);
            } else {
              expect(find.byType(TextField), findsWidgets);
              expect(find.byType(CupertinoButton), findsNothing);
            }
            tester.view.physicalSize = const Size(600, 800);
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox());
            await flush(tester);
          } finally {
            semantics.dispose();
            tester.view.resetPhysicalSize();
            tester.view.resetDevicePixelRatio();
            debugDefaultTargetPlatformOverride = null;
          }
        },
      );
    }
  }

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('$platform native date picker and back dismiss', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await tester.pumpWidget(MeterLedgerApp(openStore: () async => store));
        await flush(tester);
        await tester.tap(find.textContaining('power • electricity').first);
        await flush(tester);
        await tester.ensureVisible(find.text('Pick date').first);
        await tester.tap(find.text('Pick date').first);
        await tester.pumpAndSettle();
        if (platform == TargetPlatform.iOS) {
          expect(find.byType(CupertinoDatePicker), findsOneWidget);
          expect(find.byType(DatePickerDialog), findsNothing);
          await tester.tap(find.text('Done'));
        } else {
          expect(find.byType(DatePickerDialog), findsOneWidget);
          expect(find.byType(CupertinoDatePicker), findsNothing);
          await tester.binding.handlePopRoute();
        }
        await tester.pumpAndSettle();
        expect(find.byType(CupertinoDatePicker), findsNothing);
        expect(find.byType(DatePickerDialog), findsNothing);
        await tester.pumpWidget(const SizedBox());
        await flush(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  for (final platform in [
    TargetPlatform.iOS,
    TargetPlatform.android,
    TargetPlatform.windows,
  ]) {
    testWidgets('$platform workspace golden at 390px', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 700);
      try {
        await tester.pumpWidget(MeterLedgerApp(openStore: () async => store));
        await flush(tester);
        if (Platform.isLinux) {
          await expectLater(
            find.byType(MeterLedgerApp),
            matchesGoldenFile('goldens/${platform.name}-workspace-390.png'),
          );
        } else {
          // ponytail: raster goldens are Linux-specific; host-native widget assertions run on Windows.
          expect(find.byType(MeterWorkspaceLayout), findsOneWidget);
        }
        await tester.pumpWidget(const SizedBox());
        await flush(tester);
      } finally {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  testWidgets('Windows navigation supports keyboard and pointer', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    try {
      await tester.pumpWidget(MeterLedgerApp(openStore: () async => store));
      await flush(tester);
      final nav = find.text('Meters').first;
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.tap(nav);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await pointer.addPointer();
      await pointer.moveTo(tester.getCenter(nav));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await pointer.removePointer();
      await tester.pumpWidget(const SizedBox());
      await flush(tester);
    } finally {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
