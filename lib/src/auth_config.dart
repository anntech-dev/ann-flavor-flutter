/// Google Sign-In OAuth 2.0 configuration for one platform + build type.
///
/// Returned by [AnnFlavorConfig.auth] (release) and [AnnFlavorConfig.authDebug]
/// (debug). Both values are resolved from the `auth:` block in `annspec.yaml`
/// and baked into the generated flavor class — no runtime YAML parsing.
///
/// ```dart
/// final auth = AnnFlavor.current.auth(AnnFlavor.platform);
/// GoogleSignIn(clientId: auth?.clientId).signIn();
/// ```
class AnnAuthConfig {
  /// The OAuth 2.0 client ID for this platform and build type.
  final String? clientId;

  /// The reversed client ID used as a custom URL scheme on iOS.
  final String? reversedClientId;

  /// Creates an [AnnAuthConfig] with the given OAuth credentials.
  const AnnAuthConfig({
    this.clientId,
    this.reversedClientId,
  });

  @override
  String toString() =>
      'AnnAuthConfig(clientId: $clientId, reversedClientId: $reversedClientId)';
}
