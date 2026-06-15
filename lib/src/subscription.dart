/// A RevenueCat subscription configuration for one storefront.
class AnnSubscription {
  final String apiKey;
  final List<String> entitlementIds;

  const AnnSubscription({
    required this.apiKey,
    required this.entitlementIds,
  });

  @override
  String toString() =>
      'AnnSubscription(apiKey: $apiKey, entitlementIds: $entitlementIds)';
}
