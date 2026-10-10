import 'dart:math';
import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

class FlowBarChart extends StatelessWidget {
  final List<double> inflows;
  final List<double> outflows;
  final List<String> labels;
  final double height;

  const FlowBarChart({
    super.key,
    this.inflows = const [12000.0, 15000.0, 8000.0, 10000.0],
    this.outflows = const [4500.0, 5200.0, 4100.0, 4295.0],
    this.labels = const ['W1', 'W2', 'W3', 'W4'],
    this.height = 170,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: height,
          child: CustomPaint(
            painter: _FlowBarPainter(
              inflows: inflows,
              outflows: outflows,
              labels: labels,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _legendItem(AppColors.income, 'Inflow'),
            const SizedBox(width: 16),
            _legendItem(AppColors.expense, 'Outflow'),
          ],
        ),
      ],
    );
  }

  Widget _legendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 5),
        Text(label, style: const TextStyle(color: AppColors.text2, fontSize: 12)),
      ],
    );
  }
}

class _FlowBarPainter extends CustomPainter {
  final List<double> inflows;
  final List<double> outflows;
  final List<String> labels;

  const _FlowBarPainter({
    required this.inflows,
    required this.outflows,
    required this.labels,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final n = min(inflows.length, outflows.length);
    if (n == 0) return;

    final mid = size.height / 2 - 4;
    double maxVal = 1.0;
    for (int i = 0; i < n; i++) {
      maxVal = max(maxVal, max(inflows[i], outflows[i]));
    }

    const padH = 10.0;
    final totalW = size.width - 2 * padH;
    final barW = totalW / n;
    final w = max(2.0, barW * 0.7);

    // Baseline horizontal line
    final linePaint = Paint()
      ..color = AppColors.line2
      ..strokeWidth = 1.0;
    canvas.drawLine(Offset(padH, mid), Offset(size.width - padH, mid), linePaint);

    final inPaint = Paint()..color = AppColors.income;
    final outPaint = Paint()..color = AppColors.expense.withOpacity(0.9);

    for (int i = 0; i < n; i++) {
      final x = padH + i * barW + (barW - w) / 2;
      final hi = (inflows[i] / maxVal) * (mid - 14);
      final ho = (outflows[i] / maxVal) * (mid - 14);

      if (hi > 0) {
        final r = RRect.fromRectAndRadius(
          Rect.fromLTWH(x, mid - hi, w, hi),
          const Radius.circular(3),
        );
        canvas.drawRRect(r, inPaint);
      }

      if (ho > 0) {
        final r = RRect.fromRectAndRadius(
          Rect.fromLTWH(x, mid + 1, w, ho),
          const Radius.circular(3),
        );
        canvas.drawRRect(r, outPaint);
      }

      // Labels (show all if <= 12, or just start/end if dense)
      if (n <= 12 || i == 0 || i == n - 1) {
        final tp = TextPainter(
          text: TextSpan(
            text: labels.length > i ? labels[i] : '',
            style: const TextStyle(color: AppColors.text3, fontSize: 10),
          ),
          textDirection: TextDirection.ltr,
        )..layout();

        final labelX = (n <= 12) ? (x + w / 2 - tp.width / 2) : (i == 0 ? padH : size.width - padH - tp.width);
        tp.paint(canvas, Offset(labelX, size.height - tp.height));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _FlowBarPainter oldDelegate) => true;
}
