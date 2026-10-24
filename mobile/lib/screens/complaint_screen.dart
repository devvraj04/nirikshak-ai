import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import '../core/api_client.dart';
import '../core/theme.dart';
import '../providers/auth_provider.dart';
import '../widgets/aura_background.dart';
import '../widgets/glass_card.dart';
import '../widgets/pulse_indicator.dart';
import '../widgets/nirikshak_app_bar.dart';
import 'camera_screen.dart';

class ComplaintScreen extends ConsumerStatefulWidget {
  final double? initialMrp;
  final String? initialProductName;
  final String? initialManufacturer;
  final String? initialShopkeeperName;
  final String? initialProductImagePath;
  final String? scanId;

  const ComplaintScreen({
    super.key,
    this.initialMrp,
    this.initialProductName,
    this.initialManufacturer,
    this.initialShopkeeperName,
    this.initialProductImagePath,
    this.scanId,
  });

  @override
  ConsumerState<ComplaintScreen> createState() => _ComplaintScreenState();
}

class _ComplaintScreenState extends ConsumerState<ComplaintScreen> {
  final _formKey = GlobalKey<FormState>();
  final ApiClient _apiClient = ApiClient();
  final ImagePicker _picker = ImagePicker();

  late final TextEditingController _paidPriceController;
  late final TextEditingController _mrpController;
  late final TextEditingController _shopkeeperNameController;
  late final TextEditingController _shopAddressController;
  late final TextEditingController _descController;

  String? _receiptImagePath;
  String? _productImagePath;

  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _paidPriceController = TextEditingController();
    _mrpController = TextEditingController(
      text: widget.initialMrp != null && widget.initialMrp! > 0
          ? widget.initialMrp!.toStringAsFixed(widget.initialMrp!.truncateToDouble() == widget.initialMrp ? 0 : 2)
          : '',
    );
    _shopkeeperNameController = TextEditingController(text: widget.initialShopkeeperName ?? '');
    _shopAddressController = TextEditingController();
    
    final StringBuffer initialDesc = StringBuffer();
    if (widget.initialProductName != null && widget.initialProductName!.isNotEmpty) {
      initialDesc.write('Product: ${widget.initialProductName}. ');
    }
    if (widget.initialManufacturer != null && widget.initialManufacturer!.isNotEmpty) {
      initialDesc.write('Manufacturer: ${widget.initialManufacturer}. ');
    }
    if (widget.scanId != null && widget.scanId!.isNotEmpty) {
      initialDesc.write('(Ref Scan ID: ${widget.scanId!.substring(0, widget.scanId!.length > 8 ? 8 : widget.scanId!.length)}). ');
    }
    _descController = TextEditingController(text: initialDesc.toString());

    if (widget.initialProductImagePath != null && widget.initialProductImagePath!.isNotEmpty) {
      _productImagePath = widget.initialProductImagePath;
    }
  }

  @override
  void dispose() {
    _paidPriceController.dispose();
    _mrpController.dispose();
    _shopkeeperNameController.dispose();
    _shopAddressController.dispose();
    _descController.dispose();
    super.dispose();
  }

  /// Opens the signature CameraScreen (identical style as home page scanner)
  /// and runs the image through the custom crop pipeline.
  Future<void> _captureEvidence(bool isReceipt) async {
    final String label = isReceipt ? 'Receipt / Bill' : 'Product MRP Panel';
    final String instruction = isReceipt
        ? 'Align purchase bill showing printed price, items, and date'
        : 'Align packaging panel showing printed MRP (incl. of taxes)';

    final File? capturedFile = await Navigator.push<File>(
      context,
      MaterialPageRoute(
        builder: (context) => CameraScreen(
          sideName: label,
          instruction: instruction,
        ),
      ),
    );

    if (capturedFile == null) return;

    // Optional crop with same slate & emerald theme as home/scan page
    try {
      final croppedFile = await ImageCropper().cropImage(
        sourcePath: capturedFile.path,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Align & Crop $label',
            toolbarColor: AppTheme.slate900,
            toolbarWidgetColor: Colors.white,
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
            title: 'Align & Crop $label',
            doneButtonTitle: 'Confirm',
            cancelButtonTitle: 'Cancel',
          ),
        ],
      );

      final finalPath = croppedFile?.path ?? capturedFile.path;
      if (mounted) {
        setState(() {
          if (isReceipt) {
            _receiptImagePath = finalPath;
          } else {
            _productImagePath = finalPath;
          }
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          if (isReceipt) {
            _receiptImagePath = capturedFile.path;
          } else {
            _productImagePath = capturedFile.path;
          }
        });
      }
    }
  }

  /// Alternative option to select evidence directly from gallery
  Future<void> _pickGalleryEvidence(bool isReceipt) async {
    final String label = isReceipt ? 'Receipt / Bill' : 'Product MRP Panel';
    try {
      final XFile? image = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
      if (image == null) return;

      final croppedFile = await ImageCropper().cropImage(
        sourcePath: image.path,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Align & Crop $label',
            toolbarColor: AppTheme.slate900,
            toolbarWidgetColor: Colors.white,
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
            title: 'Align & Crop $label',
            doneButtonTitle: 'Confirm',
            cancelButtonTitle: 'Cancel',
          ),
        ],
      );

      final finalPath = croppedFile?.path ?? image.path;
      if (mounted) {
        setState(() {
          if (isReceipt) {
            _receiptImagePath = finalPath;
          } else {
            _productImagePath = finalPath;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking gallery image: $e')),
        );
      }
    }
  }

  Future<void> _submitComplaint() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    final double paidPrice = double.tryParse(_paidPriceController.text) ?? 0.0;
    final double mrp = double.tryParse(_mrpController.text) ?? 0.0;
    final auth = ref.read(authProvider);

    try {
      final res = await _apiClient.fileComplaint(
        auth.userId,
        paidPrice,
        mrp,
        _shopkeeperNameController.text,
        _shopAddressController.text,
        _descController.text,
        receiptPath: _receiptImagePath,
        productPath: _productImagePath,
      );

      if (mounted) {
        setState(() => _isSubmitting = false);
        _showSuccessDialog(res);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to submit grievance to enforcement queue: $e'),
            backgroundColor: AppTheme.dangerRed,
          ),
        );
      }
    }
  }

  void _showSuccessDialog(Map<String, dynamic> res) {
    final bool overcharged = res['is_overcharging_detected'] ?? false;
    final double diff = (res['price_difference'] ?? 0.0).toDouble();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.baseBackground,
        title: Row(
          children: [
            Icon(overcharged ? Icons.warning_amber_rounded : Icons.check_circle_outline,
                color: overcharged ? AppTheme.dangerRed : AppTheme.successGreen),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                overcharged ? 'OVERCHARGING DETECTED' : 'COMPLAINT FILED',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.slate900),
              ),
            ),
          ],
        ),
        content: Text(
          overcharged
              ? 'Violation confirmed under LMPC Rule 18(2)! Paid price exceeds printed MRP by ₹ ${diff.toStringAsFixed(2)}. Routed to officer enforcement queue.'
              : 'Complaint submitted successfully.',
          style: const TextStyle(fontSize: 12, color: AppTheme.slate700),
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              context.go('/home');
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.slate900, foregroundColor: Colors.white),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.auraBg,
      body: AuraBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  NirikshakAppBar(
                    badgeText: 'RULE 18(2)',
                    subtitle: 'LMPC MRP Grievance Redressal',
                    showBackButton: true,
                    onBack: () => Navigator.pop(context),
                  ),
                  const SizedBox(height: 12),

                  // Top Statutory Banner
                  const GlassCard(
                    padding: EdgeInsets.all(16),
                    borderRadius: 16,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.shield_outlined, color: AppTheme.emerald600, size: 18),
                            SizedBox(width: 6),
                          Text(
                            'REPORT MRP OVERCHARGING',
                            style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.1, fontSize: 12, color: AppTheme.slate900),
                          ),
                        ],
                      ),
                      SizedBox(height: 6),
                      Text(
                        'Under Rule 18(2) of Legal Metrology (Packaged Commodities) Rules, 2011, no retailer may charge a price exceeding the printed Maximum Retail Price (MRP).',
                        style: TextStyle(fontSize: 11, color: AppTheme.slate600, height: 1.3),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Form Details Card
                GlassCard(
                  padding: const EdgeInsets.all(16),
                  borderRadius: 20,
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _paidPriceController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        style: const TextStyle(color: AppTheme.slate900, fontWeight: FontWeight.bold),
                        decoration: const InputDecoration(
                          labelText: 'Paid Price Charged (₹)',
                          prefixIcon: Icon(Icons.currency_rupee, color: AppTheme.slate700),
                          border: OutlineInputBorder(),
                        ),
                        validator: (val) => val == null || val.isEmpty ? 'Enter paid price' : null,
                      ),

                      const SizedBox(height: 14),

                      TextFormField(
                        controller: _mrpController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        style: const TextStyle(color: AppTheme.slate900, fontWeight: FontWeight.bold),
                        decoration: const InputDecoration(
                          labelText: 'Printed MRP on Package (₹)',
                          prefixIcon: Icon(Icons.sell_outlined, color: AppTheme.slate700),
                          border: OutlineInputBorder(),
                        ),
                        validator: (val) => val == null || val.isEmpty ? 'Enter printed MRP' : null,
                      ),

                      const SizedBox(height: 14),

                      TextFormField(
                        controller: _shopkeeperNameController,
                        style: const TextStyle(color: AppTheme.slate900),
                        decoration: const InputDecoration(
                          labelText: 'Shopkeeper / Retailer Name',
                          prefixIcon: Icon(Icons.person_outline, color: AppTheme.slate700),
                          border: OutlineInputBorder(),
                        ),
                      ),

                      const SizedBox(height: 14),

                      TextFormField(
                        controller: _shopAddressController,
                        maxLines: 2,
                        style: const TextStyle(color: AppTheme.slate900),
                        decoration: const InputDecoration(
                          labelText: 'Shop Address & Location',
                          prefixIcon: Icon(Icons.location_on_outlined, color: AppTheme.slate700),
                          border: OutlineInputBorder(),
                        ),
                      ),

                      const SizedBox(height: 14),

                      TextFormField(
                        controller: _descController,
                        maxLines: 3,
                        style: const TextStyle(color: AppTheme.slate900),
                        decoration: const InputDecoration(
                          labelText: 'Additional Violation Details',
                          alignLabelWithHint: true,
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // Statutory Evidence Section (Matches Home Scanner Visual Theme)
                _buildEvidenceSection(),

                const SizedBox(height: 24),

                if (_isSubmitting)
                  const Center(child: CircularProgressIndicator(color: AppTheme.emerald500))
                else
                  ElevatedButton.icon(
                    onPressed: _submitComplaint,
                    icon: const Icon(Icons.send_rounded, size: 16, color: Colors.white),
                    label: const Text('SUBMIT GRIEVANCE COMPLAINT', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.slate900,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 4,
                    ),
                  ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

  /// High-Tech Evidence Attachment Section matching the Home Screen Scanner
  Widget _buildEvidenceSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Expanded(
              child: Row(
                children: [
                  PulseIndicator(color: AppTheme.emerald500, size: 8),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'STATUTORY EVIDENCE CAPTURE',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                        color: AppTheme.slate800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.emerald100,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.emerald200),
              ),
              child: const Text(
                'OCR Camera',
                style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: AppTheme.emerald800),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        const Text(
          'Attach photo proof of the purchase bill and product packaging to corroborate Section 36 overcharging prosecution.',
          style: TextStyle(fontSize: 10.5, color: AppTheme.slate500, height: 1.3),
        ),
        const SizedBox(height: 14),

        // 1. Receipt / Store Bill Card
        _buildViewfinderAttachmentCard(
          title: 'Store Bill / Cash Memo',
          subtitle: 'Align bill showing printed price, item name & date',
          icon: Icons.receipt_long_rounded,
          imagePath: _receiptImagePath,
          isReceipt: true,
        ),

        const SizedBox(height: 12),

        // 2. Product Package MRP Panel Card
        _buildViewfinderAttachmentCard(
          title: 'Product Packaging / MRP Panel',
          subtitle: 'Align printed Maximum Retail Price (inclusive of taxes)',
          icon: Icons.inventory_2_rounded,
          imagePath: _productImagePath,
          isReceipt: false,
        ),
      ],
    );
  }

  /// Viewfinder-style attachment card mirroring the home page live scanner card
  Widget _buildViewfinderAttachmentCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required String? imagePath,
    required bool isReceipt,
  }) {
    final bool hasImage = imagePath != null && File(imagePath).existsSync();

    if (hasImage) {
      // Attached Preview State
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.emerald300, width: 1.2),
          boxShadow: [
            BoxShadow(
              color: AppTheme.emerald500.withValues(alpha: 0.08),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            // Thumbnail
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.file(
                File(imagePath),
                width: 68,
                height: 68,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(width: 12),
            // Info & Status
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.check_circle_rounded, color: AppTheme.emerald600, size: 15),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppTheme.slate900),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.emerald50,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppTheme.emerald200),
                    ),
                    child: const Text(
                      'Ready for verification',
                      style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: AppTheme.emerald700),
                    ),
                  ),
                ],
              ),
            ),
            // Actions
            Column(
              children: [
                IconButton(
                  tooltip: 'Retake Camera Scan',
                  icon: const Icon(Icons.refresh_rounded, color: AppTheme.slate700, size: 20),
                  onPressed: () => _captureEvidence(isReceipt),
                  style: IconButton.styleFrom(
                    backgroundColor: AppTheme.slate100,
                    padding: const EdgeInsets.all(8),
                    minimumSize: Size.zero,
                  ),
                ),
                const SizedBox(height: 6),
                IconButton(
                  tooltip: 'Remove Attachment',
                  icon: const Icon(Icons.delete_outline_rounded, color: AppTheme.dangerRed, size: 18),
                  onPressed: () {
                    setState(() {
                      if (isReceipt) {
                        _receiptImagePath = null;
                      } else {
                        _productImagePath = null;
                      }
                    });
                  },
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.red.withValues(alpha: 0.08),
                    padding: const EdgeInsets.all(8),
                    minimumSize: Size.zero,
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    // Unattached Viewfinder State (Home Page Scanner Look & Feel)
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xEE0F172A), // Slate 900 matching home scanner card
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x33475569)),
        boxShadow: const [
          BoxShadow(color: Color(0x40000000), blurRadius: 12, offset: Offset(0, 4)),
        ],
      ),
      child: Stack(
        children: [
          // Corner Guides (Identical to Home Page Live Scanner)
          Positioned(
            top: 0,
            left: 0,
            child: Container(
              width: 14,
              height: 14,
              decoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(color: AppTheme.emerald400, width: 2),
                  left: BorderSide(color: AppTheme.emerald400, width: 2),
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: Container(
              width: 14,
              height: 14,
              decoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(color: AppTheme.emerald400, width: 2),
                  right: BorderSide(color: AppTheme.emerald400, width: 2),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            child: Container(
              width: 14,
              height: 14,
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: AppTheme.emerald400, width: 2),
                  left: BorderSide(color: AppTheme.emerald400, width: 2),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            right: 0,
            child: Container(
              width: 14,
              height: 14,
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: AppTheme.emerald400, width: 2),
                  right: BorderSide(color: AppTheme.emerald400, width: 2),
                ),
              ),
            ),
          ),

          // Central Card Viewfinder Content
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Column(
              children: [
                Row(
                  children: [
                    // Viewfinder Icon Circle
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppTheme.emerald500.withValues(alpha: 0.12),
                        border: Border.all(color: AppTheme.emerald500.withValues(alpha: 0.35)),
                      ),
                      child: Icon(
                        icon,
                        color: AppTheme.emerald400,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Title & Description
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFF1F5F9),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            style: const TextStyle(
                              fontSize: 10,
                              color: Color(0xFF94A3B8),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Action Buttons Row (Launch Camera styled identically to Home Page)
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    // Pick from Gallery text button
                    TextButton.icon(
                      onPressed: () => _pickGalleryEvidence(isReceipt),
                      icon: const Icon(Icons.photo_library_outlined, size: 14, color: Color(0xFFCBD5E1)),
                      label: const Text('Gallery', style: TextStyle(fontSize: 11, color: Color(0xFFCBD5E1))),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      ),
                    ),

                    // Launch Camera Button (same signature emerald style as home page)
                    ElevatedButton.icon(
                      onPressed: () => _captureEvidence(isReceipt),
                      icon: const Icon(Icons.camera_alt_rounded, size: 14, color: AppTheme.slate900),
                      label: const Text(
                        'Launch Camera',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.slate900),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.emerald400,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
