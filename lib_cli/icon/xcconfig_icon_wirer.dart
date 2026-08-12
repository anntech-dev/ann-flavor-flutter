import 'dart:io';
import 'package:path/path.dart' as p;

/// Patches per-flavor xcconfig files with ASSETCATALOG_COMPILER_APPICON_NAME.
///
/// If the key is already present it is updated in-place; otherwise it is
/// appended so the icon set is picked up by Xcode at build time.
void wireXcconfig(String projectRoot, String flavorName) {
  final iconSetName = '${flavorName[0].toUpperCase()}${flavorName.substring(1)}AppIcon';
  final flutterDir = p.join(projectRoot, 'ios', 'Flutter');

  for (final buildType in ['Release', 'Debug']) {
    final file = File(p.join(flutterDir, '$flavorName$buildType.xcconfig'));
    if (!file.existsSync()) continue;

    const key = 'ASSETCATALOG_COMPILER_APPICON_NAME';
    final line = '$key=$iconSetName';
    var content = file.readAsStringSync();

    final keyPattern = RegExp('^${RegExp.escape(key)}=.*', multiLine: true);
    if (keyPattern.hasMatch(content)) {
      content = content.replaceAll(keyPattern, line);
    } else {
      content = '${content.trimRight()}\n$line\n';
    }

    file.writeAsStringSync(content);
  }
}
