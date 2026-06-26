/// Typed accessor for a resolved `custom:` config group.
///
/// Retrieved via [AnnFlavorConfig.custom] — e.g.:
/// ```dart
/// final rc = AnnFlavor.current.custom('revenuecat');
/// Purchases.configure(PurchasesConfiguration(rc!.string('api_key')!));
///
/// final ids = rc.strings('entitlement_ids') ?? [];
/// ```
///
/// Values are resolved through the 4-level cascade at `sync` time
/// (`default → default.buildType → flavor → flavor.buildType`) and baked into
/// the generated Dart class — there is no runtime YAML parsing.
class AnnCustomGroup {
  final Map<String, dynamic> _data;

  /// Creates an [AnnCustomGroup] from a resolved key-value map.
  const AnnCustomGroup(this._data);

  /// Returns the value for [key] as a [String], or `null` if absent or
  /// of a different type.
  String? string(String key) => _data[key] as String?;

  /// Returns the value for [key] as a [bool], or `null` if absent or
  /// of a different type.
  bool? boolean(String key) => _data[key] as bool?;

  /// Returns the value for [key] as an [int], or `null` if absent or
  /// of a different type.
  int? integer(String key) => _data[key] as int?;

  /// Returns the value for [key] as a [double], or `null` if absent or
  /// of a different type.
  double? decimal(String key) => _data[key] as double?;

  /// Returns the value for [key] as a `List<String>`, or `null` if absent.
  List<String>? strings(String key) => (_data[key] as List?)?.cast<String>();

  /// Raw access for custom handling — returns the value as-is.
  dynamic operator [](String key) => _data[key];

  /// All keys present in this group.
  Iterable<String> get keys => _data.keys;
}
