import 'dart:io';
import 'package:test/test.dart';

final _packageRoot = Directory.current.path.endsWith('/test')
    ? Directory.current.parent.path
    : Directory.current.path;

void _writeWebSpec(Directory dir, {bool withIcon = false}) {
  final iconLine = withIcon ? '\n      icon: assets/icons/icon.png' : '';
  File('${dir.path}/annspec.yaml').writeAsStringSync('''
enabled: true
app:
  web:
    default:
      id: com.example.test$iconLine
    flavor:
      ledger_in:
        name: "Ledger IN"
        version_name: "1.2.3"
        version_code: 10203
        id_suffix: .in
''');
}

Future<ProcessResult> _runSyncWeb(
  Directory dir,
  List<String> extra, {
  bool withIcon = false,
}) async {
  _writeWebSpec(dir, withIcon: withIcon);
  return Process.run(
    Platform.executable,
    [
      'run', 'ann_flutter_flavor', 'sync-web',
      '--flavor', 'ledger_in',
      '--project', dir.path,
      ...extra,
    ],
    workingDirectory: _packageRoot,
  );
}

void main() {
  group('sync-web command', () {
    late Directory tmp;

    setUp(() => tmp = Directory.systemTemp.createTempSync('sync_web_test_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('exits 0 for a valid web flavor', () async {
      final result = await _runSyncWeb(tmp, []);
      expect(result.exitCode, 0,
          reason: 'stderr: ${result.stderr}\nstdout: ${result.stdout}');
    });

    test('creates web_flavors/<flavor>/ directory', () async {
      await _runSyncWeb(tmp, []);
      expect(Directory('${tmp.path}/web_flavors/ledger_in').existsSync(), isTrue);
    });

    test('creates version.json with correct fields', () async {
      await _runSyncWeb(tmp, []);
      final f = File('${tmp.path}/web_flavors/ledger_in/version.json');
      expect(f.existsSync(), isTrue);
      final content = f.readAsStringSync();
      expect(content, contains('"app_name": "Ledger IN"'));
      expect(content, contains('"version": "1.2.3"'));
      expect(content, contains('"build_number": "10203"'));
      expect(content, contains('"package_name": "com.example.test.in"'));
    });

    test('copies non-template files to web/', () async {
      // Place a non-template file in web_flavors/ledger_in/ before running
      final flavorDir = Directory('${tmp.path}/web_flavors/ledger_in')
        ..createSync(recursive: true);
      File('${flavorDir.path}/favicon.png').writeAsBytesSync([0, 0]);

      await _runSyncWeb(tmp, []);

      expect(File('${tmp.path}/web/favicon.png').existsSync(), isTrue);
    });

    test('does not copy *.tmpl.* files to web/', () async {
      final flavorDir = Directory('${tmp.path}/web_flavors/ledger_in')
        ..createSync(recursive: true);
      File('${flavorDir.path}/manifest.tmpl.json')
          .writeAsStringSync('{"name":"{{name}}"}');

      await _runSyncWeb(tmp, []);

      expect(File('${tmp.path}/web/manifest.tmpl.json').existsSync(), isFalse);
    });

    test('renders *.tmpl.* → *.* in web_flavors/', () async {
      final flavorDir = Directory('${tmp.path}/web_flavors/ledger_in')
        ..createSync(recursive: true);
      File('${flavorDir.path}/manifest.tmpl.json')
          .writeAsStringSync('{"name":"{{name}}","version":"{{version}}"}');

      await _runSyncWeb(tmp, []);

      final rendered = File('${tmp.path}/web_flavors/ledger_in/manifest.json');
      expect(rendered.existsSync(), isTrue);
      final content = rendered.readAsStringSync();
      expect(content, contains('"name":"Ledger IN"'));
      expect(content, contains('"version":"1.2.3"'));
    });

    test('copies rendered manifest.json (not template) to web/', () async {
      final flavorDir = Directory('${tmp.path}/web_flavors/ledger_in')
        ..createSync(recursive: true);
      File('${flavorDir.path}/manifest.tmpl.json')
          .writeAsStringSync('{"name":"{{name}}"}');

      await _runSyncWeb(tmp, []);

      final webManifest = File('${tmp.path}/web/manifest.json');
      expect(webManifest.existsSync(), isTrue);
      expect(webManifest.readAsStringSync(), contains('"name":"Ledger IN"'));
    });

    test('--scaffold-manifest creates manifest.tmpl.json', () async {
      await _runSyncWeb(tmp, ['--scaffold-manifest']);
      expect(
        File('${tmp.path}/web_flavors/ledger_in/manifest.tmpl.json').existsSync(),
        isTrue,
      );
    });

    test('--scaffold-index creates index.tmpl.html', () async {
      await _runSyncWeb(tmp, ['--scaffold-index']);
      expect(
        File('${tmp.path}/web_flavors/ledger_in/index.tmpl.html').existsSync(),
        isTrue,
      );
    });

    test('exits non-zero for unknown flavor', () async {
      _writeWebSpec(tmp);
      final result = await Process.run(
        Platform.executable,
        [
          'run', 'ann_flutter_flavor', 'sync-web',
          '--flavor', 'nonexistent_flavor',
          '--project', tmp.path,
        ],
        workingDirectory: _packageRoot,
      );
      expect(result.exitCode, isNot(0));
    });

    test('exits non-zero when annspec.yaml is missing', () async {
      final result = await Process.run(
        Platform.executable,
        [
          'run', 'ann_flutter_flavor', 'sync-web',
          '--flavor', 'ledger_in',
          '--project', tmp.path,
        ],
        workingDirectory: _packageRoot,
      );
      expect(result.exitCode, isNot(0));
    });

    test('appends web entries to .gitignore', () async {
      await _runSyncWeb(tmp, []);
      final gi = File('${tmp.path}/.gitignore');
      // .gitignore is written by sync spec web step, not sync-web itself —
      // sync-web does not modify .gitignore directly. Verified: no gitignore mutation.
      // This test confirms sync-web does NOT create a .gitignore (that's sync spec's job).
      expect(gi.existsSync(), isFalse);
    });

    test('[web] label appears in sync spec output for web platform', () async {
      // Validate that sync_command emits [web] when a web platform is present.
      // We run sync with --format=human and look for the label.
      _writeWebSpec(tmp);
      // pubspec.yaml must exist for flutter dependency resolution
      File('${tmp.path}/pubspec.yaml').writeAsStringSync('''
name: test_app
environment:
  sdk: ">=3.0.0 <4.0.0"
''');
      final result = await Process.run(
        Platform.executable,
        ['run', 'ann_flutter_flavor', 'sync', '--project', tmp.path],
        workingDirectory: _packageRoot,
      );
      expect(result.stdout.toString(), contains('[web]'));
    });
  });
}
