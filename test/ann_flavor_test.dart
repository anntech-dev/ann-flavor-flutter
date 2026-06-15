import 'package:ann_flutter_flavor/ann_flutter_flavor.dart';
import 'package:test/test.dart';

// Minimal concrete flavor for testing — mirrors what annspec codegen produces.
class _TestFlavor extends AnnFlavorConfig {
  @override final String key = 'test_flavor';
  @override final String name = 'Test App';
  @override final String? androidId = 'com.example.test';
  @override final String? iosId = 'com.example.test';

  @override String? adsId(AnnPlatform platform) =>
      platform == AnnPlatform.android ? 'ca-app-pub-test' : null;

  @override List<AnnSubscription>? subscriptions(AnnPlatform platform) =>
      [const AnnSubscription(apiKey: 'test_key', entitlementIds: ['standard'])];

  @override AnnAuthConfig? auth(AnnPlatform platform) =>
      const AnnAuthConfig(clientId: 'client-id-release');

  @override AnnAuthConfig? authDebug(AnnPlatform platform) =>
      const AnnAuthConfig(clientId: 'client-id-debug');
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

    test('adsId returns value for android, null for ios', () {
      expect(flavor.adsId(AnnPlatform.android), 'ca-app-pub-test');
      expect(flavor.adsId(AnnPlatform.ios), isNull);
    });

    test('subscriptions returns list with one entry', () {
      final subs = flavor.subscriptions(AnnPlatform.android);
      expect(subs, isNotNull);
      expect(subs!.length, 1);
      expect(subs.first.apiKey, 'test_key');
      expect(subs.first.entitlementIds, ['standard']);
    });

    test('auth returns release clientId', () {
      final auth = flavor.auth(AnnPlatform.android);
      expect(auth?.clientId, 'client-id-release');
    });

    test('authDebug returns debug clientId', () {
      final auth = flavor.authDebug(AnnPlatform.android);
      expect(auth?.clientId, 'client-id-debug');
    });
  });

  group('AnnSubscription', () {
    test('toString includes apiKey and entitlementIds', () {
      const sub = AnnSubscription(apiKey: 'key', entitlementIds: ['a', 'b']);
      expect(sub.toString(), contains('key'));
      expect(sub.toString(), contains('a'));
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
      expect(AnnPlatform.values, containsAll([
        AnnPlatform.android,
        AnnPlatform.ios,
        AnnPlatform.web,
        AnnPlatform.windows,
      ]));
    });
  });
}
