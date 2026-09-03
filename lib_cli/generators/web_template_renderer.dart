import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:ann_flavor_core/ann_flavor_core.dart' as core;

/// Renders all *.tmpl.* files in web_flavors/<flavorKey>/ to *.*
/// by substituting {{variable}} placeholders from annspec.yaml.
class WebTemplateRenderer {
  final String projectRoot;
  WebTemplateRenderer(this.projectRoot);

  void render(String flavorKey, core.AnnSpec spec) {
    final flavorDir = Directory('$projectRoot/web_flavors/$flavorKey');
    if (!flavorDir.existsSync()) return;

    final vars = _buildVars(flavorKey, spec);

    for (final entity in flavorDir.listSync(recursive: true)) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      // Match *.tmpl.* pattern — e.g. manifest.tmpl.json, index.tmpl.html
      if (!name.contains('.tmpl.')) continue;

      final rendered = _substitute(entity.readAsStringSync(), vars);
      final outName = name.replaceFirst('.tmpl.', '.');
      final outPath = p.join(p.dirname(entity.path), outName);
      File(outPath).writeAsStringSync(rendered);
    }
  }

  Map<String, String> _buildVars(String flavorKey, core.AnnSpec spec) {
    final platform = spec.app.web;
    final flavor = platform?.flavors[flavorKey];

    core.ResolvedBuildOutput? resolved;
    if (platform != null && flavor != null) {
      resolved = core.AnnSpecResolver.resolveWebFlavor(flavor, platform.defaults, 'release');
    }

    final name = resolved?.effectiveName ?? flavorKey;
    final shortName = name.split(' ').first;
    final id = resolved?.effectiveId ?? '';
    final version = resolved?.effectiveVersionName ?? '';
    final versionCode = resolved?.effectiveVersionCode?.toString() ?? '';

    // theme_color and background_color come from custom.web group. Falls
    // back to the first web flavor's resolved custom.web if this flavor key
    // wasn't found — matches the pre-existing fallback behavior.
    var customWeb = resolved?.effectiveCustom['web'];
    if (customWeb == null && platform != null && platform.flavors.isNotEmpty) {
      final firstEntry = platform.flavors.entries.first;
      customWeb = core.AnnSpecResolver
          .resolveWebFlavor(firstEntry.value, platform.defaults, 'release')
          .effectiveCustom['web'];
    }
    final themeColor = customWeb?['theme_color'] as String? ?? '#FFFFFF';
    final bgColor = customWeb?['background_color'] as String? ?? '#FFFFFF';

    final outputDir = flavorKey.isNotEmpty ? 'build/web/$flavorKey' : 'build/web';

    return {
      'name': name,
      'short_name': shortName,
      'id': id,
      'version': version,
      'version_code': versionCode,
      'package_name': id,
      'theme_color': themeColor,
      'background_color': bgColor,
      'output_dir': outputDir,
    };
  }

  String _substitute(String content, Map<String, String> vars) {
    var result = content;
    for (final entry in vars.entries) {
      result = result.replaceAll('{{${entry.key}}}', entry.value);
    }
    return result;
  }
}
