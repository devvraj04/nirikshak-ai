import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image_picker/image_picker.dart';
import '../core/theme.dart';
import 'glass_card.dart';

enum SnipMode { freeformCircle, boxSelect }

class CircleToSearchCanvas extends StatefulWidget {
  final Function(File snipFile, String labelSuggestion) onRegionSnipped;
  final VoidCallback onCancel;
  final int currentStagedCount;

  const CircleToSearchCanvas({
    super.key,
    required this.onRegionSnipped,
    required this.onCancel,
    this.currentStagedCount = 0,
  });

  @override
  State<CircleToSearchCanvas> createState() => _CircleToSearchCanvasState();
}

class _CircleToSearchCanvasState extends State<CircleToSearchCanvas>
    with SingleTickerProviderStateMixin {
  final GlobalKey _repaintBoundaryKey = GlobalKey();
  final ImagePicker _picker = ImagePicker();

  SnipMode _mode = SnipMode.freeformCircle;
  List<Offset> _points = [];
  Offset? _boxStart;
  Offset? _boxEnd;
  bool _isSnipping = false;
  Rect? _capturedRect;

  late final AnimationController _pulseController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _onPanStart(DragStartDetails details) {
    setState(() {
      _capturedRect = null;
      if (_mode == SnipMode.freeformCircle) {
        _points = [details.localPosition];
      } else {
        _boxStart = details.localPosition;
        _boxEnd = details.localPosition;
      }
    });
  }

  void _onPanUpdate(DragUpdateDetails details) {
    setState(() {
      if (_mode == SnipMode.freeformCircle) {
        _points.add(details.localPosition);
      } else {
        _boxEnd = details.localPosition;
      }
    });
  }

  Future<void> _onPanEnd(DragEndDetails details) async {
    Rect? bounds;
    if (_mode == SnipMode.freeformCircle && _points.length > 5) {
      final Path path = Path()..addPolygon(_points, true);
      bounds = path.getBounds();
    } else if (_mode == SnipMode.boxSelect && _boxStart != null && _boxEnd != null) {
      bounds = Rect.fromPoints(_boxStart!, _boxEnd!);
    }

    if (bounds != null && bounds.width > 30 && bounds.height > 30) {
      setState(() {
        _capturedRect = bounds;
        _isSnipping = true;
      });

      // Capture rendered widget sub-region
      await _cropCanvasRegion(bounds);
    } else {
      setState(() {
        _points.clear();
        _boxStart = null;
        _boxEnd = null;
      });
    }
  }

  Future<void> _cropCanvasRegion(Rect rect) async {
    try {
      final RenderRepaintBoundary? boundary = _repaintBoundaryKey.currentContext
          ?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;

      final ui.Image fullImage = await boundary.toImage(pixelRatio: 2.0);
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      // Clamp rect within image bounds
      const double scale = 2.0;
      final scaledRect = Rect.fromLTWH(
        rect.left * scale,
        rect.top * scale,
        rect.width * scale,
        rect.height * scale,
      );

      final paint = Paint();
      canvas.drawImageRect(
        fullImage,
        scaledRect,
        Rect.fromLTWH(0, 0, scaledRect.width, scaledRect.height),
        paint,
      );

      final picture = recorder.endRecording();
      final ui.Image cropped = await picture.toImage(
        scaledRect.width.toInt().clamp(10, 4096),
        scaledRect.height.toInt().clamp(10, 4096),
      );

      final byteData = await cropped.toByteData(format: ui.ImageByteFormat.png);
      if (byteData != null) {
        final buffer = byteData.buffer.asUint8List();
        final tempDir = Directory.systemTemp;
        final file = File('${tempDir.path}/snip_${DateTime.now().millisecondsSinceEpoch}.png');
        await file.writeAsBytes(buffer);

        String suggestedLabel = 'Front';
        if (widget.currentStagedCount == 1) suggestedLabel = 'Back';
        if (widget.currentStagedCount == 2) suggestedLabel = 'Nutrition';
        if (widget.currentStagedCount >= 3) suggestedLabel = 'Ingredients';

        widget.onRegionSnipped(file, suggestedLabel);
      }
    } catch (e) {
      debugPrint('Error cropping region: $e');
    } finally {
      if (mounted) setState(() => _isSnipping = false);
    }
  }

  Future<void> _pickFromGallery() async {
    final XFile? img = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 88);
    if (img != null) {
      widget.onRegionSnipped(File(img.path), 'Front');
    }
  }

  Future<void> _snapWithCamera() async {
    final XFile? img = await _picker.pickImage(source: ImageSource.camera, imageQuality: 88);
    if (img != null) {
      widget.onRegionSnipped(File(img.path), 'Front');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // 1. RepaintBoundary capturing backdrop
        RepaintBoundary(
          key: _repaintBoundaryKey,
          child: Container(
            color: Colors.black.withValues(alpha: 0.72),
            width: double.infinity,
            height: double.infinity,
          ),
        ),

        // 2. Gesture Detector for freeform circling or box drag
        Positioned.fill(
          child: GestureDetector(
            onPanStart: _onPanStart,
            onPanUpdate: _onPanUpdate,
            onPanEnd: _onPanEnd,
            child: CustomPaint(
              painter: _SnipPainter(
                points: _points,
                boxStart: _boxStart,
                boxEnd: _boxEnd,
                capturedRect: _capturedRect,
                mode: _mode,
                pulseAnimation: _pulseController,
              ),
              size: Size.infinite,
            ),
          ),
        ),

        // 3. Top Control Bar (Circle to Search title, mode toggles, cancel)
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Title Pill
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.blur_circular_rounded, color: AppTheme.emerald600, size: 18),
                      const SizedBox(width: 6),
                      const Text(
                        'Circle to Search',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.slate900),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.emerald100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${widget.currentStagedCount}/4',
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppTheme.emerald800),
                        ),
                      ),
                    ],
                  ),
                ),

                // Close Button
                GestureDetector(
                  onTap: widget.onCancel,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.9),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close_rounded, size: 20, color: AppTheme.slate900),
                  ),
                ),
              ],
            ),
          ),
        ),

        // 4. Mode Switcher & Alternative Import Bar (Bottom)
        Positioned(
          left: 16,
          right: 16,
          bottom: 30,
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Floating Instructions Hint
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: AppTheme.slate900.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.draw_rounded, color: AppTheme.emerald400, size: 16),
                      const SizedBox(width: 8),
                      Text(
                        _mode == SnipMode.freeformCircle
                            ? 'Circle any packaging image, label, or MRP on screen'
                            : 'Drag box over any packaging declaration',
                        style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Action Bar: Freeform | Box | Camera | Gallery
                GlassCard(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  borderRadius: 24,
                  backgroundColor: Colors.white.withValues(alpha: 0.92),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildBottomAction(
                        icon: Icons.gesture_rounded,
                        label: 'Lasso',
                        isActive: _mode == SnipMode.freeformCircle,
                        onTap: () => setState(() => _mode = SnipMode.freeformCircle),
                      ),
                      _buildBottomAction(
                        icon: Icons.crop_square_rounded,
                        label: 'Box',
                        isActive: _mode == SnipMode.boxSelect,
                        onTap: () => setState(() => _mode = SnipMode.boxSelect),
                      ),
                      const VerticalDivider(width: 1, thickness: 1, color: AppTheme.slate200),
                      _buildBottomAction(
                        icon: Icons.camera_alt_rounded,
                        label: 'Camera',
                        isActive: false,
                        onTap: _snapWithCamera,
                      ),
                      _buildBottomAction(
                        icon: Icons.photo_library_rounded,
                        label: 'Gallery',
                        isActive: false,
                        onTap: _pickFromGallery,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        // 5. Loading Indicator while cropping
        if (_isSnipping)
          Positioned.fill(
            child: Container(
              color: Colors.black.withValues(alpha: 0.5),
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: AppTheme.emerald400),
                    SizedBox(height: 12),
                    Text(
                      'Isolating & Scanning Region...',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildBottomAction({
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? AppTheme.slate900 : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: isActive ? AppTheme.emerald400 : AppTheme.slate700),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isActive ? FontWeight.bold : FontWeight.w600,
                color: isActive ? Colors.white : AppTheme.slate700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SnipPainter extends CustomPainter {
  final List<Offset> points;
  final Offset? boxStart;
  final Offset? boxEnd;
  final Rect? capturedRect;
  final SnipMode mode;
  final Animation<double> pulseAnimation;

  _SnipPainter({
    required this.points,
    required this.boxStart,
    required this.boxEnd,
    required this.capturedRect,
    required this.mode,
    required this.pulseAnimation,
  }) : super(repaint: pulseAnimation);

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Neon glowing stroke for Freeform Lasso
    if (mode == SnipMode.freeformCircle && points.length > 1) {
      final glowPaint = Paint()
        ..color = const Color(0xFF10B981).withValues(alpha: 0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 9.0
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);

      final linePaint = Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFF34D399), Color(0xFF06B6D4), Color(0xFF10B981)],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      final Path path = Path()..moveTo(points.first.dx, points.first.dy);
      for (int i = 1; i < points.length; i++) {
        path.lineTo(points[i].dx, points[i].dy);
      }

      canvas.drawPath(path, glowPaint);
      canvas.drawPath(path, linePaint);
    }

    // 2. Rectangular Box Drag Selection
    if (mode == SnipMode.boxSelect && boxStart != null && boxEnd != null) {
      final rect = Rect.fromPoints(boxStart!, boxEnd!);
      final fillPaint = Paint()
        ..color = const Color(0xFF10B981).withValues(alpha: 0.15)
        ..style = PaintingStyle.fill;

      final borderPaint = Paint()
        ..color = const Color(0xFF34D399)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5;

      canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(8)), fillPaint);
      canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(8)), borderPaint);
    }

    // 3. Highlight Captured Rect with pulsing ring
    if (capturedRect != null) {
      final pulseVal = pulseAnimation.value;
      final ringPaint = Paint()
        ..color = const Color(0xFF34D399).withValues(alpha: 0.6 + (0.4 * pulseVal))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0 + (pulseVal * 2.0);

      canvas.drawRRect(
        RRect.fromRectAndRadius(capturedRect!, const Radius.circular(12)),
        ringPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SnipPainter oldDelegate) => true;
}
