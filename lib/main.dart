import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

void main() => runApp(const MeterLedgerApp());

class MeterLedgerApp extends StatelessWidget {
  const MeterLedgerApp({super.key});

  @override
  Widget build(BuildContext context) {
    const message = Center(
      child: Text('Manual meter records are coming soon.'),
    );
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return const CupertinoApp(
          title: 'Meter Ledger',
          home: CupertinoPageScaffold(
            navigationBar: CupertinoNavigationBar(middle: Text('Meter Ledger')),
            child: SafeArea(child: message),
          ),
        );
      case TargetPlatform.windows:
        // ponytail: plain desktop shell until adaptive Fluent workspace issue.
        return WidgetsApp(
          color: const Color(0xff17364a),
          pageRouteBuilder: <T>(settings, builder) => PageRouteBuilder<T>(
            settings: settings,
            pageBuilder: (context, animation, secondaryAnimation) =>
                builder(context),
          ),
          home: Directionality(
            textDirection: TextDirection.ltr,
            child: Column(
              children: [
                Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Meter Ledger', textScaler: TextScaler.noScaling),
                ),
                Expanded(child: message),
              ],
            ),
          ),
        );
      default:
        return MaterialApp(
          title: 'Meter Ledger',
          theme: ThemeData(useMaterial3: true),
          home: const Scaffold(appBar: _AndroidAppBar(), body: message),
        );
    }
  }
}

class _AndroidAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _AndroidAppBar();

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) =>
      AppBar(title: const Text('Meter Ledger'));
}
