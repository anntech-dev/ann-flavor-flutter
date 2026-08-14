import 'dart:io';
import 'package:path/path.dart' as p;
import '../model/annspec_model.dart';

/// Renders all *.tmpl.* files in web_flavors/<flavorKey>/ to *.*
/// by substituting {{variable}} placeholders from annspec.yaml.
class WebTemplateRenderer {
  final String projectRoot;
  WebTemplateRenderer(this.projectRoot);

  void render(String flavorKey, AnnspecModel spec) {
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

  Map<String, String> _buildVars(String flavorKey, AnnspecModel spec) {
    final platform = spec.platform('web');
    final flavor = platform?.flavors.where((f) => f.key == flavorKey).firstOrNull;

    final name = flavor?.name ?? platform?.baseName ?? flavorKey;
    final shortName = name.split(' ').first;
    final id = _resolveId(platform, flavor);
    final version = flavor?.versionName ?? platform?.defaultVersionName ?? '';
    final versionCode = flavor?.versionCode ?? platform?.defaultVersionCode ?? '';

    // theme_color and background_color come from custom.web group
    final customWeb = flavor?.customByBuildType['release']?['web'] ??
        platform?.flavors.first.customByBuildType['release']?['web'];
    final themeColor =
        customWeb?['theme_color'] as String? ?? '#FFFFFF';
    final bgColor =
        customWeb?['background_color'] as String? ?? '#FFFFFF';

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

  String _resolveId(AnnspecPlatform? platform, AnnspecFlavor? flavor) {
    final base = platform?.baseId ?? '';
    if (flavor?.id != null) return flavor!.id!;
    if (flavor?.idSuffix != null) return '$base${flavor!.idSuffix}';
    return base;
  }

  String _substitute(String content, Map<String, String> vars) {
    var result = content;
    for (final entry in vars.entries) {
      result = result.replaceAll('{{${entry.key}}}', entry.value);
    }
    return result;
  }
}
