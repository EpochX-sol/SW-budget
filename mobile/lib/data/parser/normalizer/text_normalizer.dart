/// Normalizes raw financial SMS text, Ge'ez numerals, currency symbols, and whitespace.
class TextNormalizer {
  static const Map<String, int> geezDigits = {
    '፩': 1,
    '፪': 2,
    '፫': 3,
    '፬': 4,
    '፭': 5,
    '፮': 6,
    '፯': 7,
    '፰': 8,
    '፱': 9,
    '፲': 10,
    '፳': 20,
    '፴': 30,
    '፵': 40,
    '፶': 50,
    '፷': 60,
    '፸': 70,
    '፹': 80,
    '፺': 90,
    '፻': 100,
    '፼': 10000,
  };

  /// Sanitizes text by stripping invisible zero-width chars and collapsing whitespace.
  static String sanitize(String text) {
    if (text.isEmpty) return '';

    // Remove zero-width spaces, joiners, BOM
    var cleaned = text
        .replaceAll(RegExp(r'[\u200B-\u200D\uFEFF]'), '')
        .replaceAll('\u00A0', ' ')
        .trim();

    // Replace multiple spaces/newlines with a single space
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ');

    return cleaned;
  }

  /// Normalizes currency representations (ETB, Birr, birr, ብር) to standard 'ETB'.
  static String normalizeCurrencies(String text) {
    var result = text;

    // Replace Amharic currency word "ብር" with ETB
    result = result.replaceAll(RegExp(r'ብር'), 'ETB');

    // Normalize variations of Birr / birr / BIRR
    result = result.replaceAll(RegExp(r'\b(?:birr|Birr|BIRR)\b', caseSensitive: false), 'ETB');

    // Ensure single space between ETB and following digits
    result = result.replaceAllMapped(RegExp(r'ETB\s*([0-9])'), (m) => 'ETB ${m[1]}');

    return result;
  }

  /// Converts any single Ge'ez digit occurrences to Arabic digits.
  static String normalizeGeezNumerals(String text) {
    var result = text;
    geezDigits.forEach((geez, arabic) {
      if (arabic <= 9) {
        result = result.replaceAll(geez, arabic.toString());
      }
    });
    return result;
  }

  /// Cleans a numeric string (e.g. "1,450.50" -> 1450.50).
  static double? parseAmount(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;

    final cleaned = raw.replaceAll(',', '').replaceAll(' ', '').trim();
    return double.tryParse(cleaned);
  }

  /// Master normalization pipeline.
  static String normalize(String text) {
    final sanitized = sanitize(text);
    final geezCleaned = normalizeGeezNumerals(sanitized);
    final currenciesCleaned = normalizeCurrencies(geezCleaned);
    return currenciesCleaned;
  }
}
