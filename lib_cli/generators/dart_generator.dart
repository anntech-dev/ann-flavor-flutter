import 'dart:io';
import 'package:path/path.dart' as p;
import '../model/annspec_model.dart';

/// Generates lib/generated/ann_flavor.g.dart inside the Flutter project.
class DartGenerator {
  static void generate(AnnspecModel spec, String projectRoot) {
    final outDir = Directory(p.join(projectRoot, 'lib', 'generated'));
    outDir.createSync(recursive: true);

    final allFlavors = _collectFlavors(spec);
    final buf = StringBuffer();

    buf.writeln('// GENERATED — do not edit manually.');
    buf.writeln('// Run: dart run ann_flutter_flavor sync');
    buf.writeln('//');
    buf.writeln("import 'package:ann_flutter_flavor/ann_flutter_flavor.dart';");

    // Collect firebase imports first so we know if firebase_core is needed.
    final fbImports = <String>[];
    for (final entry in allFlavors.entries) {
      final flavorKey = entry.key;
      final byPlatform = entry.value;
      for (final platformKey in ['android', 'ios', 'web', 'windows']) {
        final flavor = byPlatform[platformKey];
        if (flavor == null) continue;
        final platform = spec.platform(platformKey);
        final fbRelease = flavor.firebaseRelease ?? platform?.defaultFirebaseRelease;
        final fbDebug   = flavor.firebaseDebug   ?? platform?.defaultFirebaseDebug;
        if (fbRelease != null) {
          fbImports.add("import './firebase/${_fbFile(flavorKey, platformKey, 'release')}' as ${_fbAlias(flavorKey, platformKey, 'release')};");
        }
        if (fbDebug != null) {
          fbImports.add("import './firebase/${_fbFile(flavorKey, platformKey, 'debug')}' as ${_fbAlias(flavorKey, platformKey, 'debug')};");
        }
      }
    }

    final hasFirebase = fbImports.isNotEmpty;
    if (hasFirebase) {
      buf.writeln("import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;");
      for (final line in fbImports) {
        buf.writeln(line);
      }
    }
    buf.writeln();
    buf.writeln('// ── Flavor keys ────────────────────────────────────');
    buf.writeln('enum AnnFlavorKey {');
    for (final key in allFlavors.keys) {
      buf.writeln('  ${_camel(key)},');
    }
    buf.writeln('}');
    buf.writeln();

    // One config class per flavor
    for (final entry in allFlavors.entries) {
      _writeFlavorClass(buf, entry.key, entry.value, spec);
      buf.writeln();
    }

    // Registry
    buf.writeln('// ── Registry ───────────────────────────────────────');
    buf.writeln('final _configs = <AnnFlavorKey, AnnFlavorConfig>{');
    for (final key in allFlavors.keys) {
      buf.writeln('  AnnFlavorKey.${_camel(key)}: const _${_pascal(key)}Config(),');
    }
    buf.writeln('};');
    buf.writeln();

    // Setup function — called from each flavor entry point
    buf.writeln('/// Call this at the top of each flavor main() before anything else.');
    buf.writeln('void setupFlavor(AnnFlavorKey flavor, AnnPlatform platform) {');
    buf.writeln('  AnnFlavor.init(config: _configs[flavor]!, platform: platform);');
    buf.writeln('}');
    buf.writeln();

    buf.writeln('/// Returns the [AnnFlavorConfig] for the given [key].');
    buf.writeln('AnnFlavorConfig configFor(AnnFlavorKey key) => _configs[key]!;');
    buf.writeln();

    if (hasFirebase) {
      // Firebase helpers — kept separate so ann_flutter_flavor package stays firebase-free.
      buf.writeln('/// Firebase options for the active flavor + platform, auto-selected by build type.');
      buf.writeln('FirebaseOptions? flavorFirebaseOptions() {');
      buf.writeln("  switch (AnnFlavor.current.key) {");
      for (final key in allFlavors.keys) {
        buf.writeln("    case '$key': return AnnFlavor.buildType == 'debug'");
        buf.writeln("        ? _${_pascal(key)}Firebase.optionsDebug(AnnFlavor.platform)");
        buf.writeln("        : _${_pascal(key)}Firebase.optionsRelease(AnnFlavor.platform);");
      }
      buf.writeln('    default: return null;');
      buf.writeln('  }');
      buf.writeln('}');
      buf.writeln();
      buf.writeln('/// Firebase options for the active flavor + platform (release only).');
      buf.writeln('FirebaseOptions? flavorFirebaseOptionsRelease() {');
      buf.writeln("  switch (AnnFlavor.current.key) {");
      for (final key in allFlavors.keys) {
        buf.writeln("    case '$key': return _${_pascal(key)}Firebase.optionsRelease(AnnFlavor.platform);");
      }
      buf.writeln('    default: return null;');
      buf.writeln('  }');
      buf.writeln('}');
      buf.writeln();
      buf.writeln('/// Firebase options for the active flavor + platform (debug only).');
      buf.writeln('FirebaseOptions? flavorFirebaseOptionsDebug() {');
      buf.writeln("  switch (AnnFlavor.current.key) {");
      for (final key in allFlavors.keys) {
        buf.writeln("    case '$key': return _${_pascal(key)}Firebase.optionsDebug(AnnFlavor.platform);");
      }
      buf.writeln('    default: return null;');
      buf.writeln('  }');
      buf.writeln('}');
      buf.writeln();

      for (final entry in allFlavors.entries) {
        _writeFirebaseClass(buf, entry.key, entry.value, spec);
        buf.writeln();
      }
    }

    final outFile = File(p.join(outDir.path, 'ann_flavor.g.dart'));
    outFile.writeAsStringSync(buf.toString());
    print('  ✓ Generated ${outFile.path}');
  }

  static void _writeFlavorClass(
    StringBuffer buf,
    String flavorKey,
    Map<String, AnnspecFlavor> byPlatform,
    AnnspecModel spec,
  ) {
    final androidPlatform = spec.platform('android');
    final iosPlatform     = spec.platform('ios');
    final android = byPlatform['android'];
    final ios     = byPlatform['ios'];

    final androidId = (androidPlatform?.baseId != null && android?.idSuffix != null)
        ? '${androidPlatform!.baseId}${android!.idSuffix}'
        : androidPlatform?.baseId;
    final iosId = (iosPlatform?.baseId != null && ios?.idSuffix != null)
        ? '${iosPlatform!.baseId}${ios!.idSuffix}'
        : iosPlatform?.baseId;

    final first = byPlatform.values.first;

    buf.writeln('class _${_pascal(flavorKey)}Config extends AnnFlavorConfig {');
    buf.writeln('  const _${_pascal(flavorKey)}Config();');
    buf.writeln();
    buf.writeln("  @override String get key => '$flavorKey';");
    buf.writeln("  @override String get name => '${_esc(first.name ?? flavorKey)}';");
    buf.writeln("  @override String? get androidId => ${_str(androidId)};");
    buf.writeln("  @override String? get iosId => ${_str(iosId)};");
    buf.writeln();

    _writeAuthGetter(buf, 'authRelease', byPlatform, (f) => f.authRelease,
        androidPlatform?.defaultAuthRelease, iosPlatform?.defaultAuthRelease);
    buf.writeln();
    _writeAuthGetter(buf, 'authDebug', byPlatform, (f) => f.authDebug,
        androidPlatform?.defaultAuthDebug, iosPlatform?.defaultAuthDebug);

    // custom() — collect all groups across platforms and build types
    final allGroups = <String, Map<String, Map<String, dynamic>>>{};
    for (final pe in byPlatform.entries) {
      final f = pe.value;
      for (final btEntry in f.customByBuildType.entries) {
        final bt = btEntry.key;
        for (final groupEntry in btEntry.value.entries) {
          final group = groupEntry.key;
          allGroups.putIfAbsent(group, () => {})[bt] = groupEntry.value;
        }
      }
    }
    if (allGroups.isNotEmpty) {
      buf.writeln();
      _writeCustomGetter(buf, allGroups);
    }

    buf.writeln('}');
  }

  static void _writeCustomGetter(
    StringBuffer buf,
    Map<String, Map<String, Map<String, dynamic>>> groups,
  ) {
    buf.writeln('  @override AnnCustomGroup? custom(String group) {');
    buf.writeln('    final bt = AnnFlavor.buildType;');
    buf.writeln('    switch (group) {');
    for (final groupEntry in groups.entries) {
      final groupName = groupEntry.key;
      final byBt = groupEntry.value;
      buf.writeln("      case '${_esc(groupName)}': return switch (bt) {");
      for (final btEntry in byBt.entries) {
        buf.writeln("        '${btEntry.key}' => AnnCustomGroup(${_dartMap(btEntry.value)}),");
      }
      // fallback to first available build type
      final fallback = byBt.values.first;
      buf.writeln("        _ => AnnCustomGroup(${_dartMap(fallback)}),");
      buf.writeln('      };');
    }
    buf.writeln('      default: return null;');
    buf.writeln('    }');
    buf.writeln('  }');
  }

  static void _writeAuthGetter(
    StringBuffer buf,
    String methodName,
    Map<String, AnnspecFlavor> byPlatform,
    AnnspecAuth? Function(AnnspecFlavor) selector,
    AnnspecAuth? androidDefault,
    AnnspecAuth? iosDefault,
  ) {
    buf.writeln('  @override AnnAuthConfig? $methodName(AnnPlatform platform) {');
    buf.writeln('    switch (platform) {');
    for (final pe in byPlatform.entries) {
      final auth = selector(pe.value) ??
          (pe.key == 'android' ? androidDefault : pe.key == 'ios' ? iosDefault : null);
      if (auth != null) {
        buf.writeln('      case AnnPlatform.${pe.key}: return AnnAuthConfig(');
        if (auth.clientId != null) {
          buf.writeln("        clientId: '${_esc(auth.clientId!)}',");
        }
        if (auth.reversedClientId != null) {
          buf.writeln("        reversedClientId: '${_esc(auth.reversedClientId!)}',");
        }
        buf.writeln('      );');
      }
    }
    buf.writeln('    }');
    buf.writeln('    return null;');
    buf.writeln('  }');
  }

  static void _writeFirebaseClass(
    StringBuffer buf,
    String flavorKey,
    Map<String, AnnspecFlavor> byPlatform,
    AnnspecModel spec,
  ) {
    buf.writeln('class _${_pascal(flavorKey)}Firebase {');
    buf.writeln('  static FirebaseOptions? optionsRelease(AnnPlatform platform) {');
    buf.writeln('    switch (platform) {');
    for (final platformKey in ['android', 'ios', 'web', 'windows']) {
      final flavor   = byPlatform[platformKey];
      if (flavor == null) continue;
      final platform = spec.platform(platformKey);
      final fb = flavor.firebaseRelease ?? platform?.defaultFirebaseRelease;
      if (fb != null) {
        final alias = _fbAlias(flavorKey, platformKey, 'release');
        buf.writeln('      case AnnPlatform.$platformKey:');
        buf.writeln('        return $alias.DefaultFirebaseOptions.currentPlatform;');
      }
    }
    buf.writeln('    }');
    buf.writeln('    return null;');
    buf.writeln('  }');
    buf.writeln();
    buf.writeln('  static FirebaseOptions? optionsDebug(AnnPlatform platform) {');
    buf.writeln('    switch (platform) {');
    for (final platformKey in ['android', 'ios', 'web', 'windows']) {
      final flavor   = byPlatform[platformKey];
      if (flavor == null) continue;
      final platform = spec.platform(platformKey);
      final fb = flavor.firebaseDebug ?? platform?.defaultFirebaseDebug;
      if (fb != null) {
        final alias = _fbAlias(flavorKey, platformKey, 'debug');
        buf.writeln('      case AnnPlatform.$platformKey:');
        buf.writeln('        return $alias.DefaultFirebaseOptions.currentPlatform;');
      }
    }
    buf.writeln('    }');
    buf.writeln('    return null;');
    buf.writeln('  }');
    buf.writeln('}');
  }

  static Map<String, Map<String, AnnspecFlavor>> _collectFlavors(AnnspecModel spec) {
    final result = <String, Map<String, AnnspecFlavor>>{};
    for (final platform in spec.platforms) {
      for (final flavor in platform.flavors) {
        result.putIfAbsent(flavor.key, () => {})[platform.key] = flavor;
      }
    }
    return result;
  }

  // Matches original naming: ledger_in_release_android_firebase_options.dart
  static String _fbFile(String flavor, String platform, String buildType) =>
      '${flavor}_${buildType}_${platform}_firebase_options.dart';

  // Matches original alias: ledger_inreleaseandroid (flavor keeps underscore)
  static String _fbAlias(String flavor, String platform, String buildType) =>
      '${flavor.replaceAll('_', '')}$buildType$platform';

  static String _camel(String s) {
    final parts = s.split('_');
    return parts.first +
        parts.skip(1).map((w) => w[0].toUpperCase() + w.substring(1)).join();
  }

  static String _pascal(String s) =>
      s.split('_').map((w) => w[0].toUpperCase() + w.substring(1)).join();

  static String _str(String? s) => s == null ? 'null' : "'${_esc(s)}'";
  static String _esc(String s) => s.replaceAll("'", "\\'");

  /// Converts a resolved custom group map to a Dart const-map literal.
  static String _dartMap(Map<String, dynamic> m) {
    if (m.isEmpty) return 'const {}';
    final entries = m.entries.map((e) => "'${_esc(e.key)}': ${_dartValue(e.value)}");
    return '{${entries.join(', ')}}';
  }

  static String _dartValue(dynamic v) {
    if (v == null)         return 'null';
    if (v is String)       return "'${_esc(v)}'";
    if (v is bool)         return v.toString();
    if (v is int)          return v.toString();
    if (v is double)       return v.toString();
    if (v is List)         return '[${v.map(_dartValue).join(', ')}]';
    return "'$v'";
  }
}
