import 'dart:io';
import 'package:path/path.dart' as p;

class IosIconGenerator {
  final String projectRoot;

  IosIconGenerator(this.projectRoot);

  Future<void> generateForFlavor(String flavorName, String sourcePath) async {
    final resolvedSource = _resolveSource(sourcePath);
    _validateSource(resolvedSource, flavorName);

    final iconSetName = _capitalize(flavorName) + 'AppIcon';
    final iconSetDir = 'ios/Runner/Assets.xcassets/$iconSetName.appiconset/';
    final tempConfig = File(p.join(projectRoot, 'flutter_launcher_icons_$flavorName.yaml'));

    tempConfig.writeAsStringSync(_buildConfig(sourcePath, iconSetDir));

    try {
      final result = await Process.run(
        'dart',
        ['run', 'flutter_launcher_icons', '-f', tempConfig.path],
        workingDirectory: projectRoot,
        runInShell: true,
      );
      if (result.exitCode != 0) {
        throw Exception(
          '[Annai] flutter_launcher_icons failed for iOS flavor "$flavorName":\n'
          '${result.stderr}\n${result.stdout}',
        );
      }
    } finally {
      if (tempConfig.existsSync()) tempConfig.deleteSync();
    }
  }

  File _resolveSource(String srcPath) {
    final candidates = [
      File(srcPath),
      File(p.join(projectRoot, srcPath)),
      File(p.join(p.dirname(projectRoot), srcPath)),
    ];
    return candidates.firstWhere(
      (f) => f.existsSync(),
      orElse: () => throw Exception(
        '[Annai] Icon source file not found: $srcPath\n'
        'Check the icon path in annspec.yaml.',
      ),
    );
  }

  void _validateSource(File file, String flavorName) {
    if (p.extension(file.path).toLowerCase() != '.png') {
      throw Exception(
        '[Annai] Icon source must be a PNG file. Got: ${p.basename(file.path)}\n'
        'Set a .png path in annspec.yaml for flavor "$flavorName".',
      );
    }

    // Read PNG IHDR to get dimensions without depending on a heavy image package.
    final bytes = file.readAsBytesSync();
    if (bytes.length < 24 || !_isPngSignature(bytes)) {
      throw Exception('[Annai] Icon source is not a valid PNG: ${file.path}');
    }
    final width  = _readInt32(bytes, 16);
    final height = _readInt32(bytes, 20);
    if (width < 1024 || height < 1024) {
      throw Exception(
        '[Annai] Icon source must be at least 1024×1024 pixels. '
        'Got ${width}×${height} for flavor "$flavorName".',
      );
    }
  }

  bool _isPngSignature(List<int> bytes) {
    const sig = [137, 80, 78, 71, 13, 10, 26, 10];
    for (var i = 0; i < sig.length; i++) {
      if (bytes[i] != sig[i]) return false;
    }
    return true;
  }

  int _readInt32(List<int> bytes, int offset) =>
      (bytes[offset] << 24) | (bytes[offset + 1] << 16) |
      (bytes[offset + 2] << 8) | bytes[offset + 3];

  String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  String _buildConfig(String sourcePath, String iconSetDir) => '''
flutter_launcher_icons:
  android: false
  ios: true
  image_path: "$sourcePath"
  ios_content_images_path: "$iconSetDir"
''';
}
