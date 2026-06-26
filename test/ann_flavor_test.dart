import 'package:ann_flutter_flavor/ann_flutter_flavor.dart';
import 'package:test/test.dart';

// Minimal concrete flavor for testing — mirrors what annspec codegen produces.
class _TestFlavor extends AnnFlavorConfig {
  @override
  final String key = 'test_flavor';
  @override
  final String name = 'Test App';
  @override
  final String? androidId = 'com.example.test';
  @override
  final String? iosId = 'com.example.test';

  @override
  AnnAuthConfig? auth(AnnPlatform platform) =>
      const AnnAuthConfig(clientId: 'client-id-release');

  @override
  AnnAuthConfig? authDebug(AnnPlatform platform) =>
      const AnnAuthConfig(clientId: 'client-id-debug');

  @override
  AnnCustomGroup? custom(String group) => switch (group) {
        'revenuecat' => switch (AnnFlavor.buildType) {
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

    test('androidId and iosId are set', () {
      expect(flavor.androidId, 'com.example.test');
      expect(flavor.iosId, 'com.example.test');
    });

    test('auth returns release clientId', () {
      final auth = flavor.auth(AnnPlatform.android);
      expect(auth?.clientId, 'client-id-release');
    });

    test('authDebug returns debug clientId', () {
      final auth = flavor.authDebug(AnnPlatform.android);
      expect(auth?.clientId, 'client-id-debug');
    });

    test('custom returns null for unknown group', () {
      AnnFlavor.init(config: flavor, platform: AnnPlatform.android);
      expect(flavor.custom('unknown_group'), isNull);
    });
  });

  group('AnnCustomGroup', () {
    test('returns release values when buildType is release', () {
      AnnFlavor.buildTypeOverride = 'release';
      AnnFlavor.init(config: _TestFlavor(), platform: AnnPlatform.android);
      final group = AnnFlavor.current.custom('revenuecat');
      expect(group, isNotNull);
      expect(group!.string('api_key'), 'rc_release');
      expect(group.strings('entitlement_ids'), ['standard', 'premium']);
    });

    test('returns debug values when buildType is debug', () {
      AnnFlavor.buildTypeOverride = 'debug';
      AnnFlavor.init(config: _TestFlavor(), platform: AnnPlatform.android);
      final group = AnnFlavor.current.custom('revenuecat');
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
