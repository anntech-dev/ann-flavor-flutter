import 'dart:io';
import 'package:path/path.dart' as p;

const _podPluginName = 'ann-ios-flavorize';

/// Ensures the ANN CocoaPods plugin is wired into the iOS project.
class IosGenerator {
  static void generate(String projectRoot) {
    final iosDir = Directory(p.join(projectRoot, 'ios'));
    if (!iosDir.existsSync()) {
      print('  ⚠ No ios/ directory found — skipping iOS wiring.');
      return;
    }
    _patchPodfile(iosDir);
  }

  static void _patchPodfile(Directory iosDir) {
    final file = File(p.join(iosDir.path, 'Podfile'));
    if (!file.existsSync()) {
      print('  ⚠ ios/Podfile not found — skipping iOS wiring.');
      return;
    }

    var content = file.readAsStringSync();
    if (content.contains(_podPluginName)) {
      print('  ✓ ios/Podfile already has ANN CocoaPods plugin.');
      return;
    }

    // Insert at top, before the first 'platform :ios' or 'target' line
    const injection = "plugin '$_podPluginName'\n";
    content = injection + content;
    file.writeAsStringSync(content);
    print('  ✓ Patched ios/Podfile with ANN CocoaPods plugin.');
  }
}
