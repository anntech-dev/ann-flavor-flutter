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
/// AnnFlavor.current.name         // "My App"
/// AnnFlavor.current.androidId    // "com.example.myapp"
/// AnnFlavor.current.custom('revenuecat')?.string('api_key')
/// ```
abstract class AnnFlavorConfig {
  /// Creates a const flavor config (all generated subclasses are const).
  const AnnFlavorConfig();

  /// The flavor key — matches the `--flavor` flag passed to Flutter CLI
  /// (e.g. `"production"`, `"staging"`).
  String get key;

  /// The app display name for this flavor.
  String get name;

  /// Android application ID (base ID + any `id_suffix`), or `null` if not
  /// set.
  String? get androidId;

  /// iOS bundle identifier (base ID + any `id_suffix`), or `null` if not set.
  String? get iosId;

  /// Google Sign-In OAuth config for the given [platform] in **release** mode,
  /// or `null` if no `auth:` block is defined for this flavor/platform.
  AnnAuthConfig? auth(AnnPlatform platform);

  /// Google Sign-In OAuth config for the given [platform] in **debug** mode,
  /// or `null` if no `auth:` block is defined for this flavor/platform.
  AnnAuthConfig? authDebug(AnnPlatform platform);

  /// Resolved `custom:` config group for [group], or `null` if the group is
  /// not defined at any cascade level for the active flavor + build type.
  ///
  /// The build type is read automatically from [AnnFlavor.buildType].
  /// Values are pre-resolved at `sync` time — no runtime YAML parsing.
  ///
  /// ```dart
  /// final rc = AnnFlavor.current.custom('revenuecat');
  /// final key = rc?.string('api_key');
  /// ```
  AnnCustomGroup? custom(String group) => null;
}
