import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import '../lib_cli/generators/links_dart_generator.dart';
import '../lib_cli/spec/annspec_reader.dart';

// Tests read the spec through AnnspecReader: they must not import ann_flavor_core, which is not
// published (scripts/vendor-flutter-core.sh rejects it).

final _packageRoot = Directory.current.path.endsWith('/test')
    ? Directory.current.parent.path
    : Directory.current.path;

String _fp(int n) => List.generate(32, (i) => ((n * 7 + i * 13) % 256).toRadixString(16).padLeft(2, '0').toUpperCase()).join(':');

/// The Love Tester case, flavors written in reverse order on purpose (output must be sorted).
String _spec({String? links, String iosStores = '''
        stores:
          app_store:
            apple_id: "1234567890"
'''}) => '''
app:
  android:
    default:
      id: com.example.lt
    flavor:
      tamil:
        name: "Tamil"
        id_suffix: .tamil
      free:
        name: "Free"
  ios:
    default:
      id: com.example.lt
    flavor:
      free:
        name: "Free"
$iosStores
${links ?? _defaultLinks}''';

final _defaultLinks = '''
links:
  default:
    domain: links.example.com
    android:
      sha256_fingerprints: ["${_fp(1)}"]
  flavors:
    tamil:
      path_prefix: /ta
    free:
      path_prefix: /en
      also_handles: [/ta]
''';

void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('links_dart_test_'));
  tearDown(() => root.deleteSync(recursive: true));

  String? generate(String yaml) {
    File('${root.path}/annspec.yaml').writeAsStringSync(yaml);
    return LinksDartGenerator.generate(AnnspecReader.read(root.path), root.path);
  }

  File out() => File('${root.path}/lib/generated/ann_links.g.dart');

  /// Evaluates the generated file with the Dart VM, so the test sees what a real consumer sees.
  Future<Map<String, dynamic>> evaluate() async {
    File('${root.path}/check.dart').writeAsStringSync("""
import 'dart:convert';
import 'lib/generated/ann_links.g.dart';

void main() => print(jsonEncode(annLinks));
""");
    final r = await Process.run('dart', ['run', '${root.path}/check.dart'], workingDirectory: _packageRoot);
    expect(r.exitCode, 0, reason: '${r.stdout}\n${r.stderr}');
    return jsonDecode(r.stdout.toString().trim()) as Map<String, dynamic>;
  }

  group('content', () {
    test('holds every linked flavor with its facts (the Love Tester case)', () async {
      expect(generate(_spec()), 'lib/generated/ann_links.g.dart');

      expect(await evaluate(), {
        'flavors': {
          'free': {
            'domain': 'links.example.com',
            'pathPrefix': '/en',
            'alsoHandles': ['/ta'],
            'platforms': ['android', 'ios'],
            'androidId': 'com.example.lt',
            'iosBundleId': 'com.example.lt',
            'appleId': '1234567890',
          },
          'tamil': {
            'domain': 'links.example.com',
            'pathPrefix': '/ta',
            'alsoHandles': <String>[],
            'platforms': ['android'],
            'androidId': 'com.example.lt.tamil',
          },
        },
      });
    });

    test('an Android-only flavor has no iosBundleId or appleId, and absent values are omitted, not null', () async {
      generate(_spec());

      final tamil = ((await evaluate())['flavors'] as Map)['tamil'] as Map;
      expect(tamil.containsKey('iosBundleId'), isFalse);
      expect(tamil.containsKey('appleId'), isFalse);
      expect(out().readAsStringSync(), isNot(contains('null')));
    });

    test('appleId is omitted when the iOS flavor has no App Store id', () async {
      generate(_spec(iosStores: ''));

      final free = ((await evaluate())['flavors'] as Map)['free'] as Map;
      expect(free.containsKey('appleId'), isFalse);
      expect(free['iosBundleId'], 'com.example.lt');
    });

    test('does not carry fingerprints or the Team ID', () {
      generate(_spec());
      final text = out().readAsStringSync();

      expect(text, isNot(contains(_fp(1))));
      expect(text.toLowerCase(), isNot(contains('team')));
      expect(text.toLowerCase(), isNot(contains('sha256')));
    });

    test('flavors are sorted by key whatever the order in annspec.yaml', () async {
      generate(_spec());

      expect(((await evaluate())['flavors'] as Map).keys.toList(), ['free', 'tamil']);
    });
  });

  group('when it is written', () {
    test('nothing without a links: block', () {
      final written = generate('app:\n  android:\n    default:\n      id: com.example.n\n');

      expect(written, isNull);
      expect(out().existsSync(), isFalse);
    });

    test('an invalid block throws and writes nothing', () {
      final bad = _defaultLinks.replaceFirst('/ta\n', '/en\n');

      expect(() => generate(_spec(links: bad)), throwsA(isA<StateError>().having((e) => e.message, 'message', contains('overlaps'))));
      expect(out().existsSync(), isFalse);
    });

    test('a second run writes nothing and leaves identical bytes', () {
      expect(generate(_spec()), isNotNull);
      final first = out().readAsStringSync();
      final modified = out().lastModifiedSync();

      expect(generate(_spec()), isNull);
      expect(out().readAsStringSync(), first);
      expect(out().lastModifiedSync(), modified);
    });

    test('a changed block rewrites the file', () {
      generate(_spec());

      expect(generate(_spec(links: _defaultLinks.replaceFirst('links.example.com', 'other.example.com'))), isNotNull);
      expect(out().readAsStringSync(), contains('other.example.com'));
    });

    test('removing the block leaves an earlier file in place', () {
      generate(_spec());

      expect(generate('app:\n  android:\n    default:\n      id: com.example.n\n'), isNull);
      expect(out().existsSync(), isTrue);
    });
  });

  group('quoting', () {
    test("escapes backslash, single quote, dollar and line breaks so any value is valid Dart", () {
      expect(LinksDartGenerator.quote(r"it's $x \ y"), r"'it\'s \$x \\ y'");
      expect(LinksDartGenerator.quote('a\nb'), r"'a\nb'");
      expect(LinksDartGenerator.quote('plain'), "'plain'");
    });
  });

  group('sync (end to end)', () {
    test('writes the file in the Dart step', () async {
      File('${root.path}/annspec.yaml').writeAsStringSync('''
enabled: true
app:
  android:
    default:
      id: com.example.lt
    flavor:
      free:
        name: "Free"
        main_file: "lib/main.dart"
        version_name: "1.0.0"
        version_code: 100
links:
  default:
    domain: links.example.com
    android:
      sha256_fingerprints: ["${_fp(1)}"]
  flavors:
    free:
      path_prefix: /en
''');
      final android = Directory('${root.path}/android')..createSync();
      File('${android.path}/settings.gradle.kts').writeAsStringSync('pluginManagement { }\nplugins { }\n');
      Directory('${android.path}/app').createSync();
      File('${android.path}/app/build.gradle.kts').writeAsStringSync('plugins { }\n');

      final r = await Process.run('dart', ['run', 'ann_flutter_flavor', 'sync', '--project', root.path], workingDirectory: _packageRoot);

      expect('${r.stdout}', contains('Generated lib/generated/ann_links.g.dart'));
      expect(out().existsSync(), isTrue);
      expect(out().readAsStringSync(), contains("'pathPrefix': '/en'"));
    });
  });
}
