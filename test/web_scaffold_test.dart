import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';

// Tests do not import ann_flavor_core (not published; scripts/vendor-flutter-core.sh rejects it).

final _packageRoot = Directory.current.path.endsWith('/test')
    ? Directory.current.parent.path
    : Directory.current.path;

const _spec = '''
enabled: true
app:
  web:
    default:
      id: com.example.app
      version_name: 1.0.0
      version_code: 100
      main_file: lib/main.dart
    flavor:
      a:
        name: "Probe A"
''';

const _specWithCanvaskit = '''
enabled: true
app:
  web:
    default:
      id: com.example.app
      version_name: 1.0.0
      version_code: 100
      main_file: lib/main.dart
      build:
        pwa_strategy: none
        canvaskit_base_url: /canvaskit/
    flavor:
      a:
        name: "Probe A"
''';

const _icons = [
  'Icon-192.png',
  'Icon-512.png',
  'Icon-maskable-192.png',
  'Icon-maskable-512.png'
];

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('web_scaffold_'));
  tearDown(() => dir.deleteSync(recursive: true));

  void write(String relative, String content) {
    final f = File('${dir.path}/$relative');
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(content);
  }

  Future<ProcessResult> run(List<String> args) =>
      Process.run('dart', ['run', 'ann_flutter_flavor', ...args],
          workingDirectory: _packageRoot);

  Future<ProcessResult> scaffold(
          {List<String> flags = const [
            '--scaffold-manifest',
            '--scaffold-index',
            '--scaffold-bootstrap'
          ]}) =>
      run(['sync-web', '--flavor', 'a', '--project', dir.path, ...flags]);

  group('the scaffolded manifest (REQ-WEB-00240)', () {
    test(
        'names the four files generate-icons writes, with the same case, and no lowercase name',
        () async {
      write('annspec.yaml', _spec);
      final r = await scaffold(flags: ['--scaffold-manifest']);
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
      final tmpl = File('${dir.path}/web_flavors/a/manifest.tmpl.json')
          .readAsStringSync();
      for (final name in _icons) {
        expect(tmpl, contains('"src": "icons/$name"'), reason: tmpl);
      }
      expect(tmpl, isNot(contains('icons/icon-')), reason: tmpl);
    });

    test('keeps the maskable purpose on the two maskable files and the sizes',
        () async {
      write('annspec.yaml', _spec);
      await scaffold(flags: ['--scaffold-manifest']);
      final m = jsonDecode(File('${dir.path}/web_flavors/a/manifest.tmpl.json')
          .readAsStringSync()) as Map;
      final icons = (m['icons'] as List).cast<Map>();
      expect(icons.map((i) => i['src']).toList(),
          [for (final n in _icons) 'icons/$n']);
      expect([for (final i in icons) i['purpose']],
          [null, null, 'maskable', 'maskable']);
      expect([for (final i in icons) i['sizes']],
          ['192x192', '512x512', '192x192', '512x512']);
    });
  });

  group('the scaffolded page (REQ-WEB-00240, REQ-WEB-00250)', () {
    test(
        'loads flutter_bootstrap.js and has no service worker block, flutter.js tag or loadEntrypoint',
        () async {
      write('annspec.yaml', _spec);
      final r = await scaffold(flags: ['--scaffold-index']);
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
      final page =
          File('${dir.path}/web_flavors/a/index.tmpl.html').readAsStringSync();
      expect(
          page, contains('<script src="flutter_bootstrap.js" async></script>'));
      expect(page, isNot(contains('serviceWorkerVersion')));
      expect(page, isNot(contains('loadEntrypoint')));
      expect(page, isNot(contains('flutter.js')));
    });

    test(
        'keeps the base href placeholder, the manifest link, the theme colour and the apple-touch icon with the generated name',
        () async {
      write('annspec.yaml', _spec);
      await scaffold(flags: ['--scaffold-index']);
      final page =
          File('${dir.path}/web_flavors/a/index.tmpl.html').readAsStringSync();
      expect(page, contains('<base href="\$FLUTTER_BASE_HREF">'));
      expect(page, contains('<link rel="manifest" href="manifest.json">'));
      expect(page, contains('{{theme_color}}'));
      expect(page,
          contains('<link rel="apple-touch-icon" href="icons/Icon-192.png">'));
      expect(page, isNot(contains('icons/icon-')));
    });

    test('is rendered into web/index.html with the flavor name', () async {
      write('annspec.yaml', _spec);
      final r = await scaffold(flags: ['--scaffold-index']);
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
      final out = File('${dir.path}/web/index.html').readAsStringSync();
      expect(out, contains('<title>Probe A</title>'));
      expect(out, contains('flutter_bootstrap.js'));
      expect(out, isNot(contains('{{')));
    });

    test('a template that already exists is never rewritten (REQ-WEB-00050)',
        () async {
      write('annspec.yaml', _spec);
      write('web_flavors/a/index.tmpl.html',
          '<html><base href="\$FLUTTER_BASE_HREF"><!-- mine --></html>\n');
      write('web_flavors/a/manifest.tmpl.json',
          '{"name": "mine", "icons": []}\n');
      final r = await scaffold();
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
      expect(
          File('${dir.path}/web_flavors/a/index.tmpl.html').readAsStringSync(),
          contains('<!-- mine -->'));
      expect(
          File('${dir.path}/web_flavors/a/manifest.tmpl.json')
              .readAsStringSync(),
          contains('"mine"'));
    });
  });

  group('a flavor scaffolded with the three flags (the issue\'s done-when)',
      () {
    test(
        'with the generated icons in place, validate has no warning and sync-web copies everything',
        () async {
      write('annspec.yaml', _specWithCanvaskit);
      var r = await scaffold();
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
      for (final n in _icons) {
        write('web_flavors/a/icons/$n', 'png');
      }
      write('web/favicon.png',
          'png'); // a Flutter project has one; the scaffolded page names it
      r = await run(['validate', '--project', dir.path]);
      final out = '${r.stdout}${r.stderr}';
      expect(out, isNot(contains('⚠')), reason: out);
      expect(r.exitCode, 0, reason: out);
      r = await run(['sync-web', '--flavor', 'a', '--project', dir.path]);
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
      expect('${r.stdout}', isNot(contains('⚠')));
      expect(File('${dir.path}/web/icons/Icon-512.png').existsSync(), isTrue);
      expect(File('${dir.path}/web/index.html').readAsStringSync(),
          contains('flutter_bootstrap.js'),
          reason: 'the page loads the file that carries canvaskit_base_url');
      expect(File('${dir.path}/web/flutter_bootstrap.js').readAsStringSync(),
          contains('canvasKitBaseUrl: "/canvaskit/"'));
    });
  });

  group('a project scaffolded the old way (REQ-WEB-00260)', () {
    const oldManifest =
        '{"name": "{{name}}", "icons": [{"src": "icons/icon-192.png", "sizes": "192x192", "type": "image/png"}]}\n';
    const oldPage =
        '<!DOCTYPE html><html><head><base href="\$FLUTTER_BASE_HREF">'
        '<link rel="apple-touch-icon" href="icons/icon-192.png"><script src="flutter.js" defer></script></head>'
        '<body><script>_flutter.loader.loadEntrypoint({});</script></body></html>\n';

    test('validate shows both warnings and still exits 0', () async {
      write('annspec.yaml', _specWithCanvaskit);
      write('web_flavors/a/manifest.tmpl.json', oldManifest);
      write('web_flavors/a/index.tmpl.html', oldPage);
      write('web_flavors/a/flutter_bootstrap.tmpl.js',
          '{{flutter_js}}\n{{flutter_build_config}}\n_flutter.loader.load({config: {canvasKitBaseUrl: "{{canvaskit_base_url}}"}});\n');
      for (final n in _icons) {
        write('web_flavors/a/icons/$n', 'png');
      }
      final r = await run(['validate', '--project', dir.path]);
      final out = '${r.stdout}${r.stderr}';
      expect(out, contains('flutter_bootstrap.js'), reason: out);
      expect(out, contains('Icon-192.png'), reason: out);
      expect(out, contains('icon-192.png'), reason: out);
      expect(r.exitCode, 0, reason: out);
    });

    test('sync-web prints the same warnings and continues', () async {
      write('annspec.yaml', _specWithCanvaskit);
      write('web_flavors/a/manifest.tmpl.json', oldManifest);
      write('web_flavors/a/index.tmpl.html', oldPage);
      write('web_flavors/a/flutter_bootstrap.tmpl.js',
          '{{flutter_js}}\n{{flutter_build_config}}\n_flutter.loader.load({config: {canvasKitBaseUrl: "{{canvaskit_base_url}}"}});\n');
      for (final n in _icons) {
        write('web_flavors/a/icons/$n', 'png');
      }
      final r = await run(['sync-web', '--flavor', 'a', '--project', dir.path]);
      final out = '${r.stdout}${r.stderr}';
      expect(out, contains('flutter_bootstrap.js'), reason: out);
      expect(out, contains('Icon-192.png'), reason: out);
      expect(r.exitCode, 0, reason: out);
      expect(File('${dir.path}/web/index.html').existsSync(), isTrue);
    });

    test(
        'a flavor with neither canvaskit_base_url nor a relative icon reference gets no warning (regression)',
        () async {
      write('annspec.yaml', _spec);
      write('web_flavors/a/manifest.tmpl.json',
          '{"name": "{{name}}", "icons": [{"src": "https://cdn.example.com/i.png"}]}\n');
      write('web_flavors/a/index.tmpl.html',
          '<html><body><script src="flutter.js" defer></script></body></html>\n');
      final r = await run(['validate', '--project', dir.path]);
      final out = '${r.stdout}${r.stderr}';
      expect(out, isNot(contains('⚠')), reason: out);
      expect(r.exitCode, 0, reason: out);
    });
  });
}
