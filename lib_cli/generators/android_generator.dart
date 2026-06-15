import 'dart:io';
import 'package:path/path.dart' as p;
import '../model/annspec_model.dart';

const _pluginId = 'com.annaibrands.android.flavorize';
const _pluginVersion = '1.1.1';

/// Ensures the ANN Gradle plugin is wired into the Android project,
/// and patches defaultConfig with applicationId + minSdk from annspec.yaml.
class AndroidGenerator {
  static void generate(String projectRoot, [AnnspecModel? spec]) {
    final androidDir = Directory(p.join(projectRoot, 'android'));
    if (!androidDir.existsSync()) {
      print('  ⚠ No android/ directory found — skipping Android wiring.');
      return;
    }
    _patchSettings(androidDir);
    _patchAppBuild(androidDir);

    // Patch defaultConfig if spec data is available
    if (spec != null) {
      final android = spec.platform('android');
      if (android != null) {
        _patchDefaultConfig(androidDir, android);
      }
    }
  }

  static void _patchSettings(Directory androidDir) {
    final file = File(p.join(androidDir.path, 'settings.gradle.kts'));
    if (!file.existsSync()) return;

    var content = file.readAsStringSync();
    if (content.contains(_pluginId)) {
      print('  ✓ Android settings.gradle.kts already has ANN Gradle plugin.');
      return;
    }

    // Insert into pluginManagement { plugins { ... } }
    final injection = '''
        id("$_pluginId") version "$_pluginVersion" apply false''';

    content = content.replaceFirstMapped(
      RegExp(r'(pluginManagement\s*\{[^}]*plugins\s*\{)', dotAll: true),
      (m) => '${m.group(0)}\n$injection',
    );

    file.writeAsStringSync(content);
    print('  ✓ Patched android/settings.gradle.kts with ANN Gradle plugin.');
  }

  static void _patchAppBuild(Directory androidDir) {
    final file = File(p.join(androidDir.path, 'app', 'build.gradle.kts'));
    if (!file.existsSync()) return;

    var content = file.readAsStringSync();
    if (content.contains(_pluginId)) {
      print('  ✓ Android app/build.gradle.kts already applies ANN Gradle plugin.');
      return;
    }

    final injection = '\n    id("$_pluginId")';
    content = content.replaceFirstMapped(
      RegExp(r'(plugins\s*\{)'),
      (m) => '${m.group(0)}$injection',
    );

    file.writeAsStringSync(content);
    print('  ✓ Patched android/app/build.gradle.kts with ANN Gradle plugin.');
  }

  // ── defaultConfig: applicationId + minSdk ──────────────────────────────────

  static void _patchDefaultConfig(Directory androidDir, AnnspecPlatform android) {
    final file = File(p.join(androidDir.path, 'app', 'build.gradle.kts'));
    if (!file.existsSync()) return;

    var content = file.readAsStringSync();
    var changed = false;

    // applicationId — use base ID from annspec
    if (android.baseId != null) {
      final newId = android.baseId!;
      final updated = content.replaceFirstMapped(
        RegExp(r'applicationId\s*=\s*"[^"]*"'),
        (_) => 'applicationId = "$newId"',
      );
      if (updated != content) {
        content = updated;
        changed = true;
        print('  ✓ Set defaultConfig.applicationId = "$newId"');
      }
    }

    // minSdk — use value from annspec android.sdk.minSdk
    if (android.minSdk != null) {
      final minSdk = android.minSdk!;
      final updated = content.replaceFirstMapped(
        RegExp(r'minSdk\s*=\s*\S+'),
        (_) => 'minSdk = $minSdk',
      );
      if (updated != content) {
        content = updated;
        changed = true;
        print('  ✓ Set defaultConfig.minSdk = $minSdk');
      }
    }

    if (changed) file.writeAsStringSync(content);
  }

  // ── AndroidManifest.xml ────────────────────────────────────────────────────

  /// Ensures the launcher activity has the flutter default intent-filter.
  /// Currently a no-op placeholder — extend as needed per project.
  static void patchManifest(String projectRoot) {
    final file = File(
      p.join(projectRoot, 'android', 'app', 'src', 'main', 'AndroidManifest.xml'),
    );
    if (!file.existsSync()) {
      print('  ⚠ AndroidManifest.xml not found — skipping.');
      return;
    }
    // Placeholder: add manifest patches here when needed.
    print('  ✓ AndroidManifest.xml — no patches required.');
  }
}
