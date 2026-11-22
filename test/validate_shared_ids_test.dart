import 'dart:io';
import 'package:test/test.dart';

final _packageRoot = Directory.current.path.endsWith('/test')
    ? Directory.current.parent.path
    : Directory.current.path;

Future<String> _validate(Directory dir) async {
  final r = await Process.run('dart', ['run', 'ann_flutter_flavor', 'validate', '--project', dir.path],
      workingDirectory: _packageRoot);
  return '${r.stdout}${r.stderr}';
}

String _flavor(String name, {String extra = ''}) => '''
      $name:
        name: "$name"
        main_file: "lib/main_$name.dart"
        version_name: "1.0.0"
        version_code: 100
$extra''';

String _spec(String android, {String ios = ''}) => '''
enabled: true
app:
  android:
    default:
      id: com.example.app
    flavor:
$android${ios.isEmpty ? '' : '''
  ios:
    default:
      id: com.example.app
    flavor:
$ios'''}
''';

bool _hasSharedIdWarning(String out) => out.contains('resolves to the same application ID');

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('validate_ids_'));
  tearDown(() => dir.deleteSync(recursive: true));

  void write(String yaml) => File('${dir.path}/annspec.yaml').writeAsStringSync(yaml);

  test('a flavor on the default ID is fine when no other flavor ends up with the same ID (Love Tester)', () async {
    write(_spec(_flavor('free') + _flavor('tamil', extra: '        id_suffix: .tamil\n')));
    final out = await _validate(dir);

    expect(out, contains('annspec.yaml is valid'));
    expect(out, isNot(contains('Neither "id" nor "id_suffix"')));
    expect(_hasSharedIdWarning(out), isFalse, reason: out);
  });

  test('a single flavor with no id_suffix is fine', () async {
    write(_spec(_flavor('only')));
    expect(_hasSharedIdWarning(await _validate(dir)), isFalse);
  });

  test('two flavors that both use the default ID get a warning naming both', () async {
    write(_spec(_flavor('free') + _flavor('paid')));
    final out = await _validate(dir);

    expect(_hasSharedIdWarning(out), isTrue, reason: out);
    expect(out, contains('app.android.flavor.paid'));
    expect(out, contains('same application ID as flavor "free"'));
    expect(out, contains('"com.example.app"'));
  });

  test('two flavors with the same id_suffix collide too', () async {
    write(_spec(_flavor('a', extra: '        id_suffix: .x\n') + _flavor('b', extra: '        id_suffix: .x\n')));
    final out = await _validate(dir);

    expect(_hasSharedIdWarning(out), isTrue, reason: out);
    expect(out, contains('"com.example.app.x"'));
  });

  test('a collision is reported once per pair, not once per build type', () async {
    write(_spec(_flavor('free') + _flavor('paid')));
    final out = await _validate(dir);

    expect(RegExp('resolves to the same application ID').allMatches(out), hasLength(1), reason: out);
  });

  test('the iOS section is checked on its own', () async {
    write(_spec(_flavor('free') + _flavor('tamil', extra: '        id_suffix: .tamil\n'),
        ios: _flavor('free') + _flavor('paid')));
    final out = await _validate(dir);

    expect(out, contains('app.ios.flavor.paid'));
    expect(out, isNot(contains('app.android.flavor')));
  });

  test('"id" together with "id_suffix" is still an error', () async {
    write(_spec(_flavor('free', extra: '        id: com.example.other\n        id_suffix: .x\n')));
    final out = await _validate(dir);

    expect(out, contains('Both "id" and "id_suffix" are set'));
  });
}
