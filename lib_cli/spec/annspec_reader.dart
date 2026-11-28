import 'dart:io';
import 'package:path/path.dart' as p;
import '../vendor/ann_flavor_core/ann_flavor_core.dart' as core;

/// Reads annspec.yaml via the shared core (ADR-008) — parsing and cascade
/// merging are entirely the core's responsibility. Every consumer under
/// lib_cli/ reads core.AnnSpec (and, for resolved/cascaded values,
/// core.AnnSpecResolver's output) directly — there is no plugin-local mirror
/// model to keep in sync (see plan 035 STEP-2.2.a, which retired one).
class AnnspecReader {
  /// The Android and iOS flavor names of annspec.yaml, for checking the test spec against them.
  /// Empty when there is no annspec.yaml or it cannot be read: that is `validate`'s to report.
  static Map<String, Set<String>> testFlavorKeys(String projectRoot) {
    try {
      final app = read(projectRoot).app;
      return {
        if (app.android != null) 'android': app.android!.flavors.keys.toSet(),
        if (app.ios != null) 'ios': app.ios!.flavors.keys.toSet(),
      };
    } catch (_) {
      return const {};
    }
  }

  static core.AnnSpec read(String projectRoot) {
    final file = File(p.join(projectRoot, 'annspec.yaml'));
    if (!file.existsSync()) {
      throw Exception('annspec.yaml not found at ${file.path}');
    }

    try {
      return core.AnnSpecParser.parse(file.readAsStringSync());
    } catch (e) {
      final raw = file.readAsStringSync();
      final hint = raw.contains('annai_app:')
          ? '\n  Hint: rename the root key from "annai_app:" to "app:" — the key was changed in v0.2.0.'
          : '';
      throw Exception('Failed to parse annspec.yaml: $e$hint');
    }
  }
}
