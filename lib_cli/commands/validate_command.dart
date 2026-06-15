import 'package:args/command_runner.dart';
import '../spec/annspec_reader.dart';

class ValidateCommand extends Command<void> {
  @override
  final name = 'validate';

  @override
  final description = 'Validate annspec.yaml structure and report any issues.';

  ValidateCommand() {
    argParser.addOption('project', abbr: 'p', defaultsTo: '.');
  }

  @override
  Future<void> run() async {
    final projectRoot = argResults!['project'] as String;
    print('ANN Flavor — validating annspec.yaml in $projectRoot');

    final errors = <String>[];

    try {
      final spec = AnnspecReader.read(projectRoot);

      for (final platform in spec.platforms) {
        if (platform.baseId == null) {
          errors.add('[${platform.key}] Missing default.id');
        }
        if (platform.flavors.isEmpty) {
          errors.add('[${platform.key}] No flavors defined');
        }
        for (final flavor in platform.flavors) {
          if (flavor.name == null) {
            errors.add('[${platform.key}/${flavor.key}] Missing name');
          }
          if (flavor.mainFile == null) {
            errors.add('[${platform.key}/${flavor.key}] Missing main_file');
          }
          if (flavor.versionName == null) {
            errors.add('[${platform.key}/${flavor.key}] Missing version_name');
          }
          if (flavor.versionCode == null) {
            errors.add('[${platform.key}/${flavor.key}] Missing version_code');
          }
        }
      }
    } catch (e) {
      print('  ✗ Failed to parse annspec.yaml: $e');
      return;
    }

    if (errors.isEmpty) {
      print('  ✅  annspec.yaml is valid.');
    } else {
      print('  ✗ Found ${errors.length} issue(s):');
      for (final e in errors) {
        print('    • $e');
      }
    }
  }
}
