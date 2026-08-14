import 'dart:io';

class WebIconGenerator {
  final String projectRoot;
  WebIconGenerator(this.projectRoot);

  /// Generates PWA icon sizes for [flavorKey] from source [iconPath].
  /// Output: web_flavors/<flavorKey>/icons/{icon-192,icon-512,icon-192-maskable,icon-512-maskable}.png
  Future<void> generateForFlavor(String flavorKey, String iconPath) async {
    final iconsDir = Directory('$projectRoot/web_flavors/$flavorKey/icons');
    iconsDir.createSync(recursive: true);

    final configFile =
        File('$projectRoot/flutter_launcher_icons-web-$flavorKey.yaml');
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
      // flutter_launcher_icons writes web icons to web/icons/ by default — copy to web_flavors/
      final src = Directory('$projectRoot/web/icons');
      if (src.existsSync()) {
        for (final f in src.listSync()) {
          if (f is File) f.copySync('${iconsDir.path}/${f.uri.pathSegments.last}');
        }
      }
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
