import 'package:test/test.dart';
import '../lib_cli/model/annspec_model.dart';

void main() {
  group('AnnspecModel.resolveServiceAccount — 4-level cascade precedence', () {
    // Regression coverage for a bug where level 3 (default.build_types[bt])
    // was checked before level 2 (flavor.firebase) — a flavor's own top-level
    // override must always outrank an inherited per-build-type default, even
    // without a matching build-type-level key of its own.

    AnnspecPlatform platformWith({
      String? defaultServiceAccount,
      AnnspecFirebase? defaultFirebaseRelease,
    }) =>
        AnnspecPlatform(
          key: 'ios',
          defaultServiceAccount: defaultServiceAccount,
          defaultFirebaseRelease: defaultFirebaseRelease,
        );

    test('level 1 (flavor build_type) wins over all other levels', () {
      final platform = platformWith(
        defaultServiceAccount: 'keys/level4.json',
        defaultFirebaseRelease: AnnspecFirebase(serviceAccount: 'keys/level3.json'),
      );
      final flavor = AnnspecFlavor(
        key: 'app',
        flavorServiceAccount: 'keys/level2.json',
        firebaseRelease: AnnspecFirebase(serviceAccount: 'keys/level1.json'),
      );
      expect(AnnspecModel.resolveServiceAccount(platform, flavor, 'release'),
          'keys/level1.json');
    });

    test('level 2 (flavor top-level) wins over level 3 (default build_type)', () {
      final platform = platformWith(
        defaultServiceAccount: 'keys/level4.json',
        defaultFirebaseRelease: AnnspecFirebase(serviceAccount: 'keys/level3.json'),
      );
      final flavor = AnnspecFlavor(
        key: 'app',
        flavorServiceAccount: 'keys/level2.json',
      );
      expect(AnnspecModel.resolveServiceAccount(platform, flavor, 'release'),
          'keys/level2.json');
    });

    test('falls back to level 3 (default build_type) when levels 1-2 are absent', () {
      final platform = platformWith(
        defaultServiceAccount: 'keys/level4.json',
        defaultFirebaseRelease: AnnspecFirebase(serviceAccount: 'keys/level3.json'),
      );
      final flavor = AnnspecFlavor(key: 'app');
      expect(AnnspecModel.resolveServiceAccount(platform, flavor, 'release'),
          'keys/level3.json');
    });

    test('falls back to level 4 (default top-level) when levels 1-3 are absent', () {
      final platform = platformWith(defaultServiceAccount: 'keys/level4.json');
      final flavor = AnnspecFlavor(key: 'app');
      expect(AnnspecModel.resolveServiceAccount(platform, flavor, 'release'),
          'keys/level4.json');
    });

    test('returns null when no level has a service_account', () {
      final platform = platformWith();
      final flavor = AnnspecFlavor(key: 'app');
      expect(AnnspecModel.resolveServiceAccount(platform, flavor, 'release'), isNull);
    });
  });

  group('AnnspecModel.resolveTarget — same 4-level cascade precedence', () {
    test('level 2 (flavor top-level) wins over level 3 (default build_type)', () {
      final platform = AnnspecPlatform(
        key: 'ios',
        defaultTarget: 'DefaultTarget',
        defaultFirebaseRelease: AnnspecFirebase(target: 'DefaultBtTarget'),
      );
      final flavor = AnnspecFlavor(key: 'app', flavorTarget: 'FlavorTopTarget');
      expect(AnnspecModel.resolveTarget(platform, flavor, 'release'), 'FlavorTopTarget');
    });

    test('falls back to "Runner" when nothing is specified anywhere', () {
      final platform = AnnspecPlatform(key: 'ios');
      final flavor = AnnspecFlavor(key: 'app');
      expect(AnnspecModel.resolveTarget(platform, flavor, 'release'), 'Runner');
    });
  });
}
