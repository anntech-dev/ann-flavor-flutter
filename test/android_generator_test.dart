import 'dart:io';
import 'package:test/test.dart';
import '../lib_cli/generators/android_generator.dart';
import '../lib_cli/spec/annspec_reader.dart';

void _writeSpec(Directory dir, {String? gradlePluginConstraint}) {
  final toolingBlock = gradlePluginConstraint != null
      ? 'tooling:\n  gradle_plugin: $gradlePluginConstraint\n'
      : '';
  File('${dir.path}/annspec.yaml').writeAsStringSync('''
enabled: true
${toolingBlock}app:
  android:
    default:
      id: com.example.test
      sdk:
        minSdk: 24
        compileSdk: 35
        targetSdk: 35
    flavor:
      app:
        name: "Test App"
        main_file: "lib/main.dart"
        version_name: "1.0.0"
        version_code: 100000
        id_suffix: .app
''');
}

void _writeAndroidProject(Directory dir) {
  Directory('${dir.path}/android').createSync();
  File('${dir.path}/android/settings.gradle.kts').writeAsStringSync('''
pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}
plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0" apply false
    id("com.android.application") version "8.7.0" apply false
    id("org.jetbrains.kotlin.android") version "1.7.10" apply false
}
include(":app")
''');
  Directory('${dir.path}/android/app').createSync();
  File('${dir.path}/android/app/build.gradle.kts').writeAsStringSync('''
plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
    id("org.jetbrains.kotlin.android")
}
''');
}

void main() {
  group('AndroidGenerator — gradle_plugin version resolution', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('android_generator_version_test_');
      _writeAndroidProject(tempDir);
    });
    tearDown(() => tempDir.deleteSync(recursive: true));

    test('tooling.gradle_plugin pinned — uses the pin directly, never calls the fetcher', () async {
      var fetchCalled = false;
      _writeSpec(tempDir, gradlePluginConstraint: '^2.3.6');
      final spec = AnnspecReader.read(tempDir.path);

      await AndroidGenerator.generate(tempDir.path, spec, (artifactId) async {
        fetchCalled = true;
        return '9.9.9';
      });

      expect(fetchCalled, isFalse,
          reason: 'a pinned constraint must never trigger a network lookup');
      final settings = File('${tempDir.path}/android/settings.gradle.kts').readAsStringSync();
      expect(settings, contains('"2.3.6"'));
    });

    test('tooling.gradle_plugin absent — calls the fetcher and uses its result', () async {
      _writeSpec(tempDir);
      final spec = AnnspecReader.read(tempDir.path);

      await AndroidGenerator.generate(tempDir.path, spec, (artifactId) async {
        expect(artifactId, 'flavorize');
        return '4.5.6';
      });

      final settings = File('${tempDir.path}/android/settings.gradle.kts').readAsStringSync();
      expect(settings, contains('"4.5.6"'),
          reason: 'the live-fetched version should be written, not any baked-in fallback');
    });

    test('tooling.gradle_plugin absent, fetch fails — sync throws instead of silently falling back', () async {
      _writeSpec(tempDir);
      final spec = AnnspecReader.read(tempDir.path);

      expect(
        () => AndroidGenerator.generate(
          tempDir.path,
          spec,
          (artifactId) async => throw Exception('network unreachable'),
        ),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('Could not resolve the ANN Gradle plugin version'),
        )),
      );
    });
  });
}
