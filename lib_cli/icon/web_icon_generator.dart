import 'dart:io';
import 'package:path/path.dart' as p;

/// Runs `dart run flutter_launcher_icons -f <config>` in the project root.
typedef FlutterLauncherIconsRunner = Future<ProcessResult> Function(
  List<String> arguments,
  String workingDirectory,
);

Future<ProcessResult> _defaultRunner(
        List<String> arguments, String workingDirectory) =>
    Process.run(Platform.executable, arguments,
        workingDirectory: workingDirectory);

class WebIconGenerator {
  final String projectRoot;
  final FlutterLauncherIconsRunner _run;

  WebIconGenerator(this.projectRoot, {FlutterLauncherIconsRunner? runner})
      : _run = runner ?? _defaultRunner;

  /// Where the real web/ folder waits while flutter_launcher_icons works on a
  /// throwaway one.
  static const backupFolderName = 'web.ann-backup';

  Directory get _webDir => Directory(p.join(projectRoot, 'web'));
  Directory get _backupDir => Directory(p.join(projectRoot, backupFolderName));

  /// Generates PWA icon sizes for [flavorKey] from source [iconPath].
  /// Output: web_flavors/<flavorKey>/icons/{Icon-192,Icon-512,Icon-maskable-192,Icon-maskable-512}.png
  ///
  /// `flutter_launcher_icons` hardcodes its web output to `web/` — it writes
  /// `web/icons/`, replaces `web/favicon.png` and rewrites `web/manifest.json`,
  /// and requires `web/index.html` and `web/manifest.json` to exist. To keep
  /// the app's own `web/` untouched, the real folder is renamed to
  /// [backupFolderName] (a same-disk rename: nothing is copied or opened for
  /// writing), a throwaway `web/` holding just those two files is used for the
  /// run, the icons are moved into web_flavors/<flavorKey>/icons/, and the real
  /// folder is renamed back in a `finally`.
  Future<void> generateForFlavor(String flavorKey, String iconPath) async {
    if (_backupDir.existsSync()) {
      throw Exception(
        '[Annai] $backupFolderName/ already exists in $projectRoot — a previous '
        'icon run was interrupted. Your original web folder is inside it. '
        'Delete the throwaway web/ folder if it is there, rename '
        '$backupFolderName to web, then run generate-icons again.',
      );
    }

    final hadWeb = _webDir.existsSync();
    final iconsDir =
        Directory(p.join(projectRoot, 'web_flavors', flavorKey, 'icons'));

    // Deliberately NOT flutter_launcher_icons-<name>.yaml: that hyphenated
    // pattern is flutter_launcher_icons' own flavor-autodetect convention
    // (getFlavors() in its main.dart globs the working directory for
    // ^flutter_launcher_icons-(.*)\.yaml$ and, if ANY match exists, silently
    // ignores the -f flag and runs flavor mode for every match found — so a
    // leftover/concurrent web config here could hijack an unrelated iOS or
    // Android run in the same directory).
    final configFile =
        File(p.join(projectRoot, 'flutter_launcher_icons_web_$flavorKey.yaml'));

    if (hadWeb) _webDir.renameSync(_backupDir.path);
    try {
      _webDir.createSync(recursive: true);
      File(p.join(_webDir.path, 'index.html')).writeAsStringSync('');
      File(p.join(_webDir.path, 'manifest.json')).writeAsStringSync('{}');

      configFile.writeAsStringSync(_config(iconPath));
      final result = await _run(
        ['run', 'flutter_launcher_icons', '-f', configFile.path],
        projectRoot,
      );
      if (result.exitCode != 0) {
        throw Exception('flutter_launcher_icons failed:\n${result.stderr}');
      }
      final producedIcons = Directory(p.join(_webDir.path, 'icons'));
      if (!producedIcons.existsSync()) {
        throw Exception(
          '[Annai] flutter_launcher_icons did not produce web/icons for web '
          'flavor "$flavorKey".',
        );
      }
      if (iconsDir.existsSync()) iconsDir.deleteSync(recursive: true);
      iconsDir.createSync(recursive: true);
      for (final f in producedIcons.listSync()) {
        if (f is File) f.copySync(p.join(iconsDir.path, p.basename(f.path)));
      }
    } finally {
      try {
        if (configFile.existsSync()) configFile.deleteSync();
      } finally {
        if (_webDir.existsSync()) _webDir.deleteSync(recursive: true);
        if (hadWeb && _backupDir.existsSync())
          _backupDir.renameSync(_webDir.path);
      }
    }
  }

  String _config(String iconPath) => '''
flutter_icons:
  image_path: "$iconPath"
  web:
    generate: true
    image_path: "$iconPath"
    background_color: "#ffffff"
    theme_color: "#ffffff"
''';
}
