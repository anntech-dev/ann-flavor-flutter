import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;

/// Param names found in a Firebase Functions source tree (REQ-FUNC-00080).
class FunctionsParamScan {
  /// Declared without a `default:` option — a value must be supplied.
  final Set<String> required = {};

  /// Declared with a `default:` option — a value is optional.
  final Set<String> optional = {};

  /// Declared with `defineSecret` / `defineJsonSecret` — must never be in a `.env`.
  final Set<String> secrets = {};

  /// Declarations whose name is not a string literal, so it cannot be checked.
  int unchecked = 0;

  bool get foundAnything => required.isNotEmpty || optional.isNotEmpty || secrets.isNotEmpty;

  Set<String> get declared => {...required, ...optional, ...secrets};

  void merge(FunctionsParamScan other) {
    required.addAll(other.required);
    optional.addAll(other.optional);
    secrets.addAll(other.secrets);
    unchecked += other.unchecked;
    // A name that is required anywhere is required.
    optional.removeAll(required);
  }
}

/// Reads `defineString(...)`-style param declarations out of JS/TS source.
///
/// A deliberately small, string-aware scanner — not a JS parser. It cannot see
/// params read straight from `process.env` or names built at runtime; those
/// are reported through [FunctionsParamScan.unchecked] or not at all.
class FunctionsParamScanner {
  static const _extensions = {'.js', '.mjs', '.cjs', '.ts', '.mts', '.cts'};
  static const _skipDirs = {'node_modules', '.git'};
  static const _valueCalls = {
    'defineString', 'defineInt', 'defineFloat', 'defineBoolean', 'defineList',
  };
  static const _secretCalls = {'defineSecret', 'defineJsonSecret'};

  static final _call = RegExp(
    r'\b(defineString|defineInt|defineFloat|defineBoolean|defineList|defineSecret|defineJsonSecret)\s*\(',
  );
  static final _defaultOption = RegExp(r'\bdefault\s*:');

  static FunctionsParamScan scan(Directory dir) {
    final result = FunctionsParamScan();
    if (!dir.existsSync()) return result;
    for (final entity in dir.listSync(recursive: false, followLinks: false)) {
      final name = p.basename(entity.path);
      if (entity is Directory) {
        if (_skipDirs.contains(name)) continue;
        result.merge(scan(entity));
      } else if (entity is File) {
        if (name.endsWith('.d.ts')) continue;
        if (!_extensions.contains(p.extension(name))) continue;
        final source = utf8.decode(entity.readAsBytesSync(), allowMalformed: true);
        result.merge(scanSource(source));
      }
    }
    return result;
  }

  static FunctionsParamScan scanSource(String source) {
    final result = FunctionsParamScan();
    final code = _stripComments(source);
    for (final m in _call.allMatches(code)) {
      final fn = m.group(1)!;
      final open = m.end - 1;
      final literal = _readStringLiteral(code, m.end);
      if (literal == null) {
        result.unchecked++;
        continue;
      }
      if (_secretCalls.contains(fn)) {
        result.secrets.add(literal.value);
        continue;
      }
      if (!_valueCalls.contains(fn)) continue;
      final close = _matchingParen(code, open);
      final rest = close == null ? '' : code.substring(literal.end, close);
      final hasDefault = _defaultOption.hasMatch(_blankStrings(rest));
      if (hasDefault) {
        if (!result.required.contains(literal.value)) result.optional.add(literal.value);
      } else {
        result.required.add(literal.value);
        result.optional.remove(literal.value);
      }
    }
    return result;
  }

  /// Replaces `//` and `/* */` comments with spaces (newlines kept) without
  /// touching comment-like text inside string literals.
  static String _stripComments(String s) {
    final out = StringBuffer();
    var i = 0;
    while (i < s.length) {
      final c = s[i];
      if (c == '"' || c == "'" || c == '`') {
        final end = _stringEnd(s, i);
        out.write(s.substring(i, end));
        i = end;
      } else if (c == '/' && i + 1 < s.length && s[i + 1] == '/') {
        while (i < s.length && s[i] != '\n') {
          out.write(' ');
          i++;
        }
      } else if (c == '/' && i + 1 < s.length && s[i + 1] == '*') {
        out.write('  ');
        i += 2;
        while (i < s.length && !(s[i] == '*' && i + 1 < s.length && s[i + 1] == '/')) {
          out.write(s[i] == '\n' ? '\n' : ' ');
          i++;
        }
        if (i < s.length) {
          out.write('  ');
          i += 2;
        }
      } else {
        out.write(c);
        i++;
      }
    }
    return out.toString();
  }

  /// Index just past the string literal that starts at [start].
  static int _stringEnd(String s, int start) {
    final quote = s[start];
    var i = start + 1;
    while (i < s.length) {
      if (s[i] == r'\') {
        i += 2;
        continue;
      }
      if (s[i] == quote) return i + 1;
      i++;
    }
    return s.length;
  }

  /// Reads a plain string literal (no `${}` interpolation) after optional
  /// whitespace at [from]; null when the next token is not one.
  static ({String value, int end})? _readStringLiteral(String s, int from) {
    var i = from;
    while (i < s.length && (s[i] == ' ' || s[i] == '\t' || s[i] == '\n' || s[i] == '\r')) {
      i++;
    }
    if (i >= s.length) return null;
    final quote = s[i];
    if (quote != '"' && quote != "'" && quote != '`') return null;
    final end = _stringEnd(s, i);
    if (end > s.length || end - 1 <= i || s[end - 1] != quote) return null;
    final body = s.substring(i + 1, end - 1);
    if (quote == '`' && body.contains(r'${')) return null;
    if (body.isEmpty) return null;
    return (value: body, end: end);
  }

  /// Index of the `)` that closes the `(` at [open]; null when unbalanced.
  static int? _matchingParen(String s, int open) {
    var depth = 0;
    var i = open;
    while (i < s.length) {
      final c = s[i];
      if (c == '"' || c == "'" || c == '`') {
        i = _stringEnd(s, i);
        continue;
      }
      if (c == '(') depth++;
      if (c == ')') {
        depth--;
        if (depth == 0) return i;
      }
      i++;
    }
    return null;
  }

  static String _blankStrings(String s) {
    final out = StringBuffer();
    var i = 0;
    while (i < s.length) {
      final c = s[i];
      if (c == '"' || c == "'" || c == '`') {
        i = _stringEnd(s, i);
        out.write('""');
      } else {
        out.write(c);
        i++;
      }
    }
    return out.toString();
  }
}
