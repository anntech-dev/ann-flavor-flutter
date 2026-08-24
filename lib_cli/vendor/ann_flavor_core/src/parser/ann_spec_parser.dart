import 'dart:io';
import 'package:yaml/yaml.dart';
import '../model/ann_spec_model.dart';

/// Single source of truth for parsing annspec.yaml.
///
/// Three entry points:
///   [parse]      — from raw YAML text (String)
///   [parseFile]  — from a file path
///   [fromMap]    — from a pre-parsed Map (e.g. in-memory UI data)
///
/// After parsing, pass the [AnnSpec] to [AnnSpecResolver.resolveAll] to obtain
/// all resolved (effective) values per flavor × build-type.
class AnnSpecParser {
  static AnnSpec parse(String yamlString) {
    final raw = loadYaml(yamlString);
    return fromMap(_asMap(raw));
  }

  static Future<AnnSpec> parseFile(String path) async {
    final content = await File(path).readAsString();
    return parse(content);
  }

  static AnnSpec fromMap(Map<String, dynamic> raw) {
    final toolingMap = _map(raw, 'tooling');
    return AnnSpec(
      app:    _parseAnnApp(_map(raw, 'app')),
      enabled:     raw['enabled'] as bool? ?? true,
      debugConfig: _parseDebugConfig(_map(raw, 'debug')),
      tooling:     toolingMap.isEmpty ? null : _parseTooling(toolingMap),
    );
  }

  static ToolingConfig _parseTooling(Map<String, dynamic> m) => ToolingConfig(
    gradlePlugin: m['gradle_plugin'] as String?,
    cocoapodsPlugin: m['cocoapods_plugin'] as String?,
    fastlanePlugin: m['fastlane_plugin'] as String?,
  );

  // ── AnnApp ─────────────────────────────────────────────────────────────────

  static AnnApp _parseAnnApp(Map<String, dynamic> m) => AnnApp(
    android:      m.containsKey('android')      ? _parseAndroid(_map(m, 'android'))           : null,
    ios:          m.containsKey('ios')           ? _parseIos(_map(m, 'ios'))                   : null,
    web:          m.containsKey('web')           ? _parseWeb(_map(m, 'web'))                   : null,
    windows:      m.containsKey('windows')       ? _parseWindows(_map(m, 'windows'))           : null,
    general:      m.containsKey('general')       ? _parseGeneral(_map(m, 'general'))           : null,
    integrations: m.containsKey('integrations') ? _parseIntegrations(_map(m, 'integrations')) : null,
  );

  static AnnIntegrations _parseIntegrations(Map<String, dynamic> m) => AnnIntegrations(
    fastlane: m['fastlane'] as bool? ?? false,
    melos:    m['melos']    as bool? ?? false,
    firebase: m['firebase'] as bool? ?? false,
  );

  // ── Android ────────────────────────────────────────────────────────────────

  static AndroidPlatform _parseAndroid(Map<String, dynamic> m) => AndroidPlatform(
    defaults: _parseAndroidDefault(_map(m, 'default')),
    flavors:  _parseFlavors(m, 'flavor', _parseAndroidFlavor),
  );

  static AndroidDefault _parseAndroidDefault(Map<String, dynamic> m) => AndroidDefault(
    id:          m['id'] as String?,
    name:        m['name'] as String?,
    versionName: m['version_name']?.toString(),
    versionCode: _parseInt(m['version_code']),
    mainFile:    m['main_file'] as String?,
    admob:       _parseAdmobConfig(_map(m, 'admob')),
    icon:        m['icon'] as String?,
    firebase:    m.containsKey('firebase') ? _parseFirebaseConfig(_map(m, 'firebase')) : null,
    sdk:         m.containsKey('sdk') ? _parseAndroidSdk(_map(m, 'sdk')) : null,
    credentials: m.containsKey('credentials') ? _parseAndroidCredentials(_map(m, 'credentials')) : null,
    buildTypes:  _parseBuildTypeConfigs(_map(m, 'build_types')),
    custom:      _parseCustomConfig(_map(m, 'custom')),
    dartDefines: _parseDartDefines(_map(m, 'dart_defines')),
  );

  static AndroidFlavor _parseAndroidFlavor(Map<String, dynamic> m) => AndroidFlavor(
    id:          m['id'] as String?,
    idSuffix:    (m['id_suffix'] as String?) ?? '',
    name:        m['name'] as String?,
    nameSuffix:  (m['name_suffix'] as String?) ?? '',
    versionName: m['version_name']?.toString(),
    versionCode: _parseInt(m['version_code']),
    mainFile:    m['main_file'] as String?,
    admob:       _parseAdmobConfig(_map(m, 'admob')),
    icon:        m['icon'] as String?,
    firebase:    m.containsKey('firebase') ? _parseFirebaseConfig(_map(m, 'firebase')) : null,
    stores:      m.containsKey('stores') ? _parseFlavorStores(_map(m, 'stores')) : null,
    credentials: m.containsKey('credentials') ? _parseAndroidCredentials(_map(m, 'credentials')) : null,
    buildTypes:  _parseBuildTypeConfigs(_map(m, 'build_types')),
    custom:      _parseCustomConfig(_map(m, 'custom')),
    dartDefines: _parseDartDefines(_map(m, 'dart_defines')),
  );

  static AndroidSdk _parseAndroidSdk(Map<String, dynamic> m) => AndroidSdk(
    minSdk:     _parseInt(m['minSdk']),
    compileSdk: _parseInt(m['compileSdk']),
    targetSdk:  _parseInt(m['targetSdk']),
  );

  static AndroidCredentials _parseAndroidCredentials(Map<String, dynamic> m) => AndroidCredentials(
    signing:       m.containsKey('signing')
                     ? AndroidSigning(keyFile: _map(m, 'signing')['key_file'] as String?)
                     : null,
    googlePlay:    m.containsKey('google_play')
                     ? GooglePlayCredentials(apiKey: _map(m, 'google_play')['api_key'] as String?)
                     : null,
    samsungGalaxy: m.containsKey('samsung_galaxy')
                     ? SamsungGalaxyCredentials(
                         sellerId: _map(m, 'samsung_galaxy')['seller_id'] as String?,
                         apiKey:   _map(m, 'samsung_galaxy')['api_key'] as String?,
                       )
                     : null,
    amazon:        m.containsKey('amazon')
                     ? AmazonCredentials(
                         clientId:     _map(m, 'amazon')['client_id'] as String?,
                         clientSecret: _map(m, 'amazon')['client_secret'] as String?,
                       )
                     : null,
  );

  // ── iOS ────────────────────────────────────────────────────────────────────

  static IosPlatform _parseIos(Map<String, dynamic> m) => IosPlatform(
    defaults: _parseIosDefault(_map(m, 'default')),
    flavors:  _parseFlavors(m, 'flavor', _parseIosFlavor),
  );

  static IosDefault _parseIosDefault(Map<String, dynamic> m) => IosDefault(
    id:          m['id'] as String?,
    name:        m['name'] as String?,
    versionName: m['version_name']?.toString(),
    versionCode: _parseInt(m['version_code']),
    mainFile:    m['main_file'] as String?,
    admob:       _parseAdmobConfig(_map(m, 'admob')),
    icon:        m['icon'] as String?,
    firebase:    m.containsKey('firebase') ? _parseFirebaseConfig(_map(m, 'firebase')) : null,
    credentials: m.containsKey('credentials') ? _parseIosCredentials(_map(m, 'credentials')) : null,
    buildTypes:  _parseBuildTypeConfigs(_map(m, 'build_types')),
    custom:      _parseCustomConfig(_map(m, 'custom')),
    dartDefines: _parseDartDefines(_map(m, 'dart_defines')),
  );

  static IosFlavor _parseIosFlavor(Map<String, dynamic> m) => IosFlavor(
    id:          m['id'] as String?,
    idSuffix:    (m['id_suffix'] as String?) ?? '',
    name:        m['name'] as String?,
    nameSuffix:  (m['name_suffix'] as String?) ?? '',
    versionName: m['version_name']?.toString(),
    versionCode: _parseInt(m['version_code']),
    mainFile:    m['main_file'] as String?,
    admob:       _parseAdmobConfig(_map(m, 'admob')),
    icon:        m['icon'] as String?,
    firebase:    m.containsKey('firebase') ? _parseFirebaseConfig(_map(m, 'firebase')) : null,
    stores:      m.containsKey('stores') ? _parseFlavorStores(_map(m, 'stores')) : null,
    credentials: m.containsKey('credentials') ? _parseIosCredentials(_map(m, 'credentials')) : null,
    buildTypes:  _parseBuildTypeConfigs(_map(m, 'build_types')),
    custom:      _parseCustomConfig(_map(m, 'custom')),
    dartDefines: _parseDartDefines(_map(m, 'dart_defines')),
  );

  static IosCredentials _parseIosCredentials(Map<String, dynamic> m) => IosCredentials(
    signing:  m.containsKey('signing')
                ? IosSigning(teamId: _map(m, 'signing')['team_id'] as String?)
                : null,
    appStore: m.containsKey('app_store')
                ? AppStoreCredentials(
                    apiKey:                          _map(m, 'app_store')['api_key'] as String?,
                    exportOptionsPlist:              _map(m, 'app_store')['export_options_plist'] as String?,
                    exportOptionsTeamId:             _map(m, 'app_store')['export_options_team_id'] as String?,
                    exportOptionsSigningCertificate: _map(m, 'app_store')['export_options_signing_certificate'] as String?,
                  )
                : null,
  );

  // ── Web ────────────────────────────────────────────────────────────────────

  static WebPlatform _parseWeb(Map<String, dynamic> m) => WebPlatform(
    defaults: _parseWebDefault(_map(m, 'default')),
    flavors:  _parseFlavors(m, 'flavor', _parseWebFlavor),
  );

  static WebDefault _parseWebDefault(Map<String, dynamic> m) => WebDefault(
    id: m['id'] as String?, name: m['name'] as String?,
    versionName: m['version_name']?.toString(), versionCode: _parseInt(m['version_code']),
    mainFile:   m['main_file'] as String?,
    icon:       m['icon'] as String?,
    cloudflare: _parseCloudflare(_map(m, 'cloudflare')),
    firebase:   m.containsKey('firebase') ? _parseFirebaseConfig(_map(m, 'firebase')) : null,
    buildTypes: _parseBuildTypeConfigs(_map(m, 'build_types')),
    custom:     _parseCustomConfig(_map(m, 'custom')),
    dartDefines: _parseDartDefines(_map(m, 'dart_defines')),
  );

  static WebFlavor _parseWebFlavor(Map<String, dynamic> m) => WebFlavor(
    id: m['id'] as String?, idSuffix: (m['id_suffix'] as String?) ?? '',
    name: m['name'] as String?, nameSuffix: (m['name_suffix'] as String?) ?? '',
    versionName: m['version_name']?.toString(), versionCode: _parseInt(m['version_code']),
    mainFile: m['main_file'] as String?,
    icon:     m['icon'] as String?,
    cloudflare: _parseCloudflare(_map(m, 'cloudflare')),
    firebase:   m.containsKey('firebase') ? _parseFirebaseConfig(_map(m, 'firebase')) : null,
    buildTypes: _parseBuildTypeConfigs(_map(m, 'build_types')),
    custom:     _parseCustomConfig(_map(m, 'custom')),
    dartDefines: _parseDartDefines(_map(m, 'dart_defines')),
  );

  static CloudflareConfig? _parseCloudflare(Map<String, dynamic> m) {
    if (m.isEmpty) return null;
    return CloudflareConfig(
      projectName: m['project_name'] as String?,
      accountId:   m['account_id'] as String?,
      branch:      m['branch'] as String?,
      mode:        m['mode'] as String?,
    );
  }

  // ── Windows ────────────────────────────────────────────────────────────────

  static WindowsPlatform _parseWindows(Map<String, dynamic> m) => WindowsPlatform(
    defaults: _parseWindowsDefault(_map(m, 'default')),
    flavors:  _parseFlavors(m, 'flavor', _parseWindowsFlavor),
  );

  static WindowsDefault _parseWindowsDefault(Map<String, dynamic> m) => WindowsDefault(
    id: m['id'] as String?, name: m['name'] as String?,
    versionName: m['version_name']?.toString(), versionCode: _parseInt(m['version_code']),
    mainFile:   m['main_file'] as String?,
    firebase:   m.containsKey('firebase') ? _parseFirebaseConfig(_map(m, 'firebase')) : null,
    buildTypes: _parseBuildTypeConfigs(_map(m, 'build_types')),
    custom:     _parseCustomConfig(_map(m, 'custom')),
    dartDefines: _parseDartDefines(_map(m, 'dart_defines')),
  );

  static WindowsFlavor _parseWindowsFlavor(Map<String, dynamic> m) => WindowsFlavor(
    id: m['id'] as String?, idSuffix: (m['id_suffix'] as String?) ?? '',
    name: m['name'] as String?, nameSuffix: (m['name_suffix'] as String?) ?? '',
    versionName: m['version_name']?.toString(), versionCode: _parseInt(m['version_code']),
    mainFile: m['main_file'] as String?,
    firebase:   m.containsKey('firebase') ? _parseFirebaseConfig(_map(m, 'firebase')) : null,
    buildTypes: _parseBuildTypeConfigs(_map(m, 'build_types')),
    custom:     _parseCustomConfig(_map(m, 'custom')),
    dartDefines: _parseDartDefines(_map(m, 'dart_defines')),
  );

  // ── Shared parsers ─────────────────────────────────────────────────────────

  static AdmobConfig? _parseAdmobConfig(Map<String, dynamic> m) =>
    m.isEmpty ? null : AdmobConfig(gmsAdsId: m['gms_ads_id'] as String?);

  static CustomConfig _parseCustomConfig(Map<String, dynamic> m) {
    if (m.isEmpty) return const {};
    return m.map((groupName, groupVal) {
      final groupMap = (groupVal as Map).map<String, dynamic>(
        (k, v) => MapEntry(k as String, _normalizeCustomValue(v)),
      );
      return MapEntry(groupName, groupMap);
    });
  }

  static dynamic _normalizeCustomValue(dynamic v) {
    if (v is List) return v.map((e) => e?.toString() ?? '').toList();
    return v;
  }

  static const _dartDefinesActionKeys = {'compile', 'run', 'deploy'};

  /// Parses `dart_defines:` — plain string entries are the common map; the three
  /// reserved sub-keys `compile`/`run`/`deploy` (each a nested map) become the
  /// corresponding action scope. Values are coerced to strings.
  static DartDefines _parseDartDefines(Map<String, dynamic> m) {
    if (m.isEmpty) return DartDefines.empty;
    Map<String, String> stringMap(dynamic raw) {
      if (raw is! Map) return const {};
      return raw.map((k, v) => MapEntry(k.toString(), v?.toString() ?? ''));
    }
    final common = Map.fromEntries(
      m.entries.where((e) => !_dartDefinesActionKeys.contains(e.key)),
    ).map((k, v) => MapEntry(k, v?.toString() ?? ''));
    return DartDefines(
      common: common,
      compile: stringMap(m['compile']),
      run: stringMap(m['run']),
      deploy: stringMap(m['deploy']),
    );
  }

  static FirebaseConfig _parseFirebaseConfig(Map<String, dynamic> m) => FirebaseConfig(
    projectId:      m['project_id'] as String?,
    configFile:     m['config_file'] as String?,
    serviceAccount: m['service_account'] as String?,
    target:         m['target'] as String?,
  );

  static AuthConfig _parseAuthConfig(Map<String, dynamic> m) => AuthConfig(
    clientId:         m['clientId'] as String?,
    reversedClientId: m['reversedClientId'] as String?,
    others:           Map<String, String>.from((_map(m, 'others'))),
  );

  static Map<String, BuildTypeConfig> _parseBuildTypeConfigs(Map<String, dynamic> m) =>
    m.map((k, v) {
      final vm = v is Map ? _asMap(v) : <String, dynamic>{};
      return MapEntry(k, BuildTypeConfig(
        idSuffix:               (vm['id_suffix'] as String?) ?? '',
        nameSuffix:             (vm['name_suffix'] as String?) ?? '',
        admob:                  _parseAdmobConfig(_map(vm, 'admob')),
        custom:                 _parseCustomConfig(_map(vm, 'custom')),
        firebase:               vm.containsKey('firebase') ? _parseFirebaseConfig(_map(vm, 'firebase')) : null,
        auth:                   vm.containsKey('auth')     ? _parseAuthConfig(_map(vm, 'auth'))         : null,
        minifyEnabled:          vm['minifyEnabled'] as bool?,
        shrinkResources:        vm['shrinkResources'] as bool?,
        lintCheckReleaseBuilds: vm['lintCheckReleaseBuilds'] as bool?,
        ndkVersion:             vm['ndkVersion'] as String?,
        ndkDebugSymbolLevel:    vm['ndkDebugSymbolLevel'] as String?,
        ndkAbiFilters:          _asList<String>(vm['ndkAbiFilters']),
        dartDefines:            _parseDartDefines(_map(vm, 'dart_defines')),
      ));
    });

  static FlavorStores _parseFlavorStores(Map<String, dynamic> m) => FlavorStores(
    googlePlay: m.containsKey('google_play')
      ? GooglePlayFlavorStore(priority: _parseInt(_map(m, 'google_play')['priority']))
      : null,
    samsungGalaxy: m.containsKey('samsung_galaxy')
      ? SamsungGalaxyFlavorStore(appId: _map(m, 'samsung_galaxy')['app_id'] as String?)
      : null,
    amazon: m.containsKey('amazon')
      ? AmazonFlavorStore(appId: _map(m, 'amazon')['app_id'] as String?)
      : null,
    appStore: m.containsKey('app_store')
      ? AppStoreFlavorStore(
          appleId: _map(m, 'app_store')['apple_id'] as String?,
          teamId:  _map(m, 'app_store')['team_id'] as String?,
        )
      : null,
  );

  static GeneralConfig _parseGeneral(Map<String, dynamic> m) => const GeneralConfig();

  static DebugConfig _parseDebugConfig(Map<String, dynamic> m) => DebugConfig(
    printDebug:                m['printDebug'] as bool? ?? false,
    printBuildAndFlavorInfo:   m['printBuildAndFlavorInfo'] as bool? ?? true,
    printSdkVersions:          m['printSdkVersions'] as bool? ?? true,
    printReleaseBuildTypeInfo: m['printReleaseBuildTypeInfo'] as bool? ?? false,
  );

  static Map<String, T> _parseFlavors<T>(
    Map<String, dynamic> parent,
    String key,
    T Function(Map<String, dynamic>) parse,
  ) {
    final raw = parent[key];
    if (raw is! Map) return const {};
    return _asMap(raw).map((k, v) => MapEntry(k, parse(v is Map ? _asMap(v) : {})));
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  static Map<String, dynamic> _map(Map<String, dynamic> m, String key) {
    final v = m[key];
    if (v is Map) return _asMap(v);
    return const {};
  }

  static Map<String, dynamic> _asMap(dynamic v) {
    if (v is Map<String, dynamic>) return v;
    if (v is YamlMap) return v.toMap();
    if (v is Map) return v.map((k, val) => MapEntry(k.toString(), val));
    return const {};
  }

  static int? _parseInt(dynamic v) {
    if (v is int) return v;
    if (v is String) return int.tryParse(v);
    return null;
  }

  static List<T> _asList<T>(dynamic v) {
    if (v is List) return v.whereType<T>().toList();
    return const [];
  }
}

extension on YamlMap {
  Map<String, dynamic> toMap() =>
    Map.fromEntries(entries.map((e) => MapEntry(e.key.toString(), e.value)));
}
