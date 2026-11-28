import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import '../lib_cli/validators/testspec_validator.dart';

/// Test spec version 2: REQ-FCLI-00080, REQ-TEST-00010 to 00050, on the shared fixtures.
void main() {
  final fixtures = p.normalize(p.join(Directory.current.path, '..', '..', 'test-fixtures', 'testspec'));

  dynamic plain(dynamic node) {
    if (node is YamlMap) {
      return {for (final e in node.entries) '${e.key}': plain(e.value)};
    }
    if (node is YamlList) return node.map(plain).toList();
    return node;
  }

  dynamic load(String name) => plain(loadYaml(File(p.join(fixtures, name)).readAsStringSync()));

  List<String> sorted(Iterable<dynamic> values) => values.map((v) => '$v').toList()..sort();

  late Directory project;

  setUp(() => project = Directory.systemTemp.createTempSync('testspec_v2_'));
  tearDown(() => project.deleteSync(recursive: true));

  TestspecResult validate(String content, List<String> files, [Map<String, Set<String>> annspec = const {}]) {
    for (final file in files) {
      File(p.join(project.path, file)).createSync(recursive: true);
    }
    final spec = File(p.join(project.path, 'anntestspec.yaml'))..writeAsStringSync(content);
    return validateTestspec(spec, project.path, annspecFlavorKeys: annspec);
  }

  void expectIssues(TestspecResult result, Map<dynamic, dynamic> expected) {
    expect(sorted(result.errors.map((i) => i.path)), sorted(expected['errors'] as List), reason: 'errors');
    expect(sorted(result.warnings.map((i) => i.path)), sorted(expected['warnings'] as List), reason: 'warnings');
    expect(sorted(result.infos.map((i) => i.path)), sorted(expected['infos'] as List), reason: 'infos');
  }

  group('version 2 rules', () {
    for (final c in load('cases.yaml')['cases'] as List) {
      test(c['name'], () {
        final annspec = {
          for (final e in ((c['annspec'] ?? {}) as Map).entries) '${e.key}': {for (final f in e.value as List) '$f'},
        };
        final result = validate(jsonEncode(c['spec']),
            ['test_driver/driver.dart', 'integration_test/app_test.dart'], annspec);

        expectIssues(result, c as Map);
      });
    }
  });

  test('the full version 2 fixture', () {
    final expected = load('v2_full.expected.yaml') as Map;
    final result = validate(File(p.join(fixtures, 'v2_full.yaml')).readAsStringSync(),
        [for (final f in expected['files'] as List) '$f']);

    expectIssues(result, expected['validator'] as Map);
  });

  // The Fastlane plugin reads these words as true and false, Dart reads them as text.
  for (final word in ['yes', 'no', 'on', 'off']) {
    test('screenshots.enabled: $word is an error', () {
      final result = validate(
          File(p.join(fixtures, 'v2_full.yaml'))
              .readAsStringSync()
              .replaceFirst('  version: 2\n', '  version: 2\n  screenshots:\n    enabled: $word\n'),
          const []);

      expect(result.errors.map((i) => i.path), ['annai_app_tests.screenshots.enabled']);
    });
  }

  test('a version 1 file keeps its rules and knows IOS_IPHONE_6_3_INCH', () {
    final result = validate(File(p.join(fixtures, 'v1.yaml')).readAsStringSync(),
        ['test_driver/driver.dart', 'integration_test/app_test.dart']);

    expectIssues(result, {'errors': [], 'warnings': [], 'infos': []});
  });

  test('validate-testspec checks the flavors against annspec.yaml', () async {
    File(p.join(project.path, 'annspec.yaml')).writeAsStringSync('''
app:
  android:
    default:
      id: com.example.app
    flavor:
      other:
        name: Other
''');
    File(p.join(project.path, 'anntestspec.yaml'))
        .writeAsStringSync(jsonEncode((load('cases.yaml')['cases'] as List).first['spec']));

    final run = await Process.run('dart',
        ['run', 'ann_flutter_flavor', 'validate-testspec', '--project', project.path, '--format', 'json']);

    final output = jsonDecode(run.stdout as String) as Map;
    expect([for (final w in output['warnings'] as List) w['path']], contains('annai_app_tests.flavor.free'));
    expect(run.exitCode, 0);
  });
}
