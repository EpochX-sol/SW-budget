import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:cryptography/cryptography.dart';
import 'package:sw_budget/data/parser/financial_parser.dart';
import 'package:sw_budget/data/parser/normalizer/text_normalizer.dart';
import 'fixtures/golden_sms_fixtures.dart';

void main() {
  group('Milestone F1: Pure Dart Financial SMS & Notification Parser', () {
    late FinancialParser parser;
    late String defaultBundleJson;

    setUpAll(() async {
      // Read the default template bundle asset from disk
      final file = File('assets/templates/default_bundle.json');
      if (await file.exists()) {
        defaultBundleJson = await file.readAsString();
      } else {
        // Fallback relative path for test execution
        defaultBundleJson =
            await File('../assets/templates/default_bundle.json').readAsString();
      }
    });

    setUp(() {
      parser = FinancialParser();
      parser.loadTemplatesFromJson(defaultBundleJson);
    });

    // ─────────────────────────────────────────────────────────────
    // 1. Text Normalizer Unit Tests
    // ─────────────────────────────────────────────────────────────
    group('TextNormalizer Unit Tests', () {
      test('cleans invisible zero-width spaces and collapses whitespace', () {
        const dirty = 'Hello\u200B \u200Cworld   from\u00A0Addis\n\nAbaba';
        final cleaned = TextNormalizer.sanitize(dirty);
        expect(cleaned, 'Hello world from Addis Ababa');
      });

      test('normalizes Amharic and English currency denominations to ETB', () {
        expect(TextNormalizer.normalizeCurrencies('150 ብር'), '150 ETB');
        expect(TextNormalizer.normalizeCurrencies('paid 200 birr'), 'paid 200 ETB');
        expect(TextNormalizer.normalizeCurrencies('transferred 500 Birr'),
            'transferred 500 ETB');
        expect(TextNormalizer.normalizeCurrencies('ETB500'), 'ETB 500');
      });

      test('converts Ge\'ez single numerals to Arabic digits', () {
        expect(TextNormalizer.normalizeGeezNumerals('ቀን ፩'), 'ቀን 1');
        expect(TextNormalizer.normalizeGeezNumerals('ቁጥር ፭'), 'ቁጥር 5');
        expect(TextNormalizer.normalizeGeezNumerals('ደረጃ ፱'), 'ደረጃ 9');
      });

      test('parses numeric string amounts with commas correctly', () {
        expect(TextNormalizer.parseAmount('1,250.50'), 1250.50);
        expect(TextNormalizer.parseAmount('25,000.00'), 25000.00);
        expect(TextNormalizer.parseAmount(' 350 '), 350.0);
        expect(TextNormalizer.parseAmount('invalid'), isNull);
        expect(TextNormalizer.parseAmount(null), isNull);
      });
    });

    // ─────────────────────────────────────────────────────────────
    // 2. 50+ Golden Regression Test Suite
    // ─────────────────────────────────────────────────────────────
    group('Golden SMS Regression Suite (50+ Ethiopian Bank Messages)', () {
      test('has at least 50 golden fixtures defined', () {
        expect(goldenSmsFixtures.length, greaterThanOrEqualTo(50));
      });

      for (final fixture in goldenSmsFixtures) {
        test('evaluates fixture: [${fixture.id}] from ${fixture.sender}', () {
          final result = parser.parse(
            sender: fixture.sender,
            body: fixture.body,
            receivedAt: DateTime(2026, 10, 7, 10, 15),
          );

          if (!fixture.isFinancial) {
            // Negative test case: must not produce a financial transaction
            expect(result.isSuccess, isFalse,
                reason: 'Expected non-financial for ${fixture.id}');
          } else {
            // Positive test case: must successfully parse with exact fields
            expect(result.isSuccess, isTrue,
                reason: 'Failed to parse ${fixture.id}: ${result.failureReason}');
            final txn = result.transaction!;

            if (fixture.expectedProvider != null) {
              expect(txn.provider, fixture.expectedProvider,
                  reason: 'Provider mismatch for ${fixture.id}');
            }

            if (fixture.expectedType != null) {
              expect(txn.type, fixture.expectedType,
                  reason: 'Type mismatch for ${fixture.id}');
            }

            if (fixture.expectedAmount != null) {
              expect(txn.amount, fixture.expectedAmount,
                  reason: 'Amount mismatch for ${fixture.id}');
            }

            if (fixture.expectedBalance != null) {
              expect(txn.balanceAfter, fixture.expectedBalance,
                  reason: 'Balance mismatch for ${fixture.id}');
            }

            if (fixture.expectedReference != null) {
              expect(txn.reference, fixture.expectedReference,
                  reason: 'Reference mismatch for ${fixture.id}');
            }

            expect(txn.dedupeKey, isNotEmpty,
                reason: 'Dedupe key must not be empty');
            expect(txn.parseConfidence, greaterThanOrEqualTo(0.60));
          }
        });
      }
    });

    // ─────────────────────────────────────────────────────────────
    // 3. Deduplication Key Stability Tests
    // ─────────────────────────────────────────────────────────────
    group('Deduplication Key Stability', () {
      test('generates identical dedupe keys for identical financial events', () {
        final time = DateTime(2026, 10, 7, 14, 20);
        final res1 = parser.parse(
          sender: 'CBE',
          body: 'Your account debited with ETB 200.00 to Kaldis. Bal: 1000. Ref: FT9988.',
          receivedAt: time,
        );
        final res2 = parser.parse(
          sender: 'CBE',
          body: 'Your account debited with ETB 200.00 to Kaldis. Bal: 1000. Ref: FT9988.',
          receivedAt: time,
        );

        expect(res1.isSuccess, isTrue);
        expect(res2.isSuccess, isTrue);
        expect(res1.transaction!.dedupeKey, res2.transaction!.dedupeKey);
      });

      test('generates distinct dedupe keys for different transactions', () {
        final time = DateTime(2026, 10, 7, 14, 20);
        final res1 = parser.parse(
          sender: 'CBE',
          body: 'Your account debited with ETB 200.00 to Kaldis. Bal: 1000. Ref: FT9988.',
          receivedAt: time,
        );
        final res2 = parser.parse(
          sender: 'CBE',
          body: 'Your account debited with ETB 500.00 to Kaldis. Bal: 700. Ref: FT9989.',
          receivedAt: time,
        );

        expect(res1.transaction!.dedupeKey,
            isNot(equals(res2.transaction!.dedupeKey)));
      });
    });

    // ─────────────────────────────────────────────────────────────
    // 4. Ed25519 Cryptographic Template Bundle Verification
    // ─────────────────────────────────────────────────────────────
    group('Ed25519 Cryptographic Template Bundle Verification', () {
      test('verifies genuine signed template bundle and rejects tampered bundle',
          () async {
        final algorithm = Ed25519();
        final keyPair = await algorithm.newKeyPair();
        final publicKey = await keyPair.extractPublicKey();

        final rawBundle = defaultBundleJson;
        final signature = await algorithm.sign(
          utf8.encode(rawBundle),
          keyPair: keyPair,
        );

        final pubKeyHex = _bytesToHex(publicKey.bytes);
        final signatureHex = _bytesToHex(signature.bytes);

        // 1. Verify valid signature succeeds
        final isValid = await parser.updateTemplates(
          bundleJson: rawBundle,
          signatureHex: signatureHex,
          publicKeyHex: pubKeyHex,
        );
        expect(isValid, isTrue);

        // 2. Tampered content fails verification
        const tamperedBundle = '{"bundle_version": 99, "templates": []}';
        final isTamperedValid = await parser.updateTemplates(
          bundleJson: tamperedBundle,
          signatureHex: signatureHex,
          publicKeyHex: pubKeyHex,
        );
        expect(isTamperedValid, isFalse);
      });
    });
  });
}

String _bytesToHex(List<int> bytes) {
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}
