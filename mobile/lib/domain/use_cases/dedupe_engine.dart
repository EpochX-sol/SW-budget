import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Generates deterministic deduplication keys for financial transactions
/// to prevent duplicate recording from simultaneous SMS and Notification streams.
class DedupeEngine {
  /// Generates a dedupe key based on bank transaction reference or content hash
  static String generateKey({
    required String provider, // 'CBE', 'TELEBIRR', 'BOA', 'CASH'
    String? reference,
    required String sender,
    required double amount,
    required String type,
    required DateTime occurredAt,
    String? counterparty,
  }) {
    final cleanProvider = provider.trim().toLowerCase();

    // 1. If bank provided a transaction reference, it is the primary unique identifier
    if (reference != null && reference.trim().isNotEmpty) {
      final cleanRef = reference.trim().replaceAll(RegExp(r'\s+'), '').toLowerCase();
      return '${cleanProvider}_$cleanRef';
    }

    // 2. Fallback to composite fingerprint hashed with SHA-256
    // Time resolution truncated to minute level to accommodate slight SMS vs notification arrival delays
    final minuteWindow =
        '${occurredAt.year}-${occurredAt.month.toString().padLeft(2, '0')}-${occurredAt.day.toString().padLeft(2, '0')}_${occurredAt.hour.toString().padLeft(2, '0')}:${occurredAt.minute.toString().padLeft(2, '0')}';
    final amtString = amount.toStringAsFixed(2);
    final partyString = (counterparty ?? '').trim().toLowerCase();

    final rawComposite =
        '$cleanProvider|$sender|$amtString|$type|$partyString|$minuteWindow';

    final bytes = utf8.encode(rawComposite);
    final digest = sha256.convert(bytes);
    return '${cleanProvider}_hash_${digest.toString().substring(0, 16)}';
  }
}
