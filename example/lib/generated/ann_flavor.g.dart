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
  bool existsOn([AnnPlatform? platform]) => switch (platform ?? AnnFlavor.platform) {
        AnnPlatform.android || AnnPlatform.ios => true,
        _ => false,
      };

  @override
  String? nameFor([AnnPlatform? platform]) => 'Flavor Example (Free)';

  @override
  String? idFor([AnnPlatform? platform]) => switch (platform ?? AnnFlavor.platform) {
        AnnPlatform.android => 'com.anntech.example.ann_flavor_example.free',
        AnnPlatform.ios => 'com.anntech.example.annFlavorExample.free',
        _ => null,
      };

  @override
  AnnAuthConfig? authFor([AnnPlatform? platform, String? buildType]) => null;

  @override
  AnnCustomGroup? customFor(String group, [AnnPlatform? platform, String? buildType]) {
    return switch (group) {
      'revenuecat' => switch (buildType ?? AnnFlavor.buildType) {
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
  bool existsOn([AnnPlatform? platform]) => switch (platform ?? AnnFlavor.platform) {
        AnnPlatform.android || AnnPlatform.ios => true,
        _ => false,
      };

  @override
  String? nameFor([AnnPlatform? platform]) => 'Flavor Example (Pro)';

  @override
  String? idFor([AnnPlatform? platform]) => switch (platform ?? AnnFlavor.platform) {
        AnnPlatform.android => 'com.anntech.example.ann_flavor_example.pro',
        AnnPlatform.ios => 'com.anntech.example.annFlavorExample.pro',
        _ => null,
      };

  @override
  AnnAuthConfig? authFor([AnnPlatform? platform, String? buildType]) => null;

  @override
  AnnCustomGroup? customFor(String group, [AnnPlatform? platform, String? buildType]) {
    return switch (group) {
      'revenuecat' => switch (buildType ?? AnnFlavor.buildType) {
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
