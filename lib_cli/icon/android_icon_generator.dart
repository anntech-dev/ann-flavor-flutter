import 'dart:io';
import 'package:path/path.dart' as p;

/// Generates per-flavor Android launcher icons via `flutter_launcher_icons`.
///
/// Unlike iOS, `flutter_launcher_icons` routes Android output to
/// `android/app/src/<flavor>/res/` correctly on its own, driven purely by the
/// config file's name (`flutter_launcher_icons-<flavor>.yaml`) — no
/// relocation step needed.
class AndroidIconGenerator {
  final String projectRoot;

  AndroidIconGenerator(this.projectRoot);

  Future<void> generateForFlavor(String flavorName, String sourcePath) async {
    final tempConfig = File(p.join(projectRoot, 'flutter_launcher_icons-$flavorName.yaml'));
    tempConfig.writeAsStringSync(_buildConfig(sourcePath));

    try {
      final result = await Process.run(
        Platform.resolvedExecutable,
        ['run', 'flutter_launcher_icons', '-f', tempConfig.path],
        workingDirectory: projectRoot,
      );
      if (result.exitCode != 0) {
        throw Exception(
          '[Annai] flutter_launcher_icons failed for Android flavor "$flavorName":\n'
          '${result.stderr}\n${result.stdout}',
        );
      }
    } finally {
      if (tempConfig.existsSync()) tempConfig.deleteSync();
    }
  }

  String _buildConfig(String sourcePath) => '''
flutter_launcher_icons:
  android: true
  ios: false
  image_path: "$sourcePath"
''';
}
