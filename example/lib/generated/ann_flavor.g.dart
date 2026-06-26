// GENERATED CODE — DO NOT EDIT BY HAND
// Run `dart run ann_flutter_flavor sync` to regenerate after editing annspec.yaml.
// ignore_for_file: type=lint

import 'package:ann_flutter_flavor/ann_flutter_flavor.dart';

// ── Free flavor ─────────────────────────────────────────────────────────────

class FreeFlavor extends AnnFlavorConfig {
  const FreeFlavor();

  @override
  String get key => 'free';

  @override
  String get name => 'Flavor Example (Free)';

  @override
  String? get androidId => 'com.anntech.example.ann_flavor_example.free';

  @override
  String? get iosId => 'com.anntech.example.annFlavorExample.free';

  @override
  AnnAuthConfig? auth(AnnPlatform platform) => null;

  @override
  AnnAuthConfig? authDebug(AnnPlatform platform) => null;

  @override
  AnnCustomGroup? custom(String group) {
    final bt = AnnFlavor.buildType;
    return switch (group) {
      'revenuecat' => switch (bt) {
          'debug' => const AnnCustomGroup({
              'api_key': 'goog_free_debug_XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX',
              'entitlement_ids': ['standard'],
            }),
          _ => const AnnCustomGroup({
              'api_key': 'goog_free_XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX',
              'entitlement_ids': ['standard'],
            }),
        },
      _ => null,
    };
  }
}

// ── Pro flavor ───────────────────────────────────────────────────────────────

class ProFlavor extends AnnFlavorConfig {
  const ProFlavor();

  @override
  String get key => 'pro';

  @override
  String get name => 'Flavor Example (Pro)';

  @override
  String? get androidId => 'com.anntech.example.ann_flavor_example.pro';

  @override
  String? get iosId => 'com.anntech.example.annFlavorExample.pro';

  @override
  AnnAuthConfig? auth(AnnPlatform platform) => null;

  @override
  AnnAuthConfig? authDebug(AnnPlatform platform) => null;

  @override
  AnnCustomGroup? custom(String group) {
    final bt = AnnFlavor.buildType;
    return switch (group) {
      'revenuecat' => switch (bt) {
          'debug' => const AnnCustomGroup({
              'api_key': 'goog_pro_debug_XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX',
              'entitlement_ids': ['standard', 'premium'],
            }),
          _ => const AnnCustomGroup({
              'api_key': 'goog_pro_XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX',
              'entitlement_ids': ['standard', 'premium'],
            }),
        },
      _ => null,
    };
  }
}
