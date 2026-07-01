import 'dart:async';
import 'dart:io';
import '../model/annspec_model.dart';

/// Runs `flutterfire configure` for every flavor × platform × build type
/// that has a project_id in the annspec.yaml.
///
/// Auth is via the service_account field only — no ADC or gcloud fallback
/// (REQ-FIRE-00100: no machine-level dependency).
class FirebaseGenerator {
  static const _buildTypes = ['release', 'debug'];
  static const _platforms  = ['android', 'ios', 'web', 'windows'];

  // Kill flutterfire if it hasn't finished within this window.
  // Auth prompts or network issues cause it to hang indefinitely otherwise.
  static const _timeout = Duration(seconds: 120);

  static Future<void> generate(
    AnnspecModel spec,
    String projectRoot,
  ) async {
    // Only run when firebase integration is explicitly enabled.
    if (spec.integrations?.firebase != true) {
      print('  ⚠ integrations.firebase is not enabled — skipping flutterfire.');
      return;
    }

    final cmds = _buildCommands(spec);

    if (cmds.isEmpty) {
      print('  ⚠ No Firebase project_id found in annspec.yaml — skipping flutterfire.');
      return;
    }

    print('  Running flutterfire configure for ${cmds.length} combination(s)...');
    var failed = 0;

    for (final cmd in cmds) {
      print('  ▶ ${cmd.label}');
      final ok = await _runFlutterfire(cmd, projectRoot);
      if (ok) {
        print('  ✓ Done: ${cmd.label}');
      } else {
        print('  ✗ Failed: ${cmd.label}');
        failed++;
      }
    }

    if (failed > 0) {
      print('  ⚠ $failed flutterfire command(s) failed.');
    } else {
      print('  ✓ Firebase options files generated.');
    }
  }

  static Future<bool> _runFlutterfire(_FbCmd cmd, String projectRoot) async {
    ProcessResult result;
    try {
      result = await Process.run(
        'flutterfire',
        _buildArgs(cmd),
        workingDirectory: projectRoot,
      ).timeout(_timeout, onTimeout: () {
        print('  ✗ Timed out after ${_timeout.inSeconds}s: ${cmd.label}');
        return ProcessResult(-1, 1, '', '');
      });
    } on ProcessException catch (e) {
      print('  ✗ Could not run flutterfire: ${e.message}');
      print('     Install it with: dart pub global activate flutterfire_cli');
      return false;
    }

    if (result.exitCode == 0) return true;

    final errText = result.stderr.toString();
    if (_isAuthError(errText)) {
      // No machine-auth fallback (REQ-FIRE-00100). Point developer to service_account.
      print('  ✗ Firebase authentication failed for: ${cmd.label}');
      print('     Check the service_account field in your annspec.yaml.');
      print('     The account needs the "Firebase Admin SDK Administrator Service Agent" IAM role.');
    } else {
      stderr.write(errText);
    }
    return false;
  }

  static bool _isAuthError(String text) {
    final lower = text.toLowerCase();
    return lower.contains('unauthenticated') ||
        lower.contains('invalid_grant') ||
        lower.contains('token') && (lower.contains('expired') || lower.contains('revoked')) ||
        lower.contains('authentication required') ||
        lower.contains('not logged in') ||
        lower.contains('please sign in') ||
        lower.contains('failed to get project') ||
        lower.contains('permission denied');
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
            projectId:      fb!.projectId!,
            serviceAccount: fb.serviceAccount,
            outFile:        outFile,
            platform:       platformKey,
            label:          '${flavor.key} / $buildType / $platformKey',
          ));
        }
      }
    }
    return cmds;
  }

  static List<String> _buildArgs(_FbCmd cmd) {
    final args = [
      'configure', '-y', '-f',
      '-p', cmd.projectId,
      '-o', cmd.outFile,
      '--platforms=${cmd.platform}',
    ];
    // Service account is the only supported auth method (REQ-FIRE-00100 — no ADC/gcloud fallback).
    if (cmd.serviceAccount != null) {
      args.addAll(['--service-account', cmd.serviceAccount!]);
    }
    return args;
  }
}

class _FbCmd {
  final String projectId;
  final String? serviceAccount;
  final String outFile;
  final String platform;
  final String label;

  const _FbCmd({
    required this.projectId,
    this.serviceAccount,
    required this.outFile,
    required this.platform,
    required this.label,
  });
}
