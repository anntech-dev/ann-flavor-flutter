import 'platform.dart';
import 'subscription.dart';
import 'auth_config.dart';

/// Abstract base class for a generated flavor configuration.
/// Each flavor in annspec.yaml produces a concrete subclass.
abstract class AnnFlavorConfig {
  const AnnFlavorConfig();

  /// The flavor key matching the --flavor flag (e.g. "ledger_in").
  String get key;

  /// Display name of the app for this flavor.
  String get name;

  /// Android bundle ID (base ID + suffix).
  String? get androidId;

  /// iOS bundle ID (base ID + suffix).
  String? get iosId;

  /// AdMob app ID for the given platform, null if not configured.
  String? adsId(AnnPlatform platform);

  /// RevenueCat subscriptions for the given platform, null if not configured.
  List<AnnSubscription>? subscriptions(AnnPlatform platform);

  /// Google Sign-In config for the given platform (release build).
  AnnAuthConfig? auth(AnnPlatform platform);

  /// Google Sign-In config for the given platform (debug build).
  AnnAuthConfig? authDebug(AnnPlatform platform);
}
