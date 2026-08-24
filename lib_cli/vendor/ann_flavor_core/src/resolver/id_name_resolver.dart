/// Canonical cascade rules for resolving effective app ID and name.
///
/// Rule:
///   effectiveId   = baseId + idSuffix + effectiveBuildTypeSuffix
///   effectiveName = baseName + nameSuffix + effectiveBuildTypeNameSuffix
///
///   effectiveBuildTypeSuffix = flavor bt suffix if non-blank, else default bt suffix
///
/// Conformance tests: test-fixtures/conformance/
class IdNameResolver {
  static String effectiveBuildTypeSuffix(
          String flavorSuffix, String defaultSuffix) =>
      flavorSuffix.isNotEmpty ? flavorSuffix : defaultSuffix;

  static String resolveId(String baseId, String idSuffix,
          [String buildTypeIdSuffix = '']) =>
      baseId + idSuffix + buildTypeIdSuffix;

  static String resolveName(String baseName, String nameSuffix,
          [String buildTypeNameSuffix = '']) =>
      baseName + nameSuffix + buildTypeNameSuffix;
}
