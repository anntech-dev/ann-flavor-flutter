import 'dart:io';
import 'package:test/test.dart';

final _packageRoot = Directory.current.path.endsWith('/test')
    ? Directory.current.parent.path
    : Directory.current.path;

Future<ProcessResult> _run(Directory project, [List<String> extra = const []]) =>
    Process.run('dart', ['run', 'ann_flutter_flavor', 'functions-prepare', '--project', project.path, ...extra],
        workingDirectory: _packageRoot);

const _spec = '''
functions:
  projects:
    prod: { project_id: my-app-prod }
    demo: { project_id: my-app-demo }
  codebases:
    purchases:
      params: { A: "1" }
''';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('fn_cmd_'));
  tearDown(() => dir.deleteSync(recursive: true));

  void write(String rel, String content) {
    final f = File('${dir.path}/$rel')..createSync(recursive: true);
    f.writeAsStringSync(content);
  }

  test('prepares every project, prints a summary and exits 0', () async {
    write('annspec.yaml', _spec);
    write('functions/index.js', 'defineString("A");');
    final r = await _run(dir);
    expect(r.exitCode, 0, reason: '${r.stderr}');
    expect(r.stdout, contains('purchases'));
    expect(r.stdout, contains('.env.my-app-prod'));
    expect(r.stdout, contains('.env.my-app-demo'));
    expect(File('${dir.path}/build/functions/purchases/.env.my-app-prod').readAsStringSync(), 'A=1\n');
  });

  test('--firebase-project writes only that project', () async {
    write('annspec.yaml', _spec);
    write('functions/index.js', 'defineString("A");');
    final r = await _run(dir, ['--firebase-project', 'demo']);
    expect(r.exitCode, 0, reason: '${r.stderr}');
    expect(File('${dir.path}/build/functions/purchases/.env.my-app-demo').existsSync(), isTrue);
    expect(File('${dir.path}/build/functions/purchases/.env.my-app-prod').existsSync(), isFalse);
  });

  test('exits 1 with the problem on stderr for a missing required param', () async {
    write('annspec.yaml', _spec);
    write('functions/index.js', 'defineString("A"); defineString("MISSING");');
    final r = await _run(dir);
    expect(r.exitCode, 1);
    expect(r.stderr, contains('MISSING'));
    expect(Directory('${dir.path}/build').existsSync(), isFalse);
  });

  test('--skip-source-check lets the same project through', () async {
    write('annspec.yaml', _spec);
    write('functions/index.js', 'defineString("A"); defineString("MISSING");');
    final r = await _run(dir, ['--skip-source-check']);
    expect(r.exitCode, 0, reason: '${r.stderr}');
  });

  test('exits 1 when annspec.yaml has no functions block', () async {
    write('annspec.yaml', 'app: {}\n');
    final r = await _run(dir);
    expect(r.exitCode, 1);
    expect(r.stderr, contains('nothing to prepare'));
  });

  test('exits 1 when annspec.yaml is missing', () async {
    final r = await _run(dir);
    expect(r.exitCode, 1);
    expect(r.stderr, contains('annspec.yaml not found'));
  });

  test('--codebase prepares only the named codebase', () async {
    write('annspec.yaml', '''
functions:
  projects:
    prod: { project_id: my-app-prod }
  codebases:
    purchases:
      params: { A: "1" }
    other:
      source: other-fn
      params: { B: "2" }
''');
    write('functions/index.js', 'defineString("A");');
    final r = await _run(dir, ['--codebase', 'purchases']);
    expect(r.exitCode, 0, reason: '${r.stderr}');
    expect(Directory('${dir.path}/build/functions/purchases').existsSync(), isTrue);
    expect(Directory('${dir.path}/build/functions/other').existsSync(), isFalse);
  });
}
