import 'package:xml/xml.dart';

/// Minimal Apple XML property-list codec — reads/writes the subset of value
/// types annspec.yaml's `info_plist` field and Flutter's stock `Info.plist`
/// actually use (string, bool, int, array, dict). No `plist` package exists
/// for null-safe Dart on pub.dev, so this is a small codec on top of the
/// well-maintained `xml` package rather than raw regex/string patching.
class PlistCodec {
  /// Parses a `.plist` file's XML content into a `Map<String, dynamic>`.
  static Map<String, dynamic> decode(String xmlContent) {
    final doc = XmlDocument.parse(xmlContent);
    final plist = doc.findAllElements('plist').first;
    final rootDict = plist.childElements.first;
    if (rootDict.name.local != 'dict') {
      throw FormatException('Expected root <dict>, found <${rootDict.name.local}>');
    }
    return _decodeDict(rootDict);
  }

  static Map<String, dynamic> _decodeDict(XmlElement dictEl) {
    final result = <String, dynamic>{};
    final children = dictEl.childElements.toList();
    for (var i = 0; i < children.length; i += 2) {
      final keyEl = children[i];
      if (keyEl.name.local != 'key') {
        throw FormatException('Expected <key>, found <${keyEl.name.local}>');
      }
      final valueEl = children[i + 1];
      result[keyEl.innerText] = _decodeValue(valueEl);
    }
    return result;
  }

  static dynamic _decodeValue(XmlElement el) {
    switch (el.name.local) {
      case 'string':
        return el.innerText;
      case 'true':
        return true;
      case 'false':
        return false;
      case 'integer':
        return int.parse(el.innerText);
      case 'real':
        return double.parse(el.innerText);
      case 'array':
        return el.childElements.map(_decodeValue).toList();
      case 'dict':
        return _decodeDict(el);
      default:
        throw FormatException('Unsupported plist value type: <${el.name.local}>');
    }
  }

  /// Encodes a `Map<String, dynamic>` into a complete `.plist` XML document
  /// string (including the `<?xml ...?>` header and Apple DOCTYPE).
  static String encode(Map<String, dynamic> values) {
    final builder = XmlBuilder();
    builder.processing('xml', 'version="1.0" encoding="UTF-8"');
    builder.doctype(
      'plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"',
    );
    builder.element('plist', attributes: {'version': '1.0'}, nest: () {
      _buildDict(builder, values);
    });
    final doc = builder.buildDocument();
    final xmlString = doc.toXmlString(pretty: true, indent: '\t');
    // The `xml` package correctly escapes `<` and `&` in text content per the
    // XML spec, but only escapes `>` when it forms the CDATA-close sequence
    // `]]>` — a bare `>` is valid, unescaped XML. Apple's plist convention (and
    // every other plist writer, including the hand-maintained files this
    // generator replaces) escapes `>` unconditionally for readability/
    // consistency. Safe to do as a post-process restricted to <string> content:
    // this codec never emits nested <string> elements or any other place a
    // literal `>` could appear outside a string's own text.
    final escaped = xmlString.replaceAllMapped(
      RegExp(r'<string>([\s\S]*?)</string>'),
      (m) => '<string>${m.group(1)!.replaceAll('>', '&gt;')}</string>',
    );
    return '$escaped\n';
  }

  static void _buildDict(XmlBuilder builder, Map<String, dynamic> values) {
    builder.element('dict', nest: () {
      for (final entry in values.entries) {
        builder.element('key', nest: entry.key);
        _buildValue(builder, entry.value);
      }
    });
  }

  static void _buildValue(XmlBuilder builder, dynamic value) {
    if (value is String) {
      builder.element('string', nest: value);
    } else if (value is bool) {
      builder.element(value ? 'true' : 'false');
    } else if (value is int) {
      builder.element('integer', nest: value.toString());
    } else if (value is double) {
      builder.element('real', nest: value.toString());
    } else if (value is List) {
      builder.element('array', nest: () {
        for (final item in value) {
          _buildValue(builder, item);
        }
      });
    } else if (value is Map) {
      _buildDict(builder, value.cast<String, dynamic>());
    } else {
      throw ArgumentError('Unsupported plist value type: ${value.runtimeType}');
    }
  }
}
