/// Google Sign-In OAuth configuration for one platform + build type.
class AnnAuthConfig {
  final String? clientId;
  final String? reversedClientId;

  const AnnAuthConfig({
    this.clientId,
    this.reversedClientId,
  });

  @override
  String toString() =>
      'AnnAuthConfig(clientId: $clientId, reversedClientId: $reversedClientId)';
}
