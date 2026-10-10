import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class StatementTransactionItem {
  final DateTime date;
  final String description;
  final String? reference;
  final String type; // 'expense' or 'income'
  final double amount;
  final double runningBalance;

  const StatementTransactionItem({
    required this.date,
    required this.description,
    this.reference,
    required this.type,
    required this.amount,
    required this.runningBalance,
  });
}

class BankStatementPdfService {
  /// Generates a vector PDF bank statement on-device with Ethiopian bank branding.
  static Future<Uint8List> generateStatementBytes({
    required String bankName,
    required String accountHolderName,
    required String accountNumber,
    required DateTime startDate,
    required DateTime endDate,
    required double openingBalance,
    required List<StatementTransactionItem> items,
  }) async {
    final pdf = pw.Document();

    double totalDebit = 0;
    double totalCredit = 0;
    for (final item in items) {
      if (item.type.toLowerCase() == 'expense') {
        totalDebit += item.amount;
      } else {
        totalCredit += item.amount;
      }
    }
    final closingBalance = openingBalance + totalCredit - totalDebit;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return [
            // Bank Header
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      bankName.toUpperCase(),
                      style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: PdfColors.indigo900),
                    ),
                    pw.Text('OFFICIAL ACCOUNT STATEMENT', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('Generated via SW-budget', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
                    pw.Text('Date: ${DateTime.now().toIso8601String().substring(0, 10)}', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
                  ],
                ),
              ],
            ),
            pw.Divider(thickness: 1, color: PdfColors.indigo900),
            pw.SizedBox(height: 12),

            // Account Holder & Date Range Box
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey100,
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('Account Holder: $accountHolderName', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
                      pw.SizedBox(height: 4),
                      pw.Text('Account Number: $accountNumber', style: const pw.TextStyle(fontSize: 10)),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text('Period Start: ${startDate.toIso8601String().substring(0, 10)}', style: const pw.TextStyle(fontSize: 10)),
                      pw.SizedBox(height: 4),
                      pw.Text('Period End: ${endDate.toIso8601String().substring(0, 10)}', style: const pw.TextStyle(fontSize: 10)),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 16),

            // Financial Summary Cards
            pw.Row(
              children: [
                _buildSummaryBox('Opening Balance', '${openingBalance.toStringAsFixed(2)} ETB'),
                pw.SizedBox(width: 8),
                _buildSummaryBox('Total Debits', '-${totalDebit.toStringAsFixed(2)} ETB', color: PdfColors.red800),
                pw.SizedBox(width: 8),
                _buildSummaryBox('Total Credits', '+${totalCredit.toStringAsFixed(2)} ETB', color: PdfColors.green800),
                pw.SizedBox(width: 8),
                _buildSummaryBox('Closing Balance', '${closingBalance.toStringAsFixed(2)} ETB', isBold: true),
              ],
            ),
            pw.SizedBox(height: 20),

            // Transactions Table
            pw.Text('TRANSACTION ACTIVITY', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.indigo900)),
            pw.SizedBox(height: 8),
            pw.TableHelper.fromTextArray(
              headers: ['Date', 'Description', 'Reference', 'Debit (ETB)', 'Credit (ETB)', 'Balance (ETB)'],
              headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.indigo900),
              cellStyle: const pw.TextStyle(fontSize: 8),
              cellAlignment: pw.Alignment.centerLeft,
              data: items.map((t) {
                final dateStr = t.date.toIso8601String().substring(0, 10);
                final isDebit = t.type.toLowerCase() == 'expense';
                return [
                  dateStr,
                  t.description,
                  t.reference ?? '-',
                  isDebit ? t.amount.toStringAsFixed(2) : '-',
                  !isDebit ? t.amount.toStringAsFixed(2) : '-',
                  t.runningBalance.toStringAsFixed(2),
                ];
              }).toList(),
            ),
          ];
        },
      ),
    );

    return pdf.save();
  }

  static pw.Widget _buildSummaryBox(String title, String amount, {PdfColor? color, bool isBold = false}) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.all(8),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey300),
          borderRadius: pw.BorderRadius.circular(4),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(title, style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
            pw.SizedBox(height: 4),
            pw.Text(
              amount,
              style: pw.TextStyle(fontSize: 10, fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal, color: color ?? PdfColors.black),
            ),
          ],
        ),
      ),
    );
  }
}
