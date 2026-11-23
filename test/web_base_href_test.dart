import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import '../lib_cli/generators/web_base_href_checker.dart';

// Tests do not import ann_flavor_core (not published; scripts/vendor-flutter-core.sh rejects it).

final _packageRoot = Directory.current.path.endsWith('/test')
    ? Directory.current.parent.path
    : Directory.current.path;

const _goodPage = '<html><head><base href="\$FLUTTER_BASE_HREF"></head><body></body></html>';
const _oldPage = '<html><head><base href="/"></head><body></body></html>';

String _spec({String? baseHref = '/banking/'}) => '''
enabled: true
app:
  web:
    default:
      id: com.example.app
    flavor:
      banking:
        name: "Banking"
        main_file: "lib/main_banking.dart"
        version_name: "1.0.0"
        version_code: 100
${baseHref == null ? '' : '        base_href: ${jsonEncode(baseHref)}\n'}      plain:
        name: "Plain"
        main_file: "lib/main_plain.dart"
        version_name: "1.0.0"
        version_code: 100
''';

String _manifest(String startUrl, {String? scope}) => '''{
  "name": "{{name}}",
  "start_url": "$startUrl",
${scope == null ? '' : '  "scope": "$scope",\n'}  "display": "standalone"
}
''';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('web_base_href_'));
  tearDown(() => dir.deleteSync(recursive: true));

  void write(String relative, String content) {
    final f = File('${dir.path}/$relative');
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(content);
  }

  List<String> messages(List<WebBaseHrefFinding> f, {required bool errors}) =>
      [for (final x in f) if (x.isError == errors) x.message];

  group('WebBaseHrefChecker (REQ-WEB-00060)', () {
    test('no findings without base_href or with /', () {
      write('web_flavors/banking/index.tmpl.html', _oldPage);
      expect(WebBaseHrefChecker.check(dir.path, 'banking', null), isEmpty);
      expect(WebBaseHrefChecker.check(dir.path, 'banking', '/'), isEmpty);
    });

    test('a value that breaks the rules is one error and nothing else is checked', () {
      write('web_flavors/banking/index.tmpl.html', _oldPage);
      final f = WebBaseHrefChecker.check(dir.path, 'banking', 'banking');
      expect(f, hasLength(1));
      expect(f.single.isError, isTrue);
      expect(f.single.path, 'app.web.flavor.banking.base_href');
      expect(f.single.message, 'must start with "/"');
    });

    test('a page without \$FLUTTER_BASE_HREF is an error that says what to change', () {
      write('web_flavors/banking/index.tmpl.html', _oldPage);
      final f = WebBaseHrefChecker.check(dir.path, 'banking', '/banking/');
      expect(f, hasLength(1));
      expect(f.single.isError, isTrue);
      expect(f.single.path, 'web_flavors/banking/index.tmpl.html');
      expect(f.single.message, contains('\$FLUTTER_BASE_HREF'));
      expect(f.single.fix, contains('<base href="\$FLUTTER_BASE_HREF">'));
    });

    test('a page with the placeholder is fine', () {
      write('web_flavors/banking/index.tmpl.html', _goodPage);
      expect(WebBaseHrefChecker.check(dir.path, 'banking', '/banking/'), isEmpty);
    });

    test('the page is looked up in order: flavor template, flavor page, web/index.html', () {
      write('web/index.html', _oldPage);
      expect(WebBaseHrefChecker.check(dir.path, 'banking', '/banking/').single.path, 'web/index.html');

      write('web_flavors/banking/index.html', _goodPage);
      expect(WebBaseHrefChecker.check(dir.path, 'banking', '/banking/'), isEmpty);

      write('web_flavors/banking/index.tmpl.html', _oldPage);
      expect(WebBaseHrefChecker.check(dir.path, 'banking', '/banking/').single.path,
          'web_flavors/banking/index.tmpl.html');
    });

    test('no page on disk gives no finding (nothing to check yet)', () {
      expect(WebBaseHrefChecker.check(dir.path, 'banking', '/banking/'), isEmpty);
    });

    test('an absolute start_url or scope outside the base path is a warning naming both lines', () {
      write('web_flavors/banking/index.tmpl.html', _goodPage);
      write('web_flavors/banking/manifest.tmpl.json', _manifest('/', scope: '/'));
      final f = WebBaseHrefChecker.check(dir.path, 'banking', '/banking/');
      expect(f.every((x) => !x.isError), isTrue);
      expect(f, hasLength(2));
      expect(messages(f, errors: false).join('\n'), allOf(contains('start_url'), contains('scope')));
      expect(f.first.fix, contains('{{base_href}}'));
    });

    test('{{base_href}}, a path under the base, and relative values are fine', () {
      write('web_flavors/banking/index.tmpl.html', _goodPage);
      write('web_flavors/banking/manifest.tmpl.json', _manifest('{{base_href}}', scope: '{{base_href}}'));
      expect(WebBaseHrefChecker.check(dir.path, 'banking', '/banking/'), isEmpty);

      write('web_flavors/banking/manifest.tmpl.json', _manifest('/banking/home', scope: '/banking/'));
      expect(WebBaseHrefChecker.check(dir.path, 'banking', '/banking/'), isEmpty);

      write('web_flavors/banking/manifest.tmpl.json', _manifest('.'));
      expect(WebBaseHrefChecker.check(dir.path, 'banking', '/banking/'), isEmpty);
    });

    test('the manifest is looked up as template, then rendered file, then web/manifest.json', () {
      write('web_flavors/banking/index.tmpl.html', _goodPage);
      write('web/manifest.json', _manifest('/'));
      expect(WebBaseHrefChecker.check(dir.path, 'banking', '/banking/'), hasLength(1));
      write('web_flavors/banking/manifest.json', _manifest('/banking/'));
      expect(WebBaseHrefChecker.check(dir.path, 'banking', '/banking/'), isEmpty);
      write('web_flavors/banking/manifest.tmpl.json', _manifest('/'));
      expect(WebBaseHrefChecker.check(dir.path, 'banking', '/banking/'), hasLength(1));
    });

    test('a manifest that is not JSON is skipped, not reported', () {
      write('web_flavors/banking/index.tmpl.html', _goodPage);
      write('web_flavors/banking/manifest.tmpl.json', '{ "start_url": {{base_href}} }');
      expect(WebBaseHrefChecker.check(dir.path, 'banking', '/banking/'), isEmpty);
    });
  });

  Future<ProcessResult> run(List<String> args) =>
      Process.run('dart', ['run', 'ann_flutter_flavor', ...args], workingDirectory: _packageRoot);

  group('validate', () {
    test('reports a page without the placeholder as an error', () async {
      write('annspec.yaml', _spec());
      write('web_flavors/banking/index.tmpl.html', _oldPage);
      final r = await run(['validate', '--project', dir.path]);
      final out = '${r.stdout}${r.stderr}';
      expect(out, contains('FLUTTER_BASE_HREF'));
      expect(r.exitCode, isNot(0));
    });

    test('is clean when the page has the placeholder and the manifest follows the base', () async {
      write('annspec.yaml', _spec());
      write('web_flavors/banking/index.tmpl.html', _goodPage);
      write('web_flavors/banking/manifest.tmpl.json', _manifest('{{base_href}}', scope: '{{base_href}}'));
      final r = await run(['validate', '--project', dir.path]);
      expect('${r.stdout}${r.stderr}', isNot(contains('FLUTTER_BASE_HREF')));
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
    });

    test('warns, without failing, about an absolute start_url outside the base', () async {
      write('annspec.yaml', _spec());
      write('web_flavors/banking/index.tmpl.html', _goodPage);
      write('web_flavors/banking/manifest.tmpl.json', _manifest('/'));
      final r = await run(['validate', '--project', dir.path]);
      expect('${r.stdout}${r.stderr}', contains('start_url'));
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
    });

    test('reports a value that breaks the rules with the flavor path', () async {
      write('annspec.yaml', _spec(baseHref: 'banking'));
      final r = await run(['validate', '--project', dir.path]);
      expect('${r.stdout}${r.stderr}', contains('app.web.flavor.banking.base_href'));
      expect('${r.stdout}${r.stderr}', contains('must start with "/"'));
      expect(r.exitCode, isNot(0));
    });

    test('a flavor without base_href gets no check even with an old page (REQ-WEB-00070)', () async {
      write('annspec.yaml', _spec(baseHref: null));
      write('web_flavors/banking/index.tmpl.html', _oldPage);
      write('web_flavors/banking/manifest.tmpl.json', _manifest('/'));
      final r = await run(['validate', '--project', dir.path]);
      expect('${r.stdout}${r.stderr}', isNot(contains('FLUTTER_BASE_HREF')));
      expect('${r.stdout}${r.stderr}', isNot(contains('start_url')));
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
    });
  });

  group('sync-web', () {
    test('stops with the same error when the page has no placeholder, before copying anything', () async {
      write('annspec.yaml', _spec());
      write('web_flavors/banking/index.tmpl.html', _oldPage);
      final r = await run(['sync-web', '--flavor', 'banking', '--project', dir.path]);
      expect(r.exitCode, isNot(0));
      expect('${r.stdout}${r.stderr}', contains('FLUTTER_BASE_HREF'));
      expect(File('${dir.path}/web/index.html').existsSync(), isFalse);
    });

    test('renders {{base_href}} in the templates of the flavor', () async {
      write('annspec.yaml', _spec());
      write('web_flavors/banking/index.tmpl.html', _goodPage);
      write('web_flavors/banking/manifest.tmpl.json', _manifest('{{base_href}}', scope: '{{base_href}}'));
      final r = await run(['sync-web', '--flavor', 'banking', '--project', dir.path]);
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
      final m = jsonDecode(File('${dir.path}/web/manifest.json').readAsStringSync()) as Map;
      expect(m['start_url'], '/banking/');
      expect(m['scope'], '/banking/');
    });

    test('{{base_href}} is / for a flavor without base_href', () async {
      write('annspec.yaml', _spec());
      write('web_flavors/plain/manifest.tmpl.json', _manifest('{{base_href}}', scope: '{{base_href}}'));
      final r = await run(['sync-web', '--flavor', 'plain', '--project', dir.path]);
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
      final m = jsonDecode(File('${dir.path}/web/manifest.json').readAsStringSync()) as Map;
      expect(m['start_url'], '/');
      expect(m['scope'], '/');
    });

    test('the scaffolded manifest uses {{base_href}} for start_url and scope and renders to the base path', () async {
      write('annspec.yaml', _spec());
      final r = await run(['sync-web', '--flavor', 'banking', '--project', dir.path, '--scaffold-manifest', '--scaffold-index']);
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
      final tmpl = File('${dir.path}/web_flavors/banking/manifest.tmpl.json').readAsStringSync();
      expect(tmpl, contains('"start_url": "{{base_href}}"'));
      expect(tmpl, contains('"scope": "{{base_href}}"'));
      final m = jsonDecode(File('${dir.path}/web/manifest.json').readAsStringSync()) as Map;
      expect(m['start_url'], '/banking/');
      expect(m['scope'], '/banking/');
      expect(File('${dir.path}/web_flavors/banking/index.tmpl.html').readAsStringSync(),
          contains('<base href="\$FLUTTER_BASE_HREF">'));
    });
  });
}
