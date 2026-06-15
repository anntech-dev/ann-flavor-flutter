class AnnspecAuth {
  final String? clientId;
  final String? reversedClientId;
  AnnspecAuth({this.clientId, this.reversedClientId});
}

class AnnspecFirebase {
  final String? projectId;
  final String? path;
  final String? appId;
  final String? buildTarget;
  AnnspecFirebase({this.projectId, this.path, this.appId, this.buildTarget});
}

class AnnspecSubscription {
  final String apiKey;
  final List<String> entitlementIds;
  AnnspecSubscription({required this.apiKey, required this.entitlementIds});
}

class AnnspecFlavor {
  final String key;
  final String? idSuffix;
  final String? name;
  final String? mainFile;
  final String? versionName;
  final String? versionCode;
  final String? gmsAdsId;
  final List<AnnspecSubscription> subscriptions;
  final AnnspecFirebase? firebaseRelease;
  final AnnspecFirebase? firebaseDebug;
  final AnnspecAuth? authRelease;
  final AnnspecAuth? authDebug;
  // store fields
  final String? googlePlayPriority;
  final String? appleId;

  AnnspecFlavor({
    required this.key,
    this.idSuffix,
    this.name,
    this.mainFile,
    this.versionName,
    this.versionCode,
    this.gmsAdsId,
    this.subscriptions = const [],
    this.firebaseRelease,
    this.firebaseDebug,
    this.authRelease,
    this.authDebug,
    this.googlePlayPriority,
    this.appleId,
  });
}

class AnnspecPlatform {
  final String key; // android | ios | web | windows
  final String? baseId;
  final String? teamId;
  final AnnspecFirebase? defaultFirebaseRelease;
  final AnnspecFirebase? defaultFirebaseDebug;
  final AnnspecAuth? defaultAuthRelease;
  final AnnspecAuth? defaultAuthDebug;
  final List<AnnspecFlavor> flavors;
  // android-specific
  final int? minSdk;
  final String? gradlePluginId;
  final String? gradlePluginVersion;
  // stores
  final String? googlePlayApiKey;
  final String? appStoreApiKey;
  final String? appStoreExportPlist;

  AnnspecPlatform({
    required this.key,
    this.baseId,
    this.teamId,
    this.defaultFirebaseRelease,
    this.defaultFirebaseDebug,
    this.defaultAuthRelease,
    this.defaultAuthDebug,
    this.flavors = const [],
    this.minSdk,
    this.gradlePluginId,
    this.gradlePluginVersion,
    this.googlePlayApiKey,
    this.appStoreApiKey,
    this.appStoreExportPlist,
  });
}

class AnnspecModel {
  final List<AnnspecPlatform> platforms;
  AnnspecModel({required this.platforms});

  AnnspecPlatform? platform(String key) =>
      platforms.where((p) => p.key == key).firstOrNull;
}
