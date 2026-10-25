import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/api_client.dart';
import '../core/theme.dart';
import '../providers/auth_provider.dart';
import '../screens/details_screen.dart';

class StagedImageSlot {
  final String slotId; // 'front', 'back', 'left', 'right'
  final String title;
  File? file;
  Map<String, dynamic>? quickOcrResult;
  bool isAnalyzing = false;

  StagedImageSlot({
    required this.slotId,
    required this.title,
    this.file,
    this.quickOcrResult,
    this.isAnalyzing = false,
  });
}

class MultiAngleStagingSheet extends ConsumerStatefulWidget {
  final List<StagedImageSlot> initialSlots;
  final VoidCallback onAddAnotherAngle;
  final VoidCallback onDismiss;

  const MultiAngleStagingSheet({
    super.key,
    required this.initialSlots,
    required this.onAddAnotherAngle,
    required this.onDismiss,
  });

  @override
  ConsumerState<MultiAngleStagingSheet> createState() => _MultiAngleStagingSheetState();
}

class _MultiAngleStagingSheetState extends ConsumerState<MultiAngleStagingSheet> {
  final ApiClient _apiClient = ApiClient();
  late List<StagedImageSlot> _slots;
  bool _isSubmitting = false;
  String _submitStepText = '';

  @override
  void initState() {
    super.initState();
    _slots = widget.initialSlots;
    _runOcrForUnanalyzedSlots();
  }

  void _runOcrForUnanalyzedSlots() {
    for (var slot in _slots) {
      if (slot.file != null && slot.quickOcrResult == null && !slot.isAnalyzing) {
        _analyzeSlot(slot);
      }
    }
  }

  Future<void> _analyzeSlot(StagedImageSlot slot) async {
    setState(() => slot.isAnalyzing = true);
    try {
      final res = await _apiClient.quickOcr(slot.file!.path);
      if (mounted) {
        setState(() {
          slot.quickOcrResult = res;
          slot.isAnalyzing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          slot.isAnalyzing = false;
        });
      }
    }
  }

  int get _capturedCount => _slots.where((s) => s.file != null).length;
  bool get _canSubmit => _slots.any((s) => s.slotId == 'front' && s.file != null);

  Future<void> _submitForReview() async {
    final frontSlot = _slots.firstWhere((s) => s.slotId == 'front' && s.file != null, orElse: () => _slots.first);
    if (frontSlot.file == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Front product packaging angle is required.')),
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
      _submitStepText = 'Uploading package angles to Supabase Cloud Storage...';
    });

    try {
      final auth = ref.read(authProvider);

      final backSlot = _slots.firstWhere((s) => s.slotId == 'back', orElse: () => StagedImageSlot(slotId: '', title: ''));
      final leftSlot = _slots.firstWhere((s) => s.slotId == 'left', orElse: () => StagedImageSlot(slotId: '', title: ''));
      final rightSlot = _slots.firstWhere((s) => s.slotId == 'right', orElse: () => StagedImageSlot(slotId: '', title: ''));

      final uploadRes = await _apiClient.uploadScanImage(
        frontSlot.file!.path,
        backFilePath: backSlot.file?.path,
        leftFilePath: leftSlot.file?.path,
        rightFilePath: rightSlot.file?.path,
        userId: auth.userId.isNotEmpty ? auth.userId : null,
      );

      final String scanId = uploadRes['scan_id'];

      setState(() {
        _submitStepText = 'Executing Legal Metrology & FSSAI Compliance Audit...';
      });

      final result = await _apiClient.processScan(scanId);

      if (!mounted) return;
      setState(() => _isSubmitting = false);

      // Dismiss overlay sheet and navigate to full details screen
      widget.onDismiss();
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => DetailsScreen(item: Map<String, dynamic>.from(result)),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Audit Submission Error: $e'),
          backgroundColor: AppTheme.dangerRed,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Find latest analyzed entities to preview
    Map<String, dynamic>? latestEntities;
    double? latestConfidence;
    for (var slot in _slots.reversed) {
      if (slot.quickOcrResult != null && slot.quickOcrResult!['entities'] != null) {
        latestEntities = Map<String, dynamic>.from(slot.quickOcrResult!['entities']);
        latestConfidence = (slot.quickOcrResult!['confidence'] as num?)?.toDouble();
        break;
      }
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag Handle
          Center(
            child: Container(
              width: 38,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: AppTheme.slate300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppTheme.emerald100,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.document_scanner_rounded, size: 16, color: AppTheme.emerald800),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Circle-to-Search Staged Deck',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.slate900),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.slate900,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$_capturedCount / 4 Angles',
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // 4 Staged Slots Row
          Row(
            children: _slots.map((slot) => Expanded(child: _buildSlotThumbnail(slot))).toList(),
          ),

          const SizedBox(height: 12),

          // Quick OCR Preview Box (if available)
          if (latestEntities != null) ...[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.slate50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.slate200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.bolt_rounded, size: 13, color: Colors.amber),
                      const SizedBox(width: 4),
                      const Text(
                        'INSTANT OCR DETECTED',
                        style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: AppTheme.slate700, letterSpacing: 0.5),
                      ),
                      const Spacer(),
                      if (latestConfidence != null)
                        Text(
                          '${(latestConfidence * 100).toInt()}% Confidence',
                          style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: AppTheme.emerald700),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    latestEntities['product_name'] ?? 'Packaged Commodity',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppTheme.slate900),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      if (latestEntities['mrp'] != null) ...[
                        Text(
                          'MRP: ₹${latestEntities['mrp']}',
                          style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: AppTheme.slate800),
                        ),
                        const SizedBox(width: 8),
                      ],
                      if (latestEntities['net_quantity'] != null) ...[
                        Text(
                          'Net: ${latestEntities['net_quantity']} ${latestEntities['unit'] ?? ''}',
                          style: const TextStyle(fontSize: 10.5, color: AppTheme.slate600),
                        ),
                        const SizedBox(width: 8),
                      ],
                      if (latestEntities['manufacturer'] != null) ...[
                        Expanded(
                          child: Text(
                            latestEntities['manufacturer'],
                            style: const TextStyle(fontSize: 10, color: AppTheme.slate500),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Submission status loading bar
          if (_isSubmitting) ...[
            Center(
              child: Column(
                children: [
                  const LinearProgressIndicator(color: AppTheme.emerald600),
                  const SizedBox(height: 8),
                  Text(
                    _submitStepText,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.slate700),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ] else ...[
            // Action Buttons: [+ Add Another Face] & [SUBMIT FOR REVIEW]
            Row(
              children: [
                if (_capturedCount < 4) ...[
                  Expanded(
                    flex: 4,
                    child: OutlinedButton.icon(
                      onPressed: widget.onAddAnotherAngle,
                      icon: const Icon(Icons.add_circle_outline_rounded, size: 15),
                      label: Text(
                        _capturedCount == 0 ? 'Snip Label' : '+ Add Face ($_capturedCount/4)',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        side: const BorderSide(color: AppTheme.slate300),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  flex: 5,
                  child: ElevatedButton.icon(
                    onPressed: _canSubmit ? _submitForReview : null,
                    icon: const Icon(Icons.verified_rounded, size: 15),
                    label: const Text(
                      'SUBMIT FOR REVIEW',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      backgroundColor: AppTheme.slate900,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSlotThumbnail(StagedImageSlot slot) {
    final bool hasFile = slot.file != null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        children: [
          Container(
            height: 64,
            width: double.infinity,
            decoration: BoxDecoration(
              color: AppTheme.slate100,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: hasFile ? AppTheme.emerald500 : AppTheme.slate200,
                width: hasFile ? 1.5 : 1,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(11),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (hasFile)
                    Image.file(slot.file!, fit: BoxFit.cover)
                  else
                    const Center(
                      child: Icon(
                        Icons.add_photo_alternate_outlined,
                        size: 20,
                        color: AppTheme.slate400,
                      ),
                    ),
                  if (slot.isAnalyzing)
                    Container(
                      color: Colors.black.withValues(alpha: 0.4),
                      child: const Center(
                        child: SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        ),
                      ),
                    ),
                  if (hasFile && !slot.isAnalyzing)
                    Positioned(
                      top: 2,
                      right: 2,
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            slot.file = null;
                            slot.quickOcrResult = null;
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: const BoxDecoration(
                            color: Colors.black54,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.close, size: 10, color: Colors.white),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            slot.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: hasFile ? FontWeight.bold : FontWeight.w500,
              color: hasFile ? AppTheme.slate900 : AppTheme.slate400,
            ),
          ),
        ],
      ),
    );
  }
}
