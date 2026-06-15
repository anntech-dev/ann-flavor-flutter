import 'dart:io';
import 'package:path/path.dart' as p;

const _pluginId = 'com.annaibrands.android.flavorize';
const _pluginVersion = '1.1.1';

/// Ensures the ANN Gradle plugin is wired into the Android project.
class AndroidGenerator {
  static void generate(String projectRoot) {
    final androidDir = Directory(p.join(projectRoot, 'android'));
    if (!androidDir.existsSync()) {
      print('  ⚠ No android/ directory found — skipping Android wiring.');
      return;
    }
    _patchSettings(androidDir);
    _patchAppBuild(androidDir);
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
}
