import 'dart:io';
import 'package:test/test.dart';
import '../lib_cli/generators/web_build_options_checker.dart';
import '../lib_cli/generators/web_icon_checker.dart';
import '../lib_cli/spec/annspec_reader.dart';

// Tests do not import ann_flavor_core (not published; scripts/vendor-flutter-core.sh rejects it).

String _spec({String defaultBuild = '', String flavorBuild = ''}) => '''
enabled: true
app:
  web:
    default:
      id: com.example.app
$defaultBuild    flavor:
      a:
        name: "A"
        main_file: "lib/main_a.dart"
        version_name: "1.0.0"
        version_code: 100
$flavorBuild''';

const _canvaskit = '      build:\n        canvaskit_base_url: /canvaskit/\n';
const _pwaOnly = '      build:\n        pwa_strategy: none\n';

String _manifest(List<String> srcs) =>
    '{"name": "{{name}}", "start_url": "{{base_href}}", "icons": [${srcs.map((s) => '{"src": "$s", "sizes": "192x192", "type": "image/png"}').join(', ')}]}\n';

String _page(
        {String script = '<script src="flutter_bootstrap.js" async></script>',
        String head = ''}) =>
    '<!DOCTYPE html><html><head><base href="\$FLUTTER_BASE_HREF">$head</head><body>$script</body></html>\n';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('web_icon_'));
  tearDown(() => dir.deleteSync(recursive: true));

  void write(String relative, [String content = 'x']) {
    final f = File('${dir.path}/$relative');
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(content);
  }

  List<WebIconFinding> icons() => WebIconChecker.check(dir.path, 'a');

  List<WebBuildOptionsFinding> options() {
    final web = AnnspecReader.read(dir.path).app.web!;
    return WebBuildOptionsChecker.check(dir.path, 'a', web);
  }

  List<WebBuildOptionsFinding> bootstrapWarnings() => options()
      .where((f) => !f.isError && f.message.contains('flutter_bootstrap.js'))
      .toList();

  group('the bootstrap warning (REQ-WEB-00260)', () {
    test(
        'canvaskit_base_url with a page that loads the old loader warns, naming the setting and the fix',
        () {
      write('annspec.yaml', _spec(defaultBuild: _canvaskit));
      write(
          'web_flavors/a/index.tmpl.html',
          _page(
              script:
                  '<script src="flutter.js" defer></script><script>_flutter.loader.loadEntrypoint({});</script>'));
      write(
          'web_flavors/a/flutter_bootstrap.tmpl.js', '{{canvaskit_base_url}}');
      final w = bootstrapWarnings();
      expect(w, hasLength(1));
      expect(w.single.path, 'app.web.flavor.a.build.canvaskit_base_url');
      expect(w.single.fix, contains('--scaffold-index'));
    });

    test(
        'a page that loads flutter_bootstrap.js gives no warning, whatever the attributes',
        () {
      write('annspec.yaml', _spec(defaultBuild: _canvaskit));
      write(
          'web_flavors/a/flutter_bootstrap.tmpl.js', '{{canvaskit_base_url}}');
      for (final tag in [
        '<script src="flutter_bootstrap.js" async></script>',
        "<script src='flutter_bootstrap.js'></script>",
        '<script defer src="flutter_bootstrap.js"></script>',
        '<script async src="./flutter_bootstrap.js"></script>',
      ]) {
        write('web_flavors/a/index.tmpl.html', _page(script: tag));
        expect(bootstrapWarnings(), isEmpty, reason: tag);
      }
    });

    test('a script tag inside an HTML comment does not count', () {
      write('annspec.yaml', _spec(defaultBuild: _canvaskit));
      write(
          'web_flavors/a/flutter_bootstrap.tmpl.js', '{{canvaskit_base_url}}');
      write(
          'web_flavors/a/index.tmpl.html',
          _page(
              script:
                  '<!-- <script src="flutter_bootstrap.js" async></script> -->'));
      expect(bootstrapWarnings(), hasLength(1));
    });

    test('no page anywhere skips the check', () {
      write('annspec.yaml', _spec(defaultBuild: _canvaskit));
      write(
          'web_flavors/a/flutter_bootstrap.tmpl.js', '{{canvaskit_base_url}}');
      expect(bootstrapWarnings(), isEmpty);
    });

    test(
        'the page is found in the flavor folder (template, then rendered file), then web/',
        () {
      write('annspec.yaml', _spec(defaultBuild: _canvaskit));
      write(
          'web_flavors/a/flutter_bootstrap.tmpl.js', '{{canvaskit_base_url}}');
      write('web/index.html',
          _page(script: '<script src="flutter.js"></script>'));
      expect(bootstrapWarnings(), hasLength(1),
          reason: 'web/index.html with the old loader');
      write('web_flavors/a/index.html', _page());
      expect(bootstrapWarnings(), isEmpty,
          reason: 'the flavor\'s rendered page wins over web/');
      write('web_flavors/a/index.tmpl.html',
          _page(script: '<script src="flutter.js"></script>'));
      expect(bootstrapWarnings(), hasLength(1),
          reason: 'the flavor\'s template wins over its rendered page');
    });

    test('canvaskit_base_url set on the flavor itself warns too', () {
      write(
          'annspec.yaml',
          _spec(
              flavorBuild:
                  '        build:\n          canvaskit_base_url: /ck/\n'));
      write(
          'web_flavors/a/flutter_bootstrap.tmpl.js', '{{canvaskit_base_url}}');
      write('web_flavors/a/index.tmpl.html',
          _page(script: '<script src="flutter.js"></script>'));
      expect(bootstrapWarnings(), hasLength(1));
    });

    test('pwa_strategy alone gives no warning, even with the old loader', () {
      write('annspec.yaml', _spec(defaultBuild: _pwaOnly));
      write('web_flavors/a/index.tmpl.html',
          _page(script: '<script src="flutter.js" defer></script>'));
      expect(bootstrapWarnings(), isEmpty);
    });

    test('a flavor without a build block gives no warning (regression)', () {
      write('annspec.yaml', _spec());
      write('web_flavors/a/index.tmpl.html',
          _page(script: '<script src="flutter.js" defer></script>'));
      expect(bootstrapWarnings(), isEmpty);
    });
  });

  group('WebIconChecker (REQ-WEB-00260)', () {
    test('no findings when every icon exists with exactly that case', () {
      write('web_flavors/a/manifest.tmpl.json',
          _manifest(['icons/Icon-192.png', 'icons/Icon-512.png']));
      write(
          'web_flavors/a/index.tmpl.html',
          _page(
              head: '<link rel="apple-touch-icon" href="icons/Icon-192.png">'));
      write('web_flavors/a/icons/Icon-192.png');
      write('web_flavors/a/icons/Icon-512.png');
      expect(icons(), isEmpty);
    });

    test(
        'a missing icon is one warning that names the file and the document and says what to do',
        () {
      write('web_flavors/a/manifest.tmpl.json',
          _manifest(['icons/Icon-192.png', 'icons/Icon-512.png']));
      write('web_flavors/a/icons/Icon-192.png');
      final f = icons();
      expect(f, hasLength(1));
      expect(f.single.path, 'web_flavors/a/manifest.tmpl.json');
      expect(f.single.message, contains('icons/Icon-512.png'));
      expect(f.single.fix, contains('generate-icons'));
    });

    test(
        'a file that differs only in case is reported with the name that exists, even on a case-insensitive file system',
        () {
      write('web_flavors/a/manifest.tmpl.json',
          _manifest(['icons/icon-192.png']));
      write('web_flavors/a/icons/Icon-192.png');
      final f = icons();
      expect(f, hasLength(1));
      expect(f.single.message, contains('icons/icon-192.png'));
      expect(f.single.message, contains('Icon-192.png'));
      expect(f.single.message.toLowerCase(), contains('case'));
      expect(f.single.fix, contains('"icons/Icon-192.png"'),
          reason: 'the fix gives the reference as the page writes it');
      expect(f.single.fix, isNot(contains('"web_flavors')),
          reason: 'not the path with the folder in front');
      expect(f.single.fix, isNot(contains('"a/icons')));
    });

    test('a folder whose case differs is reported too', () {
      write('web_flavors/a/manifest.tmpl.json',
          _manifest(['icons/Icon-192.png']));
      write('web_flavors/a/Icons/Icon-192.png');
      final f = icons();
      expect(f, hasLength(1));
      expect(f.single.message, contains('Icons'));
    });

    test(
        'the page\'s apple-touch icon and rel=icon are checked, relative to the page',
        () {
      write(
          'web_flavors/a/index.tmpl.html',
          _page(
              head:
                  '<link rel="apple-touch-icon" href="icons/icon-192.png"><link rel="icon" type="image/png" href="favicon.png">'));
      write('web_flavors/a/icons/Icon-192.png');
      write('web_flavors/a/favicon.png');
      final f = icons();
      expect(f, hasLength(1));
      expect(f.single.path, 'web_flavors/a/index.tmpl.html');
      expect(f.single.message, contains('icons/icon-192.png'));
    });

    test(
        'an icon is found in web/ when it is not in the flavor folder (the project\'s own icons)',
        () {
      write('web_flavors/a/manifest.tmpl.json',
          _manifest(['icons/Icon-192.png']));
      write('web/icons/Icon-192.png');
      expect(icons(), isEmpty);
    });

    test('absolute URLs, data URIs and paths with a variable are skipped', () {
      write(
          'web_flavors/a/manifest.tmpl.json',
          _manifest([
            'https://cdn.example.com/icon.png',
            'data:image/png;base64,AAAA',
            '{{base_href}}icons/Icon-192.png',
            '\$FLUTTER_BASE_HREF/i.png',
          ]));
      expect(icons(), isEmpty);
    });

    test(
        'the manifest is found as a template, then a rendered file in the flavor folder, then web/manifest.json',
        () {
      write('web/manifest.json', _manifest(['icons/Icon-192.png']));
      expect(icons(), hasLength(1), reason: 'web/manifest.json');
      write('web_flavors/a/manifest.json',
          _manifest(['icons/Icon-192.png', 'icons/Icon-512.png']));
      expect(
          icons().map((f) => f.path).toSet(), {'web_flavors/a/manifest.json'},
          reason: 'the flavor\'s rendered file wins');
      write('web_flavors/a/manifest.tmpl.json',
          _manifest(['icons/Icon-maskable-192.png']));
      expect(icons().single.path, 'web_flavors/a/manifest.tmpl.json',
          reason: 'the flavor\'s template wins');
    });

    test('a manifest that is not valid JSON is skipped without an error', () {
      write('web_flavors/a/manifest.tmpl.json', '{ not json');
      expect(icons(), isEmpty);
    });

    test('no manifest and no page gives no findings', () {
      expect(icons(), isEmpty);
    });

    test('the same file named twice in one document is one warning', () {
      write('web_flavors/a/manifest.tmpl.json',
          _manifest(['icons/Icon-192.png', 'icons/Icon-192.png']));
      expect(icons(), hasLength(1));
    });

    test('a file in a sub folder is checked segment by segment', () {
      write('web_flavors/a/manifest.tmpl.json',
          _manifest(['icons/sub/Icon-192.png']));
      write('web_flavors/a/icons/sub/Icon-192.png');
      expect(icons(), isEmpty);
    });
  });
}
