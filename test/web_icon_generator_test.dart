import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import '../lib_cli/icon/web_icon_generator.dart';

/// Stands in for `dart run flutter_launcher_icons`: does what the real package
/// does to web/ — replaces favicon.png, writes web/icons/*, rewrites manifest.json.
FlutterLauncherIconsRunner fakeLauncherIcons({
  int exitCode = 0,
  void Function(String webDir)? inspect,
  bool writeIcons = true,
}) {
  return (args, cwd) async {
    final web = p.join(cwd, 'web');
    inspect?.call(web);
    if (writeIcons) {
      Directory(p.join(web, 'icons')).createSync(recursive: true);
      for (final n in [
        'Icon-192.png',
        'Icon-512.png',
        'Icon-maskable-192.png',
        'Icon-maskable-512.png'
      ]) {
        File(p.join(web, 'icons', n)).writeAsStringSync('generated $n');
      }
      File(p.join(web, 'favicon.png')).writeAsStringSync('generated favicon');
      File(p.join(web, 'manifest.json'))
          .writeAsStringSync('{"theme_color":"#ffffff"}');
    }
    return ProcessResult(0, exitCode, '', exitCode == 0 ? '' : 'boom');
  };
}

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('ann_web_icon_test_'));
  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  void writeApp() {
    File(p.join(root.path, 'web', 'index.html')).createSync(recursive: true);
    File(p.join(root.path, 'web', 'index.html'))
        .writeAsStringSync('<html>mine</html>');
    File(p.join(root.path, 'web', 'favicon.png'))
        .writeAsStringSync('my favicon');
    File(p.join(root.path, 'web', 'manifest.json'))
        .writeAsStringSync('{"theme_color":"#0175C2"}');
    File(p.join(root.path, 'web', 'icons', 'Icon-192.png'))
        .createSync(recursive: true);
    File(p.join(root.path, 'web', 'icons', 'Icon-192.png'))
        .writeAsStringSync('my icon');
    File(p.join(root.path, 'web', 'assets', 'logo.svg'))
        .createSync(recursive: true);
    File(p.join(root.path, 'web', 'assets', 'logo.svg'))
        .writeAsStringSync('<svg/>');
  }

  Map<String, String> snapshot(String dir) {
    final out = <String, String>{};
    final d = Directory(p.join(root.path, dir));
    if (!d.existsSync()) return out;
    for (final e in d.listSync(recursive: true)) {
      if (e is File)
        out[p.relative(e.path, from: root.path)] = e.readAsStringSync();
    }
    return out;
  }

  test('moves the generated icons into web_flavors/<flavor>/icons', () async {
    writeApp();
    await WebIconGenerator(root.path, runner: fakeLauncherIcons())
        .generateForFlavor('pro', 'assets/icon.png');

    final out = snapshot('web_flavors/pro/icons');
    expect(out.keys.map(p.basename).toSet(), {
      'Icon-192.png',
      'Icon-512.png',
      'Icon-maskable-192.png',
      'Icon-maskable-512.png'
    });
    expect(out['web_flavors/pro/icons/Icon-512.png'], 'generated Icon-512.png');
  });

  test('leaves the real web/ folder exactly as it was', () async {
    writeApp();
    final before = snapshot('web');

    await WebIconGenerator(root.path, runner: fakeLauncherIcons())
        .generateForFlavor('pro', 'assets/icon.png');

    expect(snapshot('web'), before);
    expect(
        Directory(p.join(root.path, WebIconGenerator.backupFolderName))
            .existsSync(),
        isFalse);
  });

  test(
      'flutter_launcher_icons sees a throwaway web/ with index.html and manifest.json only',
      () async {
    writeApp();
    late Map<String, String> seen;
    await WebIconGenerator(root.path, runner: fakeLauncherIcons(inspect: (web) {
      seen = {
        for (final e in Directory(web).listSync(recursive: true))
          if (e is File) p.relative(e.path, from: web): e.readAsStringSync(),
      };
    })).generateForFlavor('pro', 'assets/icon.png');

    expect(seen, {'index.html': '', 'manifest.json': '{}'});
  });

  test('restores web/ and removes the config when flutter_launcher_icons fails',
      () async {
    writeApp();
    final before = snapshot('web');

    await expectLater(
      WebIconGenerator(root.path, runner: fakeLauncherIcons(exitCode: 1))
          .generateForFlavor('pro', 'assets/icon.png'),
      throwsA(isA<Exception>()
          .having((e) => e.toString(), 'message', contains('boom'))),
    );

    expect(snapshot('web'), before);
    expect(
        Directory(p.join(root.path, WebIconGenerator.backupFolderName))
            .existsSync(),
        isFalse);
    expect(
        File(p.join(root.path, 'flutter_launcher_icons_web_pro.yaml'))
            .existsSync(),
        isFalse);
  });

  test('restores web/ when flutter_launcher_icons throws', () async {
    writeApp();
    final before = snapshot('web');
    Future<ProcessResult> thrower(List<String> a, String c) async =>
        throw StateError('crash');

    await expectLater(
      WebIconGenerator(root.path, runner: thrower)
          .generateForFlavor('pro', 'assets/icon.png'),
      throwsA(isA<StateError>()),
    );
    expect(snapshot('web'), before);
  });

  test('restores web/ and fails clearly when no icons were produced', () async {
    writeApp();
    final before = snapshot('web');

    await expectLater(
      WebIconGenerator(root.path, runner: fakeLauncherIcons(writeIcons: false))
          .generateForFlavor('pro', 'assets/icon.png'),
      throwsA(isA<Exception>().having((e) => e.toString(), 'message',
          contains('did not produce web/icons'))),
    );
    expect(snapshot('web'), before);
  });

  test(
      'refuses to run while a web.ann-backup folder exists and touches nothing',
      () async {
    writeApp();
    Directory(p.join(root.path, WebIconGenerator.backupFolderName))
        .createSync();
    File(p.join(root.path, WebIconGenerator.backupFolderName, 'index.html'))
        .writeAsStringSync('original');
    final web = snapshot('web');
    final backup = snapshot(WebIconGenerator.backupFolderName);
    var ran = false;

    await expectLater(
      WebIconGenerator(root.path, runner: (a, c) async {
        ran = true;
        return ProcessResult(0, 0, '', '');
      }).generateForFlavor('pro', 'assets/icon.png'),
      throwsA(isA<Exception>().having((e) => e.toString(), 'message',
          contains('previous icon run was interrupted'))),
    );

    expect(ran, isFalse);
    expect(snapshot('web'), web);
    expect(snapshot(WebIconGenerator.backupFolderName), backup);
  });

  test('works when the project has no web/ folder and leaves none behind',
      () async {
    await WebIconGenerator(root.path, runner: fakeLauncherIcons())
        .generateForFlavor('pro', 'assets/icon.png');

    expect(snapshot('web_flavors/pro/icons'), isNotEmpty);
    expect(Directory(p.join(root.path, 'web')).existsSync(), isFalse);
    expect(
        Directory(p.join(root.path, WebIconGenerator.backupFolderName))
            .existsSync(),
        isFalse);
  });

  test('regenerating replaces the previous icons for that flavor only',
      () async {
    writeApp();
    File(p.join(root.path, 'web_flavors', 'pro', 'icons', 'stale.png'))
        .createSync(recursive: true);
    File(p.join(root.path, 'web_flavors', 'free', 'icons', 'keep.png'))
        .createSync(recursive: true);

    await WebIconGenerator(root.path, runner: fakeLauncherIcons())
        .generateForFlavor('pro', 'assets/icon.png');

    expect(
        File(p.join(root.path, 'web_flavors', 'pro', 'icons', 'stale.png'))
            .existsSync(),
        isFalse);
    expect(
        File(p.join(root.path, 'web_flavors', 'free', 'icons', 'keep.png'))
            .existsSync(),
        isTrue);
  });
}
