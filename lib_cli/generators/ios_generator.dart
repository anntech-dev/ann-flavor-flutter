import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';
import '../vendor/ann_flavor_core/ann_flavor_core.dart' as core;
import '../plist/plist_codec.dart';

const _annHeader = '# Added by ann_flutter_flavor — multi-flavor iOS build configuration';

// Must run from post_integrate, not post_install — post_install fires before
// CocoaPods has integrated/saved the user's Xcode project, so build phases
// annai_ios_podfile_setup injects there are silently lost regardless of which
// project they're added to (DEF-061, ann-flavor-tooling#61).
const _postIntegrateBlock = '\n'
    'post_integrate do |installer|\n'
    '  # Added by ann_flutter_flavor — wires per-flavor Firebase config into the\n'
    '  # Xcode build. Must stay in post_integrate, not post_install — see\n'
    '  # https://github.com/anntech-dev/ann-flavor-tooling/issues/61\n'
    '  annai_ios_podfile_setup(installer)\n'
    'end\n';

/// Handles iOS wiring: CocoaPods plugin, per-flavor xcconfig files, per-flavor
/// Info.plist generation. Everything under `ios/ann/` is fully disposable —
/// delete-and-regenerate on every `sync`, not patched in place (plan 035
/// Solution §1) — so a changed spec value always propagates.
class IosGenerator {
  static Future<void> generate(String projectRoot, core.AnnSpec spec) async {
    final iosDir = Directory(p.join(projectRoot, 'ios'));
    if (!iosDir.existsSync()) {
      print('  ⚠ No ios/ directory found — skipping iOS wiring.');
      return;
    }

    _patchPodfile(iosDir);
    _ensurePostIntegrateHook(iosDir);

    final iosPlatform = spec.app.ios;
    if (iosPlatform == null || iosPlatform.flavors.isEmpty) {
      print('  ✓ No iOS flavors defined — skipping xcconfig/Info.plist generation.');
      return;
    }

    final sdkIos = iosPlatform.defaults.sdk?.ios;
    if (sdkIos != null) {
      _ensurePlatformLine(iosDir, sdkIos);
    }

    if (iosPlatform.defaults.sdk?.swiftVersion != null) {
      await _preflightSwiftVersion(projectRoot);
    }

    final annDir = Directory(p.join(iosDir.path, 'ann'));
    _generateXcconfigs(annDir, iosPlatform);
    final hasAdmob = iosPlatform.defaults.admob?.gmsAdsId != null ||
        iosPlatform.flavors.values.any((f) => f.admob?.gmsAdsId != null);
    _ensureXcconfigBackedKeys(iosDir, hasAdmob);
    _generateInfoPlists(projectRoot, iosDir, annDir, iosPlatform);
    _generateEntitlements(projectRoot, iosDir, annDir, iosPlatform);
  }

  // Fixes a real pod-install failure that happens during CocoaPods' own
  // dependency-analysis phase, BEFORE any Podfile hook (including
  // post_integrate) ever gets a chance to run: a project whose SWIFT_VERSION
  // resolves inconsistently across configuration names fails analysis
  // outright, so ann-flavor-cocoapods's post_integrate-based fix
  // (configure_build_settings) never runs for a project's first-ever
  // `pod install`. Calling ann-ios-flavorize's `preflight` subcommand here —
  // a separate process that runs before `pod install` is ever invoked, not
  // gated by any CocoaPods lifecycle — fixes the .xcodeproj directly ahead
  // of time, so even a first-ever `pod install` succeeds.
  static Future<void> _preflightSwiftVersion(String projectRoot) async {
    // CocoaPods' Xcodeproj gem calls String#unicode_normalize while reading
    // the .xcodeproj; if the parent process's locale isn't UTF-8 (common
    // outside an interactive shell, e.g. a bare non-UTF-8 macOS default),
    // that raises "invalid byte sequence in US-ASCII" — confirmed as the
    // actual failure mode against a real project. Force a UTF-8 locale on
    // this subprocess, matching the same fix already applied to every
    // CocoaPods/Xcodeproj-touching subprocess call in the Studio plugin
    // (AnnaiUpgradeAction.kt, AnnaiSyncPackagesAction.kt).
    final result = await Process.run(
      'bundle',
      ['exec', 'ann-ios-flavorize', 'preflight', '--project', projectRoot],
      workingDirectory: projectRoot,
      runInShell: true,
      environment: {'LANG': 'en_US.UTF-8', 'LC_ALL': 'en_US.UTF-8'},
    );
    if (result.exitCode != 0) {
      print('  ⚠ ann-ios-flavorize preflight failed (continuing sync):');
      print('    ${result.stderr.toString().trim()}'.trim());
      return;
    }
    print('  ✓ Pre-flighted SWIFT_VERSION consistency in ios/*.xcodeproj.');
  }

  // ── CocoaPods ──────────────────────────────────────────────────────────────

  static void _patchPodfile(Directory iosDir) {
    final file = File(p.join(iosDir.path, 'Podfile'));
    if (!file.existsSync()) {
      print('  ⚠ ios/Podfile not found — skipping iOS wiring.');
      return;
    }

    var content = file.readAsStringSync();
    if (content.contains(_annHeader)) {
      print('  ✓ ios/Podfile already has ANN CocoaPods requires.');
      return;
    }

    // 'annai-flutter-flavor' is an old, pre-rename alias that just forwards
    // to 'ann_flavor_cocoapods' internally (same code, loaded twice under two
    // names) — deliberately not written here anymore so it doesn't linger in
    // fresh Podfiles going forward. Removed by hand from already-patched
    // Podfiles is fine; this guard (_annHeader presence) never re-patches an
    // existing file, so it won't come back on a later sync/upgrade.
    const header = "$_annHeader\n"
        "require 'ann-flavor-cocoapods'\n";
    content = header + content;
    file.writeAsStringSync(content);
    print('  ✓ Patched ios/Podfile with ANN CocoaPods requires.');
  }

  // Appends a post_integrate block calling annai_ios_podfile_setup when the
  // Podfile doesn't already call it from anywhere — insertion only, no
  // migration: an existing call already present in a post_install block (the
  // pre-#61 broken pattern) is left as-is rather than moved automatically,
  // since safely relocating a call out of a hand-authored post_install block
  // that may interleave arbitrary other plugins' hooks isn't reliable via a
  // generic text patch. Projects with that pattern need a one-time manual fix
  // — see https://github.com/anntech-dev/ann-flavor-tooling/issues/61.
  static void _ensurePostIntegrateHook(Directory iosDir) {
    final file = File(p.join(iosDir.path, 'Podfile'));
    if (!file.existsSync()) return;

    final content = file.readAsStringSync();
    if (content.contains('annai_ios_podfile_setup')) {
      print('  ✓ ios/Podfile already calls annai_ios_podfile_setup.');
      return;
    }

    file.writeAsStringSync(content.trimRight() + '\n' + _postIntegrateBlock);
    print('  ✓ Added post_integrate hook to ios/Podfile for Firebase config wiring.');
  }

  // Fixes a real pod-install failure: Flutter's stock Podfile ships
  // `platform :ios` commented out, so CocoaPods auto-assigns iOS 15.0 to the
  // Runner target and refuses to proceed with a "please specify a platform"
  // error. This tooling never corrected it (plan 035 hit and hand-fixed this
  // twice during real-project verification, never in code — see
  // docs/03-planning/features/035-ios-flavor-architecture-redesign.md lines
  // 856-859, 1024-1026). Only runs when sdk.ios is set — no regression for
  // projects that don't opt into this field.
  static void _ensurePlatformLine(Directory iosDir, String iosVersion) {
    final file = File(p.join(iosDir.path, 'Podfile'));
    if (!file.existsSync()) return;

    final content = file.readAsStringSync();
    final activeLine = RegExp(r"^\s*platform :ios,\s*'[\d.]+'", multiLine: true);
    final commentedLine = RegExp(r"^\s*#\s*platform :ios,\s*'[\d.]+'", multiLine: true);
    final newLine = "platform :ios, '$iosVersion'";

    String updated;
    if (activeLine.hasMatch(content)) {
      updated = content.replaceFirst(activeLine, newLine);
    } else if (commentedLine.hasMatch(content)) {
      updated = content.replaceFirst(commentedLine, newLine);
    } else {
      updated = '$newLine\n$content';
    }

    if (updated == content) {
      print('  ✓ ios/Podfile platform :ios already set to $iosVersion.');
      return;
    }
    file.writeAsStringSync(updated);
    print('  ✓ Set ios/Podfile platform :ios to $iosVersion.');
  }

  // ── xcconfig generation ────────────────────────────────────────────────────

  static void _generateXcconfigs(Directory annDir, core.IosPlatform platform) {
    final xcconfigDir = Directory(p.join(annDir.path, 'xcconfig'));
    // Delete-and-regenerate: a changed/removed spec value must always
    // propagate, which an additive-only patch can never guarantee (plan 035
    // finding #3). Safe because everything under ios/ann/ is documented as
    // fully disposable.
    if (xcconfigDir.existsSync()) xcconfigDir.deleteSync(recursive: true);
    xcconfigDir.createSync(recursive: true);

    for (final entry in platform.flavors.entries) {
      final flavorKey = entry.key;
      final flavor = entry.value;

      for (final bt in _buildTypeKeys(platform, flavor)) {
        final resolved = core.AnnSpecResolver.resolveIosFlavor(flavor, platform.defaults, bt);
        _writeXcconfig(xcconfigDir, flavorKey, bt, resolved, platform.defaults.sdk);
      }
    }
  }

  static void _writeXcconfig(
    Directory xcconfigDir,
    String flavorKey,
    String buildType,
    core.ResolvedBuildOutput resolved,
    core.IosSdk? sdk,
  ) {
    final fileName = '$flavorKey${_capitalize(buildType)}.xcconfig';
    final file = File(p.join(xcconfigDir.path, fileName));

    // Variables this xcconfig declares — all fully resolved (cascade already
    // applied by the core resolver, including the build-type suffix on the
    // bundle ID). ASSETCATALOG_COMPILER_APPICON_NAME is set unconditionally
    // here rather than patched in by a separate step, since this file is
    // deleted and regenerated on every sync (STEP-2.2) — a separate
    // after-the-fact patch would be silently wiped on the next sync. The
    // icon set itself may not exist yet (icon generation is a separate,
    // explicit step, not part of sync — see the comment in
    // sync_command.dart) but referencing it here is harmless; Xcode only
    // resolves the name at build time, when the icon set is expected to
    // already have been generated.
    final vars = <String, String>{
      // annspec.yaml's `env:` block goes first so every key below (all
      // derived from other, more specific annspec.yaml fields) always wins
      // on collision — `env:` is an additive escape hatch for arbitrary
      // build settings, not a way to override the tool's own reserved keys
      // or duplicate a value that already has its own dedicated field (e.g.
      // REVERSED_CLIENT_ID below, derived from auth.reversedClientId — never
      // ask the user to also set env.REVERSED_CLIENT_ID with the same value).
      ...resolved.effectiveEnv,
      'PRODUCT_BUNDLE_IDENTIFIER': resolved.effectiveId,
      'APP_NAME': resolved.effectiveName,
      'FLUTTER_BUILD_NAME': resolved.effectiveVersionName,
      'FLUTTER_BUILD_NUMBER': resolved.effectiveVersionCode?.toString() ?? '',
      'ASSETCATALOG_COMPILER_APPICON_NAME': '${_capitalize(flavorKey)}AppIcon',
      if (resolved.effectiveGmsAdsId != null)
        'GAD_APPLICATION_IDENTIFIER': resolved.effectiveGmsAdsId!,
      if (resolved.effectiveAuth?.reversedClientId != null)
        'REVERSED_CLIENT_ID': resolved.effectiveAuth!.reversedClientId!,
      if (sdk?.ios != null) 'IPHONEOS_DEPLOYMENT_TARGET': sdk!.ios!,
      if (sdk?.swiftVersion != null) 'SWIFT_VERSION': sdk!.swiftVersion!,
    };

    final isDebug = buildType.toLowerCase() == 'debug';
    final baseInclude = isDebug ? 'Debug' : 'Release';
    final lines = [
      '// Generated by ann_flutter_flavor — do not edit by hand, this file is',
      '// regenerated (deleted and recreated) on every `sync`.',
      '#include? "../../Pods/Target Support Files/Pods-Runner/Pods-Runner.${buildType.toLowerCase()}-$flavorKey.xcconfig"',
      '#include "../../Flutter/$baseInclude.xcconfig"',
      '#include "../../Flutter/Generated.xcconfig"',
      '',
      ...vars.entries.map((e) => '${e.key}=${e.value}'),
    ];
    file.writeAsStringSync(lines.join('\n') + '\n');
    print('  ✓ Generated ios/ann/xcconfig/$fileName');
  }

  // ── Runner/Info.plist repair (plan 038) ─────────────────────────────────────

  /// The 6 Info.plist keys this tool's generated xcconfig already provides a
  /// correct per-flavor value for, via Xcode's own build-setting substitution
  /// (resolved before Info.plist is read — no plist-level override needed).
  /// Confirmed against a real project (ledger_in): Runner/Info.plist already
  /// references $(APP_NAME)/$(PRODUCT_BUNDLE_IDENTIFIER)/$(FLUTTER_BUILD_NAME)/
  /// $(FLUTTER_BUILD_NUMBER)/$(GAD_APPLICATION_IDENTIFIER) correctly out of
  /// the box in a fresh/well-maintained project — this method exists to
  /// REPAIR drift (a renamed or deleted placeholder), not to establish these
  /// references for the first time in the common case (plan 038 Solution §1a).
  static const _xcconfigBackedKeys = {
    'CFBundleDisplayName': r'$(APP_NAME)',
    'CFBundleName': r'$(APP_NAME)',
    'CFBundleIdentifier': r'$(PRODUCT_BUNDLE_IDENTIFIER)',
    'CFBundleShortVersionString': r'$(FLUTTER_BUILD_NAME)',
    'CFBundleVersion': r'$(FLUTTER_BUILD_NUMBER)',
  };
  static const _admobBackedKey = 'GADApplicationIdentifier';
  static const _admobPlaceholder = r'$(GAD_APPLICATION_IDENTIFIER)';

  /// Patches `ios/Runner/Info.plist` in place, narrowly, for the 6 keys
  /// above — adds a key if missing, rewrites it if present with a literal or
  /// differently-named placeholder, leaves it untouched (byte-identical, no
  /// spurious sync diff) if already correct. Never removes a key: this file
  /// is developer-owned (unlike everything under `ios/ann/`, which is
  /// delete-and-regenerate) — this tool only ever adds or repairs the 6
  /// known xcconfig-backed placeholders, it never deletes a key the
  /// developer may have added for their own reasons.
  static void _ensureXcconfigBackedKeys(Directory iosDir, bool hasAdmob) {
    final plistFile = File(p.join(iosDir.path, 'Runner', 'Info.plist'));
    if (!plistFile.existsSync()) return;

    final values = PlistCodec.decode(plistFile.readAsStringSync());
    var changed = false;

    _xcconfigBackedKeys.forEach((key, placeholder) {
      if (values[key] != placeholder) {
        values[key] = placeholder;
        changed = true;
      }
    });

    if (hasAdmob && values[_admobBackedKey] != _admobPlaceholder) {
      values[_admobBackedKey] = _admobPlaceholder;
      changed = true;
    }

    if (!changed) return;
    plistFile.writeAsStringSync(PlistCodec.encode(values));
    print('  ✓ Repaired ios/Runner/Info.plist (xcconfig-backed key references)');
  }

  // ── Info.plist generation ──────────────────────────────────────────────────

  static void _generateInfoPlists(
    String projectRoot,
    Directory iosDir,
    Directory annDir,
    core.IosPlatform platform,
  ) {
    final infoDir = Directory(p.join(annDir.path, 'Info'));
    // Delete-and-regenerate, same rationale as xcconfig above.
    if (infoDir.existsSync()) infoDir.deleteSync(recursive: true);
    infoDir.createSync(recursive: true);

    // Runner/Info.plist is no longer merged in here — it becomes the base
    // layer of a build-time merge (plan 038), composed by a new
    // ann-flavor-cocoapods run-script phase, not this generator. This file
    // now contains only what annspec.yaml's info_plist: cascade actually
    // resolves for this flavor — no stock/shared keys, no CFBundleDisplayName
    // /CFBundleIdentifier/CFBundleShortVersionString/CFBundleVersion/
    // GADApplicationIdentifier literals. Those keys are already correctly
    // build-setting-driven via Runner/Info.plist's own $(VAR) placeholders +
    // the generated xcconfig (see _ensureXcconfigBackedKeys, which keeps
    // those placeholders correct) — baking resolved literals here was pure
    // duplication of a mechanism that already works.
    //
    // Plugin-contributed content (plan 041) is written to its OWN file,
    // ios/ann/Info/merged/plugin-contributions.plist, project-wide (not
    // per-flavor) -- never folded into Info-<flavor>-<buildType>.plist.
    // Keeping it separate preserves that file's meaning as "exactly what
    // annspec.yaml's info_plist: cascade resolves for this flavor",
    // inspectable on its own. Lives under merged/ (not committed -- see
    // ios/ann/.gitignore's */merged/ wildcard) rather than a sibling of the
    // flavor files, because -- unlike those, which are a pure function of
    // annspec.yaml -- this file's content depends on what plugin packages
    // are actually resolved on disk (.flutter-plugins-dependencies), which
    // varies by developer/environment and has no business being committed.
    // ann-flavor-cocoapods reads it as a plain file at pod-install time, as
    // a distinct merge layer between Runner/Info.plist (base) and the
    // flavor delta -- Ruby never needs to know about plugins or
    // .flutter-plugins-dependencies.
    final pluginContributed = _mergePluginContributions(
      _discoverPluginContributions(projectRoot, 'ann-Info.plist'),
    );
    final mergedDir = Directory(p.join(infoDir.path, 'merged'));
    final pluginsFile = File(p.join(mergedDir.path, 'plugin-contributions.plist'));
    if (pluginContributed.isNotEmpty) {
      mergedDir.createSync(recursive: true);
      pluginsFile.writeAsStringSync(PlistCodec.encode(pluginContributed));
      print('  ✓ Generated ios/ann/Info/merged/plugin-contributions.plist');
    }

    for (final entry in platform.flavors.entries) {
      final flavorKey = entry.key;
      final flavor = entry.value;

      // Resolved per build type, not just once against a hardcoded 'release'
      // — annspec.yaml's info_plist: cascade is valid at build_types.<bt>
      // level (REQ-FLVR-00110), so a debug-specific override must actually
      // reach a real file; the same buildTypeKeys set _generateXcconfigs
      // already uses (always debug/release, plus any custom build_types).
      for (final bt in _buildTypeKeys(platform, flavor)) {
        final levels = core.IosResolution.infoPlistLevels(platform, flavorKey, bt);
        final resolvedLevels = levels
            .map((level) => level == null ? null : _resolveLevel(projectRoot, level))
            .toList();
        final merged = core.IosResolution.mergeInfoPlist(resolvedLevels);

        // Opt-in, same treatment as entitlements generation — no file at all
        // when this flavor/build-type combination has no info_plist: cascade.
        if (merged.isEmpty) continue;

        final fileName = 'Info-$flavorKey-$bt.plist';
        final outFile = File(p.join(infoDir.path, fileName));
        outFile.writeAsStringSync(PlistCodec.encode(merged));
        print('  ✓ Generated ios/ann/Info/$fileName');
      }
    }
  }

  /// The build types to resolve `info_plist:`/`entitlements:` cascades
  /// against for one flavor — always at least debug + release, plus any
  /// custom build_types declared on either the flavor or platform defaults.
  /// Same set _generateXcconfigs already resolves against, kept consistent
  /// so a build type either has both a Debug-<flavor><Bt>.xcconfig entry and
  /// (when relevant) an Info-<flavor>-<bt>.plist, or neither.
  static Set<String> _buildTypeKeys(core.IosPlatform platform, core.IosFlavor flavor) => {
        'debug',
        'release',
        ...flavor.buildTypes.keys,
        ...platform.defaults.buildTypes.keys,
      };

  /// Discovers every active iOS plugin's contributed `ios/ann-Info.plist`
  /// and/or `ios/ann-Runner.entitlements` — a plugin-authoring convention
  /// (not an annspec.yaml field) letting a plugin package ship default
  /// Info.plist/entitlements content its consumers would otherwise have to
  /// copy-paste by hand (e.g. ann_ads needs NSUserTrackingUsageDescription
  /// for App Tracking Transparency — a real ledger crash,
  /// "Namespace TCC, Code 0", traced to this key never being declared
  /// anywhere). Reads `.flutter-plugins-dependencies` (written by
  /// `flutter pub get`, always fresh by the time `sync` runs) rather than
  /// re-resolving pub dependencies itself.
  ///
  /// Returns a map of plugin name -> parsed content, for exactly the
  /// plugins that actually ship the given [fileName] — most plugins
  /// contribute nothing, and are absent from the result entirely (not
  /// present with an empty map), so a key-collision check downstream only
  /// ever sees real contributors.
  static Map<String, Map<String, dynamic>> _discoverPluginContributions(
    String projectRoot,
    String fileName,
  ) {
    final depsFile = File(p.join(projectRoot, '.flutter-plugins-dependencies'));
    if (!depsFile.existsSync()) return {};

    Map<String, dynamic> deps;
    try {
      deps = jsonDecode(depsFile.readAsStringSync()) as Map<String, dynamic>;
    } catch (_) {
      // Malformed or unreadable -- non-fatal, same tolerance as a missing
      // file. sync's own later steps (flutter pub get itself) are the
      // authority on this file's validity, not this generator.
      return {};
    }

    final iosPlugins = (deps['plugins'] as Map<String, dynamic>?)?['ios'] as List<dynamic>?;
    if (iosPlugins == null) return {};

    final result = <String, Map<String, dynamic>>{};
    for (final entry in iosPlugins) {
      final map = entry as Map<String, dynamic>;
      if (map['native_build'] == false) continue;
      final name = map['name'] as String?;
      final pluginPath = map['path'] as String?;
      if (name == null || pluginPath == null) continue;

      final contributedFile = File(p.join(pluginPath, 'ios', fileName));
      if (!contributedFile.existsSync()) continue;

      try {
        result[name] = PlistCodec.decode(contributedFile.readAsStringSync());
      } catch (e) {
        print('  ⚠ Plugin "$name" ships $fileName but it could not be parsed as a '
            'plist ($e) -- skipping this plugin\'s contribution.');
      }
    }
    return result;
  }

  /// Merges per-plugin contributions (from [_discoverPluginContributions])
  /// into a single map, lowest priority of all -- annspec.yaml always wins
  /// on collision (this map is prepended, least-specific-first, ahead of
  /// the 4 existing annspec.yaml-driven levels). A real collision between
  /// two DIFFERENT plugins (not annspec.yaml vs. a plugin, which is always
  /// resolvable) is resolved alphabetically-first-wins, for determinism,
  /// and logged -- this should be rare in practice.
  static Map<String, dynamic> _mergePluginContributions(
    Map<String, Map<String, dynamic>> contributions,
  ) {
    if (contributions.isEmpty) return {};
    final orderedNames = contributions.keys.toList()..sort();
    final merged = <String, dynamic>{};
    final owner = <String, String>{};
    for (final name in orderedNames) {
      contributions[name]!.forEach((key, value) {
        if (owner.containsKey(key)) {
          print('  ⚠ Both plugins "${owner[key]}" and "$name" contribute the '
              'Info.plist/entitlements key "$key" -- "${owner[key]}" (first '
              'alphabetically) wins.');
          return;
        }
        merged[key] = value;
        owner[key] = name;
      });
    }
    return merged;
  }

  /// Resolves one raw `info_plist` level to a `Map<String, dynamic>`: an
  /// inline map is used as-is; a file-path string is read from disk relative
  /// to the project root (matching the `service_account`/`config_file`
  /// relative-path convention elsewhere in this schema) and parsed as YAML
  /// (`.yaml`/`.yml`) or plist XML (`.plist`).
  static Map<String, dynamic> _resolveLevel(String projectRoot, core.InfoPlistValue level) {
    if (level.values != null) return level.values!;

    final path = level.path!;
    final file = File(p.isAbsolute(path) ? path : p.join(projectRoot, path));
    if (!file.existsSync()) {
      print('  ⚠ info_plist file not found: ${file.path} — skipping this level.');
      return {};
    }

    final content = file.readAsStringSync();
    if (path.endsWith('.yaml') || path.endsWith('.yml')) {
      final doc = loadYaml(content);
      return Map<String, dynamic>.from(doc as Map);
    }
    if (path.endsWith('.plist')) {
      return PlistCodec.decode(content);
    }
    print('  ⚠ Unsupported info_plist file extension: $path — expected .yaml/.yml/.plist. Skipping.');
    return {};
  }

  // ── Entitlements generation ─────────────────────────────────────────────────

  /// Mirrors `_generateInfoPlists` exactly (post plan 038): the generated file
  /// contains only the resolved `entitlements:` cascade for that flavor — no
  /// `Runner.entitlements` content copied in. Runner.entitlements is instead
  /// the base layer of a build-time merge, composed by a new
  /// ann-flavor-cocoapods run-script phase (plan 039), not this generator.
  static void _generateEntitlements(
    String projectRoot,
    Directory iosDir,
    Directory annDir,
    core.IosPlatform platform,
  ) {
    final entitlementsDir = Directory(p.join(annDir.path, 'Entitlements'));
    // Delete-and-regenerate, same rationale as xcconfig/Info.plist above.
    if (entitlementsDir.existsSync()) entitlementsDir.deleteSync(recursive: true);

    // Plugin-contributed content (plan 041) is written to its OWN file,
    // ios/ann/Entitlements/merged/plugin-contributions.entitlements,
    // project-wide (not per-flavor) -- see _generateInfoPlists' identical
    // pattern and rationale (keeps <flavor>-<buildType>.entitlements
    // meaning exactly what annspec.yaml's entitlements: cascade resolves,
    // nothing else; lives under merged/, not committed, because unlike the
    // flavor files this depends on plugin packages resolved on disk).
    final pluginContributed = _mergePluginContributions(
      _discoverPluginContributions(projectRoot, 'ann-Runner.entitlements'),
    );

    // Opt-in at the directory level: skip entirely only when NEITHER
    // annspec.yaml nor any active plugin contributes anything -- a plugin
    // shipping ios/ann-Runner.entitlements with no annspec.yaml
    // entitlements: cascade anywhere must still generate output, or its
    // contribution would be silently dropped.
    if (!_anyFlavorHasEntitlements(platform) && pluginContributed.isEmpty) return;
    entitlementsDir.createSync(recursive: true);

    if (pluginContributed.isNotEmpty) {
      final mergedDir = Directory(p.join(entitlementsDir.path, 'merged'));
      mergedDir.createSync(recursive: true);
      File(p.join(mergedDir.path, 'plugin-contributions.entitlements'))
          .writeAsStringSync(PlistCodec.encode(pluginContributed));
      print('  ✓ Generated ios/ann/Entitlements/merged/plugin-contributions.entitlements');
    }

    for (final entry in platform.flavors.entries) {
      final flavorKey = entry.key;
      final flavor = entry.value;

      // Resolved per build type, not just once against a hardcoded
      // 'release' -- see _generateInfoPlists' identical comment.
      for (final bt in _buildTypeKeys(platform, flavor)) {
        final levels = core.IosResolution.entitlementsLevels(platform, flavorKey, bt);
        final resolvedLevels = levels
            .map((level) => level == null ? null : _resolveEntitlementsLevel(projectRoot, level))
            .toList();
        final merged = core.IosResolution.mergeEntitlements(resolvedLevels);

        // Opt-in per flavor/build-type too, same treatment as Info.plist —
        // no file for a combination whose own cascade is empty, even if
        // others have one.
        if (merged.isEmpty) continue;

        final fileName = '$flavorKey-$bt.entitlements';
        final outFile = File(p.join(entitlementsDir.path, fileName));
        outFile.writeAsStringSync(PlistCodec.encode(merged));
        print('  ✓ Generated ios/ann/Entitlements/$fileName');
      }
    }
  }

  static bool _anyFlavorHasEntitlements(core.IosPlatform platform) {
    if (platform.defaults.entitlements != null) return true;
    for (final flavor in platform.flavors.values) {
      if (flavor.entitlements != null) return true;
      if (flavor.buildTypes.values.any((bt) => bt.entitlements != null)) return true;
    }
    return platform.defaults.buildTypes.values.any((bt) => bt.entitlements != null);
  }

  /// Resolves one raw `entitlements` level to a `Map<String, dynamic>` — same
  /// rules as `_resolveLevel` for `info_plist`.
  static Map<String, dynamic> _resolveEntitlementsLevel(String projectRoot, core.EntitlementsValue level) {
    if (level.values != null) return level.values!;

    final path = level.path!;
    final file = File(p.isAbsolute(path) ? path : p.join(projectRoot, path));
    if (!file.existsSync()) {
      print('  ⚠ entitlements file not found: ${file.path} — skipping this level.');
      return {};
    }

    final content = file.readAsStringSync();
    if (path.endsWith('.yaml') || path.endsWith('.yml')) {
      final doc = loadYaml(content);
      return Map<String, dynamic>.from(doc as Map);
    }
    if (path.endsWith('.plist')) {
      return PlistCodec.decode(content);
    }
    print('  ⚠ Unsupported entitlements file extension: $path — expected .yaml/.yml/.plist. Skipping.');
    return {};
  }

  static String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}
