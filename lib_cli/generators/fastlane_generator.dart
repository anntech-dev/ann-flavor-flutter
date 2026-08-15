import 'dart:io';
import 'package:path/path.dart' as p;

class FastlaneGenerator {
  static const _annGemLine    = "gem 'ann-flavor-flutter'";
  static const _annGemComment = '# Added by ann_flutter_flavor — Fastlane integration';

  static bool _gemPresent(String content, String gemName) =>
      RegExp("""gem\\s+['""]$gemName['""]""").hasMatch(content);

  static void generate(String projectRoot) {
    final file = File(p.join(projectRoot, 'Gemfile'));

    if (!file.existsSync()) {
      final content = [
        'source "https://rubygems.org"',
        'gem "fastlane"',
        _annGemComment,
        _annGemLine,
      ].join('\n') + '\n';
      file.writeAsStringSync(content);
      print('  ✅ Gemfile created');
      return;
    }

    var existing = file.readAsStringSync();
    var changed = false;

    if (!_gemPresent(existing, 'https://rubygems.org') && !existing.contains('rubygems.org')) {
      existing = existing.trimRight() + '\nsource "https://rubygems.org"\n';
      changed = true;
    }

    if (!_gemPresent(existing, 'fastlane')) {
      existing = existing.trimRight() + '\ngem "fastlane"\n';
      changed = true;
    }

    if (!_gemPresent(existing, 'ann-flavor-flutter')) {
      existing = existing.trimRight() + '\n$_annGemComment\n$_annGemLine\n';
      changed = true;
    }

    if (!changed) {
      print('  ✅ Gemfile already up to date');
      return;
    }

    file.writeAsStringSync(existing);
    print('  ✅ Gemfile updated');
  }
}
