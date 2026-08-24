import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:ann_flavor_core/ann_flavor_core.dart' as core;
import '../model/annspec_model.dart';

/// Reads annspec.yaml via the shared core (ADR-008) — parsing and cascade
/// merging are the core's responsibility; this class only maps the core's
/// model onto the CLI's own `Annspec*` shape that the rest of `lib_cli/`
/// already depends on.
class AnnspecReader {
  static AnnspecModel read(String projectRoot) {
    final file = File(p.join(projectRoot, 'annspec.yaml'));
    if (!file.existsSync()) {
      throw Exception('annspec.yaml not found at ${file.path}');
    }

    core.AnnSpec spec;
    try {
      spec = core.AnnSpecParser.parse(file.readAsStringSync());
    } catch (e) {
      final raw = file.readAsStringSync();
      final hint = raw.contains('annai_app:')
          ? '\n  Hint: rename the root key from "annai_app:" to "app:" — the key was changed in v0.2.0.'
          : '';
      throw Exception('Failed to parse annspec.yaml: $e$hint');
    }

    final platforms = <AnnspecPlatform>[];
    if (spec.app.android != null) platforms.add(_mapAndroid(spec.app.android!));
    if (spec.app.ios != null) platforms.add(_mapIos(spec.app.ios!));
    if (spec.app.web != null) platforms.add(_mapWeb(spec.app.web!));
    if (spec.app.windows != null) platforms.add(_mapWindows(spec.app.windows!));

    final integrations = spec.app.integrations == null
        ? null
        : AnnspecIntegrations(
            fastlane: spec.app.integrations!.fastlane,
            melos:    spec.app.integrations!.melos,
            firebase: spec.app.integrations!.firebase,
          );

    final tooling = spec.tooling == null
        ? null
        : AnnspecTooling(
            gradlePlugin:    spec.tooling!.gradlePlugin,
            cocoapodsPlugin: spec.tooling!.cocoapodsPlugin,
            fastlanePlugin:  spec.tooling!.fastlanePlugin,
          );

    return AnnspecModel(platforms: platforms, integrations: integrations, tooling: tooling);
  }

  static AnnspecPlatform _mapAndroid(core.AndroidPlatform platform) {
    final d = platform.defaults;
    final c = d.credentials;
    final defaultBuildTypes = _mapBuildTypes(d.buildTypes);

    return AnnspecPlatform(
      key: 'android',
      baseId: d.id,
      baseName: d.name,
      defaultVersionName: d.versionName,
      defaultVersionCode: d.versionCode,
      defaultGmsAdsId: d.admob?.gmsAdsId,
      defaultIcon: d.icon,
      defaultFirebaseRelease: _mapFirebase(d.buildTypes['release']?.firebase),
      defaultFirebaseDebug: _mapFirebase(d.buildTypes['debug']?.firebase),
      defaultServiceAccount: d.firebase?.serviceAccount,
      defaultTarget: d.firebase?.target,
      defaultAuthRelease: _mapAuth(d.buildTypes['release']?.auth),
      defaultAuthDebug: _mapAuth(d.buildTypes['debug']?.auth),
      flavors: platform.flavors.entries.map((e) => _mapAndroidFlavor(
        e.key, e.value, d, defaultBuildTypes,
      )).toList(),
      minSdk: d.sdk?.minSdk,
      signingKeyFile: c?.signing?.keyFile,
      googlePlayApiKey: c?.googlePlay?.apiKey,
      defaultBuildTypes: defaultBuildTypes,
    );
  }

  static AnnspecFlavor _mapAndroidFlavor(
    String key, core.AndroidFlavor flavor, core.AndroidDefault defaults,
    Map<String, AnnspecBuildTypeConfig> defaultBuildTypes,
  ) {
    final flavorBuildTypes = _mapBuildTypes(flavor.buildTypes);
    return AnnspecFlavor(
      key: key,
      id: flavor.id,
      idSuffix: flavor.idSuffix.isEmpty ? null : flavor.idSuffix,
      name: flavor.name,
      mainFile: flavor.mainFile,
      versionName: flavor.versionName,
      versionCode: flavor.versionCode,
      gmsAdsId: flavor.admob?.gmsAdsId,
      icon: flavor.icon,
      firebaseRelease: _mapFirebase(flavor.buildTypes['release']?.firebase),
      firebaseDebug: _mapFirebase(flavor.buildTypes['debug']?.firebase),
      flavorServiceAccount: flavor.firebase?.serviceAccount,
      flavorTarget: flavor.firebase?.target,
      authRelease: _mapAuth(flavor.buildTypes['release']?.auth),
      authDebug: _mapAuth(flavor.buildTypes['debug']?.auth),
      googlePlayPriority: flavor.stores?.googlePlay?.priority?.toString(),
      samsungAppId: flavor.stores?.samsungGalaxy?.appId,
      amazonAppId: flavor.stores?.amazon?.appId,
      buildTypes: {...defaultBuildTypes, ...flavorBuildTypes},
      customByBuildType: _resolveCustomByBuildType(
        (bt) => core.AnnSpecResolver.resolveAndroidFlavor(flavor, defaults, bt),
      ),
    );
  }

  static AnnspecPlatform _mapIos(core.IosPlatform platform) {
    final d = platform.defaults;
    final c = d.credentials;
    final defaultBuildTypes = _mapBuildTypes(d.buildTypes);

    return AnnspecPlatform(
      key: 'ios',
      baseId: d.id,
      baseName: d.name,
      defaultVersionName: d.versionName,
      defaultVersionCode: d.versionCode,
      defaultGmsAdsId: d.admob?.gmsAdsId,
      defaultIcon: d.icon,
      teamId: c?.signing?.teamId,
      defaultFirebaseRelease: _mapFirebase(d.buildTypes['release']?.firebase),
      defaultFirebaseDebug: _mapFirebase(d.buildTypes['debug']?.firebase),
      defaultServiceAccount: d.firebase?.serviceAccount,
      defaultTarget: d.firebase?.target,
      defaultAuthRelease: _mapAuth(d.buildTypes['release']?.auth),
      defaultAuthDebug: _mapAuth(d.buildTypes['debug']?.auth),
      flavors: platform.flavors.entries.map((e) => _mapIosFlavor(
        e.key, e.value, d, defaultBuildTypes,
      )).toList(),
      appStoreApiKey: c?.appStore?.apiKey,
      appStoreExportPlist: c?.appStore?.exportOptionsPlist,
      defaultBuildTypes: defaultBuildTypes,
    );
  }

  static AnnspecFlavor _mapIosFlavor(
    String key, core.IosFlavor flavor, core.IosDefault defaults,
    Map<String, AnnspecBuildTypeConfig> defaultBuildTypes,
  ) {
    final flavorBuildTypes = _mapBuildTypes(flavor.buildTypes);
    return AnnspecFlavor(
      key: key,
      id: flavor.id,
      idSuffix: flavor.idSuffix.isEmpty ? null : flavor.idSuffix,
      name: flavor.name,
      mainFile: flavor.mainFile,
      versionName: flavor.versionName,
      versionCode: flavor.versionCode,
      gmsAdsId: flavor.admob?.gmsAdsId,
      icon: flavor.icon,
      firebaseRelease: _mapFirebase(flavor.buildTypes['release']?.firebase),
      firebaseDebug: _mapFirebase(flavor.buildTypes['debug']?.firebase),
      flavorServiceAccount: flavor.firebase?.serviceAccount,
      flavorTarget: flavor.firebase?.target,
      authRelease: _mapAuth(flavor.buildTypes['release']?.auth),
      authDebug: _mapAuth(flavor.buildTypes['debug']?.auth),
      appleId: flavor.stores?.appStore?.appleId,
      buildTypes: {...defaultBuildTypes, ...flavorBuildTypes},
      customByBuildType: _resolveCustomByBuildType(
        (bt) => core.AnnSpecResolver.resolveIosFlavor(flavor, defaults, bt),
      ),
    );
  }

  static AnnspecPlatform _mapWeb(core.WebPlatform platform) {
    final d = platform.defaults;
    final defaultBuildTypes = _mapBuildTypes(d.buildTypes);

    return AnnspecPlatform(
      key: 'web',
      baseId: d.id,
      baseName: d.name,
      defaultVersionName: d.versionName,
      defaultVersionCode: d.versionCode,
      defaultIcon: d.icon,
      defaultAuthRelease: _mapAuth(d.buildTypes['release']?.auth),
      defaultAuthDebug: _mapAuth(d.buildTypes['debug']?.auth),
      flavors: platform.flavors.entries.map((e) => _mapWebFlavor(
        e.key, e.value, d, defaultBuildTypes,
      )).toList(),
      defaultBuildTypes: defaultBuildTypes,
    );
  }

  static AnnspecFlavor _mapWebFlavor(
    String key, core.WebFlavor flavor, core.WebDefault defaults,
    Map<String, AnnspecBuildTypeConfig> defaultBuildTypes,
  ) {
    final flavorBuildTypes = _mapBuildTypes(flavor.buildTypes);
    return AnnspecFlavor(
      key: key,
      id: flavor.id,
      idSuffix: flavor.idSuffix.isEmpty ? null : flavor.idSuffix,
      name: flavor.name,
      mainFile: flavor.mainFile,
      versionName: flavor.versionName,
      versionCode: flavor.versionCode,
      icon: flavor.icon,
      authRelease: _mapAuth(flavor.buildTypes['release']?.auth),
      authDebug: _mapAuth(flavor.buildTypes['debug']?.auth),
      buildTypes: {...defaultBuildTypes, ...flavorBuildTypes},
      customByBuildType: _resolveCustomByBuildType(
        (bt) => core.AnnSpecResolver.resolveWebFlavor(flavor, defaults, bt),
      ),
    );
  }

  static AnnspecPlatform _mapWindows(core.WindowsPlatform platform) {
    final d = platform.defaults;
    final defaultBuildTypes = _mapBuildTypes(d.buildTypes);

    return AnnspecPlatform(
      key: 'windows',
      baseId: d.id,
      baseName: d.name,
      defaultVersionName: d.versionName,
      defaultVersionCode: d.versionCode,
      defaultAuthRelease: _mapAuth(d.buildTypes['release']?.auth),
      defaultAuthDebug: _mapAuth(d.buildTypes['debug']?.auth),
      flavors: platform.flavors.entries.map((e) => _mapWindowsFlavor(
        e.key, e.value, d, defaultBuildTypes,
      )).toList(),
      defaultBuildTypes: defaultBuildTypes,
    );
  }

  static AnnspecFlavor _mapWindowsFlavor(
    String key, core.WindowsFlavor flavor, core.WindowsDefault defaults,
    Map<String, AnnspecBuildTypeConfig> defaultBuildTypes,
  ) {
    final flavorBuildTypes = _mapBuildTypes(flavor.buildTypes);
    return AnnspecFlavor(
      key: key,
      id: flavor.id,
      idSuffix: flavor.idSuffix.isEmpty ? null : flavor.idSuffix,
      name: flavor.name,
      mainFile: flavor.mainFile,
      versionName: flavor.versionName,
      versionCode: flavor.versionCode,
      authRelease: _mapAuth(flavor.buildTypes['release']?.auth),
      authDebug: _mapAuth(flavor.buildTypes['debug']?.auth),
      buildTypes: {...defaultBuildTypes, ...flavorBuildTypes},
      customByBuildType: _resolveCustomByBuildType(
        (bt) => core.AnnSpecResolver.resolveWindowsFlavor(flavor, defaults, bt),
      ),
    );
  }

  // ── Shared mapping helpers ────────────────────────────────────────────────

  static Map<String, AnnspecBuildTypeConfig> _mapBuildTypes(Map<String, core.BuildTypeConfig> raw) {
    return raw.map((key, cfg) => MapEntry(key, AnnspecBuildTypeConfig(
      idSuffix:               cfg.idSuffix.isEmpty ? null : cfg.idSuffix,
      nameSuffix:             cfg.nameSuffix.isEmpty ? null : cfg.nameSuffix,
      gmsAdsId:               cfg.admob?.gmsAdsId,
      minifyEnabled:          cfg.minifyEnabled,
      shrinkResources:        cfg.shrinkResources,
      lintCheckReleaseBuilds: cfg.lintCheckReleaseBuilds,
      ndkVersion:             cfg.ndkVersion,
      ndkDebugSymbolLevel:    cfg.ndkDebugSymbolLevel,
      ndkAbiFilters:          cfg.ndkAbiFilters,
    )));
  }

  static AnnspecFirebase? _mapFirebase(core.FirebaseConfig? fb) {
    if (fb == null) return null;
    return AnnspecFirebase(
      projectId: fb.projectId,
      configFile: fb.configFile,
      serviceAccount: fb.serviceAccount,
      target: fb.target,
    );
  }

  static AnnspecAuth? _mapAuth(core.AuthConfig? auth) {
    if (auth == null) return null;
    return AnnspecAuth(clientId: auth.clientId, reversedClientId: auth.reversedClientId);
  }

  /// Resolved (fully cascaded) custom config per build type — matches the
  /// core resolver's 4-level merge (default → default.bt → flavor → flavor.bt),
  /// including profile now that the core resolver supports it.
  static Map<String, Map<String, Map<String, dynamic>>> _resolveCustomByBuildType(
    core.ResolvedBuildOutput Function(String buildType) resolve,
  ) {
    final result = <String, Map<String, Map<String, dynamic>>>{};
    for (final bt in core.AnnSpecResolver.standardBuildTypes) {
      final resolved = resolve(bt);
      if (resolved.effectiveCustom.isNotEmpty) {
        result[bt] = resolved.effectiveCustom;
      }
    }
    return result;
  }
}
