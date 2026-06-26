import 'package:meta/meta.dart';
import 'flavor_config.dart';
import 'platform.dart';

/// Runtime singleton. Call [AnnFlavor.init] once in your flavor entry point
/// (e.g. lib/flavors/main_ledger_in.dart) before any other code runs.
class AnnFlavor {
  AnnFlavor._();

  static AnnFlavorConfig? _config;
  static AnnPlatform? _platform;

  /// Override the detected build type — **for testing only**.
  ///
  /// Set this before calling [init] in a test to force a specific build type
  /// (`'debug'`, `'profile'`, or `'release'`). Always clear it in `tearDown`
  /// via [resetForTesting].
  // ignore: invalid_annotation_target
  @visibleForTesting
  static String? buildTypeOverride;

  /// Initialise with the active flavor config and detected platform.
  /// Build type is derived automatically from Dart compile-time constants
  /// (dart.vm.product / dart.vm.profile) — no --dart-define required.
  static void init({
    required AnnFlavorConfig config,
    required AnnPlatform platform,
  }) {
    _config = config;
    _platform = platform;
  }

  /// The active flavor configuration.
  static AnnFlavorConfig get current {
    assert(_config != null,
        'AnnFlavor.init() must be called before accessing AnnFlavor.current');
    return _config!;
  }

  /// The platform detected at startup.
  static AnnPlatform get platform {
    assert(_platform != null,
        'AnnFlavor.init() must be called before accessing AnnFlavor.platform');
    return _platform!;
  }

  /// The active build type derived from Dart's compile-time constants.
  /// Returns `'release'` in release mode, `'profile'` in profile mode, `'debug'` otherwise.
  static String get buildType {
    if (buildTypeOverride != null) return buildTypeOverride!;
    const isRelease = bool.fromEnvironment('dart.vm.product');
    if (isRelease) return 'release';
    const isProfile = bool.fromEnvironment('dart.vm.profile');
    if (isProfile) return 'profile';
    return 'debug';
  }

  /// Convenience: the active flavor key.
  static String get key => current.key;

  // ignore: invalid_annotation_target
  @visibleForTesting
  static void resetForTesting() {
    _config = null;
    _platform = null;
    buildTypeOverride = null;
  }
}
