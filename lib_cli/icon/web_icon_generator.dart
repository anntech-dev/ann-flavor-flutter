import 'dart:io';

class WebIconGenerator {
  final String projectRoot;
  WebIconGenerator(this.projectRoot);

  Directory get _stockIconsDir => Directory('$projectRoot/web/icons');

  /// Generates PWA icon sizes for [flavorKey] from source [iconPath].
  /// Output: web_flavors/<flavorKey>/icons/{icon-192,icon-512,icon-192-maskable,icon-512-maskable}.png
  ///
  /// `flutter_launcher_icons` hardcodes its web output to `web/icons/` —
  /// there is no config key to redirect it. Its result is moved (not
  /// copied) into web_flavors/<flavorKey>/icons/ and web/icons/ is left
  /// clean afterward, so this never leaves generated files behind in web/.
  Future<void> generateForFlavor(String flavorKey, String iconPath) async {
    final iconsDir = Directory('$projectRoot/web_flavors/$flavorKey/icons');

    // Deliberately NOT flutter_launcher_icons-<name>.yaml: that hyphenated
    // pattern is flutter_launcher_icons' own flavor-autodetect convention
    // (getFlavors() in its main.dart globs the working directory for
    // ^flutter_launcher_icons-(.*)\.yaml$ and, if ANY match exists, silently
    // ignores the -f flag and runs flavor mode for every match found — so a
    // leftover/concurrent web config here could hijack an unrelated iOS or
    // Android run in the same directory).
    final configFile =
        File('$projectRoot/flutter_launcher_icons_web_$flavorKey.yaml');
    configFile.writeAsStringSync(_config(iconPath));

    try {
      final result = await Process.run(
        Platform.executable,
        ['run', 'flutter_launcher_icons', '-f', configFile.path],
        workingDirectory: projectRoot,
      );
      if (result.exitCode != 0) {
        throw Exception('flutter_launcher_icons failed:\n${result.stderr}');
      }
      if (!_stockIconsDir.existsSync()) {
        throw Exception(
          '[Annai] flutter_launcher_icons did not produce '
          '${_stockIconsDir.path} for web flavor "$flavorKey".',
        );
      }
      if (iconsDir.existsSync()) iconsDir.deleteSync(recursive: true);
      iconsDir.createSync(recursive: true);
      for (final f in _stockIconsDir.listSync()) {
        if (f is File) f.copySync('${iconsDir.path}/${f.uri.pathSegments.last}');
      }
      _stockIconsDir.deleteSync(recursive: true);
    } finally {
      if (configFile.existsSync()) configFile.deleteSync();
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
