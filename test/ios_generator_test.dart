import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';

final _packageRoot = Directory.current.path.endsWith('/test')
    ? Directory.current.parent.path
    : Directory.current.path;

Future<ProcessResult> _runSync(Directory projectDir) =>
    Process.run('dart', ['run', 'ann_flutter_flavor', 'sync', '--project', projectDir.path],
        workingDirectory: _packageRoot);

const _stockInfoPlist = '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDisplayName</key>
	<string>\$(APP_DISPLAY_NAME)</string>
	<key>CFBundleIdentifier</key>
	<string>\$(PRODUCT_BUNDLE_IDENTIFIER)</string>
	<key>CFBundleShortVersionString</key>
	<string>\$(FLUTTER_BUILD_NAME)</string>
	<key>CFBundleVersion</key>
	<string>\$(FLUTTER_BUILD_NUMBER)</string>
	<key>NSCameraUsageDescription</key>
	<string>Needs camera access</string>
</dict>
</plist>
''';

void _writeIosProject(Directory dir, {String infoPlist = _stockInfoPlist}) {
  final iosDir = Directory('${dir.path}/ios')..createSync();
  File('${iosDir.path}/Podfile')
      .writeAsStringSync("platform :ios, '12.0'\n\ntarget 'Runner' do\nend\n");
  Directory('${iosDir.path}/Flutter').createSync();
  final runnerDir = Directory('${iosDir.path}/Runner')..createSync();
  File('${runnerDir.path}/Info.plist').writeAsStringSync(infoPlist);
}

void _writeSpec(Directory dir, {String extraIos = ''}) {
  File('${dir.path}/annspec.yaml').writeAsStringSync('''
enabled: true
app:
  ios:
    default:
      id: com.example.test
$extraIos
    flavor:
      app:
        name: "Test App"
        main_file: "lib/main.dart"
        version_name: "1.2.3"
        version_code: 100045
        id_suffix: .app
''');
}

/// Writes a fake `.flutter-plugins-dependencies` at [dir]'s root and a fake
/// plugin package under `[dir]/fake_plugins/<name>/` shipping the given
/// `ios/ann-Info.plist`/`ios/ann-Runner.entitlements` content (pass null to
/// omit either file, matching the common "plugin contributes nothing" case).
/// Safe to call multiple times on the same [dir] to register several plugins.
void _writeFakePlugin(
  Directory dir, {
  required String name,
  String? infoPlistXml,
  String? entitlementsXml,
}) {
  final pluginIosDir = Directory('${dir.path}/fake_plugins/$name/ios')
    ..createSync(recursive: true);
  if (infoPlistXml != null) {
    File('${pluginIosDir.path}/ann-Info.plist').writeAsStringSync(infoPlistXml);
  }
  if (entitlementsXml != null) {
    File('${pluginIosDir.path}/ann-Runner.entitlements').writeAsStringSync(entitlementsXml);
  }

  final depsFile = File('${dir.path}/.flutter-plugins-dependencies');
  final existing = depsFile.existsSync()
      ? (jsonDecode(depsFile.readAsStringSync()) as Map<String, dynamic>)
      : {
          'plugins': {'ios': <dynamic>[]}
        };
  final iosList = (existing['plugins'] as Map<String, dynamic>)['ios'] as List<dynamic>;
  iosList.add({
    'name': name,
    'path': '${dir.path}/fake_plugins/$name/',
    'native_build': true,
  });
  depsFile.writeAsStringSync(jsonEncode(existing));
}

const _plistWrap = '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
%s
</dict>
</plist>
''';

String _plist(String bodyXml) => _plistWrap.replaceFirst('%s', bodyXml);

void main() {
  group('ios_generator — xcconfig output', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('ios_xcconfig_test_');
      _writeSpec(tempDir);
      _writeIosProject(tempDir);
    });
    tearDown(() => tempDir.deleteSync(recursive: true));

    test('generates xcconfig files under ios/ann/xcconfig/, not ios/Flutter/', () async {
      await _runSync(tempDir);
      final release = File('${tempDir.path}/ios/ann/xcconfig/appRelease.xcconfig');
      final debug = File('${tempDir.path}/ios/ann/xcconfig/appDebug.xcconfig');
      expect(release.existsSync(), isTrue);
      expect(debug.existsSync(), isTrue);
      expect(File('${tempDir.path}/ios/Flutter/appRelease.xcconfig').existsSync(), isFalse);

      final content = release.readAsStringSync();
      expect(content, contains('PRODUCT_BUNDLE_IDENTIFIER=com.example.test.app'));
      expect(content, contains('APP_NAME=Test App'));
      expect(content, contains('FLUTTER_BUILD_NAME=1.2.3'));
      expect(content, contains('FLUTTER_BUILD_NUMBER=100045'));
      expect(content, contains('#include "../../Flutter/Release.xcconfig"'));
      expect(content, contains('#include? "../../Pods/Target Support Files/Pods-Runner/Pods-Runner.release-app.xcconfig"'));
    });

    test('sets ASSETCATALOG_COMPILER_APPICON_NAME unconditionally, matching the icon set name IosIconGenerator writes into', () async {
      await _runSync(tempDir);
      final content = File('${tempDir.path}/ios/ann/xcconfig/appRelease.xcconfig').readAsStringSync();
      expect(content, contains('ASSETCATALOG_COMPILER_APPICON_NAME=AppAppIcon'));
    });

    test('a changed spec value fully propagates on re-run (delete-and-regenerate, not patch)', () async {
      await _runSync(tempDir);
      // Simulate a stale, hand-edited value that a patch-in-place generator
      // would have left untouched — delete-and-regenerate must overwrite it.
      final release = File('${tempDir.path}/ios/ann/xcconfig/appRelease.xcconfig');
      var content = release.readAsStringSync();
      content = content.replaceFirst('APP_NAME=Test App', 'APP_NAME=Stale Manually Edited Name');
      release.writeAsStringSync(content);

      await _runSync(tempDir);
      final regenerated = release.readAsStringSync();
      expect(regenerated, contains('APP_NAME=Test App'));
      expect(regenerated, isNot(contains('Stale Manually Edited Name')));
    });

    test('a removed flavor\'s xcconfig is deleted, not left behind', () async {
      await _runSync(tempDir);
      expect(File('${tempDir.path}/ios/ann/xcconfig/appRelease.xcconfig').existsSync(), isTrue);

      // Rewrite the spec with a differently-named flavor.
      _writeSpec(tempDir);
      File('${tempDir.path}/annspec.yaml').writeAsStringSync(
          File('${tempDir.path}/annspec.yaml').readAsStringSync().replaceAll('app:\n        name', 'renamed:\n        name'));
      await _runSync(tempDir);

      expect(File('${tempDir.path}/ios/ann/xcconfig/appRelease.xcconfig').existsSync(), isFalse,
          reason: 'stale xcconfig for a flavor no longer in the spec must not survive delete-and-regenerate');
    });
  });

  group('ios_generator — sdk xcconfig keys', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('ios_sdk_test_');
    });
    tearDown(() => tempDir.deleteSync(recursive: true));

    test('writes IPHONEOS_DEPLOYMENT_TARGET and SWIFT_VERSION when sdk.ios/sdk.swift_version are set', () async {
      _writeSpec(tempDir, extraIos: '''
      sdk:
        ios: "15.0"
        swift_version: "5.0"
''');
      _writeIosProject(tempDir);
      await _runSync(tempDir);

      final content = File('${tempDir.path}/ios/ann/xcconfig/appRelease.xcconfig').readAsStringSync();
      expect(content, contains('IPHONEOS_DEPLOYMENT_TARGET=15.0'));
      expect(content, contains('SWIFT_VERSION=5.0'));
    });

    test('omits SWIFT_VERSION when sdk.swift_version is not set', () async {
      _writeSpec(tempDir, extraIos: '''
      sdk:
        ios: "15.0"
''');
      _writeIosProject(tempDir);
      await _runSync(tempDir);

      final content = File('${tempDir.path}/ios/ann/xcconfig/appRelease.xcconfig').readAsStringSync();
      expect(content, contains('IPHONEOS_DEPLOYMENT_TARGET=15.0'));
      expect(content, isNot(contains('SWIFT_VERSION')));
    });

    test('writes neither key when the sdk block is absent entirely', () async {
      _writeSpec(tempDir);
      _writeIosProject(tempDir);
      await _runSync(tempDir);

      final content = File('${tempDir.path}/ios/ann/xcconfig/appRelease.xcconfig').readAsStringSync();
      expect(content, isNot(contains('IPHONEOS_DEPLOYMENT_TARGET')));
      expect(content, isNot(contains('SWIFT_VERSION')));
    });
  });

  group('ios_generator — env: generic xcconfig keys', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('ios_env_test_');
    });
    tearDown(() => tempDir.deleteSync(recursive: true));

    test('writes env: key-value pairs into the generated xcconfig', () async {
      _writeSpec(tempDir, extraIos: '''
      env:
        MY_CUSTOM_KEY: my_custom_value
''');
      _writeIosProject(tempDir);
      await _runSync(tempDir);

      final content = File('${tempDir.path}/ios/ann/xcconfig/appRelease.xcconfig').readAsStringSync();
      expect(content, contains('MY_CUSTOM_KEY=my_custom_value'));
    });

    test('env: cannot override the tool\'s own reserved keys — built-ins always win', () async {
      _writeSpec(tempDir, extraIos: '''
      env:
        PRODUCT_BUNDLE_IDENTIFIER: should-not-win
''');
      _writeIosProject(tempDir);
      await _runSync(tempDir);

      final content = File('${tempDir.path}/ios/ann/xcconfig/appRelease.xcconfig').readAsStringSync();
      expect(content, contains('PRODUCT_BUNDLE_IDENTIFIER=com.example.test.app'));
      expect(content, isNot(contains('should-not-win')));
    });

    test('REVERSED_CLIENT_ID is derived from auth.reversedClientId — never needs to be duplicated in env:', () async {
      _writeSpec(tempDir, extraIos: '''
      build_types:
        release:
          auth:
            reversedClientId: "com.googleusercontent.apps.123-abc"
''');
      _writeIosProject(tempDir);
      await _runSync(tempDir);

      final content = File('${tempDir.path}/ios/ann/xcconfig/appRelease.xcconfig').readAsStringSync();
      expect(content, contains('REVERSED_CLIENT_ID=com.googleusercontent.apps.123-abc'));
    });

    test('omits REVERSED_CLIENT_ID entirely when auth.reversedClientId is not set', () async {
      _writeSpec(tempDir);
      _writeIosProject(tempDir);
      await _runSync(tempDir);

      final content = File('${tempDir.path}/ios/ann/xcconfig/appRelease.xcconfig').readAsStringSync();
      expect(content, isNot(contains('REVERSED_CLIENT_ID')));
    });
  });

  group('ios_generator — Podfile platform :ios line', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('ios_podfile_platform_test_');
      _writeSpec(tempDir, extraIos: '''
      sdk:
        ios: "15.0"
''');
    });
    tearDown(() => tempDir.deleteSync(recursive: true));

    test('uncomments a commented platform :ios line and sets it to sdk.ios', () async {
      final iosDir = Directory('${tempDir.path}/ios')..createSync();
      File('${iosDir.path}/Podfile').writeAsStringSync(
          "# Uncomment this line to define a global platform for your project\n"
          "# platform :ios, '14.0'\n\ntarget 'Runner' do\nend\n");
      Directory('${iosDir.path}/Flutter').createSync();
      final runnerDir = Directory('${iosDir.path}/Runner')..createSync();
      File('${runnerDir.path}/Info.plist').writeAsStringSync(_stockInfoPlist);

      await _runSync(tempDir);
      final content = File('${iosDir.path}/Podfile').readAsStringSync();
      expect(content, contains("platform :ios, '15.0'"));
      expect(content, isNot(contains("# platform :ios, '14.0'")));
    });

    test('updates an active platform :ios line with a different version', () async {
      _writeIosProject(tempDir); // writes platform :ios, '12.0' active
      await _runSync(tempDir);
      final content = File('${tempDir.path}/ios/Podfile').readAsStringSync();
      expect(content, contains("platform :ios, '15.0'"));
      expect(content, isNot(contains("platform :ios, '12.0'")));
    });

    test('inserts a platform :ios line when none exists at all', () async {
      final iosDir = Directory('${tempDir.path}/ios')..createSync();
      File('${iosDir.path}/Podfile').writeAsStringSync("target 'Runner' do\nend\n");
      Directory('${iosDir.path}/Flutter').createSync();
      final runnerDir = Directory('${iosDir.path}/Runner')..createSync();
      File('${runnerDir.path}/Info.plist').writeAsStringSync(_stockInfoPlist);

      await _runSync(tempDir);
      final content = File('${iosDir.path}/Podfile').readAsStringSync();
      expect(content, contains("platform :ios, '15.0'"));
    });

    test('re-running sync with the same sdk.ios value is idempotent (no diff)', () async {
      _writeIosProject(tempDir);
      await _runSync(tempDir);
      final firstContent = File('${tempDir.path}/ios/Podfile').readAsStringSync();

      await _runSync(tempDir);
      final secondContent = File('${tempDir.path}/ios/Podfile').readAsStringSync();
      expect(secondContent, firstContent);
    });

    test('leaves the Podfile platform line untouched when sdk.ios is not set', () async {
      final noSdkDir = Directory.systemTemp.createTempSync('ios_podfile_no_sdk_test_');
      addTearDown(() => noSdkDir.deleteSync(recursive: true));
      _writeSpec(noSdkDir);
      _writeIosProject(noSdkDir); // platform :ios, '12.0'
      await _runSync(noSdkDir);
      final content = File('${noSdkDir.path}/ios/Podfile').readAsStringSync();
      expect(content, contains("platform :ios, '12.0'"));
    });
  });

  group('ios_generator — Runner/Info.plist xcconfig-backed key repair (plan 038 Solution §1a)', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('ios_infoplist_repair_test_');
    });
    tearDown(() => tempDir.deleteSync(recursive: true));

    test('adds a missing key with the correct placeholder', () async {
      _writeSpec(tempDir);
      _writeIosProject(tempDir, infoPlist: '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>NSCameraUsageDescription</key>
	<string>Needs camera access</string>
</dict>
</plist>
''');
      await _runSync(tempDir);

      final content = File('${tempDir.path}/ios/Runner/Info.plist').readAsStringSync();
      expect(content, contains(r'<key>CFBundleDisplayName</key>'));
      expect(content, contains(r'<string>$(APP_NAME)</string>'));
      expect(content, contains(r'<key>CFBundleIdentifier</key>'));
      expect(content, contains(r'<string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>'));
      expect(content, contains(r'<key>CFBundleShortVersionString</key>'));
      expect(content, contains(r'<string>$(FLUTTER_BUILD_NAME)</string>'));
      expect(content, contains(r'<key>CFBundleVersion</key>'));
      expect(content, contains(r'<string>$(FLUTTER_BUILD_NUMBER)</string>'));
      // Developer-owned content untouched.
      expect(content, contains('<key>NSCameraUsageDescription</key>'));
    });

    test('rewrites a wrong or literal value back to the correct placeholder', () async {
      _writeSpec(tempDir);
      _writeIosProject(tempDir, infoPlist: '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDisplayName</key>
	<string>\$(ANN_APP_NAME)</string>
	<key>CFBundleIdentifier</key>
	<string>com.hardcoded.literal</string>
</dict>
</plist>
''');
      await _runSync(tempDir);

      final content = File('${tempDir.path}/ios/Runner/Info.plist').readAsStringSync();
      expect(content, contains(r'<string>$(APP_NAME)</string>'));
      expect(content, isNot(contains(r'$(ANN_APP_NAME)')));
      expect(content, contains(r'<string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>'));
      expect(content, isNot(contains('com.hardcoded.literal')));
    });

    test('is a no-op when all keys are already correct — file byte-unchanged, no spurious diff', () async {
      _writeSpec(tempDir);
      _writeIosProject(tempDir); // _stockInfoPlist already has correct placeholders for the non-admob keys
      await _runSync(tempDir);

      final plistFile = File('${tempDir.path}/ios/Runner/Info.plist');
      final afterFirstSync = plistFile.readAsStringSync();
      final mtimeAfterFirstSync = plistFile.lastModifiedSync();

      await Future.delayed(const Duration(seconds: 1)); // ensure a real mtime tick is observable
      await _runSync(tempDir);

      expect(plistFile.readAsStringSync(), equals(afterFirstSync));
      expect(plistFile.lastModifiedSync(), equals(mtimeAfterFirstSync),
          reason: 'an already-correct Runner/Info.plist must not be rewritten on a no-op sync');
    });

    test('GADApplicationIdentifier is added only when admob is configured', () async {
      _writeSpec(tempDir, extraIos: '');
      _writeIosProject(tempDir);
      await _runSync(tempDir);
      expect(File('${tempDir.path}/ios/Runner/Info.plist').readAsStringSync(),
          isNot(contains('GADApplicationIdentifier')));
    });

    test('GADApplicationIdentifier is added with the correct placeholder when admob is configured', () async {
      File('${tempDir.path}/annspec.yaml').writeAsStringSync('''
enabled: true
app:
  ios:
    default:
      id: com.example.test
    flavor:
      app:
        name: "Test App"
        main_file: "lib/main.dart"
        version_name: "1.2.3"
        version_code: 100045
        id_suffix: .app
        admob:
          gms_ads_id: "ca-app-pub-1234567890~1234567890"
''');
      _writeIosProject(tempDir);
      await _runSync(tempDir);

      final content = File('${tempDir.path}/ios/Runner/Info.plist').readAsStringSync();
      expect(content, contains('<key>GADApplicationIdentifier</key>'));
      expect(content, contains(r'<string>$(GAD_APPLICATION_IDENTIFIER)</string>'));
    });

    test('never removes GADApplicationIdentifier when admob is not configured but the key pre-exists (developer-owned)', () async {
      _writeSpec(tempDir);
      _writeIosProject(tempDir, infoPlist: '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>GADApplicationIdentifier</key>
	<string>ca-app-pub-hand-authored~0000000000</string>
</dict>
</plist>
''');
      await _runSync(tempDir);

      final content = File('${tempDir.path}/ios/Runner/Info.plist').readAsStringSync();
      expect(content, contains('ca-app-pub-hand-authored~0000000000'),
          reason: 'this tool must never delete a key the developer added for their own reasons');
    });
  });

  group('ios_generator — Info.plist generation', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('ios_infoplist_test_');
    });
    tearDown(() => tempDir.deleteSync(recursive: true));

    test('no info_plist: cascade anywhere — nothing generated (opt-in, plan 038)', () async {
      _writeSpec(tempDir);
      _writeIosProject(tempDir);
      await _runSync(tempDir);

      expect(File('${tempDir.path}/ios/ann/Info/Info-app-release.plist').existsSync(), isFalse);
      expect(File('${tempDir.path}/ios/ann/Info/Info-app-debug.plist').existsSync(), isFalse);
    });

    test('generated Info-<flavor>-<buildType>.plist contains only the info_plist: cascade — no Runner/Info.plist content, no modeled-key literals (plan 038)',
        () async {
      _writeSpec(tempDir, extraIos: '''
      info_plist:
        NSPhotoLibraryUsageDescription: "Needs photo library access"
''');
      _writeIosProject(tempDir);
      await _runSync(tempDir);

      // default.info_plist has no build-type override, so both debug and
      // release resolve identically -- confirms one file per build type is
      // actually generated, not just one shared file.
      for (final bt in ['debug', 'release']) {
        final generated = File('${tempDir.path}/ios/ann/Info/Info-app-$bt.plist');
        expect(generated.existsSync(), isTrue, reason: 'expected Info-app-$bt.plist');
        final content = generated.readAsStringSync();
        expect(content, contains('<key>NSPhotoLibraryUsageDescription</key>'));
        expect(content, contains('<string>Needs photo library access</string>'));
        // Runner/Info.plist's own stock key must NOT be copied in (plan 038 —
        // that's the new merge-time job of ann-flavor-cocoapods, not sync).
        expect(content, isNot(contains('NSCameraUsageDescription')));
        // The modeled-key literals this generator used to bake in are gone —
        // these keys are now build-setting-driven via Runner/Info.plist's own
        // $(VAR) placeholders (_ensureXcconfigBackedKeys), not duplicated here.
        expect(content, isNot(contains('CFBundleDisplayName')));
        expect(content, isNot(contains('CFBundleIdentifier')));
        expect(content, isNot(contains('CFBundleShortVersionString')));
        expect(content, isNot(contains('CFBundleVersion')));
      }
    });

    test('a build_types.debug-scoped info_plist: override only affects the debug file, not release', () async {
      _writeSpec(tempDir, extraIos: '''
      info_plist:
        NSPhotoLibraryUsageDescription: "Shared value"
      build_types:
        debug:
          info_plist:
            NSPhotoLibraryUsageDescription: "Debug-only value"
''');
      _writeIosProject(tempDir);
      await _runSync(tempDir);

      final debugContent = File('${tempDir.path}/ios/ann/Info/Info-app-debug.plist').readAsStringSync();
      final releaseContent = File('${tempDir.path}/ios/ann/Info/Info-app-release.plist').readAsStringSync();
      expect(debugContent, contains('<string>Debug-only value</string>'));
      expect(releaseContent, contains('<string>Shared value</string>'));
      expect(releaseContent, isNot(contains('Debug-only value')));
    });

    test('info_plist file-path reference (.yaml) is the only content, still no Runner/Info.plist copy', () async {
      File('${tempDir.path}/shared-info-plist.yaml').writeAsStringSync(
          'NSMicrophoneUsageDescription: "Needs microphone access"\n');
      _writeSpec(tempDir, extraIos: '''
      info_plist: "shared-info-plist.yaml"
''');
      _writeIosProject(tempDir);
      await _runSync(tempDir);

      final content = File('${tempDir.path}/ios/ann/Info/Info-app-release.plist').readAsStringSync();
      expect(content, contains('<key>NSMicrophoneUsageDescription</key>'));
      expect(content, contains('<string>Needs microphone access</string>'));
      expect(content, isNot(contains('NSCameraUsageDescription')));
    });

    test('a stale generated plist for a removed flavor is deleted, not left behind', () async {
      _writeSpec(tempDir, extraIos: '''
      info_plist:
        NSPhotoLibraryUsageDescription: "Needs photo library access"
''');
      _writeIosProject(tempDir);
      await _runSync(tempDir);
      expect(File('${tempDir.path}/ios/ann/Info/Info-app-release.plist').existsSync(), isTrue);

      File('${tempDir.path}/annspec.yaml').writeAsStringSync(
          File('${tempDir.path}/annspec.yaml').readAsStringSync().replaceAll('app:\n        name', 'renamed:\n        name'));
      await _runSync(tempDir);

      expect(File('${tempDir.path}/ios/ann/Info/Info-app-release.plist').existsSync(), isFalse);
      expect(File('${tempDir.path}/ios/ann/Info/Info-renamed-release.plist').existsSync(), isTrue);
    });

    test('a stale generated plist is deleted when the flavor keeps existing but its info_plist: cascade is removed (plan 038)', () async {
      _writeSpec(tempDir, extraIos: '''
      info_plist:
        NSPhotoLibraryUsageDescription: "Needs photo library access"
''');
      _writeIosProject(tempDir);
      await _runSync(tempDir);
      expect(File('${tempDir.path}/ios/ann/Info/Info-app-release.plist').existsSync(), isTrue);

      _writeSpec(tempDir); // re-sync with no info_plist: cascade at all
      await _runSync(tempDir);

      expect(File('${tempDir.path}/ios/ann/Info/Info-app-release.plist').existsSync(), isFalse);
    });
  });

  group('ios_generator — Entitlements generation', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('ios_entitlements_test_');
    });
    tearDown(() => tempDir.deleteSync(recursive: true));

    test('no entitlements: config anywhere and no stock Runner.entitlements — nothing generated', () async {
      _writeSpec(tempDir);
      _writeIosProject(tempDir);
      await _runSync(tempDir);

      expect(Directory('${tempDir.path}/ios/ann/Entitlements').existsSync(), isFalse);
    });

    test('generates one complete <flavor>-<buildType>.entitlements per flavor/build-type under ios/ann/Entitlements/', () async {
      _writeSpec(tempDir, extraIos: '''
      entitlements:
        com.apple.developer.applesignin:
          - Default
''');
      _writeIosProject(tempDir);
      await _runSync(tempDir);

      for (final bt in ['debug', 'release']) {
        final generated = File('${tempDir.path}/ios/ann/Entitlements/app-$bt.entitlements');
        expect(generated.existsSync(), isTrue, reason: 'expected app-$bt.entitlements');
        final content = generated.readAsStringSync();
        expect(content, contains('<key>com.apple.developer.applesignin</key>'));
      }
    });

    test('a build_types.debug-scoped entitlements: override only affects the debug file, not release', () async {
      _writeSpec(tempDir, extraIos: '''
      entitlements:
        aps-environment: production
      build_types:
        debug:
          entitlements:
            aps-environment: development
''');
      _writeIosProject(tempDir);
      await _runSync(tempDir);

      final debugContent = File('${tempDir.path}/ios/ann/Entitlements/app-debug.entitlements').readAsStringSync();
      final releaseContent = File('${tempDir.path}/ios/ann/Entitlements/app-release.entitlements').readAsStringSync();
      expect(debugContent, contains('<string>development</string>'));
      expect(releaseContent, contains('<string>production</string>'));
    });

    test('excludes stock Runner.entitlements-only keys — cascade-only output (plan 039)', () async {
      _writeSpec(tempDir, extraIos: '''
      entitlements:
        com.apple.developer.applesignin:
          - Default
''');
      _writeIosProject(tempDir);
      File('${tempDir.path}/ios/Runner/Runner.entitlements').writeAsStringSync('''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.network.client</key>
	<true/>
</dict>
</plist>
''');
      await _runSync(tempDir);

      final content = File('${tempDir.path}/ios/ann/Entitlements/app-release.entitlements').readAsStringSync();
      // Runner.entitlements' own stock key must NOT be copied in (plan 039 —
      // that's the new merge-time job of ann-flavor-cocoapods, not sync).
      expect(content, isNot(contains('com.apple.security.network.client')));
      // The annspec.yaml cascade key must still be present.
      expect(content, contains('<key>com.apple.developer.applesignin</key>'));
    });

    test('no file generated when a stock Runner.entitlements exists but no flavor has an entitlements: cascade (plan 039)', () async {
      _writeSpec(tempDir);
      _writeIosProject(tempDir);
      File('${tempDir.path}/ios/Runner/Runner.entitlements').writeAsStringSync('''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>aps-environment</key>
	<string>development</string>
</dict>
</plist>
''');
      await _runSync(tempDir);

      // Narrowed opt-in trigger: a stock template alone (no annspec.yaml
      // entitlements: anywhere) no longer produces a per-flavor generated
      // file -- the template reaches the build directly via the merge
      // phase's base-layer copy instead (ann-flavor-cocoapods, plan 039).
      expect(Directory('${tempDir.path}/ios/ann/Entitlements').existsSync(), isFalse);
    });

    test('entitlements file-path reference (.yaml) is read and unioned into the generated plist', () async {
      File('${tempDir.path}/shared-entitlements.yaml').writeAsStringSync(
          'com.apple.developer.applesignin:\n  - Default\n');
      _writeSpec(tempDir, extraIos: '''
      entitlements: "shared-entitlements.yaml"
''');
      _writeIosProject(tempDir);
      await _runSync(tempDir);

      final content = File('${tempDir.path}/ios/ann/Entitlements/app-release.entitlements').readAsStringSync();
      expect(content, contains('<key>com.apple.developer.applesignin</key>'));
    });

    test('a stale generated entitlements file for a removed flavor is deleted, not left behind', () async {
      _writeSpec(tempDir, extraIos: '''
      entitlements:
        com.apple.developer.applesignin:
          - Default
''');
      _writeIosProject(tempDir);
      await _runSync(tempDir);
      expect(File('${tempDir.path}/ios/ann/Entitlements/app-release.entitlements').existsSync(), isTrue);

      File('${tempDir.path}/annspec.yaml').writeAsStringSync(
          File('${tempDir.path}/annspec.yaml').readAsStringSync().replaceAll('app:\n        name', 'renamed:\n        name'));
      await _runSync(tempDir);

      expect(File('${tempDir.path}/ios/ann/Entitlements/app-release.entitlements').existsSync(), isFalse);
      expect(File('${tempDir.path}/ios/ann/Entitlements/renamed-release.entitlements').existsSync(), isTrue);
    });
  });

  group('ios_generator — plugin-contributed Info.plist/entitlements (plan 041)', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('ios_plugin_contrib_test_');
      _writeIosProject(tempDir);
    });
    tearDown(() => tempDir.deleteSync(recursive: true));

    test('plugin-contributed Info.plist is written to its own ios/ann/Info/merged/plugin-contributions.plist, '
        'not into the per-flavor file', () async {
      _writeSpec(tempDir);
      _writeFakePlugin(
        tempDir,
        name: 'ann_ads',
        infoPlistXml: _plist('''
	<key>NSUserTrackingUsageDescription</key>
	<string>ATT permission for \$(APP_NAME)</string>'''),
      );
      await _runSync(tempDir);

      final pluginsFile = File('${tempDir.path}/ios/ann/Info/merged/plugin-contributions.plist');
      expect(pluginsFile.existsSync(), isTrue);
      final pluginsContent = pluginsFile.readAsStringSync();
      expect(pluginsContent, contains('<key>NSUserTrackingUsageDescription</key>'));
      expect(pluginsContent, contains(r'<string>ATT permission for $(APP_NAME)</string>'));

      // No info_plist: cascade in annspec.yaml at all -- the per-flavor file
      // must not exist, and must never contain the plugin's key even if it
      // did (this file's meaning is exactly the annspec.yaml cascade, no more).
      expect(File('${tempDir.path}/ios/ann/Info/Info-app-release.plist').existsSync(), isFalse);
    });

    test('annspec.yaml info_plist: cascade and plugin contribution land in separate files, '
        'not merged together at sync time', () async {
      _writeSpec(tempDir, extraIos: '''
      info_plist:
        NSUserTrackingUsageDescription: "app override"
''');
      _writeFakePlugin(
        tempDir,
        name: 'ann_ads',
        infoPlistXml: _plist('''
	<key>NSUserTrackingUsageDescription</key>
	<string>plugin default</string>'''),
      );
      await _runSync(tempDir);

      final flavorContent = File('${tempDir.path}/ios/ann/Info/Info-app-release.plist').readAsStringSync();
      expect(flavorContent, contains('<string>app override</string>'),
          reason: 'the per-flavor file must contain only the resolved annspec.yaml cascade');
      expect(flavorContent, isNot(contains('plugin default')),
          reason: 'the plugin contribution must never be folded into the per-flavor file');

      final pluginsContent = File('${tempDir.path}/ios/ann/Info/merged/plugin-contributions.plist').readAsStringSync();
      expect(pluginsContent, contains('<string>plugin default</string>'),
          reason: 'the plugin contribution lives in its own file, unresolved against annspec.yaml '
              '-- annspec.yaml wins only at the final pod-install merge, not here');
    });

    test('plugin-contributed entitlements generate ios/ann/Entitlements/merged/plugin-contributions.entitlements '
        'even with zero annspec.yaml entitlements: cascade', () async {
      _writeSpec(tempDir);
      _writeFakePlugin(
        tempDir,
        name: 'ann_supabase_auth',
        entitlementsXml: _plist('''
	<key>com.apple.developer.applesignin</key>
	<array>
		<string>Default</string>
	</array>'''),
      );
      await _runSync(tempDir);

      expect(Directory('${tempDir.path}/ios/ann/Entitlements').existsSync(), isTrue,
          reason: 'a plugin-only contribution must not be silently dropped by the '
              '_anyFlavorHasEntitlements gate');
      final pluginsFile = File('${tempDir.path}/ios/ann/Entitlements/merged/plugin-contributions.entitlements');
      expect(pluginsFile.existsSync(), isTrue);
      expect(pluginsFile.readAsStringSync(), contains('<key>com.apple.developer.applesignin</key>'));

      // No entitlements: cascade in annspec.yaml -- no per-flavor file.
      expect(File('${tempDir.path}/ios/ann/Entitlements/app-release.entitlements').existsSync(), isFalse);
    });

    test('two plugins contributing the same key in plugin-contributions.plist — first alphabetically wins, '
        'warning logged', () async {
      _writeSpec(tempDir);
      _writeFakePlugin(
        tempDir,
        name: 'zzz_plugin',
        infoPlistXml: _plist('''
	<key>NSUserTrackingUsageDescription</key>
	<string>zzz value</string>'''),
      );
      _writeFakePlugin(
        tempDir,
        name: 'aaa_plugin',
        infoPlistXml: _plist('''
	<key>NSUserTrackingUsageDescription</key>
	<string>aaa value</string>'''),
      );
      final result = await _runSync(tempDir);

      final content = File('${tempDir.path}/ios/ann/Info/merged/plugin-contributions.plist').readAsStringSync();
      expect(content, contains('<string>aaa value</string>'));
      expect(content, isNot(contains('zzz value')));
      expect(result.stdout.toString(), contains('aaa_plugin'));
      expect(result.stdout.toString(), contains('zzz_plugin'));
      expect(result.stdout.toString(), contains('NSUserTrackingUsageDescription'));
    });

    test('a plugin with no ann-Info.plist/ann-Runner.entitlements is a no-op', () async {
      _writeSpec(tempDir);
      _writeFakePlugin(tempDir, name: 'some_plugin');
      await _runSync(tempDir);

      expect(File('${tempDir.path}/ios/ann/Info/merged/plugin-contributions.plist').existsSync(), isFalse);
      expect(File('${tempDir.path}/ios/ann/Info/Info-app-release.plist').existsSync(), isFalse);
      expect(Directory('${tempDir.path}/ios/ann/Entitlements').existsSync(), isFalse);
    });

    test('missing .flutter-plugins-dependencies is non-fatal', () async {
      _writeSpec(tempDir);
      // Deliberately no .flutter-plugins-dependencies written at all.
      final result = await _runSync(tempDir);

      expect(result.exitCode, equals(0));
    });

    test('malformed .flutter-plugins-dependencies is non-fatal', () async {
      _writeSpec(tempDir);
      File('${tempDir.path}/.flutter-plugins-dependencies').writeAsStringSync('{not valid json');
      final result = await _runSync(tempDir);

      expect(result.exitCode, equals(0));
    });
  });
}
