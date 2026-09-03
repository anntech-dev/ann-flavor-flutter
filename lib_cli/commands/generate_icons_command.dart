import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import '../vendor/ann_flavor_core/ann_flavor_core.dart' as core;
import '../spec/annspec_reader.dart';
import '../icon/android_icon_generator.dart';
import '../icon/ios_icon_generator.dart';
import '../icon/web_icon_generator.dart';

/// One flavor's resolved icon source path per platform (null = no icon
/// configured for that platform, either directly or via the default
/// cascade).
class _FlavorIconEntry {
  final String flavorName;
  final String? androidIcon;
  final String? iosIcon;
  final String? webIcon;

  _FlavorIconEntry(this.flavorName, this.androidIcon, this.iosIcon, this.webIcon);
}

/// Generates per-flavor app icons for one or more platforms via
/// `flutter_launcher_icons`. The single implementation Studio's
/// "Generate App Icons" action delegates to — there is no separate
/// Kotlin-side reimplementation of this logic.
class GenerateIconsCommand extends Command<void> {
  @override
  final name = 'generate-icons';

  @override
  final description =
      'Generate per-flavor app icons via flutter_launcher_icons for one or '
      'more platforms and flavors.';

  GenerateIconsCommand() {
    argParser
      ..addOption('project', abbr: 'p', defaultsTo: '.',
          help: 'Path to the Flutter project root.')
      ..addOption('platform',
          help: 'Comma-separated platforms to generate for (android,ios,web). '
              'Defaults to every platform that has icons configured.')
      ..addOption('flavor',
          help: 'Comma-separated flavor keys to generate for. '
              'Defaults to every flavor that has icons configured.');
  }

  @override
  Future<void> run() async {
    final projectRoot = p.canonicalize(argResults!['project'] as String);
    final platformFilter = (argResults!['platform'] as String?)
        ?.split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toSet();
    final flavorFilter = (argResults!['flavor'] as String?)
        ?.split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toSet();

    _clearStrayFlavorConfigs(projectRoot);

    final spec = AnnspecReader.read(projectRoot);
    final entries = _buildIconEntries(spec);

    if (entries.isEmpty) {
      print('No icon paths found in annspec.yaml.');
      return;
    }

    final selected = entries.where((e) {
      if (flavorFilter != null && !flavorFilter.contains(e.flavorName)) return false;
      final hasSelectedPlatform =
          (platformFilter == null || platformFilter.contains('android')) && e.androidIcon != null ||
          (platformFilter == null || platformFilter.contains('ios')) && e.iosIcon != null ||
          (platformFilter == null || platformFilter.contains('web')) && e.webIcon != null;
      return hasSelectedPlatform;
    }).toList();

    if (selected.isEmpty) {
      print('No matching flavor/platform combination has an icon configured.');
      return;
    }

    final errors = <String>[];
    final iosGenerator = IosIconGenerator(projectRoot);
    final androidGenerator = AndroidIconGenerator(projectRoot);
    final webGenerator = WebIconGenerator(projectRoot);

    final wantsIos = selected.any((e) =>
        e.iosIcon != null && (platformFilter == null || platformFilter.contains('ios')));
    if (wantsIos) iosGenerator.backupStockCatalog();

    try {
      for (final entry in selected) {
        if (entry.androidIcon != null && (platformFilter == null || platformFilter.contains('android'))) {
          print('  Android icons: ${entry.flavorName}...');
          try {
            await androidGenerator.generateForFlavor(entry.flavorName, entry.androidIcon!);
          } catch (e) {
            errors.add('[${entry.flavorName}/Android] $e');
          }
        }

        if (entry.iosIcon != null && (platformFilter == null || platformFilter.contains('ios'))) {
          print('  iOS icons: ${entry.flavorName}...');
          try {
            await iosGenerator.generateForFlavor(entry.flavorName, entry.iosIcon!);
          } catch (e) {
            errors.add('[${entry.flavorName}/iOS] $e');
          }
        }

        if (entry.webIcon != null && (platformFilter == null || platformFilter.contains('web'))) {
          print('  Web icons: ${entry.flavorName}...');
          try {
            await webGenerator.generateForFlavor(entry.flavorName, entry.webIcon!);
          } catch (e) {
            errors.add('[${entry.flavorName}/Web] $e');
          }
        }
      }
    } finally {
      if (wantsIos) iosGenerator.restoreStockCatalog();
    }

    if (errors.isEmpty) {
      print('✓ App icons generated for: ${selected.map((e) => e.flavorName).join(', ')}');
    } else {
      stderr.writeln('Icon generation finished with ${errors.length} error(s):');
      for (final e in errors) {
        stderr.writeln('  $e');
      }
      exitCode = 1;
    }
  }

  // flutter_launcher_icons auto-detects "flavor mode" by globbing the working
  // directory for any file matching ^flutter_launcher_icons-(.*)\.yaml$ —
  // when it finds one, it silently ignores our -f argument and runs flavor
  // mode for every match instead. AndroidIconGenerator's temp config
  // legitimately uses that hyphenated pattern (flutter_launcher_icons relies
  // on the filename to route Android output per flavor); each generator
  // deletes its own temp config in a finally block, but a config left behind
  // by an interrupted prior run (process killed, crash) would silently
  // hijack every subsequent run in this directory. Clear any stray matches
  // before starting.
  void _clearStrayFlavorConfigs(String projectRoot) {
    final pattern = RegExp(r'^flutter_launcher_icons-(.*)\.yaml$');
    final dir = Directory(projectRoot);
    if (!dir.existsSync()) return;
    for (final entity in dir.listSync(recursive: false)) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (pattern.hasMatch(name)) {
        print('  Removing stray config from a previous run: $name');
        entity.deleteSync();
      }
    }
  }

  List<_FlavorIconEntry> _buildIconEntries(core.AnnSpec spec) {
    final androidDefault = spec.app.android?.defaults;
    final iosDefault = spec.app.ios?.defaults;
    final webDefault = spec.app.web?.defaults;

    final flavorNames = <String>{
      ...?spec.app.android?.flavors.keys,
      ...?spec.app.ios?.flavors.keys,
      ...?spec.app.web?.flavors.keys,
    };

    if (flavorNames.isEmpty) {
      final defaultAndroid = androidDefault?.icon;
      final defaultIos = iosDefault?.icon;
      final defaultWeb = webDefault?.icon;
      if (defaultAndroid == null && defaultIos == null && defaultWeb == null) return [];
      return [_FlavorIconEntry('default', defaultAndroid, defaultIos, defaultWeb)];
    }

    final sorted = flavorNames.toList()..sort();
    final result = <_FlavorIconEntry>[];
    for (final name in sorted) {
      final androidIcon = spec.app.android?.flavors[name]?.icon ?? androidDefault?.icon;
      final iosIcon = spec.app.ios?.flavors[name]?.icon ?? iosDefault?.icon;
      final webIcon = spec.app.web?.flavors[name]?.icon ?? webDefault?.icon;
      if (androidIcon == null && iosIcon == null && webIcon == null) continue;
      result.add(_FlavorIconEntry(name, androidIcon, iosIcon, webIcon));
    }
    return result;
  }
}
