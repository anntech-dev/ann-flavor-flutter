import 'dart:io';
import 'package:test/test.dart';
import '../lib_cli/generators/web_site_checker.dart';
import '../lib_cli/spec/annspec_reader.dart';

// Tests do not import ann_flavor_core (not published; scripts/vendor-flutter-core.sh rejects it).

final _packageRoot = Directory.current.path.endsWith('/test')
    ? Directory.current.parent.path
    : Directory.current.path;

String _spec({String site = '', String flavors = ''}) => '''
enabled: true
app:
  web:
    default:
      id: com.example.app
$site    flavor:
      calculator:
        name: "Calculator"
        main_file: "lib/main_calculator.dart"
        version_name: "1.0.0"
        version_code: 100
        base_href: /calculator/
      banking:
        name: "Banking"
        main_file: "lib/main_banking.dart"
        version_name: "1.0.0"
        version_code: 100
        base_href: /banking/
$flavors''';

String _site(
        {String hub = '',
        String project = 'calculators',
        List<String> list = const ['calculator', 'banking']}) =>
    '''    site:
      calculators:
        flavors: [${list.join(', ')}]
${project.isEmpty ? '' : '        cloudflare:\n          project_name: $project\n'}${hub.isEmpty ? '' : '        hub_dir: $hub\n'}''';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('web_site_'));
  tearDown(() => dir.deleteSync(recursive: true));

  void write(String relative, String content) {
    final f = File('${dir.path}/$relative');
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(content);
  }

  List<WebSiteFinding> check() =>
      WebSiteChecker.check(dir.path, AnnspecReader.read(dir.path).app.web!);

  group('WebSiteChecker (REQ-WEB-00160, REQ-WEB-00180)', () {
    test('no findings without a site (REQ-WEB-00230)', () {
      write('annspec.yaml', _spec());
      expect(check(), isEmpty);
    });

    test('a valid site without a hub folder is clean', () {
      write('annspec.yaml', _spec(site: _site()));
      expect(check(), isEmpty);
    });

    test('a valid site with an existing hub folder is clean', () {
      write('annspec.yaml', _spec(site: _site(hub: 'web_site/hub')));
      write('web_site/hub/index.html', 'hub');
      expect(check(), isEmpty);
    });

    test('rule problems come from the core with the site path and message', () {
      write('annspec.yaml',
          _spec(site: _site(project: '', list: ['calculator', 'nope'])));
      final f = check();
      expect(
          f.map((x) => '${x.path}: ${x.message}'),
          unorderedEquals([
            'app.web.site.calculators.flavors: "nope" is not a web flavor',
            'app.web.site.calculators.cloudflare.project_name: must be set',
          ]));
    });

    test('a hub folder that does not exist is an error with a fix', () {
      write('annspec.yaml', _spec(site: _site(hub: 'web_site/hub')));
      final f = check();
      expect(f.single.path, 'app.web.site.calculators.hub_dir');
      expect(f.single.message, contains('does not exist'));
      expect(f.single.fix, isNotNull);
    });

    test('a hub path that is a file is an error', () {
      write('annspec.yaml', _spec(site: _site(hub: 'hub.html')));
      write('hub.html', 'x');
      expect(check().single.message, contains('is a file, not a folder'));
    });

    test(
        'an entry named like the first segment of a flavor path is an error naming the flavor',
        () {
      write('annspec.yaml', _spec(site: _site(hub: 'hub')));
      write('hub/banking/index.html', 'x');
      write('hub/index.html', 'hub');
      final f = check();
      expect(f.single.path, 'app.web.site.calculators.hub_dir');
      expect(f.single.message, contains('"banking"'));
      expect(f.single.message, contains('flavor "banking"'));
      expect(f.single.message, contains('/banking/'));
    });

    test(
        'a file named like the flavor segment is also an error; other names are fine',
        () {
      write('annspec.yaml', _spec(site: _site(hub: 'hub')));
      write('hub/calculator', 'a file');
      write('hub/bankingx/index.html', 'fine');
      write('hub/index.html', 'hub');
      final f = check();
      expect(f.single.message, contains('"calculator"'));
    });

    test(
        'a hub path the core rejects is not looked at on disk (no ".." escape)',
        () {
      write('annspec.yaml', _spec(site: _site(hub: '../outside')));
      final f = check();
      expect(f.single.message, 'must not contain ".." segments');
    });
  });

  Future<ProcessResult> run(List<String> args) =>
      Process.run('dart', ['run', 'ann_flutter_flavor', ...args],
          workingDirectory: _packageRoot);

  group('validate', () {
    test('is clean for a valid site with a hub folder', () async {
      write('annspec.yaml', _spec(site: _site(hub: 'hub')));
      write('hub/index.html', 'hub');
      final r = await run(['validate', '--project', dir.path]);
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
    });

    test(
        'reports a rule problem and a hub problem as errors and exits non-zero',
        () async {
      write(
          'annspec.yaml',
          _spec(
              site: _site(
                  hub: 'missing', list: ['calculator', 'banking', 'nope'])));
      final r = await run(['validate', '--project', dir.path]);
      final out = '${r.stdout}${r.stderr}';
      expect(out, contains('app.web.site.calculators.flavors'));
      expect(out, contains('"nope" is not a web flavor'));
      expect(out, contains('app.web.site.calculators.hub_dir'));
      expect(out, contains('does not exist'));
      expect(r.exitCode, isNot(0));
    });

    test('a spec without a site gets no site finding (REQ-WEB-00230)',
        () async {
      write('annspec.yaml', _spec());
      final r = await run(['validate', '--project', dir.path]);
      expect('${r.stdout}${r.stderr}', isNot(contains('app.web.site')));
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
    });
  });
}
