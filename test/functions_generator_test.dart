import 'dart:io';
import 'package:test/test.dart';
import '../lib_cli/generators/functions_generator.dart';
import '../lib_cli/spec/annspec_reader.dart';

const _baseSpec = '''
functions:
  projects:
    prod:
      project_id: my-app-prod
    demo:
      project_id: my-app-demo
  codebases:
    purchases:
      source: functions
      params:
        RC_ENTITLEMENT_IDS: "pro,premium"
      project_params:
        prod: { RC_PROJECT_ID: proj1234 }
        demo: { RC_PROJECT_ID: proj_demo }
''';

void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('fn_gen_'));
  tearDown(() => root.deleteSync(recursive: true));

  void write(String rel, String content) {
    final f = File('${root.path}/$rel')..createSync(recursive: true);
    f.writeAsStringSync(content);
  }

  String read(String rel) => File('${root.path}/$rel').readAsStringSync();
  bool exists(String rel) => File('${root.path}/$rel').existsSync();

  spec(String yaml) {
    write('annspec.yaml', yaml);
    return AnnspecReader.read(root.path);
  }

  void writeSource({String index = ''}) {
    write('functions/package.json', '{"name":"fn"}');
    write('functions/package-lock.json', '{}');
    write('functions/index.js', index);
  }

  Map<String, String> snapshot(String dir) {
    final out = <String, String>{};
    for (final e in Directory('${root.path}/$dir').listSync(recursive: true)) {
      if (e is File) out[e.path] = e.readAsStringSync();
    }
    return out;
  }

  test(
      'copies the package and writes one .env per project, named by project_id',
      () {
    writeSource();
    write('functions/node_modules/dep/index.js', 'x');
    write('functions/.git/HEAD', 'x');
    write('functions/.env.stale-project', 'OLD=1');
    write('functions/firebase-debug.log', 'log');

    final result = FunctionsGenerator.prepare(spec(_baseSpec), root.path);

    expect(result.written['purchases'],
        unorderedEquals(['.env.my-app-prod', '.env.my-app-demo']));
    expect(read('build/functions/purchases/.env.my-app-prod'),
        'RC_ENTITLEMENT_IDS=pro,premium\nRC_PROJECT_ID=proj1234\n');
    expect(read('build/functions/purchases/.env.my-app-demo'),
        'RC_ENTITLEMENT_IDS=pro,premium\nRC_PROJECT_ID=proj_demo\n');
    expect(exists('build/functions/purchases/package.json'), isTrue);
    expect(exists('build/functions/purchases/package-lock.json'), isTrue);
    expect(exists('build/functions/purchases/index.js'), isTrue);
    expect(exists('build/functions/purchases/.env.prod'), isFalse,
        reason: 'named by project_id, never alias');
    expect(exists('build/functions/purchases/.env.stale-project'), isFalse);
    expect(exists('build/functions/purchases/node_modules'), isFalse);
    expect(exists('build/functions/purchases/.git'), isFalse);
    expect(exists('build/functions/purchases/firebase-debug.log'), isFalse);
  });

  test('never writes into the source folder', () {
    writeSource();
    final before = snapshot('functions');
    FunctionsGenerator.prepare(spec(_baseSpec), root.path);
    expect(snapshot('functions'), before);
  });

  test('--firebase-project limits output to that one project', () {
    writeSource();
    final result = FunctionsGenerator.prepare(spec(_baseSpec), root.path,
        firebaseProject: 'demo');
    expect(result.written['purchases'], ['.env.my-app-demo']);
    expect(exists('build/functions/purchases/.env.my-app-prod'), isFalse);
  });

  test(
      'onlyCodebases prepares just those codebases and ignores problems in the others',
      () {
    writeSource();
    final yaml = '''
functions:
  projects:
    prod: { project_id: my-app-prod }
  codebases:
    purchases:
      params: { A: "1" }
    broken:
      source: does-not-exist
''';
    final result = FunctionsGenerator.prepare(spec(yaml), root.path,
        onlyCodebases: {'purchases'}, skipSourceCheck: true);
    expect(result.written.keys, ['purchases']);
    expect(
        Directory('${root.path}/build/functions/broken').existsSync(), isFalse);
  });

  test('onlyCodebases with an unknown name fails, listing the declared ones',
      () {
    writeSource();
    expect(
      () => FunctionsGenerator.prepare(spec(_baseSpec), root.path,
          onlyCodebases: {'nope'}),
      throwsA(isA<FunctionsPrepareException>().having((e) => e.message,
          'message', allOf(contains("'nope'"), contains('purchases')))),
    );
  });

  test('a re-run replaces the previous build folder', () {
    writeSource();
    write('build/functions/purchases/leftover.txt', 'old');
    FunctionsGenerator.prepare(spec(_baseSpec), root.path);
    expect(exists('build/functions/purchases/leftover.txt'), isFalse);
  });

  test('reads a source outside the project, relative to annspec.yaml', () {
    final outside = Directory.systemTemp.createTempSync('fn_outside_');
    addTearDown(() => outside.deleteSync(recursive: true));
    File('${outside.path}/index.js').writeAsStringSync('');
    final rel = '../${outside.path.split(Platform.pathSeparator).last}';
    final yaml = _baseSpec.replaceFirst('source: functions', 'source: $rel');
    // outside lives in the system temp dir, a sibling of root's own parent segment
    final result = FunctionsGenerator.prepare(spec(yaml), root.path);
    expect(result.written.keys, ['purchases']);
    expect(exists('build/functions/purchases/index.js'), isTrue);
  });

  test(
      'quotes values with spaces, # and quotes, escapes newlines, and writes LF only',
      () {
    writeSource();
    final yaml = '''
functions:
  projects:
    prod: { project_id: my-app-prod }
  codebases:
    purchases:
      params:
        PLAIN: simple
        SPACED: "a b"
        HASH: "a#b"
        QUOTED: 'say "hi"'
        MULTI: "l1\\nl2"
        UNICODE: "héllo"
''';
    FunctionsGenerator.prepare(spec(yaml), root.path, skipSourceCheck: true);
    final content = read('build/functions/purchases/.env.my-app-prod');
    expect(content, contains('PLAIN=simple\n'));
    expect(content, contains('SPACED="a b"\n'));
    expect(content, contains('HASH="a#b"\n'));
    expect(content, contains(r'QUOTED="say \"hi\""'));
    expect(content, contains(r'MULTI="l1\nl2"'));
    expect(content, contains('UNICODE=héllo\n'));
    expect(content.contains('\r'), isFalse);
  });

  test('fails when the source folder is missing, naming codebase and path', () {
    expect(
      () => FunctionsGenerator.prepare(spec(_baseSpec), root.path),
      throwsA(isA<FunctionsPrepareException>().having(
          (e) => e.message,
          'message',
          allOf(contains('purchases'), contains('not found'),
              contains('submodule')))),
    );
    expect(Directory('${root.path}/build').existsSync(), isFalse);
  });

  test('fails for a project with no values', () {
    writeSource();
    final yaml = '''
functions:
  projects:
    prod: { project_id: my-app-prod }
    demo: { project_id: my-app-demo }
  codebases:
    purchases:
      project_params:
        prod: { A: "1" }
''';
    expect(
      () => FunctionsGenerator.prepare(spec(yaml), root.path,
          skipSourceCheck: true),
      throwsA(isA<FunctionsPrepareException>().having((e) => e.message,
          'message', allOf(contains("project 'demo'"), contains('no values')))),
    );
  });

  test('fails for a blank value and for an invalid param name', () {
    writeSource();
    final yaml = '''
functions:
  projects:
    prod: { project_id: my-app-prod }
  codebases:
    purchases:
      params:
        EMPTY: ""
        "BAD-NAME": x
''';
    expect(
      () => FunctionsGenerator.prepare(spec(yaml), root.path,
          skipSourceCheck: true),
      throwsA(isA<FunctionsPrepareException>().having(
          (e) => e.message,
          'message',
          allOf(contains("'EMPTY' is blank"),
              contains("'BAD-NAME' is not a valid param name")))),
    );
  });

  test(
      'fails for an unknown --firebase-project alias, listing the declared ones',
      () {
    writeSource();
    expect(
      () => FunctionsGenerator.prepare(spec(_baseSpec), root.path,
          firebaseProject: 'stage'),
      throwsA(isA<FunctionsPrepareException>().having(
          (e) => e.message,
          'message',
          allOf(contains("'stage'"), contains('prod'), contains('demo')))),
    );
  });

  test(
      'fails when two aliases share a project_id, or a project_params key is not an alias',
      () {
    writeSource();
    final yaml = '''
functions:
  projects:
    prod: { project_id: same }
    demo: { project_id: same }
  codebases:
    purchases:
      params: { A: "1" }
      project_params:
        stage: { A: "2" }
''';
    expect(
      () => FunctionsGenerator.prepare(spec(yaml), root.path,
          skipSourceCheck: true),
      throwsA(isA<FunctionsPrepareException>().having(
          (e) => e.message,
          'message',
          allOf(contains("already used by 'prod'"),
              contains("'stage' is not declared")))),
    );
  });

  test('fails when there is no functions block', () {
    expect(
      () => FunctionsGenerator.prepare(spec('app: {}'), root.path),
      throwsA(isA<FunctionsPrepareException>()
          .having((e) => e.message, 'message', contains('nothing to prepare'))),
    );
  });

  group('source check (REQ-FUNC-00080)', () {
    test('a required param with no value for one project fails and names it',
        () {
      writeSource(
          index:
              'defineString("RC_PROJECT_ID"); defineString("MAIL_ENDPOINT");');
      expect(
        () => FunctionsGenerator.prepare(spec(_baseSpec), root.path),
        throwsA(isA<FunctionsPrepareException>().having(
            (e) => e.message,
            'message',
            allOf(contains('purchases'), contains('MAIL_ENDPOINT'),
                contains("'prod'"), contains("'demo'")))),
      );
      expect(Directory('${root.path}/build').existsSync(), isFalse);
    });

    test('an optional param (with a default) may have no value', () {
      writeSource(
          index:
              'defineString("RC_PROJECT_ID"); defineString("OPT", {default: "x"});');
      final result = FunctionsGenerator.prepare(spec(_baseSpec), root.path);
      expect(result.written['purchases'], hasLength(2));
    });

    test('a value for a defineSecret name fails', () {
      writeSource(
          index:
              'defineString("RC_PROJECT_ID"); defineSecret("RC_ENTITLEMENT_IDS");');
      expect(
        () => FunctionsGenerator.prepare(spec(_baseSpec), root.path),
        throwsA(isA<FunctionsPrepareException>().having(
            (e) => e.message,
            'message',
            allOf(contains('RC_ENTITLEMENT_IDS'), contains('Secret Manager')))),
      );
    });

    test('a spec value not declared in the source only warns', () {
      writeSource(index: 'defineString("RC_PROJECT_ID");');
      final result = FunctionsGenerator.prepare(spec(_baseSpec), root.path);
      expect(result.warnings,
          contains(contains('RC_ENTITLEMENT_IDS is not declared')));
      expect(result.written['purchases'], hasLength(2));
    });

    test('a non-literal declaration warns that the check is incomplete', () {
      writeSource(
          index: 'defineString("RC_PROJECT_ID"); defineString(dynamicName);');
      final result = FunctionsGenerator.prepare(spec(_baseSpec), root.path);
      expect(result.warnings, contains(contains('non-literal')));
    });

    test('a source with no declarations warns once instead of failing', () {
      writeSource(index: 'const x = process.env.FOO;');
      final result = FunctionsGenerator.prepare(spec(_baseSpec), root.path);
      expect(result.warnings.where((w) => w.contains('no defineString-style')),
          hasLength(1));
    });

    test('skipSourceCheck bypasses the scan', () {
      writeSource(index: 'defineString("NOT_IN_SPEC");');
      final result = FunctionsGenerator.prepare(spec(_baseSpec), root.path,
          skipSourceCheck: true);
      expect(result.warnings, isEmpty);
      expect(result.written['purchases'], hasLength(2));
    });
  });
}
