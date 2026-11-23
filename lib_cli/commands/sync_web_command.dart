import 'dart:convert';
import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import '../vendor/ann_flavor_core/ann_flavor_core.dart' as core;
import '../spec/annspec_reader.dart';
import '../generators/links_generator.dart';
import '../generators/web_template_renderer.dart';
import '../generators/web_scaffold_generator.dart';
import '../generators/web_base_href_checker.dart';
import '../generators/web_build_options_checker.dart';
import '../generators/web_icon_checker.dart';

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
          help: 'Scaffold index.tmpl.html if not present.')
      ..addFlag('scaffold-bootstrap',
          defaultsTo: false,
          help: 'Scaffold flutter_bootstrap.tmpl.js (loads CanvasKit from build.canvaskit_base_url) if not present.');
  }

  @override
  Future<void> run() async {
    final flavorKey = argResults!['flavor'] as String;
    final projectRoot = p.canonicalize(argResults!['project'] as String);
    final scaffoldManifest = argResults!['scaffold-manifest'] as bool;
    final scaffoldIndex = argResults!['scaffold-index'] as bool;
    final scaffoldBootstrap = argResults!['scaffold-bootstrap'] as bool;

    final spec = AnnspecReader.read(projectRoot);

    final webPlatform = spec.app.web;
    if (webPlatform == null) {
      stderr.writeln('No web platform defined in annspec.yaml.');
      exit(1);
    }

    final flavor = webPlatform.flavors[flavorKey];
    if (flavor == null) {
      stderr.writeln(
          'Flavor "$flavorKey" not found under app.web.flavor in annspec.yaml.');
      exit(1);
    }

    // 1. Scaffold
    if (scaffoldManifest || scaffoldIndex || scaffoldBootstrap) {
      print('  Scaffolding web_flavors/$flavorKey/...');
      WebScaffoldGenerator(projectRoot).scaffold(
        flavorKey,
        manifestTemplate: scaffoldManifest,
        indexTemplate: scaffoldIndex,
        bootstrapTemplate: scaffoldBootstrap,
      );
    }

    // 1b. base_href checks (REQ-WEB-00060): stop before copying anything when the build would fail
    final findings = <({bool isError, String path, String message, String? fix})>[
      for (final f in WebBaseHrefChecker.check(projectRoot, flavorKey, flavor.baseHref))
        (isError: f.isError, path: f.path, message: f.message, fix: f.fix),
      // 1c. build options (REQ-WEB-00130)
      for (final f in WebBuildOptionsChecker.check(projectRoot, flavorKey, webPlatform))
        (isError: f.isError, path: f.path, message: f.message, fix: f.fix),
      // 1d. icons the manifest and the page name (REQ-WEB-00260)
      for (final f in WebIconChecker.check(projectRoot, flavorKey))
        (isError: false, path: f.path, message: f.message, fix: f.fix),
    ];
    for (final f in findings.where((f) => !f.isError)) {
      print('  ⚠ ${f.path}: ${f.message}${f.fix == null ? '' : ' → ${f.fix}'}');
    }
    final blocking = findings.where((f) => f.isError).toList();
    if (blocking.isNotEmpty) {
      for (final f in blocking) {
        stderr.writeln('  ✗ ${f.path}: ${f.message}${f.fix == null ? '' : ' → ${f.fix}'}');
      }
      exit(1);
    }

    // 2. Render *.tmpl.* files
    print('  Rendering templates for $flavorKey...');
    WebTemplateRenderer(projectRoot).render(flavorKey, spec);

    // 3. Regenerate version.json
    print('  Generating version.json for $flavorKey...');
    _writeVersionJson(projectRoot, flavorKey, flavor, webPlatform.defaults);

    // 4. Copy web_flavors/<flavor>/ → web/ (excluding *.tmpl.* and wrangler.toml)
    print('  Copying web_flavors/$flavorKey/ → web/...');
    _copyToWeb(projectRoot, flavorKey);

    print('  ✓ sync-web complete for $flavorKey');
  }

  void _writeVersionJson(
    String projectRoot,
    String flavorKey,
    core.WebFlavor flavor,
    core.WebDefault defaults,
  ) {
    final resolved = core.AnnSpecResolver.resolveWebFlavor(flavor, defaults, 'release');
    final name = resolved.effectiveName;
    final version = resolved.effectiveVersionName;
    final buildNumber = resolved.effectiveVersionCode?.toString() ?? '';
    final packageName = resolved.effectiveId;

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

  /// web/ is shared by every flavor, so files a previous flavor copied in would otherwise
  /// ship with this one. Deep link files belong only to the flavor whose folder holds them
  /// (`links.serve_from`): remove the two generated files and the marked `_headers` block
  /// first; the copy below puts them back for the serving flavor. Any other file in
  /// web/.well-known, and any other line of `_headers`, is left alone.
  void _clearStaleLinksFiles(String projectRoot) {
    final wellKnown = Directory(p.join(projectRoot, 'web', '.well-known'));
    for (final name in const ['assetlinks.json', 'apple-app-site-association']) {
      final f = File(p.join(wellKnown.path, name));
      if (f.existsSync()) f.deleteSync();
    }
    if (wellKnown.existsSync() && wellKnown.listSync().isEmpty) wellKnown.deleteSync();

    final headers = File(p.join(projectRoot, 'web', '_headers'));
    if (headers.existsSync()) {
      final before = headers.readAsStringSync();
      final after = LinksGenerator.stripHeaderBlock(before);
      if (after != before) {
        if (after.trim().isEmpty) {
          headers.deleteSync();
        } else {
          headers.writeAsStringSync(after);
        }
      }
    }
  }

  void _copyToWeb(String projectRoot, String flavorKey) {
    final src = Directory('$projectRoot/web_flavors/$flavorKey');
    if (!src.existsSync()) return;
    _clearStaleLinksFiles(projectRoot);

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
