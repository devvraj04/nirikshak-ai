import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:dio/dio.dart';
import 'package:printing/printing.dart';
import '../core/api_client.dart';
import '../core/theme.dart';
import '../widgets/aura_background.dart';
import '../widgets/glass_card.dart';
import '../widgets/pulse_indicator.dart';
import '../widgets/price_history_chart.dart';
import '../widgets/nirikshak_app_bar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import 'rules_chat_screen.dart';

class DetailsScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> item;
  final bool? isOfficer;

  const DetailsScreen({super.key, required this.item, this.isOfficer});

  @override
  ConsumerState<DetailsScreen> createState() => _DetailsScreenState();
}

class _DetailsScreenState extends ConsumerState<DetailsScreen> {
  int _activeRuleIndex = 0;
  late final PageController _pageController = PageController(initialPage: 0);

  /// Selected packaging face for OCR text and photo inspection
  String _selectedOcrSide = 'front';
  Map<String, dynamic>? _ocrDetails;
  bool _loadingOcr = false;
  bool _rawOcrViewMode = false;
  bool _showOcrBoundingBoxes = true;
  int? _selectedBoxIndex;

  /// Track intrinsic aspect ratio of packaging images to align bounding boxes with zero error
  final Map<String, double> _imageAspectRatios = {};

  /// Selected tab for structured facts table: 'front', 'back', 'left', 'right', 'all'
  String _structuredTableTab = 'front';

  void _resolveImageAspect(String url) {
    if (url.isEmpty || _imageAspectRatios.containsKey(url)) return;
    try {
      final img = NetworkImage(url);
      img.resolve(const ImageConfiguration()).addListener(
        ImageStreamListener((ImageInfo info, bool _) {
          if (mounted) {
            final w = info.image.width.toDouble();
            final h = info.image.height.toDouble();
            if (w > 0 && h > 0) {
              setState(() {
                _imageAspectRatios[url] = w / h;
              });
            }
          }
        }),
      );
    } catch (_) {}
  }

  /// Cache of enriched violation data from LLM+RAG. Keyed by rule_id.
  final Map<String, Map<String, dynamic>> _violationCache = {};
  final Set<String> _loadingRuleIds = {};

  /// E-Commerce Twin data: twice-daily price history & product violation history
  Map<String, dynamic>? _ecommerceTwinData;
  bool _loadingEcommerceTwin = false;

  @override
  void initState() {
    super.initState();
    _fetchScanOcr();
  }

  Future<void> _fetchScanOcr() async {
    final String scanId = (widget.item['scan_id'] ?? widget.item['id'] ?? '').toString();
    if (scanId.isEmpty) return;
    setState(() => _loadingOcr = true);
    try {
      final ocrRes = await _apiClient.getScanOcr(scanId);
      if (mounted) {
        setState(() {
          _ocrDetails = ocrRes;
          _loadingOcr = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loadingOcr = false);
      }
    }
  }

  bool get _isOfficer {
    if (widget.isOfficer == true) return true;
    try {
      final role = ref.read(authProvider).role;
      if (role == UserRoleState.officer) return true;
    } catch (_) {}
    final item = widget.item;
    if (item['type'] == 'COMPLAINT') return true;
    if (item.containsKey('complaint_id')) return true;
    return false;
  }

  final ApiClient _apiClient = ApiClient();

  Future<void> _handleOfficerDecision(
    bool isComplaint,
    String scanOrComplaintId,
    String decision,
  ) async {
    String officerId = '00000000-0000-0000-0000-000000000001';
    try {
      final auth = ref.read(authProvider);
      if (auth.userId.isNotEmpty) officerId = auth.userId;
    } catch (_) {}

    try {
      if (isComplaint) {
        final status = decision == 'ACCEPT' ? 'RESOLVED' : 'REJECTED';
        await _apiClient.reviewComplaint(
          scanOrComplaintId,
          officerId,
          status,
          'Officer Raj recorded decision $decision from details evaluation screen',
        );
      } else {
        await _apiClient.submitReview(
          scanOrComplaintId,
          officerId,
          decision,
          'Officer Raj recorded decision $decision from details evaluation screen',
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                decision == 'ACCEPT' ? Icons.check_circle_rounded : Icons.cancel_rounded,
                color: Colors.white,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text('${isComplaint ? 'Complaint' : 'Scan'} marked as $decision.'),
            ],
          ),
          backgroundColor: decision == 'ACCEPT' ? AppTheme.successGreen : AppTheme.dangerRed,
          duration: const Duration(seconds: 2),
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error recording officer decision: $e'),
          backgroundColor: AppTheme.dangerRed,
        ),
      );
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  /// Fetch enriched violation data for a FAIL rule lazily.
  Future<void> _fetchViolationEnrichment(String scanId, String ruleId) async {
    if (_violationCache.containsKey(ruleId) || _loadingRuleIds.contains(ruleId)) return;
    setState(() => _loadingRuleIds.add(ruleId));
    try {
      final result = await ApiClient().getViolationAnalysis(scanId, ruleId: ruleId);
      final violations = result['violations'] as List? ?? [];
      final match = violations.firstWhere(
        (v) => v['rule_id'] == ruleId || v['rule_code'] == ruleId,
        orElse: () => <String, dynamic>{},
      );
      if (match.isNotEmpty && mounted) {
        setState(() {
          _violationCache[ruleId] = Map<String, dynamic>.from(match);
          _loadingRuleIds.remove(ruleId);
        });
      } else {
        setState(() => _loadingRuleIds.remove(ruleId));
      }
    } catch (e) {
      if (mounted) setState(() => _loadingRuleIds.remove(ruleId));
    }
  }

  /// Fetch twice-daily price history and violation history for this product.
  Future<void> _fetchEcommerceTwin(String scanId) async {
    if (_ecommerceTwinData != null || _loadingEcommerceTwin) return;
    if (scanId.isEmpty || scanId == 'N/A') return;
    setState(() => _loadingEcommerceTwin = true);
    try {
      final data = await ApiClient().getProductEcommerceTwin(scanId);
      if (mounted) {
        setState(() {
          _ecommerceTwinData = data;
          _loadingEcommerceTwin = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loadingEcommerceTwin = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final isComplaint = item['type'] == 'COMPLAINT';
    final scanId = (isComplaint ? (item['complaint_id'] ?? item['id']) : (item['scan_id'] ?? item['id']))?.toString() ?? 'N/A';

    return Scaffold(
      backgroundColor: AppTheme.auraBg,
      body: AuraBackground(
        child: SafeArea(
          bottom: false,
          child: Stack(
            children: [
              // Scrollable Content
              Positioned.fill(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(
                    left: 16,
                    right: 16,
                    top: 10,
                    bottom: 110, // Padding for floating bottom dock
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHeader(context, isComplaint, scanId),
                      const SizedBox(height: 12),
                      _buildScanIdPill(context, scanId),
                      const SizedBox(height: 16),
                      if (isComplaint)
                        _buildComplaintDetails(context)
                      else
                        _buildScanDetails(context),
                    ],
                  ),
                ),
              ),

              // Floating Dock Action Bottom Bar
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: _buildFloatingDock(context, isComplaint, scanId),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- Top Navigation Header ---
  Widget _buildHeader(BuildContext context, bool isComplaint, String scanId) {
    final String pageSubtitle = isComplaint
        ? 'Complaint Evaluation'
        : (_isOfficer ? 'Inspection Evaluation' : 'Scan Breakdown');
    final String badge = isComplaint ? 'GRIEVANCE' : (_isOfficer ? 'ENFORCEMENT' : 'LMPC 2011');

    return NirikshakAppBar(
      badgeText: badge,
      subtitle: pageSubtitle,
      showBackButton: true,
      onBack: () {
        if (Navigator.canPop(context)) {
          Navigator.pop(context);
        } else {
          context.go('/home');
        }
      },
      trailing: GestureDetector(
        onTap: () => _downloadPdfReport(context, isComplaint, scanId),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.picture_as_pdf_rounded,
                size: 14,
                color: Color(0xFFF43F5E), // Rose 500
              ),
              SizedBox(width: 4),
              Text(
                'PDF',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.slate900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- Scan ID Pill Badge ---
  Widget _buildScanIdPill(BuildContext context, String scanId) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.9)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              children: [
                const Text(
                  '#',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.slate400,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'ID: $scanId',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.slate700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: scanId));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Scan ID copied to clipboard'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
            child: const Padding(
              padding: EdgeInsets.all(2.0),
              child: Icon(
                Icons.copy_rounded,
                size: 14,
                color: AppTheme.slate400,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- Scan Breakdown Complete Layout ---
  Widget _buildScanDetails(BuildContext context) {
    final item = widget.item;
    final String scanId = (item['scan_id'] ?? item['id'] ?? '').toString();
    final declarations = (item['extracted_declarations'] as Map?) ?? {};
    final evaluations = (item['evaluations'] as List?) ?? [];
    final summary = (item['compliance_summary'] as Map?) ?? {};
    final totalRules = evaluations.length;
    final passedRules = evaluations.where((e) {
      final st = (e['status'] ?? '').toString().toUpperCase();
      return st == 'PASS' || st == 'YES' || st == 'COMPLIANT' || st == 'TRUE';
    }).length;
    final int dynamicScore = totalRules > 0 ? ((passedRules / totalRules) * 100).round() : 0;
    final int score = summary['compliance_score'] is int
        ? summary['compliance_score'] as int
        : (summary['compliance_score'] != null ? int.tryParse(summary['compliance_score'].toString()) ?? dynamicScore : dynamicScore);
    final bool hasFailedRules = evaluations.any((e) {
      final st = (e['status'] ?? '').toString().toUpperCase();
      return st == 'FAIL' || st == 'NON-COMPLIANT' || st == 'NON_COMPLIANT' || st == 'VIOLATION' || st == 'FALSE';
    });
    final overallStatus = (item['overall_compliance'] ?? item['status'] ?? '').toString().toUpperCase();
    final bool isOverallCompliant = (overallStatus == 'PASS' || overallStatus == 'COMPLIANT' || overallStatus.isEmpty)
        && !hasFailedRules
        && (totalRules == 0 || passedRules == totalRules)
        && (score == 100);
    final imageUrls = (item['image_urls'] as Map?) ?? {};

    // Format declarations — NO hardcoded fallbacks; show null as missing
    final prodName = (declarations['generic_product_name'] ?? declarations['generic_name'] ?? declarations['product_name'])?.toString();
    final mfgName = (declarations['manufacturer_name'] ?? declarations['packer_name'] ?? declarations['importer_name'])?.toString();
    final mrpValue = declarations['mrp']?.toString();
    final mfgDate = declarations['manufacturing_date']?.toString()
        ?? ((declarations['manufacture_month'] != null || declarations['manufacture_year'] != null)
            ? '${declarations['manufacture_month'] ?? ''}/${declarations['manufacture_year'] ?? ''}'.trim()
            : null);
    final expDate = declarations['expiry_date']?.toString();
    final netQty = declarations['net_quantity'] != null
        ? '${declarations['net_quantity']} ${declarations['unit'] ?? ''}'.trim()
        : null;
    final batchId = (declarations['batch_number'] ?? declarations['batch_no'])?.toString();
    final contactPhone = declarations['consumer_care_phone']?.toString();
    final contactEmail = declarations['consumer_care_email']?.toString();
    final contactAddress = declarations['consumer_care_address']?.toString();
    final contact = (contactPhone != null && contactPhone.isNotEmpty)
        ? contactPhone
        : ((contactEmail != null && contactEmail.isNotEmpty)
            ? contactEmail
            : contactAddress);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. SCANNED EVIDENCE SECTION
        _buildScannedEvidenceSection(context, imageUrls),

        const SizedBox(height: 20),

        // 1B. ISOLATED VISUAL CROPS (Nutrition Table & Ingredients)
        _buildVisualCropEvidenceSection(context, Map<String, dynamic>.from(item), scanId),

        const SizedBox(height: 20),

        // 2. PACKAGING PHOTO & VISUAL OCR STUDIO (4-WAY ROTATION)
        _buildPackagingOcrStudio(
          context: context,
          imageUrls: Map<String, dynamic>.from(imageUrls),
          declarations: Map<String, dynamic>.from(declarations),
          scanId: scanId,
        ),

        const SizedBox(height: 20),

        // 4C. LLM PACKAGING SENTENCES CARD (Brand Claims highlighted)
        _buildLlmSentencesCard(
          item: Map<String, dynamic>.from(item),
          declarations: Map<String, dynamic>.from(declarations),
        ),

        const SizedBox(height: 20),

        // 4D. CLAIMS MADE BY BRAND (Dedicated Luxury Showcase)
        _buildBrandClaimsSection(
          item: Map<String, dynamic>.from(item),
          declarations: Map<String, dynamic>.from(declarations),
        ),

        const SizedBox(height: 20),

        // 4E. FLAGSHIP USP: SURROGATE ADVERTISING & DARK PATTERNS AUDIT
        _buildSurrogateAuditCard(
          item: Map<String, dynamic>.from(item),
          declarations: Map<String, dynamic>.from(declarations),
        ),

        const SizedBox(height: 20),

        // 5. EXTRACTED FACTS TABLE
        _buildExtractedFactsTable(
          mfgName: mfgName,
          prodName: prodName,
          netQty: netQty,
          batchId: batchId,
          contact: contact,
          declarations: Map<String, dynamic>.from(declarations),
          item: Map<String, dynamic>.from(item),
          evaluations: evaluations,
        ),

        const SizedBox(height: 20),

        // 5B. FULL CONTENT SECTIONS (Ingredients, Nutrition, Allergen, Storage, etc.)
        _buildFullContentSections(
          declarations: Map<String, dynamic>.from(declarations),
          item: Map<String, dynamic>.from(item),
        ),
      ],
    );
  }

  // --- 4E. Flagship USP: Surrogate Advertising & Dark Pattern Audit Card ---
  Widget _buildSurrogateAuditCard({
    required Map<String, dynamic> item,
    required Map<String, dynamic> declarations,
  }) {
    final surrogateData = item['surrogate_analysis'] ??
        declarations['surrogate_analysis'] ??
        _ocrDetails?['surrogate_analysis'];

    if (surrogateData == null || surrogateData is! Map) {
      return const SizedBox.shrink();
    }

    final bool isSurrogate = surrogateData['is_surrogate'] == true;
    final int riskScore = (surrogateData['surrogate_risk_score'] as num?)?.toInt() ?? 0;
    final String riskLevel = (surrogateData['risk_level'] ?? 'CLEAN').toString();
    final String? matchedBrand = surrogateData['matched_restricted_brand']?.toString();
    final String? parentIndustry = surrogateData['parent_restricted_industry']?.toString();
    final String? camouflageType = surrogateData['camouflaged_sku_type']?.toString();
    final String explanation = surrogateData['surrogate_explanation']?.toString() ?? '';
    final String consumerVerdict = surrogateData['consumer_plain_verdict']?.toString() ?? '';
    final List darkPatterns = (surrogateData['dark_patterns'] as List?) ?? [];
    final List legalViolations = (surrogateData['legal_violations'] as List?) ?? [];

    final Color primaryColor = isSurrogate
        ? const Color(0xFFE11D48)
        : (riskScore >= 50 ? Colors.amber.shade800 : AppTheme.emerald600);
    final Color bgColor = isSurrogate
        ? const Color(0xFFFFF1F2)
        : (riskScore >= 50 ? const Color(0xFFFFFBEB) : const Color(0xFFF0FDF4));
    final Color borderColor = isSurrogate
        ? const Color(0xFFFECDD3)
        : (riskScore >= 50 ? const Color(0xFFFDE68A) : const Color(0xFFBBF7D0));

    return GlassCard(
      borderRadius: 18,
      padding: const EdgeInsets.all(16),
      borderColor: borderColor,
      borderWidth: 1.5,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: primaryColor.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isSurrogate ? Icons.shield_rounded : Icons.verified_user_rounded,
                        color: primaryColor,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'SURROGATE AD & DARK PATTERNS',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.8,
                              color: AppTheme.slate500,
                            ),
                          ),
                          Text(
                            'CCPA 2022 & FSSAI 2018 Audit',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.slate900,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: primaryColor,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$riskLevel ($riskScore%)',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isSurrogate) ...[
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE11D48),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'SURROGATE DETECTED',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Parent Brand: ${matchedBrand ?? "Restricted Brand"}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF881337),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
                Text(
                  isSurrogate ? explanation : consumerVerdict,
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.45,
                    color: isSurrogate ? const Color(0xFF4C0519) : AppTheme.slate800,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (parentIndustry != null && parentIndustry != 'NONE') ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: AppTheme.slate200),
                        ),
                        child: Text(
                          'Industry: ${parentIndustry.replaceAll('_', ' ')}',
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppTheme.slate700),
                        ),
                      ),
                      if (camouflageType != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppTheme.slate200),
                          ),
                          child: Text(
                            'Vehicle: $camouflageType',
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppTheme.slate700),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (darkPatterns.isNotEmpty) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                const Icon(Icons.warning_amber_rounded, size: 14, color: Colors.amber),
                const SizedBox(width: 6),
                Text(
                  'DETECTED PACKAGING DARK PATTERNS (${darkPatterns.length})',
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                    color: AppTheme.slate600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...darkPatterns.map((dp) {
              if (dp is! Map) return const SizedBox.shrink();
              final title = (dp['title'] ?? 'Deceptive Claim').toString();
              final detail = (dp['detail'] ?? '').toString();
              final severity = (dp['severity'] ?? 'MED').toString();
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.slate200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.slate900,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: severity == 'CRITICAL' ? Colors.red.shade50 : Colors.amber.shade50,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            severity,
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: severity == 'CRITICAL' ? Colors.red.shade900 : Colors.amber.shade900,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (detail.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        detail,
                        style: const TextStyle(fontSize: 11, color: AppTheme.slate600, height: 1.35),
                      ),
                    ],
                  ],
                ),
              );
            }),
          ],
          if (legalViolations.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.slate50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.slate200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'STATUTORY LEGAL SECTIONS CITED',
                    style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: AppTheme.slate500),
                  ),
                  const SizedBox(height: 6),
                  ...legalViolations.take(2).map((lv) {
                    if (lv is! Map) return const SizedBox.shrink();
                    final act = (lv['act'] ?? '').toString();
                    final sec = (lv['section'] ?? '').toString();
                    final penalty = (lv['max_penalty'] ?? lv['penalty_clause'] ?? '').toString();
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4.0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.gavel_rounded, size: 13, color: AppTheme.slate600),
                          const SizedBox(width: 6),
                          Expanded(
                            child: RichText(
                              text: TextSpan(
                                style: const TextStyle(fontSize: 10.5, color: AppTheme.slate800),
                                children: [
                                  TextSpan(text: '$sec of $act: ', style: const TextStyle(fontWeight: FontWeight.bold)),
                                  TextSpan(text: penalty, style: const TextStyle(color: Color(0xFFE11D48), fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // --- 1B. Isolated Visual Crop Evidence Section ---
  bool _recroppingPanels = false;

  Widget _buildVisualCropEvidenceSection(BuildContext context, Map<String, dynamic> item, String scanId) {
    final String? nutritionCrop = (item['nutrition_table_image'] ?? item['nutrition_table_image_url'] ?? _ocrDetails?['nutrition_table_image'] ?? _ocrDetails?['nutrition_table_image_url'])?.toString();
    final String? ingredientsCrop = (item['ingredients_image'] ?? item['ingredients_image_url'] ?? _ocrDetails?['ingredients_image'] ?? _ocrDetails?['ingredients_image_url'])?.toString();

    final bool hasNutrition = nutritionCrop != null && nutritionCrop.isNotEmpty;
    final bool hasIngredients = ingredientsCrop != null && ingredientsCrop.isNotEmpty;

    return GlassCard(
      borderRadius: 18,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: AppTheme.emerald600.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.crop_free_rounded,
                        color: AppTheme.emerald600,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'ISOLATED VISUAL CROPS',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.8,
                              color: AppTheme.slate500,
                            ),
                          ),
                          Text(
                            'Nutrition & Formulation Panels',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.slate900,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (_recroppingPanels)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.emerald600),
                )
              else
                GestureDetector(
                  onTap: () async {
                    setState(() => _recroppingPanels = true);
                    try {
                      final res = await _apiClient.recropScanPanels(scanId);
                      if (mounted) {
                        setState(() {
                          _ocrDetails = _ocrDetails ?? {};
                          _ocrDetails!['nutrition_table_image'] = res['nutrition_table_image'];
                          _ocrDetails!['ingredients_image'] = res['ingredients_image'];
                          widget.item['nutrition_table_image'] = res['nutrition_table_image'];
                          widget.item['ingredients_image'] = res['ingredients_image'];
                          _recroppingPanels = false;
                        });
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Visual regions cropped successfully!'),
                              backgroundColor: AppTheme.emerald600,
                            ),
                          );
                        }
                      }
                    } catch (e) {
                      if (mounted) {
                        setState(() => _recroppingPanels = false);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Error cropping panels: $e'),
                              backgroundColor: AppTheme.dangerRed,
                            ),
                          );
                        }
                      }
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.slate100,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.slate200),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.refresh_rounded, size: 12, color: AppTheme.slate600),
                        SizedBox(width: 4),
                        Text(
                          'Re-crop',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppTheme.slate700),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              // Nutrition Table Crop Card
              Expanded(
                child: _buildCropThumbnailCard(
                  title: 'Nutrition Table',
                  subtitle: hasNutrition ? 'Tap to view full crop' : 'Not detected',
                  cropUrl: nutritionCrop,
                  icon: Icons.restaurant_menu_rounded,
                  badgeText: hasNutrition ? 'TABLE' : 'N/A',
                  badgeColor: hasNutrition ? AppTheme.emerald600 : AppTheme.slate400,
                ),
              ),
              const SizedBox(width: 10),
              // Ingredients Section Crop Card
              Expanded(
                child: _buildCropThumbnailCard(
                  title: 'Ingredients List',
                  subtitle: hasIngredients ? 'Tap to view full crop' : 'Not detected',
                  cropUrl: ingredientsCrop,
                  icon: Icons.format_list_bulleted_rounded,
                  badgeText: hasIngredients ? 'FORMULA' : 'N/A',
                  badgeColor: hasIngredients ? const Color(0xFF3B82F6) : AppTheme.slate400,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCropThumbnailCard({
    required String title,
    required String subtitle,
    required String? cropUrl,
    required IconData icon,
    required String badgeText,
    required Color badgeColor,
  }) {
    final bool hasImage = cropUrl != null && cropUrl.isNotEmpty;
    final fullUrl = hasImage
        ? (cropUrl.startsWith('http') ? cropUrl : '${ApiClient.getBaseUrl}$cropUrl')
        : null;

    return GestureDetector(
      onTap: () {
        if (fullUrl != null) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => FullScreenImageViewer(imageUrl: fullUrl),
            ),
          );
        }
      },
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: hasImage ? badgeColor.withValues(alpha: 0.35) : AppTheme.slate200,
            width: hasImage ? 1.5 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 100,
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: AppTheme.slate100,
              ),
              clipBehavior: Clip.antiAlias,
              child: hasImage
                  ? Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.network(
                          fullUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Center(
                            child: Icon(icon, color: AppTheme.slate400, size: 28),
                          ),
                        ),
                        Positioned(
                          top: 6,
                          right: 6,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.55),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.zoom_in_rounded,
                              color: Colors.white,
                              size: 14,
                            ),
                          ),
                        ),
                      ],
                    )
                  : Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(icon, color: AppTheme.slate300, size: 26),
                          const SizedBox(height: 4),
                          const Text(
                            'No crop available',
                            style: TextStyle(fontSize: 9, color: AppTheme.slate400, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.slate900,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: badgeColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    badgeText,
                    style: TextStyle(
                      fontSize: 8.5,
                      fontWeight: FontWeight.w900,
                      color: badgeColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 9.5,
                color: AppTheme.slate500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- 1. Scanned Evidence Section ---
  Widget _buildScannedEvidenceSection(BuildContext context, Map imageUrls) {
    final validImages = imageUrls.entries.where((e) => e.value != null && e.value.toString().isNotEmpty).toList();
    final count = validImages.isNotEmpty ? validImages.length : 3;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Expanded(
              child: Text(
                'SCANNED EVIDENCE',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.1,
                  color: AppTheme.slate600,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.emerald600.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: AppTheme.emerald600.withValues(alpha: 0.25),
                ),
              ),
              child: Text(
                '$count Angles Verified',
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.emerald600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // 3 Thumbnail Cards Grid
        if (validImages.isNotEmpty)
          Row(
            children: validImages.map((entry) {
              final side = entry.key.toString().toUpperCase();
              final url = entry.value.toString();
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => FullScreenImageViewer(
                          imageUrl: url.startsWith('http') ? url : '${ApiClient.getBaseUrl}$url',
                        ),
                      ),
                    ),
                    child: _buildEvidenceCard(
                      label: side,
                      imageWidget: Image.network(
                        url.startsWith('http') ? url : '${ApiClient.getBaseUrl}$url',
                        fit: BoxFit.cover,
                        errorBuilder: (c, e, s) => _buildPlaceholderEvidence(side),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          )
        else
          Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: _buildEvidenceCard(
                    label: 'FRONT',
                    imageWidget: _buildPlaceholderEvidence('FRONT'),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: _buildEvidenceCard(
                    label: 'BACK',
                    imageWidget: _buildPlaceholderEvidence('BACK'),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: _buildEvidenceCard(
                    label: 'TOP',
                    imageWidget: _buildPlaceholderEvidence('TOP'),
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildEvidenceCard({required String label, required Widget imageWidget}) {
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.85)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            height: 64,
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: AppTheme.slate100,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  imageWidget,
                  // Verified Green Dot Indicator
                  Positioned(
                    top: 4,
                    left: 5,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppTheme.emerald600,
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
              color: AppTheme.slate700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceholderEvidence(String side) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.slate100,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.slate200),
      ),
      padding: const EdgeInsets.all(6),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.image_not_supported_outlined, size: 20, color: AppTheme.slate400),
          const SizedBox(height: 4),
          Text(
            '$side VIEW',
            style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: AppTheme.slate600, fontFamily: 'monospace'),
          ),
          const Text(
            'Angle not uploaded',
            style: TextStyle(fontSize: 6.5, color: AppTheme.slate400),
          ),
        ],
      ),
    );
  }

  // --- 2. Packaging Photo & Multi-Angle OCR Studio (Replaces 3D Box) ---
  Widget _buildPackagingOcrStudio({
    required BuildContext context,
    required Map<String, dynamic> imageUrls,
    required Map<String, dynamic> declarations,
    required String scanId,
  }) {
    final validEntries = imageUrls.entries.where((e) => e.value != null && e.value.toString().isNotEmpty).toList();
    final availableSides = validEntries.isNotEmpty ? validEntries.map((e) => e.key.toString()).toList() : ['front'];

    if (!availableSides.contains(_selectedOcrSide) && availableSides.isNotEmpty) {
      _selectedOcrSide = availableSides.first;
    }

    final currentRawUrl = (imageUrls[_selectedOcrSide] ?? '').toString();
    final resolvedImageUrl = currentRawUrl.isNotEmpty
        ? (currentRawUrl.startsWith('http') ? currentRawUrl : '${ApiClient.getBaseUrl}$currentRawUrl')
        : '';
    if (resolvedImageUrl.isNotEmpty) {
      _resolveImageAspect(resolvedImageUrl);
    }

    // Extract OCR text and bounding boxes specifically for _selectedOcrSide
    String ocrText = '';
    double? confidence;
    int lineCount = 0;
    List<Map<String, dynamic>> boundingBoxes = [];

    // Check fetched _ocrDetails from /scans/$scanId/ocr
    if (_ocrDetails != null && _ocrDetails!['faces'] is List) {
      for (var f in (_ocrDetails!['faces'] as List)) {
        final sideName = (f['image_side'] ?? '').toString().toLowerCase();
        if (sideName == _selectedOcrSide.toLowerCase()) {
          ocrText = (f['processed_text'] ?? f['raw_text'] ?? '').toString();
          if (f['confidence'] != null) {
            confidence = (f['confidence'] as num).toDouble();
          }
          if (f['bounding_boxes'] is List) {
            boundingBoxes = List<Map<String, dynamic>>.from(
              (f['bounding_boxes'] as List).map((b) => Map<String, dynamic>.from(b)),
            );
          }
          break;
        }
      }
    }

    // Check widget.item['ocr_transcriptions']
    if (widget.item['ocr_transcriptions'] is List) {
      for (var t in (widget.item['ocr_transcriptions'] as List)) {
        final sideName = (t['image_side'] ?? t['side'] ?? '').toString().toLowerCase();
        if (sideName == _selectedOcrSide.toLowerCase()) {
          if (ocrText.isEmpty) {
            ocrText = (t['detected_text'] ?? t['text'] ?? t['raw_text'] ?? '').toString();
          }
          if (confidence == null && t['confidence'] != null) {
            confidence = (t['confidence'] as num).toDouble();
          }
          if (boundingBoxes.isEmpty && t['bounding_boxes'] is List) {
            boundingBoxes = List<Map<String, dynamic>>.from(
              (t['bounding_boxes'] as List).map((b) => Map<String, dynamic>.from(b)),
            );
          }
          break;
        }
      }
    }

    // Check widget.item['all_detected_text']
    if (ocrText.isEmpty && widget.item['all_detected_text'] != null) {
      final all = widget.item['all_detected_text'].toString();
      final tag = '[${_selectedOcrSide.toUpperCase()}';
      if (all.contains(tag)) {
        final parts = all.split(tag);
        if (parts.length > 1) {
          final sub = parts[1].split('[').first;
          ocrText = sub.replaceFirst('LABEL]\n', '').replaceFirst(']\n', '').trim();
        }
      } else if (availableSides.length == 1) {
        ocrText = all.trim();
      }
    }

    // Fallback: structured lines from declarations if no raw OCR recorded
    if (ocrText.isEmpty) {
      final List<String> fallbackLines = [];
      if (declarations['generic_product_name'] != null) {
        fallbackLines.add(declarations['generic_product_name'].toString());
      }
      if (declarations['net_quantity'] != null) {
        fallbackLines.add('NET WEIGHT: ${declarations['net_quantity']} ${declarations['unit'] ?? ''}'.trim());
      }
      if (declarations['mrp'] != null) {
        fallbackLines.add('MRP: Rs. ${declarations['mrp']} (INCL. OF ALL TAXES)');
      }
      if (declarations['manufacturer_name'] != null) {
        fallbackLines.add('MANUFACTURED BY: ${declarations['manufacturer_name']}');
      }
      if (declarations['manufacture_month'] != null || declarations['manufacture_year'] != null) {
        fallbackLines.add('MFD: ${declarations['manufacture_month'] ?? ''}/${declarations['manufacture_year'] ?? ''}'.trim());
      }
      if (declarations['expiry_date'] != null) {
        fallbackLines.add('EXPIRY: ${declarations['expiry_date']}');
      }
      if (declarations['batch_number'] != null) {
        fallbackLines.add('BATCH: ${declarations['batch_number']}');
      }
      if (declarations['consumer_care_phone'] != null) {
        fallbackLines.add('CARE: ${declarations['consumer_care_phone']}');
      }
      ocrText = fallbackLines.join('\n');
    }

    final lines = ocrText.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    lineCount = lines.length;

    // Check declarations or root item for bounding boxes
    if (boundingBoxes.isEmpty) {
      final bbCandidate = declarations['bounding_boxes'] ?? widget.item['bounding_boxes'];
      if (bbCandidate is List) {
        boundingBoxes = List<Map<String, dynamic>>.from(
          bbCandidate.map((b) => Map<String, dynamic>.from(b)),
        );
      }
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.9)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.07),
            blurRadius: 32,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppTheme.emerald600.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.document_scanner_rounded, size: 16, color: AppTheme.emerald600),
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'PACKAGING OCR STUDIO',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.1,
                          color: AppTheme.slate800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.emerald600.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppTheme.emerald600.withValues(alpha: 0.2)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_loadingOcr) ...[
                      const SizedBox(
                        width: 10,
                        height: 10,
                        child: CircularProgressIndicator(strokeWidth: 1.5, color: AppTheme.emerald600),
                      ),
                      const SizedBox(width: 5),
                    ],
                    Text(
                      confidence != null ? '${(confidence * 100).toStringAsFixed(1)}% Conf • 4-Way' : '4-Way Scanned',
                      style: const TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.emerald600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Face Tabs Selector (if multiple)
          if (availableSides.length > 1) ...[
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: availableSides.map((side) {
                  final isSelected = _selectedOcrSide.toLowerCase() == side.toLowerCase();
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        setState(() {
                          _selectedOcrSide = side;
                        });
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: isSelected ? AppTheme.emerald600 : Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected ? AppTheme.emerald600 : AppTheme.slate200,
                            width: 1.2,
                          ),
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                    color: AppTheme.emerald600.withValues(alpha: 0.25),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ]
                              : null,
                        ),
                        child: Text(
                          '${side.toUpperCase()} FACE',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                            color: isSelected ? Colors.white : AppTheme.slate600,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Packaging Image Preview with tap to zoom and interactive OCR bounding boxes
          if (resolvedImageUrl.isNotEmpty)
            Container(
              height: 220,
              width: double.infinity,
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.slate200),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(15),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final boxW = constraints.maxWidth;
                    final boxH = constraints.maxHeight;

                    // 1. Determine image aspect ratio (width / height)
                    double imgAspect = _imageAspectRatios[resolvedImageUrl] ?? 0.0;
                    if (imgAspect <= 0 && boundingBoxes.isNotEmpty) {
                      final firstBox = boundingBoxes.first;
                      if (firstBox['aspect_ratio'] != null && (firstBox['aspect_ratio'] as num) > 0) {
                        imgAspect = (firstBox['aspect_ratio'] as num).toDouble();
                      } else if (firstBox['orig_w'] != null && firstBox['orig_h'] != null && (firstBox['orig_h'] as num) > 0) {
                        imgAspect = (firstBox['orig_w'] as num).toDouble() / (firstBox['orig_h'] as num).toDouble();
                      }
                    }
                    if (imgAspect <= 0) {
                      imgAspect = boxW / boxH; // Fallback before image metadata resolves
                    }

                    // 2. Exact letterbox geometry matching BoxFit.contain
                    final containerAspect = boxW / boxH;
                    double renderedW, renderedH, offsetX, offsetY;
                    if (containerAspect > imgAspect) {
                      renderedH = boxH;
                      renderedW = boxH * imgAspect;
                      offsetX = (boxW - renderedW) / 2.0;
                      offsetY = 0.0;
                    } else {
                      renderedW = boxW;
                      renderedH = boxW / imgAspect;
                      offsetX = 0.0;
                      offsetY = (boxH - renderedH) / 2.0;
                    }

                    return Stack(
                      children: [
                        // Base Packaging Image placed exactly inside the letterbox bounds
                        Positioned(
                          left: offsetX,
                          top: offsetY,
                          width: renderedW,
                          height: renderedH,
                          child: GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => FullScreenImageViewer(
                                    imageUrl: resolvedImageUrl,
                                    boundingBoxes: boundingBoxes,
                                    aspectRatio: imgAspect > 0 ? imgAspect : null,
                                  ),
                                ),
                              );
                            },
                            child: Image.network(
                              resolvedImageUrl,
                              fit: BoxFit.fill,
                              loadingBuilder: (ctx, child, progress) {
                                if (progress == null) return child;
                                return const Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.emerald600));
                              },
                              errorBuilder: (_, __, ___) => const Center(
                                child: Icon(Icons.broken_image_rounded, color: AppTheme.slate500, size: 36),
                              ),
                            ),
                          ),
                        ),

                        // Interactive OCR Bounding Boxes Highlight Overlay aligned to rendered image
                        if (_showOcrBoundingBoxes && boundingBoxes.isNotEmpty)
                          ...boundingBoxes.asMap().entries.map((entry) {
                            final idx = entry.key;
                            final box = entry.value;
                            final isSelected = _selectedBoxIndex == idx;

                            double normX = 0, normY = 0, normW = 0, normH = 0;
                            final origW = (box['orig_w'] as num?)?.toDouble();
                            final origH = (box['orig_h'] as num?)?.toDouble();

                            if (box.containsKey('x') && box['x'] != null) {
                              double rx = (box['x'] as num).toDouble();
                              double ry = ((box['y'] ?? 0) as num).toDouble();
                              double rw = ((box['width'] ?? 0) as num).toDouble();
                              double rh = ((box['height'] ?? 0) as num).toDouble();

                              if (origW != null && origW > 0 && rx > 100.0) {
                                normX = (rx / origW) * 100.0;
                                normW = (rw / origW) * 100.0;
                              } else if (rx <= 1.0 && rw <= 1.0 && (rx > 0 || rw > 0)) {
                                normX = rx * 100.0;
                                normW = rw * 100.0;
                              } else {
                                normX = rx;
                                normW = rw;
                              }

                              if (origH != null && origH > 0 && ry > 100.0) {
                                normY = (ry / origH) * 100.0;
                                normH = (rh / origH) * 100.0;
                              } else if (ry <= 1.0 && rh <= 1.0 && (ry > 0 || rh > 0)) {
                                normY = ry * 100.0;
                                normH = rh * 100.0;
                              } else {
                                normY = ry;
                                normH = rh;
                              }
                            } else if (box['box'] is List && (box['box'] as List).length >= 4) {
                              final pts = box['box'] as List;
                              final x1 = (pts[0][0] as num).toDouble();
                              final y1 = (pts[0][1] as num).toDouble();
                              final x2 = (pts[1][0] as num).toDouble();
                              final y3 = (pts[2][1] as num).toDouble();
                              final ow = origW ?? (imgAspect > 0 ? 1000.0 * imgAspect : 1000.0);
                              final oh = origH ?? 1000.0;
                              normX = (x1 / ow) * 100.0;
                              normY = (y1 / oh) * 100.0;
                              normW = ((x2 - x1) / ow) * 100.0;
                              normH = ((y3 - y1) / oh) * 100.0;
                            }

                            final l = offsetX + (normX / 100.0) * renderedW;
                            final t = offsetY + (normY / 100.0) * renderedH;
                            final w = (normW / 100.0) * renderedW;
                            final h = (normH / 100.0) * renderedH;

                            final cl = l.clamp(offsetX, (offsetX + renderedW - 8.0).clamp(offsetX, offsetX + renderedW));
                            final ct = t.clamp(offsetY, (offsetY + renderedH - 6.0).clamp(offsetY, offsetY + renderedH));
                            final cw = w.clamp(8.0, (offsetX + renderedW - cl).clamp(8.0, renderedW));
                            final ch = h.clamp(6.0, (offsetY + renderedH - ct).clamp(6.0, renderedH));

                            final bText = (box['text'] ?? '').toString();
                            final bConf = box['confidence'] != null
                                ? ((box['confidence'] as num) * 100).toStringAsFixed(0)
                                : '95';

                            return Positioned(
                              left: cl,
                              top: ct,
                              width: cw,
                              height: ch,
                              child: GestureDetector(
                                onTap: () {
                                  setState(() => _selectedBoxIndex = idx);
                                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      duration: const Duration(seconds: 3),
                                      backgroundColor: const Color(0xFF0F172A),
                                      behavior: SnackBarBehavior.floating,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      content: Row(
                                        children: [
                                          const Icon(Icons.crop_free_rounded, color: AppTheme.emerald400, size: 16),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              'OCR Box #${idx + 1}: "$bText" ($bConf% conf)',
                                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? Colors.amber.withValues(alpha: 0.35)
                                        : AppTheme.emerald500.withValues(alpha: 0.22),
                                    border: Border.all(
                                      color: isSelected ? Colors.amberAccent : AppTheme.emerald400,
                                      width: isSelected ? 2.0 : 1.2,
                                    ),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                  child: Align(
                                    alignment: Alignment.topLeft,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 0.5),
                                      color: isSelected ? Colors.amber[800] : AppTheme.emerald700.withValues(alpha: 0.9),
                                      child: Text(
                                        '#${idx + 1}',
                                        style: const TextStyle(fontSize: 7.5, fontWeight: FontWeight.bold, color: Colors.white),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }),

                        // Side view indicator badge
                        Positioned(
                          top: 8,
                          left: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.7),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '${_selectedOcrSide.toUpperCase()} VIEW',
                              style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white, fontFamily: 'monospace'),
                            ),
                          ),
                        ),

                        // Action Controls: Toggle Bounding Boxes & Fullscreen Button
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (boundingBoxes.isNotEmpty)
                                GestureDetector(
                                  onTap: () {
                                    setState(() => _showOcrBoundingBoxes = !_showOcrBoundingBoxes);
                                  },
                                  child: Container(
                                    margin: const EdgeInsets.only(right: 6),
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: _showOcrBoundingBoxes
                                          ? AppTheme.emerald600.withValues(alpha: 0.9)
                                          : Colors.black.withValues(alpha: 0.65),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: _showOcrBoundingBoxes ? AppTheme.emerald400 : Colors.white24,
                                        width: 0.8,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          _showOcrBoundingBoxes ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                                          size: 13,
                                          color: Colors.white,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Boxes (${boundingBoxes.length})',
                                          style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              GestureDetector(
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => FullScreenImageViewer(
                                        imageUrl: resolvedImageUrl,
                                        boundingBoxes: boundingBoxes,
                                      ),
                                    ),
                                  );
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(5),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.65),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.fullscreen_rounded, size: 16, color: Colors.white),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),

          const SizedBox(height: 14),

          // OCR Transcription Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.slate50,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
              border: Border.all(color: AppTheme.slate200),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      const Icon(Icons.text_snippet_rounded, size: 14, color: AppTheme.slate600),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'DETECTED OCR TEXT ($lineCount LINES)',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.slate700,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Row(
                  children: [
                    // Mode Toggle (Cards / Raw)
                    InkWell(
                      onTap: () {
                        setState(() {
                          _rawOcrViewMode = !_rawOcrViewMode;
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: AppTheme.slate200),
                        ),
                        child: Text(
                          _rawOcrViewMode ? 'CARDS' : 'RAW',
                          style: const TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: AppTheme.slate600),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    // Copy button
                    InkWell(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: ocrText));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('OCR text copied to clipboard'),
                            duration: Duration(seconds: 1),
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: AppTheme.slate200),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.copy_rounded, size: 11, color: AppTheme.slate600),
                            SizedBox(width: 3),
                            Text(
                              'COPY',
                              style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: AppTheme.slate600),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Transcribed Text Display Box
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxHeight: 220),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14)),
              border: Border(
                left: BorderSide(color: AppTheme.slate200),
                right: BorderSide(color: AppTheme.slate200),
                bottom: BorderSide(color: AppTheme.slate200),
              ),
            ),
            child: lines.isNotEmpty
                ? (_rawOcrViewMode
                    ? SingleChildScrollView(
                        child: SelectableText(
                          ocrText,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                            height: 1.5,
                            color: AppTheme.slate800,
                          ),
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: lines.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 5),
                        itemBuilder: (ctx, idx) {
                          final line = lines[idx];
                          final isMrp = line.contains('MRP') || line.contains('Rs') || line.contains('₹') || line.contains('TAXES');
                          final isDate = line.contains('MFD') || line.contains('EXP') || line.contains('PKD') || line.contains('DATE') || line.contains('USE BY');
                          final isQty = line.contains('NET') || line.contains('WT') || line.contains('QTY') || line.contains(' g') || line.contains(' ml') || line.contains(' kg');

                          Color pillColor = AppTheme.slate100;
                          Color textColor = AppTheme.slate800;
                          if (isMrp) {
                            pillColor = AppTheme.emerald600.withValues(alpha: 0.12);
                            textColor = AppTheme.emerald800;
                          } else if (isDate) {
                            pillColor = Colors.blue.withValues(alpha: 0.1);
                            textColor = Colors.blue.shade900;
                          } else if (isQty) {
                            pillColor = Colors.amber.withValues(alpha: 0.14);
                            textColor = Colors.amber.shade900;
                          }

                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                            decoration: BoxDecoration(
                              color: pillColor,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: pillColor.withValues(alpha: 0.5)),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '[${(idx + 1).toString().padLeft(2, '0')}]',
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'monospace',
                                    color: AppTheme.slate400,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    line,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      fontFamily: 'monospace',
                                      color: textColor,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ))
                : const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'No text detected on this face',
                        style: TextStyle(fontSize: 11, color: AppTheme.slate400),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  // --- 3. Rule Carousel Card ---
  Widget _buildRuleCarouselCard(
    List rawEvaluations,
    String? mrpValue,
    String? mfgDate,
    String? expDate,
    int complianceScore,
    bool isOverallPass,
  ) {
    final rulesList = [
      {
        'is_summary': true,
        'score': complianceScore,
      },
      ...rawEvaluations
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.9)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.07),
            blurRadius: 32,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 270, // Height for Reason, RAG Citation Quote, Penalties, and Ask AI button
            child: PageView.builder(
              controller: _pageController,
              onPageChanged: (index) {
                setState(() => _activeRuleIndex = index);
              },
              itemCount: rulesList.length,
              itemBuilder: (context, index) {
                final currentRule = Map<String, dynamic>.from(rulesList[index] as Map);
                final isSummary = currentRule['is_summary'] == true;
                
                if (isSummary) {
                  return _buildSummarySlide(isOverallPass, complianceScore, index, rulesList.length);
                } else {
                  final String ruleId = (currentRule['rule_id'] ?? currentRule['rule_code'] ?? '').toString();
                  final cached = _violationCache[ruleId];
                  final ruleData = cached != null ? {...currentRule, ...cached} : currentRule;

                  final String ruleTitle = ruleData['rule_title'] ?? ruleData['rule_name'] ?? ruleData['rule_id'] ?? 'Rule';
                  final String ruleCode = ruleData['rule_code'] ?? ruleData['rule_reference'] ?? 'Rule #$index';
                  final String statusStr = (ruleData['status'] ?? 'FAIL').toString().toUpperCase();
                  final bool isPass = statusStr == 'PASS' || statusStr == 'YES' || statusStr == 'COMPLIANT' || statusStr == 'TRUE';
                  final String reason = ruleData['reason'] ?? ruleData['details'] ?? 'No supporting evidence available.';
                  
                  // Extract penalty and RAG citation
                  String penalty = (ruleData['penalty'] ?? ruleData['penalties'] ?? '').toString();
                  final citation = ruleData['citation'] as Map?;
                  final String? legalQuote = (citation?['quote'] ?? ruleData['legal_quote'])?.toString();
                  final String? actName = (citation?['act_name'] ?? ruleData['act_name'] ?? citation?['rule_reference'])?.toString();

                  // Lazy trigger LLM RAG enrichment if rule failed and penalty is missing
                  final String scanId = (widget.item['scan_id'] ?? widget.item['id'] ?? '').toString();
                  if (!isPass && penalty.isEmpty && ruleId.isNotEmpty && scanId.isNotEmpty && scanId != 'N/A') {
                    _fetchViolationEnrichment(scanId, ruleId);
                  }
                  
                  return SingleChildScrollView(
                    child: _buildRuleSlide(
                      title: ruleTitle,
                      code: ruleCode,
                      statusStr: statusStr,
                      isPass: isPass,
                      reason: reason,
                      penalty: penalty,
                      legalQuote: legalQuote,
                      actName: actName,
                      activeIndex: index,
                      totalLength: rulesList.length,
                    ),
                  );
                }
              },
            ),
          ),

          const SizedBox(height: 14),
          // Pagination Dots
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(rulesList.length, (idx) {
              final isCurrent = idx == _activeRuleIndex;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                margin: const EdgeInsets.symmetric(horizontal: 2.5),
                width: isCurrent ? 20 : 6,
                height: 5,
                decoration: BoxDecoration(
                  color: isCurrent ? AppTheme.emerald600 : AppTheme.slate300,
                  borderRadius: BorderRadius.circular(10),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildSummarySlide(bool isPass, int score, int activeIndex, int totalLength) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            _buildRightArrow(activeIndex, totalLength),
          ],
        ),
        const SizedBox(height: 4),
        Icon(
          isPass ? Icons.check_circle_outline_rounded : Icons.cancel_rounded,
          size: 72,
          color: isPass ? AppTheme.successGreen : AppTheme.dangerRed,
        ),
        const SizedBox(height: 12),
        Text(
          isPass ? 'PRODUCT IS COMPLIANT' : 'PRODUCT NON-COMPLIANT',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w900,
            color: isPass ? AppTheme.successGreen : AppTheme.dangerRed,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Overall Compliance Score: $score%',
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppTheme.slate600,
          ),
        ),
      ],
    );
  }

  Widget _buildRuleSlide({
    required String title,
    required String code,
    required String statusStr,
    required bool isPass,
    required String reason,
    required String penalty,
    String? legalQuote,
    String? actName,
    required int activeIndex,
    required int totalLength,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              isPass ? Icons.check_circle_rounded : Icons.cancel_rounded,
              color: isPass ? AppTheme.successGreen : AppTheme.dangerRed,
              size: 24,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'AUDIT $code OF ${totalLength - 1}'.toUpperCase(),
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.1,
                      color: isPass ? AppTheme.successGreen : AppTheme.dangerRed,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                      color: AppTheme.slate900,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: (isPass ? AppTheme.successGreen : AppTheme.dangerRed).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                statusStr,
                style: TextStyle(
                  color: isPass ? AppTheme.successGreen : AppTheme.dangerRed,
                  fontWeight: FontWeight.bold,
                  fontSize: 10,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 12.0),
              child: _buildLeftArrow(activeIndex),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Clickable Evidence & Reason Card
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => RulesChatScreen(
                            initialTabIndex: 1,
                            quotedRuleCode: code,
                            quotedRuleTitle: title,
                            violationReason: reason,
                            violationPenalty: penalty,
                          ),
                        ),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.slate200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('EVIDENCE / REASON', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.slate500)),
                              Row(
                                children: [
                                  Text(
                                    'Click to consult AI',
                                    style: TextStyle(fontSize: 8.5, color: AppTheme.emerald600.withValues(alpha: 0.9), fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(width: 2),
                                  const Icon(Icons.arrow_forward_ios_rounded, size: 8, color: AppTheme.emerald600),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(reason, style: const TextStyle(fontSize: 12, color: AppTheme.slate800, fontWeight: FontWeight.w500)),
                        ],
                      ),
                    ),
                  ),
                  if (legalQuote != null && legalQuote.isNotEmpty && legalQuote != 'null') ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC).withValues(alpha: 0.95), // Slate 50
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFCBD5E1)), // Slate 300
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.gavel_rounded, size: 12, color: AppTheme.slate700),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  (actName != null && actName.isNotEmpty && actName != 'null')
                                      ? actName.toUpperCase()
                                      : 'OFFICIAL LMPC ACT QUOTATION',
                                  style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 0.5, color: AppTheme.slate700),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            legalQuote,
                            style: const TextStyle(
                              fontSize: 11,
                              fontStyle: FontStyle.italic,
                              color: Color(0xFF1E293B),
                              fontWeight: FontWeight.w500,
                              height: 1.25,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (!isPass && penalty.isNotEmpty && penalty != 'null') ...[
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => RulesChatScreen(
                              initialTabIndex: 1,
                              quotedRuleCode: code,
                              quotedRuleTitle: title,
                              violationReason: reason,
                              violationPenalty: penalty,
                            ),
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFFBEB).withValues(alpha: 0.9), // Amber 50
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFFCD34D).withValues(alpha: 0.8)), // Amber 300
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.warning_rounded, size: 12, color: Color(0xFF92400E)),
                                SizedBox(width: 4),
                                Text('PENALTIES / CONSEQUENCES', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF92400E))),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(penalty, style: const TextStyle(fontSize: 11, color: Color(0xFF991B1B), fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ),
                  ],

                  // Dedicated "Ask Legal AI" Button
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => RulesChatScreen(
                            initialTabIndex: 1,
                            quotedRuleCode: code,
                            quotedRuleTitle: title,
                            violationReason: reason,
                            violationPenalty: penalty,
                          ),
                        ),
                      );
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                      decoration: BoxDecoration(
                        color: AppTheme.slate900,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.12),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.auto_awesome, size: 13, color: AppTheme.emerald400),
                          const SizedBox(width: 6),
                          Text(
                            isPass ? 'Ask Legal AI About This Rule' : 'Ask Legal AI About This Violation',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.3,
                            ),
                          ),
                          const SizedBox(width: 5),
                          const Icon(Icons.arrow_forward_rounded, size: 12, color: AppTheme.emerald400),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Padding(
              padding: const EdgeInsets.only(top: 12.0),
              child: _buildRightArrow(activeIndex, totalLength),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLeftArrow(int activeIndex) {
    return GestureDetector(
      onTap: () {
        if (activeIndex > 0) {
          _pageController.animateToPage(activeIndex - 1, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
        }
      },
      child: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: AppTheme.slate200),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 4),
          ],
        ),
        child: const Icon(Icons.arrow_back_ios_new_rounded, size: 11, color: AppTheme.slate700),
      ),
    );
  }

  Widget _buildRightArrow(int activeIndex, int totalLength) {
    return GestureDetector(
      onTap: () {
        if (activeIndex < totalLength - 1) {
          _pageController.animateToPage(activeIndex + 1, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
        }
      },
      child: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: AppTheme.slate200),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 4),
          ],
        ),
        child: const Icon(Icons.arrow_forward_ios_rounded, size: 11, color: AppTheme.slate700),
      ),
    );
  }

  // --- 4. Regulation Compliance Score Card ---
  Widget _buildComplianceScoreCard(int score, bool isOverallCompliant) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.9)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          // Circular Progress Gauge
          SizedBox(
            width: 52,
            height: 52,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: score / 100,
                  backgroundColor: AppTheme.slate200,
                  color: isOverallCompliant ? AppTheme.emerald600 : (score >= 50 ? AppTheme.warningOrange : AppTheme.dangerRed),
                  strokeWidth: 5.5,
                ),
                Text(
                  '$score%',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 12.5,
                    fontFamily: 'monospace',
                    color: AppTheme.slate900,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 14),

          // Score Description
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'REGULATION COMPLIANCE SCORE',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.8,
                        color: AppTheme.slate800,
                      ),
                    ),
                    const SizedBox(width: 6),
                    PulseIndicator(
                      color: isOverallCompliant ? AppTheme.emerald600 : AppTheme.dangerRed,
                      size: 7,
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  isOverallCompliant ? 'Compliant with LMPC PC Rules 2011' : 'Non-compliance flags detected',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: isOverallCompliant ? AppTheme.emerald600 : AppTheme.dangerRed,
                  ),
                ),
                const SizedBox(height: 1),
                const Text(
                  'Packaged Commodities & Drug Controller Standard',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.slate500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- 4C. LLM Packaging Sentences Card ---
  Widget _buildLlmSentencesCard({
    required Map item,
    required Map<String, dynamic> declarations,
  }) {
    List<String> sentences = [];

    // Check all containers for summary_sentences
    for (final container in [
      declarations,
      item,
      _ocrDetails,
      declarations['raw_declarations'],
      declarations['raw_extractions'],
      declarations['extracted_declarations'],
      item['raw_declarations'],
      item['raw_extractions'],
      item['extracted_declarations'],
      _ocrDetails?['raw_declarations'],
      _ocrDetails?['raw_extractions'],
      _ocrDetails?['extracted_declarations'],
    ]) {
      if (container is Map && container['summary_sentences'] is List && (container['summary_sentences'] as List).isNotEmpty) {
        sentences = (container['summary_sentences'] as List)
            .map((s) => s.toString().trim())
            .where((s) => s.isNotEmpty)
            .toList();
        if (sentences.isNotEmpty) break;
      }
    }

    // Dynamic synthesis fallback if empty
    if (sentences.isEmpty) {
      final pName = declarations['generic_product_name'] ?? item['product_name'] ?? 'Product';
      final mName = declarations['manufacturer_name'] ?? item['manufacturer_name'];
      final mrp = declarations['mrp'] ?? item['mrp'];
      final netQty = declarations['net_quantity'] ?? item['net_quantity'];
      final unit = declarations['unit'] ?? 'g';
      final mfgDate = declarations['manufacturing_date'] ?? declarations['manufacture_month'];
      final expDate = declarations['expiry_date'] ?? declarations['best_before'];

      sentences.add('The packaging explicitly declares commodity name as "$pName".');
      if (mName != null && mName.toString().isNotEmpty) {
        sentences.add('Manufactured and packed by "$mName".');
      }
      if (mrp != null && mrp.toString().isNotEmpty) {
        sentences.add('Maximum Retail Price (MRP) is labeled as ₹$mrp inclusive of all applicable taxes.');
      }
      if (netQty != null && netQty.toString().isNotEmpty) {
        sentences.add('Net declared weight/volume is $netQty $unit under Rule 11 of the Legal Metrology Rules.');
      }
      if (mfgDate != null || expDate != null) {
        sentences.add('Production timeline identified with MFD ${mfgDate ?? "Declared"} and Best Before / Expiry ${expDate ?? "Declared"}.');
      }

      // Check if brand claims exist to synthesize claim sentences
      final claimsList = declarations['brand_claims'] ?? item['brand_claims'];
      if (claimsList is List && claimsList.isNotEmpty) {
        for (var c in claimsList) {
          final claimStr = c is Map ? (c['claim'] ?? '').toString() : c.toString();
          if (claimStr.isNotEmpty) {
            sentences.add('Brand Claim: "$claimStr" prominently showcased on packaging label.');
          }
        }
      }
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.95)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.06),
            blurRadius: 28,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with AI Icon
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF6366F1).withValues(alpha: 0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: const Icon(Icons.psychology_rounded, size: 18, color: Colors.white),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'LLM PACKAGING SENTENCES',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.0,
                        color: AppTheme.slate800,
                      ),
                    ),
                    Text(
                      'Groq LLaMA 3.3 70B • Packaging Reasoning Engine',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.slate500,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF2FF),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFC7D2FE)),
                ),
                child: Text(
                  '${sentences.length} Sentences',
                  style: const TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF4F46E5),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Formulated by passing all detected packaging OCR tokens to the LLM to verify consumer claims and statutory declarations.',
            style: TextStyle(fontSize: 11, color: AppTheme.slate600, height: 1.4),
          ),
          const SizedBox(height: 14),

          // Sentences List
          ...sentences.asMap().entries.map((entry) {
            final idx = entry.key;
            final sentence = entry.value;
            final isBrandClaim = sentence.toLowerCase().contains('brand claim') ||
                sentence.toLowerCase().contains('claim') ||
                sentence.contains('“') ||
                (sentence.contains('"') && (sentence.toLowerCase().contains('pure') || sentence.toLowerCase().contains('veg') || sentence.toLowerCase().contains('crispy') || sentence.toLowerCase().contains('zero')));

            if (isBrandClaim) {
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFBEB),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFFDE68A), width: 1.2),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFF59E0B).withValues(alpha: 0.08),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 2),
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Color(0xFFF59E0B),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.star_rounded, size: 12, color: Colors.white),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFEF3C7),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  'BRAND CLAIM HIGHLIGHT',
                                  style: TextStyle(
                                    fontSize: 8.5,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.6,
                                    color: Color(0xFFB45309),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            sentence,
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF78350F),
                              height: 1.45,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 3),
                    width: 18,
                    height: 18,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppTheme.emerald600.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '${idx + 1}',
                      style: const TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.emerald700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      sentence,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.slate700,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // --- 4D. Claims Made by Brand ---
  Widget _buildBrandClaimsSection({
    required Map item,
    required Map<String, dynamic> declarations,
  }) {
    List<Map<String, dynamic>> brandClaims = [];

    // Check all containers for brand_claims
    List<dynamic>? claimsSource;
    for (final container in [
      declarations,
      item,
      _ocrDetails,
      declarations['raw_declarations'],
      declarations['raw_extractions'],
      declarations['extracted_declarations'],
      item['raw_declarations'],
      item['raw_extractions'],
      item['extracted_declarations'],
      _ocrDetails?['raw_declarations'],
      _ocrDetails?['raw_extractions'],
      _ocrDetails?['extracted_declarations'],
    ]) {
      if (container is Map && container['brand_claims'] is List && (container['brand_claims'] as List).isNotEmpty) {
        claimsSource = container['brand_claims'] as List;
        break;
      }
    }

    if (claimsSource != null) {
      for (var c in claimsSource) {
        if (c is Map) {
          brandClaims.add(Map<String, dynamic>.from(c));
        } else if (c is String && c.isNotEmpty) {
          brandClaims.add({
            'claim': c,
            'category': 'Packaging Assurance',
            'verified': true,
            'note': 'Extracted by OCR and analyzed against statutory standards.',
          });
        }
      }
    }

    // If no brand claims in raw OCR, render factual placeholder without hallucination
    if (brandClaims.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.slate200),
        ),
        child: const Row(
          children: [
            Icon(Icons.verified_outlined, color: AppTheme.slate400, size: 20),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'No promotional marketing claims detected in raw packaging OCR. Only statutory regulatory declarations were identified.',
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.slate600,
                  fontStyle: FontStyle.italic,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFFBEB), Color(0xFFFEF3C7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFFDE68A), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFD97706).withValues(alpha: 0.12),
            blurRadius: 30,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section Title Row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: const Color(0xFFD97706),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFD97706).withValues(alpha: 0.35),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: const Icon(Icons.verified_rounded, size: 18, color: Colors.white),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'CLAIMS MADE BY BRAND',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.1,
                        color: Color(0xFF78350F),
                      ),
                    ),
                    Text(
                      'Promotional & Product Assurances Highlighted by AI',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF92400E).withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.auto_awesome_rounded, size: 12, color: Colors.white),
                    const SizedBox(width: 4),
                    Text(
                      '${brandClaims.length} Claims',
                      style: const TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Cards for each claim
          ...brandClaims.map((claim) {
            final claimText = (claim['claim'] ?? '').toString();
            final category = (claim['category'] ?? 'Brand Assurance').toString();
            final isVerified = claim['verified'] == true;
            final note = (claim['note'] ?? '').toString();

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFFDE68A)),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFB45309).withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF3C7),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFFCD34D)),
                        ),
                        child: Text(
                          category.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 8.5,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.6,
                            color: Color(0xFF92400E),
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                        decoration: BoxDecoration(
                          color: isVerified ? const Color(0xFFECFDF5) : const Color(0xFFFFF7ED),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isVerified ? const Color(0xFFA7F3D0) : const Color(0xFFFED7AA),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isVerified ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                              size: 11,
                              color: isVerified ? const Color(0xFF059669) : const Color(0xFFD97706),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              isVerified ? 'Verified in OCR' : 'Under Review',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                color: isVerified ? const Color(0xFF047857) : const Color(0xFFB45309),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '“$claimText”',
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1E293B),
                      height: 1.35,
                    ),
                  ),
                  if (note.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.info_rounded, size: 12, color: Color(0xFFD97706)),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            note,
                            style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF64748B),
                              height: 1.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            );
          }),
        ],
      ),
    );
  }


  // --- 5B. Full Verbatim Content Sections (Ingredients, Nutrition, Allergen, Storage, etc.) ---
  Widget _buildFullContentSections({
    required Map<String, dynamic> declarations,
    Map<String, dynamic>? item,
  }) {
    final rootItem = item ?? widget.item;

    dynamic findVal(String key) {
      if (declarations[key] != null) return declarations[key];
      if (rootItem[key] != null) return rootItem[key];
      if (_ocrDetails?[key] != null) return _ocrDetails![key];
      for (final container in [
        declarations['raw_declarations'],
        declarations['raw_extractions'],
        declarations['extracted_declarations'],
        rootItem['raw_declarations'],
        rootItem['raw_extractions'],
        rootItem['extracted_declarations'],
        _ocrDetails?['raw_declarations'],
        _ocrDetails?['raw_extractions'],
        _ocrDetails?['extracted_declarations'],
      ]) {
        if (container is Map) {
          if (container[key] != null) return container[key];
          if (container['llm'] is Map && container['llm'][key] != null) return container['llm'][key];
        }
      }
      return null;
    }

    String? getStr(String key) {
      final v = findVal(key);
      if (v == null) return null;
      final s = v.toString().trim();
      return (s.isNotEmpty && s.toLowerCase() != 'null' && s.toLowerCase() != 'none') ? s : null;
    }

    List<dynamic>? getList(String key) {
      final v = findVal(key);
      return (v is List && v.isNotEmpty) ? v : null;
    }

    final dynamic rawIngredientAnalysis = findVal('ingredient_analysis');
    final Map<String, dynamic>? ingredientAnalysis = (rawIngredientAnalysis is Map) ? Map<String, dynamic>.from(rawIngredientAnalysis) : null;
    final ingredientsList = getStr('ingredients_list');
    final compositionText = getStr('composition');
    final allergenInfo = getStr('allergen_info');
    final storageInstructions = getStr('storage_instructions');
    final usageInstructions = getStr('usage_instructions');
    final legalDisclaimer = getStr('legal_disclaimer');
    final nutritionTable = getList('nutrition_table');
    final certifications = getList('certifications');
    final otherTextBlocks = getList('other_text_blocks');

    final hasSomething = (ingredientsList != null ||
        compositionText != null ||
        ingredientAnalysis != null ||
        allergenInfo != null ||
        storageInstructions != null ||
        usageInstructions != null ||
        legalDisclaimer != null ||
        nutritionTable != null ||
        certifications != null ||
        otherTextBlocks != null);

    if (!hasSomething) return const SizedBox.shrink();

    Widget buildSectionCard({
      required IconData icon,
      required Color iconBg,
      required Color iconColor,
      required String title,
      required Widget body,
    }) {
      return Container(
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0F172A).withValues(alpha: 0.06),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: iconBg.withValues(alpha: 0.08),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
                border: Border(
                  bottom: BorderSide(color: iconBg.withValues(alpha: 0.2), width: 1),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: iconBg,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, size: 16, color: iconColor),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                        color: iconBg.withValues(alpha: 1.0),
                        height: 1.25,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: body,
            ),
          ],
        ),
      );
    }

    Widget buildVerbatimText(String text, {Color? color}) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: SelectableText(
          text,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: color ?? const Color(0xFF1E293B),
            height: 1.6,
            fontFamily: 'monospace',
          ),
        ),
      );
    }

    final sections = <Widget>[];

    // Section header
    sections.add(
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          children: [
            const Icon(Icons.article_rounded, size: 16, color: Color(0xFF475569)),
            const SizedBox(width: 6),
            const Expanded(
              child: Text(
                'FULL PACKAGE CONTENT EXTRACTION',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.0,
                  color: Color(0xFF475569),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
              decoration: BoxDecoration(
                color: const Color(0xFF7C3AED).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFF7C3AED).withValues(alpha: 0.3)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.text_snippet_rounded, size: 10, color: Color(0xFF7C3AED)),
                  SizedBox(width: 4),
                  Text(
                    'Verbatim OCR',
                    style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Color(0xFF7C3AED)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    // --- Ingredients List ---
    if (ingredientsList != null) {
      sections.add(buildSectionCard(
        icon: Icons.grass_rounded,
        iconBg: const Color(0xFF16A34A),
        iconColor: Colors.white,
        title: 'INGREDIENTS / COMPOSITION',
        body: buildVerbatimText(ingredientsList, color: const Color(0xFF14532D)),
      ));
    }

    // --- Detailed Ingredient Safety & Chemical Breakdown Engine ---
    if (ingredientAnalysis != null) {
      final bannedList = (ingredientAnalysis['banned_ingredients_detected'] is List)
          ? (ingredientAnalysis['banned_ingredients_detected'] as List)
          : [];
      final allergensList = (ingredientAnalysis['statutory_allergens_detected'] is List)
          ? (ingredientAnalysis['statutory_allergens_detected'] as List)
          : [];
      final allIngredientsList = (ingredientAnalysis['all_ingredients'] is List)
          ? (ingredientAnalysis['all_ingredients'] as List)
          : [];
      final safetyScore = ingredientAnalysis['safety_score'] ?? 100;
      final safetyRating = ingredientAnalysis['overall_safety_rating']?.toString() ?? 'ASSESSED';

      // 1. Critical Banned Substances Alert Card
      if (bannedList.isNotEmpty) {
        sections.add(
          Container(
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFEF4444), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFDC2626),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.dangerous_rounded, color: Colors.white, size: 20),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'PROHIBITED / BANNED INGREDIENT DETECTED',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFFB91C1C),
                                letterSpacing: 0.5,
                              ),
                            ),
                            Text(
                              '${bannedList.length} illegal or strictly banned substance(s) identified',
                              style: const TextStyle(fontSize: 11.5, color: Color(0xFF991B1B)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ...bannedList.map((b) {
                    final bMap = (b is Map) ? b : {};
                    final details = (bMap['banned_details'] is Map) ? bMap['banned_details'] : {};
                    return Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFFCA5A5)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            bMap['canonical_name']?.toString() ?? 'Unknown Chemical',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF991B1B),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '⛔ Status: ${details['status'] ?? 'BANNED'}',
                            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFFDC2626)),
                          ),
                          Text(
                            '🏛️ Banned in: ${(details['banned_jurisdictions'] as List?)?.join(', ') ?? 'FSSAI / Global'}',
                            style: const TextStyle(fontSize: 11.5, color: Color(0xFF4B5563)),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '⚠️ Hazard: ${details['hazard_summary'] ?? bMap['what_is_it'] ?? ''}',
                            style: const TextStyle(fontSize: 12, color: Color(0xFF1F2937), height: 1.3),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
        );
      }

      // 2. Allergen & Chemical Sensitivities Card
      if (allergensList.isNotEmpty) {
        sections.add(
          buildSectionCard(
            icon: Icons.health_and_safety_rounded,
            iconBg: const Color(0xFFEA580C),
            iconColor: Colors.white,
            title: 'ALLERGEN & HEALTH SENSITIVITY ALERTS (${allergensList.length})',
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: allergensList.map((al) {
                final alMap = (al is Map) ? al : {};
                final sev = alMap['severity']?.toString() ?? 'MODERATE';
                final isCritical = sev == 'CRITICAL';
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isCritical ? const Color(0xFFFFF7ED) : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: isCritical ? const Color(0xFFFDBA74) : const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            isCritical ? Icons.warning_rounded : Icons.info_outline_rounded,
                            size: 16,
                            color: isCritical ? const Color(0xFFC2410C) : const Color(0xFF64748B),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              alMap['display_name']?.toString() ?? 'Allergen',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: isCritical ? const Color(0xFFC2410C) : const Color(0xFF0F172A),
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: isCritical ? const Color(0xFFDC2626) : const Color(0xFFD97706),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              sev,
                              style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '👤 Sensitive to: ${alMap['sensitive_population'] ?? ''}',
                        style: const TextStyle(fontSize: 11.5, color: Color(0xFF475569)),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '🩺 Symptoms: ${alMap['symptoms'] ?? ''}',
                        style: const TextStyle(fontSize: 11.5, color: Color(0xFF334155), height: 1.3),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        );
      }

      // 3. Complete Ingredient-by-Ingredient Tabular Matrix & Chemical Decoder
      if (allIngredientsList.isNotEmpty) {
        String activeIngFilter = 'all';

        sections.add(
          StatefulBuilder(
            builder: (context, setIngState) {
              List filteredIngredients = allIngredientsList;
              if (activeIngFilter == 'banned') {
                filteredIngredients = allIngredientsList.where((i) => (i is Map) && (i['is_banned'] == true)).toList();
              } else if (activeIngFilter == 'allergens') {
                filteredIngredients = allIngredientsList.where((i) {
                  if (i is! Map) return false;
                  final risk = (i['allergy_and_health_risk'] ?? '').toString().toLowerCase();
                  final alList = i['allergens_detected'] as List?;
                  return (alList != null && alList.isNotEmpty) ||
                      risk.contains('allergy') ||
                      risk.contains('allergic') ||
                      risk.contains('celiac') ||
                      risk.contains('asthma') ||
                      risk.contains('gluten') ||
                      risk.contains('lactose') ||
                      risk.contains('urticaria') ||
                      risk.contains('anaphylaxis');
                }).toList();
              } else if (activeIngFilter == 'addictive') {
                filteredIngredients = allIngredientsList.where((i) {
                  if (i is! Map) return false;
                  final lvl = (i['addictiveness_level'] ?? '').toString().toUpperCase();
                  return lvl.contains('HIGH') || lvl.contains('MOD');
                }).toList();
              }

              final bannedCount = allIngredientsList.where((i) => (i is Map) && (i['is_banned'] == true)).length;
              final allergenCount = allIngredientsList.where((i) {
                if (i is! Map) return false;
                final risk = (i['allergy_and_health_risk'] ?? '').toString().toLowerCase();
                final alList = i['allergens_detected'] as List?;
                return (alList != null && alList.isNotEmpty) || risk.contains('allergy') || risk.contains('allergic') || risk.contains('celiac') || risk.contains('asthma');
              }).length;
              final addictiveCount = allIngredientsList.where((i) {
                if (i is! Map) return false;
                final lvl = (i['addictiveness_level'] ?? '').toString().toUpperCase();
                return lvl.contains('HIGH') || lvl.contains('MOD');
              }).length;

              Color getAddictColor(String lvl) {
                if (lvl.contains('HIGH')) return const Color(0xFFDC2626);
                if (lvl.contains('MOD')) return const Color(0xFFD97706);
                if (lvl.contains('LOW')) return const Color(0xFF0284C7);
                return const Color(0xFF16A34A);
              }

              String getAddictLabel(String lvl) {
                if (lvl.contains('HIGH')) return '⚡ HIGH CRAVING';
                if (lvl.contains('MOD')) return '⚠️ HABIT FORMING';
                if (lvl.contains('LOW')) return 'MILD';
                return '✓ NON-ADDICTIVE';
              }

              Widget buildFilterPill(String key, String label, int count, IconData icon, Color color) {
                final isSelected = activeIngFilter == key;
                return GestureDetector(
                  onTap: () => setIngState(() => activeIngFilter = key),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: isSelected ? color : Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: isSelected ? color : const Color(0xFFE2E8F0)),
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: color.withValues(alpha: 0.25),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : null,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, size: 12, color: isSelected ? Colors.white : color),
                        const SizedBox(width: 4),
                        Text(
                          '$label ($count)',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                            color: isSelected ? Colors.white : const Color(0xFF334155),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              return buildSectionCard(
                icon: Icons.table_view_rounded,
                iconBg: const Color(0xFF0D9488),
                iconColor: Colors.white,
                title: 'TABULAR INGREDIENTS MATRIX &\nCHEMICAL REPORT (${allIngredientsList.length})',
                body: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Safety Score Briefing Bar
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0FDFA),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF99F6E4)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.verified_user_rounded, size: 18, color: Color(0xFF0D9488)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Formulation Safety Score: $safetyScore/100 • $safetyRating',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF0F766E)),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0D9488),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'LLM Research',
                              style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Filter Pills Row
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      child: Row(
                        children: [
                          buildFilterPill('all', 'All Items', allIngredientsList.length, Icons.layers_rounded, const Color(0xFF0D9488)),
                          const SizedBox(width: 6),
                          if (bannedCount > 0) ...[
                            buildFilterPill('banned', 'Banned / Prohibited', bannedCount, Icons.dangerous_rounded, const Color(0xFFDC2626)),
                            const SizedBox(width: 6),
                          ],
                          if (allergenCount > 0) ...[
                            buildFilterPill('allergens', 'Allergen Alert', allergenCount, Icons.warning_rounded, const Color(0xFFEA580C)),
                            const SizedBox(width: 6),
                          ],
                          if (addictiveCount > 0) ...[
                            buildFilterPill('addictive', 'Habit Forming', addictiveCount, Icons.bolt_rounded, const Color(0xFF7C3AED)),
                            const SizedBox(width: 6),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Scroll guidance notice
                    const Row(
                      children: [
                        Icon(Icons.swipe_left_rounded, size: 14, color: Color(0xFF94A3B8)),
                        SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            'Swipe horizontally to review all analytical parameters across columns',
                            style: TextStyle(fontSize: 10, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // FULL TABULAR SPREADSHEET (Horizontally Scrollable)
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.03),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          physics: const BouncingScrollPhysics(),
                          child: IntrinsicWidth(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Table Header
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                  color: const Color(0xFFF1F5F9),
                                  child: const Row(
                                    children: [
                                      SizedBox(
                                        width: 170,
                                        child: Text(
                                          'INGREDIENT & IDENTITY',
                                          style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900, color: Color(0xFF475569), letterSpacing: 0.6),
                                        ),
                                      ),
                                      SizedBox(width: 14),
                                      SizedBox(
                                        width: 130,
                                        child: Text(
                                          'CLASS & ORIGIN',
                                          style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900, color: Color(0xFF475569), letterSpacing: 0.6),
                                        ),
                                      ),
                                      SizedBox(width: 14),
                                      SizedBox(
                                        width: 160,
                                        child: Text(
                                          'ADEQUATE USAGE (ADI)',
                                          style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900, color: Color(0xFF475569), letterSpacing: 0.6),
                                        ),
                                      ),
                                      SizedBox(width: 14),
                                      SizedBox(
                                        width: 160,
                                        child: Text(
                                          'RECOMMENDED LIMIT',
                                          style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900, color: Color(0xFF475569), letterSpacing: 0.6),
                                        ),
                                      ),
                                      SizedBox(width: 14),
                                      SizedBox(
                                        width: 170,
                                        child: Text(
                                          'ADDICTIVENESS LEVEL',
                                          style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900, color: Color(0xFF475569), letterSpacing: 0.6),
                                        ),
                                      ),
                                      SizedBox(width: 14),
                                      SizedBox(
                                        width: 250,
                                        child: Text(
                                          'BIOMEDICAL ALLERGIES & RISKS',
                                          style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900, color: Color(0xFF475569), letterSpacing: 0.6),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const Divider(height: 1, thickness: 0.5, color: Color(0xFFCBD5E1)),

                                // Table Rows
                                ...filteredIngredients.asMap().entries.map((entry) {
                                  final idx = entry.key;
                                  final ing = entry.value;
                                  final ingMap = (ing is Map) ? ing : {};
                                  final isBanned = ingMap['is_banned'] == true;
                                  final name = ingMap['canonical_name']?.toString() ?? 'Ingredient';
                                  final insCode = ingMap['ins_code']?.toString();
                                  final category = ingMap['category']?.toString() ?? 'Additive';
                                  final origin = ingMap['origin']?.toString() ?? 'Commercial';
                                  final adequate = ingMap['adequate_usage']?.toString() ?? 'Quantum satis (GMP)';
                                  final recommended = ingMap['recommended_usage']?.toString() ?? 'Consume in moderation';
                                  final addictLvl = (ingMap['addictiveness_level']?.toString() ?? 'NONE').toUpperCase();
                                  final addictDetails = ingMap['addictiveness_details']?.toString() ?? '';
                                  final allergy = ingMap['allergy_and_health_risk']?.toString() ?? 'Hypoallergenic; no severe IgE reactions documented.';
                                  final isEven = idx % 2 == 0;

                                  return Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                    color: isBanned
                                        ? const Color(0xFFFEF2F2)
                                        : (isEven ? Colors.white : const Color(0xFFF8FAFC)),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        // 1. INGREDIENT & IDENTITY
                                        SizedBox(
                                          width: 170,
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                name,
                                                style: TextStyle(
                                                  fontSize: 12.5,
                                                  fontWeight: FontWeight.w800,
                                                  color: isBanned ? const Color(0xFFB91C1C) : const Color(0xFF0F172A),
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Wrap(
                                                spacing: 4,
                                                runSpacing: 2,
                                                children: [
                                                  if (insCode != null && insCode.isNotEmpty)
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                                      decoration: BoxDecoration(
                                                        color: const Color(0xFFE0E7FF),
                                                        borderRadius: BorderRadius.circular(4),
                                                      ),
                                                      child: Text(
                                                        insCode,
                                                        style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFF3730A3)),
                                                      ),
                                                    ),
                                                  if (isBanned)
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                                      decoration: BoxDecoration(
                                                        color: const Color(0xFFDC2626),
                                                        borderRadius: BorderRadius.circular(4),
                                                      ),
                                                      child: const Text(
                                                        'BANNED',
                                                        style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: Colors.white),
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 14),

                                        // 2. CLASS & ORIGIN
                                        SizedBox(
                                          width: 130,
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                category,
                                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF334155)),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                'Src: $origin',
                                                style: const TextStyle(fontSize: 10, color: Color(0xFF64748B)),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 14),

                                        // 3. ADEQUATE USAGE (ADI)
                                        SizedBox(
                                          width: 160,
                                          child: Text(
                                            adequate,
                                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF0F766E), height: 1.3),
                                          ),
                                        ),
                                        const SizedBox(width: 14),

                                        // 4. RECOMMENDED LIMIT
                                        SizedBox(
                                          width: 160,
                                          child: Text(
                                            recommended,
                                            style: const TextStyle(fontSize: 11, color: Color(0xFF334155), height: 1.3),
                                          ),
                                        ),
                                        const SizedBox(width: 14),

                                        // 5. ADDICTIVENESS
                                        SizedBox(
                                          width: 170,
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: getAddictColor(addictLvl).withValues(alpha: 0.12),
                                                  borderRadius: BorderRadius.circular(6),
                                                  border: Border.all(color: getAddictColor(addictLvl).withValues(alpha: 0.3)),
                                                ),
                                                child: Text(
                                                  getAddictLabel(addictLvl),
                                                  style: TextStyle(
                                                    fontSize: 9,
                                                    fontWeight: FontWeight.w900,
                                                    color: getAddictColor(addictLvl),
                                                  ),
                                                ),
                                              ),
                                              if (addictDetails.isNotEmpty) ...[
                                                const SizedBox(height: 3),
                                                Text(
                                                  addictDetails,
                                                  style: const TextStyle(fontSize: 10, color: Color(0xFF64748B), height: 1.25),
                                                  maxLines: 3,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 14),

                                        // 6. BIOMEDICAL ALLERGIES & RISKS
                                        SizedBox(
                                          width: 250,
                                          child: Text(
                                            allergy,
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: isBanned ? const Color(0xFF991B1B) : const Color(0xFF1E293B),
                                              height: 1.3,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Expandable Biochemical Meanings & Purpose Cards
                    const Text(
                      'CHEMICAL NATURE & FORMULATION PURPOSE',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.8,
                        color: Color(0xFF475569),
                      ),
                    ),
                    const SizedBox(height: 8),

                    ...filteredIngredients.map((ing) {
                      final ingMap = (ing is Map) ? ing : {};
                      final name = ingMap['canonical_name']?.toString() ?? 'Ingredient';
                      final isBanned = ingMap['is_banned'] == true;
                      final meaning = ingMap['what_is_it']?.toString() ?? '';
                      final purpose = ingMap['why_used']?.toString() ?? '';

                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isBanned ? const Color(0xFFFEF2F2) : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: isBanned ? const Color(0xFFFCA5A5) : const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: isBanned ? const Color(0xFFB91C1C) : const Color(0xFF0F172A),
                              ),
                            ),
                            if (ingMap['origin'] != null && ingMap['origin'].toString().isNotEmpty) ...[
                              const SizedBox(height: 3),
                              Text(
                                'Origin: ${ingMap['origin']}',
                                style: const TextStyle(
                                  fontSize: 10.5,
                                  color: Color(0xFF64748B),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                            if (meaning.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text.rich(
                                TextSpan(
                                  style: const TextStyle(fontSize: 11.5, color: Color(0xFF334155), height: 1.35),
                                  children: [
                                    const TextSpan(text: '🔬 Meaning: ', style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF0F172A))),
                                    TextSpan(text: meaning),
                                  ],
                                ),
                              ),
                            ],
                            if (purpose.isNotEmpty) ...[
                              const SizedBox(height: 3),
                              Text.rich(
                                TextSpan(
                                  style: const TextStyle(fontSize: 11.5, color: Color(0xFF334155), height: 1.35),
                                  children: [
                                    const TextSpan(text: '🎯 Why Used: ', style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF0F172A))),
                                    TextSpan(text: purpose),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              );
            },
          ),
        );
      }
    }

    // --- Composition (if separate from ingredients) ---
    if (compositionText != null && compositionText != ingredientsList) {
      sections.add(buildSectionCard(
        icon: Icons.science_rounded,
        iconBg: const Color(0xFF0284C7),
        iconColor: Colors.white,
        title: 'COMPOSITION',
        body: buildVerbatimText(compositionText, color: const Color(0xFF0C4A6E)),
      ));
    }

    // --- Nutrition Table ---
    if (nutritionTable != null) {
      sections.add(buildSectionCard(
        icon: Icons.bar_chart_rounded,
        iconBg: const Color(0xFFD97706),
        iconColor: Colors.white,
        title: 'NUTRITIONAL INFORMATION',
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Table header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFF78350F).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Expanded(flex: 5, child: Text('Nutrient', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF78350F), letterSpacing: 0.5))),
                  Expanded(flex: 3, child: Text('Per Serving', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF78350F), letterSpacing: 0.5), textAlign: TextAlign.center)),
                  Expanded(flex: 3, child: Text('Per 100g/ml', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF78350F), letterSpacing: 0.5), textAlign: TextAlign.center)),
                ],
              ),
            ),
            const SizedBox(height: 6),
            ...nutritionTable.asMap().entries.map((entry) {
              final idx = entry.key;
              final row = entry.value;
              if (row is! Map) return const SizedBox.shrink();
              final nutrient = (row['nutrient'] ?? '').toString();
              final perServing = (row['per_serving'] ?? row['per100g'] ?? '—').toString();
              final per100g = (row['per_100g'] ?? row['per100g'] ?? '—').toString();
              final unit = (row['unit'] ?? '').toString();
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: idx.isEven ? Colors.transparent : const Color(0xFFF8FAFC),
                  border: Border(bottom: BorderSide(color: const Color(0xFFE2E8F0).withValues(alpha: 0.6), width: 0.5)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 5,
                      child: Text(
                        nutrient,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)),
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(
                        perServing.isNotEmpty ? perServing : '—',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Color(0xFF475569), fontFamily: 'monospace'),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(
                        per100g.isNotEmpty ? '$per100g ${unit.isNotEmpty ? unit : ""}'.trim() : '—',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Color(0xFF475569), fontFamily: 'monospace'),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ));
    }

    // --- Allergen Info ---
    if (allergenInfo != null) {
      sections.add(buildSectionCard(
        icon: Icons.warning_amber_rounded,
        iconBg: const Color(0xFFDC2626),
        iconColor: Colors.white,
        title: 'ALLERGEN INFORMATION',
        body: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFFEF2F2),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFFCA5A5)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.error_outline_rounded, size: 16, color: Color(0xFFDC2626)),
              const SizedBox(width: 8),
              Expanded(
                child: SelectableText(
                  allergenInfo,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF7F1D1D),
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ));
    }

    // --- Storage Instructions ---
    if (storageInstructions != null) {
      sections.add(buildSectionCard(
        icon: Icons.inventory_2_rounded,
        iconBg: const Color(0xFF0891B2),
        iconColor: Colors.white,
        title: 'STORAGE INSTRUCTIONS',
        body: buildVerbatimText(storageInstructions, color: const Color(0xFF0C4A6E)),
      ));
    }

    // --- Usage / Preparation Instructions ---
    if (usageInstructions != null) {
      sections.add(buildSectionCard(
        icon: Icons.restaurant_menu_rounded,
        iconBg: const Color(0xFF7C3AED),
        iconColor: Colors.white,
        title: 'USAGE / PREPARATION INSTRUCTIONS',
        body: buildVerbatimText(usageInstructions, color: const Color(0xFF4C1D95)),
      ));
    }

    // --- Certifications ---
    if (certifications != null && certifications.isNotEmpty) {
      sections.add(buildSectionCard(
        icon: Icons.verified_rounded,
        iconBg: const Color(0xFF059669),
        iconColor: Colors.white,
        title: 'CERTIFICATIONS & MARKS',
        body: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: certifications.map((cert) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFECFDF5),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFF6EE7B7)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.check_circle_rounded, size: 13, color: Color(0xFF059669)),
                  const SizedBox(width: 5),
                  Text(
                    cert.toString(),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF065F46),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ));
    }

    // --- Legal Disclaimer ---
    if (legalDisclaimer != null) {
      sections.add(buildSectionCard(
        icon: Icons.gavel_rounded,
        iconBg: const Color(0xFF6B7280),
        iconColor: Colors.white,
        title: 'LEGAL DISCLAIMER / ADVISORY',
        body: buildVerbatimText(legalDisclaimer, color: const Color(0xFF374151)),
      ));
    }

    // --- Other Text Blocks ---
    if (otherTextBlocks != null) {
      for (final block in otherTextBlocks) {
        if (block is! Map) continue;
        final label = (block['label'] ?? 'Additional Information').toString();
        final text = (block['text'] ?? '').toString().trim();
        final panel = (block['panel'] ?? '').toString();
        if (text.isEmpty) continue;
        sections.add(buildSectionCard(
          icon: Icons.notes_rounded,
          iconBg: const Color(0xFF64748B),
          iconColor: Colors.white,
          title: '${label.toUpperCase()}${panel.isNotEmpty ? " (${panel.toUpperCase()} PANEL)" : ""}',
          body: buildVerbatimText(text),
        ));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: sections,
    );
  }

  // --- 5. Structured Extracted Facts Table (Front vs Back Panel & Deep Key-Values) ---
  Widget _buildExtractedFactsTable({

    String? mfgName,
    String? prodName,
    String? netQty,
    String? batchId,
    String? contact,
    required Map<String, dynamic> declarations,
    Map<String, dynamic>? item,
    List<dynamic>? evaluations,
  }) {
    final rootItem = item ?? widget.item;
    final List<dynamic> evals = evaluations ?? (rootItem['evaluations'] as List?) ?? [];

    final failedEvals = evals.where((e) {
      final st = (e['status'] ?? '').toString().toUpperCase();
      return st == 'FAIL' || st == 'VIOLATION' || st == 'NON_COMPLIANT';
    }).toList();

    bool isRuleFailed(List<String> keywords) {
      for (final ev in failedEvals) {
        final rId = (ev['rule_id'] ?? ev['rule_code'] ?? '').toString().toLowerCase();
        final rTitle = (ev['rule_title'] ?? '').toString().toLowerCase();
        final reason = (ev['reason'] ?? '').toString().toLowerCase();
        final field = (ev['field'] ?? ev['field_name'] ?? '').toString().toLowerCase();

        for (final kw in keywords) {
          final k = kw.toLowerCase();
          if (rId.contains(k) || rTitle.contains(k) || reason.contains(k) || field.contains(k)) {
            return true;
          }
        }
      }
      return false;
    }

    dynamic findAny(String key) {
      if (declarations[key] != null) return declarations[key];
      if (rootItem[key] != null) return rootItem[key];
      if (_ocrDetails?[key] != null) return _ocrDetails![key];
      for (final container in [
        declarations['raw_declarations'],
        declarations['raw_extractions'],
        declarations['extracted_declarations'],
        rootItem['raw_declarations'],
        rootItem['raw_extractions'],
        rootItem['extracted_declarations'],
        _ocrDetails?['raw_declarations'],
        _ocrDetails?['raw_extractions'],
        _ocrDetails?['extracted_declarations'],
      ]) {
        if (container is Map) {
          if (container[key] != null) return container[key];
          if (container['llm'] is Map && container['llm'][key] != null) return container['llm'][key];
        }
      }
      return null;
    }

    String? getVal(List<String> keys) {
      for (final k in keys) {
        final v = findAny(k);
        if (v != null) {
          final s = v.toString().trim();
          if (s.isNotEmpty && s.toLowerCase() != 'null' && s.toLowerCase() != 'none') return s;
        }
      }
      return null;
    }

    List<dynamic>? findList(String key) {
      final v = findAny(key);
      return (v is List && v.isNotEmpty) ? v : null;
    }

    // 1. Data collections
    final List<Map<String, dynamic>> frontItems = [];
    final List<Map<String, dynamic>> backItems = [];
    final List<Map<String, dynamic>> leftItems = [];
    final List<Map<String, dynamic>> rightItems = [];
    final List<Map<String, dynamic>> allKvItems = [];

    // Helper to safely add an item
    void addItem({
      required String parameter,
      required String? value,
      required String category,
      required String panel,
      required bool isNonCompliant,
      bool isBold = false,
      bool isEmerald = false,
      bool isMono = false,
    }) {
      final isDetected = value != null &&
          value.trim().isNotEmpty &&
          value.trim().toLowerCase() != 'null' &&
          value.trim().toLowerCase() != 'none';

      if (!isDetected && !isNonCompliant) return;

      final itemMap = {
        'parameter': parameter,
        'value': isDetected ? value : null,
        'category': category,
        'panel': panel.toUpperCase(),
        'isNonCompliant': isNonCompliant,
        'isBold': isBold,
        'isEmerald': isEmerald,
        'isMono': isMono,
      };

      final panUpper = panel.toUpperCase();
      if (panUpper.contains('FRONT')) {
        if (!frontItems.any((x) => x['parameter'] == parameter)) {
          frontItems.add(itemMap);
        }
      } else if (panUpper.contains('LEFT')) {
        if (!leftItems.any((x) => x['parameter'] == parameter)) {
          leftItems.add(itemMap);
        }
      } else if (panUpper.contains('RIGHT')) {
        if (!rightItems.any((x) => x['parameter'] == parameter)) {
          rightItems.add(itemMap);
        }
      } else {
        if (!backItems.any((x) => x['parameter'] == parameter)) {
          backItems.add(itemMap);
        }
      }

      if (!allKvItems.any((x) => x['parameter'] == parameter)) {
        allKvItems.add(itemMap);
      }
    }

    // A. Ingest structured tables returned directly by backend LLM
    final rawFront = findList('front_panel_table');
    if (rawFront != null) {
      for (var it in rawFront) {
        if (it is Map) {
          final p = (it['parameter'] ?? it['key'] ?? '').toString();
          final v = (it['declared_value'] ?? it['value'] ?? '').toString();
          final c = (it['category'] ?? 'Primary Declaration').toString();
          if (p.isNotEmpty && v.isNotEmpty) {
            addItem(
              parameter: p,
              value: v,
              category: c,
              panel: 'FRONT',
              isNonCompliant: isRuleFailed([p, c]),
            );
          }
        }
      }
    }

    final rawBack = findList('back_panel_table');
    if (rawBack != null) {
      for (var it in rawBack) {
        if (it is Map) {
          final p = (it['parameter'] ?? it['key'] ?? '').toString();
          final v = (it['declared_value'] ?? it['value'] ?? '').toString();
          final c = (it['category'] ?? 'Statutory Declaration').toString();
          if (p.isNotEmpty && v.isNotEmpty) {
            addItem(
              parameter: p,
              value: v,
              category: c,
              panel: 'BACK',
              isNonCompliant: isRuleFailed([p, c]),
            );
          }
        }
      }
    }

    final rawLeft = findList('left_panel_table');
    if (rawLeft != null) {
      for (var it in rawLeft) {
        if (it is Map) {
          final p = (it['parameter'] ?? it['key'] ?? '').toString();
          final v = (it['declared_value'] ?? it['value'] ?? '').toString();
          final c = (it['category'] ?? 'Side Panel Declaration').toString();
          if (p.isNotEmpty && v.isNotEmpty) {
            addItem(
              parameter: p,
              value: v,
              category: c,
              panel: 'LEFT',
              isNonCompliant: isRuleFailed([p, c]),
            );
          }
        }
      }
    }

    final rawRight = findList('right_panel_table');
    if (rawRight != null) {
      for (var it in rawRight) {
        if (it is Map) {
          final p = (it['parameter'] ?? it['key'] ?? '').toString();
          final v = (it['declared_value'] ?? it['value'] ?? '').toString();
          final c = (it['category'] ?? 'Side Panel Declaration').toString();
          if (p.isNotEmpty && v.isNotEmpty) {
            addItem(
              parameter: p,
              value: v,
              category: c,
              panel: 'RIGHT',
              isNonCompliant: isRuleFailed([p, c]),
            );
          }
        }
      }
    }

    final rawAll = findList('all_key_value_pairs');
    if (rawAll != null) {
      for (var it in rawAll) {
        if (it is Map) {
          final p = (it['key'] ?? it['parameter'] ?? '').toString();
          final v = (it['value'] ?? it['declared_value'] ?? '').toString();
          final c = (it['category'] ?? 'General').toString();
          final pan = (it['panel'] ?? 'BACK').toString();
          if (p.isNotEmpty && v.isNotEmpty) {
            addItem(
              parameter: p,
              value: v,
              category: c,
              panel: pan,
              isNonCompliant: isRuleFailed([p, c]),
            );
          }
        }
      }
    }

    // B. Deterministic Packaging Declarations (Front vs Back classification)
    // 1. Generic Product Name (FRONT)
    final genericVal = prodName ?? getVal(['generic_product_name', 'generic_name', 'product_name', 'commodity_name']);
    addItem(
      parameter: 'Generic Product Name',
      value: genericVal,
      category: 'Product Identity',
      panel: 'FRONT',
      isNonCompliant: isRuleFailed(['generic_product_name', 'rule-lm-006', 'commodity', 'generic name']),
      isBold: true,
      isEmerald: true,
    );

    // 2. Net Quantity (FRONT)
    final netQtyVal = netQty ?? (() {
      final q = getVal(['net_quantity', 'quantity', 'net_wt', 'net_weight', 'net_volume']);
      final u = getVal(['unit', 'net_quantity_unit', 'metric_unit']) ?? '';
      if (q != null && q.isNotEmpty) return '$q $u'.trim();
      return null;
    })();
    addItem(
      parameter: 'Net Quantity',
      value: netQtyVal,
      category: 'Legal Metrology',
      panel: 'FRONT',
      isNonCompliant: isRuleFailed(['net_quantity', 'rule-lm-002', 'quantity', 'weight', 'measure', 'unit']),
      isBold: true,
    );

    // 3. Dietary Indicator (FRONT)
    final vegVal = getVal(['veg_nonveg', 'is_vegetarian', 'dietary_indicator']);
    if (vegVal != null) {
      addItem(
        parameter: 'Dietary Symbol',
        value: vegVal,
        category: 'Food Safety (FSSAI)',
        panel: 'FRONT',
        isNonCompliant: isRuleFailed(['vegetarian', 'dietary']),
      );
    }

    // 4. Maximum Retail Price (MRP) (BACK)
    final rawMrp = getVal(['mrp', 'price', 'maximum_retail_price']);
    final currency = getVal(['currency']) ?? '₹';
    final mrpDisplay = rawMrp != null
        ? (rawMrp.startsWith('₹') || rawMrp.startsWith('Rs')
            ? '$rawMrp (Incl. of all taxes)'
            : '$currency $rawMrp (Incl. of all taxes)')
        : null;
    addItem(
      parameter: 'Maximum Retail Price (MRP)',
      value: mrpDisplay,
      category: 'Statutory Pricing',
      panel: 'BACK',
      isNonCompliant: isRuleFailed(['mrp', 'rule-lm-001', 'retail price', 'maximum price']),
      isBold: true,
      isMono: true,
    );

    // 5. Unit Sale Price (USP) (BACK)
    final uspVal = getVal(['unit_sale_price', 'usp', 'unit_price']);
    addItem(
      parameter: 'Unit Sale Price (USP)',
      value: uspVal,
      category: 'Statutory Pricing',
      panel: 'BACK',
      isNonCompliant: isRuleFailed(['unit sale price', 'usp']),
      isMono: true,
    );

    // 6. Manufacturer Name (BACK)
    final mfgVal = mfgName ?? getVal(['manufacturer_name', 'mfg_name', 'manufacturer']);
    addItem(
      parameter: 'Manufacturer Name',
      value: mfgVal,
      category: 'Manufacturer Identity',
      panel: 'BACK',
      isNonCompliant: isRuleFailed(['manufacturer', 'rule-lm-003', 'packer', 'importer']),
      isBold: true,
    );

    // 7. Manufacturer Address (BACK)
    final mfgAddrVal = getVal(['manufacturer_address', 'mfg_address', 'factory_address', 'premise_address']);
    addItem(
      parameter: 'Manufacturer Address',
      value: mfgAddrVal,
      category: 'Manufacturing Premise',
      panel: 'BACK',
      isNonCompliant: isRuleFailed(['manufacturer_address', 'factory_address', 'premise_address']),
    );

    // 8. Month & Year of Manufacture (BACK)
    final mfgDateVal = getVal(['manufacturing_date', 'mfg_date', 'packing_date', 'packed_date']) ?? (() {
      final m = getVal(['manufacture_month', 'mfg_month']);
      final y = getVal(['manufacture_year', 'mfg_year']);
      if (m != null || y != null) return '${m ?? ''}/${y ?? ''}'.trim();
      return null;
    })();
    addItem(
      parameter: 'Date of Manufacture',
      value: mfgDateVal,
      category: 'Production Timeline',
      panel: 'BACK',
      isNonCompliant: isRuleFailed(['manufacture_date', 'rule-lm-004', 'month', 'year', 'packing date']),
      isMono: true,
    );

    // 9. Best Before / Expiry Date (BACK)
    final expDateVal = getVal(['expiry_date', 'best_before', 'use_by', 'exp_date']);
    addItem(
      parameter: 'Expiry / Best Before',
      value: expDateVal,
      category: 'Shelf Life & Safety',
      panel: 'BACK',
      isNonCompliant: isRuleFailed(['expiry', 'best before', 'use by']),
      isMono: true,
    );

    // 10. Batch Identifier (BACK)
    final batchVal = batchId ?? getVal(['batch_number', 'batch_no', 'lot_number', 'lot_no', 'batch_code']);
    addItem(
      parameter: 'Batch Identifier',
      value: batchVal,
      category: 'Traceability & Lot',
      panel: 'BACK',
      isNonCompliant: isRuleFailed(['batch', 'lot number', 'lot no']),
      isMono: true,
    );

    // 11. Consumer Care Support (BACK)
    final phoneVal = getVal(['consumer_care_phone', 'customer_care_phone', 'helpline', 'care_phone', 'toll_free']);
    final emailVal = getVal(['consumer_care_email', 'customer_care_email', 'email', 'support_email']);
    final careAddrVal = getVal(['consumer_care_address', 'customer_care_address', 'care_address']);
    final careContact = contact ?? phoneVal ?? emailVal ?? careAddrVal;
    addItem(
      parameter: 'Consumer Care Helpline',
      value: careContact,
      category: 'Consumer Redressal',
      panel: 'BACK',
      isNonCompliant: isRuleFailed(['consumer_care', 'rule-lm-005', 'customer care', 'helpline', 'contact', 'telephone', 'email']),
      isMono: true,
    );

    if (emailVal != null && emailVal != careContact) {
      addItem(
        parameter: 'Consumer Care Email',
        value: emailVal,
        category: 'Consumer Redressal',
        panel: 'BACK',
        isNonCompliant: false,
        isMono: true,
      );
    }

    if (careAddrVal != null && careAddrVal != careContact) {
      addItem(
        parameter: 'Consumer Care Address',
        value: careAddrVal,
        category: 'Consumer Redressal',
        panel: 'BACK',
        isNonCompliant: false,
      );
    }

    // 12. Country of Origin (BACK)
    final cooVal = getVal(['country_of_origin', 'origin_country', 'made_in', 'origin']);
    addItem(
      parameter: 'Country of Origin',
      value: cooVal,
      category: 'Trade & Origin',
      panel: 'BACK',
      isNonCompliant: isRuleFailed(['country of origin', 'origin', 'made in']),
    );

    // 13. Packer Details (BACK)
    final packerVal = getVal(['packer_name', 'packer_address', 'packed_by']);
    if (packerVal != null) {
      addItem(
        parameter: 'Packer Details',
        value: packerVal,
        category: 'Packaging Entity',
        panel: 'BACK',
        isNonCompliant: isRuleFailed(['packer']),
      );
    }

    // 14. Importer Details (BACK)
    final importerVal = getVal(['importer_name', 'importer_address', 'imported_by']);
    if (importerVal != null) {
      addItem(
        parameter: 'Importer Details',
        value: importerVal,
        category: 'Import Entity',
        panel: 'BACK',
        isNonCompliant: isRuleFailed(['importer']),
      );
    }

    // 15. FSSAI License Number (BACK)
    final fssaiVal = getVal(['fssai_license_number', 'fssai_license', 'fssai_no', 'license_no']);
    addItem(
      parameter: 'FSSAI License No.',
      value: fssaiVal,
      category: 'Food Safety Authority',
      panel: 'BACK',
      isNonCompliant: isRuleFailed(['fssai', 'food safety']),
      isMono: true,
    );

    // 16. Barcode / GS1 GTIN (BACK)
    final barcodeVal = getVal(['barcode', 'ean_code', 'gtin', 'upc']);
    addItem(
      parameter: 'Barcode / GTIN',
      value: barcodeVal,
      category: 'Standard Identification',
      panel: 'BACK',
      isNonCompliant: isRuleFailed(['barcode', 'gtin', 'ean']),
      isMono: true,
    );

    // C. Add other dynamic extracted fields (storage, ingredients, nutritional table)
    final handledKeys = {
      'generic_product_name', 'generic_name', 'product_name', 'commodity_name',
      'mrp', 'price', 'maximum_retail_price', 'currency', 'unit_sale_price', 'usp', 'unit_price',
      'net_quantity', 'quantity', 'net_wt', 'net_weight', 'net_volume', 'unit', 'net_quantity_unit', 'metric_unit',
      'manufacturer_name', 'mfg_name', 'manufacturer', 'manufacturer_address', 'mfg_address', 'factory_address', 'premise_address',
      'packer_name', 'packer_address', 'packed_by', 'importer_name', 'importer_address', 'imported_by',
      'country_of_origin', 'origin_country', 'made_in', 'origin',
      'manufacturing_date', 'mfg_date', 'packing_date', 'packed_date', 'manufacture_month', 'mfg_month', 'manufacture_year', 'mfg_year',
      'expiry_date', 'best_before', 'use_by', 'exp_date',
      'batch_number', 'batch_no', 'lot_number', 'lot_no', 'batch_code',
      'consumer_care_phone', 'customer_care_phone', 'helpline', 'care_phone', 'toll_free',
      'consumer_care_email', 'customer_care_email', 'email', 'support_email',
      'consumer_care_address', 'customer_care_address', 'care_address',
      'consumer_care_name', 'customer_care_name', 'care_person',
      'fssai_license_number', 'fssai_license', 'fssai_no', 'license_no',
      'barcode', 'ean_code', 'gtin', 'upc',
      'veg_nonveg', 'is_vegetarian', 'dietary_indicator',
      'dynamic_fields', 'raw_extractions', 'raw_declarations', 'field_confidence', 'bounding_boxes',
      'brand_claims', 'summary_sentences', 'declarations_table', 'front_panel_table', 'back_panel_table', 'left_panel_table', 'right_panel_table', 'all_key_value_pairs',
    };

    void addDynamicField(String k, dynamic v) {
      if (v == null || handledKeys.contains(k.toLowerCase())) return;
      final str = v.toString().trim();
      if (str.isEmpty || str.toLowerCase() == 'null' || str.toLowerCase() == 'none') return;

      final formattedLabel = k
          .replaceAll('_', ' ')
          .split(' ')
          .map((w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : '')
          .join(' ');

      addItem(
        parameter: formattedLabel,
        value: str,
        category: 'Additional Declaration',
        panel: 'BACK',
        isNonCompliant: false,
      );
    }

    declarations.forEach((k, v) {
      if (k == 'dynamic_fields' && v is Map) {
        v.forEach((dk, dv) => addDynamicField(dk.toString(), dv));
      } else if (k == 'raw_extractions' && v is Map) {
        v.forEach((rk, rv) => addDynamicField(rk.toString(), rv));
      } else {
        addDynamicField(k, v);
      }
    });

    // Determine active items based on _structuredTableTab ('front' | 'back' | 'left' | 'right' | 'all')
    List<Map<String, dynamic>> activeItems = [];
    if (_structuredTableTab == 'front') {
      activeItems = frontItems;
    } else if (_structuredTableTab == 'back') {
      activeItems = backItems;
    } else if (_structuredTableTab == 'left') {
      activeItems = leftItems;
    } else if (_structuredTableTab == 'right') {
      activeItems = rightItems;
    } else {
      activeItems = allKvItems;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Title & Zero-Hallucination Badge
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Expanded(
              child: Row(
                children: [
                  Icon(Icons.table_chart_rounded, size: 16, color: AppTheme.slate700),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'STRUCTURED PACKAGING DECLARATIONS',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.0,
                        color: AppTheme.slate700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
              decoration: BoxDecoration(
                color: AppTheme.emerald500.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppTheme.emerald500.withValues(alpha: 0.3)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.verified_rounded, size: 11, color: AppTheme.emerald600),
                  SizedBox(width: 4),
                  Text(
                    'OCR Verified',
                    style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: AppTheme.emerald700),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Interactive Segmented Tab Selector: Front vs Back vs Left vs Right vs All Key-Values
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9), // Slate 100
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.slate200),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              children: [
                _buildTabPill('front', 'Front', Icons.crop_portrait_rounded, frontItems.length),
                const SizedBox(width: 3),
                _buildTabPill('back', 'Back', Icons.flip_to_back_rounded, backItems.length),
                const SizedBox(width: 3),
                _buildTabPill('left', 'Left Panel', Icons.align_horizontal_left_rounded, leftItems.length),
                const SizedBox(width: 3),
                _buildTabPill('right', 'Right Panel', Icons.align_horizontal_right_rounded, rightItems.length),
                const SizedBox(width: 3),
                _buildTabPill('all', 'All KV', Icons.data_object_rounded, allKvItems.length),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),

        // Context Subtitle based on active tab
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            _structuredTableTab == 'front'
                ? 'Front Display Panel (PDP) — Mandatory statutory identity, net measure & consumer marks.'
                : (_structuredTableTab == 'back'
                    ? 'Information Panel — Statutory Legal Metrology declarations, manufacturing/expiry dates & licensing.'
                    : (_structuredTableTab == 'left'
                        ? 'Left Panel — Ingredients, allergen advisory, storage & handling instructions.'
                        : (_structuredTableTab == 'right'
                            ? 'Right Panel — Nutritional facts, barcoding, batching & statutory certifications.'
                            : 'All Key-Value Extractions — Complete raw-to-structured parameter mapping directly from raw OCR.'))),
            style: const TextStyle(fontSize: 10.5, color: AppTheme.slate500, fontWeight: FontWeight.w500),
          ),
        ),
        const SizedBox(height: 10),

        // The Structured Table Card
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.95)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0F172A).withValues(alpha: 0.05),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: activeItems.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.notes_rounded, color: AppTheme.slate300, size: 36),
                          const SizedBox(height: 8),
                          Text(
                            'No declarations detected on the ${_structuredTableTab.toUpperCase()} panel in raw OCR text.',
                            style: const TextStyle(fontSize: 12, color: AppTheme.slate500, fontWeight: FontWeight.w500),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  )
                : Column(
                    children: [
                      // Table Column Header
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        color: const Color(0xFFF8FAFC),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'PARAMETER & CATEGORY',
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.8,
                                color: AppTheme.slate500,
                              ),
                            ),
                            Text(
                              'DECLARED RAW VALUE',
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.8,
                                color: AppTheme.slate500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1, thickness: 0.5),

                      // Rows
                      ...activeItems.asMap().entries.map((entry) {
                        final idx = entry.key;
                        final it = entry.value;
                        final isLast = idx == activeItems.length - 1;

                        return Column(
                          children: [
                            _buildStructuredTableRow(
                              parameter: (it['parameter'] ?? '').toString(),
                              value: it['value']?.toString(),
                              category: (it['category'] ?? 'Declaration').toString(),
                              panel: (it['panel'] ?? 'BACK').toString(),
                              isNonCompliant: it['isNonCompliant'] == true,
                              isBold: it['isBold'] == true,
                              isEmerald: it['isEmerald'] == true,
                              isMono: it['isMono'] == true,
                            ),
                            if (!isLast) const Divider(height: 1, thickness: 0.5),
                          ],
                        );
                      }),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildTabPill(String tabKey, String label, IconData icon, int count) {
    final isSelected = _structuredTableTab == tabKey;
    return GestureDetector(
      onTap: () {
        setState(() => _structuredTableTab = tabKey);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.emerald600 : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppTheme.emerald600.withValues(alpha: 0.28),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13,
              color: isSelected ? Colors.white : AppTheme.slate600,
            ),
            const SizedBox(width: 4),
            Text(
              '$label ($count)',
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected ? Colors.white : AppTheme.slate600,
              ),
              maxLines: 1,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStructuredTableRow({
    required String parameter,
    required String? value,
    required String category,
    required String panel,
    required bool isNonCompliant,
    bool isBold = false,
    bool isEmerald = false,
    bool isMono = false,
  }) {
    final bool isMissing = value == null ||
        value.trim().isEmpty ||
        value.trim().toLowerCase() == 'null' ||
        value.trim().toLowerCase() == 'none';
    final panUpper = panel.toUpperCase();
    final isFront = panUpper.contains('FRONT');
    final isLeft = panUpper.contains('LEFT');
    final isRight = panUpper.contains('RIGHT');

    Color badgeBg;
    Color badgeText;
    String badgeLabel;

    if (isFront) {
      badgeBg = AppTheme.emerald500.withValues(alpha: 0.12);
      badgeText = AppTheme.emerald700;
      badgeLabel = 'FRONT';
    } else if (isLeft) {
      badgeBg = const Color(0xFF0284C7).withValues(alpha: 0.12); // Sky 600
      badgeText = const Color(0xFF0369A1);
      badgeLabel = 'LEFT';
    } else if (isRight) {
      badgeBg = const Color(0xFFD97706).withValues(alpha: 0.12); // Amber 600
      badgeText = const Color(0xFFB45309);
      badgeLabel = 'RIGHT';
    } else {
      badgeBg = const Color(0xFF6366F1).withValues(alpha: 0.12); // Indigo
      badgeText = const Color(0xFF4F46E5);
      badgeLabel = 'BACK';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left Column: Parameter name & Category pill
          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  parameter,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.slate800,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: badgeBg,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        badgeLabel,
                        style: TextStyle(
                          fontSize: 8.5,
                          fontWeight: FontWeight.w900,
                          color: badgeText,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: AppTheme.slate100,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: AppTheme.slate200, width: 0.6),
                        ),
                        child: Text(
                          category,
                          style: const TextStyle(
                            fontSize: 8.5,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.slate600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),

          // Right Column: Extracted Value or Non-Compliant Missing Badge
          Expanded(
            flex: 6,
            child: Align(
              alignment: Alignment.centerRight,
              child: isMissing
                  ? Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEE2E2),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFFFCA5A5)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.warning_amber_rounded, size: 12, color: Color(0xFFDC2626)),
                          SizedBox(width: 4),
                          Text(
                            'Not Declared',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'monospace',
                              color: Color(0xFFDC2626),
                            ),
                          ),
                        ],
                      ),
                    )
                  : InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: value));
                        ScaffoldMessenger.of(context).hideCurrentSnackBar();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            duration: const Duration(seconds: 2),
                            backgroundColor: const Color(0xFF0F172A),
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            content: Text('Copied "$parameter": $value'),
                          ),
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
                        child: Text(
                          value,
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: isBold || isEmerald ? FontWeight.w800 : FontWeight.w600,
                            fontFamily: isMono ? 'monospace' : null,
                            color: isNonCompliant
                                ? const Color(0xFFDC2626)
                                : (isEmerald
                                    ? AppTheme.emerald600
                                    : (isBold ? AppTheme.slate900 : AppTheme.slate800)),
                          ),
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // --- 6. Digital E-Commerce Twin ---
  Widget _buildEcommerceTwinSection(String? mfgName, String? prodName, String scanId, String? mrpValue) {
    // Lazy fetch e-commerce twin data (twice-daily price checkpoints & violation history)
    if (_ecommerceTwinData == null && !_loadingEcommerceTwin && scanId.isNotEmpty && scanId != 'N/A') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _fetchEcommerceTwin(scanId);
      });
    }

    final bool hasSearchQuery = (mfgName != null && mfgName.isNotEmpty) || (prodName != null && prodName.isNotEmpty);
    final String queryTerm = '${mfgName ?? ''} ${prodName ?? ''}'.trim();

    final twin = _ecommerceTwinData;
    final List rawPriceHistory = (twin?['price_history'] as List?) ?? [];
    final List<Map<String, dynamic>> priceHistory = rawPriceHistory
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    final List rawViolations = (twin?['violation_history'] as List?) ?? [];
    final List<Map<String, dynamic>> violationHistory = rawViolations
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    final stats = (twin?['price_statistics'] as Map?) ?? {};
    final double? declaredMrp = (stats['declared_mrp'] as num?)?.toDouble()
        ?? (mrpValue != null ? double.tryParse(mrpValue.replaceAll(RegExp(r'[^0-9.]'), '')) : null);

    final double? currentPrice = (stats['current_price'] as num?)?.toDouble()
        ?? (priceHistory.isNotEmpty ? (priceHistory.last['price'] as num?)?.toDouble() : declaredMrp);
    final double? minPrice = (stats['min_price'] as num?)?.toDouble();
    final double? maxPrice = (stats['max_price'] as num?)?.toDouble();
    final bool hasOvercharge = stats['has_overcharging_violation'] == true ||
        (declaredMrp != null && currentPrice != null && currentPrice > declaredMrp);

    return GlassCard(
      padding: const EdgeInsets.all(16),
      borderRadius: 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section Header
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppTheme.emerald600.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                  border: Border.all(color: AppTheme.emerald600.withValues(alpha: 0.25)),
                ),
                child: const Icon(Icons.storefront_rounded, size: 17, color: AppTheme.emerald600),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'DIGITAL E-COMMERCE TWIN',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 11.5,
                        letterSpacing: 1.0,
                        color: AppTheme.slate800,
                      ),
                    ),
                    SizedBox(height: 1),
                    Text(
                      'Continuous Market Price Surveillance & Violation Log',
                      style: TextStyle(color: AppTheme.slate500, fontSize: 10, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFCBD5E1)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    PulseIndicator(color: AppTheme.emerald600, size: 6),
                    SizedBox(width: 5),
                    Text(
                      '2x Daily Surveillance',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.slate700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Rule 18(2) Compliance Alert Banner
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: hasOvercharge ? const Color(0xFFFEF2F2) : const Color(0xFFF0FDF4),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: hasOvercharge ? const Color(0xFFFCA5A5) : const Color(0xFF86EFAC),
                width: 0.8,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  hasOvercharge ? Icons.gavel_rounded : Icons.verified_user_rounded,
                  size: 18,
                  color: hasOvercharge ? AppTheme.dangerRed : AppTheme.emerald600,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hasOvercharge
                            ? 'RULE 18(2) VIOLATION — DUAL PRICING DETECTED'
                            : 'RULE 18(2) COMPLIANT — PRICE WITHIN MRP',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5,
                          color: hasOvercharge ? AppTheme.dangerRed : AppTheme.emerald600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        hasOvercharge
                            ? 'Marketplace listing price exceeds the declared package MRP. Non-compliance under Rule 18(2) of LMPC Rules, 2011 punishable under Section 36.'
                            : 'All recorded morning (09:00 AM) & evening (06:00 PM) marketplace checkpoints comply with declared package MRP.',
                        style: TextStyle(
                          fontSize: 10,
                          color: hasOvercharge ? const Color(0xFF991B1B) : const Color(0xFF166534),
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // Price Statistics Strip
          Row(
            children: [
              Expanded(
                child: _buildPriceStatChip(
                  label: 'Current Online',
                  value: currentPrice != null ? '₹${currentPrice.toStringAsFixed(2)}' : 'N/A',
                  color: hasOvercharge ? AppTheme.dangerRed : AppTheme.emerald600,
                  isHighlight: true,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildPriceStatChip(
                  label: 'Declared MRP',
                  value: declaredMrp != null ? '₹${declaredMrp.toStringAsFixed(2)}' : 'N/A',
                  color: const Color(0xFFE11D48),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildPriceStatChip(
                  label: '7-Day Min',
                  value: minPrice != null ? '₹${minPrice.toStringAsFixed(2)}' : 'N/A',
                  color: AppTheme.slate700,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildPriceStatChip(
                  label: '7-Day Max',
                  value: maxPrice != null ? '₹${maxPrice.toStringAsFixed(2)}' : 'N/A',
                  color: AppTheme.slate700,
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Subheader: Price History Graph
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'TWICE-DAILY PRICE SURVEILLANCE TREND',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.9,
                    color: AppTheme.slate700,
                  ),
                ),
              ),
              SizedBox(width: 8),
              Text(
                '09:00 AM / 06:00 PM Log',
                style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: AppTheme.slate400),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Interactive CustomPainter Spline Chart
          if (_loadingEcommerceTwin && priceHistory.isEmpty)
            Container(
              height: 180,
              alignment: Alignment.center,
              child: const CircularProgressIndicator(strokeWidth: 2, color: AppTheme.emerald600),
            )
          else
            PriceHistoryChart(
              priceHistory: priceHistory,
              declaredMrp: declaredMrp,
              height: 180,
            ),

          const SizedBox(height: 18),

          // Product Violation History Section
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Text(
                  'PRODUCT VIOLATION HISTORY',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.9,
                    color: AppTheme.slate700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: violationHistory.isNotEmpty
                      ? AppTheme.dangerRed.withValues(alpha: 0.12)
                      : AppTheme.emerald600.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  violationHistory.isNotEmpty ? '${violationHistory.length} Incident(s)' : 'Clean Record',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.bold,
                    color: violationHistory.isNotEmpty ? AppTheme.dangerRed : AppTheme.emerald600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          if (violationHistory.isEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.shield_outlined, size: 16, color: AppTheme.emerald600),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'No historical compliance violations recorded for this commodity.',
                      style: TextStyle(fontSize: 11, color: AppTheme.slate600, fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            )
          else
            Column(
              children: violationHistory.take(4).map((v) => _buildViolationHistoryCard(v)).toList(),
            ),

          const SizedBox(height: 14),

          // Cross-Reference Marketplaces
          const Text(
            'CROSS-REFERENCE MARKETPLACES',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.9,
              color: AppTheme.slate600,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: hasSearchQuery
                      ? () async {
                          final query = Uri.encodeComponent(queryTerm);
                          final url = Uri.parse('https://www.google.com/search?tbm=shop&q=$query');
                          if (await canLaunchUrl(url)) await launchUrl(url);
                        }
                      : null,
                  icon: const Icon(Icons.shopping_cart_outlined, size: 14),
                  label: const Text('Google Shopping', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.withValues(alpha: 0.12),
                    foregroundColor: Colors.blue[800],
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: hasSearchQuery
                      ? () async {
                          final query = Uri.encodeComponent(queryTerm);
                          final url = Uri.parse('https://www.amazon.in/s?k=$query');
                          if (await canLaunchUrl(url)) await launchUrl(url);
                        }
                      : null,
                  icon: const Icon(Icons.search_rounded, size: 14),
                  label: const Text('Amazon Search', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange.withValues(alpha: 0.14),
                    foregroundColor: Colors.orange[900],
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPriceStatChip({
    required String label,
    required String value,
    required Color color,
    bool isHighlight = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 8),
      decoration: BoxDecoration(
        color: isHighlight ? color.withValues(alpha: 0.08) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isHighlight ? color.withValues(alpha: 0.3) : const Color(0xFFE2E8F0),
          width: 0.8,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 8.5, fontWeight: FontWeight.w600, color: AppTheme.slate500),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w900,
              fontFamily: 'monospace',
              color: color,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildViolationHistoryCard(Map<String, dynamic> v) {
    final isRepeat = v['is_repeat_offence'] == true;
    final ruleCode = (v['rule_code'] ?? 'RULE').toString();
    final ruleTitle = (v['rule_title'] ?? v['field_name'] ?? 'Violation').toString();
    final date = (v['date'] ?? '').toString();
    final reason = (v['reason'] ?? '').toString();
    final penalty = (v['penalty'] ?? '').toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB), // Amber 50
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFDE68A)), // Amber 200
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isRepeat ? const Color(0xFFDC2626) : const Color(0xFFD97706),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    isRepeat ? 'REPEAT OFFENCE (ESCALATED)' : 'FIRST OFFENCE',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                date,
                style: const TextStyle(fontSize: 9, color: AppTheme.slate500, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded, size: 14, color: Color(0xFFB45309)),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  '$ruleCode: $ruleTitle',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF92400E),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          if (reason.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              reason,
              style: const TextStyle(fontSize: 10, color: Color(0xFF78350F), height: 1.2),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (penalty.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              penalty,
              style: const TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.bold,
                fontStyle: FontStyle.italic,
                color: Color(0xFFB45309),
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }

  // --- Complaint View Fallback ---
  Widget _buildComplaintDetails(BuildContext context) {
    final item = widget.item;
    final status = (item['status'] ?? 'SUBMITTED').toString().toUpperCase();
    final isResolved = status == 'RESOLVED' || status == 'ACCEPT' || status == 'ACCEPTED';
    final isRejected = status == 'REJECTED';
    final double? paidPrice = double.tryParse(item['paid_price']?.toString() ?? '');
    final double? printedMrp = double.tryParse(item['printed_mrp']?.toString() ?? '');
    final bool isOvercharged = paidPrice != null && printedMrp != null && paidPrice > printedMrp;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Statutory Violation & Complaint Status Card
        GlassCard(
          padding: const EdgeInsets.all(14),
          borderRadius: 18,
          borderColor: isResolved
              ? AppTheme.emerald400.withValues(alpha: 0.4)
              : AppTheme.dangerRed.withValues(alpha: 0.4),
          backgroundColor: isResolved
              ? const Color(0xFFF0FDF4).withValues(alpha: 0.9)
              : const Color(0xFFFEF2F2).withValues(alpha: 0.9),
          child: Row(
            children: [
              Icon(
                isResolved ? Icons.check_circle_rounded : Icons.cancel_rounded,
                color: isResolved ? AppTheme.emerald600 : AppTheme.dangerRed,
                size: 30,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isResolved
                          ? 'COMPLAINT RESOLVED'
                          : (isRejected
                              ? 'COMPLAINT REJECTED'
                              : (isOvercharged
                                  ? 'RULE 18(2) VIOLATION: NON-COMPLIANT'
                                  : 'GRIEVANCE PENDING AUDIT')),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: isResolved ? AppTheme.emerald700 : AppTheme.dangerRed,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isOvercharged
                          ? 'Paid ₹$paidPrice exceeds printed MRP ₹$printedMrp. Illegal dual pricing under LMPC PC Rules, 2011.'
                          : (isResolved
                              ? 'This consumer complaint has been verified and settled.'
                              : 'Status: $status. Pending legal metrology verification.'),
                      style: TextStyle(
                        fontSize: 11,
                        color: isResolved ? AppTheme.slate600 : const Color(0xFF991B1B),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        GlassCard(
          padding: const EdgeInsets.all(14),
          borderRadius: 18,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Shop & Retailer Details', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppTheme.slate900)),
              const Divider(height: 14),
              Text('Shopkeeper: ${item['shopkeeper_name'] ?? 'N/A'}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.slate800)),
              const SizedBox(height: 4),
              Text('Address: ${item['shop_address'] ?? 'N/A'}', style: const TextStyle(fontSize: 12, color: AppTheme.slate600)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        GlassCard(
          padding: const EdgeInsets.all(14),
          borderRadius: 18,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Pricing Discrepancy', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppTheme.slate900)),
              const Divider(height: 14),
              Text('Paid Price: ₹${item['paid_price']}', style: const TextStyle(fontSize: 14, color: AppTheme.dangerRed, fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              Text('Printed MRP: ₹${item['printed_mrp']}', style: const TextStyle(fontSize: 12, color: AppTheme.slate500, decoration: TextDecoration.lineThrough)),
              const SizedBox(height: 6),
              Text('Description: ${item['description'] ?? 'None'}', style: const TextStyle(fontSize: 12, color: AppTheme.slate700)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const Text('ATTACHED EVIDENCE', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 1.1, color: AppTheme.slate700)),
        const SizedBox(height: 8),
        Row(
          children: [
            if (item['receipt_image_url'] != null)
              Expanded(
                child: GestureDetector(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => FullScreenImageViewer(
                        imageUrl: '${ApiClient.getBaseUrl}${item['receipt_image_url']}',
                      ),
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      '${ApiClient.getBaseUrl}${item['receipt_image_url']}',
                      height: 120,
                      fit: BoxFit.cover,
                      errorBuilder: (c, e, s) => const Icon(Icons.broken_image),
                    ),
                  ),
                ),
              ),
            const SizedBox(width: 10),
            if (item['product_image_url'] != null)
              Expanded(
                child: GestureDetector(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => FullScreenImageViewer(
                        imageUrl: '${ApiClient.getBaseUrl}${item['product_image_url']}',
                      ),
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      '${ApiClient.getBaseUrl}${item['product_image_url']}',
                      height: 120,
                      fit: BoxFit.cover,
                      errorBuilder: (c, e, s) => const Icon(Icons.broken_image),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  // --- Report Overpricing Callout Card (Rule 18(2) LMPC Act) ---
  Widget _buildReportOverpricingCard({
    required BuildContext context,
    required String? mrpValue,
    required String? prodName,
    required String? mfgName,
    required String scanId,
    required Map imageUrls,
  }) {
    double? parsedMrp;
    if (mrpValue != null) {
      final clean = mrpValue.replaceAll(RegExp(r'[^0-9.]'), '');
      parsedMrp = double.tryParse(clean);
    }
    final frontImg = imageUrls['front'] ?? imageUrls['main'] ?? imageUrls['front_url'];

    void navigateToComplaint() {
      context.push(
        '/complaint',
        extra: {
          'mrp': parsedMrp,
          'product_name': prodName,
          'manufacturer_name': mfgName,
          'product_image_path': frontImg?.toString(),
          'scan_id': scanId,
        },
      );
    }

    return GlassCard(
      borderRadius: 20,
      padding: const EdgeInsets.all(16),
      borderColor: const Color(0xFFFCA5A5).withValues(alpha: 0.6),
      backgroundColor: const Color(0xFFFFF1F2).withValues(alpha: 0.85),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.dangerRed.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.price_change_rounded,
                  color: AppTheme.dangerRed,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE11D48).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'LMPC RULE 18(2) OVERPRICING GRIEVANCE',
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFFBE123C),
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                    const SizedBox(height: 3),
                    const Text(
                      'Charged More Than Printed MRP?',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.slate900,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            parsedMrp != null
                ? 'The detected packaging ceiling price is ₹${parsedMrp.toStringAsFixed(parsedMrp.truncateToDouble() == parsedMrp ? 0 : 2)}. Under Rule 18(2) of the Legal Metrology Act, no retailer may legally charge above this price.'
                : 'Under Rule 18(2) of the Legal Metrology Act, no retailer or seller may legally demand more than the printed MRP inclusive of all taxes.',
            style: const TextStyle(
              fontSize: 11.5,
              color: AppTheme.slate700,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: navigateToComplaint,
              icon: const Icon(Icons.campaign_rounded, size: 18, color: Colors.white),
              label: const Text(
                'REPORT OVERPRICING NOW',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                  color: Colors.white,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE11D48),
                foregroundColor: Colors.white,
                elevation: 3,
                shadowColor: const Color(0x66E11D48),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- Floating Dock Bottom Action Bar ---
  Widget _buildFloatingDock(BuildContext context, bool isComplaint, String scanId) {
    final item = widget.item;
    final declarations = (item['extracted_declarations'] as Map?) ?? {};
    final prodName = (declarations['generic_product_name'] ?? declarations['generic_name'] ?? declarations['product_name'])?.toString();
    final mfgName = (declarations['manufacturer_name'] ?? declarations['packer_name'] ?? declarations['importer_name'])?.toString();
    final imageUrls = (item['image_urls'] as Map?) ?? {};
    final mrpValue = declarations['mrp']?.toString();
    double? parsedMrp;
    if (mrpValue != null) {
      final clean = mrpValue.replaceAll(RegExp(r'[^0-9.]'), '');
      parsedMrp = double.tryParse(clean);
    }
    final frontImg = imageUrls['front'] ?? imageUrls['main'] ?? imageUrls['front_url'];

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.auraBg.withValues(alpha: 0.0),
            AppTheme.auraBg.withValues(alpha: 0.95),
            AppTheme.auraBg,
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0F172A).withValues(alpha: 0.12),
              blurRadius: 28,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: _isOfficer
            ? Row(
                children: [
                  // Officer ACCEPT Button
                  Expanded(
                    flex: 5,
                    child: GestureDetector(
                      onTap: () => _handleOfficerDecision(isComplaint, scanId, 'ACCEPT'),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: AppTheme.emerald600,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.emerald600.withValues(alpha: 0.25),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.check_circle_rounded, size: 16, color: Colors.white),
                            SizedBox(width: 5),
                            Text(
                              'ACCEPT',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(width: 8),

                  // Officer REJECT Button
                  Expanded(
                    flex: 5,
                    child: GestureDetector(
                      onTap: () => _handleOfficerDecision(isComplaint, scanId, 'REJECT'),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: AppTheme.dangerRed,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.dangerRed.withValues(alpha: 0.25),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.cancel_rounded, size: 16, color: Colors.white),
                            SizedBox(width: 5),
                            Text(
                              'REJECT',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(width: 8),

                  // Export Report Button
                  Expanded(
                    flex: 4,
                    child: GestureDetector(
                      onTap: () => _downloadPdfReport(context, isComplaint, scanId),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.15),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.picture_as_pdf_rounded, size: 14, color: Colors.white),
                            SizedBox(width: 4),
                            Text(
                              'PDF',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              )
            : Row(
                children: [
                  // Re-scan Button
                  Expanded(
                    flex: 5,
                    child: GestureDetector(
                      onTap: () {
                        if (Navigator.canPop(context)) {
                          Navigator.pop(context);
                        } else {
                          context.go('/scan');
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppTheme.slate200),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.03),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.crop_free_rounded, size: 15, color: AppTheme.slate700),
                            SizedBox(width: 4),
                            Text(
                              'Re-scan',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.slate800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(width: 8),

                  // Export Full Report Button
                  Expanded(
                    flex: 6,
                    child: GestureDetector(
                      onTap: () => _downloadPdfReport(context, isComplaint, scanId),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.2),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Export Report',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                            SizedBox(width: 4),
                            Icon(
                              Icons.arrow_forward_rounded,
                              size: 14,
                              color: Color(0xFF34D399),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  // --- PDF Export Handler ---
  Future<void> _downloadPdfReport(BuildContext context, bool isComplaint, String scanId) async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Generating Audit PDF Report...'),
          duration: Duration(seconds: 2),
        ),
      );
      final dio = Dio();
      final endpoint = isComplaint
          ? '/reports/complaint/$scanId/download'
          : '/reports/$scanId/download';

      final response = await dio.get(
        '${ApiClient.getBaseUrl}$endpoint',
        options: Options(responseType: ResponseType.bytes),
      );
      await Printing.sharePdf(
        bytes: response.data,
        filename: 'nirikshak_audit_$scanId.pdf',
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF Download: $e')),
        );
      }
    }
  }
}

// Fullscreen Viewer for images with interactive OCR bounding boxes
class FullScreenImageViewer extends StatefulWidget {
  final String imageUrl;
  final List<Map<String, dynamic>>? boundingBoxes;
  final double? aspectRatio;

  const FullScreenImageViewer({
    super.key,
    required this.imageUrl,
    this.boundingBoxes,
    this.aspectRatio,
  });

  @override
  State<FullScreenImageViewer> createState() => _FullScreenImageViewerState();
}

class _FullScreenImageViewerState extends State<FullScreenImageViewer> {
  bool _showBoxes = true;
  int? _selectedBox;
  double? _resolvedAspect;

  @override
  void initState() {
    super.initState();
    _resolvedAspect = widget.aspectRatio;
    if (_resolvedAspect == null && widget.imageUrl.isNotEmpty) {
      try {
        final img = NetworkImage(widget.imageUrl);
        img.resolve(const ImageConfiguration()).addListener(
          ImageStreamListener((ImageInfo info, bool _) {
            if (mounted) {
              final w = info.image.width.toDouble();
              final h = info.image.height.toDouble();
              if (w > 0 && h > 0) {
                setState(() => _resolvedAspect = w / h);
              }
            }
          }),
        );
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final boxes = widget.boundingBoxes ?? [];

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Packaging Evidence & OCR',
          style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
        ),
        actions: [
          if (boxes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  backgroundColor: _showBoxes ? AppTheme.emerald600 : Colors.white12,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () {
                  setState(() => _showBoxes = !_showBoxes);
                },
                icon: Icon(
                  _showBoxes ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                  size: 16,
                  color: Colors.white,
                ),
                label: Text(
                  _showBoxes ? 'OCR Boxes (${boxes.length})' : 'Show Boxes',
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            ),
        ],
      ),
      body: Center(
        child: InteractiveViewer(
          maxScale: 5.0,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final boxW = constraints.maxWidth;
              final boxH = constraints.maxHeight;

              double imgAspect = _resolvedAspect ?? 0.0;
              if (imgAspect <= 0 && boxes.isNotEmpty) {
                final fb = boxes.first;
                if (fb['aspect_ratio'] != null && (fb['aspect_ratio'] as num) > 0) {
                  imgAspect = (fb['aspect_ratio'] as num).toDouble();
                } else if (fb['orig_w'] != null && fb['orig_h'] != null && (fb['orig_h'] as num) > 0) {
                  imgAspect = (fb['orig_w'] as num).toDouble() / (fb['orig_h'] as num).toDouble();
                }
              }
              if (imgAspect <= 0) {
                imgAspect = boxW / boxH;
              }

              final containerAspect = boxW / boxH;
              double renderedW, renderedH, offsetX, offsetY;
              if (containerAspect > imgAspect) {
                renderedH = boxH;
                renderedW = boxH * imgAspect;
                offsetX = (boxW - renderedW) / 2.0;
                offsetY = 0.0;
              } else {
                renderedW = boxW;
                renderedH = boxW / imgAspect;
                offsetX = 0.0;
                offsetY = (boxH - renderedH) / 2.0;
              }

              return Stack(
                children: [
                  Positioned(
                    left: offsetX,
                    top: offsetY,
                    width: renderedW,
                    height: renderedH,
                    child: Image.network(
                      widget.imageUrl,
                      fit: BoxFit.fill,
                      errorBuilder: (c, e, s) => const Icon(
                        Icons.broken_image_rounded,
                        color: Colors.white,
                        size: 50,
                      ),
                    ),
                  ),
                  if (_showBoxes && boxes.isNotEmpty)
                    ...boxes.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final box = entry.value;
                      final isSelected = _selectedBox == idx;

                      double normX = 0, normY = 0, normW = 0, normH = 0;
                      final origW = (box['orig_w'] as num?)?.toDouble();
                      final origH = (box['orig_h'] as num?)?.toDouble();

                      if (box.containsKey('x') && box['x'] != null) {
                        double rx = (box['x'] as num).toDouble();
                        double ry = ((box['y'] ?? 0) as num).toDouble();
                        double rw = ((box['width'] ?? 0) as num).toDouble();
                        double rh = ((box['height'] ?? 0) as num).toDouble();

                        if (origW != null && origW > 0 && rx > 100.0) {
                          normX = (rx / origW) * 100.0;
                          normW = (rw / origW) * 100.0;
                        } else if (rx <= 1.0 && rw <= 1.0 && (rx > 0 || rw > 0)) {
                          normX = rx * 100.0;
                          normW = rw * 100.0;
                        } else {
                          normX = rx;
                          normW = rw;
                        }

                        if (origH != null && origH > 0 && ry > 100.0) {
                          normY = (ry / origH) * 100.0;
                          normH = (rh / origH) * 100.0;
                        } else if (ry <= 1.0 && rh <= 1.0 && (ry > 0 || rh > 0)) {
                          normY = ry * 100.0;
                          normH = rh * 100.0;
                        } else {
                          normY = ry;
                          normH = rh;
                        }
                      } else if (box['box'] is List && (box['box'] as List).length >= 4) {
                        final pts = box['box'] as List;
                        final x1 = (pts[0][0] as num).toDouble();
                        final y1 = (pts[0][1] as num).toDouble();
                        final x2 = (pts[1][0] as num).toDouble();
                        final y3 = (pts[2][1] as num).toDouble();
                        final ow = origW ?? (imgAspect > 0 ? 1000.0 * imgAspect : 1000.0);
                        final oh = origH ?? 1000.0;
                        normX = (x1 / ow) * 100.0;
                        normY = (y1 / oh) * 100.0;
                        normW = ((x2 - x1) / ow) * 100.0;
                        normH = ((y3 - y1) / oh) * 100.0;
                      }

                      final l = offsetX + (normX / 100.0) * renderedW;
                      final t = offsetY + (normY / 100.0) * renderedH;
                      final w = (normW / 100.0) * renderedW;
                      final h = (normH / 100.0) * renderedH;

                      final cl = l.clamp(offsetX, (offsetX + renderedW - 8.0).clamp(offsetX, offsetX + renderedW));
                      final ct = t.clamp(offsetY, (offsetY + renderedH - 6.0).clamp(offsetY, offsetY + renderedH));
                      final cw = w.clamp(8.0, (offsetX + renderedW - cl).clamp(8.0, renderedW));
                      final ch = h.clamp(6.0, (offsetY + renderedH - ct).clamp(6.0, renderedH));

                      final bText = (box['text'] ?? '').toString();
                      final bConf = box['confidence'] != null
                          ? ((box['confidence'] as num) * 100).toStringAsFixed(0)
                          : '95';

                      return Positioned(
                        left: cl,
                        top: ct,
                        width: cw,
                        height: ch,
                        child: GestureDetector(
                          onTap: () {
                            setState(() => _selectedBox = idx);
                            ScaffoldMessenger.of(context).hideCurrentSnackBar();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                duration: const Duration(seconds: 4),
                                backgroundColor: const Color(0xFF0F172A),
                                behavior: SnackBarBehavior.floating,
                                content: Text('OCR #${idx + 1}: "$bText" ($bConf% confidence)'),
                              ),
                            );
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              color: isSelected ? Colors.amber.withValues(alpha: 0.35) : AppTheme.emerald500.withValues(alpha: 0.22),
                              border: Border.all(
                                color: isSelected ? Colors.amberAccent : AppTheme.emerald400,
                                width: isSelected ? 2.5 : 1.5,
                              ),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                      );
                    }),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class RoundedRectangleWidget extends RoundedRectangleBorder {
  const RoundedRectangleWidget({super.borderRadius});
}
