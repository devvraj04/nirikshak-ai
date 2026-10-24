import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class ScanLoadingView extends StatefulWidget {
  final double progress;

  const ScanLoadingView({super.key, required this.progress});

  @override
  State<ScanLoadingView> createState() => _ScanLoadingViewState();
}

class _ScanLoadingViewState extends State<ScanLoadingView> with TickerProviderStateMixin {
  late final AnimationController _radarController;
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();

    _radarController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _radarController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  String _getDiagnosticStatus(double progress) {
    if (progress < 0.25) {
      return 'Uploading packaging labels & calibrating sensors...';
    } else if (progress < 0.55) {
      return 'AI OCR scanning text & reading barcodes...';
    } else if (progress < 0.85) {
      return 'Extracting MRP, Net Quantity & FSSAI declarations...';
    } else if (progress < 0.999) {
      return 'Cross-referencing Legal Metrology Rules...';
    } else {
      return 'Metrology node verified.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Container(
      color: const Color(0xFFFBF9F3),
      width: double.infinity,
      height: double.infinity,
      child: Stack(
        children: [
          // Ambient Radial Mesh Glow
          Positioned(
            top: size.height * 0.16,
            left: size.width * 0.1,
            right: size.width * 0.1,
            child: Container(
              height: 320,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF10B981).withValues(alpha: 0.14),
                    const Color(0xFF34D399).withValues(alpha: 0.05),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.55, 1.0],
                ),
              ),
            ),
          ),

          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // 1. Top Certification Pill Badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8F5E9).withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(color: const Color(0xFFA7F3D0), width: 1.2),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF10B981).withValues(alpha: 0.08),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AnimatedBuilder(
                            animation: _pulseController,
                            builder: (context, child) {
                              return Container(
                                width: 7,
                                height: 7,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: const Color(0xFF059669),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF10B981).withValues(alpha: 0.4 + (_pulseController.value * 0.5)),
                                      blurRadius: 6,
                                      spreadRadius: _pulseController.value * 2,
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                          const SizedBox(width: 7),
                          Text(
                            'LEGAL METROLOGY DEPT. CERTIFIED',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.7,
                              color: const Color(0xFF006948),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 36),

                    // 2. Center Radar Reticle & Logo Showcase
                    SizedBox(
                      width: 230,
                      height: 230,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Animated Radar Scanner Canvas
                          AnimatedBuilder(
                            animation: _radarController,
                            builder: (context, child) {
                              return CustomPaint(
                                size: const Size(230, 230),
                                painter: _RadarReticlePainter(
                                  sweepAngle: _radarController.value * 2 * math.pi,
                                ),
                              );
                            },
                          ),

                          // The Glowing Glassmorphic Card Housing the Logo
                          Container(
                            width: 136,
                            height: 136,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(28),
                              border: Border.all(
                                color: const Color(0xFF6EE7B7),
                                width: 2.2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF10B981).withValues(alpha: 0.22),
                                  blurRadius: 28,
                                  spreadRadius: 3,
                                  offset: const Offset(0, 8),
                                ),
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.04),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            padding: const EdgeInsets.all(16),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: Image.asset(
                                'assets/images/nirikshak_logo.jpeg',
                                fit: BoxFit.contain,
                                errorBuilder: (context, error, stackTrace) {
                                  return const Icon(
                                    Icons.shield_rounded,
                                    size: 64,
                                    color: Color(0xFF006948),
                                  );
                                },
                              ),
                            ),
                          ),

                          // Pinned "LMPC RADAR READY" Badge Overlapping the Card Base
                          Positioned(
                            bottom: 22,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4.5),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0F172A),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: const Color(0xFF334155),
                                  width: 1,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.18),
                                    blurRadius: 8,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 6,
                                    height: 6,
                                    decoration: const BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Color(0xFF34D399),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'LMPC RADAR READY',
                                    style: GoogleFonts.jetBrainsMono(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.8,
                                      color: const Color(0xFF34D399),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 26),

                    // 3. Brand Identity Headline
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          'Nirikshak',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 30,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.8,
                            color: const Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE8F5E9),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFA7F3D0), width: 1.2),
                          ),
                          child: Text(
                            'AI',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: const Color(0xFF006948),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 6),

                    Text(
                      'NIRIKSHAK METROLOGY NETWORK',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                        color: const Color(0xFF565E74),
                      ),
                    ),

                    const SizedBox(height: 8),

                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Text(
                        'Securing Fair Pricing & Statutory Standards\nfor Packaged Commodities',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: const Color(0xFF64748B),
                          height: 1.45,
                        ),
                      ),
                    ),

                    const SizedBox(height: 44),

                    // 4. Dynamic Diagnostic Progress Bar & Status Readout
                    TweenAnimationBuilder<double>(
                      tween: Tween<double>(begin: 0.0, end: widget.progress.clamp(0.0, 1.0)),
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOutCubic,
                      builder: (context, smoothVal, child) {
                        final percent = (smoothVal * 100).toInt();
                        final isComplete = smoothVal >= 0.999;

                        return Column(
                          children: [
                            // Milestone Label & Percentage
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    _getDiagnosticStatus(smoothVal),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: isComplete ? const Color(0xFF006948) : const Color(0xFF475569),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '$percent%',
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: const Color(0xFF0F172A),
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 8),

                            // Sleek Rounded Gradient Progress Track
                            Container(
                              height: 6,
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: const Color(0xFFE2E8F0),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Stack(
                                children: [
                                  FractionallySizedBox(
                                    widthFactor: smoothVal.clamp(0.0, 1.0),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(10),
                                        gradient: const LinearGradient(
                                          colors: [
                                            Color(0xFF00855D),
                                            Color(0xFF34D399),
                                            Color(0xFF68DBA9),
                                          ],
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: const Color(0xFF10B981).withValues(alpha: 0.4),
                                            blurRadius: 8,
                                            offset: const Offset(0, 1),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 14),

                            // Synchronized Confirmation Status
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  isComplete ? Icons.check_circle_rounded : Icons.sync_rounded,
                                  size: 16,
                                  color: isComplete ? const Color(0xFF059669) : const Color(0xFF10B981),
                                ),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    isComplete
                                        ? 'All Systems Synchronized · Rendering Compliance Report'
                                        : 'Calibrating National Metrology Grid...',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                      color: isComplete ? const Color(0xFF065F46) : const Color(0xFF0D9488),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        );
                      },
                    ),

                    const SizedBox(height: 32),

                    // 5. Statutory Verification Footer
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6.5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.security_rounded, size: 13, color: Color(0xFF475569)),
                          const SizedBox(width: 6),
                          Text(
                            'LMPC Act 2009 & Rule 18(2) Certified',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF64748B),
                              letterSpacing: 0.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Custom painter that renders the futuristic radar reticle and corner brackets
class _RadarReticlePainter extends CustomPainter {
  final double sweepAngle;

  _RadarReticlePainter({required this.sweepAngle});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()..isAntiAlias = true;

    // 1. Concentric Faint Radar Circles
    paint
      ..color = const Color(0xFF10B981).withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    canvas.drawCircle(center, 100, paint);
    canvas.drawCircle(center, 74, paint);

    // 2. Animated Rotating Radar Sweep Beam
    final sweepPaint = Paint()
      ..shader = SweepGradient(
        colors: [
          const Color(0xFF10B981).withValues(alpha: 0.0),
          const Color(0xFF10B981).withValues(alpha: 0.0),
          const Color(0xFF34D399).withValues(alpha: 0.22),
        ],
        stops: const [0.0, 0.75, 1.0],
        transform: GradientRotation(sweepAngle),
      ).createShader(Rect.fromCircle(center: center, radius: 100))
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, 100, sweepPaint);

    // 3. Four Emerald Corner L-Brackets
    final bracketPaint = Paint()
      ..color = const Color(0xFF10B981)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;

    const double bracketSize = 20.0;
    const double inset = 16.0;

    // Top-Left Bracket
    canvas.drawLine(const Offset(inset, inset), const Offset(inset + bracketSize, inset), bracketPaint);
    canvas.drawLine(const Offset(inset, inset), const Offset(inset, inset + bracketSize), bracketPaint);

    // Top-Right Bracket
    canvas.drawLine(Offset(size.width - inset, inset), Offset(size.width - inset - bracketSize, inset), bracketPaint);
    canvas.drawLine(Offset(size.width - inset, inset), Offset(size.width - inset, inset + bracketSize), bracketPaint);

    // Bottom-Left Bracket
    canvas.drawLine(Offset(inset, size.height - inset), Offset(inset + bracketSize, size.height - inset), bracketPaint);
    canvas.drawLine(Offset(inset, size.height - inset), Offset(inset, size.height - inset - bracketSize), bracketPaint);

    // Bottom-Right Bracket
    canvas.drawLine(Offset(size.width - inset, size.height - inset), Offset(size.width - inset - bracketSize, size.height - inset), bracketPaint);
    canvas.drawLine(Offset(size.width - inset, size.height - inset), Offset(size.width - inset, size.height - inset - bracketSize), bracketPaint);

    // 4. Four Crosshair Axis Tick Marks
    final tickPaint = Paint()
      ..color = const Color(0xFF10B981).withValues(alpha: 0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;

    // Top tick
    canvas.drawLine(Offset(center.dx, inset - 3), Offset(center.dx, inset + 4), tickPaint);
    // Bottom tick
    canvas.drawLine(Offset(center.dx, size.height - inset + 3), Offset(center.dx, size.height - inset - 4), tickPaint);
    // Left tick
    canvas.drawLine(Offset(inset - 3, center.dy), Offset(inset + 4, center.dy), tickPaint);
    // Right tick
    canvas.drawLine(Offset(size.width - inset + 3, center.dy), Offset(size.width - inset - 4, center.dy), tickPaint);
  }

  @override
  bool shouldRepaint(covariant _RadarReticlePainter oldDelegate) {
    return oldDelegate.sweepAngle != sweepAngle;
  }
}
