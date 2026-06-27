import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';
import '../spec/annspec_reader.dart';
import '../model/annspec_model.dart';

// auth and project_id are valid on all platforms.
// file is Android-only — iOS downloads config via project_id at build time.
const _androidOnlyBuildTypeFields = [
  'minifyEnabled', 'shrinkResources', 'lintCheckReleaseBuilds',
  'ndkVersion', 'ndkDebugSymbolLevel', 'ndkAbiFilters',
];

class ValidateCommand extends Command<void> {
  @override
  final name = 'validate';

  @override
  final description = 'Validate annspec.yaml structure and report any issues.';

  ValidateCommand() {
    argParser.addOption('project', abbr: 'p', defaultsTo: '.');
  }

  @override
  Future<void> run() async {
    final projectRoot = argResults!['project'] as String;
    print('ANN Flavor — validating annspec.yaml in $projectRoot');

    final errors = <String>[];
    final warnings = <String>[];

    AnnspecModel spec;
    YamlMap rawDoc;

    try {
      spec = AnnspecReader.read(projectRoot);
      final file = File(p.join(projectRoot, 'annspec.yaml'));
      rawDoc = loadYaml(file.readAsStringSync()) as YamlMap;
    } catch (e) {
      print('  ✗ Failed to parse annspec.yaml: $e');
      return;
    }

    final rawApp = rawDoc['app'] as YamlMap?;

    for (final platform in spec.platforms) {
      _validatePlatform(platform, rawApp, errors, warnings);
    }

    _printResults(errors, warnings);
  }

  void _validatePlatform(
    AnnspecPlatform platform,
    YamlMap? rawApp,
    List<String> errors,
    List<String> warnings,
  ) {
    final tag = '[${platform.key}]';
    final rawPlatform = rawApp?[platform.key] as YamlMap?;

    if (platform.baseId == null) {
      errors.add('$tag Missing default.id');
    }
    if (platform.flavors.isEmpty) {
      errors.add('$tag No flavors defined');
    }

    // Signing credentials warning when release build_type is configured
    if (platform.key == 'android' && platform.signingKeyFile == null) {
      if (platform.defaultFirebaseRelease != null ||
          platform.flavors.any((f) => f.firebaseRelease != null)) {
        warnings.add('$tag credentials.signing.key_file not set — release builds may fail to sign');
      }
    }
    if (platform.key == 'ios' && platform.teamId == null) {
      if (platform.defaultFirebaseRelease != null ||
          platform.flavors.any((f) => f.firebaseRelease != null)) {
        warnings.add('$tag credentials.signing.team_id not set — release builds may fail to sign');
      }
    }

    // Default build_type firebase checks
    _checkFirebase(tag, 'default.build_types.release.firebase',
        platform.defaultFirebaseRelease, platform.key, errors);
    _checkFirebase(tag, 'default.build_types.debug.firebase',
        platform.defaultFirebaseDebug, platform.key, errors);

    // Platform-specific build_type field checks (raw YAML)
    final rawDefault = rawPlatform?['default'] as YamlMap?;
    _checkBuildTypeFieldsByPlatform(tag, 'default', platform.key,
        rawDefault?['build_types'] as YamlMap?, errors);

    for (final flavor in platform.flavors) {
      _validateFlavor(flavor, platform, rawPlatform, errors, warnings);
    }
  }

  void _validateFlavor(
    AnnspecFlavor flavor,
    AnnspecPlatform platform,
    YamlMap? rawPlatform,
    List<String> errors,
    List<String> warnings,
  ) {
    final tag = '[${platform.key}/${flavor.key}]';
    final rawFlavor = (rawPlatform?['flavor'] as YamlMap?)?[flavor.key] as YamlMap?;

    // Required fields
    if (flavor.name == null)        errors.add('$tag Missing name');
    if (flavor.mainFile == null)    errors.add('$tag Missing main_file');
    if (flavor.versionName == null) errors.add('$tag Missing version_name');
    if (flavor.versionCode == null) errors.add('$tag Missing version_code');

    // id vs id_suffix mutual exclusion
    if (flavor.id != null && flavor.idSuffix != null) {
      errors.add('$tag Cannot set both id and id_suffix — use one or the other');
    }
    if (flavor.id == null && flavor.idSuffix == null) {
      warnings.add('$tag Neither id nor id_suffix set — flavor will share default.id exactly');
    }

    // Firebase mutual exclusion (file vs project_id) on flavor build_types
    _checkFirebase(tag, 'build_types.release.firebase',
        flavor.firebaseRelease, platform.key, errors);
    _checkFirebase(tag, 'build_types.debug.firebase',
        flavor.firebaseDebug, platform.key, errors);

    // Store field platform checks
    if (platform.key == 'ios') {
      if (flavor.googlePlayPriority != null)
        errors.add('$tag stores.google_play is Android-only — remove from iOS flavor');
      if (flavor.samsungAppId != null)
        errors.add('$tag stores.samsung_galaxy is Android-only — remove from iOS flavor');
      if (flavor.amazonAppId != null)
        errors.add('$tag stores.amazon is Android-only — remove from iOS flavor');
    }
    if (platform.key == 'android') {
      if (flavor.appleId != null)
        errors.add('$tag stores.app_store is iOS-only — remove from Android flavor');
    }

    // google_play.priority range
    if (flavor.googlePlayPriority != null) {
      final priority = int.tryParse(flavor.googlePlayPriority!);
      if (priority == null || priority < 1 || priority > 5) {
        errors.add('$tag stores.google_play.priority must be 1–5 (got: ${flavor.googlePlayPriority})');
      }
    }

    // Platform-specific build_type field checks (raw YAML)
    _checkBuildTypeFieldsByPlatform(tag, 'flavor', platform.key,
        rawFlavor?['build_types'] as YamlMap?, errors);
  }

  void _checkFirebase(
    String tag,
    String fieldPath,
    AnnspecFirebase? firebase,
    String platformKey,
    List<String> errors,
  ) {
    if (firebase == null) return;

    if (firebase.file != null && firebase.projectId != null) {
      errors.add('$tag $fieldPath: cannot set both file and project_id — pick one');
    }
    if (platformKey == 'ios' && firebase.file != null) {
      errors.add('$tag $fieldPath: firebase.file is Android-only — use project_id on iOS');
    }
  }

  void _checkBuildTypeFieldsByPlatform(
    String tag,
    String context,
    String platformKey,
    YamlMap? buildTypesRaw,
    List<String> errors,
  ) {
    if (buildTypesRaw == null) return;

    for (final btEntry in buildTypesRaw.entries) {
      final btKey = btEntry.key as String;
      final btMap = btEntry.value as YamlMap?;
      if (btMap == null) continue;
      final btTag = '$tag $context.build_types.$btKey';

      if (platformKey == 'ios') {
        for (final field in _androidOnlyBuildTypeFields) {
          if (btMap.containsKey(field)) {
            errors.add('$btTag: $field is Android-only — remove from iOS build_type');
          }
        }
      }
    }
  }

  void _printResults(List<String> errors, List<String> warnings) {
    if (warnings.isNotEmpty) {
      print('  ⚠  ${warnings.length} warning(s):');
      for (final w in warnings) print('    • $w');
    }
    if (errors.isEmpty) {
      print('  ✅  annspec.yaml is valid.');
    } else {
      print('  ✗ ${errors.length} error(s):');
      for (final e in errors) print('    • $e');
    }
  }
}
