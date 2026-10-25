import 'dart:io';
import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../services/system_overlay_service.dart';
import 'circle_to_search_canvas.dart';
import 'multi_angle_staging_sheet.dart';

class FloatingOverlayBubble extends StatefulWidget {
  final Widget? child;

  const FloatingOverlayBubble({super.key, this.child});

  @override
  State<FloatingOverlayBubble> createState() => _FloatingOverlayBubbleState();
}

class _FloatingOverlayBubbleState extends State<FloatingOverlayBubble>
    with SingleTickerProviderStateMixin {
  // Bubble position
  double _x = 24.0;
  double _y = 220.0;
  bool _isDragging = false;

  // Active overlay state
  bool _isCircleToSearchOpen = false;
  bool _isStagingSheetOpen = false;

  // Staged slots (up to 4 images)
  final List<StagedImageSlot> _stagedSlots = [
    StagedImageSlot(slotId: 'front', title: 'Front Label'),
    StagedImageSlot(slotId: 'back', title: 'Declarations'),
    StagedImageSlot(slotId: 'left', title: 'Nutrition'),
    StagedImageSlot(slotId: 'right', title: 'Ingredients'),
  ];

  late final AnimationController _pulseController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat(reverse: true);

  @override
  void initState() {
    super.initState();
    SystemOverlayService.addCircleToSearchListener(_handleExternalCircleToSearchTrigger);
    SystemOverlayService.addSnipSubmittedListener(_handleExternalSnipSubmitted);
    SystemOverlayService.addReviewSubmittedListener(_handleExternalReviewSubmitted);
  }

  void _handleExternalCircleToSearchTrigger() {
    if (mounted) {
      _openCircleToSearch();
    }
  }

  void _handleExternalSnipSubmitted(String imagePath) {
    if (mounted) {
      _onRegionSnipped(File(imagePath), 'Front');
    }
  }

  void _handleExternalReviewSubmitted(List<String> imagePaths) {
    if (mounted) {
      for (int i = 0; i < imagePaths.length && i < _stagedSlots.length; i++) {
        _stagedSlots[i].file = File(imagePaths[i]);
      }
      setState(() {
        _isCircleToSearchOpen = false;
        _isStagingSheetOpen = true;
      });
    }
  }

  @override
  void dispose() {
    SystemOverlayService.removeCircleToSearchListener(_handleExternalCircleToSearchTrigger);
    SystemOverlayService.removeSnipSubmittedListener(_handleExternalSnipSubmitted);
    SystemOverlayService.removeReviewSubmittedListener(_handleExternalReviewSubmitted);
    _pulseController.dispose();
    super.dispose();
  }

  int get _stagedCount => _stagedSlots.where((s) => s.file != null).length;

  void _onPanStart(DragStartDetails details) {
    setState(() => _isDragging = true);
  }

  void _onPanUpdate(DragUpdateDetails details) {
    setState(() {
      _x += details.delta.dx;
      _y += details.delta.dy;
    });
  }

  void _onPanEnd(DragEndDetails details) {
    final screenSize = MediaQuery.of(context).size;
    final double midX = screenSize.width / 2;
    setState(() {
      _isDragging = false;
      // Snap to nearest edge (left or right)
      _x = _x < midX ? 16.0 : (screenSize.width - 72.0);
      // Clamp Y within screen
      _y = _y.clamp(80.0, screenSize.height - 140.0);
    });
  }

  void _openCircleToSearch() {
    setState(() {
      _isCircleToSearchOpen = true;
      _isStagingSheetOpen = false;
    });
  }

  void _onRegionSnipped(File snipFile, String labelSuggestion) {
    // Assign to next available slot
    StagedImageSlot? targetSlot;
    for (var slot in _stagedSlots) {
      if (slot.file == null) {
        targetSlot = slot;
        break;
      }
    }
    targetSlot ??= _stagedSlots.first;

    setState(() {
      targetSlot!.file = snipFile;
      targetSlot.quickOcrResult = null; // will trigger fresh quickOcr
      _isCircleToSearchOpen = false;
      _isStagingSheetOpen = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final int count = _stagedCount;

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Material(
        type: MaterialType.transparency,
        child: Stack(
          children: [
            if (widget.child != null) widget.child!,

            // 1. Circle to Search Interactive Canvas Overlay
            if (_isCircleToSearchOpen)
              Positioned.fill(
                child: CircleToSearchCanvas(
                  currentStagedCount: count,
                  onRegionSnipped: _onRegionSnipped,
                  onCancel: () => setState(() => _isCircleToSearchOpen = false),
                ),
              ),

            // 2. Multi-Angle Staging & OCR Decision Sheet Overlay
            if (_isStagingSheetOpen)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: MultiAngleStagingSheet(
                  initialSlots: _stagedSlots,
                  onAddAnotherAngle: _openCircleToSearch,
                  onDismiss: () => setState(() => _isStagingSheetOpen = false),
                ),
              ),

            // 3. Floating Overlay Bubble with Nirikshak Logo
            if (!_isCircleToSearchOpen)
              Positioned(
                left: _x,
                top: _y,
                child: GestureDetector(
                  onPanStart: _onPanStart,
                  onPanUpdate: _onPanUpdate,
                  onPanEnd: _onPanEnd,
                  onTap: () {
                    if (_stagedCount > 0) {
                      setState(() => _isStagingSheetOpen = !_isStagingSheetOpen);
                    } else {
                      _openCircleToSearch();
                    }
                  },
                  child: AnimatedScale(
                    scale: _isDragging ? 1.08 : 1.0,
                    duration: const Duration(milliseconds: 150),
                    child: AnimatedBuilder(
                      animation: _pulseController,
                      builder: (context, child) {
                        final pulse = _pulseController.value;
                        return Container(
                          width: 58,
                          height: 58,
                          decoration: BoxDecoration(
                            color: AppTheme.slate900,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: const Color(0xFF34D399).withValues(alpha: 0.7 + (0.3 * pulse)),
                              width: 2.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF10B981).withValues(alpha: 0.4 + (0.25 * pulse)),
                                blurRadius: 16 + (8 * pulse),
                                spreadRadius: 2,
                                offset: const Offset(0, 4),
                              ),
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.35),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Stack(
                            children: [
                              // Nirikshak Logo inside the floating bubble
                              Center(
                                child: ClipOval(
                                  child: Image.asset(
                                    'assets/images/nirikshak_logo.jpeg',
                                    width: 44,
                                    height: 44,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => const Icon(
                                      Icons.search_rounded,
                                      color: AppTheme.emerald400,
                                      size: 26,
                                    ),
                                  ),
                                ),
                              ),
                              if (count > 0)
                                Positioned(
                                  top: 1,
                                  right: 1,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppTheme.emerald500,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: AppTheme.slate900, width: 1.5),
                                    ),
                                    child: Text(
                                      '$count',
                                      style: const TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w900,
                                        color: AppTheme.slate900,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
