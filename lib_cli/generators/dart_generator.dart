import 'dart:io';
import 'package:path/path.dart' as p;
import '../vendor/ann_flavor_core/ann_flavor_core.dart' as core;

/// Generates lib/generated/ann_flavor.g.dart inside the Flutter project.
class DartGenerator {
  static void generate(core.AnnSpec spec, String projectRoot) {
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
        final byBuildType = byPlatform[platformKey];
        if (byBuildType == null) continue;
        final fbRelease = byBuildType['release']?.effectiveFirebase;
        final fbDebug   = byBuildType['debug']?.effectiveFirebase;
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
      buf.writeln('// ignore: depend_on_referenced_packages');
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

    final outFile = File(p.join(outDir.path, 'ann_flavor.g.dart'));
    outFile.writeAsStringSync(buf.toString());
    print('  ✓ Generated ${outFile.path}');
  }

  static void _writeFlavorClass(
    StringBuffer buf,
    String flavorKey,
    Map<String, Map<String, core.ResolvedBuildOutput>> byPlatform,
    core.AnnSpec spec,
  ) {
    final iosPlatform = spec.app.ios;
    final ios = iosPlatform?.flavors[flavorKey];

    buf.writeln('class _${_pascal(flavorKey)}Config extends AnnFlavorConfig {');
    buf.writeln('  const _${_pascal(flavorKey)}Config();');
    buf.writeln();
    buf.writeln("  @override String get key => '$flavorKey';");
    buf.writeln();

    _writeExistsOnOverride(buf, flavorKey, spec);
    buf.writeln();

    _writeNameForOverride(buf, flavorKey, spec);
    buf.writeln();
    _writeIdForOverride(buf, flavorKey, spec);
    buf.writeln();

    buf.writeln("  @override String? get appleId => ${_str(ios?.stores?.appStore?.appleId)};");
    buf.writeln();

    _writeAuthForOverride(buf, flavorKey, byPlatform, spec);

    final hasFirebaseForFlavor = byPlatform.values.any(
      (byBt) => byBt.values.any((r) => r.effectiveFirebase != null),
    );
    if (hasFirebaseForFlavor) {
      buf.writeln();
      _writeFirebaseOptionsForOverride(buf, flavorKey, byPlatform, spec);
    }

    // customFor(platform, group, buildType) — collected per platform, not
    // merged across platforms (plan 036: merging silently dropped data when
    // two platforms configured different values for the same group+buildType).
    final byPlatformGroups = <String, Map<String, Map<String, Map<String, dynamic>>>>{};
    for (final platformEntry in byPlatform.entries) {
      final platformKey = platformEntry.key;
      final groups = byPlatformGroups.putIfAbsent(platformKey, () => {});
      for (final btEntry in platformEntry.value.entries) {
        final bt = btEntry.key;
        for (final groupEntry in btEntry.value.effectiveCustom.entries) {
          groups.putIfAbsent(groupEntry.key, () => {})[bt] = groupEntry.value;
        }
      }
    }
    final hasAnyCustom = byPlatformGroups.values.any((g) => g.isNotEmpty);
    if (hasAnyCustom) {
      buf.writeln();
      _writeCustomForOverride(buf, flavorKey, byPlatformGroups, spec);
    }

    buf.writeln('}');
  }

  // Every AnnPlatform arm falls into one of two buckets: THIS FLAVOR has no
  // entry under that platform at all (throw — querying a platform a flavor
  // was never configured for is a programming error, regardless of whether
  // the platform itself exists for the app), or the flavor exists there and
  // may or may not have a value for the specific field being resolved
  // (return the value, or return null).
  //
  // When two or more platforms resolve to the identical return expression
  // (text-equal, including 'return null;'), their arms are merged into one
  // `case A || B:` pattern instead of being repeated verbatim — and if every
  // platform agrees AND none of them need a throw arm, the whole switch
  // collapses to a single expression-bodied return. Purely a
  // generated-code-size/readability optimization; the resolved values are
  // unchanged either way.
  static void _throwOrNullSwitch(
    StringBuffer buf,
    String flavorKey,
    String methodName,
    core.AnnSpec spec,
    String? Function(String platformKey) valueFor,
  ) {
    final bodies = <String, String>{};
    for (final platformKey in ['android', 'ios', 'web', 'windows']) {
      if (!spec.flavorExistsOn(platformKey, flavorKey)) {
        bodies[platformKey] = 'throw StateError(\n'
            "  \"'$flavorKey'.$methodName(AnnPlatform.$platformKey): this flavor has no entry under app.$platformKey.flavor in annspec.yaml.\",\n"
            ');';
        continue;
      }
      final expr = valueFor(platformKey);
      bodies[platformKey] = 'return ${expr ?? 'null'};';
    }
    _writeCollapsedSwitch(buf, bodies);
  }

  // Groups platform keys whose generated bodies are text-identical into one
  // `case A || B || ...:` arm, in the fixed android/ios/web/windows order.
  // If a single group covers every platform present in [bodies] AND that
  // group's body is a plain `return <expr>;` (no throw), the switch is
  // skipped entirely and the caller gets just that one statement back —
  // the expression-bodied-method collapse. Each body's lines after the
  // first are re-indented to [indent] so a multi-line throw lines up under
  // whichever case/switch depth it lands at (top-level statement or nested
  // under a `case ...:` arm).
  static void _writeCollapsedSwitch(
    StringBuffer buf,
    Map<String, String> bodies, {
    String indent = '    ',
  }) {
    const order = ['android', 'ios', 'web', 'windows'];
    final groups = <String, List<String>>{};
    for (final platformKey in order) {
      final body = bodies[platformKey];
      if (body == null) continue;
      groups.putIfAbsent(body, () => []).add(platformKey);
    }
    String reindent(String body, String lineIndent) =>
        body.split('\n').join('\n$lineIndent');
    if (groups.length == 1) {
      final onlyBody = groups.keys.single;
      if (!onlyBody.startsWith('throw ')) {
        buf.writeln('$indent${reindent(onlyBody, indent)}');
        return;
      }
    }
    buf.writeln('${indent}switch (platform) {');
    for (final entry in groups.entries) {
      final pattern = entry.value.map((k) => 'AnnPlatform.$k').join(' || ');
      buf.writeln('$indent  case $pattern:');
      buf.writeln('$indent    ${reindent(entry.key, '$indent    ')}');
    }
    buf.writeln('$indent}');
  }

  // Backs the public existsOn([platform]) — a plain boolean, never a throw
  // arm, since this IS the presence check callers use to decide whether
  // it's safe to call nameFor/idFor/authFor/etc. for a platform they're not
  // sure this flavor targets. Reuses AnnSpec.flavorExistsOn, the same
  // canonical presence check that drives every other method's throw
  // condition (see _throwOrNullSwitch).
  static void _writeExistsOnOverride(StringBuffer buf, String flavorKey, core.AnnSpec spec) {
    final bodies = <String, String>{
      for (final platformKey in ['android', 'ios', 'web', 'windows'])
        platformKey: 'return ${spec.flavorExistsOn(platformKey, flavorKey)};',
    };
    buf.writeln('  @override bool existsOn([AnnPlatform? platform]) {');
    buf.writeln('    platform ??= AnnFlavor.platform;');
    _writeCollapsedSwitch(buf, bodies);
    buf.writeln('  }');
  }

  // Extends android/ios-only name resolution to web/windows (plan 036 fix
  // for the bug where a web-only flavor's real name was invisible to name
  // resolution — it silently fell back to the raw flavor key). Each
  // platform's flavor/defaults type is distinct (no shared base class in
  // the core model), so the per-platform name is precomputed directly
  // rather than routed through one generically-typed map.
  static void _writeNameForOverride(StringBuffer buf, String flavorKey, core.AnnSpec spec) {
    final android = spec.app.android?.flavors[flavorKey];
    final ios     = spec.app.ios?.flavors[flavorKey];
    final web     = spec.app.web?.flavors[flavorKey];
    final windows = spec.app.windows?.flavors[flavorKey];
    // _throwOrNullSwitch already throws before calling this for any platform
    // this flavor has no entry under (via AnnSpec.flavorExistsOn), so these
    // lookups only ever run for a platform this flavor genuinely exists on —
    // falling back to the platform default.name there is correct, not a
    // presence leak.
    final names = {
      'android': android?.name ?? spec.app.android?.defaults.name,
      'ios':     ios?.name ?? spec.app.ios?.defaults.name,
      'web':     web?.name ?? spec.app.web?.defaults.name,
      'windows': windows?.name ?? spec.app.windows?.defaults.name,
    };
    buf.writeln('  @override String? nameFor([AnnPlatform? platform]) {');
    buf.writeln('    platform ??= AnnFlavor.platform;');
    _throwOrNullSwitch(buf, flavorKey, 'nameFor', spec, (platformKey) {
      final name = names[platformKey];
      return name != null ? _str(name) : null;
    });
    buf.writeln('  }');
  }

  // Unifies the old androidId/iosId getters into one platform-scoped method,
  // extended to web/windows (neither had id-suffix output before, despite
  // the resolver already computing effectiveId for every platform).
  static void _writeIdForOverride(StringBuffer buf, String flavorKey, core.AnnSpec spec) {
    final androidPlatform = spec.app.android;
    final iosPlatform     = spec.app.ios;
    final webPlatform     = spec.app.web;
    final windowsPlatform = spec.app.windows;
    final android = androidPlatform?.flavors[flavorKey];
    final ios     = iosPlatform?.flavors[flavorKey];
    final web     = webPlatform?.flavors[flavorKey];
    final windows = windowsPlatform?.flavors[flavorKey];

    // _throwOrNullSwitch already throws before calling this for any platform
    // this flavor has no entry under (via AnnSpec.flavorExistsOn), so
    // computeId only ever runs for a platform this flavor genuinely exists
    // on — falling back to the platform's default.id there is correct.
    // flavor.id is a full override (mutually exclusive with idSuffix per
    // REQ-IDEN-00010); flavor.idSuffix appends to the platform default.id.
    String? computeId(dynamic flavor, String? defaultId) {
      if (flavor?.id != null) return flavor.id as String;
      if (defaultId == null) return null;
      final idSuffix = flavor?.idSuffix as String? ?? '';
      return idSuffix.isNotEmpty ? '$defaultId$idSuffix' : defaultId;
    }

    final ids = {
      'android': computeId(android, androidPlatform?.defaults.id),
      'ios':     computeId(ios, iosPlatform?.defaults.id),
      'web':     computeId(web, webPlatform?.defaults.id),
      'windows': computeId(windows, windowsPlatform?.defaults.id),
    };
    buf.writeln('  @override String? idFor([AnnPlatform? platform]) {');
    buf.writeln('    platform ??= AnnFlavor.platform;');
    _throwOrNullSwitch(buf, flavorKey, 'idFor', spec, (platformKey) {
      final id = ids[platformKey];
      return id != null ? _str(id) : null;
    });
    buf.writeln('  }');
  }

  // Reads .effectiveAuth (fully cascaded via the core resolver — flavor.bt ->
  // flavor -> default.bt -> default) instead of the old mirror's raw,
  // uncascaded flavor.buildTypes[bt]?.auth-only lookup (plan 035 STEP-2.2.a).
  // authFor(platform, buildType) collapses the old authRelease/authDebug
  // split into one method (plan 036) — buildType becomes a nested switch
  // rather than two near-duplicate generated methods. Platforms whose whole
  // nested switch resolves identically are grouped via _writeCollapsedSwitch.
  static void _writeAuthForOverride(
    StringBuffer buf,
    String flavorKey,
    Map<String, Map<String, core.ResolvedBuildOutput>> byPlatform,
    core.AnnSpec spec,
  ) {
    final bodies = <String, String>{};
    for (final platformKey in ['android', 'ios', 'web', 'windows']) {
      if (!spec.flavorExistsOn(platformKey, flavorKey)) {
        bodies[platformKey] = 'throw StateError(\n'
            "  \"'$flavorKey'.authFor(AnnPlatform.$platformKey, \$buildType): this flavor has no entry under app.$platformKey.flavor in annspec.yaml.\",\n"
            ');';
        continue;
      }
      final bt = StringBuffer();
      bt.writeln('switch (buildType) {');
      for (final key in ['release', 'debug']) {
        final auth = byPlatform[platformKey]?[key]?.effectiveAuth;
        if (auth != null) {
          bt.writeln("  case '$key': return AnnAuthConfig(");
          if (auth.clientId != null) bt.writeln("    clientId: '${_esc(auth.clientId!)}',");
          if (auth.reversedClientId != null) bt.writeln("    reversedClientId: '${_esc(auth.reversedClientId!)}',");
          bt.writeln('  );');
        } else {
          bt.writeln("  case '$key': return null;");
        }
      }
      // profile / any other build type falls back to release's value, same
      // convention as custom()'s build-type collapsing below.
      final releaseAuth = byPlatform[platformKey]?['release']?.effectiveAuth;
      if (releaseAuth != null) {
        bt.writeln('  default: return AnnAuthConfig(');
        if (releaseAuth.clientId != null) bt.writeln("    clientId: '${_esc(releaseAuth.clientId!)}',");
        if (releaseAuth.reversedClientId != null) bt.writeln("    reversedClientId: '${_esc(releaseAuth.reversedClientId!)}',");
        bt.writeln('  );');
      } else {
        bt.writeln('  default: return null;');
      }
      bt.write('}');
      bodies[platformKey] = bt.toString();
    }
    buf.writeln('  @override AnnAuthConfig? authFor([AnnPlatform? platform, String? buildType]) {');
    buf.writeln('    platform ??= AnnFlavor.platform;');
    buf.writeln('    buildType ??= AnnFlavor.buildType;');
    _writeCollapsedSwitch(buf, bodies);
    buf.writeln('  }');
  }

  // Inlined directly on the flavor's own config class — no separate
  // delegate class (plan 036 removed the old _XFirebase class, which only
  // ever existed so the old top-level flavorFirebaseOptions* functions had
  // something static to call into).
  static void _writeFirebaseOptionsForOverride(
    StringBuffer buf,
    String flavorKey,
    Map<String, Map<String, core.ResolvedBuildOutput>> byPlatform,
    core.AnnSpec spec,
  ) {
    final bodies = <String, String>{};
    for (final platformKey in ['android', 'ios', 'web', 'windows']) {
      if (!spec.flavorExistsOn(platformKey, flavorKey)) {
        bodies[platformKey] = 'throw StateError(\n'
            "  \"'$flavorKey'.firebaseOptionsFor(AnnPlatform.$platformKey, \$buildType): this flavor has no entry under app.$platformKey.flavor in annspec.yaml.\",\n"
            ');';
        continue;
      }
      final bt = StringBuffer();
      bt.writeln('switch (buildType) {');
      for (final key in ['release', 'debug']) {
        final fb = byPlatform[platformKey]?[key]?.effectiveFirebase;
        if (fb != null) {
          final alias = _fbAlias(flavorKey, platformKey, key);
          bt.writeln("  case '$key': return $alias.DefaultFirebaseOptions.currentPlatform;");
        } else {
          bt.writeln("  case '$key': return null;");
        }
      }
      final releaseFb = byPlatform[platformKey]?['release']?.effectiveFirebase;
      if (releaseFb != null) {
        final alias = _fbAlias(flavorKey, platformKey, 'release');
        bt.writeln("  default: return $alias.DefaultFirebaseOptions.currentPlatform;");
      } else {
        bt.writeln('  default: return null;');
      }
      bt.write('}');
      bodies[platformKey] = bt.toString();
    }
    buf.writeln('  @override FirebaseOptions? firebaseOptionsFor([AnnPlatform? platform, String? buildType]) {');
    buf.writeln('    platform ??= AnnFlavor.platform;');
    buf.writeln('    buildType ??= AnnFlavor.buildType;');
    _writeCollapsedSwitch(buf, bodies);
    buf.writeln('  }');
  }

  // Fixes a cross-platform data-loss bug (plan 036): the previous
  // implementation merged effectiveCustom across every platform into one
  // Map<group, Map<buildType, value>>, discarding which platform each value
  // came from — two platforms configuring different values for the same
  // group+buildType meant whichever was iterated last silently won.
  static void _writeCustomForOverride(
    StringBuffer buf,
    String flavorKey,
    Map<String, Map<String, Map<String, Map<String, dynamic>>>> byPlatformGroups,
    core.AnnSpec spec,
  ) {
    final bodies = <String, String>{};
    for (final platformKey in ['android', 'ios', 'web', 'windows']) {
      if (!spec.flavorExistsOn(platformKey, flavorKey)) {
        bodies[platformKey] = 'throw StateError(\n'
            "  \"'$flavorKey'.customFor(AnnPlatform.$platformKey, \$group, \$buildType): this flavor has no entry under app.$platformKey.flavor in annspec.yaml.\",\n"
            ');';
        continue;
      }
      // Flavor exists on this platform but simply has no custom: block —
      // this is the "field not set" case, distinct from flavor-absence
      // above, and correctly stays null rather than throwing.
      final groups = byPlatformGroups[platformKey] ?? {};
      if (groups.isEmpty) {
        bodies[platformKey] = 'return null;';
        continue;
      }
      final gr = StringBuffer();
      gr.writeln('switch (group) {');
      for (final groupEntry in groups.entries) {
        final groupName = groupEntry.key;
        final byBt = groupEntry.value;
        gr.writeln("  case '${_esc(groupName)}': return switch (buildType) {");
        // 'debug' and 'release' always get an explicit case. Any other build
        // type (currently just 'profile') only gets one when its resolved
        // value actually differs from release's — an unconfigured build type
        // that merely cascaded from release is never spelled out, it just
        // falls through to the release value via the `_ =>` arm below.
        final releaseValue = byBt['release'];
        for (final btEntry in byBt.entries) {
          final isStandard = btEntry.key == 'debug' || btEntry.key == 'release';
          final matchesRelease = releaseValue != null && _dartMap(btEntry.value) == _dartMap(releaseValue);
          if (!isStandard && matchesRelease) continue;
          gr.writeln("    '${btEntry.key}' => AnnCustomGroup(${_dartMap(btEntry.value)}),");
        }
        // fallback: release if present, else whatever's available
        final fallback = releaseValue ?? byBt.values.first;
        gr.writeln("    _ => AnnCustomGroup(${_dartMap(fallback)}),");
        gr.writeln('  };');
      }
      gr.writeln('  default: return null;');
      gr.write('}');
      bodies[platformKey] = gr.toString();
    }
    buf.writeln('  @override AnnCustomGroup? customFor(String group, [AnnPlatform? platform, String? buildType]) {');
    buf.writeln('    platform ??= AnnFlavor.platform;');
    buf.writeln('    buildType ??= AnnFlavor.buildType;');
    _writeCollapsedSwitch(buf, bodies);
    buf.writeln('  }');
  }

  // flavorKey -> platformKey -> buildType -> resolved output. Built via the
  // batch resolver (resolveAndroid/resolveIos/resolveWeb/resolveWindows) so
  // every value read downstream is fully cascaded, not a raw/partial one.
  static Map<String, Map<String, Map<String, core.ResolvedBuildOutput>>> _collectFlavors(
    core.AnnSpec spec,
  ) {
    final result = <String, Map<String, Map<String, core.ResolvedBuildOutput>>>{};
    const buildTypes = ['debug', 'release', 'profile'];

    void collect(String platformKey, Map<String, core.ResolvedFlavor> resolved) {
      for (final entry in resolved.entries) {
        result.putIfAbsent(entry.key, () => {})[platformKey] = entry.value.byBuildType;
      }
    }

    if (spec.app.android != null) {
      collect('android', core.AnnSpecResolver.resolveAndroid(spec.app.android!, buildTypes: buildTypes));
    }
    if (spec.app.ios != null) {
      collect('ios', core.AnnSpecResolver.resolveIos(spec.app.ios!, buildTypes: buildTypes));
    }
    if (spec.app.web != null) {
      collect('web', core.AnnSpecResolver.resolveWeb(spec.app.web!, buildTypes: buildTypes));
    }
    if (spec.app.windows != null) {
      collect('windows', core.AnnSpecResolver.resolveWindows(spec.app.windows!, buildTypes: buildTypes));
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

  // Escape backslashes first, then quotes — otherwise the backslash inserted
  // by the quote-escape below would itself get re-escaped by a naive
  // single-pass replace, corrupting values that legitimately contain `\`.
  static String _esc(String s) =>
      s.replaceAll('\\', '\\\\').replaceAll("'", "\\'");

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
