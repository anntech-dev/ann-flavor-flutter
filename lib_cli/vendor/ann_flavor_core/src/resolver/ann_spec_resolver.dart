import '../model/ann_spec_model.dart';
import 'id_name_resolver.dart';

/// High-level resolver. Takes a parsed [AnnSpec] and returns all effective
/// (resolved) values for every flavor × build-type combination.
///
/// Usage patterns:
///
///   // From YAML (batch — all platforms, all build types)
///   final spec = AnnSpecParser.parse(yamlString);
///   final resolved = AnnSpecResolver.resolveAll(spec);
///
///   // From in-memory model (e.g. live UI data before saving to YAML)
///   final output = AnnSpecResolver.resolveAndroidFlavor(flavor, defaults, 'debug');
class AnnSpecResolver {
  static const standardBuildTypes = ['debug', 'release', 'profile'];

  // ── Entry points ────────────────────────────────────────────────────────────

  static ResolvedSpec resolveAll(
    AnnSpec spec, {
    List<String> buildTypes = standardBuildTypes,
  }) =>
    ResolvedSpec(
      android: spec.app.android != null ? resolveAndroid(spec.app.android!, buildTypes: buildTypes) : const {},
      ios:     spec.app.ios     != null ? resolveIos(spec.app.ios!,         buildTypes: buildTypes) : const {},
      web:     spec.app.web     != null ? resolveWeb(spec.app.web!,         buildTypes: buildTypes) : const {},
      windows: spec.app.windows != null ? resolveWindows(spec.app.windows!, buildTypes: buildTypes) : const {},
    );

  static Map<String, ResolvedFlavor> resolveAndroid(
    AndroidPlatform platform, {
    List<String> buildTypes = standardBuildTypes,
  }) =>
    platform.flavors.map((name, flavor) => MapEntry(
      name,
      ResolvedFlavor(
        flavorName:  name,
        byBuildType: {for (final bt in buildTypes) bt: resolveAndroidFlavor(flavor, platform.defaults, bt)},
      ),
    ));

  static Map<String, ResolvedFlavor> resolveIos(
    IosPlatform platform, {
    List<String> buildTypes = standardBuildTypes,
  }) =>
    platform.flavors.map((name, flavor) => MapEntry(
      name,
      ResolvedFlavor(
        flavorName:  name,
        byBuildType: {for (final bt in buildTypes) bt: resolveIosFlavor(flavor, platform.defaults, bt)},
      ),
    ));

  static Map<String, ResolvedFlavor> resolveWeb(
    WebPlatform platform, {
    List<String> buildTypes = standardBuildTypes,
  }) =>
    platform.flavors.map((name, flavor) => MapEntry(
      name,
      ResolvedFlavor(
        flavorName:  name,
        byBuildType: {for (final bt in buildTypes) bt: resolveWebFlavor(flavor, platform.defaults, bt)},
      ),
    ));

  static Map<String, ResolvedFlavor> resolveWindows(
    WindowsPlatform platform, {
    List<String> buildTypes = standardBuildTypes,
  }) =>
    platform.flavors.map((name, flavor) => MapEntry(
      name,
      ResolvedFlavor(
        flavorName:  name,
        byBuildType: {for (final bt in buildTypes) bt: resolveWindowsFlavor(flavor, platform.defaults, bt)},
      ),
    ));

  // ── Per-flavor resolvers (callable directly from UI / in-memory data) ───────

  static ResolvedBuildOutput resolveAndroidFlavor(
    AndroidFlavor flavor,
    AndroidDefault defaults,
    String buildType,
  ) {
    final bt = _effectiveBtConfig(
      flavor.buildTypes, defaults.buildTypes, buildType,
      flavorFirebase: flavor.firebase,
      defaultFirebase: defaults.firebase,
    );
    return ResolvedBuildOutput(
      flavorName:           '',
      buildType:            buildType,
      effectiveId:          IdNameResolver.resolveId(
        flavor.id ?? defaults.id ?? '', flavor.idSuffix, bt.idSuffix,
      ),
      effectiveName:        IdNameResolver.resolveName(
        flavor.name ?? defaults.name ?? '', flavor.nameSuffix, bt.nameSuffix,
      ),
      effectiveVersionName: flavor.versionName ?? defaults.versionName ?? '',
      effectiveVersionCode: flavor.versionCode ?? defaults.versionCode,
      effectiveMainFile:    flavor.mainFile ?? defaults.mainFile,
      effectiveFirebase:    bt.firebase,
      effectiveAuth:        bt.auth,
      effectiveGmsAdsId:    bt.admob?.gmsAdsId ?? flavor.admob?.gmsAdsId ?? defaults.admob?.gmsAdsId,
      effectiveIcon:        flavor.icon ?? defaults.icon,
      effectiveCustom:      _resolveCustom(
        defaultCustom:    defaults.custom,
        defaultBtCustom:  defaults.buildTypes[buildType]?.custom ?? const {},
        flavorCustom:     flavor.custom,
        flavorBtCustom:   flavor.buildTypes[buildType]?.custom ?? const {},
      ),
      effectiveDartDefines: _resolveDartDefines(
        defaultDefines:   defaults.dartDefines,
        defaultBtDefines: defaults.buildTypes[buildType]?.dartDefines ?? DartDefines.empty,
        flavorDefines:    flavor.dartDefines,
        flavorBtDefines:  flavor.buildTypes[buildType]?.dartDefines ?? DartDefines.empty,
      ),
    );
  }

  static ResolvedBuildOutput resolveIosFlavor(
    IosFlavor flavor,
    IosDefault defaults,
    String buildType,
  ) {
    final bt = _effectiveBtConfig(
      flavor.buildTypes, defaults.buildTypes, buildType,
      flavorFirebase: flavor.firebase,
      defaultFirebase: defaults.firebase,
    );
    return ResolvedBuildOutput(
      flavorName:           '',
      buildType:            buildType,
      effectiveId:          IdNameResolver.resolveId(flavor.id ?? defaults.id ?? '', flavor.idSuffix, bt.idSuffix),
      effectiveName:        IdNameResolver.resolveName(flavor.name ?? defaults.name ?? '', flavor.nameSuffix, bt.nameSuffix),
      effectiveVersionName: flavor.versionName ?? defaults.versionName ?? '',
      effectiveVersionCode: flavor.versionCode ?? defaults.versionCode,
      effectiveMainFile:    flavor.mainFile ?? defaults.mainFile,
      effectiveFirebase:    bt.firebase,
      effectiveAuth:        bt.auth,
      effectiveGmsAdsId:    bt.admob?.gmsAdsId ?? flavor.admob?.gmsAdsId ?? defaults.admob?.gmsAdsId,
      effectiveIcon:        flavor.icon ?? defaults.icon,
      effectiveCustom:      _resolveCustom(
        defaultCustom:    defaults.custom,
        defaultBtCustom:  defaults.buildTypes[buildType]?.custom ?? const {},
        flavorCustom:     flavor.custom,
        flavorBtCustom:   flavor.buildTypes[buildType]?.custom ?? const {},
      ),
      effectiveDartDefines: _resolveDartDefines(
        defaultDefines:   defaults.dartDefines,
        defaultBtDefines: defaults.buildTypes[buildType]?.dartDefines ?? DartDefines.empty,
        flavorDefines:    flavor.dartDefines,
        flavorBtDefines:  flavor.buildTypes[buildType]?.dartDefines ?? DartDefines.empty,
      ),
      effectiveEnv: _mergeDefinesMap(
        defaults.env, defaults.buildTypes[buildType]?.env ?? const {},
        flavor.env, flavor.buildTypes[buildType]?.env ?? const {},
      ),
      // Whole-value most-specific-wins — unlike firebase's per-field merge
      // (via _effectiveBtConfig), info_plist's value (an arbitrary map, or a
      // file-path string) has no fixed sub-fields to merge independently, so
      // a more specific level's value replaces a less specific one entirely
      // rather than being merged key-by-key here (per-key content merging
      // across levels happens later, in the consuming plugin, not the core).
      effectiveInfoPlist: flavor.buildTypes[buildType]?.infoPlist
          ?? flavor.infoPlist
          ?? defaults.buildTypes[buildType]?.infoPlist
          ?? defaults.infoPlist,
      // Same whole-value most-specific-wins rule as effectiveInfoPlist above.
      effectiveEntitlements: flavor.buildTypes[buildType]?.entitlements
          ?? flavor.entitlements
          ?? defaults.buildTypes[buildType]?.entitlements
          ?? defaults.entitlements,
      // Same whole-value most-specific-wins rule as effectiveInfoPlist above.
      effectiveExportOptions: flavor.buildTypes[buildType]?.exportOptions
          ?? flavor.exportOptions
          ?? defaults.buildTypes[buildType]?.exportOptions
          ?? defaults.exportOptions,
    );
  }

  static ResolvedBuildOutput resolveWebFlavor(
    WebFlavor flavor,
    WebDefault defaults,
    String buildType,
  ) {
    final bt = _effectiveBtConfig(
      flavor.buildTypes, defaults.buildTypes, buildType,
      flavorFirebase: flavor.firebase,
      defaultFirebase: defaults.firebase,
    );
    return ResolvedBuildOutput(
      flavorName:           '',
      buildType:            buildType,
      effectiveId:          IdNameResolver.resolveId(flavor.id ?? defaults.id ?? '', flavor.idSuffix, bt.idSuffix),
      effectiveName:        IdNameResolver.resolveName(flavor.name ?? defaults.name ?? '', flavor.nameSuffix, bt.nameSuffix),
      effectiveVersionName: flavor.versionName ?? defaults.versionName ?? '',
      effectiveVersionCode: flavor.versionCode ?? defaults.versionCode,
      effectiveMainFile:    flavor.mainFile ?? defaults.mainFile,
      effectiveFirebase:    bt.firebase,
      effectiveAuth:        bt.auth,
      effectiveGmsAdsId:    null,
      effectiveIcon:        flavor.icon ?? defaults.icon,
      effectiveCloudflare:  _resolveCloudflare(flavor.cloudflare, defaults.cloudflare),
      effectiveCustom:      _resolveCustom(
        defaultCustom:    defaults.custom,
        defaultBtCustom:  defaults.buildTypes[buildType]?.custom ?? const {},
        flavorCustom:     flavor.custom,
        flavorBtCustom:   flavor.buildTypes[buildType]?.custom ?? const {},
      ),
      effectiveDartDefines: _resolveDartDefines(
        defaultDefines:   defaults.dartDefines,
        defaultBtDefines: defaults.buildTypes[buildType]?.dartDefines ?? DartDefines.empty,
        flavorDefines:    flavor.dartDefines,
        flavorBtDefines:  flavor.buildTypes[buildType]?.dartDefines ?? DartDefines.empty,
      ),
    );
  }

  static ResolvedBuildOutput resolveWindowsFlavor(
    WindowsFlavor flavor,
    WindowsDefault defaults,
    String buildType,
  ) {
    final bt = _effectiveBtConfig(
      flavor.buildTypes, defaults.buildTypes, buildType,
      flavorFirebase: flavor.firebase,
      defaultFirebase: defaults.firebase,
    );
    return ResolvedBuildOutput(
      flavorName:           '',
      buildType:            buildType,
      effectiveId:          IdNameResolver.resolveId(flavor.id ?? defaults.id ?? '', flavor.idSuffix, bt.idSuffix),
      effectiveName:        IdNameResolver.resolveName(flavor.name ?? defaults.name ?? '', flavor.nameSuffix, bt.nameSuffix),
      effectiveVersionName: flavor.versionName ?? defaults.versionName ?? '',
      effectiveVersionCode: flavor.versionCode ?? defaults.versionCode,
      effectiveMainFile:    flavor.mainFile ?? defaults.mainFile,
      effectiveFirebase:    bt.firebase,
      effectiveAuth:        bt.auth,
      effectiveGmsAdsId:    null,
      effectiveIcon:        null,
      effectiveCustom:      _resolveCustom(
        defaultCustom:    defaults.custom,
        defaultBtCustom:  defaults.buildTypes[buildType]?.custom ?? const {},
        flavorCustom:     flavor.custom,
        flavorBtCustom:   flavor.buildTypes[buildType]?.custom ?? const {},
      ),
      effectiveDartDefines: _resolveDartDefines(
        defaultDefines:   defaults.dartDefines,
        defaultBtDefines: defaults.buildTypes[buildType]?.dartDefines ?? DartDefines.empty,
        flavorDefines:    flavor.dartDefines,
        flavorBtDefines:  flavor.buildTypes[buildType]?.dartDefines ?? DartDefines.empty,
      ),
    );
  }

  // ── Internal helpers ────────────────────────────────────────────────────────

  static BuildTypeConfig _effectiveBtConfig(
    Map<String, BuildTypeConfig> flavorBts,
    Map<String, BuildTypeConfig> defaultBts,
    String buildType, {
    FirebaseConfig? flavorFirebase,   // level 2: flavor.firebase
    FirebaseConfig? defaultFirebase,  // level 4: default.firebase
  }) {
    final f = flavorBts[buildType];
    final d = defaultBts[buildType];
    // Full 4-level cascade for every firebase field (most specific wins):
    //   L1: flavor.buildTypes[bt].firebase, L2: flavor.firebase,
    //   L3: default.buildTypes[bt].firebase, L4: default.firebase
    final effectiveProjectId = f?.firebase?.projectId
        ?? flavorFirebase?.projectId
        ?? d?.firebase?.projectId
        ?? defaultFirebase?.projectId;
    final effectiveConfigFile = f?.firebase?.configFile
        ?? flavorFirebase?.configFile
        ?? d?.firebase?.configFile
        ?? defaultFirebase?.configFile;
    final effectiveSa = f?.firebase?.serviceAccount
        ?? flavorFirebase?.serviceAccount
        ?? d?.firebase?.serviceAccount
        ?? defaultFirebase?.serviceAccount;
    final effectiveTarget = f?.firebase?.target
        ?? flavorFirebase?.target
        ?? d?.firebase?.target
        ?? defaultFirebase?.target;
    final firebase = (effectiveProjectId == null && effectiveConfigFile == null &&
            effectiveSa == null && effectiveTarget == null) ? null
        : FirebaseConfig(
            projectId:      effectiveProjectId,
            configFile:     effectiveConfigFile,
            serviceAccount: effectiveSa,
            target:         effectiveTarget,
          );
    return BuildTypeConfig(
      idSuffix:   IdNameResolver.effectiveBuildTypeSuffix(f?.idSuffix ?? '', d?.idSuffix ?? ''),
      nameSuffix: IdNameResolver.effectiveBuildTypeSuffix(f?.nameSuffix ?? '', d?.nameSuffix ?? ''),
      firebase:   firebase,
      auth:       _mergeAuthConfig(f?.auth, d?.auth),
    );
  }

  /// Deep-merges custom config in cascade priority order (lowest → highest):
  ///   default → default.buildType → flavor → flavor.buildType
  static CloudflareConfig _resolveCloudflare(CloudflareConfig? flavor, CloudflareConfig? defaults) =>
    CloudflareConfig(
      projectName: flavor?.projectName,
      accountId:   flavor?.accountId ?? defaults?.accountId,
      branch:      flavor?.branch    ?? defaults?.branch ?? 'main',
      mode:        flavor?.mode      ?? defaults?.mode   ?? 'pages',
    );

  static CustomConfig _resolveCustom({
    required CustomConfig defaultCustom,
    required CustomConfig defaultBtCustom,
    required CustomConfig flavorCustom,
    required CustomConfig flavorBtCustom,
  }) {
    CustomConfig merge(CustomConfig base, CustomConfig over) {
      if (over.isEmpty) return base;
      final result = Map<String, Map<String, dynamic>>.from(base);
      for (final e in over.entries) {
        result[e.key] = {...?result[e.key], ...e.value};
      }
      return result;
    }
    var result = merge(merge(merge(defaultCustom, defaultBtCustom), flavorCustom), flavorBtCustom);
    return result;
  }

  /// Shallow key-union across all four cascade levels — most specific key wins.
  static Map<String, String> _mergeDefinesMap(
    Map<String, String> default_,
    Map<String, String> defaultBt,
    Map<String, String> flavor,
    Map<String, String> flavorBt,
  ) =>
    {...default_, ...defaultBt, ...flavor, ...flavorBt};

  /// Resolves all four dart_defines sub-maps (common + three action scopes)
  /// independently.
  static DartDefines _resolveDartDefines({
    required DartDefines defaultDefines,
    required DartDefines defaultBtDefines,
    required DartDefines flavorDefines,
    required DartDefines flavorBtDefines,
  }) =>
    DartDefines(
      common: _mergeDefinesMap(
        defaultDefines.common, defaultBtDefines.common, flavorDefines.common, flavorBtDefines.common,
      ),
      compile: _mergeDefinesMap(
        defaultDefines.compile, defaultBtDefines.compile, flavorDefines.compile, flavorBtDefines.compile,
      ),
      run: _mergeDefinesMap(
        defaultDefines.run, defaultBtDefines.run, flavorDefines.run, flavorBtDefines.run,
      ),
      deploy: _mergeDefinesMap(
        defaultDefines.deploy, defaultBtDefines.deploy, flavorDefines.deploy, flavorBtDefines.deploy,
      ),
    );

  static AuthConfig? _mergeAuthConfig(AuthConfig? flavor, AuthConfig? defaults) {
    if (flavor == null) return defaults;
    if (defaults == null) return flavor;
    return AuthConfig(
      clientId:         flavor.clientId         ?? defaults.clientId,
      reversedClientId: flavor.reversedClientId ?? defaults.reversedClientId,
      others:           {...defaults.others, ...flavor.others},
    );
  }
}
