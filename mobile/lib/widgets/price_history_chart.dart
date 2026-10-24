import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/theme.dart';

class PriceHistoryChart extends StatefulWidget {
  final List<Map<String, dynamic>> priceHistory;
  final double? declaredMrp;
  final double height;

  const PriceHistoryChart({
    super.key,
    required this.priceHistory,
    this.declaredMrp,
    this.height = 200,
  });

  @override
  State<PriceHistoryChart> createState() => _PriceHistoryChartState();
}

class _PriceHistoryChartState extends State<PriceHistoryChart> {
  int? _selectedIndex;

  @override
  void initState() {
    super.initState();
    // Default to latest point
    if (widget.priceHistory.isNotEmpty) {
      _selectedIndex = widget.priceHistory.length - 1;
    }
  }

  @override
  void didUpdateWidget(covariant PriceHistoryChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.priceHistory.isNotEmpty &&
        (_selectedIndex == null || _selectedIndex! >= widget.priceHistory.length)) {
      _selectedIndex = widget.priceHistory.length - 1;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.priceHistory.isEmpty) {
      return Container(
        height: widget.height,
        alignment: Alignment.center,
        child: const Text(
          'No price surveillance data available.',
          style: TextStyle(color: AppTheme.slate400, fontSize: 12),
        ),
      );
    }

    final selected = (_selectedIndex != null && _selectedIndex! < widget.priceHistory.length)
        ? widget.priceHistory[_selectedIndex!]
        : widget.priceHistory.last;

    final selectedPrice = (selected['price'] as num?)?.toDouble() ?? 0.0;
    final selectedMrp = (selected['declared_mrp'] as num?)?.toDouble() ?? widget.declaredMrp ?? 0.0;
    final selectedTime = selected['time_label']?.toString() ?? '${selected['date']} (${selected['session']})';
    final selectedMarket = selected['marketplace']?.toString() ?? 'Marketplace';
    final isOvercharge = selected['is_overcharging'] == true || (selectedMrp > 0 && selectedPrice > selectedMrp);
    final variance = selectedPrice - selectedMrp;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Top Tooltip Inspection Pill
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isOvercharge
                ? const Color(0xFFFEF2F2)
                : const Color(0xFFF0FDF4),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isOvercharge
                  ? const Color(0xFFFCA5A5)
                  : const Color(0xFF86EFAC),
              width: 0.8,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Icon(
                      isOvercharge ? Icons.warning_rounded : Icons.trending_up_rounded,
                      size: 16,
                      color: isOvercharge ? AppTheme.dangerRed : AppTheme.emerald600,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            selectedTime,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.slate500,
                            ),
                          ),
                          Text(
                            selectedMarket,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.slate800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '₹ ${selectedPrice.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      fontFamily: 'monospace',
                      color: isOvercharge ? AppTheme.dangerRed : AppTheme.emerald600,
                    ),
                  ),
                  Text(
                    isOvercharge
                        ? '+₹${variance.toStringAsFixed(2)} Above MRP'
                        : (selectedMrp > 0
                            ? (variance == 0 ? 'Equal to MRP' : '-₹${(-variance).toStringAsFixed(2)} Discount')
                            : 'Normal'),
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.bold,
                      color: isOvercharge ? AppTheme.dangerRed : AppTheme.slate600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 10),

        // Custom Canvas Chart
        SizedBox(
          height: widget.height,
          width: double.infinity,
          child: LayoutBuilder(
            builder: (context, constraints) {
              return GestureDetector(
                onPanDown: (details) => _handleTouch(details.localPosition.dx, constraints.maxWidth),
                onPanUpdate: (details) => _handleTouch(details.localPosition.dx, constraints.maxWidth),
                child: CustomPaint(
                  size: Size(constraints.maxWidth, widget.height),
                  painter: _PriceCurvePainter(
                    priceHistory: widget.priceHistory,
                    declaredMrp: widget.declaredMrp,
                    selectedIndex: _selectedIndex,
                  ),
                ),
              );
            },
          ),
        ),

        const SizedBox(height: 8),

        // Legend Wrap
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 14,
          runSpacing: 4,
          children: [
            _buildLegendItem(
              color: AppTheme.emerald600,
              label: 'Marketplace Price (Twice-Daily)',
              isDashed: false,
            ),
            if (widget.declaredMrp != null && widget.declaredMrp! > 0)
              _buildLegendItem(
                color: const Color(0xFFE11D48),
                label: 'Pack MRP (₹${widget.declaredMrp!.toStringAsFixed(2)})',
                isDashed: true,
              ),
          ],
        ),
      ],
    );
  }

  void _handleTouch(double touchX, double totalWidth) {
    if (widget.priceHistory.isEmpty) return;
    final count = widget.priceHistory.length;
    if (count <= 1) {
      setState(() => _selectedIndex = 0);
      return;
    }

    const paddingH = 20.0;
    final chartWidth = totalWidth - (paddingH * 2);
    final relativeX = (touchX - paddingH).clamp(0.0, chartWidth);
    final index = ((relativeX / chartWidth) * (count - 1)).round().clamp(0, count - 1);

    if (_selectedIndex != index) {
      setState(() => _selectedIndex = index);
    }
  }

  Widget _buildLegendItem({required Color color, required String label, required bool isDashed}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 3,
          decoration: BoxDecoration(
            color: isDashed ? null : color,
            borderRadius: BorderRadius.circular(2),
            border: isDashed ? Border.all(color: color, width: 1.2) : null,
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w600,
            color: AppTheme.slate500,
          ),
        ),
      ],
    );
  }
}

class _PriceCurvePainter extends CustomPainter {
  final List<Map<String, dynamic>> priceHistory;
  final double? declaredMrp;
  final int? selectedIndex;

  _PriceCurvePainter({
    required this.priceHistory,
    this.declaredMrp,
    this.selectedIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (priceHistory.isEmpty) return;

    const paddingLeft = 24.0;
    const paddingRight = 16.0;
    const paddingTop = 16.0;
    const paddingBottom = 26.0;

    final drawWidth = size.width - paddingLeft - paddingRight;
    final drawHeight = size.height - paddingTop - paddingBottom;

    final prices = priceHistory.map((e) => (e['price'] as num?)?.toDouble() ?? 0.0).toList();
    if (declaredMrp != null && declaredMrp! > 0) {
      prices.add(declaredMrp!);
    }

    double minVal = prices.reduce(math.min);
    double maxVal = prices.reduce(math.max);

    // Give vertical breathing room
    if (maxVal == minVal) {
      maxVal += 10;
      minVal = math.max(0, minVal - 10);
    } else {
      final range = maxVal - minVal;
      maxVal += range * 0.15;
      minVal = math.max(0, minVal - range * 0.15);
    }

    final count = priceHistory.length;

    // Helper to calculate (x, y) coordinates
    Offset getPoint(int i) {
      final double x = count > 1
          ? paddingLeft + (i / (count - 1)) * drawWidth
          : paddingLeft + (drawWidth / 2);
      final double price = (priceHistory[i]['price'] as num?)?.toDouble() ?? 0.0;
      final double y = paddingTop + (1.0 - ((price - minVal) / (maxVal - minVal))) * drawHeight;
      return Offset(x, y);
    }

    // 1. Draw Subtle Gridlines & Y-Axis Labels
    final gridPaint = Paint()
      ..color = const Color(0xFFE2E8F0)
      ..strokeWidth = 0.6;

    const ySteps = 3;
    for (int s = 0; s <= ySteps; s++) {
      final y = paddingTop + (s / ySteps) * drawHeight;
      final val = maxVal - (s / ySteps) * (maxVal - minVal);
      canvas.drawLine(Offset(paddingLeft, y), Offset(size.width - paddingRight, y), gridPaint);

      final textSpan = TextSpan(
        text: '₹${val.round()}',
        style: const TextStyle(
          color: Color(0xFF94A3B8),
          fontSize: 8.5,
          fontFamily: 'monospace',
          fontWeight: FontWeight.w600,
        ),
      );
      final tp = TextPainter(text: textSpan, textDirection: TextDirection.ltr)..layout();
      tp.paint(canvas, Offset(0, y - tp.height / 2));
    }

    // 2. Draw Declared MRP Dotted Baseline (if available)
    if (declaredMrp != null && declaredMrp! > 0) {
      final mrpY = paddingTop + (1.0 - ((declaredMrp! - minVal) / (maxVal - minVal))) * drawHeight;
      final mrpPaint = Paint()
        ..color = const Color(0xFFF43F5E).withValues(alpha: 0.8)
        ..strokeWidth = 1.2;

      // Draw dashed line
      const dashWidth = 4.0;
      const dashSpace = 3.0;
      double startX = paddingLeft;
      while (startX < size.width - paddingRight) {
        canvas.drawLine(
          Offset(startX, mrpY),
          Offset(math.min(startX + dashWidth, size.width - paddingRight), mrpY),
          mrpPaint,
        );
        startX += dashWidth + dashSpace;
      }
    }

    // 3. Build Smooth Spline (Cubic Bézier) Path
    final points = List.generate(count, (i) => getPoint(i));

    final path = Path();
    path.moveTo(points[0].dx, points[0].dy);

    for (int i = 0; i < points.length - 1; i++) {
      final p0 = points[i];
      final p1 = points[i + 1];
      final controlX = (p0.dx + p1.dx) / 2;
      path.cubicTo(controlX, p0.dy, controlX, p1.dy, p1.dx, p1.dy);
    }

    // 4. Fill Area Gradient Under Path
    final fillPath = Path.from(path);
    fillPath.lineTo(points.last.dx, paddingTop + drawHeight);
    fillPath.lineTo(points.first.dx, paddingTop + drawHeight);
    fillPath.close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          AppTheme.emerald600.withValues(alpha: 0.28),
          AppTheme.auraCyan.withValues(alpha: 0.12),
          Colors.white.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromLTWH(paddingLeft, paddingTop, drawWidth, drawHeight));

    canvas.drawPath(fillPath, fillPaint);

    // 5. Stroke Spline Line
    final linePaint = Paint()
      ..color = AppTheme.emerald600
      ..strokeWidth = 2.4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawPath(path, linePaint);

    // 6. Draw Points & Overcharging Warnings
    for (int i = 0; i < points.length; i++) {
      final pt = points[i];
      final item = priceHistory[i];
      final isOvercharge = item['is_overcharging'] == true ||
          (declaredMrp != null && declaredMrp! > 0 && ((item['price'] as num).toDouble()) > declaredMrp!);
      final isSelected = selectedIndex == i;

      // Outer glow for selected or overcharging
      if (isSelected || isOvercharge) {
        final glowPaint = Paint()
          ..color = (isOvercharge ? AppTheme.dangerRed : AppTheme.emerald600).withValues(alpha: 0.25)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(pt, isSelected ? 8.0 : 6.0, glowPaint);
      }

      // Point circle
      final ptPaint = Paint()
        ..color = isOvercharge ? AppTheme.dangerRed : Colors.white
        ..style = PaintingStyle.fill;
      canvas.drawCircle(pt, isSelected ? 4.5 : 3.0, ptPaint);

      final ptBorderPaint = Paint()
        ..color = isOvercharge ? AppTheme.dangerRed : AppTheme.emerald600
        ..strokeWidth = isSelected ? 2.2 : 1.5
        ..style = PaintingStyle.stroke;
      canvas.drawCircle(pt, isSelected ? 4.5 : 3.0, ptBorderPaint);

      // X-Axis Labels (Date / Session: every 2-3 points to avoid crowding)
      if (count <= 7 || i % 2 == 0 || i == count - 1) {
        final sessionShort = (item['session'] ?? '').toString().contains('AM') ? 'AM' : 'PM';
        final labelText = '${item['date'] ?? ''}\n$sessionShort';

        final xSpan = TextSpan(
          text: labelText,
          style: TextStyle(
            color: isSelected ? AppTheme.slate800 : const Color(0xFF94A3B8),
            fontSize: 7.5,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
            height: 1.1,
          ),
        );
        final xTp = TextPainter(text: xSpan, textAlign: TextAlign.center, textDirection: TextDirection.ltr)..layout();
        xTp.paint(canvas, Offset(pt.dx - xTp.width / 2, paddingTop + drawHeight + 4));
      }
    }

    // 7. Selected Vertical Indicator Line
    if (selectedIndex != null && selectedIndex! < points.length) {
      final selPt = points[selectedIndex!];
      final selLinePaint = Paint()
        ..color = AppTheme.slate400.withValues(alpha: 0.5)
        ..strokeWidth = 1.0
        ..style = PaintingStyle.stroke;

      canvas.drawLine(
        Offset(selPt.dx, paddingTop),
        Offset(selPt.dx, paddingTop + drawHeight),
        selLinePaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PriceCurvePainter oldDelegate) {
    return oldDelegate.priceHistory != priceHistory ||
        oldDelegate.declaredMrp != declaredMrp ||
        oldDelegate.selectedIndex != selectedIndex;
  }
}
