import 'dart:io';
import 'package:path/path.dart' as p;
import '../vendor/ann_flavor_core/ann_flavor_core.dart' as core;

/// Writes `lib/generated/ann_links.g.dart` (REQ-LINK-00100 → 00130): the facts of the `links:`
/// block that Dart code needs at runtime, as one plain `const` map with no imports.
///
/// The shape is a contract with the code that reads it (the planned `ann_links` package or the
/// app itself): keys may be added, never renamed or removed without a major version.
class LinksDartGenerator {
  static const _relativePath = 'lib/generated/ann_links.g.dart';

  /// Writes the file when the `links:` block is present. Returns the path relative to
  /// [projectRoot] when the file was created or changed, null when nothing was written
  /// (no block, or the file is already up to date). Throws [StateError] for an invalid block.
  static String? generate(core.AnnSpec spec, String projectRoot) {
    if (spec.links == null) return null;
    final links = core.AnnSpecResolver.resolveLinks(spec);
    if (links.errors.isNotEmpty) {
      throw StateError(links.errors.map((e) => '  - $e').join('\n'));
    }

    final content = render(spec, links);
    final file = File(p.join(projectRoot, _relativePath));
    if (file.existsSync() && file.readAsStringSync() == content) return null;
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
    return _relativePath;
  }

  /// The file's text. Flavors sorted by key, keys in a fixed order, absent values omitted.
  static String render(core.AnnSpec spec, core.ResolvedLinks links) {
    final buf = StringBuffer()
      ..writeln('// GENERATED — do not edit manually.')
      ..writeln('// Run: dart run ann_flutter_flavor sync')
      ..writeln('//')
      ..writeln('// Deep link facts from annspec.yaml (links:). See the Deep Links page of the guide.')
      ..writeln('const Map<String, Object?> annLinks = {')
      ..writeln("  'flavors': {");

    for (final name in links.flavors.keys.toList()..sort()) {
      final f = links.flavors[name]!;
      final appleId = spec.app.ios?.flavors[name]?.stores?.appStore?.appleId;
      buf
        ..writeln('    ${quote(name)}: {')
        ..writeln("      'domain': ${quote(f.domain!)},")
        ..writeln("      'pathPrefix': ${quote(f.pathPrefix!)},")
        ..writeln("      'alsoHandles': ${_list(f.alsoHandles)},")
        ..writeln("      'platforms': ${_list(f.platforms)},");
      if (f.androidId != null) buf.writeln("      'androidId': ${quote(f.androidId!)},");
      if (f.iosBundleId != null) buf.writeln("      'iosBundleId': ${quote(f.iosBundleId!)},");
      if (appleId != null && appleId.isNotEmpty) buf.writeln("      'appleId': ${quote(appleId)},");
      buf.writeln('    },');
    }

    buf
      ..writeln('  },')
      ..writeln('};');
    return buf.toString();
  }

  /// A Dart single-quoted string literal for any value: `\`, `'`, `$` and line breaks escaped.
  static String quote(String value) {
    final escaped = value
        .replaceAll(r'\', r'\\')
        .replaceAll("'", r"\'")
        .replaceAll(r'$', r'\$')
        .replaceAll('\n', r'\n')
        .replaceAll('\r', r'\r');
    return "'$escaped'";
  }

  static String _list(List<String> values) => '[${values.map(quote).join(', ')}]';
}
