import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import '../lib_cli/generators/links_generator.dart';
import '../lib_cli/spec/annspec_reader.dart';

final _packageRoot = Directory.current.path.endsWith('/test')
    ? Directory.current.parent.path
    : Directory.current.path;

String _fp(int n) => List.generate(32, (i) => ((n * 7 + i * 13) % 256).toRadixString(16).padLeft(2, '0').toUpperCase()).join(':');

final _f1 = _fp(1), _f2 = _fp(2), _f3 = _fp(3);

/// The Love Tester case: one domain, two Android apps, one iPhone app; the free web build serves the files.
String _loveTester({String destination = 'serve_from: free', String extra = ''}) => '''
app:
  android:
    default:
      id: com.example.lt
    flavor:
      free:
        name: "Free"
      tamil:
        name: "Tamil"
        id_suffix: .tamil
  ios:
    default:
      id: com.example.lt
      credentials:
        signing:
          team_id: ABCDE12345
    flavor:
      free:
        name: "Free"
  web:
    default:
      id: com.example.lt
    flavor:
      free:
        name: "Free"
links:
  $destination
  default:
    domain: links.example.com
    android:
      sha256_fingerprints: ["$_f1"]
  flavors:
    free:
      path_prefix: /en
      also_handles: [/ta]
      android:
        sha256_fingerprints: ["$_f2"]
    tamil:
      path_prefix: /ta
      android:
        sha256_fingerprints: ["$_f3"]
$extra''';

dynamic _readJson(String path) => jsonDecode(File(path).readAsStringSync());

void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('links_generator_test_'));
  tearDown(() => root.deleteSync(recursive: true));

  // The spec is read through AnnspecReader: tests must not import ann_flavor_core, which is
  // not published (scripts/vendor-flutter-core.sh rejects it).
  LinksResult run(String yaml) {
    File('${root.path}/annspec.yaml').writeAsStringSync(yaml);
    return LinksGenerator.generate(AnnspecReader.read(root.path), root.path);
  }

  group('assetlinks.json', () {
    test('lists every Android package on the domain, including a flavor with no web flavor', () {
      run(_loveTester());

      final statements = _readJson('${root.path}/web_flavors/free/.well-known/assetlinks.json') as List;
      expect(statements.map((s) => s['target']['package_name']), ['com.example.lt', 'com.example.lt.tamil']);
      expect(statements[0]['relation'], ['delegate_permission/common.handle_all_urls']);
      expect(statements[0]['target']['namespace'], 'android_app');
      expect(statements[0]['target']['sha256_cert_fingerprints'], [_f1, _f2]..sort());
      expect(statements[1]['target']['sha256_cert_fingerprints'], [_f1, _f3]..sort());
    });

    test('includes a flavor\'s debug fingerprints in its own statement only', () {
      run(_loveTester().replaceFirst('''
      android:
        sha256_fingerprints: ["$_f3"]''', '''
      android:
        sha256_fingerprints: ["$_f3"]
        debug_sha256_fingerprints: ["${_fp(9)}"]'''));

      final statements = _readJson('${root.path}/web_flavors/free/.well-known/assetlinks.json') as List;
      expect(statements[0]['target']['sha256_cert_fingerprints'], hasLength(2));
      expect(statements[1]['target']['sha256_cert_fingerprints'], contains(_fp(9)));
    });
  });

  group('apple-app-site-association', () {
    test('lists only iOS flavors, with their own and also_handles prefixes', () {
      run(_loveTester());

      final aasa = _readJson('${root.path}/web_flavors/free/.well-known/apple-app-site-association');
      final details = aasa['applinks']['details'] as List;
      expect(details, hasLength(1));
      expect(details[0]['appIDs'], ['ABCDE12345.com.example.lt']);
      expect(details[0]['components'], [
        {'/': '/en'},
        {'/': '/en/*'},
        {'/': '/ta'},
        {'/': '/ta/*'},
      ]);
    });

    test('is not written when no flavor on the domain is an iOS flavor', () {
      run('''
app:
  android:
    default:
      id: com.example.a
    flavor:
      main:
        name: "Main"
links:
  well_known_dir: public
  flavors:
    main:
      domain: a.example.com
      path_prefix: /go
      android:
        sha256_fingerprints: ["$_f1"]
''');

      expect(File('${root.path}/public/.well-known/assetlinks.json').existsSync(), isTrue);
      expect(File('${root.path}/public/.well-known/apple-app-site-association').existsSync(), isFalse);
    });
  });

  group('_headers', () {
    test('gets a marked block with a JSON content type for both files', () {
      run(_loveTester());

      final headers = File('${root.path}/web_flavors/free/_headers').readAsStringSync();
      expect(headers, contains('# ann-flavor:links begin'));
      expect(headers, contains('/.well-known/assetlinks.json\n  Content-Type: application/json'));
      expect(headers, contains('/.well-known/apple-app-site-association\n  Content-Type: application/json'));
    });

    test('keeps the user\'s own rules and replaces only the marked block', () {
      File('${root.path}/web_flavors/free/_headers')
        ..createSync(recursive: true)
        ..writeAsStringSync('/assets/*\n  Cache-Control: max-age=3600\n');

      run(_loveTester());
      run(_loveTester());

      final headers = File('${root.path}/web_flavors/free/_headers').readAsStringSync();
      expect(headers, startsWith('/assets/*\n  Cache-Control: max-age=3600\n'));
      expect('# ann-flavor:links begin'.allMatches(headers), hasLength(1));
    });
  });

  group('determinism and destinations', () {
    test('a second run writes nothing and leaves identical bytes', () {
      final first = run(_loveTester());
      expect(first.written, isNotEmpty);
      final before = File('${root.path}/web_flavors/free/.well-known/assetlinks.json').readAsStringSync();

      final second = run(_loveTester());

      expect(second.written, isEmpty);
      expect(File('${root.path}/web_flavors/free/.well-known/assetlinks.json').readAsStringSync(), before);
      expect(before.endsWith('\n'), isTrue);
    });

    test('well_known_dir writes the files and headers there', () {
      run(_loveTester(destination: 'well_known_dir: build/web_site'));

      expect(File('${root.path}/build/web_site/.well-known/assetlinks.json').existsSync(), isTrue);
      expect(File('${root.path}/build/web_site/_headers').existsSync(), isTrue);
      expect(Directory('${root.path}/web_flavors').existsSync(), isFalse);
    });

    test('writes nothing when neither serve_from nor well_known_dir is set', () {
      final result = run(_loveTester(destination: '# nothing served from here'));

      expect(result.written, isEmpty);
      expect(Directory('${root.path}/web_flavors').existsSync(), isFalse);
    });

    test('an absent links: block writes nothing', () {
      final result = run('app:\n  android:\n    default:\n      id: com.example.n\n');
      expect(result.written, isEmpty);
    });
  });

  group('validation and warnings', () {
    test('an invalid block throws and writes nothing', () {
      final yaml = _loveTester().replaceFirst('/ta\n', '/en\n');
      expect(() => run(yaml), throwsA(isA<StateError>().having((e) => e.message, 'message', contains('overlaps'))));
      expect(Directory('${root.path}/web_flavors').existsSync(), isFalse);
    });

    test('warns about a catch-all rewrite in the served flavor\'s _redirects', () {
      File('${root.path}/web_flavors/free/_redirects')
        ..createSync(recursive: true)
        ..writeAsStringSync('/*  /index.html  200\n');

      final result = run(_loveTester());

      expect(result.warnings, hasLength(1));
      expect(result.warnings.single, contains('catch-all rewrite'));
    });

    test('no warning without a catch-all rewrite', () {
      File('${root.path}/web_flavors/free/_redirects')
        ..createSync(recursive: true)
        ..writeAsStringSync('# a comment\n/old  /new  301\n');

      expect(run(_loveTester()).warnings, isEmpty);
    });
  });

  group('iOS entitlements (end to end through sync)', () {
    Future<ProcessResult> sync() =>
        Process.run('dart', ['run', 'ann_flutter_flavor', 'sync', '--project', root.path], workingDirectory: _packageRoot);

    void writeIosProject() {
      final ios = Directory('${root.path}/ios')..createSync();
      File('${ios.path}/Podfile').writeAsStringSync("platform :ios, '12.0'\n\ntarget 'Runner' do\nend\n");
      Directory('${ios.path}/Flutter').createSync();
      Directory('${ios.path}/Runner').createSync();
      File('${ios.path}/Runner/Info.plist').writeAsStringSync('''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>CFBundleName</key><string>x</string></dict></plist>
''');
    }

    String iosSpec({String entitlements = ''}) => '''
enabled: true
app:
  ios:
    default:
      id: com.example.lt
      credentials:
        signing:
          team_id: ABCDE12345
$entitlements
    flavor:
      free:
        name: "Free"
        main_file: "lib/main.dart"
        version_name: "1.0.0"
        version_code: 100
      other:
        name: "Other"
        main_file: "lib/main.dart"
        version_name: "1.0.0"
        version_code: 100
        id_suffix: .other
links:
  default:
    domain: links.example.com
  flavors:
    free:
      path_prefix: /en
''';

    test('an iOS flavor with a links entry gets applinks:<domain>; one without gets nothing', () async {
      File('${root.path}/annspec.yaml').writeAsStringSync(iosSpec());
      writeIosProject();

      final result = await sync();
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');

      final free = File('${root.path}/ios/ann/Entitlements/free-release.entitlements').readAsStringSync();
      expect(free, contains('<key>com.apple.developer.associated-domains</key>'));
      expect(free, contains('<string>applinks:links.example.com</string>'));
      expect(File('${root.path}/ios/ann/Entitlements/other-release.entitlements').existsSync(), isFalse);
    });

    test('merges with a domain list the entitlements cascade already carries instead of dropping it', () async {
      File('${root.path}/annspec.yaml').writeAsStringSync(iosSpec(entitlements: '''
      entitlements:
        com.apple.developer.associated-domains:
          - webcredentials:links.example.com
        com.apple.developer.applesignin:
          - Default
'''));
      writeIosProject();

      final result = await sync();
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');

      final free = File('${root.path}/ios/ann/Entitlements/free-release.entitlements').readAsStringSync();
      expect(free, contains('<string>applinks:links.example.com</string>'));
      expect(free, contains('<string>webcredentials:links.example.com</string>'));
      expect(free, contains('<key>com.apple.developer.applesignin</key>'));
    });

    test('an invalid links block stops sync with the problem named', () async {
      File('${root.path}/annspec.yaml').writeAsStringSync(iosSpec().replaceFirst('path_prefix: /en', 'path_prefix: en'));
      writeIosProject();

      final result = await sync();

      expect(result.exitCode, isNot(0));
      expect('${result.stdout}${result.stderr}', contains('links.flavors.free.path_prefix'));
      expect(Directory('${root.path}/ios/ann').existsSync(), isFalse);
    });
  });

  group("sync-web does not leak the serving flavor's files into another flavor", () {
    Future<ProcessResult> syncWeb(String flavor) => Process.run(
        'dart', ['run', 'ann_flutter_flavor', 'sync-web', '--flavor', flavor, '--project', root.path],
        workingDirectory: _packageRoot);

    test('copies them for the serving flavor and removes them again for another one', () async {
      final spec = '''
app:
  android:
    default:
      id: com.example.lt
    flavor:
      free:
        name: "Free"
  web:
    default:
      id: com.example.lt
    flavor:
      free:
        name: "Free"
        version_name: "1.0.0"
        version_code: 100
      admin:
        name: "Admin"
        version_name: "1.0.0"
        version_code: 100
        id_suffix: .admin
links:
  serve_from: free
  default:
    domain: links.example.com
    android:
      sha256_fingerprints: ["$_f1"]
  flavors:
    free:
      path_prefix: /en
''';
      File('${root.path}/annspec.yaml').writeAsStringSync(spec);
      run(spec);
      // a rule of the other flavor's own, which must survive in the shared web/_headers
      File('${root.path}/web_flavors/admin/_headers')
        ..createSync(recursive: true)
        ..writeAsStringSync('/admin/*\n  X-Robots-Tag: noindex\n');

      var result = await syncWeb('free');
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(File('${root.path}/web/.well-known/assetlinks.json').existsSync(), isTrue);
      expect(File('${root.path}/web/_headers').readAsStringSync(), contains('ann-flavor:links begin'));

      result = await syncWeb('admin');
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(File('${root.path}/web/.well-known/assetlinks.json').existsSync(), isFalse);
      expect(Directory('${root.path}/web/.well-known').existsSync(), isFalse);
      final headers = File('${root.path}/web/_headers').readAsStringSync();
      expect(headers, isNot(contains('ann-flavor:links')));
      expect(headers, contains('X-Robots-Tag: noindex'));
    });

    test('stripHeaderBlock removes only the marked block', () {
      const text = '/a\n  X: 1\n\n# ann-flavor:links begin\n/.well-known/assetlinks.json\n'
          '  Content-Type: application/json\n# ann-flavor:links end\n/b\n  Y: 2\n';
      expect(LinksGenerator.stripHeaderBlock(text), '/a\n  X: 1\n/b\n  Y: 2\n');
      expect(LinksGenerator.stripHeaderBlock('/a\n  X: 1\n'), '/a\n  X: 1\n');
    });
  });
}
