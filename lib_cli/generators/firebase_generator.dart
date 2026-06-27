import 'dart:io';
import '../model/annspec_model.dart';

/// Runs `flutterfire configure` for every flavor × platform × build type
/// that has a project_id in the annspec.yaml.
class FirebaseGenerator {
  static const _buildTypes = ['release', 'debug'];
  static const _platforms  = ['android', 'ios', 'web', 'windows'];

  static void generate(AnnspecModel spec, String projectRoot) {
    final cmds = _buildCommands(spec);

    if (cmds.isEmpty) {
      print('  ⚠ No Firebase project_id found in annspec.yaml — skipping flutterfire.');
      return;
    }

    print('  Running flutterfire configure for ${cmds.length} combination(s)...');
    var failed = 0;

    for (final cmd in cmds) {
      print('  ▶ ${cmd.label}');
      final args = _buildArgs(cmd);
      final result = Process.runSync(
        'flutterfire',
        args,
        workingDirectory: projectRoot,
      );
      if (result.exitCode != 0) {
        stderr.write(result.stderr);
        print('  ✗ Failed: ${cmd.label}');
        failed++;
      } else {
        print('  ✓ Done: ${cmd.label}');
      }
    }

    if (failed > 0) {
      print('  ⚠ $failed flutterfire command(s) failed.');
    } else {
      print('  ✓ Firebase options files generated.');
    }
  }

  // ── Command builder ──────────────────────────────────────────────────────────

  static List<_FbCmd> _buildCommands(AnnspecModel spec) {
    final cmds = <_FbCmd>[];

    for (final platformKey in _platforms) {
      final platform = spec.platform(platformKey);
      if (platform == null) continue;

      for (final flavor in platform.flavors) {
        for (final buildType in _buildTypes) {
          final fb = buildType == 'release'
              ? (flavor.firebaseRelease ?? platform.defaultFirebaseRelease)
              : (flavor.firebaseDebug   ?? platform.defaultFirebaseDebug);

          if (fb?.projectId == null) continue;

          final outFile =
              'lib/generated/firebase/${flavor.key}_${buildType}_${platformKey}_firebase_options.dart';

          cmds.add(_FbCmd(
            projectId: fb!.projectId!,
            outFile:   outFile,
            platform:  platformKey,
            label:     '${flavor.key} / $buildType / $platformKey',
          ));
        }
      }
    }
    return cmds;
  }

  static List<String> _buildArgs(_FbCmd cmd) => [
    'configure',
    '-y',
    '-f',
    '-p', cmd.projectId,
    '-o', cmd.outFile,
    '--platforms=${cmd.platform}',
  ];
}

class _FbCmd {
  final String projectId;
  final String outFile;
  final String platform;
  final String label;

  const _FbCmd({
    required this.projectId,
    required this.outFile,
    required this.platform,
    required this.label,
  });
}
