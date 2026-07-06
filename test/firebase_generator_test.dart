import 'dart:io';
import 'package:test/test.dart';

// Package root is one level up from the test/ directory.
final _packageRoot = Directory.current.path.endsWith('/test')
    ? Directory.current.parent.path
    : Directory.current.path;

void _writeIosConfigFileSpec(Directory dir) {
  File('${dir.path}/annspec.yaml').writeAsStringSync('''
enabled: true
app:
  integrations:
    firebase: true
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
  ios:
    default:
      id: com.example.test
    flavor:
      app:
        name: "Test App"
        main_file: "lib/main.dart"
        version_name: "1.0.0"
        version_code: 100000
        id_suffix: .app
        build_types:
          release:
            firebase:
              config_file: "keys/GoogleService-Info.plist"
''');
}

Future<ProcessResult> _runSync(Directory projectDir, {String? firebaseMode}) {
  final args = ['run', 'ann_flutter_flavor', 'sync', '--project', projectDir.path];
  if (firebaseMode != null) args.addAll(['--firebase-mode', firebaseMode]);
  return Process.run('dart', args, workingDirectory: _packageRoot);
}

void _writeProjectIdSpec(Directory dir) {
  File('${dir.path}/annspec.yaml').writeAsStringSync('''
enabled: true
app:
  integrations:
    firebase: true
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
  ios:
    default:
      id: com.example.test
    flavor:
      app:
        name: "Test App"
        main_file: "lib/main.dart"
        version_name: "1.0.0"
        version_code: 100000
        id_suffix: .app
        build_types:
          release:
            firebase:
              project_id: "my-firebase-prod"
''');
}

void _writeProjectIdSpecWithIosTarget(Directory dir) {
  File('${dir.path}/annspec.yaml').writeAsStringSync('''
enabled: true
app:
  integrations:
    firebase: true
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
  ios:
    default:
      id: com.example.test
    flavor:
      app:
        name: "Test App"
        main_file: "lib/main.dart"
        version_name: "1.0.0"
        version_code: 100000
        id_suffix: .app
        build_types:
          release:
            firebase:
              project_id: "my-firebase-prod"
              target: "RunnerPro"
''');
}

// Spec with project_id on both Android and iOS — used to verify temp routing on both platforms.
void _writeBothPlatformSpec(Directory dir) {
  File('${dir.path}/annspec.yaml').writeAsStringSync('''
enabled: true
app:
  integrations:
    firebase: true
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
        build_types:
          release:
            firebase:
              project_id: "my-firebase-prod"
  ios:
    default:
      id: com.example.test
    flavor:
      app:
        name: "Test App"
        main_file: "lib/main.dart"
        version_name: "1.0.0"
        version_code: 100000
        id_suffix: .app
        build_types:
          release:
            firebase:
              project_id: "my-firebase-prod"
''');
}

void main() {
  group('firebase_generator — iOS config_file guard', () {
    late Directory tempDir;

    setUp(() => tempDir = Directory.systemTemp.createTempSync('fbgen_test_'));
    tearDown(() => tempDir.deleteSync(recursive: true));

    test('sync exits 1 when iOS firebase block uses config_file', () async {
      _writeIosConfigFileSpec(tempDir);
      final result = await _runSync(tempDir);
      expect(result.exitCode, 1,
          reason: 'stderr: ${result.stderr}\nstdout: ${result.stdout}');
    });

    test('sync error mentions config_file is Android-only', () async {
      _writeIosConfigFileSpec(tempDir);
      final result = await _runSync(tempDir);
      final output = '${result.stdout}${result.stderr}';
      expect(
        output.toLowerCase(),
        anyOf(
          contains('android-only'),
          contains('config_file'),
          contains('project_id'),
        ),
        reason: 'Expected error mentioning config_file/Android-only, got: $output',
      );
    });

    test('no firebase options dart file generated when iOS config_file aborts step 4', () async {
      _writeIosConfigFileSpec(tempDir);
      await _runSync(tempDir);
      // Firebase options files (generated by flutterfire configure) must not exist.
      // Step 1 Dart codegen may still produce ann_flavor.g.dart — that is expected.
      final firebaseDir = Directory('${tempDir.path}/lib/generated/firebase');
      expect(
        firebaseDir.existsSync() && firebaseDir.listSync().isNotEmpty,
        isFalse,
        reason: 'No firebase options files should be generated when iOS config_file aborts step 4',
      );
    });
  });

  group('firebase_generator — script mode', () {
    late Directory tempDir;

    setUp(() => tempDir = Directory.systemTemp.createTempSync('fbscript_test_'));
    tearDown(() => tempDir.deleteSync(recursive: true));

    test('--firebase-mode script generates firebase.sh', () async {
      _writeProjectIdSpec(tempDir);
      final result = await _runSync(tempDir, firebaseMode: 'script');
      expect(result.exitCode, 0,
          reason: 'stderr: ${result.stderr}\nstdout: ${result.stdout}');
      final scriptFile = File('${tempDir.path}/lib/generated/scripts/firebase.sh');
      expect(scriptFile.existsSync(), isTrue,
          reason: 'lib/generated/scripts/firebase.sh should be created');
    });

    test('--firebase-mode script writes flutterfire configure commands', () async {
      _writeProjectIdSpec(tempDir);
      await _runSync(tempDir, firebaseMode: 'script');
      final content = File('${tempDir.path}/lib/generated/scripts/firebase.sh').readAsStringSync();
      expect(content, contains('flutterfire configure'));
      expect(content, contains('my-firebase-prod'));
      expect(content, contains('SCRIPT_DIR'));
    });

    test('--firebase-mode script does not run flutterfire inline', () async {
      _writeProjectIdSpec(tempDir);
      final result = await _runSync(tempDir, firebaseMode: 'script');
      // In script mode, sync should never exec flutterfire; stdout must not
      // contain messages that indicate an inline run.
      expect(result.stdout, isNot(contains('Running flutterfire')));
    });

    test('script contains error accumulation pattern', () async {
      _writeProjectIdSpec(tempDir);
      await _runSync(tempDir, firebaseMode: 'script');
      final content = File('${tempDir.path}/lib/generated/scripts/firebase.sh').readAsStringSync();
      expect(content, contains('EXIT_CODE=0'));
      expect(content, contains('ERROR_MESSAGES=""'));
      expect(content, contains('exit "\$EXIT_CODE"'));
      expect(content, contains('Script Execution Summary'));
    });

    test('script contains cleanup step targeting only Dart options files', () async {
      _writeProjectIdSpec(tempDir);
      await _runSync(tempDir, firebaseMode: 'script');
      final content = File('${tempDir.path}/lib/generated/scripts/firebase.sh').readAsStringSync();
      expect(content, contains('rm -f lib/generated/firebase/*_firebase_options.dart'));
      expect(content, isNot(contains('rm -rf lib/generated/firebase/*')));
      // Cleanup must appear before the first flutterfire call
      final cleanupIdx = content.indexOf('rm -f lib/generated/firebase/*_firebase_options.dart');
      final configureIdx = content.indexOf('flutterfire configure');
      expect(cleanupIdx, lessThan(configureIdx));
    });

    test('script contains bundle ID flag for iOS', () async {
      _writeProjectIdSpec(tempDir);
      await _runSync(tempDir, firebaseMode: 'script');
      final content = File('${tempDir.path}/lib/generated/scripts/firebase.sh').readAsStringSync();
      // iOS bundle ID flag (-i) with derived bundle id (base + suffix)
      expect(content, contains('-i com.example.test.app'));
    });

    test('script never includes --ios-build-config', () async {
      _writeProjectIdSpec(tempDir);
      await _runSync(tempDir, firebaseMode: 'script');
      final content = File('${tempDir.path}/lib/generated/scripts/firebase.sh').readAsStringSync();
      expect(content, isNot(contains('--ios-build-config')));
    });

    test('script includes --target with explicit value from spec', () async {
      _writeProjectIdSpecWithIosTarget(tempDir);
      await _runSync(tempDir, firebaseMode: 'script');
      final content = File('${tempDir.path}/lib/generated/scripts/firebase.sh').readAsStringSync();
      expect(content, contains('--target RunnerPro'));
    });

    test('script includes --target Runner when not set in spec', () async {
      _writeProjectIdSpec(tempDir); // no target field → default Runner
      await _runSync(tempDir, firebaseMode: 'script');
      final content = File('${tempDir.path}/lib/generated/scripts/firebase.sh').readAsStringSync();
      expect(content, contains('--target Runner'));
    });

    test('script does not contain set -euo pipefail', () async {
      _writeProjectIdSpec(tempDir);
      await _runSync(tempDir, firebaseMode: 'script');
      final content = File('${tempDir.path}/lib/generated/scripts/firebase.sh').readAsStringSync();
      expect(content, isNot(contains('set -euo pipefail')));
    });

    test('script does not define ANN_TEMP_DIR variable', () async {
      _writeProjectIdSpec(tempDir);
      await _runSync(tempDir, firebaseMode: 'script');
      final content = File('${tempDir.path}/lib/generated/scripts/firebase.sh').readAsStringSync();
      expect(content, isNot(contains('ANN_TEMP_DIR')));
    });

    test('script sets CI=true and TERM=dumb to suppress flutterfire spinners', () async {
      _writeProjectIdSpec(tempDir);
      await _runSync(tempDir, firebaseMode: 'script');
      final content = File('${tempDir.path}/lib/generated/scripts/firebase.sh').readAsStringSync();
      expect(content, contains('export CI=true'));
      expect(content, contains('export TERM=dumb'));
    });

    test('script routes android --android-out to standard path then mv to stable path', () async {
      _writeBothPlatformSpec(tempDir);
      await _runSync(tempDir, firebaseMode: 'script');
      final content = File('${tempDir.path}/lib/generated/scripts/firebase.sh').readAsStringSync();
      // flutterfire requires --android-out to be named exactly google-services.json.
      expect(content, contains('--android-out android/app/google-services.json'));
      // After success, the file is moved to the stable committed location.
      expect(content, contains('mv android/app/google-services.json lib/generated/firebase/google-services-'));
      expect(content, isNot(contains('ANN_TEMP_DIR')));
    });

    test('script routes ios --ios-out to Runner path then cp to stable path', () async {
      _writeBothPlatformSpec(tempDir);
      await _runSync(tempDir, firebaseMode: 'script');
      final content = File('${tempDir.path}/lib/generated/scripts/firebase.sh').readAsStringSync();
      // flutterfire v1.4.0 only accepts --ios-out when basename is exactly GoogleService-Info.plist
      expect(content, contains('--ios-out ios/Runner/GoogleService-Info.plist'));
      // After success, the file is copied to the stable committed location and the temp file removed.
      expect(content, contains('cp ios/Runner/GoogleService-Info.plist lib/generated/firebase/GoogleService-Info-'));
      expect(content, contains('rm ios/Runner/GoogleService-Info.plist'));
      expect(content, isNot(contains('ANN_TEMP_DIR')));
    });

    test('script uses unique stable paths per flavor/buildType combination', () async {
      _writeBothPlatformSpec(tempDir);
      await _runSync(tempDir, firebaseMode: 'script');
      final content = File('${tempDir.path}/lib/generated/scripts/firebase.sh').readAsStringSync();
      // Android: mv destinations must all be distinct stable paths.
      final mvMatches = RegExp(r'mv android/app/google-services\.json (\S+)').allMatches(content);
      final mvDests = mvMatches.map((m) => m.group(1)).toSet();
      expect(mvDests.length, equals(mvMatches.length),
          reason: 'Each android configure call must mv to a unique stable file');
      // iOS: cp destinations (stable paths) must all be distinct.
      final cpMatches = RegExp(r'cp ios/Runner/GoogleService-Info\.plist (\S+)').allMatches(content);
      final cpDests = cpMatches.map((m) => m.group(1)).toSet();
      expect(cpDests.length, equals(cpMatches.length),
          reason: 'Each iOS configure call must cp to a unique stable file');
    });
  });
}
