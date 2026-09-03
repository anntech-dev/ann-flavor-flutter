/// Opt-in unknown-key detection for `annspec.yaml`.
///
/// Dart has no runtime reflection available to a published package (`dart:mirrors` is
/// unsupported outside the standalone VM), so — unlike the Kotlin (`kotlin-reflect`)
/// and Ruby (`Struct#members`) checkers, which derive per-level valid keys
/// automatically — this checker uses a hand-written [_schema] registry.
///
/// Drift protection: `test/strict_mode_registry_drift_test.dart` uses `package:analyzer`
/// (dev-only, not shipped) to parse `ann_spec_model.dart`'s AST at test time and assert
/// every class's field list here matches the real model source. A registry that goes
/// stale fails that test, not silently — the same drift-proof guarantee Kotlin/Ruby get
/// from runtime reflection, enforced at test time instead.
///
/// Does NOT modify [AnnSpecParser] in any way — a fully separate, additive pass over
/// the same raw `Map<String, dynamic>` the parser already receives.
library;

/// One class's shape: its valid YAML keys (snake_case) and, for keys that nest into
/// another class, which one — either a direct nested object ([NestedKind.object]) or a
/// map of user-named entries whose values are that class ([NestedKind.map], e.g.
/// `flavor:`/`build_types:`).
class _ClassSchema {
  final Map<String, _Nested?> fields;
  const _ClassSchema(this.fields);
}

enum NestedKind { object, map }

class _Nested {
  final String targetClass;
  final NestedKind kind;
  const _Nested(this.targetClass, this.kind);
  const _Nested.object(this.targetClass) : kind = NestedKind.object;
  const _Nested.map(this.targetClass) : kind = NestedKind.map;
}

/// Fields whose value is a free-form map (arbitrary user-declared keys are data, not
/// schema) — exempted from unknown-key checking entirely, at any level.
///
/// info_plist and entitlements are additionally union types (an inline map OR
/// a plain file-path string), so even when their value IS a map, its keys are
/// raw Info.plist/entitlement keys the user controls, never our own schema
/// fields — same free-form treatment as custom/dart_defines.
///
/// env is a flat string map of arbitrary, user-declared native build-setting
/// keys (e.g. REVERSED_CLIENT_ID) — same free-form treatment.
const _freeFormFields = {'custom', 'dart_defines', 'env', 'info_plist', 'entitlements'};

const _schema = <String, _ClassSchema>{
  'AnnSpec': _ClassSchema({
    'app': _Nested.object('AnnApp'),
    'enabled': null,
    'debug': _Nested.object('DebugConfig'),
    'tooling': _Nested.object('ToolingConfig'),
  }),
  'AnnApp': _ClassSchema({
    'android': _Nested.object('AndroidPlatform'),
    'ios': _Nested.object('IosPlatform'),
    'web': _Nested.object('WebPlatform'),
    'windows': _Nested.object('WindowsPlatform'),
    'general': _Nested.object('GeneralConfig'),
    'integrations': _Nested.object('AnnIntegrations'),
  }),
  'GeneralConfig': _ClassSchema({}),
  'DebugConfig': _ClassSchema({
    'printDebug': null,
    'printBuildAndFlavorInfo': null,
    'printSdkVersions': null,
    'printReleaseBuildTypeInfo': null,
  }),
  'ToolingConfig': _ClassSchema({
    'gradle_plugin': null,
    'cocoapods_plugin': null,
    'fastlane_plugin': null,
  }),
  'AnnIntegrations': _ClassSchema({
    'fastlane': null,
    'melos': null,
    'firebase': null,
  }),
  'AndroidPlatform': _ClassSchema({
    'default': _Nested.object('AndroidDefault'),
    'flavor': _Nested.map('AndroidFlavor'),
  }),
  'AndroidDefault': _ClassSchema({
    'id': null,
    'name': null,
    'version_name': null,
    'version_code': null,
    'main_file': null,
    'admob': _Nested.object('AdmobConfig'),
    'icon': null,
    'firebase': _Nested.object('FirebaseConfig'),
    'sdk': _Nested.object('AndroidSdk'),
    'credentials': _Nested.object('AndroidCredentials'),
    'build_types': _Nested.map('BuildTypeConfig'),
    'custom': null,
    'dart_defines': null,
  }),
  'AndroidFlavor': _ClassSchema({
    'id': null,
    'id_suffix': null,
    'name': null,
    'name_suffix': null,
    'version_name': null,
    'version_code': null,
    'main_file': null,
    'admob': _Nested.object('AdmobConfig'),
    'icon': null,
    'firebase': _Nested.object('FirebaseConfig'),
    'stores': _Nested.object('FlavorStores'),
    'credentials': _Nested.object('AndroidCredentials'),
    'build_types': _Nested.map('BuildTypeConfig'),
    'custom': null,
    'dart_defines': null,
  }),
  'AndroidSdk': _ClassSchema({
    'minSdk': null,
    'compileSdk': null,
    'targetSdk': null, // NOTE: parser reads compileSdk/targetSdk camelCase, matching minSdk
  }),
  'AndroidCredentials': _ClassSchema({
    'signing': _Nested.object('AndroidSigning'),
    'google_play': _Nested.object('GooglePlayCredentials'),
    'samsung_galaxy': _Nested.object('SamsungGalaxyCredentials'),
    'amazon': _Nested.object('AmazonCredentials'),
  }),
  'AndroidSigning': _ClassSchema({'key_file': null}),
  'GooglePlayCredentials': _ClassSchema({'api_key': null}),
  'SamsungGalaxyCredentials': _ClassSchema({'seller_id': null, 'api_key': null}),
  'AmazonCredentials': _ClassSchema({'client_id': null, 'client_secret': null}),
  'IosPlatform': _ClassSchema({
    'default': _Nested.object('IosDefault'),
    'flavor': _Nested.map('IosFlavor'),
  }),
  'IosDefault': _ClassSchema({
    'id': null,
    'name': null,
    'version_name': null,
    'version_code': null,
    'main_file': null,
    'admob': _Nested.object('AdmobConfig'),
    'icon': null,
    'firebase': _Nested.object('FirebaseConfig'),
    'credentials': _Nested.object('IosCredentials'),
    'build_types': _Nested.map('BuildTypeConfig'),
    'custom': null,
    'dart_defines': null,
    'env': null,
    'info_plist': null,
    'entitlements': null,
    'sdk': _Nested.object('IosSdk'),
  }),
  'IosSdk': _ClassSchema({
    'ios': null,
    'swift_version': null,
  }),
  'IosFlavor': _ClassSchema({
    'id': null,
    'id_suffix': null,
    'name': null,
    'name_suffix': null,
    'version_name': null,
    'version_code': null,
    'main_file': null,
    'admob': _Nested.object('AdmobConfig'),
    'icon': null,
    'firebase': _Nested.object('FirebaseConfig'),
    'stores': _Nested.object('FlavorStores'),
    'credentials': _Nested.object('IosCredentials'),
    'build_types': _Nested.map('BuildTypeConfig'),
    'custom': null,
    'dart_defines': null,
    'env': null,
    'info_plist': null,
    'entitlements': null,
  }),
  'IosCredentials': _ClassSchema({
    'signing': _Nested.object('IosSigning'),
    'app_store': _Nested.object('AppStoreCredentials'),
  }),
  'IosSigning': _ClassSchema({'team_id': null}),
  'AppStoreCredentials': _ClassSchema({
    'api_key': null,
    'export_options_plist': null,
    'export_options_team_id': null,
    'export_options_signing_certificate': null,
  }),
  'WebPlatform': _ClassSchema({
    'default': _Nested.object('WebDefault'),
    'flavor': _Nested.map('WebFlavor'),
  }),
  'WebDefault': _ClassSchema({
    'id': null,
    'name': null,
    'version_name': null,
    'version_code': null,
    'main_file': null,
    'icon': null,
    'cloudflare': _Nested.object('CloudflareConfig'),
    'firebase': _Nested.object('FirebaseConfig'),
    'build_types': _Nested.map('BuildTypeConfig'),
    'custom': null,
    'dart_defines': null,
  }),
  'WebFlavor': _ClassSchema({
    'id': null,
    'id_suffix': null,
    'name': null,
    'name_suffix': null,
    'version_name': null,
    'version_code': null,
    'main_file': null,
    'icon': null,
    'cloudflare': _Nested.object('CloudflareConfig'),
    'firebase': _Nested.object('FirebaseConfig'),
    'build_types': _Nested.map('BuildTypeConfig'),
    'custom': null,
    'dart_defines': null,
  }),
  'CloudflareConfig': _ClassSchema({
    'project_name': null,
    'account_id': null,
    'branch': null,
    'mode': null,
  }),
  'WindowsPlatform': _ClassSchema({
    'default': _Nested.object('WindowsDefault'),
    'flavor': _Nested.map('WindowsFlavor'),
  }),
  'WindowsDefault': _ClassSchema({
    'id': null,
    'name': null,
    'version_name': null,
    'version_code': null,
    'main_file': null,
    'firebase': _Nested.object('FirebaseConfig'),
    'build_types': _Nested.map('BuildTypeConfig'),
    'custom': null,
    'dart_defines': null,
  }),
  'WindowsFlavor': _ClassSchema({
    'id': null,
    'id_suffix': null,
    'name': null,
    'name_suffix': null,
    'version_name': null,
    'version_code': null,
    'main_file': null,
    'firebase': _Nested.object('FirebaseConfig'),
    'build_types': _Nested.map('BuildTypeConfig'),
    'custom': null,
    'dart_defines': null,
  }),
  'AdmobConfig': _ClassSchema({'gms_ads_id': null}),
  'BuildTypeConfig': _ClassSchema({
    'id_suffix': null,
    'name_suffix': null,
    'admob': _Nested.object('AdmobConfig'),
    'firebase': _Nested.object('FirebaseConfig'),
    'auth': _Nested.object('AuthConfig'),
    'custom': null,
    'minifyEnabled': null,
    'shrinkResources': null,
    'lintCheckReleaseBuilds': null,
    'ndkVersion': null,
    'ndkDebugSymbolLevel': null,
    'ndkAbiFilters': null,
    'dart_defines': null,
    'env': null,
    'info_plist': null,
    'entitlements': null,
  }),
  'FirebaseConfig': _ClassSchema({
    'project_id': null,
    'config_file': null,
    'service_account': null,
    'target': null,
  }),
  'AuthConfig': _ClassSchema({
    'clientId': null,
    'reversedClientId': null,
    'others': null,
  }),
  'FlavorStores': _ClassSchema({
    'google_play': _Nested.object('GooglePlayFlavorStore'),
    'samsung_galaxy': _Nested.object('SamsungGalaxyFlavorStore'),
    'amazon': _Nested.object('AmazonFlavorStore'),
    'app_store': _Nested.object('AppStoreFlavorStore'),
  }),
  'GooglePlayFlavorStore': _ClassSchema({'priority': null}),
  'SamsungGalaxyFlavorStore': _ClassSchema({'app_id': null}),
  'AmazonFlavorStore': _ClassSchema({'app_id': null}),
  'AppStoreFlavorStore': _ClassSchema({'apple_id': null, 'team_id': null}),
};

class StrictModeChecker {
  static List<String> check(Map<String, dynamic> raw, {String rootClass = 'AnnSpec'}) {
    final issues = <String>[];
    _walk(raw, rootClass, '', issues);
    return issues;
  }

  static void _walk(
    Map<dynamic, dynamic> raw,
    String className,
    String path,
    List<String> issues,
  ) {
    final schema = _schema[className];
    if (schema == null) return;

    for (final entry in raw.entries) {
      final key = entry.key.toString();
      final fieldPath = path.isEmpty ? key : '$path.$key';

      if (!schema.fields.containsKey(key)) {
        final context = path.isEmpty ? 'top-level annspec.yaml' : '$path block';
        issues.add('Unknown field "$key" in $context. Check for typos or remove the field.');
        continue;
      }

      if (_freeFormFields.contains(key)) continue;

      final nested = schema.fields[key];
      if (nested == null) continue;

      final rawValue = entry.value;
      if (nested.kind == NestedKind.object) {
        if (rawValue is Map) _walk(rawValue, nested.targetClass, fieldPath, issues);
      } else {
        if (rawValue is Map) {
          for (final entryVal in rawValue.values) {
            if (entryVal is Map) _walk(entryVal, nested.targetClass, fieldPath, issues);
          }
        }
      }
    }
  }
}
