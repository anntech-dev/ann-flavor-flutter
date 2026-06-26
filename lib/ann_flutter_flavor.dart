/// ANN Flutter Flavor — runtime API and CLI code generation.
///
/// Runtime usage (in generated flavor entry point):
/// ```dart
/// AnnFlavor.init(config: LedgerInConfig(), platform: AnnPlatform.android);
/// ```
///
/// Access anywhere in your app:
/// ```dart
/// AnnFlavor.current.name          // "ANN Smart Budget"
/// AnnFlavor.current.androidId     // "com.annai.productivity.ledger.in"
/// AnnFlavor.platform              // AnnPlatform.android
/// ```
library ann_flutter_flavor;

export 'src/flavor_config.dart';
export 'src/flavor_registry.dart';
export 'src/platform.dart';
export 'src/auth_config.dart';
export 'src/custom_group.dart';
