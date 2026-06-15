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
    buf.writeln("import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;");
    buf.writeln();

    // Firebase imports per flavor per platform.
    // Uses platform-default firebase when no flavor-level firebase exists.
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
          buf.writeln("import './firebase/${_fbFile(flavorKey, platformKey, 'release')}' as ${_fbAlias(flavorKey, platformKey, 'release')};");
        }
        if (fbDebug != null) {
          buf.writeln("import './firebase/${_fbFile(flavorKey, platformKey, 'debug')}' as ${_fbAlias(flavorKey, platformKey, 'debug')};");
        }
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

    // Firebase helpers — kept separate so ann_flutter_flavor package stays firebase-free.
    // Switch on String key so the package does not need to know AnnFlavorKey.
    buf.writeln('/// Firebase options for the active flavor + platform (release).');
    buf.writeln('FirebaseOptions? flavorFirebaseOptions() {');
    buf.writeln("  switch (AnnFlavor.current.key) {");
    for (final key in allFlavors.keys) {
      buf.writeln("    case '${key}': return _${_pascal(key)}Firebase.options(AnnFlavor.platform);");
    }
    buf.writeln('    default: return null;');
    buf.writeln('  }');
    buf.writeln('}');
    buf.writeln();
    buf.writeln('/// Firebase options for the active flavor + platform (debug).');
    buf.writeln('FirebaseOptions? flavorFirebaseOptionsDebug() {');
    buf.writeln("  switch (AnnFlavor.current.key) {");
    for (final key in allFlavors.keys) {
      buf.writeln("    case '${key}': return _${_pascal(key)}Firebase.optionsDebug(AnnFlavor.platform);");
    }
    buf.writeln('    default: return null;');
    buf.writeln('  }');
    buf.writeln('}');
    buf.writeln();

    // Firebase class per flavor
    for (final entry in allFlavors.entries) {
      _writeFirebaseClass(buf, entry.key, entry.value, spec);
      buf.writeln();
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

    // adsId
    buf.writeln('  @override String? adsId(AnnPlatform platform) {');
    buf.writeln('    switch (platform) {');
    for (final pe in byPlatform.entries) {
      if (pe.value.gmsAdsId != null) {
        buf.writeln("      case AnnPlatform.${pe.key}: return '${_esc(pe.value.gmsAdsId!)}';");
      }
    }
    buf.writeln('      default: return null;');
    buf.writeln('    }');
    buf.writeln('  }');
    buf.writeln();

    // subscriptions
    buf.writeln('  @override List<AnnSubscription>? subscriptions(AnnPlatform platform) {');
    buf.writeln('    switch (platform) {');
    for (final pe in byPlatform.entries) {
      if (pe.value.subscriptions.isNotEmpty) {
        buf.writeln('      case AnnPlatform.${pe.key}: return [');
        for (final s in pe.value.subscriptions) {
          final ids = s.entitlementIds.map((e) => "'$e'").join(', ');
          buf.writeln("        AnnSubscription(apiKey: '${_esc(s.apiKey)}', entitlementIds: [$ids]),");
        }
        buf.writeln('      ];');
      }
    }
    buf.writeln('      default: return null;');
    buf.writeln('    }');
    buf.writeln('  }');
    buf.writeln();

    _writeAuthGetter(buf, 'auth', byPlatform, (f) => f.authRelease,
        androidPlatform?.defaultAuthRelease, iosPlatform?.defaultAuthRelease);
    buf.writeln();
    _writeAuthGetter(buf, 'authDebug', byPlatform, (f) => f.authDebug,
        androidPlatform?.defaultAuthDebug, iosPlatform?.defaultAuthDebug);

    buf.writeln('}');
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
    buf.writeln('      default: return null;');
    buf.writeln('    }');
    buf.writeln('  }');
  }

  static void _writeFirebaseClass(
    StringBuffer buf,
    String flavorKey,
    Map<String, AnnspecFlavor> byPlatform,
    AnnspecModel spec,
  ) {
    buf.writeln('class _${_pascal(flavorKey)}Firebase {');
    buf.writeln('  static FirebaseOptions? options(AnnPlatform platform) {');
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
    buf.writeln('      default: return null;');
    buf.writeln('    }');
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
    buf.writeln('      default: return null;');
    buf.writeln('    }');
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
}
