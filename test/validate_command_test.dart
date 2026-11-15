import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';

final _packageRoot = Directory.current.path.endsWith('/test')
    ? Directory.current.parent.path
    : Directory.current.path;

void _writeValidAnnspec(Directory dir) {
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
''');
}

void _writeValidTestspec(Directory dir) {
  File('${dir.path}/anntestspec.yaml').writeAsStringSync('''
annai_app_tests:
  version: "1"
  default:
    phone_type: pixel_7
    driver_file: test_driver/integration_test.dart
    test_file: integration_test/app_test.dart
''');
}

void _writeInvalidTestspec(Directory dir) {
  // Missing the required 'annai_app_tests' root key → validator produces an error.
  File('${dir.path}/anntestspec.yaml').writeAsStringSync('''
wrong_root_key:
  version: "1"
''');
}

Future<ProcessResult> _runValidate(Directory projectDir, List<String> extraArgs) {
  return Process.run(
    'dart',
    ['run', 'ann_flutter_flavor', 'validate', '--project', projectDir.path, ...extraArgs],
    workingDirectory: _packageRoot,
  );
}

void main() {
  group('validate command — testspec handling', () {
    late Directory tempDir;

    setUp(() => tempDir = Directory.systemTemp.createTempSync('validate_ts_test_'));
    tearDown(() => tempDir.deleteSync(recursive: true));

    test('exits 0 with info when anntestspec is absent', () async {
      _writeValidAnnspec(tempDir);
      final result = await _runValidate(tempDir, []);
      expect(result.exitCode, 0,
          reason: 'Missing testspec is non-fatal for validate\n'
              'stderr: ${result.stderr}\nstdout: ${result.stdout}');
      final output = result.stdout.toString();
      expect(output.toLowerCase(),
          anyOf(contains('skipped'), contains('not found'), contains('anntestspec')));
    });

    test('exits 1 when anntestspec has errors', () async {
      _writeValidAnnspec(tempDir);
      _writeInvalidTestspec(tempDir);
      final result = await _runValidate(tempDir, []);
      expect(result.exitCode, 1,
          reason: 'Invalid testspec should cause exit 1\n'
              'stderr: ${result.stderr}\nstdout: ${result.stdout}');
    });

    test('exits 0 when both annspec and anntestspec are valid', () async {
      _writeValidAnnspec(tempDir);
      _writeValidTestspec(tempDir);
      final result = await _runValidate(tempDir, []);
      expect(result.exitCode, 0,
          reason: 'Both specs valid should exit 0\n'
              'stderr: ${result.stderr}\nstdout: ${result.stdout}');
    });

    test('JSON output has testspec.present: false when anntestspec absent', () async {
      _writeValidAnnspec(tempDir);
      final result = await _runValidate(tempDir, ['--format', 'json']);
      expect(result.exitCode, 0);
      final Map<String, dynamic> json;
      try {
        json = jsonDecode(result.stdout.toString().trim()) as Map<String, dynamic>;
      } catch (e) {
        fail('stdout was not valid JSON: ${result.stdout}');
      }
      final testspec = json['testspec'] as Map<String, dynamic>?;
      expect(testspec, isNotNull, reason: 'testspec key must be present in JSON output');
      expect(testspec!['present'], isFalse,
          reason: 'testspec.present must be false when anntestspec.yaml is absent');
    });

    test('JSON output has non-empty testspec.errors when anntestspec is invalid', () async {
      _writeValidAnnspec(tempDir);
      _writeInvalidTestspec(tempDir);
      final result = await _runValidate(tempDir, ['--format', 'json']);
      expect(result.exitCode, 1);
      final Map<String, dynamic> json;
      try {
        json = jsonDecode(result.stdout.toString().trim()) as Map<String, dynamic>;
      } catch (e) {
        fail('stdout was not valid JSON: ${result.stdout}');
      }
      final testspec = json['testspec'] as Map<String, dynamic>?;
      expect(testspec, isNotNull);
      expect(testspec!['present'], isTrue);
      expect(testspec['valid'], isFalse);
      final errors = testspec['errors'] as List?;
      expect(errors, isNotNull);
      expect(errors!.isNotEmpty, isTrue,
          reason: 'testspec.errors must be non-empty for an invalid testspec');
    });
  });

  group('validate command — functions block (REQ-FUNC-00020/00070)', () {
    late Directory tempDir;
    setUp(() => tempDir = Directory.systemTemp.createTempSync('validate_fn_test_'));
    tearDown(() => tempDir.deleteSync(recursive: true));

    Future<List<Map<String, dynamic>>> errorsFor(String functionsYaml) async {
      _writeValidAnnspec(tempDir);
      final f = File('${tempDir.path}/annspec.yaml');
      f.writeAsStringSync(f.readAsStringSync() + functionsYaml);
      final result = await _runValidate(tempDir, ['--format', 'json']);
      final json = jsonDecode(result.stdout.toString().trim()) as Map<String, dynamic>;
      return (json['errors'] as List).cast<Map<String, dynamic>>();
    }

    test('a valid functions block adds no errors', () async {
      final errors = await errorsFor('''
functions:
  projects:
    prod: { project_id: my-app-prod }
    demo: { project_id: my-app-demo }
  codebases:
    purchases:
      source: ../shared/fn
      project_params:
        prod: { A: "1" }
''');
      expect(errors, isEmpty);
    });

    test('rejects absolute, drive-letter and backslash sources', () async {
      for (final bad in ['/abs/path', r'C:/x', r'C:\x', r'sub\dir']) {
        final errors = await errorsFor('''
functions:
  projects:
    prod: { project_id: p }
  codebases:
    purchases:
      source: "${bad.replaceAll(r'\', r'\\')}"
''');
        expect(errors.map((e) => e['path']), contains('functions.codebases.purchases'),
            reason: 'source "$bad" should be rejected');
      }
    });

    test('reports a blank project_id, a duplicate project_id and an unknown alias', () async {
      final errors = await errorsFor('''
functions:
  projects:
    a: {}
    b: { project_id: same }
    c: { project_id: same }
  codebases:
    purchases:
      project_params:
        stage: { A: "1" }
''');
      final messages = errors.map((e) => '${e['path']} ${e['message']}').join('\n');
      expect(messages, contains('functions.projects.a'));
      expect(messages, contains('blank'));
      expect(messages, contains("already used by 'b'"));
      expect(messages, contains("'stage' is not declared"));
    });
  });
}
