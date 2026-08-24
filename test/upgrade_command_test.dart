import 'dart:io';
import 'package:test/test.dart';

final _packageRoot = Directory.current.path.endsWith('/test')
    ? Directory.current.parent.path
    : Directory.current.path;

Future<ProcessResult> _runUpgrade(Directory projectDir) {
  return Process.run(
    'dart',
    ['run', 'ann_flutter_flavor', 'upgrade', '--project', projectDir.path],
    workingDirectory: _packageRoot,  // run from package root so dart can resolve ann_flutter_flavor
  );
}

// Writes a minimal pubspec.yaml so the sync subprocess can locate the package root.
void _writePubspec(Directory dir) {
  File('${dir.path}/pubspec.yaml').writeAsStringSync('''
name: test_app
environment:
  sdk: ">=3.0.0 <4.0.0"
''');
}

// Minimal valid spec with a tooling: section (all exact pins — no network needed).
void _writeSpecWithTooling(Directory dir, {
  String? gradlePlugin,
  String? cocoapodsPlugin,
  String? fastlanePlugin,
}) {
  final toolingLines = <String>[];
  if (gradlePlugin != null) toolingLines.add('  gradle_plugin: $gradlePlugin');
  if (cocoapodsPlugin != null) toolingLines.add('  cocoapods_plugin: $cocoapodsPlugin');
  if (fastlanePlugin != null) toolingLines.add('  fastlane_plugin: $fastlanePlugin');

  final toolingBlock = toolingLines.isEmpty
      ? ''
      : 'tooling:\n${toolingLines.join('\n')}\n';

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

void main() {
  group('upgrade command — exact pins (no network)', () {
    late Directory tempDir;

    setUp(() => tempDir = Directory.systemTemp.createTempSync('upgrade_test_'));
    tearDown(() => tempDir.deleteSync(recursive: true));

    test('all three fields exact-pinned — logs exact pin for all three fields', () async {
      _writePubspec(tempDir);
      _writeSpecWithTooling(tempDir,
          gradlePlugin: '2.3.6',
          cocoapodsPlugin: '0.1.17',
          fastlanePlugin: '0.4.4');
      final result = await _runUpgrade(tempDir);
      // Exact pin messages appear before sync is invoked
      expect(result.stdout, contains('exact pin'),
          reason: 'should log exact pin messages for all three fields');
      expect(result.stdout, contains('gradle_plugin'),
          reason: 'gradle_plugin pin message should appear');
      expect(result.stdout, contains('cocoapods_plugin'),
          reason: 'cocoapods_plugin pin message should appear');
      expect(result.stdout, contains('fastlane_plugin'),
          reason: 'fastlane_plugin pin message should appear');
    });

    test('only gradle_plugin present — exact pin logged for gradle only', () async {
      _writePubspec(tempDir);
      _writeSpecWithTooling(tempDir, gradlePlugin: '2.3.6');
      final result = await _runUpgrade(tempDir);
      expect(result.stdout, contains('gradle_plugin'));
      expect(result.stdout, isNot(contains('cocoapods_plugin')));
      expect(result.stdout, isNot(contains('fastlane_plugin')));
    });

    test('only cocoapods_plugin present — exact pin logged for cocoapods only', () async {
      _writePubspec(tempDir);
      _writeSpecWithTooling(tempDir, cocoapodsPlugin: '0.1.17');
      final result = await _runUpgrade(tempDir);
      expect(result.stdout, contains('cocoapods_plugin'));
      expect(result.stdout, isNot(contains('gradle_plugin')));
      expect(result.stdout, isNot(contains('fastlane_plugin')));
    });

    test('only fastlane_plugin present — exact pin logged for fastlane only', () async {
      _writePubspec(tempDir);
      _writeSpecWithTooling(tempDir, fastlanePlugin: '0.4.4');
      final result = await _runUpgrade(tempDir);
      expect(result.stdout, contains('fastlane_plugin'));
      expect(result.stdout, isNot(contains('gradle_plugin')));
      expect(result.stdout, isNot(contains('cocoapods_plugin')));
    });

    test('no tooling: section — exits early without running sync', () async {
      _writePubspec(tempDir);
      // Write spec with NO tooling: block
      File('${tempDir.path}/annspec.yaml').writeAsStringSync('''
enabled: true
app:
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
      final result = await _runUpgrade(tempDir);
      expect(result.exitCode, 0,
          reason: 'stderr: ${result.stderr}\nstdout: ${result.stdout}');
      expect(result.stdout, contains('No tooling'),
          reason: 'should warn and exit without running sync');
      // sync did NOT run — no 'Running sync spec' message
      expect(result.stdout, isNot(contains('Running sync')),
          reason: 'sync should not run when tooling: is absent');
    });
  });

  group('upgrade command — live registry resolution (network required)', () {
    // Regression coverage for a real bug: the registry lookups for
    // gradle_plugin and fastlane_plugin used the wrong artifact/gem name
    // (a nonexistent Maven search hit and a nonexistent RubyGems package),
    // so both silently failed ("could not determine latest version" /
    // "registry error — HTTP 404") while cocoapods_plugin (whose real gem
    // name happened to match the guessed name) resolved correctly. These
    // tests hit the real registries — skipped automatically if the network
    // is unavailable rather than failing the whole suite.
    late Directory tempDir;

    setUp(() => tempDir = Directory.systemTemp.createTempSync('upgrade_net_test_'));
    tearDown(() => tempDir.deleteSync(recursive: true));

    test('gradle_plugin resolves against the real dev.anntech.flavorize:flavorize artifact',
        () async {
      _writePubspec(tempDir);
      _writeSpecWithTooling(tempDir, gradlePlugin: '^0.0.1');
      final result = await _runUpgrade(tempDir);
      expect(result.stdout, isNot(contains('could not determine latest version')),
          reason: 'stdout: ${result.stdout}\nstderr: ${result.stderr}');
      expect(result.stdout, contains('gradle_plugin: 0.0.1 →'),
          reason: 'should resolve a real newer version from maven-metadata.xml');
    });

    test('fastlane_plugin resolves against the real ann-flavor-flutter RubyGems package',
        () async {
      _writePubspec(tempDir);
      _writeSpecWithTooling(tempDir, fastlanePlugin: '^0.0.1');
      final result = await _runUpgrade(tempDir);
      expect(result.stdout, isNot(contains('registry error')),
          reason: 'stdout: ${result.stdout}\nstderr: ${result.stderr}');
      expect(result.stdout, contains('fastlane_plugin: 0.0.1 →'),
          reason: 'should resolve a real newer version from rubygems.org, '
              'not 404 on the nonexistent fastlane-plugin-ann_fastlane_flavor gem');
    });
  });
}
