import 'dart:io';
import 'package:test/test.dart';

final _packageRoot = Directory.current.path.endsWith('/test')
    ? Directory.current.parent.path
    : Directory.current.path;

Future<ProcessResult> _runValidate(Directory dir) => Process.run(
      'dart',
      ['run', 'ann_flutter_flavor', 'validate', '--project', dir.path],
      workingDirectory: _packageRoot,
    );

Future<ProcessResult> _runSync(Directory dir) => Process.run(
      'dart',
      ['run', 'ann_flutter_flavor', 'sync', '--project', dir.path],
      workingDirectory: _packageRoot,
    );

void _writeSpec(Directory dir, String iosFirebase) =>
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
      $iosFirebase
    flavor:
      app:
        name: "Test App"
        main_file: "lib/main.dart"
        version_name: "1.0.0"
        version_code: 100000
        id_suffix: .app
''');

void main() {
  late Directory tempDir;
  setUp(() => tempDir = Directory.systemTemp.createTempSync('target_cascade_'));
  tearDown(() => tempDir.deleteSync(recursive: true));

  group('firebase target — valid field accepted by validate', () {
    test('target in ios default build_type firebase block is accepted', () async {
      _writeSpec(tempDir, '''
firebase:
        service_account: "keys/sa.json"
      build_types:
        release:
          firebase:
            project_id: "proj-prod"
            target: "RunnerPro"''');
      final result = await _runValidate(tempDir);
      expect(result.exitCode, 0,
          reason: 'target is a valid firebase field\nstdout: ${result.stdout}\nstderr: ${result.stderr}');
    });
  });

  group('firebase target — valid field accepted by sync', () {
    test('target in ios default build_type firebase block does not abort sync', () async {
      _writeSpec(tempDir, '''
firebase:
        service_account: "keys/sa.json"
      build_types:
        release:
          firebase:
            project_id: "proj-prod"
            target: "RunnerPro"''');
      final result = await _runSync(tempDir);
      expect(result.exitCode, 0,
          reason: 'target is a valid firebase field; sync must not abort\n'
              'stdout: ${result.stdout}\nstderr: ${result.stderr}');
    });
  });

  group('firebase target — ios_build_config rejected as unknown field', () {
    test('ios_build_config in firebase block causes validate to exit 1', () async {
      _writeSpec(tempDir, '''
build_types:
        release:
          firebase:
            project_id: "proj-prod"
            ios_build_config: "Release-RunnerPro"''');
      final result = await _runValidate(tempDir);
      expect(result.exitCode, 1,
          reason: 'ios_build_config is no longer a valid firebase field\n'
              'stdout: ${result.stdout}\nstderr: ${result.stderr}');
      expect('${result.stdout}${result.stderr}', contains('ios_build_config'));
    });
  });
}
