import 'dart:io';
import 'package:test/test.dart';
import '../lib_cli/generators/web_build_options_checker.dart';
import '../lib_cli/spec/annspec_reader.dart';

// Tests do not import ann_flavor_core (not published; scripts/vendor-flutter-core.sh rejects it).

final _packageRoot = Directory.current.path.endsWith('/test')
    ? Directory.current.parent.path
    : Directory.current.path;

String _spec(
        {String defaultBuild = '',
        String bankingBuild = '',
        String plainBuild = ''}) =>
    '''
enabled: true
app:
  web:
    default:
      id: com.example.app
$defaultBuild    flavor:
      banking:
        name: "Banking"
        main_file: "lib/main_banking.dart"
        version_name: "1.0.0"
        version_code: 100
$bankingBuild      plain:
        name: "Plain"
        main_file: "lib/main_plain.dart"
        version_name: "1.0.0"
        version_code: 100
$plainBuild''';

String _block(String indent, {String? pwa, String? url}) => '$indent'
    'build:\n'
    '${pwa == null ? '' : '$indent  pwa_strategy: $pwa\n'}'
    '${url == null ? '' : '$indent  canvaskit_base_url: $url\n'}';

const _bootstrapTmpl =
    '{{flutter_js}}\n{{flutter_build_config}}\n_flutter.loader.load({config: {canvasKitBaseUrl: "{{canvaskit_base_url}}"}});\n';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('web_build_options_'));
  tearDown(() => dir.deleteSync(recursive: true));

  void write(String relative, String content) {
    final f = File('${dir.path}/$relative');
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(content);
  }

  List<WebBuildOptionsFinding> check(String flavor) {
    final web = AnnspecReader.read(dir.path).app.web!;
    return WebBuildOptionsChecker.check(dir.path, flavor, web);
  }

  group('WebBuildOptionsChecker (REQ-WEB-00130)', () {
    test('no findings without a build block (REQ-WEB-00140)', () {
      write('annspec.yaml', _spec());
      expect(check('banking'), isEmpty);
      expect(check('plain'), isEmpty);
    });

    test('no findings for a missing flavor', () {
      write('annspec.yaml', _spec());
      expect(check('nope'), isEmpty);
    });

    test('pwa_strategy alone needs no template and is clean', () {
      write(
          'annspec.yaml', _spec(bankingBuild: _block('        ', pwa: 'none')));
      expect(check('banking'), isEmpty);
    });

    test(
        'a bad value is an error with the flavor path and the core message, and nothing else is checked',
        () {
      write('annspec.yaml',
          _spec(bankingBuild: _block('        ', pwa: 'always', url: '/ck')));
      final f = check('banking');
      expect(f.map((x) => x.isError), everyElement(isTrue));
      expect(
          f.map((x) => '${x.path}: ${x.message}'),
          unorderedEquals([
            'app.web.flavor.banking.build.pwa_strategy: must be "none" or "offline-first"',
            'app.web.flavor.banking.build.canvaskit_base_url: must end with "/"',
          ]));
    });

    test(
        'a bad value in the web default is reported under the default path for a flavor that inherits it',
        () {
      write(
          'annspec.yaml', _spec(defaultBuild: _block('      ', pwa: 'always')));
      final f = check('plain');
      expect(f.single.isError, isTrue);
      expect(f.single.path, 'app.web.default.build.pwa_strategy');
    });

    test('a flavor that overrides a bad default value is not blamed for it',
        () {
      write(
          'annspec.yaml',
          _spec(
              defaultBuild: _block('      ', pwa: 'always'),
              bankingBuild: _block('        ', pwa: 'none')));
      expect(check('banking'), isEmpty);
      expect(check('plain'), hasLength(1));
    });

    test(
        'warns when canvaskit_base_url is set and no template uses the variable',
        () {
      write('annspec.yaml',
          _spec(bankingBuild: _block('        ', url: '/canvaskit/')));
      final f = check('banking');
      expect(f.single.isError, isFalse);
      expect(f.single.path, 'app.web.flavor.banking.build.canvaskit_base_url');
      expect(f.single.fix, contains('--scaffold-bootstrap'));
    });

    test('warns for a flavor that inherits canvaskit_base_url from the default',
        () {
      write('annspec.yaml',
          _spec(defaultBuild: _block('      ', url: '/canvaskit/')));
      expect(check('plain').single.isError, isFalse);
    });

    test('no warning when a template of the flavor uses {{canvaskit_base_url}}',
        () {
      write('annspec.yaml',
          _spec(bankingBuild: _block('        ', url: '/canvaskit/')));
      write('web_flavors/banking/flutter_bootstrap.tmpl.js', _bootstrapTmpl);
      expect(check('banking'), isEmpty);
    });

    test('a template of another flavor does not count', () {
      write('annspec.yaml',
          _spec(defaultBuild: _block('      ', url: '/canvaskit/')));
      write('web_flavors/banking/flutter_bootstrap.tmpl.js', _bootstrapTmpl);
      expect(check('banking'), isEmpty);
      expect(check('plain'), hasLength(1));
    });

    test('a file that is not a template does not count', () {
      write('annspec.yaml',
          _spec(bankingBuild: _block('        ', url: '/canvaskit/')));
      write('web_flavors/banking/flutter_bootstrap.js', _bootstrapTmpl);
      expect(check('banking'), hasLength(1));
    });
  });

  Future<ProcessResult> run(List<String> args) =>
      Process.run('dart', ['run', 'ann_flutter_flavor', ...args],
          workingDirectory: _packageRoot);

  group('validate', () {
    test('reports a bad value as an error', () async {
      write('annspec.yaml',
          _spec(bankingBuild: _block('        ', pwa: 'always')));
      final r = await run(['validate', '--project', dir.path]);
      final out = '${r.stdout}${r.stderr}';
      expect(out, contains('app.web.flavor.banking.build.pwa_strategy'));
      expect(out, contains('must be "none" or "offline-first"'));
      expect(r.exitCode, isNot(0));
    });

    test('a bad web default value is reported once, not once per flavor',
        () async {
      write(
          'annspec.yaml', _spec(defaultBuild: _block('      ', pwa: 'always')));
      final r =
          await run(['validate', '--project', dir.path, '--format', 'json']);
      final out = '${r.stdout}';
      expect('app.web.default.build.pwa_strategy'.allMatches(out).length, 1,
          reason: out);
      expect(r.exitCode, isNot(0));
    });

    test(
        'warns, without failing, when canvaskit_base_url has no template using it',
        () async {
      write('annspec.yaml',
          _spec(bankingBuild: _block('        ', url: '/canvaskit/')));
      final r = await run(['validate', '--project', dir.path]);
      expect('${r.stdout}${r.stderr}', contains('canvaskit_base_url'));
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
    });

    test('is clean with the option and a template that uses it', () async {
      write(
          'annspec.yaml',
          _spec(
              bankingBuild:
                  _block('        ', pwa: 'none', url: '/canvaskit/')));
      write('web_flavors/banking/flutter_bootstrap.tmpl.js', _bootstrapTmpl);
      final r = await run(['validate', '--project', dir.path]);
      expect('${r.stdout}${r.stderr}', isNot(contains('canvaskit_base_url')));
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
    });

    test(
        'a spec without a build block gets no web build finding (REQ-WEB-00140)',
        () async {
      write('annspec.yaml', _spec());
      final r = await run(['validate', '--project', dir.path]);
      expect('${r.stdout}${r.stderr}', isNot(contains('canvaskit')));
      expect('${r.stdout}${r.stderr}', isNot(contains('pwa_strategy')));
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
    });
  });

  group('sync-web', () {
    test('stops on a bad value before copying anything', () async {
      write('annspec.yaml',
          _spec(bankingBuild: _block('        ', pwa: 'always')));
      write('web_flavors/banking/flutter_bootstrap.tmpl.js', _bootstrapTmpl);
      final r =
          await run(['sync-web', '--flavor', 'banking', '--project', dir.path]);
      expect(r.exitCode, isNot(0));
      expect('${r.stdout}${r.stderr}',
          contains('app.web.flavor.banking.build.pwa_strategy'));
      expect(
          File('${dir.path}/web/flutter_bootstrap.js').existsSync(), isFalse);
    });

    test(
        'renders {{canvaskit_base_url}} and leaves Flutter\'s own placeholders as written',
        () async {
      write('annspec.yaml',
          _spec(bankingBuild: _block('        ', url: '/canvaskit/')));
      write('web_flavors/banking/flutter_bootstrap.tmpl.js', _bootstrapTmpl);
      final r =
          await run(['sync-web', '--flavor', 'banking', '--project', dir.path]);
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
      final out =
          File('${dir.path}/web/flutter_bootstrap.js').readAsStringSync();
      expect(out, contains('canvasKitBaseUrl: "/canvaskit/"'));
      expect(out, contains('{{flutter_js}}'));
      expect(out, contains('{{flutter_build_config}}'));
      expect(out, isNot(contains('{{canvaskit_base_url}}')));
    });

    test('{{canvaskit_base_url}} is empty for a flavor that sets none',
        () async {
      write('annspec.yaml', _spec());
      write('web_flavors/plain/flutter_bootstrap.tmpl.js', _bootstrapTmpl);
      final r =
          await run(['sync-web', '--flavor', 'plain', '--project', dir.path]);
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
      expect(File('${dir.path}/web/flutter_bootstrap.js').readAsStringSync(),
          contains('canvasKitBaseUrl: ""'));
    });

    test('a flavor takes canvaskit_base_url from the web default', () async {
      write('annspec.yaml',
          _spec(defaultBuild: _block('      ', url: '/shared/')));
      write('web_flavors/plain/flutter_bootstrap.tmpl.js', _bootstrapTmpl);
      final r =
          await run(['sync-web', '--flavor', 'plain', '--project', dir.path]);
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
      expect(File('${dir.path}/web/flutter_bootstrap.js').readAsStringSync(),
          contains('"/shared/"'));
    });

    test(
        '--scaffold-bootstrap writes a template that keeps the Flutter placeholders, and it renders',
        () async {
      write(
          'annspec.yaml',
          _spec(
              bankingBuild:
                  _block('        ', pwa: 'none', url: '/canvaskit/')));
      final r = await run([
        'sync-web',
        '--flavor',
        'banking',
        '--project',
        dir.path,
        '--scaffold-bootstrap'
      ]);
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
      final tmpl =
          File('${dir.path}/web_flavors/banking/flutter_bootstrap.tmpl.js')
              .readAsStringSync();
      for (final v in const [
        '{{flutter_js}}',
        '{{flutter_build_config}}',
        '{{flutter_service_worker_version}}',
        '{{canvaskit_base_url}}'
      ]) {
        expect(tmpl, contains(v));
      }
      final out =
          File('${dir.path}/web/flutter_bootstrap.js').readAsStringSync();
      expect(out, contains('canvasKitBaseUrl: "/canvaskit/"'));
      expect(out, contains('{{flutter_service_worker_version}}'));
      expect(r.stdout.toString(), isNot(contains('⚠')));
    });

    test('--scaffold-bootstrap never rewrites an existing template', () async {
      write('annspec.yaml', _spec());
      write('web_flavors/plain/flutter_bootstrap.tmpl.js', '// mine\n');
      final r = await run([
        'sync-web',
        '--flavor',
        'plain',
        '--project',
        dir.path,
        '--scaffold-bootstrap'
      ]);
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
      expect(
          File('${dir.path}/web_flavors/plain/flutter_bootstrap.tmpl.js')
              .readAsStringSync(),
          '// mine\n');
    });

    test(
        'a flavor without a build block syncs exactly as before (REQ-WEB-00140)',
        () async {
      write('annspec.yaml', _spec());
      write('web_flavors/plain/manifest.tmpl.json', '{"name": "{{name}}"}\n');
      final r =
          await run(['sync-web', '--flavor', 'plain', '--project', dir.path]);
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
      expect(File('${dir.path}/web/manifest.json').readAsStringSync(),
          contains('"Plain"'));
      expect(
          File('${dir.path}/web/flutter_bootstrap.js').existsSync(), isFalse);
    });
  });
}
