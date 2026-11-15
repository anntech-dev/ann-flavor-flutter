import 'dart:io';
import 'package:test/test.dart';

final _packageRoot = Directory.current.path.endsWith('/test')
    ? Directory.current.parent.path
    : Directory.current.path;

// The `android_generator — _patchSettings version update` group below pins
// this exact version via tooling.gradle_plugin in its own spec fixture
// rather than exercising the live-Maven-Central-fetch fallback path — that
// path is already covered, fully offline via dependency injection, by
// test/android_generator_test.dart. Coupling this group's expectation to
// versions.yaml's real value (as an earlier version of this file did) meant
// any commit that bumped gradle_plugin locally, before that version was
// actually published, would fail CI by construction: the test read its
// expectation from versions.yaml (intent) while the generator read its
// value from Maven Central (published fact) — the two only agree after a
// publish. Pinning the fixture removes that coupling entirely.
const _pinnedGradleVersion = '9.9.9';

Future<ProcessResult> _runSync(Directory projectDir) =>
    Process.run('dart', ['run', 'ann_flutter_flavor', 'sync', '--project', projectDir.path],
        workingDirectory: _packageRoot);

void _writeMinimalSpec(Directory dir) {
  File('${dir.path}/annspec.yaml').writeAsStringSync('''
enabled: true
app:
  integrations:
    fastlane: true
  android:
    default:
      id: com.example.test
      sdk:
        minSdk: 24
        compileSdk: 35
        targetSdk: 35
    flavor:
      app:
        name: "Test"
        main_file: "lib/main.dart"
        version_name: "1.0.0"
        version_code: 100000
        id_suffix: .app
  ios:
    default:
      id: com.example.test
    flavor:
      app:
        name: "Test"
        main_file: "lib/main.dart"
        version_name: "1.0.0"
        version_code: 100000
        id_suffix: .app
''');
}

void main() {
  group('ios_generator — Podfile comment', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('podfile_test_');
      _writeMinimalSpec(tempDir);
      // Create a minimal ios/Podfile
      final iosDir = Directory('${tempDir.path}/ios')..createSync();
      File('${iosDir.path}/Podfile').writeAsStringSync(
          "platform :ios, '12.0'\n\ntarget 'Runner' do\nend\n");
    });
    tearDown(() => tempDir.deleteSync(recursive: true));

    test('Podfile gets comment and the require line', () async {
      await _runSync(tempDir);
      final content = File('${tempDir.path}/ios/Podfile').readAsStringSync();
      expect(content, contains("# Added by ann_flutter_flavor — multi-flavor iOS build configuration"));
      expect(content, contains("require 'ann-flavor-cocoapods'"));
      // 'annai-flutter-flavor' is an old, pre-rename alias that just forwards
      // to the same code under a different name — deliberately no longer
      // written into fresh Podfiles.
      expect(content, isNot(contains("require 'annai-flutter-flavor'")));
      // Comment must appear before the require
      final commentIdx = content.indexOf('# Added by ann_flutter_flavor');
      final requireIdx = content.indexOf("require 'ann-flavor-cocoapods'");
      expect(requireIdx, greaterThan(commentIdx), reason: 'ann-flavor-cocoapods require must follow the comment');
    });

    test('Podfile is not patched twice on re-run', () async {
      await _runSync(tempDir);
      await _runSync(tempDir);
      final content = File('${tempDir.path}/ios/Podfile').readAsStringSync();
      expect("require 'ann-flavor-cocoapods'".allMatches(content).length, 1,
          reason: 'ann-flavor-cocoapods require should appear exactly once');
    });

    // Regression coverage for ann-flavor-tooling#61: annai_ios_podfile_setup
    // must be called from post_integrate, not post_install — post_install
    // fires before CocoaPods has integrated/saved the user's Xcode project,
    // so build phases it injects there are silently lost.
    test('Podfile without the call gets a post_integrate hook added', () async {
      await _runSync(tempDir);
      final content = File('${tempDir.path}/ios/Podfile').readAsStringSync();
      expect(content, contains('post_integrate do |installer|'));
      expect(content, contains('annai_ios_podfile_setup(installer)'));
    });

    test('post_integrate hook is not duplicated on re-run', () async {
      await _runSync(tempDir);
      await _runSync(tempDir);
      final content = File('${tempDir.path}/ios/Podfile').readAsStringSync();
      expect('annai_ios_podfile_setup'.allMatches(content).length, 1,
          reason: 'annai_ios_podfile_setup should appear exactly once');
      expect('post_integrate do'.allMatches(content).length, 1,
          reason: 'post_integrate block should appear exactly once');
    });

    test('does not insert a second call when annai_ios_podfile_setup already exists anywhere (e.g. the pre-#61 post_install pattern)', () async {
      // Simulates a project migrated by hand to the correct post_integrate
      // hook, or one still using the old (broken but pre-existing) post_install
      // placement — either way, sync must not add a duplicate call.
      final podfile = File('${tempDir.path}/ios/Podfile');
      podfile.writeAsStringSync(
          "platform :ios, '12.0'\n\n"
          "target 'Runner' do\nend\n\n"
          "post_install do |installer|\n"
          "  annai_ios_podfile_setup(installer)\n"
          "end\n");
      await _runSync(tempDir);
      final content = podfile.readAsStringSync();
      expect('annai_ios_podfile_setup'.allMatches(content).length, 1,
          reason: 'existing call must not be duplicated');
      expect(content, isNot(contains('post_integrate do')),
          reason: 'no post_integrate block should be added when the call already exists elsewhere');
    });
  });

  group('fastlane_generator — Gemfile comment', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('gemfile_test_');
      _writeMinimalSpec(tempDir);
    });
    tearDown(() => tempDir.deleteSync(recursive: true));

    test('new Gemfile contains comment before ann-flavor-fastlane gem', () async {
      await _runSync(tempDir);
      final gemfile = File('${tempDir.path}/Gemfile');
      expect(gemfile.existsSync(), isTrue);
      final content = gemfile.readAsStringSync();
      expect(content, contains('# Added by ann_flutter_flavor — Fastlane integration'));
      final commentIdx = content.indexOf('# Added by ann_flutter_flavor — Fastlane integration');
      final gemIdx     = content.indexOf("gem 'ann-flavor-fastlane'");
      expect(gemIdx, greaterThan(commentIdx),
          reason: 'Comment must appear before the gem line');
    });

    test('existing Gemfile gets comment+gem pair appended', () async {
      File('${tempDir.path}/Gemfile').writeAsStringSync(
          'source "https://rubygems.org"\ngem "fastlane"\n');
      await _runSync(tempDir);
      final content = File('${tempDir.path}/Gemfile').readAsStringSync();
      expect(content, contains('# Added by ann_flutter_flavor — Fastlane integration'));
      expect(content, contains("gem 'ann-flavor-fastlane'"));
    });

    test('Gemfile is not patched twice on re-run', () async {
      await _runSync(tempDir);
      await _runSync(tempDir);
      final content = File('${tempDir.path}/Gemfile').readAsStringSync();
      expect('ann-flavor-fastlane'.allMatches(content).length, 1,
          reason: 'gem line should appear exactly once');
    });

    test('does not add ann-flavor-fastlane when already present with double quotes', () async {
      File('${tempDir.path}/Gemfile').writeAsStringSync(
          'source "https://rubygems.org"\ngem "fastlane"\ngem "ann-flavor-fastlane"\n');
      await _runSync(tempDir);
      final content = File('${tempDir.path}/Gemfile').readAsStringSync();
      expect('ann-flavor-fastlane'.allMatches(content).length, 1,
          reason: 'gem must not be duplicated when already present with double quotes');
    });

    // Plan 040 (STEP-02): FastlaneGenerator.generate must recognize the
    // pre-rename gem name as "already present" too, so it doesn't append a
    // second, differently-named line before sync_command.dart's
    // _ensureFastlaneGemEntry gets a chance to migrate the old line in
    // place -- without this, a project on the old name would end up with
    // two Fastlane gem entries after one sync.
    test('does not duplicate when the legacy pre-rename gem name is already present', () async {
      File('${tempDir.path}/Gemfile').writeAsStringSync(
          "source 'https://rubygems.org'\ngem 'fastlane'\ngem 'ann-flavor-flutter'\n");
      await _runSync(tempDir);
      final content = File('${tempDir.path}/Gemfile').readAsStringSync();
      // sync_command.dart's migration rewrites the legacy line to the new
      // name in the same run -- exactly one Fastlane gem entry total,
      // referencing the new name, not two.
      expect('ann-flavor-fastlane'.allMatches(content).length, 1);
      expect(content, isNot(contains('ann-flavor-flutter')));
    });
  });

  group('android_generator — _patchSettings version update', () {
    late Directory tempDir;

    // Pins tooling.gradle_plugin so this group's expectations never depend
    // on the live Maven Central fetch / versions.yaml's real value — see the
    // comment on _pinnedGradleVersion above.
    void _writeSpecWithPinnedGradleVersion(Directory dir) {
      File('${dir.path}/annspec.yaml').writeAsStringSync('''
enabled: true
tooling:
  gradle_plugin: $_pinnedGradleVersion
app:
  integrations:
    fastlane: true
  android:
    default:
      id: com.example.test
      sdk:
        minSdk: 24
        compileSdk: 35
        targetSdk: 35
    flavor:
      app:
        name: "Test"
        main_file: "lib/main.dart"
        version_name: "1.0.0"
        version_code: 100000
        id_suffix: .app
  ios:
    default:
      id: com.example.test
    flavor:
      app:
        name: "Test"
        main_file: "lib/main.dart"
        version_name: "1.0.0"
        version_code: 100000
        id_suffix: .app
''');
    }

    Directory _makeAndroidDir(String settingsContent, {bool kts = true}) {
      final androidDir = Directory('${tempDir.path}/android')..createSync(recursive: true);
      final appDir = Directory('${androidDir.path}/app')..createSync(recursive: true);
      final filename = kts ? 'settings.gradle.kts' : 'settings.gradle';
      File('${androidDir.path}/$filename').writeAsStringSync(settingsContent);
      File('${appDir.path}/build.gradle.kts').writeAsStringSync('''
plugins {
    id("com.android.application")
}
android {
    defaultConfig {
        applicationId = "com.example.test"
        minSdk = 24
    }
}
''');
      return androidDir;
    }

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('patch_version_test_');
      _writeSpecWithPinnedGradleVersion(tempDir);
    });
    tearDown(() => tempDir.deleteSync(recursive: true));

    test('updates stale version in KTS settings', () async {
      _makeAndroidDir('''
pluginManagement {
    repositories {
        google()
        mavenCentral()
    }
}
plugins {
    id("dev.anntech.flavorize") version "0.0.1" apply false
}
''');
      await _runSync(tempDir);
      final content = File('${tempDir.path}/android/settings.gradle.kts').readAsStringSync();
      expect(content, contains('version "$_pinnedGradleVersion"'),
          reason: 'Version should be updated to the pinned tooling.gradle_plugin');
      expect(content, isNot(contains('version "0.0.1"')),
          reason: 'Stale version should be replaced');
    });

    test('updates stale version in Groovy settings', () async {
      _makeAndroidDir('''
pluginManagement {
    repositories {
        google()
        mavenCentral()
    }
}
plugins {
    id 'dev.anntech.flavorize' version '0.0.1' apply false
}
''', kts: false);
      await _runSync(tempDir);
      final content = File('${tempDir.path}/android/settings.gradle').readAsStringSync();
      expect(content, contains("version '$_pinnedGradleVersion'"),
          reason: 'Version should be updated to the pinned tooling.gradle_plugin');
      expect(content, isNot(contains("version '0.0.1'")),
          reason: 'Stale version should be replaced');
    });

    test('does not write file when version already current', () async {
      _makeAndroidDir('''
pluginManagement {
    repositories {
        google()
        mavenCentral()
    }
}
plugins {
    id("dev.anntech.flavorize") version "$_pinnedGradleVersion" apply false
}
''');
      final file = File('${tempDir.path}/android/settings.gradle.kts');
      await _runSync(tempDir);
      final content = file.readAsStringSync();
      // Version should remain the same and appear exactly once
      expect('version "$_pinnedGradleVersion"'.allMatches(content).length, 1,
          reason: 'Version line should appear exactly once — no duplicate inserted');
    });
  });

  group('android_generator — no applicationId / minSdk patching', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('android_test_');
      _writeMinimalSpec(tempDir);
      // Create a minimal android project structure
      final appDir = Directory('${tempDir.path}/android/app')..createSync(recursive: true);
      File('${appDir.path}/build.gradle.kts').writeAsStringSync('''
plugins {
    id("com.android.application")
}
android {
    defaultConfig {
        applicationId = "com.original.id"
        minSdk = 21
    }
}
''');
      final settingsFile = File('${tempDir.path}/android/settings.gradle.kts');
      settingsFile.writeAsStringSync('''
pluginManagement {
    repositories {
        google()
        mavenCentral()
    }
    plugins {}
}
plugins {}
''');
    });
    tearDown(() => tempDir.deleteSync(recursive: true));

    test('sync does not overwrite applicationId in build.gradle.kts', () async {
      await _runSync(tempDir);
      final content = File('${tempDir.path}/android/app/build.gradle.kts').readAsStringSync();
      expect(content, contains('applicationId = "com.original.id"'),
          reason: 'applicationId must not be changed by sync');
    });

    test('sync does not overwrite minSdk in build.gradle.kts', () async {
      await _runSync(tempDir);
      final content = File('${tempDir.path}/android/app/build.gradle.kts').readAsStringSync();
      expect(content, contains('minSdk = 21'),
          reason: 'minSdk must not be changed by sync');
    });
  });
}
