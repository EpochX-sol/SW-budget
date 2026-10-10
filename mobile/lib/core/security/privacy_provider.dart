import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

final privacyModeProvider = StateProvider<bool>((ref) => false);

String formatCurrency(num amount, {bool isPrivate = false, bool showSymbol = true}) {
  if (isPrivate) {
    return showSymbol ? 'ETB ••••' : '••••';
  }
  final formatter = NumberFormat('#,##0.00', 'en_US');
  final formatted = formatter.format(amount);
  return showSymbol ? 'ETB $formatted' : formatted;
}
