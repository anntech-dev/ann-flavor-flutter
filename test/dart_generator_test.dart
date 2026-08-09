import 'dart:io';
import 'package:test/test.dart';

// Package root is one level up from the test/ directory.
final _packageRoot = Directory.current.path.endsWith('/test')
    ? Directory.current.parent.path
    : Directory.current.path;

Future<ProcessResult> _runSync(Directory projectDir) {
  return Process.run(
    'dart',
    ['run', 'ann_flutter_flavor', 'sync', '--project', projectDir.path,
     '--firebase-mode', 'script'],
    workingDirectory: _packageRoot,
  );
}

String _readGenerated(Directory dir) =>
    File('${dir.path}/lib/generated/ann_flavor.g.dart').readAsStringSync();

// Spec with firebase project_id on android (release + debug) and auth on android + iOS.
void _writeFirebaseAndAuthSpec(Directory dir) {
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
      myapp:
        name: "My App"
        main_file: "lib/main.dart"
        version_name: "1.0.0"
        version_code: 100000
        id_suffix: .myapp
        build_types:
          release:
            firebase:
              project_id: "my-project-prod"
            auth:
              clientId: "release-android-client"
          debug:
            firebase:
              project_id: "my-project-dev"
            auth:
              clientId: "debug-android-client"
  ios:
    default:
      id: com.example.test
    flavor:
      myapp:
        name: "My App"
        main_file: "lib/main.dart"
        version_name: "1.0.0"
        version_code: 100000
        id_suffix: .myapp
        build_types:
          release:
            auth:
              clientId: "release-ios-client"
          debug:
            auth:
              clientId: "debug-ios-client"
''');
}

// Spec with no firebase integration — firebase helpers must not be generated.
void _writeNoFirebaseSpec(Directory dir) {
  File('${dir.path}/annspec.yaml').writeAsStringSync('''
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
      myapp:
        name: "My App"
        main_file: "lib/main.dart"
        version_name: "1.0.0"
        version_code: 100000
        id_suffix: .myapp
  ios:
    default:
      id: com.example.test
    flavor:
      myapp:
        name: "My App"
        main_file: "lib/main.dart"
        version_name: "1.0.0"
        version_code: 100000
        id_suffix: .myapp
''');
}

void main() {
  group('dart_generator — firebase three-function API', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('dartgen_firebase_test_');
      _writeFirebaseAndAuthSpec(tempDir);
    });
    tearDown(() => tempDir.deleteSync(recursive: true));

    test('flavorFirebaseOptions() auto-select function is generated', () async {
      final result = await _runSync(tempDir);
      expect(result.exitCode, 0,
          reason: 'stderr: ${result.stderr}\nstdout: ${result.stdout}');
      final content = _readGenerated(tempDir);
      expect(content, contains('FirebaseOptions? flavorFirebaseOptions()'));
    });

    test('flavorFirebaseOptionsRelease() explicit release function is generated', () async {
      final result = await _runSync(tempDir);
      expect(result.exitCode, 0,
          reason: 'stderr: ${result.stderr}\nstdout: ${result.stdout}');
      final content = _readGenerated(tempDir);
      expect(content, contains('FirebaseOptions? flavorFirebaseOptionsRelease()'));
    });

    test('flavorFirebaseOptionsDebug() explicit debug function is generated', () async {
      final result = await _runSync(tempDir);
      expect(result.exitCode, 0,
          reason: 'stderr: ${result.stderr}\nstdout: ${result.stdout}');
      final content = _readGenerated(tempDir);
      expect(content, contains('FirebaseOptions? flavorFirebaseOptionsDebug()'));
    });

    test('flavorFirebaseOptions() dispatches on AnnFlavor.buildType', () async {
      final result = await _runSync(tempDir);
      expect(result.exitCode, 0,
          reason: 'stderr: ${result.stderr}\nstdout: ${result.stdout}');
      final content = _readGenerated(tempDir);
      expect(content, contains("AnnFlavor.buildType == 'debug'"));
    });

    test('flavorFirebaseOptionsRelease() calls optionsRelease', () async {
      final result = await _runSync(tempDir);
      expect(result.exitCode, 0,
          reason: 'stderr: ${result.stderr}\nstdout: ${result.stdout}');
      final content = _readGenerated(tempDir);
      expect(content, contains('optionsRelease(AnnFlavor.platform)'));
    });

    test('old options(AnnFlavor.platform) call is not present', () async {
      final result = await _runSync(tempDir);
      expect(result.exitCode, 0,
          reason: 'stderr: ${result.stderr}\nstdout: ${result.stdout}');
      final content = _readGenerated(tempDir);
      expect(content, isNot(contains('.options(AnnFlavor.platform)')));
    });

    test('private Firebase class uses optionsRelease method name', () async {
      final result = await _runSync(tempDir);
      expect(result.exitCode, 0,
          reason: 'stderr: ${result.stderr}\nstdout: ${result.stdout}');
      final content = _readGenerated(tempDir);
      expect(content, contains('static FirebaseOptions? optionsRelease(AnnPlatform platform)'));
    });

    test('exhaustive AnnPlatform switch — all four arms generated, no default', () async {
      final result = await _runSync(tempDir);
      expect(result.exitCode, 0,
          reason: 'stderr: ${result.stderr}\nstdout: ${result.stdout}');
      final content = _readGenerated(tempDir);
      final classStart = content.indexOf('class _MyappFirebase');
      expect(classStart, greaterThan(-1), reason: '_MyappFirebase class not found');
      final classBody = content.substring(classStart);
      // All four AnnPlatform arms must be present
      expect(classBody, contains('case AnnPlatform.android:'));
      expect(classBody, contains('case AnnPlatform.ios:'));
      expect(classBody, contains('case AnnPlatform.web:'));
      expect(classBody, contains('case AnnPlatform.windows:'));
      // No default arm — exhaustive switch, no dead post-switch return
      expect(classBody, isNot(contains('default: return null;')));
    });
  });

  group('dart_generator — no firebase helpers when firebase not configured', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('dartgen_nofb_test_');
      _writeNoFirebaseSpec(tempDir);
    });
    tearDown(() => tempDir.deleteSync(recursive: true));

    test('flavorFirebaseOptions not generated when firebase disabled', () async {
      final result = await _runSync(tempDir);
      expect(result.exitCode, 0,
          reason: 'stderr: ${result.stderr}\nstdout: ${result.stdout}');
      final content = _readGenerated(tempDir);
      expect(content, isNot(contains('flavorFirebaseOptions')));
    });

    test('flavorFirebaseOptionsRelease not generated when firebase disabled', () async {
      final result = await _runSync(tempDir);
      expect(result.exitCode, 0,
          reason: 'stderr: ${result.stderr}\nstdout: ${result.stdout}');
      final content = _readGenerated(tempDir);
      expect(content, isNot(contains('flavorFirebaseOptionsRelease')));
    });

    test('flavorFirebaseOptionsDebug not generated when firebase disabled', () async {
      final result = await _runSync(tempDir);
      expect(result.exitCode, 0,
          reason: 'stderr: ${result.stderr}\nstdout: ${result.stdout}');
      final content = _readGenerated(tempDir);
      expect(content, isNot(contains('flavorFirebaseOptionsDebug')));
    });
  });

  group('dart_generator — auth three-method API', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('dartgen_auth_test_');
      _writeFirebaseAndAuthSpec(tempDir);
    });
    tearDown(() => tempDir.deleteSync(recursive: true));

    test('authRelease override is generated in flavor config class', () async {
      final result = await _runSync(tempDir);
      expect(result.exitCode, 0,
          reason: 'stderr: ${result.stderr}\nstdout: ${result.stdout}');
      final content = _readGenerated(tempDir);
      expect(content, contains('@override AnnAuthConfig? authRelease(AnnPlatform platform)'));
    });

    test('authDebug override is generated in flavor config class', () async {
      final result = await _runSync(tempDir);
      expect(result.exitCode, 0,
          reason: 'stderr: ${result.stderr}\nstdout: ${result.stdout}');
      final content = _readGenerated(tempDir);
      expect(content, contains('@override AnnAuthConfig? authDebug(AnnPlatform platform)'));
    });

    test('auth is NOT overridden in generated class — it comes from abstract class default', () async {
      final result = await _runSync(tempDir);
      expect(result.exitCode, 0,
          reason: 'stderr: ${result.stderr}\nstdout: ${result.stdout}');
      final content = _readGenerated(tempDir);
      expect(content, isNot(contains('@override AnnAuthConfig? auth(')));
    });

    test('exhaustive AnnPlatform switch in auth — all four arms generated, no default', () async {
      final result = await _runSync(tempDir);
      expect(result.exitCode, 0,
          reason: 'stderr: ${result.stderr}\nstdout: ${result.stdout}');
      final content = _readGenerated(tempDir);
      final classStart = content.indexOf('class _MyappConfig');
      expect(classStart, greaterThan(-1), reason: '_MyappConfig class not found');
      final classEnd = content.indexOf('\n}\n\n', classStart + 1);
      final classBody = classEnd > classStart
          ? content.substring(classStart, classEnd + 2)
          : content.substring(classStart);
      // All four AnnPlatform arms must be present in each auth method
      expect(classBody, contains('case AnnPlatform.android:'));
      expect(classBody, contains('case AnnPlatform.ios:'));
      expect(classBody, contains('case AnnPlatform.web:'));
      expect(classBody, contains('case AnnPlatform.windows:'));
      expect(classBody, isNot(contains('default: return null;')));
    });
  });

  group('dart_generator — web/windows default auth from platform default', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('dartgen_webauth_test_');
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
      myapp:
        name: "My App"
        main_file: "lib/main.dart"
        version_name: "1.0.0"
        version_code: 100000
        id_suffix: .myapp
  ios:
    default:
      id: com.example.test
    flavor:
      myapp:
        name: "My App"
        main_file: "lib/main.dart"
        version_name: "1.0.0"
        version_code: 100000
        id_suffix: .myapp
  web:
    default:
      id: com.example.test
      build_types:
        release:
          auth:
            clientId: "web-release-client-id"
        debug:
          auth:
            clientId: "web-debug-client-id"
    flavor:
      myapp:
        name: "My App"
        main_file: "lib/main.dart"
        version_name: "1.0.0"
        version_code: 100000
''');
    });
    tearDown(() => tempDir.deleteSync(recursive: true));

    test('authRelease emits web clientId from web.default.build_types', () async {
      final result = await _runSync(tempDir);
      expect(result.exitCode, 0,
          reason: 'stderr: ${result.stderr}\nstdout: ${result.stdout}');
      final content = _readGenerated(tempDir);
      expect(content, contains("case AnnPlatform.web: return AnnAuthConfig("));
      expect(content, contains("clientId: 'web-release-client-id'"));
    });

    test('authDebug emits web clientId from web.default.build_types', () async {
      final result = await _runSync(tempDir);
      expect(result.exitCode, 0,
          reason: 'stderr: ${result.stderr}\nstdout: ${result.stdout}');
      final content = _readGenerated(tempDir);
      expect(content, contains("clientId: 'web-debug-client-id'"));
    });

    test('web default does not bleed into authRelease when not configured', () async {
      // android and ios have no auth — web has it — windows should still be null
      final result = await _runSync(tempDir);
      expect(result.exitCode, 0,
          reason: 'stderr: ${result.stderr}\nstdout: ${result.stdout}');
      final content = _readGenerated(tempDir);
      expect(content, contains('case AnnPlatform.windows: return null;'));
    });
  });
}
