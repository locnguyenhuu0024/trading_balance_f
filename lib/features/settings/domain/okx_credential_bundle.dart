import 'dart:convert';

/// A validated set of OKX credentials entered as one labeled bundle.
class OkxCredentialBundle {
  const OkxCredentialBundle({
    required this.apiKey,
    required this.secretKey,
    required this.passphrase,
  });

  static const String invalidInputMessage = 'Thông tin API không hợp lệ.';

  final String apiKey;
  final String secretKey;
  final String passphrase;

  factory OkxCredentialBundle.parse(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) _throwInvalidInput();

    final values = trimmed.startsWith('{')
        ? _parseJsonObject(trimmed)
        : _parseLabeledLines(trimmed);

    final apiKey = values['apiKey'];
    final secretKey = values['secretKey'];
    final passphrase = values['passphrase'];
    if (apiKey == null || secretKey == null || passphrase == null) {
      _throwInvalidInput();
    }

    return OkxCredentialBundle(
      apiKey: apiKey,
      secretKey: secretKey,
      passphrase: passphrase,
    );
  }

  static Map<String, String> _parseLabeledLines(String input) {
    final values = <String, String>{};
    for (final line in input.split('\n')) {
      if (line.trim().isEmpty) continue;

      final colon = line.indexOf(':');
      final equals = line.indexOf('=');
      final separator = switch ((colon, equals)) {
        (-1, -1) => -1,
        (-1, final equalsIndex) => equalsIndex,
        (final colonIndex, -1) => colonIndex,
        (final colonIndex, final equalsIndex) =>
          colonIndex < equalsIndex ? colonIndex : equalsIndex,
      };
      if (separator <= 0) _throwInvalidInput();

      _addValue(
        values,
        line.substring(0, separator),
        line.substring(separator + 1),
      );
    }
    return values;
  }

  static Map<String, String> _parseJsonObject(String input) {
    final reader = _JsonCredentialObjectReader(input);
    return reader.read();
  }

  static void _addValue(
    Map<String, String> values,
    String label,
    String rawValue,
  ) {
    final canonical = _canonicalLabel(label);
    final value = rawValue.trim();
    if (canonical == null || value.isEmpty || values.containsKey(canonical)) {
      _throwInvalidInput();
    }
    values[canonical] = value;
  }

  static String? _canonicalLabel(String label) {
    final normalized = label.trim().toLowerCase().replaceAll(
      RegExp(r'[\s_-]+'),
      '',
    );
    return switch (normalized) {
      'apikey' => 'apiKey',
      'secretkey' || 'secret' => 'secretKey',
      'passphrase' => 'passphrase',
      _ => null,
    };
  }

  static Never _throwInvalidInput() =>
      throw const FormatException(invalidInputMessage);
}

/// Reads a flat JSON object while retaining duplicate keys until validation.
///
/// `jsonDecode` into a map alone loses identical duplicate keys, so this reader
/// parses each quoted token before adding it to the semantic credential map.
class _JsonCredentialObjectReader {
  _JsonCredentialObjectReader(this.input);

  final String input;
  int _cursor = 0;

  Map<String, String> read() {
    final values = <String, String>{};
    final originalKeys = <String>{};
    _skipWhitespace();
    _expect('{');
    _skipWhitespace();

    if (_take('}')) {
      _skipWhitespace();
      if (_cursor != input.length) OkxCredentialBundle._throwInvalidInput();
      return values;
    }

    while (true) {
      _skipWhitespace();
      final key = _readStringToken();
      if (!originalKeys.add(key)) OkxCredentialBundle._throwInvalidInput();
      _skipWhitespace();
      _expect(':');
      _skipWhitespace();
      final value = _readStringToken();
      OkxCredentialBundle._addValue(values, key, value);
      _skipWhitespace();

      if (_take('}')) break;
      _expect(',');
    }

    _skipWhitespace();
    if (_cursor != input.length) OkxCredentialBundle._throwInvalidInput();
    return values;
  }

  String _readStringToken() {
    if (_cursor >= input.length || input[_cursor] != '"') {
      OkxCredentialBundle._throwInvalidInput();
    }

    final start = _cursor++;
    while (_cursor < input.length) {
      final character = input[_cursor];
      if (character == r'\') {
        _cursor += 2;
        continue;
      }
      if (character == '"') {
        _cursor++;
        try {
          final decoded = jsonDecode(input.substring(start, _cursor));
          if (decoded is! String) OkxCredentialBundle._throwInvalidInput();
          return decoded;
        } on FormatException {
          OkxCredentialBundle._throwInvalidInput();
        }
      }
      _cursor++;
    }

    OkxCredentialBundle._throwInvalidInput();
  }

  void _skipWhitespace() {
    while (_cursor < input.length &&
        const {' ', '\t', '\r', '\n'}.contains(input[_cursor])) {
      _cursor++;
    }
  }

  void _expect(String character) {
    if (!_take(character)) OkxCredentialBundle._throwInvalidInput();
  }

  bool _take(String character) {
    if (_cursor >= input.length || input[_cursor] != character) return false;
    _cursor++;
    return true;
  }
}
