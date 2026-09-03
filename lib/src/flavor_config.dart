import 'platform.dart';
import 'auth_config.dart';
import 'custom_group.dart';
import 'flavor_registry.dart';

/// Abstract base class for a generated flavor configuration.
///
/// Each flavor entry in `annspec.yaml` produces a concrete subclass in
/// `lib/generated/ann_flavor.g.dart`. You never write these classes manually —
/// run `dart run ann_flutter_flavor sync` to regenerate them after editing the
/// spec.
///
/// Call [AnnFlavor.init] once in each flavor entry point (`main_*.dart`):
///
/// ```dart
/// void main() async {
///   WidgetsFlutterBinding.ensureInitialized();
///   AnnFlavor.init(
///     config:   ProductionFlavor(),
///     platform: Platform.isAndroid ? AnnPlatform.android : AnnPlatform.ios,
///   );
///   runApp(const MyApp());
/// }
/// ```
///
/// Access values anywhere with `AnnFlavor.current`:
/// ```dart
/// AnnFlavor.current.nameFor()                      // active platform — "My App"
/// AnnFlavor.current.existsOn(AnnPlatform.web)       // false if this flavor doesn't ship on web
/// AnnFlavor.current.idFor(AnnPlatform.android)      // "com.example.myapp"
/// AnnFlavor.current.customFor('revenuecat')?.string('api_key')
/// ```
///
/// Every method below (other than [existsOn]) takes its platform (and, where
/// relevant, build type) as an *optional* trailing parameter — omit it to
/// use the currently active [AnnFlavor.platform] / [AnnFlavor.buildType].
/// Passing it explicitly and omitting it behave identically once the value
/// is known: there is no separate "safe" no-arg form — if this flavor has no
/// entry under the resolved platform, it throws [StateError] either way.
/// [existsOn] is the one exception — it never throws, and is the check to
/// make before querying a platform you're not sure this flavor targets.
///
/// [auth], [firebaseOptions], and [custom] are shorthand for calling
/// [authFor]/[firebaseOptionsFor]/[customFor] with no arguments — same
/// throw/null contract, just terser at the call site when you always want
/// the currently active platform/build type. [name] and [id] are the same
/// shorthand over [nameFor] and [idFor], except non-nullable — they fall
/// back to [key] instead of `null`.
abstract class AnnFlavorConfig {
  /// Creates a const flavor config (all generated subclasses are const).
  const AnnFlavorConfig();

  /// The flavor key — matches the `--flavor` flag passed to Flutter CLI
  /// (e.g. `"production"`, `"staging"`).
  String get key;

  // ── Presence ────────────────────────────────────────────────────────────

  /// Whether this flavor has an entry under `app.<platform>.flavor` in
  /// `annspec.yaml` — i.e. whether it actually targets [platform] (defaults
  /// to [AnnFlavor.platform] if omitted).
  ///
  /// Never throws — this is the check to make *before* calling [nameFor],
  /// [idFor], [authFor], [firebaseOptionsFor], or [customFor] for a platform
  /// you're not sure this flavor ships on, since those throw [StateError]
  /// rather than return `null` when this would be `false`.
  ///
  /// ```dart
  /// if (AnnFlavor.current.existsOn(AnnPlatform.web)) {
  ///   final name = AnnFlavor.current.nameFor(AnnPlatform.web);
  /// }
  /// ```
  bool existsOn([AnnPlatform? platform]);

  // ── Name ────────────────────────────────────────────────────────────────

  /// The display name of this flavor on [platform] (defaults to
  /// [AnnFlavor.platform] if omitted), or `null` if this flavor has no entry
  /// under that platform (e.g. a web-only flavor queried for
  /// [AnnPlatform.android]).
  ///
  /// Throws [StateError] if the resolved platform was never configured for
  /// this app at all (`app.<platform>` absent from `annspec.yaml` entirely)
  /// — that is a programming error at the call site, not an expected
  /// per-flavor gap, whether [platform] was passed explicitly or defaulted.
  String? nameFor([AnnPlatform? platform]);

  /// Shorthand for `nameFor()` — the display name for the currently active
  /// platform ([AnnFlavor.platform]), falling back to [key] if `nameFor()`
  /// returns `null`. Always non-null, unlike [nameFor]. Still throws
  /// [StateError] under the same contract as [nameFor] if the resolved
  /// platform was never configured for this app at all.
  String get name => nameFor() ?? key;

  // ── Application ID ─────────────────────────────────────────────────────

  /// The application ID / bundle identifier of this flavor on [platform]
  /// (defaults to [AnnFlavor.platform] if omitted; base ID + any
  /// `id_suffix`), or `null` if this flavor has no entry under that
  /// platform.
  ///
  /// Throws [StateError] under the same contract as [nameFor].
  String? idFor([AnnPlatform? platform]);

  /// Shorthand for `idFor()` — the application ID for the currently active
  /// platform ([AnnFlavor.platform]), falling back to [key] if `idFor()`
  /// returns `null`. Always non-null, unlike [idFor]. Still throws
  /// [StateError] under the same contract as [nameFor] if the resolved
  /// platform was never configured for this app at all.
  String get id => idFor() ?? key;

  /// App Store application ID (numeric), or `null` if `stores.app_store.apple_id`
  /// is not set in `annspec.yaml`.
  String? get appleId => null;

  // ── Auth ────────────────────────────────────────────────────────────────

  /// Google Sign-In OAuth config for this flavor on [platform] at
  /// [buildType] (`'release'`, `'debug'`, or `'profile'`) — both default to
  /// the currently active [AnnFlavor.platform] / [AnnFlavor.buildType] if
  /// omitted — or `null` if no `auth:` block resolves for this
  /// flavor/platform/build-type.
  ///
  /// Throws [StateError] under the same contract as [nameFor].
  AnnAuthConfig? authFor([AnnPlatform? platform, String? buildType]);

  /// Shorthand for `authFor()` — the OAuth config for the currently active
  /// platform/build type. Same throw/null contract as [authFor].
  AnnAuthConfig? get auth => authFor();

  // ── Firebase options ───────────────────────────────────────────────────

  /// Firebase options for this flavor on [platform] at [buildType] — both
  /// default to the currently active [AnnFlavor.platform] /
  /// [AnnFlavor.buildType] if omitted — or `null` if this flavor has no
  /// Firebase config for that platform/build-type.
  ///
  /// Typed `dynamic` (not `FirebaseOptions?`) because this package does not
  /// depend on `firebase_core` — only generated flavor classes that
  /// actually have a `firebase:` block anywhere in `annspec.yaml` override
  /// this with a concrete `FirebaseOptions?`-typed method. Callers in an app
  /// that does depend on `firebase_core` should cast the result, e.g.
  /// `AnnFlavor.current.firebaseOptionsFor() as FirebaseOptions?`.
  ///
  /// Throws [StateError] under the same contract as [nameFor].
  dynamic firebaseOptionsFor([AnnPlatform? platform, String? buildType]) => null;

  /// Shorthand for `firebaseOptionsFor()` — Firebase options for the
  /// currently active platform/build type. Same throw/null contract as
  /// [firebaseOptionsFor].
  dynamic get firebaseOptions => firebaseOptionsFor();

  // ── Custom config ───────────────────────────────────────────────────────

  /// Resolved `custom:` config group [group] for this flavor on [platform]
  /// at [buildType] — both default to the currently active
  /// [AnnFlavor.platform] / [AnnFlavor.buildType] if omitted — or `null` if
  /// the group isn't defined at any cascade level for that
  /// platform/build-type. Values are pre-resolved at `sync` time — no
  /// runtime YAML parsing.
  ///
  /// Throws [StateError] under the same contract as [nameFor]. Each
  /// platform is resolved independently — a value set under
  /// `app.web.default.custom.<group>` never bleeds into
  /// `customFor(AnnPlatform.android, ...)`.
  ///
  /// ```dart
  /// final rc = AnnFlavor.current.customFor('revenuecat');
  /// final key = rc?.string('api_key');
  /// ```
  AnnCustomGroup? customFor(String group, [AnnPlatform? platform, String? buildType]) => null;

  /// Shorthand for `customFor(group)` — the resolved config group for the
  /// currently active platform/build type. Same throw/null contract as
  /// [customFor].
  AnnCustomGroup? custom(String group) => customFor(group);
}
