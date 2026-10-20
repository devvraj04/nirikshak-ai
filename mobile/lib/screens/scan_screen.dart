import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:go_router/go_router.dart';
import '../core/api_client.dart';
import '../core/theme.dart';
import '../widgets/aura_background.dart';
import '../widgets/glass_card.dart';
import '../widgets/nirikshak_app_bar.dart';
import 'camera_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';

class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen> {
  final ApiClient _apiClient = ApiClient();

  File? _frontImage;
  File? _backImage;
  File? _leftImage;
  File? _rightImage;
  bool _isProcessing = false;
  bool _scanFlowActive = false;
  int _currentStep = 0;

  final List<String> _steps = ['Front', 'Back', 'Left', 'Right'];

  /// Captures a single image via camera, crops it, and returns the File (or null if cancelled).
  Future<File?> _captureAndCrop(String side) async {
    final File? capturedFile = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => CameraScreen(sideName: side)),
    );

    if (capturedFile == null) return null;

    final croppedFile = await ImageCropper().cropImage(
      sourcePath: capturedFile.path,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Align & Crop $side Label',
          toolbarColor: AppTheme.slate900,
          toolbarWidgetColor: Colors.white,
          statusBarColor: AppTheme.slate900,
          activeControlsWidgetColor: AppTheme.emerald400,
          initAspectRatio: CropAspectRatioPreset.original,
          lockAspectRatio: false,
          hideBottomControls: false,
          showCropGrid: true,
          cropGridColor: const Color(0x9934D399),
          cropFrameColor: const Color(0xFF34D399),
          cropGridRowCount: 2,
          cropGridColumnCount: 2,
        ),
        IOSUiSettings(
          title: 'Align & Crop $side',
          doneButtonTitle: 'Confirm',
          cancelButtonTitle: 'Cancel',
        ),
      ],
    );

    if (croppedFile != null) {
      return File(croppedFile.path);
    }
    return null;
  }

  /// Runs the full sequential scan flow: Front (mandatory) → Back (mandatory) → Left (optional) → Right (optional)
  Future<void> _runScanFlow() async {
    setState(() {
      _scanFlowActive = true;
      _currentStep = 0;
    });

    // Step 1: Front (mandatory)
    final front = await _captureAndCrop('Front');
    if (front == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Front capture is required. Scan cancelled.')),
        );
        setState(() => _scanFlowActive = false);
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      _frontImage = front;
      _currentStep = 1;
    });

    // Step 2: Back (mandatory)
    final back = await _captureAndCrop('Back');
    if (back == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Back capture is required. Scan cancelled.')),
        );
        setState(() => _scanFlowActive = false);
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      _backImage = back;
      _currentStep = 2;
    });

    // Step 3: Left (optional)
    if (mounted) {
      final shouldScanLeft = await _showOptionalDialog('Left');
      if (shouldScanLeft == true) {
        final left = await _captureAndCrop('Left');
        if (left != null && mounted) {
          setState(() => _leftImage = left);
        }
      }
    }
    if (!mounted) return;
    setState(() => _currentStep = 3);

    // Step 4: Right (optional)
    if (mounted) {
      final shouldScanRight = await _showOptionalDialog('Right');
      if (shouldScanRight == true) {
        final right = await _captureAndCrop('Right');
        if (right != null && mounted) {
          setState(() => _rightImage = right);
        }
      }
    }

    // All steps done — auto-submit
    if (mounted) {
      setState(() => _scanFlowActive = false);
      await _startComplianceScan();
    }
  }

  Future<bool?> _showOptionalDialog(String side) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.baseBackground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.camera_alt_outlined, color: AppTheme.emerald600),
            const SizedBox(width: 8),
            Text('Scan $side Side?', style: const TextStyle(color: AppTheme.slate900, fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: Text(
          'Would you like to capture the $side side of the product? This is optional and enhances declaration detection accuracy.',
          style: const TextStyle(color: AppTheme.slate700, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('SKIP', style: TextStyle(color: AppTheme.slate500)),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.camera_alt, size: 14),
            label: const Text('CAPTURE'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.emerald500,
              foregroundColor: AppTheme.slate900,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _startComplianceScan() async {
    if (_frontImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please capture front package label first.')),
      );
      return;
    }

    setState(() => _isProcessing = true);

    try {
      final auth = ref.read(authProvider);

      final uploadRes = await _apiClient.uploadScanImage(
        _frontImage!.path,
        backFilePath: _backImage?.path,
        leftFilePath: _leftImage?.path,
        rightFilePath: _rightImage?.path,
        userId: auth.userId,
      );
      final String scanId = uploadRes['scan_id'];

      final result = await _apiClient.processScan(scanId);

      if (mounted) {
        setState(() => _isProcessing = false);
        context.push('/result', extra: result);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Scan evaluation failed: ${e.toString()}'),
            duration: const Duration(seconds: 6),
            backgroundColor: AppTheme.dangerRed,
          ),
        );
      }
    }
  }

  File? _getImageForStep(int step) {
    if (step == 0) return _frontImage;
    if (step == 1) return _backImage;
    if (step == 2) return _leftImage;
    if (step == 3) return _rightImage;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.auraBg,
      body: AuraBackground(
        child: SafeArea(
          child: _isProcessing
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(
                        width: 50,
                        height: 50,
                        child: CircularProgressIndicator(
                          color: AppTheme.emerald500,
                          strokeWidth: 4,
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'AI OCR Extraction & Rule Evaluation...',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.slate900),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Checking Legal Metrology (PC) Rules, 2011 declarations',
                        style: TextStyle(fontSize: 12, color: AppTheme.slate500),
                      ),
                    ],
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      NirikshakAppBar(
                        badgeText: 'VISION OCR',
                        subtitle: 'Packaging Declaration Scanner',
                        showBackButton: true,
                        onBack: () => Navigator.pop(context),
                      ),
                      const SizedBox(height: 12),

                      // Stepper Indicator
                    GlassCard(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      borderRadius: 16,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: List.generate(4, (index) {
                          final isActive = index == _currentStep;
                          final isDone = _getImageForStep(index) != null;
                          return Expanded(
                            child: Column(
                              children: [
                                Container(
                                  width: 28,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: isDone
                                        ? AppTheme.emerald500
                                        : (isActive ? AppTheme.slate900 : Colors.transparent),
                                    border: Border.all(
                                      color: isActive || isDone ? Colors.transparent : AppTheme.slate400,
                                      width: 1.5,
                                    ),
                                  ),
                                  child: isDone
                                      ? const Icon(Icons.check, size: 16, color: Colors.white)
                                      : Center(
                                          child: Text(
                                            '${index + 1}',
                                            style: TextStyle(
                                              color: isActive ? Colors.white : AppTheme.slate500,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 11,
                                            ),
                                          ),
                                        ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _steps[index],
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: isActive || isDone ? AppTheme.slate900 : AppTheme.slate500,
                                    fontWeight: isDone || isActive ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                                if (index > 1)
                                  const Text(
                                    '(optional)',
                                    style: TextStyle(fontSize: 8, color: AppTheme.slate400),
                                  ),
                              ],
                            ),
                          );
                        }),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Preview Area
                    Expanded(
                      child: _frontImage == null && !_scanFlowActive
                          ? _buildStartPrompt()
                          : _buildImagePreview(),
                    ),

                    const SizedBox(height: 16),

                    // Main Action Buttons
                    if (!_scanFlowActive) ...[
                      ElevatedButton.icon(
                        onPressed: _frontImage == null ? _runScanFlow : _startComplianceScan,
                        icon: Icon(_frontImage == null ? Icons.camera_alt_rounded : Icons.analytics_outlined, color: AppTheme.slate900),
                        label: Text(
                          _frontImage == null ? 'START GUIDED SCAN' : 'SUBMIT FOR COMPLIANCE AUDIT',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.slate900),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.emerald400,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                      if (_frontImage != null) ...[
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: () {
                            setState(() {
                              _frontImage = null;
                              _backImage = null;
                              _leftImage = null;
                              _rightImage = null;
                              _currentStep = 0;
                            });
                            _runScanFlow();
                          },
                          icon: const Icon(Icons.replay_rounded, color: AppTheme.warningAmber, size: 16),
                          label: const Text('RESCAN ALL SIDES', style: TextStyle(color: AppTheme.warningAmber, fontWeight: FontWeight.bold, fontSize: 12)),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: AppTheme.warningAmber),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
        ),
      ),
    );
  }

  Widget _buildStartPrompt() {
    return GlassCard(
      padding: const EdgeInsets.all(24),
      borderRadius: 20,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.emerald100,
                border: Border.all(color: AppTheme.emerald400, width: 2),
              ),
              child: const Icon(Icons.center_focus_strong_rounded, size: 44, color: AppTheme.emerald600),
            ),
            const SizedBox(height: 18),
            const Text(
              'Multi-Angle Scanner Ready',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.slate900),
            ),
            const SizedBox(height: 6),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'Photograph the front and back of the product package (required), then optionally capture sides to ensure all declarations are captured.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.slate500, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImagePreview() {
    final captured = <MapEntry<String, File>>[];
    if (_frontImage != null) captured.add(MapEntry('Front', _frontImage!));
    if (_backImage != null) captured.add(MapEntry('Back', _backImage!));
    if (_leftImage != null) captured.add(MapEntry('Left', _leftImage!));
    if (_rightImage != null) captured.add(MapEntry('Right', _rightImage!));

    if (captured.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.emerald500),
      );
    }

    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.85,
      ),
      itemCount: captured.length,
      itemBuilder: (context, index) {
        final entry = captured[index];
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.emerald500, width: 2),
            boxShadow: const [
              BoxShadow(color: Color(0x1A000000), blurRadius: 8, offset: Offset(0, 2)),
            ],
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.file(entry.value, fit: BoxFit.cover),
              ),
              Positioned(
                top: 8,
                left: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.emerald600,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.check, size: 12, color: Colors.white),
                      const SizedBox(width: 4),
                      Text(entry.key, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
