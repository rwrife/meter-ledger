import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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
  });
  tearDown(() => store.close());

  Future<void> flush(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await tester.pumpAndSettle();
    }
  }

  testWidgets('exports labeled CSV only to selected destination', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    String? filename;
    Uint8List? saved;
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MeterWorkspaceLayout(
              store: store,
              saveFile: (name, bytes, mime) async {
                filename = name;
                saved = bytes;
                expect(mime, 'text/csv');
                return Uri.file('/chosen/$name');
              },
            ),
          ),
        ),
      );
      await flush(tester);
      await tester.ensureVisible(find.text('Export readings CSV'));
      await tester.tap(find.text('Export readings CSV'));
      await flush(tester);
      expect(filename, 'meter-ledger-readings.csv');
      expect(
        utf8.decode(saved!),
        contains('property,meter,kind,unit,date,value'),
      );
      expect(find.textContaining('Export saved'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await flush(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('invalid backup never asks for consent or changes journal', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MeterWorkspaceLayout(
              store: store,
              pickBackup: () async => Uint8List.fromList(utf8.encode('{bad')),
            ),
          ),
        ),
      );
      await flush(tester);
      await tester.ensureVisible(find.text('Restore JSON backup'));
      await tester.tap(find.text('Restore JSON backup'));
      await flush(tester);
      expect(
        find.textContaining('Restore failed; journal unchanged'),
        findsOneWidget,
      );
      expect(find.text('Replace local journal?'), findsNothing);
      final properties = await tester.runAsync(store.properties);
      expect(properties!.single.name, 'Home');
      await tester.pumpWidget(const SizedBox());
      await flush(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('valid backup requires consent and replaces journal', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final backup = await tester.runAsync(store.exportJson);
      await tester.runAsync(
        () => store.addProperty(Property(id: 'extra', name: 'Temporary')),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MeterWorkspaceLayout(
              store: store,
              pickBackup: () async => Uint8List.fromList(utf8.encode(backup!)),
            ),
          ),
        ),
      );
      await flush(tester);
      await tester.ensureVisible(find.text('Restore JSON backup'));
      await tester.tap(find.text('Restore JSON backup'));
      await flush(tester);
      expect(find.text('Replace local journal?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await flush(tester);
      expect((await tester.runAsync(store.properties))!.length, 2);
      await tester.tap(find.text('Restore JSON backup'));
      await flush(tester);
      await tester.tap(find.text('Replace journal'));
      await flush(tester);
      expect(find.text('Backup restored'), findsOneWidget);
      expect((await tester.runAsync(store.properties))!.single.name, 'Home');
      await tester.pumpWidget(const SizedBox());
      await flush(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
