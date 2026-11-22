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
      ..writeln(
          '// Deep link facts from annspec.yaml (links:). See the Deep Links page of the guide.')
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
      if (f.androidId != null)
        buf.writeln("      'androidId': ${quote(f.androidId!)},");
      if (f.iosBundleId != null)
        buf.writeln("      'iosBundleId': ${quote(f.iosBundleId!)},");
      if (appleId != null && appleId.isNotEmpty)
        buf.writeln("      'appleId': ${quote(appleId)},");
      buf.writeln('    },');
    }

    buf
      ..writeln('  },')
      ..writeln('};')
      ..writeln();
    _writeTypedLayer(buf, spec, links);
    return buf.toString();
  }

  static const _reserved = {
    'abstract',
    'as',
    'assert',
    'async',
    'await',
    'break',
    'case',
    'catch',
    'class',
    'const',
    'continue',
    'covariant',
    'default',
    'deferred',
    'do',
    'dynamic',
    'else',
    'enum',
    'export',
    'extends',
    'extension',
    'external',
    'factory',
    'false',
    'final',
    'finally',
    'for',
    'function',
    'get',
    'hide',
    'if',
    'implements',
    'import',
    'in',
    'interface',
    'is',
    'late',
    'library',
    'mixin',
    'new',
    'null',
    'of',
    'on',
    'operator',
    'part',
    'required',
    'rethrow',
    'return',
    'set',
    'show',
    'static',
    'super',
    'switch',
    'sync',
    'this',
    'throw',
    'true',
    'try',
    'typedef',
    'var',
    'void',
    'while',
    'with',
    'yield',
  };

  /// The enum value name of a flavor key: lowerCamelCase over `_` and `-`, safe as a Dart identifier
  /// (a name that starts with a digit or is a Dart keyword gets a `flavor` prefix).
  static String enumName(String key) {
    final parts =
        key.split(RegExp(r'[_\-]+')).where((w) => w.isNotEmpty).toList();
    var name = parts.isEmpty
        ? 'flavor'
        : parts.first +
            parts
                .skip(1)
                .map((w) => w[0].toUpperCase() + w.substring(1))
                .join();
    if (RegExp(r'^[0-9]').hasMatch(name) || _reserved.contains(name)) {
      name = 'flavor${name[0].toUpperCase()}${name.substring(1)}';
    }
    return name;
  }

  static void _writeTypedLayer(
      StringBuffer buf, core.AnnSpec spec, core.ResolvedLinks links) {
    final names = links.flavors.keys.toList()..sort();
    buf
      ..writeln('// ── Typed layer ────────────────────────────────────')
      ..writeln('// Built from the same values as annLinks. No imports.')
      ..writeln('enum AnnLinkFlavorKey {');
    for (final n in names) {
      buf.writeln('  ${enumName(n)},');
    }
    buf
      ..writeln('}')
      ..writeln()
      ..write(_classSource)
      ..writeln()
      ..writeln(
          'const Map<AnnLinkFlavorKey, AnnLinkFlavor> annLinkFlavors = {');
    for (final n in names) {
      final f = links.flavors[n]!;
      final appleId = spec.app.ios?.flavors[n]?.stores?.appStore?.appleId;
      buf
        ..writeln('  AnnLinkFlavorKey.${enumName(n)}: AnnLinkFlavor(')
        ..writeln('    key: AnnLinkFlavorKey.${enumName(n)},')
        ..writeln('    domain: ${quote(f.domain!)},')
        ..writeln('    pathPrefix: ${quote(f.pathPrefix!)},')
        ..writeln('    alsoHandles: ${_list(f.alsoHandles)},')
        ..writeln('    platforms: ${_list(f.platforms)},');
      if (f.androidId != null)
        buf.writeln('    androidId: ${quote(f.androidId!)},');
      if (f.iosBundleId != null)
        buf.writeln('    iosBundleId: ${quote(f.iosBundleId!)},');
      if (appleId != null && appleId.isNotEmpty)
        buf.writeln('    appleId: ${quote(appleId)},');
      buf.writeln('  ),');
    }
    buf
      ..writeln('};')
      ..writeln()
      ..write(_functionsSource);
  }

  static const _classSource = r'''
/// One flavor's deep link facts.
class AnnLinkFlavor {
  const AnnLinkFlavor({
    required this.key,
    required this.domain,
    required this.pathPrefix,
    this.alsoHandles = const [],
    this.platforms = const [],
    this.androidId,
    this.iosBundleId,
    this.appleId,
  });

  final AnnLinkFlavorKey key;
  final String domain;
  final String pathPrefix;
  final List<String> alsoHandles;
  final List<String> platforms;
  final String? androidId;
  final String? iosBundleId;
  final String? appleId;

  /// `https://<domain>`.
  String get origin => 'https://$domain';

  /// The https address of [path] under this flavor's own prefix; no [path] gives the prefix itself.
  Uri uri([String path = '']) {
    final tail = path.isEmpty || path.startsWith('/') ? path : '/$path';
    return Uri.parse('$origin$pathPrefix$tail');
  }

  /// True for this flavor's own prefix and for the prefixes it also handles.
  bool handlesPath(String path) =>
      _annLinkMatches(pathPrefix, path) || alsoHandles.any((p) => _annLinkMatches(p, path));

  /// [platform] is `'android'`, `'ios'` or `'web'`.
  bool existsOn(String platform) => platforms.contains(platform);
}
''';

  static const _functionsSource = r'''
bool _annLinkMatches(String prefix, String path) {
  final end = path.indexOf(RegExp(r'[?#]'));
  final clean = end < 0 ? path : path.substring(0, end);
  return clean == prefix || clean.startsWith('$prefix/');
}

/// The flavor for [key].
AnnLinkFlavor linkFlavorFor(AnnLinkFlavorKey key) => annLinkFlavors[key]!;

/// The flavor whose own prefix owns [path] (the longest prefix wins), or null. `alsoHandles` is not
/// consulted: it says who may open a link, not who owns it.
AnnLinkFlavor? linkFlavorOwning(String path) {
  AnnLinkFlavor? best;
  for (final f in annLinkFlavors.values) {
    if (_annLinkMatches(f.pathPrefix, path) && (best == null || f.pathPrefix.length > best.pathPrefix.length)) {
      best = f;
    }
  }
  return best;
}

/// Like [linkFlavorOwning] for a full address: only https on the flavor's domain counts.
AnnLinkFlavor? linkFlavorOwningUri(Uri uri) {
  if (uri.scheme != 'https') return null;
  final host = uri.host.toLowerCase();
  AnnLinkFlavor? best;
  for (final f in annLinkFlavors.values) {
    if (f.domain == host &&
        _annLinkMatches(f.pathPrefix, uri.path) &&
        (best == null || f.pathPrefix.length > best.pathPrefix.length)) {
      best = f;
    }
  }
  return best;
}

/// The flavor whose Android id or iOS bundle id is [id], or null.
AnnLinkFlavor? linkFlavorByApplicationId(String id) {
  for (final f in annLinkFlavors.values) {
    if (f.androidId == id || f.iosBundleId == id) return f;
  }
  return null;
}
''';

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

  static String _list(List<String> values) =>
      '[${values.map(quote).join(', ')}]';
}
