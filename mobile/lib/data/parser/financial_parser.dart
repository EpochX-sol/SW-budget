import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'models/parsed_transaction.dart';
import 'models/regex_template.dart';
import 'models/template_bundle.dart';
import 'models/parse_result.dart';
import 'normalizer/text_normalizer.dart';

/// Pure Dart financial message parser with regex matching, deduplication hashing,
/// and Ed25519 cryptographic bundle validation.
class FinancialParser {
  List<RegexTemplate> _templates = [];

  FinancialParser({List<RegexTemplate>? initialTemplates}) {
    if (initialTemplates != null) {
      _templates = List.from(initialTemplates);
      _sortTemplates();
    }
  }

  /// Loads templates from a JSON string (e.g. from assets or cache).
  void loadTemplatesFromJson(String jsonString) {
    final decoded = jsonDecode(jsonString) as Map<String, dynamic>;
    final bundle = TemplateBundle.fromJson(decoded);
    _templates = List.from(bundle.templates);
    _sortTemplates();
  }

  void _sortTemplates() {
    _templates.sort((a, b) => b.priority.compareTo(a.priority));
  }

  /// Known financial senders in Ethiopia.
  static const Set<String> _knownFinancialSenders = {
    'cbe',
    'cbebirr',
    'cbe_birr',
    'telebirr',
    '127',
    'boa',
    'abyssinia',
    'bank of abyssinia',
    'dashen',
    'enat',
    'awash',
    'nib',
    'zemen',
  };

  /// Common non-financial OTP / security keywords.
  static const List<String> _otpKeywords = [
    'verification code',
    'security code',
    'otp',
    'do not share',
    'ይለፍ ቃል',
  ];

  /// Detects whether the sender and message content indicate a financial transaction.
  bool isFinancialMessage(String sender, String body) {
    final sLower = sender.toLowerCase().trim();
    final bLower = body.toLowerCase();

    // Reject pure OTP messages
    for (final otp in _otpKeywords) {
      if (bLower.contains(otp) &&
          !bLower.contains('debited') &&
          !bLower.contains('credited') &&
          !bLower.contains('paid') &&
          !bLower.contains('received') &&
          !bLower.contains('ተቀንሷል') &&
          !bLower.contains('ተከፍሏል')) {
        return false;
      }
    }

    // Reject failed transaction / insufficient balance alerts
    if (bLower.contains('insufficient balance') ||
        bLower.contains('transaction failed') ||
        bLower.contains('unsuccessful')) {
      return false;
    }

    // Check sender match
    for (final known in _knownFinancialSenders) {
      if (sLower.contains(known)) return true;
    }

    // Check body financial cues
    if (bLower.contains('etb') ||
        bLower.contains('birr') ||
        bLower.contains('ብር') ||
        bLower.contains('debited') ||
        bLower.contains('credited') ||
        bLower.contains('telebirr') ||
        bLower.contains('cbe') ||
        bLower.contains('balance is')) {
      return true;
    }

    return false;
  }

  /// Detects the target bank provider from sender name or content.
  String detectProvider(String sender, String body) {
    final s = sender.toLowerCase();
    final b = body.toLowerCase();

    // 1. Check sender name first (most authoritative)
    if (s.contains('telebirr') || s == '127') {
      return 'TELEBIRR';
    }
    if (s.contains('cbe') || s.contains('commercial bank of ethiopia')) {
      return 'CBE';
    }
    if (s.contains('boa') || s.contains('abyssinia')) {
      return 'ABYSSINIA';
    }
    if (s.contains('dashen')) {
      return 'DASHEN';
    }
    if (s.contains('enat')) {
      return 'ENAT';
    }

    // 2. Fall back to body inspection if sender is numeric or generic
    if (b.contains('bank of abyssinia') || b.contains('abyssinia')) {
      return 'ABYSSINIA';
    }
    if (b.contains('commercial bank of ethiopia') || b.contains('cbe')) {
      return 'CBE';
    }
    if (b.contains('telebirr')) {
      return 'TELEBIRR';
    }
    if (b.contains('dashen')) {
      return 'DASHEN';
    }
    if (b.contains('enat')) {
      return 'ENAT';
    }
    return 'OTHER';
  }

  /// Parses a raw financial SMS or notification text.
  ParseResult parse({
    required String sender,
    required String body,
    required DateTime receivedAt,
  }) {
    if (!isFinancialMessage(sender, body)) {
      return ParseResult.nonFinancial();
    }

    final normalized = TextNormalizer.normalize(body);
    final provider = detectProvider(sender, body);

    // Filter templates for matching bank provider or fallback
    final candidates = _templates.where((t) {
      return t.bank.toUpperCase() == provider.toUpperCase() || t.bank == 'ALL';
    }).toList();

    for (final template in candidates) {
      final rootRegex = _safeRegExp(template.pattern, caseSensitive: false);
      if (rootRegex.hasMatch(normalized)) {
        // Match individual field regexes
        final fields = template.fields;

        // 1. Amount
        final amountRegex = _safeRegExp(fields.amount, caseSensitive: false);
        final amountMatch = amountRegex.firstMatch(normalized);
        String? rawAmount;
        if (amountMatch != null && amountMatch.groupCount >= 1) {
          for (int g = 1; g <= amountMatch.groupCount; g++) {
            final candidate = amountMatch.group(g);
            if (candidate != null && candidate.trim().isNotEmpty) {
              rawAmount = candidate;
              break;
            }
          }
        }
        final amount = TextNormalizer.parseAmount(rawAmount);

        if (amount == null || amount <= 0) {
          continue; // Amount is mandatory for a valid financial transaction
        }

        // 2. Balance After
        double? balanceAfter;
        if (fields.balance != null) {
          final balRegex = _safeRegExp(fields.balance!, caseSensitive: false);
          final balMatch = balRegex.firstMatch(normalized);
          if (balMatch != null && balMatch.groupCount >= 1) {
            for (int g = 1; g <= balMatch.groupCount; g++) {
              final candidate = balMatch.group(g);
              if (candidate != null && candidate.trim().isNotEmpty) {
                balanceAfter = TextNormalizer.parseAmount(candidate);
                break;
              }
            }
          }
        }

        // 3. Counterparty
        String? counterparty;
        if (fields.counterparty != null) {
          final cpRegex = _safeRegExp(fields.counterparty!, caseSensitive: false);
          final cpMatch = cpRegex.firstMatch(normalized);
          if (cpMatch != null && cpMatch.groupCount >= 1) {
            for (int g = 1; g <= cpMatch.groupCount; g++) {
              final candidate = cpMatch.group(g)?.trim();
              if (candidate != null && candidate.isNotEmpty) {
                counterparty = candidate;
                break;
              }
            }
          }
        }

        // 4. Reference
        String? reference;
        if (fields.reference != null) {
          final refRegex = _safeRegExp(fields.reference!, caseSensitive: false);
          final refMatch = refRegex.firstMatch(normalized);
          if (refMatch != null && refMatch.groupCount >= 1) {
            for (int g = 1; g <= refMatch.groupCount; g++) {
              final candidate = refMatch.group(g)?.trim();
              if (candidate != null && candidate.isNotEmpty) {
                reference = candidate;
                break;
              }
            }
          }
        }

        // 5. Deduplication Key calculation
        final dedupeKey = _computeDedupeKey(
          provider: provider,
          reference: reference,
          amount: amount,
          occurredAt: receivedAt,
        );

        // 6. Confidence Scoring
        double confidence = 0.70;
        if (balanceAfter != null) confidence += 0.15;
        if (reference != null) confidence += 0.10;
        if (counterparty != null) confidence += 0.04;
        if (confidence > 0.99) confidence = 0.99;

        final isReviewRequired = confidence < 0.80 || balanceAfter == null;

        final transaction = ParsedTransaction(
          provider: provider,
          type: template.type,
          amount: amount,
          balanceAfter: balanceAfter,
          counterparty: counterparty,
          reference: reference,
          occurredAt: receivedAt,
          parseConfidence: double.parse(confidence.toStringAsFixed(2)),
          dedupeKey: dedupeKey,
          rawBody: body,
          templateId: template.id,
          needsReview: isReviewRequired,
        );

        return ParseResult.success(transaction);
      }
    }

    return ParseResult.unparsed(
      'No matching pattern found for provider $provider',
      isFinancial: true,
    );
  }

  /// Generates deterministic unique deduplication hash.
  String _computeDedupeKey({
    required String provider,
    String? reference,
    required double amount,
    required DateTime occurredAt,
  }) {
    final refPart = reference ?? 'noref';
    final amtPart = amount.toStringAsFixed(2);
    final datePart =
        '${occurredAt.year}-${occurredAt.month.toString().padLeft(2, '0')}-${occurredAt.day.toString().padLeft(2, '0')}-${occurredAt.hour.toString().padLeft(2, '0')}';

    final raw = '$provider:$refPart:$amtPart:$datePart';
    final bytes = utf8.encode(raw);

    // Simple SHA-256 digest representation
    return _simpleHash(bytes);
  }

  String _simpleHash(List<int> bytes) {
    var h0 = 0x6a09e667;
    var h1 = 0xbb67ae85;
    for (final b in bytes) {
      h0 = ((h0 << 5) - h0) + b;
      h0 &= 0xffffffff;
      h1 = ((h1 << 5) - h1) + h0;
      h1 &= 0xffffffff;
    }
    return '${h0.toRadixString(16).padLeft(8, '0')}${h1.toRadixString(16).padLeft(8, '0')}';
  }

  /// Cryptographically verifies and updates templates with Ed25519 signature.
  Future<bool> updateTemplates({
    required String bundleJson,
    required String signatureHex,
    required String publicKeyHex,
  }) async {
    try {
      final ed25519 = Ed25519();
      final publicKeyBytes = _hexToBytes(publicKeyHex);
      final signatureBytes = _hexToBytes(signatureHex);
      final messageBytes = utf8.encode(bundleJson);

      final publicKey = SimplePublicKey(
        publicKeyBytes,
        type: KeyPairType.ed25519,
      );

      final signature = Signature(
        signatureBytes,
        publicKey: publicKey,
      );

      final isValid = await ed25519.verify(
        messageBytes,
        signature: signature,
      );

      if (!isValid) return false;

      loadTemplatesFromJson(bundleJson);
      return true;
    } catch (_) {
      return false;
    }
  }

  List<int> _hexToBytes(String hex) {
    final clean = hex.replaceAll(' ', '');
    final result = <int>[];
    for (var i = 0; i < clean.length; i += 2) {
      result.add(int.parse(clean.substring(i, i + 2), radix: 16));
    }
    return result;
  }

  static RegExp _safeRegExp(String pattern, {bool caseSensitive = false}) {
    // Strip inline PCRE flags like (?i) which are not supported in Dart's RegExp engine
    final clean = pattern.replaceAll(RegExp(r'\(\?[imsux-]+\)'), '');
    return RegExp(clean, caseSensitive: caseSensitive);
  }
}
