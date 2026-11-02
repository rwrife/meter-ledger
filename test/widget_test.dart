import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:meterledger/main.dart';

void main() {
  testWidgets('renders Android Material shell', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await tester.pumpWidget(const MeterLedgerApp());
    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.text('Manual meter records are coming soon.'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('renders iOS Cupertino shell', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await tester.pumpWidget(const MeterLedgerApp());
    expect(find.byType(CupertinoApp), findsOneWidget);
    expect(find.byType(CupertinoNavigationBar), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('renders Windows shell without phone scaffolding', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    await tester.pumpWidget(const MeterLedgerApp());
    expect(find.byType(WidgetsApp), findsOneWidget);
    expect(find.byType(MaterialApp), findsNothing);
    expect(find.byType(CupertinoApp), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });
}
