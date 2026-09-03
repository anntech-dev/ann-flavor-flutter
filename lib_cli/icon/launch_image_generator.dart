import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;

/// Generates a per-flavor `<Flavor>LaunchImage.imageset` into
/// `ios/ann/Assets.xcassets/` (the same tool-owned catalog used for app
/// icons — plan 035 Solution §6), and patches the stock, shared, unmodified
/// `LaunchScreen.storyboard`'s image reference to point at it.
///
/// Unlike app icons, a launch image doesn't need `flutter_launcher_icons`'s
/// many-fixed-pixel-size treatment — `flutter_launcher_icons` has no code
/// path for generating anything other than its hardcoded AppIcon size table,
/// so the same source image is copied as-is into the imageset's @1x/@2x/@3x
/// slots, matching Flutter's own stock `LaunchImage.imageset` shape exactly.
class LaunchImageGenerator {
  final String projectRoot;

  LaunchImageGenerator(this.projectRoot);

  Future<void> generateForFlavor(String flavorName, String sourcePath) async {
    final resolvedSource = _resolveSource(sourcePath);
    _validateSource(resolvedSource, flavorName);

    final imageSetName = '${_capitalize(flavorName)}LaunchImage';
    final imageSetDir = Directory(
      p.join(projectRoot, 'ios', 'ann', 'Assets.xcassets', '$imageSetName.imageset'),
    );
    if (imageSetDir.existsSync()) imageSetDir.deleteSync(recursive: true);
    imageSetDir.createSync(recursive: true);

    final bytes = resolvedSource.readAsBytesSync();
    File(p.join(imageSetDir.path, 'LaunchImage.png')).writeAsBytesSync(bytes);
    File(p.join(imageSetDir.path, 'LaunchImage@2x.png')).writeAsBytesSync(bytes);
    File(p.join(imageSetDir.path, 'LaunchImage@3x.png')).writeAsBytesSync(bytes);
    File(p.join(imageSetDir.path, 'Contents.json')).writeAsStringSync(_contentsJson());

    _patchStoryboardReference(imageSetName);
  }

  String _contentsJson() => const JsonEncoder.withIndent('  ').convert({
        'images': [
          {'idiom': 'universal', 'filename': 'LaunchImage.png', 'scale': '1x'},
          {'idiom': 'universal', 'filename': 'LaunchImage@2x.png', 'scale': '2x'},
          {'idiom': 'universal', 'filename': 'LaunchImage@3x.png', 'scale': '3x'},
        ],
        'info': {'version': 1, 'author': 'xcode'},
      });

  /// Patches the stock, shared `LaunchScreen.storyboard`'s image reference
  /// from whatever name it currently uses to `<Flavor>LaunchImage`, for the
  /// flavor just generated. The storyboard itself is never duplicated or
  /// otherwise templated (plan 035 Solution §6 step 1) — only its single
  /// `image="..."` attribute and matching `<image name="...">` resource
  /// declaration are rewritten, each time this is run for a given flavor.
  void _patchStoryboardReference(String imageSetName) {
    final storyboardFile = _findStoryboard();
    if (storyboardFile == null) {
      print('  ⚠ ios/Runner/**/LaunchScreen.storyboard not found — skipping storyboard patch.');
      return;
    }

    var content = storyboardFile.readAsStringSync();
    final currentName = _currentImageName(content);
    if (currentName == null) {
      print('  ⚠ Could not find an image reference in LaunchScreen.storyboard — skipping patch.');
      return;
    }
    if (currentName == imageSetName) {
      print('  ✓ LaunchScreen.storyboard already references $imageSetName.');
      return;
    }

    content = content
        .replaceAll('image="$currentName"', 'image="$imageSetName"')
        .replaceAll('<image name="$currentName"', '<image name="$imageSetName"');
    storyboardFile.writeAsStringSync(content);
    print('  ✓ Patched LaunchScreen.storyboard: $currentName → $imageSetName');
  }

  static final _imageAttrPattern = RegExp(r'<imageView\b[^>]*\bimage="([^"]+)"');

  String? _currentImageName(String content) => _imageAttrPattern.firstMatch(content)?.group(1);

  File? _findStoryboard() {
    final candidates = [
      File(p.join(projectRoot, 'ios', 'Runner', 'Base.lproj', 'LaunchScreen.storyboard')),
      File(p.join(projectRoot, 'ios', 'Runner', 'LaunchScreen.storyboard')),
    ];
    for (final f in candidates) {
      if (f.existsSync()) return f;
    }
    return null;
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
        '[Annai] Launch image source file not found: $srcPath\n'
        'Check the launch_image path in annspec.yaml.',
      ),
    );
  }

  void _validateSource(File file, String flavorName) {
    if (p.extension(file.path).toLowerCase() != '.png') {
      throw Exception(
        '[Annai] Launch image source must be a PNG file. Got: ${p.basename(file.path)}\n'
        'Set a .png path in annspec.yaml for flavor "$flavorName".',
      );
    }
    final bytes = file.readAsBytesSync();
    if (bytes.length < 8 || !_isPngSignature(bytes)) {
      throw Exception('[Annai] Launch image source is not a valid PNG: ${file.path}');
    }
  }

  bool _isPngSignature(List<int> bytes) {
    const sig = [137, 80, 78, 71, 13, 10, 26, 10];
    for (var i = 0; i < sig.length; i++) {
      if (bytes[i] != sig[i]) return false;
    }
    return true;
  }

  String _capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}
