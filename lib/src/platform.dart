/// The platform the Flutter app is currently running on.
///
/// Pass one of these values to [AnnFlavor.init] so the runtime knows which
/// platform-specific credentials and config to expose.
///
/// ```dart
/// import 'dart:io';
///
/// AnnFlavor.init(
///   config:   MyFlavor(),
///   platform: Platform.isAndroid ? AnnPlatform.android
///           : Platform.isIOS    ? AnnPlatform.ios
///           : AnnPlatform.web,
/// );
/// ```
enum AnnPlatform {
  /// Android phone/tablet.
  android,

  /// iPhone or iPad.
  ios,

  /// Browser (Flutter Web).
  web,

  /// Windows desktop.
  windows,
}
