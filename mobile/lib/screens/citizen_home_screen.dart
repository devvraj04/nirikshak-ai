import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../core/theme.dart';
import '../providers/auth_provider.dart';
import '../core/api_client.dart';
import '../widgets/aura_background.dart';
import '../widgets/glass_card.dart';
import '../widgets/pulse_indicator.dart';
import '../widgets/nirikshak_app_bar.dart';
import 'details_screen.dart';

class CitizenHomeScreen extends ConsumerStatefulWidget {
  const CitizenHomeScreen({super.key});

  @override
  ConsumerState<CitizenHomeScreen> createState() => _CitizenHomeScreenState();
}

class _CitizenHomeScreenState extends ConsumerState<CitizenHomeScreen> {
  final ApiClient _apiClient = ApiClient();
  final ImagePicker _picker = ImagePicker();
  List<dynamic> _history = [];
  int _rewardPoints = 0;
  bool _isLoading = true;
  int _currentNavIndex = 0; // 0: Home, 1: Audits, 2: Center Scan, 3: Reports, 4: Rules

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final auth = ref.read(authProvider);
    try {
      final data = await _apiClient.fetchCitizenHistory(auth.userId);
      if (mounted) {
        setState(() {
          _history = data['history'] ?? [];
          _rewardPoints = data['reward_points'] ?? 0;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickAndUploadGalleryImage() async {
    try {
      final XFile? image = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
      if (image != null && mounted) {
        context.push('/scan');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking image: $e')),
        );
      }
    }
  }

  List<dynamic> get _scans => _history.where((item) => item['type'] == 'SCAN').toList();
  List<dynamic> get _complaints => _history.where((item) => item['type'] == 'COMPLAINT').toList();

  Map<String, List<dynamic>> get _scansByBrand {
    final Map<String, List<dynamic>> grouped = {};
    for (final scan in _scans) {
      final brand = scan['manufacturer_name']?.toString() ?? 'Unknown Brand';
      grouped.putIfAbsent(brand, () => []).add(scan);
    }
    for (final group in grouped.values) {
      group.sort((a, b) {
        final dateA = a['date']?.toString() ?? '';
        final dateB = b['date']?.toString() ?? '';
        return dateB.compareTo(dateA);
      });
    }
    return Map.fromEntries(
      grouped.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);

    return Scaffold(
      body: AuraBackground(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: AppTheme.emerald500))
            : Stack(
                children: [
                  // Scrollable Content
                  Positioned.fill(
                    child: RefreshIndicator(
                      onRefresh: _loadData,
                      color: AppTheme.emerald500,
                      child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Top Header / Status Bar
                            _buildHeader(auth),

                            const SizedBox(height: 12),

                            // Welcome & Reward Pill
                            _buildWelcomePill(auth),

                            const SizedBox(height: 12),

                            // Main switchable content based on nav selection
                            if (_currentNavIndex == 1) ...[
                              _buildAuditsSection(),
                            ] else if (_currentNavIndex == 3) ...[
                              _buildReportsSection(),
                            ] else ...[
                              _buildLiveScannerCard(),
                              const SizedBox(height: 14),
                              _buildChecklistCard(),
                              const SizedBox(height: 14),
                              _buildAnalyticsGrid(),
                              const SizedBox(height: 14),
                              _buildRecentActivitySection(),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Bottom Floating App Bar Navigation
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 16,
                    child: _buildFloatingBottomNav(),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildHeader(AuthState auth) {
    return NirikshakAppBar(
      badgeText: 'LMPC 2011',
      subtitle: 'Legal Metrology Compliance Engine',
      trailing: Row(
        children: [
          GestureDetector(
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('All legal metrology compliance rules are active & updated.')),
              );
            },
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.72),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withValues(alpha: 0.85)),
                boxShadow: const [
                  BoxShadow(color: Color(0x121F2687), blurRadius: 16, offset: Offset(0, 4)),
                ],
              ),
              child: const Icon(Icons.notifications_none_rounded, size: 18, color: AppTheme.slate700),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => context.go('/login'),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppTheme.slate200,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: const [
                  BoxShadow(color: Color(0x1A000000), blurRadius: 6, offset: Offset(0, 2)),
                ],
              ),
              child: Center(
                child: Text(
                  auth.role == UserRoleState.officer ? 'RAJ' : 'DEV',
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.slate900),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWelcomePill(AuthState auth) {
    final String displayName = auth.userName.isNotEmpty ? auth.userName : 'Dev';
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      borderRadius: 14,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              children: [
                const Icon(Icons.verified_user_outlined, size: 16, color: AppTheme.emerald600),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Welcome, $displayName',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.slate900),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppTheme.warningAmberLight,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.warningAmber.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.stars_rounded, color: AppTheme.warningAmber, size: 13),
                const SizedBox(width: 4),
                Text(
                  '$_rewardPoints PTS',
                  style: const TextStyle(color: AppTheme.warningAmber, fontWeight: FontWeight.bold, fontSize: 10),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLiveScannerCard() {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      borderRadius: 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Row
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    PulseIndicator(color: AppTheme.emerald500, size: 8),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'VISION OCR & LABEL SCANNER',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.slate700,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Rule 6 Mandate',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: AppTheme.slate500),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Viewfinder Frame
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            decoration: BoxDecoration(
              color: const Color(0xEE0F172A), // Slate 900/90
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0x33475569)),
              boxShadow: const [
                BoxShadow(color: Color(0x40000000), blurRadius: 12, offset: Offset(0, 4)),
              ],
            ),
            child: Stack(
              children: [
                // Corner guides
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

                // Center Viewfinder Content
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppTheme.emerald500.withValues(alpha: 0.12),
                          border: Border.all(color: AppTheme.emerald500.withValues(alpha: 0.35)),
                        ),
                        child: const Icon(
                          Icons.qr_code_scanner_rounded,
                          color: AppTheme.emerald400,
                          size: 24,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Align package label, MRP panel, or barcode',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFF1F5F9),
                        ),
                      ),
                      const SizedBox(height: 3),
                      const Text(
                        'Detects Net Quantity, MRP, Mfg Date, Customer Care',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 10,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Action Buttons
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ElevatedButton.icon(
                            onPressed: () => context.push('/scan'),
                            icon: const Icon(Icons.camera_alt_rounded, size: 14, color: AppTheme.slate900),
                            label: const Text('Launch Camera', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.slate900)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.emerald400,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                          ElevatedButton.icon(
                            onPressed: _pickAndUploadGalleryImage,
                            icon: const Icon(Icons.file_upload_outlined, size: 14, color: Colors.white),
                            label: const Text('Upload Image', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: Colors.white)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white.withValues(alpha: 0.12),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                                side: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
                              ),
                              elevation: 0,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChecklistCard() {
    final passCount = _scans.where((s) => s['status'] == 'PASS').length;
    final totalCount = _scans.isEmpty ? 8 : _scans.length;
    final scoreDisplay = _scans.isEmpty ? '8/8 Passed' : '$passCount/$totalCount Passed';

    return GlassCard(
      padding: const EdgeInsets.all(16),
      borderRadius: 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Row(
                  children: [
                    Icon(Icons.checklist_rtl_rounded, color: AppTheme.emerald600, size: 16),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Legal Metrology (PC) Rules, 2011',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.slate900),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.emerald100,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  scoreDisplay,
                  style: const TextStyle(color: AppTheme.emerald800, fontWeight: FontWeight.bold, fontSize: 10),
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          _buildChecklistItem(
            title: 'Manufacturer / Packer Identity',
            subtitle: 'Name & complete address with PIN code',
            ruleTag: 'Rule 6(1)(a)',
          ),

          const SizedBox(height: 8),

          _buildChecklistItem(
            title: 'Net Quantity & Unit Sale Price (USP)',
            subtitle: 'Standard units (g/ml/kg) & price per g/ml',
            ruleTag: 'Rule 6(1)(c)',
          ),

          const SizedBox(height: 8),

          _buildChecklistItem(
            title: 'Maximum Retail Price (MRP)',
            subtitle: 'Inclusive of all taxes formatted correctly',
            ruleTag: 'Rule 6(1)(e)',
          ),

          const SizedBox(height: 8),

          _buildChecklistItem(
            title: 'Consumer Care Redressal',
            subtitle: 'Tel No., email, and officer designation',
            ruleTag: 'Rule 6(8)',
          ),
        ],
      ),
    );
  }

  Widget _buildChecklistItem({
    required String title,
    required String subtitle,
    required String ruleTag,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.slate200.withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              children: [
                Container(
                  width: 20,
                  height: 20,
                  decoration: const BoxDecoration(
                    color: AppTheme.emerald100,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check, size: 12, color: AppTheme.emerald600),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.slate900),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        subtitle,
                        style: const TextStyle(fontSize: 9, color: AppTheme.slate500),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppTheme.slate100,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              ruleTag,
              style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: AppTheme.slate700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnalyticsGrid() {
    final scanCount = _scans.isEmpty ? 1482 : _scans.length;
    final flagCount = _complaints.isEmpty ? 14 : _complaints.length;

    return Row(
      children: [
        // SKUs Verified Card
        Expanded(
          child: GlassCard(
            padding: const EdgeInsets.all(12),
            borderRadius: 16,
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppTheme.infoBlueLight,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.inventory_2_outlined, color: AppTheme.infoBlue, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$scanCount',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.slate900),
                      ),
                      const Text(
                        'SKUs Verified',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 10, color: AppTheme.slate500, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(width: 10),

        // Flags Card
        Expanded(
          child: GlassCard(
            padding: const EdgeInsets.all(12),
            borderRadius: 16,
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppTheme.warningAmberLight,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.warning_amber_rounded, color: AppTheme.warningAmber, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$flagCount Flags',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.slate900),
                      ),
                      const Text(
                        'Pending Review',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 10, color: AppTheme.slate500, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRecentActivitySection() {
    if (_history.isEmpty) {
      return GlassCard(
        padding: const EdgeInsets.all(16),
        borderRadius: 16,
        child: Column(
          children: [
            const Icon(Icons.shield_outlined, size: 32, color: AppTheme.emerald600),
            const SizedBox(height: 6),
            const Text('Compliance Engine Standing By', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.slate900)),
            const SizedBox(height: 2),
            const Text('Scan any packaged product to instantly extract label declarations.', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: AppTheme.slate500)),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              onPressed: () => context.push('/scan'),
              icon: const Icon(Icons.camera_alt_outlined, size: 14),
              label: const Text('SCAN PRODUCT', style: TextStyle(fontSize: 11)),
            ),
          ],
        ),
      );
    }

    final recentScans = _scans.take(3).toList();

    return GlassCard(
      padding: const EdgeInsets.all(14),
      borderRadius: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Recent Inspections', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.slate900)),
              TextButton(
                onPressed: () => setState(() => _currentNavIndex = 1),
                style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 0)),
                child: const Text('View All', style: TextStyle(fontSize: 11, color: AppTheme.emerald600, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...recentScans.map((scan) {
            final isPass = scan['status'] == 'PASS';
            return InkWell(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => DetailsScreen(item: Map<String, dynamic>.from(scan as Map))),
                );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: AppTheme.slate200.withValues(alpha: 0.5))),
                ),
                child: Row(
                  children: [
                    Icon(
                      isPass ? Icons.check_circle : Icons.cancel,
                      color: isPass ? AppTheme.successGreen : AppTheme.dangerRed,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(scan['product_name'] ?? 'Packaged Item', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.slate900), overflow: TextOverflow.ellipsis),
                          Text(scan['manufacturer_name'] ?? 'LMPC Audited', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: AppTheme.slate500)),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: (isPass ? AppTheme.successGreen : AppTheme.dangerRed).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        scan['status'] ?? 'REVIEW',
                        style: TextStyle(
                          color: isPass ? AppTheme.successGreen : AppTheme.dangerRed,
                          fontWeight: FontWeight.bold,
                          fontSize: 9,
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
    );
  }

  Widget _buildAuditsSection() {
    final brandGroups = _scansByBrand;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Product Audits & Scans', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.slate900)),
            Text('${_scans.length} Total', style: const TextStyle(fontSize: 12, color: AppTheme.slate500)),
          ],
        ),
        const SizedBox(height: 12),
        if (_scans.isEmpty)
          const GlassCard(
            padding: EdgeInsets.all(30),
            child: Center(
              child: Text('No audits yet. Scan a package to get started.', style: TextStyle(color: AppTheme.slate500)),
            ),
          )
        else
          ...brandGroups.entries.map((entry) {
            final brand = entry.key;
            final scans = entry.value;
            final passCount = scans.where((s) => s['status'] == 'PASS').length;
            final failCount = scans.where((s) => s['status'] == 'FAIL').length;

            return GlassCard(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              borderRadius: 16,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.business, size: 16, color: AppTheme.slate800),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          brand,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.slate900),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(color: AppTheme.emerald100, borderRadius: BorderRadius.circular(4)),
                        child: Text('$passCount✓', style: const TextStyle(color: AppTheme.emerald800, fontSize: 10, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                        child: Text('$failCount✗', style: const TextStyle(color: AppTheme.dangerRed, fontSize: 10, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...scans.map((scan) {
                    final isPass = scan['status'] == 'PASS';
                    return InkWell(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => DetailsScreen(item: Map<String, dynamic>.from(scan as Map))),
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            Icon(isPass ? Icons.check_circle_outline : Icons.highlight_off, color: isPass ? AppTheme.successGreen : AppTheme.dangerRed, size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(scan['product_name'] ?? 'Product', style: const TextStyle(fontSize: 12, color: AppTheme.slate900), overflow: TextOverflow.ellipsis),
                            ),
                            Text(scan['status'] ?? '', style: TextStyle(color: isPass ? AppTheme.successGreen : AppTheme.dangerRed, fontWeight: FontWeight.bold, fontSize: 10)),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ),
            );
          }),
      ],
    );
  }

  Widget _buildReportsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Expanded(
              child: Text(
                'Consumer Overcharging Reports',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.slate900),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: () => context.push('/complaint'),
              icon: const Icon(Icons.add, size: 14),
              label: const Text('File Report', style: TextStyle(fontSize: 11)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.warningAmber,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_complaints.isEmpty)
          const GlassCard(
            padding: EdgeInsets.all(30),
            child: Center(
              child: Text('No complaints filed yet.', style: TextStyle(color: AppTheme.slate500)),
            ),
          )
        else
          ..._complaints.map((item) {
            final status = item['status'] ?? 'SUBMITTED';
            final isResolved = status != 'SUBMITTED';

            return GlassCard(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(14),
              borderRadius: 16,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => DetailsScreen(item: Map<String, dynamic>.from(item as Map))),
                );
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(isResolved ? Icons.check_circle : Icons.pending_actions, color: isResolved ? AppTheme.successGreen : AppTheme.warningOrange, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(item['shopkeeper_name'] ?? 'Retail Store', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.slate900)),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: (isResolved ? AppTheme.successGreen : AppTheme.warningOrange).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(status, style: TextStyle(color: isResolved ? AppTheme.successGreen : AppTheme.warningOrange, fontWeight: FontWeight.bold, fontSize: 9)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text('Paid: ₹${item['paid_price']}', style: const TextStyle(color: AppTheme.dangerRed, fontWeight: FontWeight.bold, fontSize: 12)),
                      const SizedBox(width: 10),
                      Text('MRP: ₹${item['printed_mrp']}', style: const TextStyle(color: AppTheme.slate500, fontSize: 12, decoration: TextDecoration.lineThrough)),
                    ],
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }

  Widget _buildFloatingBottomNav() {
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      borderRadius: 24,
      backgroundColor: Colors.white.withValues(alpha: 0.85),
      child: Row(
        children: [
          Expanded(
            child: _buildNavItem(
              icon: Icons.home_rounded,
              label: 'Home',
              isActive: _currentNavIndex == 0,
              onTap: () => setState(() => _currentNavIndex = 0),
            ),
          ),
          Expanded(
            child: _buildNavItem(
              icon: Icons.search_rounded,
              label: 'Audits',
              isActive: _currentNavIndex == 1,
              onTap: () => setState(() => _currentNavIndex = 1),
            ),
          ),
          Expanded(
            child: Center(
              child: Transform.translate(
                offset: const Offset(0, -5),
                child: GestureDetector(
                  onTap: () => context.push('/scan'),
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppTheme.slate900,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2.5),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x33000000),
                          blurRadius: 12,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.qr_code_scanner_rounded,
                      color: AppTheme.emerald400,
                      size: 22,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: _buildNavItem(
              icon: Icons.description_outlined,
              label: 'Reports',
              isActive: _currentNavIndex == 3,
              onTap: () => setState(() => _currentNavIndex = 3),
            ),
          ),
          Expanded(
            child: _buildNavItem(
              icon: Icons.tune_rounded,
              label: 'Rules',
              isActive: _currentNavIndex == 4,
              onTap: () => context.push('/rules'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem({
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    final color = isActive ? AppTheme.slate900 : AppTheme.slate500;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10,
              fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
