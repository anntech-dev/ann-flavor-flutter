import 'package:ann_flutter_flavor/ann_flutter_flavor.dart';
import 'package:test/test.dart';

// Minimal concrete flavor for testing — mirrors what annspec codegen produces.
class _TestFlavor extends AnnFlavorConfig {
  @override
  final String key = 'test_flavor';

  @override
  bool existsOn([AnnPlatform? platform]) => true;

  @override
  String? nameFor([AnnPlatform? platform]) => 'Test App';

  @override
  String? idFor([AnnPlatform? platform]) => 'com.example.test';

  @override
  AnnAuthConfig? authFor([AnnPlatform? platform, String? buildType]) =>
      (buildType ?? AnnFlavor.buildType) == 'debug'
          ? const AnnAuthConfig(clientId: 'client-id-debug')
          : const AnnAuthConfig(clientId: 'client-id-release');

  @override
  AnnCustomGroup? customFor(String group, [AnnPlatform? platform, String? buildType]) =>
      switch (group) {
        'revenuecat' => switch (buildType ?? AnnFlavor.buildType) {
            'debug' => AnnCustomGroup({
                'api_key': 'rc_debug',
                'entitlement_ids': ['standard']
              }),
            _ => AnnCustomGroup({
                'api_key': 'rc_release',
                'entitlement_ids': ['standard', 'premium']
              }),
          },
        _ => null,
      };
}

void main() {
  setUp(() {
    // Reset singleton state before each test.
    // ignore: invalid_use_of_visible_for_testing_member
    AnnFlavor.resetForTesting();
  });

  group('AnnFlavor', () {
    test('init sets current config and platform', () {
      AnnFlavor.init(config: _TestFlavor(), platform: AnnPlatform.android);
      expect(AnnFlavor.current.key, 'test_flavor');
      expect(AnnFlavor.platform, AnnPlatform.android);
    });

    test('buildType returns debug in test environment', () {
      AnnFlavor.init(config: _TestFlavor(), platform: AnnPlatform.android);
      // kDebugMode is true in test runs, so buildType resolves to 'debug'
      expect(AnnFlavor.buildType, 'debug');
    });

    test('buildTypeOverride allows forcing a specific build type in tests', () {
      AnnFlavor.buildTypeOverride = 'release';
      AnnFlavor.init(config: _TestFlavor(), platform: AnnPlatform.android);
      expect(AnnFlavor.buildType, 'release');
    });

    test('key shortcut returns flavor key', () {
      AnnFlavor.init(config: _TestFlavor(), platform: AnnPlatform.ios);
      expect(AnnFlavor.key, 'test_flavor');
    });

    test('accessing current before init throws assertion', () {
      expect(() => AnnFlavor.current, throwsA(isA<AssertionError>()));
    });

    test('accessing platform before init throws assertion', () {
      expect(() => AnnFlavor.platform, throwsA(isA<AssertionError>()));
    });

    test('init can be called again to switch flavor', () {
      AnnFlavor.init(config: _TestFlavor(), platform: AnnPlatform.android);
      AnnFlavor.init(config: _TestFlavor(), platform: AnnPlatform.ios);
      expect(AnnFlavor.platform, AnnPlatform.ios);
    });
  });

  group('AnnFlavorConfig', () {
    late _TestFlavor flavor;
    setUp(() => flavor = _TestFlavor());

    test('idFor(platform) resolves for an explicit platform', () {
      expect(flavor.idFor(AnnPlatform.android), 'com.example.test');
      expect(flavor.idFor(AnnPlatform.ios), 'com.example.test');
    });

    test('authFor(platform, buildType) resolves release clientId', () {
      final auth = flavor.authFor(AnnPlatform.android, 'release');
      expect(auth?.clientId, 'client-id-release');
    });

    test('authFor(platform, buildType) resolves debug clientId', () {
      final auth = flavor.authFor(AnnPlatform.android, 'debug');
      expect(auth?.clientId, 'client-id-debug');
    });

    test('authFor() with no args resolves the active platform + build type (release)', () {
      AnnFlavor.init(config: flavor, platform: AnnPlatform.android);
      AnnFlavor.buildTypeOverride = 'release';
      expect(flavor.authFor()?.clientId, 'client-id-release');
      AnnFlavor.buildTypeOverride = null;
    });

    test('authFor() with no args resolves the active platform + build type (debug)', () {
      AnnFlavor.init(config: flavor, platform: AnnPlatform.android);
      AnnFlavor.buildTypeOverride = 'debug';
      expect(flavor.authFor()?.clientId, 'client-id-debug');
      AnnFlavor.buildTypeOverride = null;
    });

    test('customFor(group) with omitted platform/buildType resolves the active ones', () {
      AnnFlavor.init(config: flavor, platform: AnnPlatform.android);
      expect(flavor.customFor('unknown_group'), isNull);
    });
  });

  group('AnnCustomGroup', () {
    test('returns release values when buildType is release', () {
      AnnFlavor.buildTypeOverride = 'release';
      AnnFlavor.init(config: _TestFlavor(), platform: AnnPlatform.android);
      final group = AnnFlavor.current.customFor('revenuecat');
      expect(group, isNotNull);
      expect(group!.string('api_key'), 'rc_release');
      expect(group.strings('entitlement_ids'), ['standard', 'premium']);
    });

    test('returns debug values when buildType is debug', () {
      AnnFlavor.buildTypeOverride = 'debug';
      AnnFlavor.init(config: _TestFlavor(), platform: AnnPlatform.android);
      final group = AnnFlavor.current.customFor('revenuecat');
      expect(group, isNotNull);
      expect(group!.string('api_key'), 'rc_debug');
      expect(group.strings('entitlement_ids'), ['standard']);
    });

    test('typed accessors return correct types', () {
      const g = AnnCustomGroup({
        'label': 'hello',
        'enabled': true,
        'count': 42,
        'ratio': 3.14,
        'tags': ['a', 'b'],
      });
      expect(g.string('label'), 'hello');
      expect(g.boolean('enabled'), true);
      expect(g.integer('count'), 42);
      expect(g.decimal('ratio'), 3.14);
      expect(g.strings('tags'), ['a', 'b']);
    });

    test('returns null for missing key', () {
      const g = AnnCustomGroup({'x': 'y'});
      expect(g.string('missing'), isNull);
      expect(g.boolean('missing'), isNull);
    });

    test('keys returns all group keys', () {
      const g = AnnCustomGroup({'a': 1, 'b': 2});
      expect(g.keys, containsAll(['a', 'b']));
    });
  });

  group('AnnAuthConfig', () {
    test('toString includes clientId', () {
      const auth = AnnAuthConfig(clientId: 'abc', reversedClientId: 'xyz');
      expect(auth.toString(), contains('abc'));
    });

    test('clientId and reversedClientId can both be null', () {
      const auth = AnnAuthConfig();
      expect(auth.clientId, isNull);
      expect(auth.reversedClientId, isNull);
    });
  });

  group('AnnPlatform', () {
    test('all 4 values exist', () {
      expect(AnnPlatform.values.length, 4);
      expect(
          AnnPlatform.values,
          containsAll([
            AnnPlatform.android,
            AnnPlatform.ios,
            AnnPlatform.web,
            AnnPlatform.windows,
          ]));
    });
  });
}
