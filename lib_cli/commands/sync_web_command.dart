import 'dart:convert';
import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import '../spec/annspec_reader.dart';
import '../generators/web_template_renderer.dart';
import '../generators/web_scaffold_generator.dart';

class SyncWebCommand extends Command<void> {
  @override
  final name = 'sync-web';

  @override
  final description =
      'Prepare web/ for a specific flavor: scaffold, render templates, '
      'generate version.json, and copy to web/.';

  SyncWebCommand() {
    argParser
      ..addOption('flavor', abbr: 'f', mandatory: true,
          help: 'Flavor key to sync (e.g. ledger_in).')
      ..addOption('project', abbr: 'p', defaultsTo: '.',
          help: 'Path to the Flutter project root.')
      ..addFlag('scaffold-manifest',
          defaultsTo: false,
          help: 'Scaffold manifest.tmpl.json if not present.')
      ..addFlag('scaffold-index',
          defaultsTo: false,
          help: 'Scaffold index.tmpl.html if not present.');
  }

  @override
  Future<void> run() async {
    final flavorKey = argResults!['flavor'] as String;
    final projectRoot = p.canonicalize(argResults!['project'] as String);
    final scaffoldManifest = argResults!['scaffold-manifest'] as bool;
    final scaffoldIndex = argResults!['scaffold-index'] as bool;

    final spec = AnnspecReader.read(projectRoot);

    final webPlatform = spec.platform('web');
    if (webPlatform == null) {
      stderr.writeln('No web platform defined in annspec.yaml.');
      exit(1);
    }

    final flavor =
        webPlatform.flavors.where((f) => f.key == flavorKey).firstOrNull;
    if (flavor == null) {
      stderr.writeln(
          'Flavor "$flavorKey" not found under app.web.flavor in annspec.yaml.');
      exit(1);
    }

    // 1. Scaffold
    if (scaffoldManifest || scaffoldIndex) {
      print('  Scaffolding web_flavors/$flavorKey/...');
      WebScaffoldGenerator(projectRoot).scaffold(
        flavorKey,
        manifestTemplate: scaffoldManifest,
        indexTemplate: scaffoldIndex,
      );
    }

    // 2. Render *.tmpl.* files
    print('  Rendering templates for $flavorKey...');
    WebTemplateRenderer(projectRoot).render(flavorKey, spec);

    // 3. Regenerate version.json
    print('  Generating version.json for $flavorKey...');
    _writeVersionJson(projectRoot, flavorKey, flavor, webPlatform);

    // 4. Copy web_flavors/<flavor>/ → web/ (excluding *.tmpl.* and wrangler.toml)
    print('  Copying web_flavors/$flavorKey/ → web/...');
    _copyToWeb(projectRoot, flavorKey);

    print('  ✓ sync-web complete for $flavorKey');
  }

  void _writeVersionJson(
    String projectRoot,
    String flavorKey,
    dynamic flavor,
    dynamic platform,
  ) {
    final name = flavor.name ?? platform.baseName ?? flavorKey;
    final version = flavor.versionName ?? platform.defaultVersionName ?? '';
    final buildNumber =
        flavor.versionCode ?? platform.defaultVersionCode ?? '';
    final base = platform.baseId ?? '';
    final packageName = flavor.id ??
        (flavor.idSuffix != null ? '$base${flavor.idSuffix}' : base);

    final json = const JsonEncoder.withIndent('  ').convert({
      'app_name': name,
      'version': version,
      'build_number': buildNumber,
      'package_name': packageName,
    });

    final outFile = File('$projectRoot/web_flavors/$flavorKey/version.json');
    outFile.parent.createSync(recursive: true);
    outFile.writeAsStringSync('$json\n');
  }

  void _copyToWeb(String projectRoot, String flavorKey) {
    final src = Directory('$projectRoot/web_flavors/$flavorKey');
    if (!src.existsSync()) return;

    for (final entity in src.listSync(recursive: true)) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      // Skip template sources — only copy rendered outputs
      if (name.contains('.tmpl.') || name == 'wrangler.toml') continue;

      final relative =
          p.relative(entity.path, from: src.path);
      final dest = File(p.join(projectRoot, 'web', relative));
      dest.parent.createSync(recursive: true);
      entity.copySync(dest.path);
    }
  }
}
