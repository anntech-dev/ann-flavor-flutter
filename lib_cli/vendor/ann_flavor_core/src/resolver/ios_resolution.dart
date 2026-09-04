import '../model/ann_spec_model.dart';
import 'ann_spec_resolver.dart';

/// Shared iOS resolution helpers — mirrors AnnFlavorCore::IosResolution in
/// core/ann-flavor-core-ruby (core/ann-flavor-core-ruby/lib/ann_flavor_core/
/// ios_resolution.rb), at parity. Both exist for the same reason: multiple
/// consumers need identical effective iOS values without each independently
/// re-deriving the cascade — Ruby's version is shared across
/// ann-flavor-cocoapods and ann-flavor-fastlane; this one is for
/// ann-flavor-flutter and any future Dart consumer.
///
/// service_account and target are NOT separately re-cascaded here — the
/// resolver's own 4-level firebase cascade (resolveFirebase, inside
/// AnnSpecResolver) already resolves them correctly as fields on
/// ResolvedBuildOutput.effectiveFirebase. These helpers just expose that
/// value under the names/shape a consumer wants, plus the one piece of
/// actual business logic — target's "Runner" fallback when nothing resolves
/// at any level.
class IosResolution {
  /// Effective service_account for a flavor at a specific build type. Full
  /// 4-level cascade (flavor.buildTypes[bt] -> flavor -> default.buildTypes[bt]
  /// -> default), already computed by AnnSpecResolver.resolveIosFlavor.
  static String? serviceAccount(
    IosPlatform platform,
    String flavorKey,
    String buildType,
  ) {
    final flavor = platform.flavors[flavorKey] ?? const IosFlavor();
    final resolved =
        AnnSpecResolver.resolveIosFlavor(flavor, platform.defaults, buildType);
    return resolved.effectiveFirebase?.serviceAccount;
  }

  /// Effective Xcode target name for `flutterfire configure --ios-target`, at
  /// a specific build type. Same 4-level cascade as [serviceAccount]; falls
  /// back to "Runner" when nothing resolves at any level (the default Xcode
  /// target name Flutter's own template uses).
  static String target(
    IosPlatform platform,
    String flavorKey,
    String buildType,
  ) {
    final flavor = platform.flavors[flavorKey] ?? const IosFlavor();
    final resolved =
        AnnSpecResolver.resolveIosFlavor(flavor, platform.defaults, buildType);
    return resolved.effectiveFirebase?.target ?? 'Runner';
  }

  /// The 4 raw `info_plist` levels for a flavor at a specific build type, in
  /// least-specific-first order: `[default, default.buildType, flavor,
  /// flavor.buildType]`. Unlike [serviceAccount]/[target], `info_plist` is
  /// NOT whole-value-resolved by AnnSpecResolver (see the comment on
  /// ResolvedBuildOutput.effectiveInfoPlist) — a more specific level's
  /// content-key set is meant to be unioned with less specific levels', not
  /// replace them outright. That per-key union can't happen inside the core:
  /// a level's raw value may be a file-path string that only the plugin can
  /// read from disk. So the core exposes the raw 4 levels here; the plugin
  /// resolves any file-path string to a Map itself, then passes the 4
  /// resolved maps to [mergeInfoPlist] for the actual merge.
  static List<InfoPlistValue?> infoPlistLevels(
    IosPlatform platform,
    String flavorKey,
    String buildType,
  ) {
    final flavor = platform.flavors[flavorKey] ?? const IosFlavor();
    final defaults = platform.defaults;
    return [
      defaults.infoPlist,
      defaults.buildTypes[buildType]?.infoPlist,
      flavor.infoPlist,
      flavor.buildTypes[buildType]?.infoPlist,
    ];
  }

  /// Unions already-resolved `info_plist` maps for a single flavor/build type
  /// across all levels present, least-specific first — a key set by a more
  /// specific level overrides the same key from a less specific one, but
  /// keys unique to a less specific level still appear in the result. Pure:
  /// no file I/O, no knowledge of the file-path form — the plugin resolves
  /// each level's raw value (inline map or file-path-read map) before
  /// calling this.
  static Map<String, dynamic> mergeInfoPlist(
    List<Map<String, dynamic>?> levelsLeastSpecificFirst,
  ) {
    final merged = <String, dynamic>{};
    for (final level in levelsLeastSpecificFirst) {
      if (level != null) merged.addAll(level);
    }
    return merged;
  }

  /// The 4 raw `entitlements` levels for a flavor at a specific build type,
  /// in least-specific-first order — same shape and rationale as
  /// [infoPlistLevels].
  static List<EntitlementsValue?> entitlementsLevels(
    IosPlatform platform,
    String flavorKey,
    String buildType,
  ) {
    final flavor = platform.flavors[flavorKey] ?? const IosFlavor();
    final defaults = platform.defaults;
    return [
      defaults.entitlements,
      defaults.buildTypes[buildType]?.entitlements,
      flavor.entitlements,
      flavor.buildTypes[buildType]?.entitlements,
    ];
  }

  /// Unions already-resolved `entitlements` maps for a single flavor/build
  /// type across all levels present, least-specific first — same merge rule
  /// as [mergeInfoPlist].
  static Map<String, dynamic> mergeEntitlements(
    List<Map<String, dynamic>?> levelsLeastSpecificFirst,
  ) {
    final merged = <String, dynamic>{};
    for (final level in levelsLeastSpecificFirst) {
      if (level != null) merged.addAll(level);
    }
    return merged;
  }

  /// The 4 raw `export_options` levels for a flavor at a specific build
  /// type, in least-specific-first order — same shape and rationale as
  /// [infoPlistLevels].
  static List<ExportOptionsValue?> exportOptionsLevels(
    IosPlatform platform,
    String flavorKey,
    String buildType,
  ) {
    final flavor = platform.flavors[flavorKey] ?? const IosFlavor();
    final defaults = platform.defaults;
    return [
      defaults.exportOptions,
      defaults.buildTypes[buildType]?.exportOptions,
      flavor.exportOptions,
      flavor.buildTypes[buildType]?.exportOptions,
    ];
  }

  /// Unions already-resolved `export_options` maps for a single flavor/build
  /// type across all levels present, least-specific first — same merge rule
  /// as [mergeInfoPlist]. Callers layer this union on top of a
  /// generator-computed base (team ID, provisioning profile guess) — see
  /// ann-flavor-flutter's ios_generator.dart.
  static Map<String, dynamic> mergeExportOptions(
    List<Map<String, dynamic>?> levelsLeastSpecificFirst,
  ) {
    final merged = <String, dynamic>{};
    for (final level in levelsLeastSpecificFirst) {
      if (level != null) merged.addAll(level);
    }
    return merged;
  }
}
