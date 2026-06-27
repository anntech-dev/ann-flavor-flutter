import 'dart:io';
import 'package:path/path.dart' as p;

class FastlaneGenerator {
  static const _requiredLines = [
    'source "https://rubygems.org"',
    'gem "fastlane"',
    'gem "ann-flavor-flutter"',
  ];

  static void generate(String projectRoot) {
    final file = File(p.join(projectRoot, 'Gemfile'));

    if (!file.existsSync()) {
      file.writeAsStringSync(_requiredLines.join('\n') + '\n');
      print('  ✅ Gemfile created');
      return;
    }

    final existing = file.readAsStringSync();
    final missing = _requiredLines.where((line) => !existing.contains(line)).toList();

    if (missing.isEmpty) {
      print('  ✅ Gemfile already up to date');
      return;
    }

    final updated = existing.trimRight() + '\n' + missing.join('\n') + '\n';
    file.writeAsStringSync(updated);
    print('  ✅ Gemfile updated (added ${missing.length} line(s))');
  }
}
