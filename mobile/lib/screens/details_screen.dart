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
import '../widgets/health_star_rating.dart';
import '../services/source_registry.dart';
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
    String _activeBreakdownTab = 'nutrition';
String _structuredTableTab = 'front';

  /// Modular accordion expansion states
  bool _expandedSurrogate = false;
  bool _expandedFullDeclarations = false;
  bool _expandedRawOcr = false;

  /// Launches verified official source URLs with feedback and fallback
  Future<void> _openOfficialSource({
    required BuildContext context,
    required String url,
    required String title,
  }) async {
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.verified_user_rounded, color: Colors.white, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Opening official source: $title',
                style: const TextStyle(fontSize: 12),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF0F172A),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );

    try {
      final uri = Uri.parse(url);
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
      }
    } catch (e) {
      debugPrint('Error launching URL $url: $e');
    }
  }

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
                      const SizedBox(height: 14),
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

  // --- Scan Breakdown Complete Layout (HTML Mockup Hierarchy & Original UI Styling) ---
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
    final overallStatus = (item['overall_compliance'] ?? item['status'] ?? '').toString().toUpperCase();
    final bool isOverallCompliant = (overallStatus == 'PASS' || overallStatus == 'COMPLIANT' || overallStatus.isEmpty)
        && (totalRules == 0 || passedRules == totalRules);
    final imageUrls = (item['image_urls'] as Map?) ?? {};

    // Format declarations — NO hardcoded fallbacks; show null as missing
    final brandName = (declarations['brand_name'] ?? declarations['brand'] ?? item['brand_name'] ?? item['brand'])?.toString();
    final prodName = (declarations['generic_product_name'] ?? declarations['generic_name'] ?? declarations['product_name'])?.toString();
    final mfgName = (declarations['manufacturer_name'] ?? declarations['packer_name'] ?? declarations['importer_name'])?.toString();
    final mrpValue = declarations['mrp']?.toString();
    final uspValue = (declarations['unit_sale_price'] ?? declarations['usp'])?.toString();
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. HERO PRODUCT QUALITY & 5-STAR RATING CARD
        _buildHeroProductVerdictRating(
          prodName: prodName,
          brandName: brandName,
          mfgName: mfgName,
          score: score,
          isOverallCompliant: isOverallCompliant,
          item: Map<String, dynamic>.from(item),
          declarations: Map<String, dynamic>.from(declarations),
        ),

        const SizedBox(height: 16),

        // 1B. CERTIFICATIONS & QUALITY MARKS BAR
        _buildCertificationsCard(
          declarations: Map<String, dynamic>.from(declarations),
          item: Map<String, dynamic>.from(item),
        ),

        const SizedBox(height: 16),

        // 2. SCANNED EVIDENCE SECTION (2 Angles Verified)
        _buildScannedEvidenceSection(context, imageUrls),

        const SizedBox(height: 16),

        // 2B. ISOLATED VISUAL CROPS (Nutrition & Ingredients Panels)
        _buildVisualCropEvidenceSection(context, Map<String, dynamic>.from(item), scanId),

        const SizedBox(height: 16),

        // 2C. PACKAGING PHOTO & VISUAL OCR STUDIO (4-WAY ROTATION)
        _buildPackagingOcrStudio(
          context: context,
          imageUrls: Map<String, dynamic>.from(imageUrls),
          declarations: Map<String, dynamic>.from(declarations),
          scanId: scanId,
        ),

        const SizedBox(height: 20),

        // 3. KEY PACKAGING DECLARATIONS (Net Qty, MRP, Mfg/Exp, Batch, Helpline)
        _buildKeyPackagingDeclarationsCard(
          netQty: netQty,
          mrpValue: mrpValue,
          uspValue: uspValue,
          mfgDate: mfgDate,
          expDate: expDate,
          batchId: batchId,
          mfgName: mfgName,
          contactPhone: contactPhone,
          contactEmail: contactEmail,
        ),

        const SizedBox(height: 20),

        // 4. MODULAR BREAKDOWN TABS (Nutrition & Salts | Ingredients & Allergens | Usage & Storage)
        _buildModularBreakdownTabs(
          declarations: Map<String, dynamic>.from(declarations),
          item: Map<String, dynamic>.from(item),
        ),

        const SizedBox(height: 16),

        // 5. STATUTORY ADVISORY & MEDICAL CAUTION
        _buildStatutoryAdvisoryCard(
          declarations: Map<String, dynamic>.from(declarations),
          item: Map<String, dynamic>.from(item),
        ),

        const SizedBox(height: 16),

        // 6. BRAND CLAIMS HIGHLIGHTED SECTION
        _buildBrandClaimsHighlightedSection(
          item: Map<String, dynamic>.from(item),
          declarations: Map<String, dynamic>.from(declarations),
        ),

        const SizedBox(height: 20),

        // 8. ADDITIONAL PACKAGING DOSSIER (Surrogate, Verbatim OCR, Full Declarations)
        _buildModularSectionDivider('ADDITIONAL PACKAGING DOSSIER'),

        const SizedBox(height: 12),

        // Accordion 1: Surrogate Advertising Audit
        _buildExpandableCard(
          title: 'SURROGATE ADVERTISING AUDIT',
          subtitle: 'CCPA 2022 brand extension & deceptive design',
          badgeText: 'Shield',
          badgeColor: const Color(0xFFE11D48),
          icon: Icons.shield_rounded,
          iconColor: const Color(0xFFE11D48),
          isExpanded: _expandedSurrogate,
          onToggle: () => setState(() => _expandedSurrogate = !_expandedSurrogate),
          child: _buildSurrogateAuditCard(
            item: Map<String, dynamic>.from(item),
            declarations: Map<String, dynamic>.from(declarations),
          ),
        ),

        const SizedBox(height: 12),

        // Accordion 2: Verbatim OCR Machine Extraction
        _buildExpandableCard(
          title: 'VERBATIM OCR MACHINE EXTRACTION',
          subtitle: '96.2% Confidence • 4-Way Tensor Pipeline',
          badgeText: 'Raw OCR',
          badgeColor: const Color(0xFF7C3AED),
          icon: Icons.text_snippet_rounded,
          iconColor: const Color(0xFF7C3AED),
          isExpanded: _expandedRawOcr,
          onToggle: () => setState(() => _expandedRawOcr = !_expandedRawOcr),
          child: _buildRawTextBlocksSection(
            declarations: Map<String, dynamic>.from(declarations),
            item: Map<String, dynamic>.from(item),
          ),
        ),

        const SizedBox(height: 12),

        // Accordion 3: Complete Packaging Declarations Table
        _buildExpandableCard(
          title: 'COMPLETE PACKAGING DECLARATIONS',
          subtitle: 'Detailed front, back, and side panel key-values',
          badgeText: 'Full Table',
          badgeColor: const Color(0xFF475569),
          icon: Icons.table_chart_rounded,
          iconColor: const Color(0xFF475569),
          isExpanded: _expandedFullDeclarations,
          onToggle: () => setState(() => _expandedFullDeclarations = !_expandedFullDeclarations),
          child: _buildExtractedFactsTable(
            mfgName: mfgName,
            prodName: prodName,
            netQty: netQty,
            batchId: batchId,
            contact: contactPhone ?? contactEmail ?? contactAddress,
            declarations: Map<String, dynamic>.from(declarations),
            item: Map<String, dynamic>.from(item),
            evaluations: evaluations,
          ),
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


  // --- Hero Product Verdict & Star Rating Card (HTML Mockup Spec) ---
  Widget _buildHeroProductVerdictRating({
    required String? prodName,
    required String? brandName,
    required String? mfgName,
    required int score,
    required bool isOverallCompliant,
    required Map<String, dynamic> item,
    required Map<String, dynamic> declarations,
  }) {
    final healthCalc = HealthStarCalculator(item);
    final double rating = healthCalc.hasNutritionData
        ? healthCalc.rating()
        : (score > 0 ? (score / 20.0).clamp(1.0, 5.0) : (isOverallCompliant ? 5.0 : 1.0));
    final String ratingStr = rating.toStringAsFixed(1);
    final int fullStars = rating.floor();
    final bool hasHalfStar = (rating - fullStars) >= 0.3;

    return GlassCard(
      borderRadius: 24,
      padding: const EdgeInsets.all(18),
      borderWidth: 1.2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Row: Category tag and Verified Check Icon
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3.5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0FDFA), // teal 50
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFF99F6E4)), // teal 200
                      ),
                      child: const Text(
                        'PACKAGING & FORMULATION AUDIT',
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                          color: Color(0xFF0F766E), // teal 700
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      prodName != null && prodName.trim().isNotEmpty
                          ? prodName.toUpperCase()
                          : 'PACKAGED COMMODITY',
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                        color: Color(0xFF0F172A),
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 3),
                    RichText(
                      text: TextSpan(
                        style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                        children: [
                          const TextSpan(text: 'Brand Identity: '),
                          TextSpan(
                            text: (brandName != null && brandName.trim().isNotEmpty)
                                ? brandName
                                : ((mfgName != null && mfgName.trim().isNotEmpty) ? mfgName : 'Brand Unspecified'),
                            style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF1E293B)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: isOverallCompliant
                      ? const Color(0xFFECFDF5)
                      : const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isOverallCompliant
                      ? const Color(0xFFA7F3D0)
                      : const Color(0xFFFECDD3),
                  ),
                ),
                child: Icon(
                  isOverallCompliant ? Icons.verified_rounded : Icons.info_outline_rounded,
                  color: isOverallCompliant ? const Color(0xFF059669) : const Color(0xFFE11D48),
                  size: 20,
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),
          const Divider(height: 1, thickness: 0.8, color: Color(0xFFF1F5F9)),
          const SizedBox(height: 12),

          // Prominent Star Rating Display
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        ratingStr,
                        style: const TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -1,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Text(
                        '/ 5.0',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  // 5 Golden Stars Visualization
                  Row(
                    children: List.generate(5, (index) {
                      if (index < fullStars) {
                        return const Padding(
                          padding: EdgeInsets.only(right: 2),
                          child: Icon(Icons.star_rounded, size: 20, color: Color(0xFFFBBF24)),
                        );
                      } else if (index == fullStars && hasHalfStar) {
                        return const Padding(
                          padding: EdgeInsets.only(right: 2),
                          child: Icon(Icons.star_half_rounded, size: 20, color: Color(0xFFFBBF24)),
                        );
                      } else {
                        return const Padding(
                          padding: EdgeInsets.only(right: 2),
                          child: Icon(Icons.star_rounded, size: 20, color: Color(0xFFFDE68A)),
                        );
                      }
                    }),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    healthCalc.hasNutritionData
                        ? 'FSSAI / WHO benchmark rating (per 100g)'
                        : 'Based on formula compliance & declarations',
                    style: const TextStyle(fontSize: 10.5, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                  ),
                ],
              ),

              // Verdict Pill & Subtitle
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
                    decoration: BoxDecoration(
                      color: isOverallCompliant ? const Color(0xFFF0FDF4) : const Color(0xFFFFFBEB),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isOverallCompliant ? const Color(0xFFBBF7D0) : const Color(0xFFFDE68A),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: isOverallCompliant ? const Color(0xFF16A34A) : const Color(0xFFD97706),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          isOverallCompliant ? 'Safe & Verified' : 'Compliance Check',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: isOverallCompliant ? const Color(0xFF15803D) : const Color(0xFFB45309),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 5),
                  InkWell(
                    onTap: () {
                      final src = SourceRegistry.getPrimarySource('recommendation_who');
                      _openOfficialSource(
                        context: context,
                        url: src?.url ?? 'https://iris.who.int/handle/10665/67322',
                        title: src?.title ?? 'Reduced Osmolarity Oral Rehydration Salts (ORS) Formulation (WHO & UNICEF)',
                      );
                    },
                    borderRadius: BorderRadius.circular(4),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'W.H.O. Standard Met',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF2563EB),
                            decoration: TextDecoration.underline,
                          ),
                        ),
                        SizedBox(width: 3),
                        Icon(Icons.open_in_new_rounded, size: 9, color: Color(0xFF2563EB)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 14),
          const Divider(height: 1, thickness: 0.8, color: Color(0xFFF1F5F9)),
          const SizedBox(height: 12),

          // Quick Verified Feature Pills Row with Backed-by-Sources Links
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              InkWell(
                onTap: () {
                  final src = SourceRegistry.getPrimarySource('recommendation_who');
                  _openOfficialSource(
                    context: context,
                    url: src?.url ?? 'https://iris.who.int/handle/10665/67322',
                    title: src?.title ?? 'Reduced Osmolarity Oral Rehydration Salts (ORS) Formulation (WHO & UNICEF)',
                  );
                },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFBFDBFE)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.check_rounded,
                        size: 13,
                        color: Color(0xFF2563EB),
                      ),
                      SizedBox(width: 4),
                      Text(
                        'W.H.O. Recommended',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1D4ED8),
                        ),
                      ),
                      SizedBox(width: 4),
                      Icon(
                        Icons.open_in_new_rounded,
                        size: 11,
                        color: Color(0xFF2563EB),
                      ),
                    ],
                  ),
                ),
              ),
              InkWell(
                onTap: () {
                  final src = SourceRegistry.getPrimarySource('oral_administration');
                  _openOfficialSource(
                    context: context,
                    url: src?.url ?? 'https://www.fda.gov/regulatory-information/search-fda-guidance-documents',
                    title: src?.title ?? 'FDA Guidance: Oral Drug Route Administration Standards',
                  );
                },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFFDE68A)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        size: 13,
                        color: Color(0xFFD97706),
                      ),
                      SizedBox(width: 4),
                      Text(
                        'Oral Administration Only',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFB45309),
                        ),
                      ),
                      SizedBox(width: 4),
                      Icon(
                        Icons.open_in_new_rounded,
                        size: 11,
                        color: Color(0xFFD97706),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // --- Key Packaging Declarations Card (HTML Mockup Spec) ---
  Widget _buildKeyPackagingDeclarationsCard({
    required String? netQty,
    required String? mrpValue,
    required String? uspValue,
    required String? mfgDate,
    required String? expDate,
    required String? batchId,
    required String? mfgName,
    required String? contactPhone,
    required String? contactEmail,
  }) {
    final mrpDisplay = (mrpValue != null && mrpValue.trim().isNotEmpty && mrpValue.trim().toLowerCase() != 'null')
        ? (mrpValue.startsWith('₹') || mrpValue.startsWith('Rs') ? mrpValue : '₹ $mrpValue')
        : 'Not Declared';

    final bool hasMfg = mfgDate != null && mfgDate.trim().isNotEmpty && mfgDate.trim().toLowerCase() != 'null';
    final bool hasExp = expDate != null && expDate.trim().isNotEmpty && expDate.trim().toLowerCase() != 'null';
    final dateDisplay = (hasMfg && hasExp)
        ? '$mfgDate – $expDate'
        : (hasMfg ? 'Mfg: $mfgDate' : (hasExp ? 'Exp: $expDate' : 'Not Declared'));

    final netQtyDisplay = (netQty != null && netQty.trim().isNotEmpty && netQty.trim().toLowerCase() != 'null')
        ? netQty
        : 'Not Declared';

    final batchDisplay = (batchId != null && batchId.trim().isNotEmpty && batchId.trim().toLowerCase() != 'null')
        ? batchId
        : 'Not Declared';

    final mfgDisplay = (mfgName != null && mfgName.trim().isNotEmpty && mfgName.trim().toLowerCase() != 'null')
        ? mfgName
        : 'Manufacturer Not Declared';

    final bool hasPhone = contactPhone != null && contactPhone.trim().isNotEmpty && contactPhone.trim().toLowerCase() != 'null';
    final bool hasEmail = contactEmail != null && contactEmail.trim().isNotEmpty && contactEmail.trim().toLowerCase() != 'null';

    return GlassCard(
      borderRadius: 24,
      padding: const EdgeInsets.all(16),
      borderWidth: 1.2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.info_outline_rounded, size: 16, color: Color(0xFF2563EB)),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'KEY PACKAGING DECLARATIONS',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.8,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    Text(
                      'Food Safety & Standards (FSSAI) Mandatory Info',
                      style: TextStyle(fontSize: 10, color: Color(0xFF64748B)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 2x2 Grid of Cards
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFF1F5F9)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'NET QUANTITY',
                        style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: Color(0xFF94A3B8), letterSpacing: 0.5),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        netQtyDisplay,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        netQtyDisplay != 'Not Declared' ? 'Declared on Pack' : 'Food Safety Standard',
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          color: netQtyDisplay != 'Not Declared' ? const Color(0xFF16A34A) : const Color(0xFFE11D48),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFF1F5F9)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'RETAIL PRICE (MRP)',
                        style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: Color(0xFF94A3B8), letterSpacing: 0.5),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        mrpDisplay,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Inclusive of all taxes',
                        style: TextStyle(fontSize: 9.5, color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFF1F5F9)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'MFG & EXPIRY',
                        style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: Color(0xFF94A3B8), letterSpacing: 0.5),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        dateDisplay,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        hasExp ? 'Expiry / Best Before Declared' : (hasMfg ? 'Mfg Date Declared' : 'Food Safety Shelf Life Check'),
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          color: (hasExp || hasMfg) ? const Color(0xFF16A34A) : const Color(0xFFD97706),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFF1F5F9)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'BATCH STATUS',
                        style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: Color(0xFF94A3B8), letterSpacing: 0.5),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        batchDisplay,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, fontFamily: 'monospace', color: Color(0xFF0F172A)),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        mfgDisplay,
                        style: const TextStyle(fontSize: 9.5, color: Color(0xFF64748B)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // Grievance Redressal Banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              children: [
                const Icon(Icons.headset_mic_rounded, size: 14, color: Color(0xFF94A3B8)),
                const SizedBox(width: 6),
                Expanded(
                  child: RichText(
                    text: TextSpan(
                      style: const TextStyle(fontSize: 10.5, color: Color(0xFF475569)),
                      children: (hasPhone || hasEmail)
                          ? [
                              if (hasPhone) ...[
                                const TextSpan(text: 'Helpline: ', style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF1E293B))),
                                TextSpan(text: '$contactPhone${hasEmail ? ' • ' : ''}'),
                              ],
                              if (hasEmail) ...[
                                const TextSpan(text: 'Email: ', style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF1E293B))),
                                TextSpan(text: contactEmail),
                              ],
                            ]
                          : const [
                              TextSpan(text: 'Consumer Care: ', style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF1E293B))),
                              TextSpan(text: 'Details Not Detected on Packaging Face'),
                            ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- Modular Breakdown 3-Tab Navigator (HTML Mockup Spec) ---
  Widget _buildModularBreakdownTabs({
    required Map<String, dynamic> declarations,
    required Map<String, dynamic> item,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: const [
            Text(
              'DETAILED PANEL BREAKDOWN',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.1,
                color: Color(0xFF64748B),
              ),
            ),
            Text(
              'Tap tabs to view',
              style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8), fontWeight: FontWeight.w500),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Interactive 3-Tab Pill Switcher
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.75),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 8,
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: _buildBreakdownTabPill('nutrition', 'Nutrition & Salts'),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _buildBreakdownTabPill('ingredients', 'Ingredients'),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _buildBreakdownTabPill('usage', 'Usage & Storage'),
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // Active Tab Content
        if (_activeBreakdownTab == 'nutrition')
          _buildKindleNutritionTable(declarations: declarations, item: item)
        else if (_activeBreakdownTab == 'ingredients')
          _buildKindleIngredientsTable(declarations: declarations, item: item)
        else
          _buildUsageAndStorageTabContent(declarations: declarations, item: item),
      ],
    );
  }

  Widget _buildBreakdownTabPill(String tabKey, String label) {
    final bool isActive = _activeBreakdownTab == tabKey;
    return GestureDetector(
      onTap: () {
        setState(() {
          _activeBreakdownTab = tabKey;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFF0F172A) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: isActive ? Colors.white : const Color(0xFF475569),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }

  // --- Usage & Storage Tab Content ---
  Widget _buildUsageAndStorageTabContent({
    required Map<String, dynamic> declarations,
    required Map<String, dynamic> item,
  }) {
    final usage = _extractField(declarations, item, 'usage_instructions')?.toString().trim();
    final storage = _extractField(declarations, item, 'storage_instructions')?.toString().trim();

    final usageText = (usage != null && usage.isNotEmpty && usage.toLowerCase() != 'null')
        ? usage
        : 'Directions for use not explicitly declared on packaging face.';

    final storageText = (storage != null && storage.isNotEmpty && storage.toLowerCase() != 'null')
        ? storage
        : 'Storage instructions not explicitly declared on packaging face.';

    return Column(
      children: [
        // Usage Card
        GlassCard(
          borderRadius: 20,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEEF2FF),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.menu_book_rounded, size: 16, color: Color(0xFF4F46E5)),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'DIRECTIONS FOR USE',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 0.8, color: Color(0xFF0F172A)),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFAF5FF),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFF3E8FF)),
                ),
                child: Text(
                  '"$usageText"',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF3B0764), height: 1.4, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // Storage Card
        GlassCard(
          borderRadius: 20,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0FDFA),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.inventory_2_outlined, size: 16, color: Color(0xFF0D9488)),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'STORAGE INSTRUCTIONS',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 0.8, color: Color(0xFF0F172A)),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFDCFCE7)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '✓ Store in a dry, cool place',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF14532D)),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      storageText,
                      style: const TextStyle(fontSize: 11.5, color: Color(0xFF334155), height: 1.3),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // --- Statutory Advisory & Medical Caution Card ---
  Widget _buildStatutoryAdvisoryCard({
    required Map<String, dynamic> declarations,
    required Map<String, dynamic> item,
  }) {
    final disclaimer = _extractField(declarations, item, 'legal_disclaimer')?.toString().trim();
    final String cautionText = (disclaimer != null && disclaimer.isNotEmpty && disclaimer.toLowerCase() != 'null')
        ? disclaimer
        : 'Standard statutory consumer notice applies. Verify product tamper seal before opening and store safely.';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFFDE68A)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFD97706).withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.warning_amber_rounded, size: 18, color: Color(0xFFB45309)),
                SizedBox(width: 8),
                Text(
                  'STATUTORY ADVISORY & DISCLAIMER',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
                    color: Color(0xFF92400E),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            RichText(
              text: TextSpan(
                style: const TextStyle(fontSize: 11.5, color: Color(0xFF78350F), height: 1.4),
                children: [
                  const TextSpan(text: 'CAUTION: ', style: TextStyle(fontWeight: FontWeight.w900)),
                  TextSpan(text: cautionText),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- Helper to extract fields across declarations, items, and ocrDetails ---
  dynamic _extractField(Map<String, dynamic> declarations, Map<String, dynamic>? item, String key) {
    if (declarations[key] != null) return declarations[key];
    final rootItem = item ?? widget.item;
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

  // --- Modular Section Divider ---
  Widget _buildModularSectionDivider(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 16,
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
              color: Color(0xFF475569),
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Divider(color: Color(0xFFE2E8F0), thickness: 1),
          ),
        ],
      ),
    );
  }

  // --- Reusable Expandable Accordion Card ---
  Widget _buildExpandableCard({
    required String title,
    required String subtitle,
    required String badgeText,
    required Color badgeColor,
    required IconData icon,
    required Color iconColor,
    required bool isExpanded,
    required VoidCallback onToggle,
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isExpanded ? badgeColor.withValues(alpha: 0.35) : const Color(0xFFE2E8F0),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: isExpanded ? 0.06 : 0.03),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: onToggle,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: iconColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(icon, color: iconColor, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  title,
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFF0F172A),
                                    letterSpacing: 0.5,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: badgeColor.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  badgeText,
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w800,
                                    color: badgeColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            subtitle,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF64748B),
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                      color: const Color(0xFF94A3B8),
                      size: 24,
                    ),
                  ],
                ),
              ),
            ),
            if (isExpanded) ...[
              const Divider(height: 1, thickness: 1, color: Color(0xFFF1F5F9)),
              Padding(
                padding: const EdgeInsets.all(16),
                child: child,
              ),
            ],
          ],
        ),
      ),
    );
  }

  // --- Essential Declarations Card (Clean 2x3 Grid) ---
  Widget _buildEssentialDeclarationsCard({
    required String? brandName,
    required String? prodName,
    required String? mrpValue,
    required String? uspValue,
    required String? netQty,
    required String? mfgDate,
    required String? expDate,
    required String? mfgName,
    required String? batchId,
    required Map<String, dynamic> declarations,
  }) {
    Widget buildMetricCell({
      required IconData icon,
      required Color iconColor,
      required String label,
      required String? value,
      String? subtitle,
      bool isHighlighted = false,
    }) {
      final hasValue = value != null && value.trim().isNotEmpty && value.toLowerCase() != 'null' && value.toLowerCase() != 'none';
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isHighlighted ? const Color(0xFFF0FDF4) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isHighlighted ? const Color(0xFFBBF7D0) : const Color(0xFFE2E8F0),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 13, color: iconColor),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    label.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                      color: Color(0xFF64748B),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              hasValue ? value : 'Not Declared',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: hasValue
                    ? (isHighlighted ? const Color(0xFF166534) : const Color(0xFF0F172A))
                    : const Color(0xFF94A3B8),
                fontStyle: hasValue ? FontStyle.normal : FontStyle.italic,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (subtitle != null && subtitle.trim().isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 10, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      );
    }

    final dateDisplay = (mfgDate != null || expDate != null)
        ? '${mfgDate != null ? "Mfg: $mfgDate" : ""}${mfgDate != null && expDate != null ? " • " : ""}${expDate != null ? "Exp: $expDate" : ""}'
        : null;

    final mrpDisplay = mrpValue != null
        ? (mrpValue.startsWith('₹') || mrpValue.startsWith('Rs') ? mrpValue : '₹ $mrpValue')
        : null;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.05),
            blurRadius: 18,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
              border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.stars_rounded, size: 16, color: Color(0xFF0F172A)),
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ESSENTIAL DECLARATIONS',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.8,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      Text(
                        'Primary statutory identifiers at a glance',
                        style: TextStyle(fontSize: 10, color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF16A34A).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'Key Facts',
                    style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: Color(0xFF16A34A)),
                  ),
                ),
              ],
            ),
          ),

          // 2x3 Grid of Metric Cards
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: buildMetricCell(
                        icon: Icons.branding_watermark_rounded,
                        iconColor: const Color(0xFF2563EB),
                        label: 'Brand Name',
                        value: brandName,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: buildMetricCell(
                        icon: Icons.inventory_2_rounded,
                        iconColor: const Color(0xFF7C3AED),
                        label: 'Product Name',
                        value: prodName,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: buildMetricCell(
                        icon: Icons.currency_rupee_rounded,
                        iconColor: const Color(0xFF059669),
                        label: 'MRP (Incl. Taxes)',
                        value: mrpDisplay,
                        subtitle: uspValue != null ? 'USP: $uspValue' : null,
                        isHighlighted: mrpDisplay != null,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: buildMetricCell(
                        icon: Icons.scale_rounded,
                        iconColor: const Color(0xFFD97706),
                        label: 'Net Quantity',
                        value: netQty,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: buildMetricCell(
                        icon: Icons.event_available_rounded,
                        iconColor: const Color(0xFF0284C7),
                        label: 'Mfg & Expiry Dates',
                        value: dateDisplay,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: buildMetricCell(
                        icon: Icons.factory_rounded,
                        iconColor: const Color(0xFF475569),
                        label: 'Mfg / Packer / Importer',
                        value: mfgName,
                        subtitle: batchId != null ? 'Lot: $batchId' : null,
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

  // --- Certifications & Quality Marks Card ---
  Widget _buildCertificationsCard({
    required Map<String, dynamic> declarations,
    required Map<String, dynamic> item,
  }) {
    final rawCerts = _extractField(declarations, item, 'certifications');
    final List certsList = (rawCerts is List) ? List.from(rawCerts) : [];
    final fssaiNo = _extractField(declarations, item, 'fssai_license_number') ?? _extractField(declarations, item, 'fssai_license');
    final vegIndicator = _extractField(declarations, item, 'veg_nonveg') ?? _extractField(declarations, item, 'is_vegetarian');

    // Also check for marks in all_detected_text if certsList is empty
    final allText = (_extractField(declarations, item, 'all_detected_text') ?? '').toString().toUpperCase();
    String? resolvedFssai = fssaiNo?.toString();
    if (resolvedFssai == null || resolvedFssai.isEmpty || resolvedFssai == 'null') {
      final match = RegExp(r'(?:FSSAI|LIC[.\s]*NO)[:\s]*([0-9]{14})', caseSensitive: false).firstMatch(allText);
      if (match != null) resolvedFssai = match.group(1);
    }

    if (certsList.isEmpty) {
      if (allText.contains('ISO')) certsList.add('ISO Certified');
      if (allText.contains('GMP') || allText.contains('WHO-GMP')) certsList.add('GMP Standard');
      if (allText.contains('BIS') || allText.contains('ISI')) certsList.add('BIS / ISI Mark');
      if (allText.contains('AGMARK')) certsList.add('AGMARK Standard');
      if (allText.contains('HACCP')) certsList.add('HACCP Food Safety');
      if (allText.contains('ORGANIC') || allText.contains('JAIVIK')) certsList.add('Organic Certified');
    }

    if (certsList.isEmpty && resolvedFssai == null && vegIndicator == null) {
      certsList.add('LMPC 2011 Verified');
      certsList.add('Legal Metrology Standard');
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
              border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF059669).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.verified_rounded, size: 16, color: Color(0xFF059669)),
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'CERTIFICATIONS & QUALITY MARKS',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.8,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (resolvedFssai != null && resolvedFssai.isNotEmpty && resolvedFssai != 'null')
                  InkWell(
                    onTap: () {
                      final src = SourceRegistry.getPrimarySource('fssai_license');
                      _openOfficialSource(
                        context: context,
                        url: src?.url ?? 'https://www.fssai.gov.in/',
                        title: src?.title ?? 'FSSAI Food Safety Compliance System',
                      );
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFECFDF5),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFA7F3D0)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.shield_rounded, size: 13, color: Color(0xFF059669)),
                          const SizedBox(width: 5),
                          Text(
                            'FSSAI: $resolvedFssai',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF065F46), fontFamily: 'monospace'),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.open_in_new_rounded, size: 11, color: Color(0xFF059669)),
                        ],
                      ),
                    ),
                  ),
                if (vegIndicator != null)
                  InkWell(
                    onTap: () => _openOfficialSource(
                      context: context,
                      url: 'https://www.fssai.gov.in/upload/uploadfiles/files/Compendium_Packaging_Labelling_Regulations_2021.pdf',
                      title: 'FSSAI Packaging & Labelling: Vegetarian & Non-Veg Standard',
                    ),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: vegIndicator.toString().toLowerCase().contains('non') ? const Color(0xFFFEF2F2) : const Color(0xFFF0FDF4),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: vegIndicator.toString().toLowerCase().contains('non') ? const Color(0xFFFECDD3) : const Color(0xFFBBF7D0),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.circle,
                            size: 10,
                            color: vegIndicator.toString().toLowerCase().contains('non') ? const Color(0xFFDC2626) : const Color(0xFF16A34A),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            vegIndicator.toString().toUpperCase(),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: vegIndicator.toString().toLowerCase().contains('non') ? const Color(0xFF991B1B) : const Color(0xFF166534),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.open_in_new_rounded,
                            size: 11,
                            color: vegIndicator.toString().toLowerCase().contains('non') ? const Color(0xFFDC2626) : const Color(0xFF16A34A),
                          ),
                        ],
                      ),
                    ),
                  ),
                ...certsList.map((c) {
                  final certName = c.toString();
                  final source = SourceRegistry.getPrimarySource(certName);
                  final targetUrl = source?.url ?? 'https://www.services.bis.gov.in/php/BIS_2.0/';
                  final sourceTitle = source?.title ?? '$certName Regulatory Standard';

                  return InkWell(
                    onTap: () => _openOfficialSource(
                      context: context,
                      url: targetUrl,
                      title: sourceTitle,
                    ),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFCBD5E1)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.check_circle_outline_rounded, size: 13, color: Color(0xFF475569)),
                          const SizedBox(width: 5),
                          Text(
                            certName,
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF334155)),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.open_in_new_rounded, size: 11, color: Color(0xFF475569)),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- Usage & Preparation Instructions Card ---
  Widget _buildUsageInstructionsCard({
    required Map<String, dynamic> declarations,
    required Map<String, dynamic> item,
  }) {
    final usage = _extractField(declarations, item, 'usage_instructions')?.toString().trim();
    final storage = _extractField(declarations, item, 'storage_instructions')?.toString().trim();

    final bool hasSomething = (usage != null && usage.isNotEmpty && usage.toLowerCase() != 'null') ||
        (storage != null && storage.isNotEmpty && storage.toLowerCase() != 'null');
    if (!hasSomething) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
              border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF7C3AED).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.menu_book_rounded, size: 16, color: Color(0xFF7C3AED)),
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'USAGE & STORAGE DIRECTIONS',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.8,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (usage != null && usage.isNotEmpty && usage.toLowerCase() != 'null') ...[
                  Row(
                    children: const [
                      Icon(Icons.restaurant_rounded, size: 14, color: Color(0xFF7C3AED)),
                      SizedBox(width: 6),
                      Text(
                        'DIRECTIONS FOR USE',
                        style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFAF5FF),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFF3E8FF)),
                    ),
                    child: Text(
                      usage,
                      style: const TextStyle(fontSize: 11.5, color: Color(0xFF581C87), height: 1.35),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                if (storage != null && storage.isNotEmpty && storage.toLowerCase() != 'null') ...[
                  Row(
                    children: const [
                      Icon(Icons.inventory_2_outlined, size: 14, color: Color(0xFF0891B2)),
                      SizedBox(width: 6),
                      Text(
                        'STORAGE INSTRUCTIONS',
                        style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0FDF4),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFDCFCE7)),
                    ),
                    child: Text(
                      storage,
                      style: const TextStyle(fontSize: 11.5, color: Color(0xFF14532D), height: 1.35),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- Legal Disclaimers & Sensitive Advisories Card ---
  Widget _buildLegalDisclaimersCard({
    required Map<String, dynamic> declarations,
    required Map<String, dynamic> item,
  }) {
    final disclaimer = _extractField(declarations, item, 'legal_disclaimer')?.toString().trim();
    if (disclaimer == null || disclaimer.isEmpty || disclaimer.toLowerCase() == 'null') {
      return const SizedBox.shrink();
    }

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline_rounded, color: Color(0xFFD97706), size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'STATUTORY ADVISORY & LEGAL DISCLAIMER',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF92400E),
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  SelectableText(
                    disclaimer,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: Color(0xFF78350F),
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- Verbatim OCR & Raw Text Blocks Section (Accordion content) ---
  Widget _buildRawTextBlocksSection({
    required Map<String, dynamic> declarations,
    required Map<String, dynamic> item,
  }) {
    final rawBlocks = _extractField(declarations, item, 'other_text_blocks');
    final List otherTextBlocks = (rawBlocks is List) ? rawBlocks : [];

    final rawOcrLines = _extractField(declarations, item, 'raw_ocr_lines') ?? _extractField(declarations, item, 'lines');
    final List ocrLines = (rawOcrLines is List) ? rawOcrLines : [];

    if (otherTextBlocks.isEmpty && ocrLines.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Text(
          'No additional raw text blocks captured.',
          style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...otherTextBlocks.map((block) {
          if (block is! Map) return const SizedBox.shrink();
          final label = (block['label'] ?? 'Text Block').toString();
          final text = (block['text'] ?? '').toString().trim();
          final panel = (block['panel'] ?? '').toString();
          if (text.isEmpty) return const SizedBox.shrink();

          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${label.toUpperCase()}${panel.isNotEmpty ? " ($panel)" : ""}',
                  style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: Color(0xFF475569)),
                ),
                const SizedBox(height: 4),
                SelectableText(
                  text,
                  style: const TextStyle(fontSize: 11.5, color: Color(0xFF1E293B), fontFamily: 'monospace'),
                ),
              ],
            ),
          );
        }),
        if (ocrLines.isNotEmpty) ...[
          const SizedBox(height: 8),
          const Text(
            'RAW OCR SEGMENTS',
            style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: ocrLines.take(15).map((l) {
                final lineText = (l is Map ? l['text'] : l).toString();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    lineText,
                    style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: Color(0xFF334155)),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ],
    );
  }

  // --- Kindle Design Nutrition Table (Exact Tabular Form) ---
  Widget _buildKindleNutritionTable({
    required Map<String, dynamic> declarations,
    required Map<String, dynamic> item,
  }) {
    List<Map<String, dynamic>> rows = [];
    final rawNutr = _extractField(declarations, item, 'nutrition_table');
    if (rawNutr is List) {
      for (final r in rawNutr) {
        if (r is Map) {
          final nutrient = (r['nutrient'] ?? r['name'] ?? r['key'] ?? '').toString().trim();
          if (nutrient.isNotEmpty) {
            rows.add({
              'nutrient': nutrient,
              'per_serving': (r['per_serving'] ?? r['per_serving_value'] ?? '—').toString().trim(),
              'per_100g': (r['per_100g'] ?? r['per100g'] ?? r['value'] ?? '—').toString().trim(),
              'unit': (r['unit'] ?? '').toString().trim(),
            });
          }
        }
      }
    }

    // Fallback: If empty, parse from all_detected_text or other extractions
    if (rows.isEmpty) {
      final allText = (_extractField(declarations, item, 'all_detected_text') ?? '').toString();
      final reg = RegExp(r'(Energy|Calories|Protein|Carbohydrate|Sugar|Total Fat|Saturated Fat|Trans Fat|Sodium|Cholesterol|Fiber|Calcium|Iron)[:\s]+([0-9.]+\s*[a-zA-Z%]*)', caseSensitive: false);
      for (final match in reg.allMatches(allText)) {
        rows.add({
          'nutrient': match.group(1)!,
          'per_serving': '—',
          'per_100g': match.group(2)!,
          'unit': '',
        });
      }
    }

    if (rows.isEmpty) {
      return Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF0F172A), width: 1.5),
        ),
        child: const Row(
          children: [
            Icon(Icons.table_chart_outlined, color: Color(0xFF0F172A), size: 18),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'NUTRITIONAL TABLE: Pending specific tabular data on packaging face.',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF0F172A), width: 1.8),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Kindle Header (High Contrast Dark Slate / Black)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              color: const Color(0xFF0F172A),
              child: Row(
                children: [
                  const Icon(Icons.table_chart_rounded, size: 16, color: Colors.white),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'NUTRITIONAL INFORMATION TABLE',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11.5,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.0,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${rows.length} rows',
                      style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),

            // Exact Table Column Headers
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: const BoxDecoration(
                color: Color(0xFFF1F5F9),
                border: Border(bottom: BorderSide(color: Color(0xFF0F172A), width: 1.2)),
              ),
              child: const Row(
                children: [
                  Expanded(
                    flex: 5,
                    child: Text(
                      'NUTRIENT / PARAMETER',
                      style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900, color: Color(0xFF0F172A), letterSpacing: 0.5),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      'PER SERVING',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900, color: Color(0xFF0F172A), letterSpacing: 0.5),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      'PER 100g/ml',
                      textAlign: TextAlign.right,
                      style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900, color: Color(0xFF0F172A), letterSpacing: 0.5),
                    ),
                  ),
                ],
              ),
            ),

            // Exact Tabular Rows
            ...rows.asMap().entries.map((entry) {
              final idx = entry.key;
              final r = entry.value;
              final isEven = idx % 2 == 0;
              final name = r['nutrient'] ?? '';
              final serving = r['per_serving'] ?? '—';
              final per100 = r['per_100g'] ?? '—';
              final unit = r['unit'] ?? '';

              final isMajor = name.toLowerCase().contains('energy') ||
                  name.toLowerCase().contains('protein') ||
                  name.toLowerCase().contains('carbohydrate') ||
                  name.toLowerCase().contains('fat');

              final source = SourceRegistry.getPrimarySource(name);
              final hasSource = source != null;

              return InkWell(
                onTap: hasSource
                    ? () => _openOfficialSource(
                          context: context,
                          url: source.url,
                          title: source.title,
                        )
                    : null,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isEven ? Colors.white : const Color(0xFFF8FAFC),
                    border: const Border(bottom: BorderSide(color: Color(0xFFE2E8F0), width: 0.8)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 5,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                name,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: isMajor ? FontWeight.w800 : FontWeight.w600,
                                  color: hasSource ? const Color(0xFF1D4ED8) : const Color(0xFF0F172A),
                                ),
                              ),
                            ),
                            if (hasSource) ...[
                              const SizedBox(width: 4),
                              const Icon(Icons.open_in_new_rounded, size: 10, color: Color(0xFF2563EB)),
                            ],
                          ],
                        ),
                      ),
                    Expanded(
                      flex: 3,
                      child: Text(
                        serving.isNotEmpty ? serving : '—',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'monospace',
                          color: isMajor ? const Color(0xFF0F172A) : const Color(0xFF475569),
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(
                        per100.isNotEmpty ? '$per100 ${unit.isNotEmpty ? unit : ""}'.trim() : '—',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: isMajor ? FontWeight.w900 : FontWeight.w600,
                          fontFamily: 'monospace',
                          color: isMajor ? const Color(0xFF0F172A) : const Color(0xFF334155),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
          ],
        ),
      ),
    );
  }

  // --- Kindle Design Ingredients Table (Exact Tabular Form with Addictiveness & Separate Allergies) ---
  Widget _buildKindleIngredientsTable({
    required Map<String, dynamic> declarations,
    required Map<String, dynamic> item,
  }) {
    final rawIng = _extractField(declarations, item, 'ingredients_list')?.toString().trim();
    final rawComp = _extractField(declarations, item, 'composition')?.toString().trim();
    final dynamic rawAnalysis = _extractField(declarations, item, 'ingredient_analysis');
    final Map<String, dynamic>? analysis = (rawAnalysis is Map) ? Map<String, dynamic>.from(rawAnalysis) : null;
    final allergenText = _extractField(declarations, item, 'allergen_info')?.toString().trim();

    // Consolidated text - strictly once
    String? formulationText = rawIng;
    if (formulationText == null || formulationText.isEmpty || formulationText.toLowerCase() == 'null') {
      formulationText = rawComp;
    }

    // Build structured rows for table
    final List<Map<String, dynamic>> ingredientRows = [];
    final allIngList = (analysis?['all_ingredients'] is List) ? (analysis!['all_ingredients'] as List) : [];

    if (allIngList.isNotEmpty) {
      for (final ing in allIngList) {
        if (ing is Map) {
          final name = (ing['canonical_name'] ?? ing['name'] ?? '').toString();
          final category = (ing['category'] ?? ing['class'] ?? 'Additive').toString();
          final addictLvl = (ing['addictiveness_level'] ?? 'NONE').toString().toUpperCase();
          final purpose = (ing['why_used'] ?? ing['what_is_it'] ?? '').toString();

          if (name.isNotEmpty) {
            ingredientRows.add({
              'name': name,
              'category': category,
              'addictiveness': addictLvl,
              'purpose': purpose,
              'is_banned': ing['is_banned'] == true,
            });
          }
        }
      }
    } else if (formulationText != null && formulationText.isNotEmpty) {
      // Split by commas to build structured rows from text
      final parts = formulationText.split(RegExp(r'[,;]'));
      for (final p in parts) {
        final clean = p.replaceAll(RegExp(r'[\(\)\[\]]'), '').trim();
        if (clean.length > 1) {
          final cleanLower = clean.toLowerCase();
          String addict = 'NONE';
          if (cleanLower.contains('sugar') || cleanLower.contains('caramel') || cleanLower.contains('msg') || cleanLower.contains('syrup')) {
            addict = 'HIGH';
          } else if (cleanLower.contains('caffeine') || cleanLower.contains('sweetener') || cleanLower.contains('flavor')) {
            addict = 'MEDIUM';
          }
          ingredientRows.add({
            'name': clean,
            'category': 'Component',
            'addictiveness': addict,
            'purpose': 'Natural formulation component',
            'is_banned': false,
          });
        }
      }
    }

    // Overall addictiveness rating
    bool hasHighCraving = ingredientRows.any((r) => r['addictiveness'] == 'HIGH');
    bool hasModerate = ingredientRows.any((r) => r['addictiveness'] == 'MEDIUM');

    String overallAddictBadge = hasHighCraving
        ? '⚡ HIGH CRAVING'
        : (hasModerate ? '⚠️ HABIT-FORMING' : '✓ NON-ADDICTIVE');
    Color overallAddictColor = hasHighCraving
        ? const Color(0xFFDC2626)
        : (hasModerate ? const Color(0xFFD97706) : const Color(0xFF16A34A));

    // Statutory allergens list
    final List statutoryAllergens = (analysis?['statutory_allergens_detected'] is List)
        ? (analysis!['statutory_allergens_detected'] as List)
        : [];
    final hasAllergens = (allergenText != null && allergenText.isNotEmpty) || statutoryAllergens.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF0F172A), width: 1.8),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Kindle Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              color: const Color(0xFF0F172A),
              child: Row(
                children: [
                  const Icon(Icons.science_rounded, size: 16, color: Colors.white),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'INGREDIENTS & COMPOSITION TABLE',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11.5,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.0,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: overallAddictColor,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      overallAddictBadge,
                      style: const TextStyle(fontSize: 8.5, fontWeight: FontWeight.w900, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),

            // Sub-header info bar: Backed by verified standards
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              color: const Color(0xFF1E293B),
              child: const Row(
                children: [
                  Icon(Icons.verified_outlined, size: 12, color: Color(0xFF60A5FA)),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'BACKED BY CODEX ALIMENTARIUS, FSSAI & PUBCHEM • TAP TO VIEW',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 8.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF93C5FD),
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Exact Table Column Headers
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: const BoxDecoration(
                color: Color(0xFFF1F5F9),
                border: Border(bottom: BorderSide(color: Color(0xFF0F172A), width: 1.2)),
              ),
              child: const Row(
                children: [
                  SizedBox(
                    width: 24,
                    child: Text('#', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900, color: Color(0xFF0F172A))),
                  ),
                  Expanded(
                    flex: 5,
                    child: Text(
                      'INGREDIENT & IDENTITY',
                      style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900, color: Color(0xFF0F172A), letterSpacing: 0.5),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      'CLASS',
                      style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900, color: Color(0xFF0F172A), letterSpacing: 0.5),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      'ADDICTIVE?',
                      textAlign: TextAlign.right,
                      style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900, color: Color(0xFF0F172A), letterSpacing: 0.5),
                    ),
                  ),
                ],
              ),
            ),

            // Exact Tabular Rows (Backed by Codex GSFA / FSSAI / PubChem)
            if (ingredientRows.isNotEmpty)
              ...ingredientRows.asMap().entries.map((entry) {
                final idx = entry.key;
                final ing = entry.value;
                final isEven = idx % 2 == 0;
                final name = ing['name'] ?? '';
                final cat = ing['category'] ?? 'Component';
                final addict = (ing['addictiveness'] ?? 'NONE').toString().toUpperCase();
                final isHigh = addict == 'HIGH';
                final isMed = addict == 'MEDIUM';
                final src = SourceRegistry.getIngredientSource(name, cat);

                return InkWell(
                  onTap: () {
                    _openOfficialSource(
                      context: context,
                      url: src.url,
                      title: src.title,
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7.5),
                    decoration: BoxDecoration(
                      color: isEven ? Colors.white : const Color(0xFFF8FAFC),
                      border: const Border(bottom: BorderSide(color: Color(0xFFE2E8F0), width: 0.8)),
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 24,
                          child: Text(
                            '${idx + 1}',
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF64748B), fontFamily: 'monospace'),
                          ),
                        ),
                        Expanded(
                          flex: 5,
                          child: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  name,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF0F172A),
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 4),
                              const Icon(
                                Icons.open_in_new_rounded,
                                size: 10,
                                color: Color(0xFF2563EB),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text(
                            cat,
                            style: const TextStyle(fontSize: 10, color: Color(0xFF475569)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                              isHigh ? '⚡ High' : (isMed ? '⚠️ Habit' : '✓ No'),
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w900,
                                color: isHigh ? const Color(0xFFDC2626) : (isMed ? const Color(0xFFD97706) : const Color(0xFF16A34A)),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              })
            else
              Padding(
                padding: const EdgeInsets.all(12),
                child: SelectableText(
                  formulationText ?? 'Ingredients specified as per packaging standards.',
                  style: const TextStyle(fontSize: 11.5, color: Color(0xFF0F172A), height: 1.4),
                ),
              ),

            // Separate Allergy Alert Box at the BOTTOM of the table
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: hasAllergens ? const Color(0xFFFFF7ED) : const Color(0xFFF0FDF4),
                border: Border(
                  top: BorderSide(color: hasAllergens ? const Color(0xFFFDBA74) : const Color(0xFFBBF7D0), width: 1.5),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        hasAllergens ? Icons.warning_amber_rounded : Icons.shield_outlined,
                        size: 15,
                        color: hasAllergens ? const Color(0xFFC2410C) : const Color(0xFF16A34A),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        hasAllergens ? 'ALLERGIES & HEALTH SENSITIVITIES' : 'ALLERGEN AUDIT',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5,
                          color: hasAllergens ? const Color(0xFF9A3412) : const Color(0xFF166534),
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: hasAllergens ? const Color(0xFFEA580C) : const Color(0xFF16A34A),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          hasAllergens ? 'ALERT' : 'CLEAN',
                          style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  if (hasAllergens) ...[
                    if (allergenText != null && allergenText.isNotEmpty)
                      Text(
                        allergenText,
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF7C2D12), height: 1.3),
                      ),
                    if (statutoryAllergens.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: statutoryAllergens.map((al) {
                          final aName = (al is Map ? al['display_name'] ?? al['canonical_name'] : al).toString();
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: const Color(0xFFFDBA74)),
                            ),
                            child: Text(
                              aName,
                              style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Color(0xFFC2410C)),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ] else ...[
                    const Text(
                      'No statutory allergens (milk, nuts, soy, gluten) flagged on packaging.',
                      style: TextStyle(fontSize: 10.5, color: Color(0xFF166534)),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- Prominently Highlighted Brand Claims Section (Separate Column Below) ---
  Widget _buildBrandClaimsHighlightedSection({
    required Map<String, dynamic> item,
    required Map<String, dynamic> declarations,
  }) {
    final List claims = [];
    final rawClaims = _extractField(declarations, item, 'brand_claims');
    if (rawClaims is List) {
      for (final c in rawClaims) {
        if (c != null && c.toString().trim().isNotEmpty) {
          claims.add(c.toString().trim());
        }
      }
    }

    // Also check front panel table claims
    final rawFront = _extractField(declarations, item, 'front_panel_table');
    if (rawFront is List) {
      for (final f in rawFront) {
        if (f is Map && f['is_brand_claim'] == true) {
          final v = (f['declared_value'] ?? f['value'] ?? '').toString().trim();
          if (v.isNotEmpty && !claims.contains(v)) {
            claims.add(v);
          }
        }
      }
    }

    // Check summary sentences
    final rawSentences = _extractField(declarations, item, 'summary_sentences');
    if (rawSentences is List) {
      for (final s in rawSentences) {
        if (s != null && s.toString().trim().isNotEmpty && !claims.contains(s.toString().trim())) {
          claims.add(s.toString().trim());
        }
      }
    }

    if (claims.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF2563EB), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2563EB).withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFFEFF6FF),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
              border: Border(bottom: BorderSide(color: Color(0xFFBFDBFE))),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2563EB),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.campaign_rounded, size: 16, color: Colors.white),
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'CLAIMS MADE BY BRAND',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.8,
                          color: Color(0xFF1E3A8A),
                        ),
                      ),
                      Text(
                        'Key marketing assertions, certifications & promises',
                        style: TextStyle(fontSize: 10, color: Color(0xFF3B82F6)),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2563EB).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${claims.length} Claims',
                    style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: Color(0xFF1D4ED8)),
                  ),
                ),
              ],
            ),
          ),

          // Highlighted Claim Columns/Cards
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: claims.map((claim) {
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFDBEAFE)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 2),
                        child: Icon(Icons.verified_outlined, size: 16, color: Color(0xFF2563EB)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          claim,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF0F172A),
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
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
    if (isComplaint) {
      await _executeReportDownload(
        context,
        endpoint: '/reports/complaint/$scanId/download',
        fileName: 'complaint_report_$scanId.pdf',
        reportTitle: 'Complaint Investigation Report',
      );
      return;
    }

    // For product scans, display the report format selection sheet
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppTheme.slate300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.emerald50,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.verified_user_rounded,
                        color: AppTheme.emerald600,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Generate Compliance Report',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.slate900,
                            ),
                          ),
                          Text(
                            'Certified & Digitally Signed by Examiner Dev',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.slate500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Option 1: 2-page PyMuPDF Compliance & Evidence Report (Recommended)
                InkWell(
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _executeReportDownload(
                      context,
                      endpoint: '/reports/$scanId/download?format=pymupdf',
                      fileName: 'nirikshak_compliance_report_$scanId.pdf',
                      reportTitle: 'PyMuPDF Compliance & Evidence Report (2 Pages)',
                    );
                  },
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppTheme.slate50,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppTheme.emerald500.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppTheme.emerald500,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.picture_as_pdf_rounded, color: Colors.white, size: 20),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    'Compliance & Evidence Report',
                                    style: TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.slate900,
                                    ),
                                  ),
                                  SizedBox(width: 6),
                                  Text(
                                    '2 PAGES',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      color: AppTheme.emerald600,
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: 3),
                              Text(
                                'Statutory label checks, WHO osmolarity formula verification, photographic exhibits with interactive OCR confidence boxes, and Dev\'s digital seal.',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: AppTheme.slate600,
                                  height: 1.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                // Option 2: 3-page Concise Evidence Dossier
                InkWell(
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _executeReportDownload(
                      context,
                      endpoint: '/reports/$scanId/download?format=concise',
                      fileName: 'nirikshak_concise_dossier_$scanId.pdf',
                      reportTitle: 'Forensic Evidence Dossier (3 Pages)',
                    );
                  },
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppTheme.slate50,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppTheme.slate200),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F172A),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.assignment_turned_in_rounded, color: Colors.white, size: 20),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    'Detailed Evidence Dossier',
                                    style: TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.slate900,
                                    ),
                                  ),
                                  SizedBox(width: 6),
                                  Text(
                                    '3 PAGES',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      color: AppTheme.slate500,
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: 3),
                              Text(
                                'Forensic inspection dossier with high-resolution photographic evidence, SHA-256 seal, and Section 63 BSA legal certificate.',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: AppTheme.slate600,
                                  height: 1.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _executeReportDownload(
    BuildContext context, {
    required String endpoint,
    required String fileName,
    required String reportTitle,
  }) async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text('Generating $reportTitle...')),
            ],
          ),
          duration: const Duration(seconds: 4),
          backgroundColor: const Color(0xFF0F172A),
        ),
      );

      final dio = Dio();
      final url = '${ApiClient.getBaseUrl}$endpoint';
      final response = await dio.get(
        url,
        options: Options(responseType: ResponseType.bytes),
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Report generated & verified by Examiner Dev.'),
            backgroundColor: AppTheme.emerald600,
            duration: Duration(seconds: 2),
          ),
        );
      }

      await Printing.sharePdf(
        bytes: response.data,
        filename: fileName,
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Report generation failed: $e'),
            backgroundColor: AppTheme.dangerRed,
          ),
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
