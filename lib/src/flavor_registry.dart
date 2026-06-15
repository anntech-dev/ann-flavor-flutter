import 'flavor_config.dart';
import 'platform.dart';

/// Runtime singleton. Call [AnnFlavor.init] once in your flavor entry point
/// (e.g. lib/flavors/main_ledger_in.dart) before any other code runs.
class AnnFlavor {
  AnnFlavor._();

  static AnnFlavorConfig? _config;
  static AnnPlatform? _platform;

  /// Initialise with the active flavor config and detected platform.
  /// Must be called before accessing [current] or [platform].
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

  /// Convenience: the active flavor key.
  static String get key => current.key;
}
