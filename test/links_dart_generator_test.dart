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

  /// Runs [body] (Dart statements ending in `return <jsonable>;`) against the generated file.
  Future<Object?> run(String body) async {
    File('${root.path}/check.dart').writeAsStringSync("""
import 'dart:convert';
import 'lib/generated/ann_links.g.dart';

Object? probe() {
$body
}

void main() => print(jsonEncode(probe()));
""");
    final r = await Process.run('dart', ['run', '${root.path}/check.dart'], workingDirectory: _packageRoot);
    expect(r.exitCode, 0, reason: '${r.stdout}\n${r.stderr}');
    return jsonDecode(r.stdout.toString().trim());
  }

  group('typed layer (REQ-LINK-00140 → 00190)', () {
    setUp(() => generate(_spec()));

    test('the enum has one value per flavor, sorted, and annLinkFlavors agrees with annLinks', () async {
      expect(await run(r'''
  return {
    'keys': AnnLinkFlavorKey.values.map((k) => k.name).toList(),
    'agree': annLinkFlavors.entries.every((e) {
      final m = (annLinks['flavors'] as Map)[e.key.name] as Map;
      final f = e.value;
      return m['domain'] == f.domain && m['pathPrefix'] == f.pathPrefix &&
          m['androidId'] == f.androidId && m['iosBundleId'] == f.iosBundleId && m['appleId'] == f.appleId &&
          '${m['alsoHandles']}' == '${f.alsoHandles}' && '${m['platforms']}' == '${f.platforms}';
    }),
    'count': annLinkFlavors.length,
  };
'''), {'keys': ['free', 'tamil'], 'agree': true, 'count': 2});
    });

    test('fields, origin, uri and existsOn', () async {
      expect(await run('''
  final free = linkFlavorFor(AnnLinkFlavorKey.free);
  final tamil = linkFlavorFor(AnnLinkFlavorKey.tamil);
  return {
    'key': free.key.name,
    'domain': free.domain,
    'origin': free.origin,
    'uri': free.uri('/result/42').toString(),
    'uriBare': free.uri().toString(),
    'uriNoSlash': free.uri('result').toString(),
    'freeIos': free.existsOn('ios'),
    'tamilIos': tamil.existsOn('ios'),
    'tamilAndroid': tamil.existsOn('android'),
    'tamilIosBundle': tamil.iosBundleId,
    'tamilApple': tamil.appleId,
    'freeApple': free.appleId,
  };
'''), {
        'key': 'free',
        'domain': 'links.example.com',
        'origin': 'https://links.example.com',
        'uri': 'https://links.example.com/en/result/42',
        'uriBare': 'https://links.example.com/en',
        'uriNoSlash': 'https://links.example.com/en/result',
        'freeIos': true,
        'tamilIos': false,
        'tamilAndroid': true,
        'tamilIosBundle': null,
        'tamilApple': null,
        'freeApple': '1234567890',
      });
    });

    test('linkFlavorOwning matches at segment boundaries and ignores query, fragment and a trailing slash', () async {
      expect(await run('''
  String? o(String p) => linkFlavorOwning(p)?.key.name;
  return {
    'en': o('/en'), 'enX': o('/en/x'), 'enSlash': o('/en/'), 'enQuery': o('/en?a=1'), 'enFrag': o('/en/x#top'),
    'ta': o('/ta/quiz'), 'entry': o('/entry'), 'none': o('/other'), 'root': o('/'), 'empty': o(''), 'upper': o('/EN'),
  };
'''), {
        'en': 'free', 'enX': 'free', 'enSlash': 'free', 'enQuery': 'free', 'enFrag': 'free',
        'ta': 'tamil', 'entry': null, 'none': null, 'root': null, 'empty': null, 'upper': null,
      });
    });

    test('handlesPath honours alsoHandles, linkFlavorOwning does not', () async {
      expect(await run('''
  final free = linkFlavorFor(AnnLinkFlavorKey.free);
  final tamil = linkFlavorFor(AnnLinkFlavorKey.tamil);
  return {
    'freeTa': free.handlesPath('/ta/quiz'),
    'freeEn': free.handlesPath('/en/x'),
    'freeOther': free.handlesPath('/other'),
    'tamilEn': tamil.handlesPath('/en/x'),
    'tamilTa': tamil.handlesPath('/ta'),
    'freeTaEntry': free.handlesPath('/tax'),
    'owner': linkFlavorOwning('/ta/quiz')?.key.name,
  };
'''), {'freeTa': true, 'freeEn': true, 'freeOther': false, 'tamilEn': false, 'tamilTa': true, 'freeTaEntry': false, 'owner': 'tamil'});
    });

    test('linkFlavorOwningUri needs https and the links domain (host compared in lower case)', () async {
      expect(await run('''
  String? o(String u) => linkFlavorOwningUri(Uri.parse(u))?.key.name;
  return {
    'ok': o('https://links.example.com/ta/x'),
    'upperHost': o('https://LINKS.example.com/en'),
    'http': o('http://links.example.com/en'),
    'otherHost': o('https://evil.example.com/en'),
    'noPath': o('https://links.example.com'),
    'custom': o('myapp://links.example.com/en'),
  };
'''), {'ok': 'tamil', 'upperHost': 'free', 'http': null, 'otherHost': null, 'noPath': null, 'custom': null});
    });

    test('linkFlavorByApplicationId finds by Android id or iOS bundle id', () async {
      expect(await run('''
  return {
    'free': linkFlavorByApplicationId('com.example.lt')?.key.name,
    'tamil': linkFlavorByApplicationId('com.example.lt.tamil')?.key.name,
    'none': linkFlavorByApplicationId('com.other')?.key.name,
  };
'''), {'free': 'free', 'tamil': 'tamil', 'none': null});
    });

    test('the longest prefix wins when prefixes are nested (only possible across domains: the spec rejects it on one)', () async {
      generate(_spec(links: '''
links:
  flavors:
    free:
      domain: a.example.com
      path_prefix: /l
      android:
        sha256_fingerprints: ["${_fp(1)}"]
    tamil:
      domain: b.example.com
      path_prefix: /l/ta
      android:
        sha256_fingerprints: ["${_fp(2)}"]
'''));
      expect(await run("  return {'a': linkFlavorOwning('/l/ta/x')?.key.name, 'b': linkFlavorOwning('/l/x')?.key.name, 'c': linkFlavorOwning('/l/tax')?.key.name};"),
          {'a': 'tamil', 'b': 'free', 'c': 'free'});
    });

    test('flavors on different domains: linkFlavorOwningUri tells them apart', () async {
      generate(_spec(links: '''
links:
  flavors:
    free:
      domain: a.example.com
      path_prefix: /go
      android:
        sha256_fingerprints: ["${_fp(1)}"]
    tamil:
      domain: b.example.com
      path_prefix: /go
      android:
        sha256_fingerprints: ["${_fp(2)}"]
'''));
      expect(await run('''
  return {
    'a': linkFlavorOwningUri(Uri.parse('https://a.example.com/go/x'))?.key.name,
    'b': linkFlavorOwningUri(Uri.parse('https://b.example.com/go/x'))?.key.name,
  };
'''), {'a': 'free', 'b': 'tamil'});
    });

    test('a flavor name with a dash still gives a valid enum value', () async {
      File('${root.path}/annspec.yaml').writeAsStringSync('''
app:
  android:
    default:
      id: com.example.lt
    flavor:
      my-app:
        name: "My"
links:
  default:
    domain: links.example.com
    android:
      sha256_fingerprints: ["${_fp(1)}"]
  flavors:
    my-app:
      path_prefix: /my
''');
      LinksDartGenerator.generate(AnnspecReader.read(root.path), root.path);
      expect(await run("  return AnnLinkFlavorKey.values.map((k) => k.name).toList();"), ['myApp']);
    });

    test('the output passes dart analyze with no issue', () async {
      final r = await Process.run('dart', ['analyze', '--fatal-infos', out().path], workingDirectory: _packageRoot);
      expect(r.exitCode, 0, reason: '${r.stdout}\n${r.stderr}');
    });

    test('a second run writes nothing and leaves identical bytes', () {
      final before = out().readAsStringSync();
      expect(LinksDartGenerator.generate(AnnspecReader.read(root.path), root.path), isNull);
      expect(out().readAsStringSync(), before);
    });
  });

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
      final text = out().readAsStringSync();
      expect(text.substring(0, text.indexOf('// ── Typed layer')), isNot(contains('null')));
      expect(text, isNot(contains("iosBundleId: 'null")));
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
