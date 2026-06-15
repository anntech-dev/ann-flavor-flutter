import 'dart:io';
import 'package:path/path.dart' as p;
import '../model/annspec_model.dart';

const _pluginId = 'com.annaibrands.android.flavorize';
const _pluginVersion = '1.1.1';

// ── DSL resolver ──────────────────────────────────────────────────────────────

enum _GradleDsl { kts, groovy }

class _GradleFile {
  final File file;
  final _GradleDsl dsl;
  _GradleFile(this.file, this.dsl);
}

/// Returns the first Gradle file that exists: prefers .kts, falls back to .gradle.
/// [pathSegments] should be the path including the base filename (e.g. ['android', 'app', 'build.gradle']).
_GradleFile? _resolveGradle(List<String> pathSegments) {
  final base       = p.joinAll(pathSegments);
  final ktsFile    = File('$base.kts');
  final groovyFile = File(base);

  if (ktsFile.existsSync())    return _GradleFile(ktsFile,    _GradleDsl.kts);
  if (groovyFile.existsSync()) return _GradleFile(groovyFile, _GradleDsl.groovy);
  return null;
}

/// Ensures the ANN Gradle plugin is wired into the Android project,
/// and patches defaultConfig with applicationId + minSdk from annspec.yaml.
/// Supports both Kotlin DSL (build.gradle.kts) and Groovy DSL (build.gradle).
class AndroidGenerator {
  static void generate(String projectRoot, [AnnspecModel? spec]) {
    final androidDir = Directory(p.join(projectRoot, 'android'));
    if (!androidDir.existsSync()) {
      print('  ⚠ No android/ directory found — skipping Android wiring.');
      return;
    }
    _patchSettings(androidDir);
    _patchAppBuild(androidDir);

    if (spec != null) {
      final android = spec.platform('android');
      if (android != null) _patchDefaultConfig(androidDir, android);
    }
  }

  static void _patchSettings(Directory androidDir) {
    final gf = _resolveGradle([androidDir.path, 'settings.gradle']);
    if (gf == null) return;

    var content = gf.file.readAsStringSync();
    final label = p.basename(gf.file.path);

    if (content.contains(_pluginId)) {
      print('  ✓ Android $label already has ANN Gradle plugin.');
      return;
    }

    final injection = gf.dsl == _GradleDsl.kts
        ? '\n        id("$_pluginId") version "$_pluginVersion" apply false'
        : '\n        id \'$_pluginId\' version \'$_pluginVersion\' apply false';

    content = content.replaceFirstMapped(
      RegExp(r'(pluginManagement\s*\{[^}]*plugins\s*\{)', dotAll: true),
      (m) => '${m.group(0)}$injection',
    );

    gf.file.writeAsStringSync(content);
    print('  ✓ Patched android/$label with ANN Gradle plugin.');
  }

  static void _patchAppBuild(Directory androidDir) {
    final gf = _resolveGradle([androidDir.path, 'app', 'build.gradle']);
    if (gf == null) return;

    var content = gf.file.readAsStringSync();
    final label = p.basename(gf.file.path);

    if (content.contains(_pluginId)) {
      print('  ✓ Android app/$label already applies ANN Gradle plugin.');
      return;
    }

    final injection = gf.dsl == _GradleDsl.kts
        ? '\n    id("$_pluginId")'
        : '\n    id \'$_pluginId\'';

    content = content.replaceFirstMapped(
      RegExp(r'(plugins\s*\{)'),
      (m) => '${m.group(0)}$injection',
    );

    gf.file.writeAsStringSync(content);
    print('  ✓ Patched android/app/$label with ANN Gradle plugin.');
  }

  // ── defaultConfig: applicationId + minSdk ──────────────────────────────────

  static void _patchDefaultConfig(Directory androidDir, AnnspecPlatform android) {
    final gf = _resolveGradle([androidDir.path, 'app', 'build.gradle']);
    if (gf == null) return;

    var content = gf.file.readAsStringSync();
    var changed = false;

    if (android.baseId != null) {
      final newId = android.baseId!;
      // KTS: applicationId = "..."   Groovy: applicationId "..."
      final pattern = gf.dsl == _GradleDsl.kts
          ? RegExp(r'applicationId\s*=\s*"[^"]*"')
          : RegExp(r'''applicationId\s+['"][^'"]*['"]''');
      final replacement = gf.dsl == _GradleDsl.kts
          ? 'applicationId = "$newId"'
          : 'applicationId "$newId"';
      final updated = content.replaceFirstMapped(pattern, (_) => replacement);
      if (updated != content) {
        content = updated; changed = true;
        print('  ✓ Set defaultConfig.applicationId = "$newId"');
      }
    }

    if (android.minSdk != null) {
      final minSdk = android.minSdk!;
      // KTS: minSdk = 24   Groovy: minSdkVersion 24
      final pattern = gf.dsl == _GradleDsl.kts
          ? RegExp(r'minSdk\s*=\s*\S+')
          : RegExp(r'minSdkVersion\s+\S+');
      final replacement = gf.dsl == _GradleDsl.kts
          ? 'minSdk = $minSdk'
          : 'minSdkVersion $minSdk';
      final updated = content.replaceFirstMapped(pattern, (_) => replacement);
      if (updated != content) {
        content = updated; changed = true;
        print('  ✓ Set defaultConfig.minSdk = $minSdk');
      }
    }

    if (changed) gf.file.writeAsStringSync(content);
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
