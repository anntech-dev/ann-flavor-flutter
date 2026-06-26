import 'package:ann_flutter_flavor/ann_flutter_flavor.dart';
import 'package:flutter/material.dart';

/// Root widget — shared across all flavors.
/// Each flavor entry point (lib/flavors/main_*.dart) calls [AnnFlavor.init]
/// before running this app.
class FlavorApp extends StatelessWidget {
  const FlavorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AnnFlavor.current.name,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const FlavorInfoPage(),
    );
  }
}

class FlavorInfoPage extends StatelessWidget {
  const FlavorInfoPage({super.key});

  @override
  Widget build(BuildContext context) {
    final flavor = AnnFlavor.current;
    final rc = flavor.custom('revenuecat');

    return Scaffold(
      appBar: AppBar(
        title: Text(flavor.name),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _section('Runtime'),
          _row('Flavor key', flavor.key),
          _row('Build type', AnnFlavor.buildType),
          _row('Platform', AnnFlavor.platform.name),
          const SizedBox(height: 16),
          _section('App IDs'),
          _row('Android ID', flavor.androidId ?? '—'),
          _row('iOS ID', flavor.iosId ?? '—'),
          const SizedBox(height: 16),
          _section('RevenueCat (custom group)'),
          _row('api_key', rc?.string('api_key') ?? '—'),
          _row(
            'entitlement_ids',
            rc?.strings('entitlement_ids')?.join(', ') ?? '—',
          ),
          const SizedBox(height: 24),
          const Text(
            'Run with:\n'
            '  flutter run --flavor free -t lib/flavors/main_free.dart\n'
            '  flutter run --flavor pro  -t lib/flavors/main_pro.dart',
            style: TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
      );

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 150,
              child: Text('$label:', style: const TextStyle(color: Colors.grey)),
            ),
            Expanded(child: Text(value)),
          ],
        ),
      );
}
