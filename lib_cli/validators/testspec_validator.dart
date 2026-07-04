import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

const knownPhoneTypes = {
  'ANDROID_PHONE', 'ANDROID_TABLET_7_INCH', 'ANDROID_TABLET_10_INCH',
  'ANDROID_TV', 'ANDROID_WEAR', 'ANDROID_SAMSUNG', 'ANDROID_AMAZON',
  'IOS_IPHONE_6_9_INCH', 'IOS_IPHONE_6_5_INCH', 'IOS_IPAD_13_INCH', 'APPLE_TV',
  'IOS_IPHONE_6_7_INCH', 'IOS_IPAD_PRO_2GEN_12_9_INCH',
};

class TestspecIssue {
  final String path;
  final String message;
  final String? fix;
  const TestspecIssue(this.path, this.message, {this.fix});
}

class TestspecResult {
  final bool present;
  final String? specPath;
  final List<TestspecIssue> errors;
  final List<TestspecIssue> warnings;
  final List<TestspecIssue> infos;
  TestspecResult({
    required this.present,
    this.specPath,
    this.errors = const [],
    this.warnings = const [],
    this.infos = const [],
  });
}

/// Locates anntestspec.yaml (or legacy annaitestspec.yaml) under [projectRoot].
/// Returns the new-name file as the fallback when neither exists, so "not found"
/// messages always reference the current filename.
File findTestspecFile(String projectRoot) {
  final newFile    = File(p.join(projectRoot, 'anntestspec.yaml'));
  final legacyFile = File(p.join(projectRoot, 'annaitestspec.yaml'));
  if (newFile.existsSync()) return newFile;
  if (legacyFile.existsSync()) return legacyFile;
  return newFile;
}

/// Validates [testspecFile] against the anntestspec schema rules.
/// [annspecFlavorKeys] is a map of platform → flavor key set used for
/// cross-referencing; pass an empty map when annspec is not available.
TestspecResult validateTestspec(
  File testspecFile,
  String projectRoot, {
  Map<String, Set<String>> annspecFlavorKeys = const {},
}) {
  final specPath = testspecFile.path;

  if (!testspecFile.existsSync()) {
    return TestspecResult(present: false, specPath: specPath);
  }

  final errors   = <TestspecIssue>[];
  final warnings = <TestspecIssue>[];
  final infos    = <TestspecIssue>[];

  dynamic rawAny;
  try {
    rawAny = loadYaml(testspecFile.readAsStringSync());
  } catch (e) {
    errors.add(TestspecIssue('anntestspec.yaml', 'Cannot parse anntestspec.yaml: $e'));
    return TestspecResult(present: true, specPath: specPath,
        errors: errors, warnings: warnings, infos: infos);
  }

  if (rawAny is! YamlMap) {
    errors.add(TestspecIssue('anntestspec.yaml',
        'anntestspec.yaml is empty or does not contain a valid YAML mapping.'));
    return TestspecResult(present: true, specPath: specPath,
        errors: errors, warnings: warnings, infos: infos);
  }

  final rootMap = rawAny['annai_app_tests'];
  if (rootMap == null) {
    errors.add(TestspecIssue('annai_app_tests',
        "Missing top-level 'annai_app_tests' key.",
        fix: 'The root key must be  annai_app_tests:'));
    return TestspecResult(present: true, specPath: specPath,
        errors: errors, warnings: warnings, infos: infos);
  }
  if (rootMap is! YamlMap) {
    errors.add(TestspecIssue('annai_app_tests',
        "'annai_app_tests' must be a YAML mapping."));
    return TestspecResult(present: true, specPath: specPath,
        errors: errors, warnings: warnings, infos: infos);
  }

  for (final platformKey in ['android', 'ios']) {
    final platformMap = rootMap[platformKey];
    if (platformMap == null) continue;
    if (platformMap is! YamlMap) continue;

    final annspecKeys = annspecFlavorKeys[platformKey] ?? {};

    final defaultBlock = platformMap['default'];
    final driverFile = (defaultBlock is YamlMap)
        ? defaultBlock['driver_file']?.toString()
        : null;
    final testFile = (defaultBlock is YamlMap)
        ? defaultBlock['test_file']?.toString()
        : null;

    if (driverFile == null || driverFile.trim().isEmpty) {
      warnings.add(TestspecIssue(
          'annai_app_tests.$platformKey.default.driver_file',
          'driver_file is not set.'));
    } else if (!File(p.join(projectRoot, driverFile)).existsSync()) {
      warnings.add(TestspecIssue(
          'annai_app_tests.$platformKey.default.driver_file',
          'Driver file not found on disk: $driverFile'));
    }

    if (testFile == null || testFile.trim().isEmpty) {
      warnings.add(TestspecIssue(
          'annai_app_tests.$platformKey.default.test_file',
          'test_file is not set.'));
    } else if (!File(p.join(projectRoot, testFile)).existsSync()) {
      warnings.add(TestspecIssue(
          'annai_app_tests.$platformKey.default.test_file',
          'Test file not found on disk: $testFile'));
    }

    final flavors = platformMap['flavor'];
    if (flavors is! YamlMap) continue;

    for (final flavorEntry in flavors.entries) {
      final fk = flavorEntry.key.toString();

      if (annspecKeys.isNotEmpty && !annspecKeys.contains(fk)) {
        warnings.add(TestspecIssue(
            'annai_app_tests.$platformKey.flavor.$fk',
            "Flavor '$fk' is defined in anntestspec.yaml but not in annspec.yaml ($platformKey).",
            fix: "Add '$fk' to annspec.yaml app.$platformKey.flavor, "
                "or remove it from anntestspec.yaml."));
      }

      final flavorVal = flavorEntry.value;
      if (flavorVal is! YamlMap) continue;
      final devices = flavorVal['devices'];
      if (devices is! YamlMap || devices.isEmpty) {
        warnings.add(TestspecIssue(
            'annai_app_tests.$platformKey.flavor.$fk.devices',
            'No devices configured.'));
        continue;
      }

      for (final deviceEntry in devices.entries) {
        final dn = deviceEntry.key.toString();
        final deviceVal = deviceEntry.value;
        final tests = (deviceVal is YamlMap) ? deviceVal['tests'] : null;

        if (tests is! YamlMap || tests.isEmpty) {
          warnings.add(TestspecIssue(
              'annai_app_tests.$platformKey.flavor.$fk.devices.$dn.tests',
              "Device '$dn' has no test cases."));
          continue;
        }

        for (final testEntry in tests.entries) {
          final tn = testEntry.key.toString();
          final testVal = testEntry.value;
          final phoneType = (testVal is YamlMap)
              ? testVal['phone_type']?.toString().trim() ?? ''
              : '';

          if (phoneType.isEmpty) {
            errors.add(TestspecIssue(
                'annai_app_tests.$platformKey.flavor.$fk.devices.$dn.tests.$tn.phone_type',
                "phone_type is missing for test '$tn' on device '$dn'.",
                fix: 'Add  phone_type: "ANDROID_PHONE"  (or another known type)'));
          } else {
            for (final singleType in phoneType
                .split(',')
                .map((t) => t.trim())
                .where((t) => t.isNotEmpty)) {
              if (!knownPhoneTypes.contains(singleType.toUpperCase())) {
                infos.add(TestspecIssue(
                    'annai_app_tests.$platformKey.flavor.$fk.devices.$dn.tests.$tn.phone_type',
                    "Unknown phone type '$singleType' — custom types are allowed but check for typos."));
              }
            }
          }
        }
      }
    }
  }

  return TestspecResult(present: true, specPath: specPath,
      errors: errors, warnings: warnings, infos: infos);
}
