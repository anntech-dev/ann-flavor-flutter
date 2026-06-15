import 'dart:io';
import 'package:yaml/yaml.dart';
import 'package:path/path.dart' as p;
import '../model/annspec_model.dart';

class AnnspecReader {
  static AnnspecModel read(String projectRoot) {
    final file = File(p.join(projectRoot, 'annspec.yaml'));
    if (!file.existsSync()) {
      throw Exception('annspec.yaml not found at ${file.path}');
    }
    final doc = loadYaml(file.readAsStringSync()) as YamlMap;
    final app = doc['annai_app'] as YamlMap;
    final platforms = <AnnspecPlatform>[];

    for (final platformKey in ['android', 'ios', 'web', 'windows']) {
      final platformMap = app[platformKey] as YamlMap?;
      if (platformMap == null) continue;
      platforms.add(_parsePlatform(platformKey, platformMap));
    }

    return AnnspecModel(platforms: platforms);
  }

  static AnnspecPlatform _parsePlatform(String key, YamlMap map) {
    final defaultMap = map['default'] as YamlMap?;
    final flavorMap = map['flavor'] as YamlMap?;
    final storesMap = map['stores'] as YamlMap?;
    final sdkMap = map['sdk'] as YamlMap?;

    return AnnspecPlatform(
      key: key,
      baseId: defaultMap?['id'] as String?,
      teamId: defaultMap?['team_id'] as String?,
      defaultFirebaseRelease: _parseFirebase(defaultMap?['firebase']?['release']),
      defaultFirebaseDebug: _parseFirebase(defaultMap?['firebase']?['debug']),
      defaultAuthRelease: _parseAuth(defaultMap?['auth']?['release']),
      defaultAuthDebug: _parseAuth(defaultMap?['auth']?['debug']),
      flavors: flavorMap != null ? _parseFlavors(flavorMap) : [],
      minSdk: sdkMap?['minSdk'] as int?,
      googlePlayApiKey: storesMap?['google_play']?['api_key'] as String?,
      appStoreApiKey: storesMap?['app_store']?['api_key'] as String?,
      appStoreExportPlist: storesMap?['app_store']?['export_options_plist'] as String?,
    );
  }

  static List<AnnspecFlavor> _parseFlavors(YamlMap map) {
    return map.entries.map((e) {
      final key = e.key as String;
      final fm = e.value as YamlMap;
      return AnnspecFlavor(
        key: key,
        idSuffix: fm['id_suffix'] as String?,
        name: fm['name'] as String?,
        mainFile: fm['main_file'] as String?,
        versionName: fm['version_name']?.toString(),
        versionCode: fm['version_code']?.toString(),
        gmsAdsId: fm['gms_ads_id'] as String?,
        subscriptions: _parseSubscriptions(fm['in_app_subscription']),
        firebaseRelease: _parseFirebase(fm['firebase']?['release']),
        firebaseDebug: _parseFirebase(fm['firebase']?['debug']),
        authRelease: _parseAuth(fm['auth']?['release']),
        authDebug: _parseAuth(fm['auth']?['debug']),
        googlePlayPriority: fm['stores']?['google_play']?['priority']?.toString(),
        appleId: fm['stores']?['app_store']?['apple_id']?.toString(),
      );
    }).toList();
  }

  static AnnspecFirebase? _parseFirebase(dynamic map) {
    if (map == null) return null;
    final m = map as YamlMap;
    return AnnspecFirebase(
      projectId: m['project_id'] as String?,
      path: m['path'] as String?,
      appId: m['firebase_app_id'] as String?,
      buildTarget: m['build_target'] as String?,
    );
  }

  static AnnspecAuth? _parseAuth(dynamic map) {
    if (map == null) return null;
    final m = map as YamlMap;
    return AnnspecAuth(
      clientId: m['clientId'] as String?,
      reversedClientId: m['reversedClientId'] as String?,
    );
  }

  static List<AnnspecSubscription> _parseSubscriptions(dynamic raw) {
    if (raw == null) return [];
    final list = raw as YamlList;
    return list.map((item) {
      final m = item as YamlMap;
      final ids = (m['entitlementIds'] as YamlList).map((e) => e as String).toList();
      return AnnspecSubscription(apiKey: m['apiKey'] as String, entitlementIds: ids);
    }).toList();
  }
}
