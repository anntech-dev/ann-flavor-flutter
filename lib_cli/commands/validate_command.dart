import 'dart:convert';
import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';
import 'package:ann_flavor_core/ann_flavor_core.dart' as core;
import '../spec/annspec_reader.dart';
import '../validators/testspec_validator.dart';

const _androidOnlyBuildTypeFields = [
  'minifyEnabled', 'shrinkResources', 'lintCheckReleaseBuilds',
  'ndkVersion', 'ndkDebugSymbolLevel', 'ndkAbiFilters',
];

class _Issue {
  final String path;
  final String message;
  final String? fix;
  const _Issue(this.path, this.message, {this.fix});
}

class ValidateCommand extends Command<void> {
  @override
  final name = 'validate';

  @override
  final description = 'Validate annspec.yaml structure and report any issues.';

  ValidateCommand() {
    argParser.addOption('project', abbr: 'p', defaultsTo: '.');
    argParser.addOption(
      'format',
      allowed: ['human', 'json'],
      defaultsTo: 'human',
      help: 'Output format: "human" (default) or "json" for machine consumers.',
    );
  }

  @override
  Future<void> run() async {
    final jsonMode = (argResults!['format'] as String) == 'json';
    // Wrap everything so stdout is always valid JSON in json mode.
    try {
      await _runValidate(jsonMode);
    } catch (e) {
      if (jsonMode) {
        _printJson('annspec.yaml', [], [], parseError: 'Internal error: $e');
      } else {
        rethrow;
      }
      exitCode = 1;
    }
  }

  Future<void> _runValidate(bool jsonMode) async {
    final projectRoot = argResults!['project'] as String;
    final specPath = p.join(projectRoot, 'annspec.yaml');

    if (!jsonMode) {
      print('ANN Flavor — validating annspec.yaml in $projectRoot');
      print('');
    }

    final errors   = <_Issue>[];
    final warnings = <_Issue>[];

    core.AnnSpec spec;
    YamlMap rawDoc;

    try {
      spec   = AnnspecReader.read(projectRoot);
      rawDoc = loadYaml(File(specPath).readAsStringSync()) as YamlMap;
    } catch (e) {
      final msg = '$e'.replaceFirst('Exception: ', '');
      if (jsonMode) {
        _printJson(specPath, [], [], parseError: msg);
        exitCode = 1;
      } else {
        print('  ✗  Cannot read annspec.yaml:\n     $msg');
      }
      return;
    }

    // Warn if enabled: false — validation still runs on the whole file.
    final specEnabled = rawDoc['enabled'] as bool? ?? true;
    if (!specEnabled) {
      warnings.add(_Issue(
        'enabled',
        'annspec.yaml is disabled (enabled: false) — '
            'all plugins will skip this file and apply no configuration.',
        fix: 'Set  enabled: true  to re-activate, '
            'or remove the field (defaults to true).',
      ));
    }

    final rawApp = rawDoc['app'] as YamlMap?;

    final annspecFlavorKeys = <String, Set<String>>{};

    if (spec.app.android != null) {
      final android = spec.app.android!;
      annspecFlavorKeys['android'] = android.flavors.keys.toSet();
      _validateAndroid(android, rawApp?['android'] as YamlMap?, errors, warnings);
    }
    if (spec.app.ios != null) {
      final ios = spec.app.ios!;
      annspecFlavorKeys['ios'] = ios.flavors.keys.toSet();
      _validateIos(ios, rawApp?['ios'] as YamlMap?, errors, warnings);
    }

    _checkFirebaseIntegration(spec, errors, warnings);
    _checkDeprecatedFirebaseFields(rawDoc, errors);
    final testspecResult = validateTestspec(
      findTestspecFile(projectRoot),
      projectRoot,
      annspecFlavorKeys: annspecFlavorKeys,
    );

    if (jsonMode) {
      _printJson(specPath, errors, warnings, testspec: testspecResult);
    } else {
      _printResults(errors, warnings);
      _printTestspecResults(testspecResult);
    }
    if (errors.isNotEmpty || testspecResult.errors.isNotEmpty) exitCode = 1;
  }

  // ── Android platform ───────────────────────────────────────────────────────

  void _validateAndroid(
    core.AndroidPlatform platform,
    YamlMap? rawPlatform,
    List<_Issue> errors,
    List<_Issue> warnings,
  ) {
    const plat = 'android';
    const basePath = 'app.$plat';

    if (platform.defaults.id == null) {
      errors.add(_Issue(
        '$basePath.default',
        '"id" is required but not set.',
        fix: 'Add:  id: "com.example.myapp"  under  $basePath.default',
      ));
    }
    if (platform.flavors.isEmpty) {
      errors.add(_Issue(
        '$basePath.flavor',
        'No flavors defined — at least one flavor is required.',
        fix: 'Add a flavor block under  $basePath.flavor',
      ));
    }

    final hasRelease = platform.defaults.firebase != null ||
        platform.defaults.buildTypes['release']?.firebase != null ||
        platform.flavors.values.any((f) =>
            f.firebase != null || f.buildTypes['release']?.firebase != null);
    if (hasRelease && platform.defaults.credentials?.signing?.keyFile == null) {
      warnings.add(_Issue(
        '$basePath.default.credentials.signing',
        '"key_file" is not set — release builds may fail to sign.',
        fix: 'Add:  signing:\n          key_file: "keys/keystore.properties"',
      ));
    }

    for (final bt in const ['release', 'debug']) {
      final resolved = core.AnnSpecResolver.resolveAndroidFlavor(
          const core.AndroidFlavor(), platform.defaults, bt);
      _checkFirebase('$basePath.default.build_types.$bt.firebase',
          platform.defaults.buildTypes[bt]?.firebase ?? platform.defaults.firebase,
          plat, errors, warnings,
          resolvedServiceAccount: resolved.effectiveFirebase?.serviceAccount);
    }

    final rawDefault = rawPlatform?['default'] as YamlMap?;
    _checkBuildTypeFields('$basePath.default', plat,
        rawDefault?['build_types'] as YamlMap?, errors);

    for (final entry in platform.flavors.entries) {
      _validateAndroidFlavor(entry.key, entry.value, platform.defaults,
          (rawPlatform?['flavor'] as YamlMap?)?[entry.key] as YamlMap?, errors, warnings);
    }
  }

  void _validateAndroidFlavor(
    String flv,
    core.AndroidFlavor flavor,
    core.AndroidDefault defaults,
    YamlMap? rawFlavor,
    List<_Issue> errors,
    List<_Issue> warnings,
  ) {
    const plat = 'android';
    final basePath = 'app.$plat.flavor.$flv';

    _checkCommonFlavorFields(basePath, flv, flavor.name, flavor.mainFile,
        flavor.versionName, flavor.versionCode, flavor.id, flavor.idSuffix, errors, warnings);

    for (final bt in const ['release', 'debug']) {
      final resolved = core.AnnSpecResolver.resolveAndroidFlavor(flavor, defaults, bt);
      _checkFirebase('$basePath.build_types.$bt.firebase',
          flavor.buildTypes[bt]?.firebase ?? flavor.firebase,
          plat, errors, warnings,
          resolvedServiceAccount: resolved.effectiveFirebase?.serviceAccount);
    }

    if (flavor.stores?.appStore?.appleId != null) {
      errors.add(_Issue(
        '$basePath.stores.app_store',
        '"app_store" is iOS-only — not valid under Android.',
        fix: 'Remove the app_store block from  $basePath.stores',
      ));
    }

    final priority = flavor.stores?.googlePlay?.priority;
    if (priority != null && (priority < 1 || priority > 5)) {
      errors.add(_Issue(
        '$basePath.stores.google_play.priority',
        '"priority" must be an integer from 1 to 5 (got: $priority).',
        fix: '1 = background update (lowest urgency), '
            '5 = immediate/forced update (highest urgency).',
      ));
    }

    _checkBuildTypeFields(basePath, plat, rawFlavor?['build_types'] as YamlMap?, errors);
  }

  // ── iOS platform ────────────────────────────────────────────────────────────

  void _validateIos(
    core.IosPlatform platform,
    YamlMap? rawPlatform,
    List<_Issue> errors,
    List<_Issue> warnings,
  ) {
    const plat = 'ios';
    const basePath = 'app.$plat';

    if (platform.defaults.id == null) {
      errors.add(_Issue(
        '$basePath.default',
        '"id" is required but not set.',
        fix: 'Add:  id: "com.example.myapp"  under  $basePath.default',
      ));
    }
    if (platform.flavors.isEmpty) {
      errors.add(_Issue(
        '$basePath.flavor',
        'No flavors defined — at least one flavor is required.',
        fix: 'Add a flavor block under  $basePath.flavor',
      ));
    }

    final hasRelease = platform.defaults.firebase != null ||
        platform.defaults.buildTypes['release']?.firebase != null ||
        platform.flavors.values.any((f) =>
            f.firebase != null || f.buildTypes['release']?.firebase != null);
    if (hasRelease && platform.defaults.credentials?.signing?.teamId == null) {
      warnings.add(_Issue(
        '$basePath.default.credentials.signing',
        '"team_id" is not set — release builds may fail to sign.',
        fix: 'Add:  signing:\n          team_id: "YOURTEAMID"',
      ));
    }

    for (final bt in const ['release', 'debug']) {
      final resolved = core.AnnSpecResolver.resolveIosFlavor(
          const core.IosFlavor(), platform.defaults, bt);
      _checkFirebase('$basePath.default.build_types.$bt.firebase',
          platform.defaults.buildTypes[bt]?.firebase ?? platform.defaults.firebase,
          plat, errors, warnings,
          resolvedServiceAccount: resolved.effectiveFirebase?.serviceAccount);
    }

    final rawDefault = rawPlatform?['default'] as YamlMap?;
    _checkBuildTypeFields('$basePath.default', plat,
        rawDefault?['build_types'] as YamlMap?, errors);

    for (final entry in platform.flavors.entries) {
      _validateIosFlavor(entry.key, entry.value, platform.defaults,
          (rawPlatform?['flavor'] as YamlMap?)?[entry.key] as YamlMap?, errors, warnings);
    }
  }

  void _validateIosFlavor(
    String flv,
    core.IosFlavor flavor,
    core.IosDefault defaults,
    YamlMap? rawFlavor,
    List<_Issue> errors,
    List<_Issue> warnings,
  ) {
    const plat = 'ios';
    final basePath = 'app.$plat.flavor.$flv';

    _checkCommonFlavorFields(basePath, flv, flavor.name, flavor.mainFile,
        flavor.versionName, flavor.versionCode, flavor.id, flavor.idSuffix, errors, warnings);

    for (final bt in const ['release', 'debug']) {
      final resolved = core.AnnSpecResolver.resolveIosFlavor(flavor, defaults, bt);
      _checkFirebase('$basePath.build_types.$bt.firebase',
          flavor.buildTypes[bt]?.firebase ?? flavor.firebase,
          plat, errors, warnings,
          resolvedServiceAccount: resolved.effectiveFirebase?.serviceAccount);
    }

    if (flavor.stores?.googlePlay != null) {
      errors.add(_Issue(
        '$basePath.stores.google_play',
        '"google_play" is Android-only — not valid under iOS.',
        fix: 'Remove the google_play block from  $basePath.stores',
      ));
    }
    if (flavor.stores?.samsungGalaxy?.appId != null) {
      errors.add(_Issue(
        '$basePath.stores.samsung_galaxy',
        '"samsung_galaxy" is Android-only — not valid under iOS.',
        fix: 'Remove the samsung_galaxy block from  $basePath.stores',
      ));
    }
    if (flavor.stores?.amazon?.appId != null) {
      errors.add(_Issue(
        '$basePath.stores.amazon',
        '"amazon" is Android-only — not valid under iOS.',
        fix: 'Remove the amazon block from  $basePath.stores',
      ));
    }

    _checkBuildTypeFields(basePath, plat, rawFlavor?['build_types'] as YamlMap?, errors);
  }

  // ── Shared flavor field checks ─────────────────────────────────────────────

  void _checkCommonFlavorFields(
    String basePath,
    String flv,
    String? name,
    String? mainFile,
    String? versionName,
    int? versionCode,
    String? id,
    String idSuffix,
    List<_Issue> errors,
    List<_Issue> warnings,
  ) {
    if (name == null) {
      errors.add(_Issue(
        '$basePath.name',
        '"name" is required but not set.',
        fix: 'Add:  name: "My App ${_titleCase(flv)}"',
      ));
    }
    if (mainFile == null) {
      errors.add(_Issue(
        '$basePath.main_file',
        '"main_file" is required but not set.',
        fix: 'Add:  main_file: "lib/flavors/main_$flv.dart"',
      ));
    }
    if (versionName == null) {
      errors.add(_Issue(
        '$basePath.version_name',
        '"version_name" is required but not set.',
        fix: 'Add:  version_name: "1.0.0"',
      ));
    }
    if (versionCode == null) {
      errors.add(_Issue(
        '$basePath.version_code',
        '"version_code" is required but not set.',
        fix: 'Add:  version_code: 100000',
      ));
    }

    final hasIdSuffix = idSuffix.isNotEmpty;
    if (id != null && hasIdSuffix) {
      errors.add(_Issue(
        basePath,
        'Both "id" and "id_suffix" are set — use one, not both.',
        fix: 'Use "id" to override the full bundle ID, '
            'or "id_suffix" to append to default.id.  Remove one.',
      ));
    }
    if (id == null && !hasIdSuffix) {
      warnings.add(_Issue(
        basePath,
        'Neither "id" nor "id_suffix" is set — this flavor will share the same bundle ID as default.',
        fix: 'Add:  id_suffix: ".$flv"  to make the ID unique, '
            'or  id: "com.example.$flv"  for a full override.',
      ));
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  void _checkFirebase(
    String path,
    core.FirebaseConfig? firebase,
    String platformKey,
    List<_Issue> errors,
    List<_Issue> warnings, {
    required String? resolvedServiceAccount,
  }) {
    if (firebase == null) return;

    if (firebase.configFile != null && firebase.projectId != null) {
      errors.add(_Issue(
        path,
        '"config_file" and "project_id" are both set — use one, not both.',
        fix: 'Use "config_file" (path to google-services.json) on Android, '
            'or "project_id" (Firebase project ID) for flutterfire configure.',
      ));
    }
    if (platformKey == 'ios' && firebase.configFile != null) {
      errors.add(_Issue(
        path,
        '"config_file" is Android-only — iOS downloads its config via "project_id" at build time.',
        fix: 'Replace  config_file: "..."  with  project_id: "your-firebase-project-id"',
      ));
    }
    // project_id mode requires a service_account resolved via the 4-level cascade;
    // without it flutterfire configure will fail (REQ-FIRE-00100).
    if (firebase.projectId != null && resolvedServiceAccount == null) {
      warnings.add(_Issue(
        path,
        '"project_id" is set but no "service_account" resolves for this build — '
            'flutterfire configure will fail without credentials.',
        fix: 'Add:  service_account: "keys/firebase-sa.json"  '
            'at default.firebase, default.build_types.<bt>.firebase, '
            'flavor.firebase, or flavor.build_types.<bt>.firebase level.',
      ));
    }
    // service_account with config_file mode is ineffective — service_account is only used
    // by flutterfire configure, which only runs in project_id mode.
    if (firebase.serviceAccount != null && firebase.configFile != null && firebase.projectId == null) {
      warnings.add(_Issue(
        path,
        '"service_account" is set but the mode is "config_file" — '
            'service_account is only used with project_id mode.',
        fix: 'Remove "service_account" or switch to "project_id" mode.',
      ));
    }
  }

  // ── Firebase integration gate ──────────────────────────────────────────────

  void _checkFirebaseIntegration(
    core.AnnSpec spec,
    List<_Issue> errors,
    List<_Issue> warnings,
  ) {
    if (spec.app.integrations?.firebase != true) return;

    // integrations.firebase: true but no firebase blocks found anywhere is likely a mistake.
    bool platformHasFirebase(dynamic defaults, Map flavors) {
      if (defaults.firebase != null) return true;
      if (defaults.buildTypes['release']?.firebase != null) return true;
      if (defaults.buildTypes['debug']?.firebase != null) return true;
      for (final f in flavors.values) {
        if (f.firebase != null) return true;
        if (f.buildTypes['release']?.firebase != null) return true;
        if (f.buildTypes['debug']?.firebase != null) return true;
      }
      return false;
    }

    final hasAny =
        (spec.app.android != null &&
            platformHasFirebase(spec.app.android!.defaults, spec.app.android!.flavors)) ||
        (spec.app.ios != null &&
            platformHasFirebase(spec.app.ios!.defaults, spec.app.ios!.flavors)) ||
        (spec.app.web != null &&
            platformHasFirebase(spec.app.web!.defaults, spec.app.web!.flavors)) ||
        (spec.app.windows != null &&
            platformHasFirebase(spec.app.windows!.defaults, spec.app.windows!.flavors));

    if (!hasAny) {
      warnings.add(_Issue(
        'integrations.firebase',
        'integrations.firebase is true but no firebase blocks are configured on any platform.',
        fix: 'Add firebase blocks under build_types, or set integrations.firebase: false.',
      ));
    }
  }

  // ── Deprecated field scanner ───────────────────────────────────────────────

  // Scan the raw YAML for deprecated fields. No backward compatibility (REQ-FIRE-00180) —
  // these are errors, not warnings, and no automatic migration is performed.
  void _checkDeprecatedFirebaseFields(YamlMap rawDoc, List<_Issue> errors) {
    // Top-level app.general.firebase_token_file
    final general = (rawDoc['app'] as YamlMap?)?['general'] as YamlMap?;
    if (general != null && general.containsKey('firebase_token_file')) {
      errors.add(_Issue(
        'app.general.firebase_token_file',
        '"firebase_token_file" was removed in v0.3.0 — machine auth is no longer supported.',
        fix: 'Add  service_account: "keys/firebase-sa.json"  inside each build_type.firebase block. '
            'See the Firebase Setup guide for service account creation steps.',
      ));
    }
    _scanForDeprecatedFirebase(rawDoc, '', errors);
  }

  static const _knownFirebaseKeys = {
    'config_file', 'project_id', 'service_account', 'target',
    // 'file' is intentionally absent — caught separately as a deprecated-field error.
  };

  void _scanForDeprecatedFirebase(dynamic node, String path, List<_Issue> errors) {
    if (node is! YamlMap) return;
    for (final entry in node.entries) {
      final key = entry.key as String;
      final childPath = path.isEmpty ? key : '$path.$key';
      if (key == 'firebase' && entry.value is YamlMap) {
        final fb = entry.value as YamlMap;
        if (fb.containsKey('file')) {
          errors.add(_Issue(
            '$childPath.file',
            '"firebase.file" was renamed to "firebase.config_file" in v0.3.0.',
            fix: 'Rename  file: "..."  to  config_file: "..."  in this firebase block.',
          ));
        }
        for (final fbKey in fb.keys.cast<String>()) {
          if (!_knownFirebaseKeys.contains(fbKey) && fbKey != 'file') {
            errors.add(_Issue(
              '$childPath.$fbKey',
              '"$fbKey" is not a recognised firebase field.',
              fix: 'Valid fields are: config_file, project_id, service_account, target.',
            ));
          }
        }
      }
      _scanForDeprecatedFirebase(entry.value, childPath, errors);
    }
  }

  void _checkBuildTypeFields(
    String contextPath,
    String platformKey,
    YamlMap? buildTypesRaw,
    List<_Issue> errors,
  ) {
    if (buildTypesRaw == null || platformKey != 'ios') return;

    for (final btEntry in buildTypesRaw.entries) {
      final btKey = btEntry.key as String;
      final btMap = btEntry.value as YamlMap?;
      if (btMap == null) continue;

      for (final field in _androidOnlyBuildTypeFields) {
        if (btMap.containsKey(field)) {
          errors.add(_Issue(
            '$contextPath.build_types.$btKey.$field',
            '"$field" is Android-only — not valid inside an iOS build_type.',
            fix: 'Remove "$field" from  $contextPath.build_types.$btKey',
          ));
        }
      }
    }
  }

  String _titleCase(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  // ── Output ─────────────────────────────────────────────────────────────────

  void _printJson(
    String specPath,
    List<_Issue> errors,
    List<_Issue> warnings, {
    String? parseError,
    TestspecResult? testspec,
  }) {
    final errList = parseError != null
        ? [
            {'severity': 'error', 'path': 'annspec.yaml', 'message': parseError, 'fix': null}
          ]
        : errors
            .map((e) => {'severity': 'error', 'path': e.path, 'message': e.message, 'fix': e.fix})
            .toList();

    final warnList = warnings
        .map((w) => {'severity': 'warning', 'path': w.path, 'message': w.message, 'fix': w.fix})
        .toList();

    Map<String, dynamic>? testspecJson;
    if (testspec != null) {
      if (!testspec.present) {
        testspecJson = {'present': false};
      } else {
        testspecJson = {
          'present': true,
          'valid': testspec.errors.isEmpty,
          'specPath': p.absolute(testspec.specPath!),
          'errors': testspec.errors
              .map((e) => {'severity': 'error', 'path': e.path, 'message': e.message, 'fix': e.fix})
              .toList(),
          'warnings': testspec.warnings
              .map((w) => {'severity': 'warning', 'path': w.path, 'message': w.message, 'fix': w.fix})
              .toList(),
          'infos': testspec.infos
              .map((i) => {'severity': 'info', 'path': i.path, 'message': i.message, 'fix': i.fix})
              .toList(),
        };
      }
    }

    final overall = errList.isEmpty && (testspec == null || testspec.errors.isEmpty);

    print(jsonEncode({
      'valid': overall,
      'specPath': p.absolute(specPath),
      'errors': errList,
      'warnings': warnList,
      if (testspecJson != null) 'testspec': testspecJson,
    }));
  }

  void _printResults(List<_Issue> errors, List<_Issue> warnings) {
    if (warnings.isNotEmpty) {
      print('  ⚠  ${warnings.length} warning${warnings.length == 1 ? '' : 's'}:');
      for (final w in warnings) _printIssue(w, isError: false);
      print('');
    }

    if (errors.isEmpty) {
      print('  ✅  annspec.yaml is valid${warnings.isEmpty ? '.' : ' (with warnings above).'}');
    } else {
      print('  ✗  ${errors.length} error${errors.length == 1 ? '' : 's'}:');
      for (final e in errors) _printIssue(e, isError: true);
    }
  }

  void _printTestspecResults(TestspecResult result) {
    print('');
    if (!result.present) {
      print('  ℹ  anntestspec.yaml not found — test spec validation skipped.');
      return;
    }

    if (result.warnings.isNotEmpty) {
      print('  ⚠  anntestspec.yaml — ${result.warnings.length} warning${result.warnings.length == 1 ? '' : 's'}:');
      for (final w in result.warnings) _printTestspecIssue(w, icon: '⚠');
      print('');
    }
    if (result.infos.isNotEmpty) {
      print('  ℹ  anntestspec.yaml — ${result.infos.length} info item${result.infos.length == 1 ? '' : 's'}:');
      for (final i in result.infos) _printTestspecIssue(i, icon: 'ℹ');
      print('');
    }

    if (result.errors.isEmpty) {
      final suffix = result.warnings.isEmpty && result.infos.isEmpty ? '.' : ' (with items above).';
      print('  ✅  anntestspec.yaml is valid$suffix');
    } else {
      print('  ✗  anntestspec.yaml — ${result.errors.length} error${result.errors.length == 1 ? '' : 's'}:');
      for (final e in result.errors) _printTestspecIssue(e, icon: '✗');
    }
  }

  void _printTestspecIssue(TestspecIssue issue, {required String icon}) {
    print('');
    print('    $icon  ${issue.path}');
    print('       ${issue.message}');
    if (issue.fix != null) print('       → ${issue.fix}');
  }

  void _printIssue(_Issue issue, {required bool isError}) {
    final icon = isError ? '✗' : '⚠';
    print('');
    print('    $icon  ${issue.path}');
    print('       ${issue.message}');
    if (issue.fix != null) {
      print('       → ${issue.fix}');
    }
  }
}
