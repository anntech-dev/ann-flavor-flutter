import 'package:ann_flutter_flavor/ann_flutter_flavor.dart';
import 'package:test/test.dart';

// A flavor that records which platform/buildType it was actually called
// with, to verify the optional-param default resolution
// (platform ?? AnnFlavor.platform, buildType ?? AnnFlavor.buildType) picks
// the right value whether the caller passes it explicitly or omits it.
class _RecordingFlavor extends AnnFlavorConfig {
  @override
  final String key = 'recording';

  AnnPlatform? lastPlatform;
  String? lastBuildType;

  @override
  bool existsOn([AnnPlatform? platform]) {
    lastPlatform = platform ?? AnnFlavor.platform;
    return true;
  }

  @override
  String? nameFor([AnnPlatform? platform]) {
    lastPlatform = platform ?? AnnFlavor.platform;
    return 'name-for-$lastPlatform';
  }

  @override
  String? idFor([AnnPlatform? platform]) {
    lastPlatform = platform ?? AnnFlavor.platform;
    return 'id-for-$lastPlatform';
  }

  @override
  AnnAuthConfig? authFor([AnnPlatform? platform, String? buildType]) {
    lastPlatform = platform ?? AnnFlavor.platform;
    lastBuildType = buildType ?? AnnFlavor.buildType;
    return AnnAuthConfig(clientId: '$lastPlatform-$lastBuildType');
  }

  @override
  dynamic firebaseOptionsFor([AnnPlatform? platform, String? buildType]) {
    lastPlatform = platform ?? AnnFlavor.platform;
    lastBuildType = buildType ?? AnnFlavor.buildType;
    return null;
  }

  @override
  AnnCustomGroup? customFor(String group, [AnnPlatform? platform, String? buildType]) {
    lastPlatform = platform ?? AnnFlavor.platform;
    lastBuildType = buildType ?? AnnFlavor.buildType;
    return AnnCustomGroup({'group': group});
  }
}

// A flavor whose nameFor/idFor return null (not throw) for every platform,
// to verify the `name`/`id` shorthand getters fall back to `key`.
class _NullFieldsFlavor extends AnnFlavorConfig {
  @override
  final String key = 'null_fields';

  @override
  bool existsOn([AnnPlatform? platform]) => true;

  @override
  String? nameFor([AnnPlatform? platform]) => null;

  @override
  String? idFor([AnnPlatform? platform]) => null;

  @override
  AnnAuthConfig? authFor([AnnPlatform? platform, String? buildType]) => null;

  @override
  AnnCustomGroup? customFor(String group, [AnnPlatform? platform, String? buildType]) => null;
}

// A flavor whose *ForPlatform(AndBuildType) primitives always throw, to
// verify the throw propagates identically whether platform/buildType were
// passed explicitly or left to default — there is no separate "safe" path.
class _AlwaysThrowsFlavor extends AnnFlavorConfig {
  @override
  final String key = 'always_throws';

  @override
  bool existsOn([AnnPlatform? platform]) => false;

  @override
  String? nameFor([AnnPlatform? platform]) =>
      throw StateError('no app.${platform ?? AnnFlavor.platform} section');

  @override
  String? idFor([AnnPlatform? platform]) =>
      throw StateError('no app.${platform ?? AnnFlavor.platform} section');

  @override
  AnnAuthConfig? authFor([AnnPlatform? platform, String? buildType]) =>
      throw StateError('no app.${platform ?? AnnFlavor.platform} section');

  @override
  AnnCustomGroup? customFor(String group, [AnnPlatform? platform, String? buildType]) =>
      throw StateError('no app.${platform ?? AnnFlavor.platform} section');
}

void main() {
  setUp(() {
    // ignore: invalid_use_of_visible_for_testing_member
    AnnFlavor.resetForTesting();
  });

  group('AnnFlavorConfig — omitted platform/buildType default to AnnFlavor.platform/.buildType', () {
    late _RecordingFlavor flavor;

    setUp(() {
      flavor = _RecordingFlavor();
      AnnFlavor.init(config: flavor, platform: AnnPlatform.web);
      AnnFlavor.buildTypeOverride = 'release';
    });

    tearDown(() => AnnFlavor.buildTypeOverride = null);

    test('existsOn() with no args resolves using AnnFlavor.platform', () {
      expect(flavor.existsOn(), isTrue);
      expect(flavor.lastPlatform, AnnPlatform.web);
    });

    test('existsOn(platform) with an explicit platform overrides the active one', () {
      flavor.existsOn(AnnPlatform.android);
      expect(flavor.lastPlatform, AnnPlatform.android);
    });

    test('nameFor() with no args resolves using AnnFlavor.platform', () {
      expect(flavor.nameFor(), 'name-for-AnnPlatform.web');
      expect(flavor.lastPlatform, AnnPlatform.web);
    });

    test('nameFor(platform) with an explicit platform overrides the active one', () {
      expect(flavor.nameFor(AnnPlatform.android), 'name-for-AnnPlatform.android');
      expect(flavor.lastPlatform, AnnPlatform.android);
    });

    test('idFor() with no args resolves using AnnFlavor.platform', () {
      expect(flavor.idFor(), 'id-for-AnnPlatform.web');
    });

    test('authFor() with no args resolves both platform and buildType from AnnFlavor', () {
      final auth = flavor.authFor();
      expect(flavor.lastPlatform, AnnPlatform.web);
      expect(flavor.lastBuildType, 'release');
      expect(auth?.clientId, 'AnnPlatform.web-release');
    });

    test('authFor(platform) with only platform explicit still defaults buildType', () {
      flavor.authFor(AnnPlatform.ios);
      expect(flavor.lastPlatform, AnnPlatform.ios);
      expect(flavor.lastBuildType, 'release');
    });

    test('authFor(platform, buildType) with both explicit ignores AnnFlavor entirely', () {
      flavor.authFor(AnnPlatform.android, 'debug');
      expect(flavor.lastPlatform, AnnPlatform.android);
      expect(flavor.lastBuildType, 'debug');
    });

    test('firebaseOptionsFor() with no args resolves both from AnnFlavor', () {
      flavor.firebaseOptionsFor();
      expect(flavor.lastPlatform, AnnPlatform.web);
      expect(flavor.lastBuildType, 'release');
    });

    test('customFor(group) with omitted platform/buildType resolves both from AnnFlavor', () {
      final group = flavor.customFor('revenuecat');
      expect(flavor.lastPlatform, AnnPlatform.web);
      expect(flavor.lastBuildType, 'release');
      expect(group?.string('group'), 'revenuecat');
    });

    test('customFor(group, platform, buildType) with all explicit ignores AnnFlavor entirely', () {
      flavor.customFor('revenuecat', AnnPlatform.android, 'debug');
      expect(flavor.lastPlatform, AnnPlatform.android);
      expect(flavor.lastBuildType, 'debug');
    });
  });

  group('AnnFlavorConfig — throw propagates identically whether platform is explicit or defaulted', () {
    late _AlwaysThrowsFlavor flavor;

    setUp(() {
      flavor = _AlwaysThrowsFlavor();
      AnnFlavor.init(config: flavor, platform: AnnPlatform.android);
    });

    test('existsOn() never throws, even for a flavor whose other accessors always do', () {
      expect(flavor.existsOn(), isFalse);
      expect(flavor.existsOn(AnnPlatform.web), isFalse);
    });

    test('nameFor() with no args still throws — there is no separate non-throwing path', () {
      expect(() => flavor.nameFor(), throwsA(isA<StateError>()));
    });

    test('nameFor(platform) with an explicit platform still throws', () {
      expect(() => flavor.nameFor(AnnPlatform.ios), throwsA(isA<StateError>()));
    });

    test('idFor() with no args still throws', () {
      expect(() => flavor.idFor(), throwsA(isA<StateError>()));
    });

    test('authFor() with no args still throws', () {
      expect(() => flavor.authFor(), throwsA(isA<StateError>()));
    });

    test('customFor(group) with no args still throws', () {
      expect(() => flavor.customFor('revenuecat'), throwsA(isA<StateError>()));
    });

    test('name is shorthand for nameFor() — still throws', () {
      expect(() => flavor.name, throwsA(isA<StateError>()));
    });

    test('id is shorthand for idFor() — still throws', () {
      expect(() => flavor.id, throwsA(isA<StateError>()));
    });

    test('auth is shorthand for authFor() — still throws', () {
      expect(() => flavor.auth, throwsA(isA<StateError>()));
    });

    test('custom(group) is shorthand for customFor(group) — still throws', () {
      expect(() => flavor.custom('revenuecat'), throwsA(isA<StateError>()));
    });
  });

  group('AnnFlavorConfig — name/id fall back to key when nameFor()/idFor() return null', () {
    late _NullFieldsFlavor flavor;

    setUp(() {
      flavor = _NullFieldsFlavor();
      AnnFlavor.init(config: flavor, platform: AnnPlatform.android);
    });

    test('name falls back to key when nameFor() returns null', () {
      expect(flavor.nameFor(), isNull);
      expect(flavor.name, 'null_fields');
    });

    test('id falls back to key when idFor() returns null', () {
      expect(flavor.idFor(), isNull);
      expect(flavor.id, 'null_fields');
    });
  });

  group('AnnFlavorConfig — name/auth/firebaseOptions/custom are shorthand for the *For methods with no args', () {
    late _RecordingFlavor flavor;

    setUp(() {
      flavor = _RecordingFlavor();
      AnnFlavor.init(config: flavor, platform: AnnPlatform.web);
      AnnFlavor.buildTypeOverride = 'release';
    });

    tearDown(() => AnnFlavor.buildTypeOverride = null);

    test('name resolves via nameFor() using the active platform', () {
      expect(flavor.name, 'name-for-AnnPlatform.web');
      expect(flavor.lastPlatform, AnnPlatform.web);
    });

    test('id resolves via idFor() using the active platform', () {
      expect(flavor.id, 'id-for-AnnPlatform.web');
      expect(flavor.lastPlatform, AnnPlatform.web);
    });

    test('auth resolves via authFor() using the active platform/buildType', () {
      final auth = flavor.auth;
      expect(flavor.lastPlatform, AnnPlatform.web);
      expect(flavor.lastBuildType, 'release');
      expect(auth?.clientId, 'AnnPlatform.web-release');
    });

    test('firebaseOptions resolves via firebaseOptionsFor() using the active platform/buildType', () {
      flavor.firebaseOptions;
      expect(flavor.lastPlatform, AnnPlatform.web);
      expect(flavor.lastBuildType, 'release');
    });

    test('custom(group) resolves via customFor() using the active platform/buildType', () {
      final group = flavor.custom('revenuecat');
      expect(flavor.lastPlatform, AnnPlatform.web);
      expect(flavor.lastBuildType, 'release');
      expect(group?.string('group'), 'revenuecat');
    });
  });
}
