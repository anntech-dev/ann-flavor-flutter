// ─── Top-level ───────────────────────────────────────────────────────────────

class AnnSpec {
  final AnnApp app;
  final bool enabled;
  final DebugConfig debugConfig;
  final ToolingConfig? tooling;

  const AnnSpec({
    this.app = const AnnApp(),
    this.enabled = true,
    this.debugConfig = const DebugConfig(),
    this.tooling,
  });
}

// ─── Tooling (REQ-TOOL-00010 — top-level, non-cascading) ──────────────────────

class ToolingConfig {
  final String? gradlePlugin;
  final String? cocoapodsPlugin;
  final String? fastlanePlugin;

  const ToolingConfig({this.gradlePlugin, this.cocoapodsPlugin, this.fastlanePlugin});
}

class AnnApp {
  final AndroidPlatform? android;
  final IosPlatform? ios;
  final WebPlatform? web;
  final WindowsPlatform? windows;
  final GeneralConfig? general;
  final AnnIntegrations? integrations;

  const AnnApp({this.android, this.ios, this.web, this.windows, this.general, this.integrations});
}

// ─── Integrations ─────────────────────────────────────────────────────────────

class AnnIntegrations {
  final bool fastlane;
  final bool melos;
  final bool firebase;

  const AnnIntegrations({this.fastlane = false, this.melos = false, this.firebase = false});
}

// ─── Android ─────────────────────────────────────────────────────────────────

class AndroidPlatform {
  final AndroidDefault defaults;
  final Map<String, AndroidFlavor> flavors;

  const AndroidPlatform({
    this.defaults = const AndroidDefault(),
    this.flavors = const {},
  });
}

class AndroidDefault {
  final String? id;
  final String? name;
  final String? versionName;
  final int? versionCode;
  final String? mainFile;
  final AdmobConfig? admob;
  final String? icon;
  final FirebaseConfig? firebase;
  final AndroidSdk? sdk;
  final AndroidCredentials? credentials;
  final Map<String, BuildTypeConfig> buildTypes;
  final CustomConfig custom;
  final DartDefines dartDefines;

  const AndroidDefault({
    this.id,
    this.name,
    this.versionName,
    this.versionCode,
    this.mainFile,
    this.admob,
    this.icon,
    this.firebase,
    this.sdk,
    this.credentials,
    this.buildTypes = const {},
    this.custom = const {},
    this.dartDefines = DartDefines.empty,
  });
}

class AndroidFlavor {
  final String? id;
  final String idSuffix;
  final String? name;
  final String nameSuffix;
  final String? versionName;
  final int? versionCode;
  final String? mainFile;
  final AdmobConfig? admob;
  final String? icon;
  final FirebaseConfig? firebase;
  final FlavorStores? stores;
  final AndroidCredentials? credentials;
  final Map<String, BuildTypeConfig> buildTypes;
  final CustomConfig custom;
  final DartDefines dartDefines;

  const AndroidFlavor({
    this.id,
    this.idSuffix = '',
    this.name,
    this.nameSuffix = '',
    this.versionName,
    this.versionCode,
    this.mainFile,
    this.admob,
    this.icon,
    this.firebase,
    this.stores,
    this.credentials,
    this.buildTypes = const {},
    this.custom = const {},
    this.dartDefines = DartDefines.empty,
  });
}

class AndroidSdk {
  final int? minSdk;
  final int? compileSdk;
  final int? targetSdk;

  const AndroidSdk({this.minSdk, this.compileSdk, this.targetSdk});
}

class AndroidCredentials {
  final AndroidSigning? signing;
  final GooglePlayCredentials? googlePlay;
  final SamsungGalaxyCredentials? samsungGalaxy;
  final AmazonCredentials? amazon;

  const AndroidCredentials({this.signing, this.googlePlay, this.samsungGalaxy, this.amazon});
}

class AndroidSigning {
  final String? keyFile;
  const AndroidSigning({this.keyFile});
}

class GooglePlayCredentials {
  final String? apiKey;
  const GooglePlayCredentials({this.apiKey});
}

class SamsungGalaxyCredentials {
  final String? sellerId;
  final String? apiKey;
  const SamsungGalaxyCredentials({this.sellerId, this.apiKey});
}

class AmazonCredentials {
  final String? clientId;
  final String? clientSecret;
  const AmazonCredentials({this.clientId, this.clientSecret});
}

// ─── iOS ─────────────────────────────────────────────────────────────────────

class IosPlatform {
  final IosDefault defaults;
  final Map<String, IosFlavor> flavors;

  const IosPlatform({
    this.defaults = const IosDefault(),
    this.flavors = const {},
  });
}

class IosDefault {
  final String? id;
  final String? name;
  final String? versionName;
  final int? versionCode;
  final String? mainFile;
  final AdmobConfig? admob;
  final String? icon;
  final FirebaseConfig? firebase;
  final IosCredentials? credentials;
  final Map<String, BuildTypeConfig> buildTypes;
  final CustomConfig custom;
  final DartDefines dartDefines;

  const IosDefault({
    this.id,
    this.name,
    this.versionName,
    this.versionCode,
    this.mainFile,
    this.admob,
    this.icon,
    this.firebase,
    this.credentials,
    this.buildTypes = const {},
    this.custom = const {},
    this.dartDefines = DartDefines.empty,
  });
}

class IosFlavor {
  final String? id;
  final String idSuffix;
  final String? name;
  final String nameSuffix;
  final String? versionName;
  final int? versionCode;
  final String? mainFile;
  final AdmobConfig? admob;
  final String? icon;
  final FirebaseConfig? firebase;
  final FlavorStores? stores;
  final IosCredentials? credentials;
  final Map<String, BuildTypeConfig> buildTypes;
  final CustomConfig custom;
  final DartDefines dartDefines;

  const IosFlavor({
    this.id,
    this.idSuffix = '',
    this.name,
    this.nameSuffix = '',
    this.versionName,
    this.versionCode,
    this.mainFile,
    this.admob,
    this.icon,
    this.firebase,
    this.stores,
    this.credentials,
    this.buildTypes = const {},
    this.custom = const {},
    this.dartDefines = DartDefines.empty,
  });
}

class IosCredentials {
  final IosSigning? signing;
  final AppStoreCredentials? appStore;

  const IosCredentials({this.signing, this.appStore});
}

class IosSigning {
  final String? teamId;
  const IosSigning({this.teamId});
}

class AppStoreCredentials {
  final String? apiKey;
  final String? exportOptionsPlist;
  final String? exportOptionsTeamId;
  final String? exportOptionsSigningCertificate;

  const AppStoreCredentials({
    this.apiKey,
    this.exportOptionsPlist,
    this.exportOptionsTeamId,
    this.exportOptionsSigningCertificate,
  });
}

// ─── Web ─────────────────────────────────────────────────────────────────────

class WebPlatform {
  final WebDefault defaults;
  final Map<String, WebFlavor> flavors;

  const WebPlatform({this.defaults = const WebDefault(), this.flavors = const {}});
}

class CloudflareConfig {
  final String? projectName;
  final String? accountId;
  final String? branch;
  final String? mode;

  const CloudflareConfig({this.projectName, this.accountId, this.branch, this.mode});
}

class WebDefault {
  final String? id;
  final String? name;
  final String? versionName;
  final int? versionCode;
  final String? mainFile;
  final String? icon;
  final CloudflareConfig? cloudflare;
  final FirebaseConfig? firebase;
  final Map<String, BuildTypeConfig> buildTypes;
  final CustomConfig custom;
  final DartDefines dartDefines;

  const WebDefault({
    this.id, this.name, this.versionName, this.versionCode, this.mainFile,
    this.icon,
    this.cloudflare,
    this.firebase,
    this.buildTypes = const {},
    this.custom = const {},
    this.dartDefines = DartDefines.empty,
  });
}

class WebFlavor {
  final String? id;
  final String idSuffix;
  final String? name;
  final String nameSuffix;
  final String? versionName;
  final int? versionCode;
  final String? mainFile;
  final String? icon;
  final CloudflareConfig? cloudflare;
  final FirebaseConfig? firebase;
  final Map<String, BuildTypeConfig> buildTypes;
  final CustomConfig custom;
  final DartDefines dartDefines;

  const WebFlavor({
    this.id, this.idSuffix = '', this.name, this.nameSuffix = '',
    this.versionName, this.versionCode, this.mainFile,
    this.icon,
    this.cloudflare,
    this.firebase,
    this.buildTypes = const {},
    this.custom = const {},
    this.dartDefines = DartDefines.empty,
  });
}

// ─── Windows ─────────────────────────────────────────────────────────────────

class WindowsPlatform {
  final WindowsDefault defaults;
  final Map<String, WindowsFlavor> flavors;

  const WindowsPlatform({this.defaults = const WindowsDefault(), this.flavors = const {}});
}

class WindowsDefault {
  final String? id;
  final String? name;
  final String? versionName;
  final int? versionCode;
  final String? mainFile;
  final FirebaseConfig? firebase;
  final Map<String, BuildTypeConfig> buildTypes;
  final CustomConfig custom;
  final DartDefines dartDefines;

  const WindowsDefault({
    this.id, this.name, this.versionName, this.versionCode, this.mainFile,
    this.firebase,
    this.buildTypes = const {},
    this.custom = const {},
    this.dartDefines = DartDefines.empty,
  });
}

class WindowsFlavor {
  final String? id;
  final String idSuffix;
  final String? name;
  final String nameSuffix;
  final String? versionName;
  final int? versionCode;
  final String? mainFile;
  final FirebaseConfig? firebase;
  final Map<String, BuildTypeConfig> buildTypes;
  final CustomConfig custom;
  final DartDefines dartDefines;

  const WindowsFlavor({
    this.id, this.idSuffix = '', this.name, this.nameSuffix = '',
    this.versionName, this.versionCode, this.mainFile,
    this.firebase,
    this.buildTypes = const {},
    this.custom = const {},
    this.dartDefines = DartDefines.empty,
  });
}

// ─── Shared types ─────────────────────────────────────────────────────────────

/// `Map<groupName, Map<key, value>>` — the raw custom config at one spec level.
typedef CustomConfig = Map<String, Map<String, dynamic>>;

/// `compile`/`run`/`deploy` are reserved action-scope sub-keys (REQ-DDEF-00015).
/// [common] holds keys declared directly under `dart_defines` — they apply to every
/// action. Each action map is resolved as an addition on top of [common], never a
/// replacement.
class DartDefines {
  final Map<String, String> common;
  final Map<String, String> compile;
  final Map<String, String> run;
  final Map<String, String> deploy;

  const DartDefines({
    this.common = const {},
    this.compile = const {},
    this.run = const {},
    this.deploy = const {},
  });

  static const empty = DartDefines();
}

class BuildTypeConfig {
  final String idSuffix;
  final String nameSuffix;
  final AdmobConfig? admob;
  final FirebaseConfig? firebase;
  final AuthConfig? auth;
  final CustomConfig custom;
  final bool? minifyEnabled;
  final bool? shrinkResources;
  final bool? lintCheckReleaseBuilds;
  final String? ndkVersion;
  final String? ndkDebugSymbolLevel;
  final List<String> ndkAbiFilters;
  final DartDefines dartDefines;

  const BuildTypeConfig({
    this.idSuffix = '',
    this.nameSuffix = '',
    this.admob,
    this.firebase,
    this.auth,
    this.custom = const {},
    this.minifyEnabled,
    this.shrinkResources,
    this.lintCheckReleaseBuilds,
    this.ndkVersion,
    this.ndkDebugSymbolLevel,
    this.ndkAbiFilters = const [],
    this.dartDefines = DartDefines.empty,
  });
}

class AdmobConfig {
  final String? gmsAdsId;
  const AdmobConfig({this.gmsAdsId});
}

class FirebaseConfig {
  final String? projectId;
  final String? configFile;
  final String? serviceAccount;
  final String? target;

  const FirebaseConfig({this.projectId, this.configFile, this.serviceAccount, this.target});
}

class AuthConfig {
  final String? clientId;
  final String? reversedClientId;
  final Map<String, String> others;

  const AuthConfig({this.clientId, this.reversedClientId, this.others = const {}});
}

class FlavorStores {
  final GooglePlayFlavorStore?    googlePlay;
  final SamsungGalaxyFlavorStore? samsungGalaxy;
  final AmazonFlavorStore?        amazon;
  final AppStoreFlavorStore?      appStore;

  const FlavorStores({this.googlePlay, this.samsungGalaxy, this.amazon, this.appStore});
}

class GooglePlayFlavorStore {
  final int? priority;
  const GooglePlayFlavorStore({this.priority});
}

class SamsungGalaxyFlavorStore {
  final String? appId;
  const SamsungGalaxyFlavorStore({this.appId});
}

class AmazonFlavorStore {
  final String? appId;
  const AmazonFlavorStore({this.appId});
}

class AppStoreFlavorStore {
  final String? appleId;
  final String? teamId;

  const AppStoreFlavorStore({this.appleId, this.teamId});
}

class GeneralConfig {
  const GeneralConfig();
}

class DebugConfig {
  final bool printDebug;
  final bool printBuildAndFlavorInfo;
  final bool printSdkVersions;
  final bool printReleaseBuildTypeInfo;

  const DebugConfig({
    this.printDebug = false,
    this.printBuildAndFlavorInfo = true,
    this.printSdkVersions = true,
    this.printReleaseBuildTypeInfo = false,
  });
}

// ─── Resolved output types ────────────────────────────────────────────────────

class ResolvedSpec {
  final Map<String, ResolvedFlavor> android;
  final Map<String, ResolvedFlavor> ios;
  final Map<String, ResolvedFlavor> web;
  final Map<String, ResolvedFlavor> windows;

  const ResolvedSpec({
    this.android = const {},
    this.ios = const {},
    this.web = const {},
    this.windows = const {},
  });
}

class ResolvedFlavor {
  final String flavorName;
  final Map<String, ResolvedBuildOutput> byBuildType;

  const ResolvedFlavor({required this.flavorName, required this.byBuildType});
}

class ResolvedBuildOutput {
  final String flavorName;
  final String buildType;
  final String effectiveId;
  final String effectiveName;
  final String effectiveVersionName;
  final int? effectiveVersionCode;
  final String? effectiveMainFile;
  final FirebaseConfig? effectiveFirebase;
  final AuthConfig? effectiveAuth;
  final String? effectiveGmsAdsId;
  final String? effectiveIcon;
  final CloudflareConfig? effectiveCloudflare;
  final CustomConfig effectiveCustom;
  final DartDefines effectiveDartDefines;

  const ResolvedBuildOutput({
    required this.flavorName,
    required this.buildType,
    required this.effectiveId,
    required this.effectiveName,
    required this.effectiveVersionName,
    this.effectiveVersionCode,
    this.effectiveMainFile,
    this.effectiveFirebase,
    this.effectiveAuth,
    this.effectiveGmsAdsId,
    this.effectiveIcon,
    this.effectiveCloudflare,
    this.effectiveCustom = const {},
    this.effectiveDartDefines = DartDefines.empty,
  });
}
