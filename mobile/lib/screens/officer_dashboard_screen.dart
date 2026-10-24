import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../core/api_client.dart';
import '../core/theme.dart';
import '../providers/auth_provider.dart';
import '../widgets/aura_background.dart';
import '../widgets/glass_card.dart';
import '../widgets/pulse_indicator.dart';
import '../widgets/nirikshak_app_bar.dart';
import 'details_screen.dart';

class OfficerDashboardScreen extends ConsumerStatefulWidget {
  const OfficerDashboardScreen({super.key});

  @override
  ConsumerState<OfficerDashboardScreen> createState() => _OfficerDashboardScreenState();
}

class _OfficerDashboardScreenState extends ConsumerState<OfficerDashboardScreen> {
  final ApiClient _apiClient = ApiClient();
  final ImagePicker _picker = ImagePicker();

  int _currentNavIndex = 0; // 0: Requests, 1: Scanner (also center button), 2: Bulk Scan, 3: Trust Portal
  int _requestFilterIndex = 0; // 0: All, 1: Complaints, 2: AI Scans
  bool _showResolved = false;

  List<dynamic> _queue = [];
  bool _isLoading = true;

  List<dynamic> _trustRatings = [];
  bool _isTrustLoading = true;

  // --- Bulk Scanning State ---
  bool _isBulkScanning = false;
  int _bulkTotal = 0;
  int _bulkCompleted = 0;
  final List<Map<String, dynamic>> _bulkResults = [];

  @override
  void initState() {
    super.initState();
    _loadQueue();
    _loadTrustRatings();
  }

  Future<void> _loadQueue() async {
    try {
      final scansQueue = await _apiClient.fetchReviewQueue();
      final complaintsQueue = await _apiClient.fetchComplaints();

      final combinedQueue = [
        ...scansQueue.map((s) => {'type': 'SCAN', ...s}),
        ...complaintsQueue.map((c) => {'type': 'COMPLAINT', ...c}),
      ];

      combinedQueue.sort((a, b) {
        final dateA = a['created_at']?.toString() ?? '';
        final dateB = b['created_at']?.toString() ?? '';
        return dateB.compareTo(dateA);
      });

      if (mounted) {
        setState(() {
          _queue = combinedQueue;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _queue = [];
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load review queue: ${e.toString()}'),
            backgroundColor: AppTheme.dangerRed,
          ),
        );
      }
    }
  }

  Future<void> _loadTrustRatings() async {
    setState(() => _isTrustLoading = true);
    try {
      final ratings = await _apiClient.fetchManufacturerRatings();
      if (mounted) {
        setState(() {
          _trustRatings = ratings;
          _isTrustLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isTrustLoading = false);
      }
    }
  }

  Future<void> _handleDecision(String scanId, String decision) async {
    final auth = ref.read(authProvider);
    try {
      await _apiClient.submitReview(scanId, auth.userId, decision, 'Officer adjudication action');
      if (mounted) {
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
                Text('Scan marked as $decision.'),
              ],
            ),
            backgroundColor: decision == 'ACCEPT' ? AppTheme.successGreen : AppTheme.dangerRed,
            duration: const Duration(seconds: 2),
          ),
        );
        _loadQueue();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to record decision: $e'),
            backgroundColor: AppTheme.dangerRed,
          ),
        );
      }
    }
  }

  Future<void> _handleComplaintDecision(String complaintId, String decision) async {
    final auth = ref.read(authProvider);
    try {
      final status = decision == 'ACCEPT' ? 'RESOLVED' : 'REJECTED';
      await _apiClient.reviewComplaint(complaintId, auth.userId, status, 'Officer reviewed citizen grievance');
      if (mounted) {
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
                Text('Complaint $decision action recorded ($status).'),
              ],
            ),
            backgroundColor: decision == 'ACCEPT' ? AppTheme.successGreen : AppTheme.dangerRed,
            duration: const Duration(seconds: 2),
          ),
        );
        _loadQueue();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to record complaint review: $e'),
            backgroundColor: AppTheme.dangerRed,
          ),
        );
      }
    }
  }

  // --- Bulk Scanning Execution ---
  Future<void> _startBulkScanning() async {
    try {
      final List<XFile> pickedFiles = await _picker.pickMultiImage(imageQuality: 85);
      if (pickedFiles.isEmpty) return;

      setState(() {
        _isBulkScanning = true;
        _bulkTotal = pickedFiles.length;
        _bulkCompleted = 0;
        _bulkResults.clear();
      });

      final auth = ref.read(authProvider);

      for (int i = 0; i < pickedFiles.length; i++) {
        final file = pickedFiles[i];
        try {
          final uploadRes = await _apiClient.uploadScanImage(
            file.path,
            userId: auth.userId,
          );
          final String scanId = uploadRes['scan_id'];
          final scanResult = await _apiClient.processScan(scanId);

          if (mounted) {
            setState(() {
              _bulkCompleted = i + 1;
              _bulkResults.add({
                'file_path': file.path,
                'file_name': file.name,
                'status': 'SUCCESS',
                'scan_id': scanId,
                'result': scanResult,
              });
            });
          }
        } catch (err) {
          if (mounted) {
            setState(() {
              _bulkCompleted = i + 1;
              _bulkResults.add({
                'file_path': file.path,
                'file_name': file.name,
                'status': 'ERROR',
                'error': err.toString(),
              });
            });
          }
        }
      }

      if (mounted) {
        setState(() => _isBulkScanning = false);
        _loadQueue(); // Refresh queue with newly processed batch scans
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isBulkScanning = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Bulk scanning error: $e')),
        );
      }
    }
  }

  void _showManufacturerHistory(String manufacturerName) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator(color: AppTheme.emerald500)),
    );

    try {
      final data = await _apiClient.fetchManufacturerHistory(manufacturerName);
      if (mounted) {
        Navigator.pop(context);
        _buildHistoryDialog(data);
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading history: ${e.toString()}')),
        );
      }
    }
  }

  void _buildHistoryDialog(Map<String, dynamic> data) {
    showDialog(
      context: context,
      builder: (context) {
        final history = data['history'] as List<dynamic>? ?? [];
        return AlertDialog(
          backgroundColor: AppTheme.baseBackground,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(
            '${data['manufacturer_name']} History',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.slate900),
          ),
          content: SizedBox(
            width: double.maxFinite,
            height: 300,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Total Scans: ${data['total_scans']}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.slate800)),
                    Text('Score: ${data['compliance_score']}%', style: const TextStyle(fontSize: 12, color: AppTheme.emerald600, fontWeight: FontWeight.bold)),
                  ],
                ),
                const Divider(height: 20),
                Expanded(
                  child: history.isEmpty
                      ? const Center(child: Text('No historical data available', style: TextStyle(color: AppTheme.slate500)))
                      : ListView.builder(
                          itemCount: history.length,
                          itemBuilder: (context, index) {
                            final item = history[index];
                            final status = (item['status'] ?? 'UNKNOWN').toString();
                            final isPass = status == 'PASS' || status == 'COMPLIANT';
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                item['product_name'] ?? 'Unknown Product',
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.slate900),
                              ),
                              subtitle: Text(
                                item['date']?.toString().substring(0, 10) ?? '',
                                style: const TextStyle(fontSize: 11, color: AppTheme.slate500),
                              ),
                              trailing: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: isPass ? AppTheme.successGreen.withValues(alpha: 0.12) : AppTheme.dangerRed.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  status,
                                  style: TextStyle(
                                    color: isPass ? AppTheme.successGreen : AppTheme.dangerRed,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 10,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.slate900, foregroundColor: Colors.white),
              child: const Text('CLOSE'),
            ),
          ],
        );
      },
    );
  }

  // --- Main Build ---
  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);

    return Scaffold(
      body: AuraBackground(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: AppTheme.emerald500))
            : Stack(
                children: [
                  // Scrollable Content Body
                  Positioned.fill(
                    child: RefreshIndicator(
                      onRefresh: () async {
                        await _loadQueue();
                        await _loadTrustRatings();
                      },
                      color: AppTheme.emerald500,
                      child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Top Header with insignia
                            _buildHeader(auth),

                            const SizedBox(height: 12),

                            // Officer Status & Action Banner
                            _buildWelcomeBanner(auth),

                            const SizedBox(height: 14),

                            // Main Switchable View based on Bottom Nav
                            if (_currentNavIndex == 1) ...[
                              _buildScannerSection(),
                            ] else if (_currentNavIndex == 2) ...[
                              _buildBulkScanningSection(),
                            ] else if (_currentNavIndex == 3) ...[
                              _buildTrustPortalSection(),
                            ] else ...[
                              _buildIncomingRequestsSection(),
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

  // --- Top Header ---
  Widget _buildHeader(AuthState auth) {
    return NirikshakAppBar(
      badgeText: 'ENFORCEMENT WING',
      subtitle: 'Legal Metrology Statutory Enforcement',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: AppTheme.emerald50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.emerald200),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.badge_rounded, size: 13, color: AppTheme.emerald700),
                SizedBox(width: 4),
                Text(
                  'Raj',
                  style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: AppTheme.emerald800),
                ),
              ],
            ),
          ),
          const SizedBox(width: 5),
          GestureDetector(
            onTap: () => context.go('/login'),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.slate200),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.logout_rounded, size: 13, color: AppTheme.slate600),
                  SizedBox(width: 3),
                  Text(
                    'Exit',
                    style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: AppTheme.slate700),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- Welcome Banner ---
  Widget _buildWelcomeBanner(AuthState auth) {
    final pendingCount = _queue.where((i) {
      if (i['type'] == 'COMPLAINT') return i['status'] == 'SUBMITTED';
      return i['is_resolved'] != true;
    }).length;

    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      borderRadius: 18,
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppTheme.emerald50,
              shape: BoxShape.circle,
              border: Border.all(color: AppTheme.emerald200),
            ),
            child: const Center(
              child: Icon(Icons.shield_rounded, color: AppTheme.emerald600, size: 22),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Text(
                      'Officer Raj',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.slate900,
                      ),
                    ),
                    SizedBox(width: 6),
                    PulseIndicator(size: 7, color: AppTheme.emerald500),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  pendingCount > 0
                      ? '$pendingCount incoming request${pendingCount == 1 ? '' : 's'} awaiting your review'
                      : 'All incoming requests have been reviewed',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: pendingCount > 0 ? const Color(0xFFE11D48) : AppTheme.slate500,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: pendingCount > 0 ? const Color(0xFFFFF1F2) : AppTheme.emerald50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: pendingCount > 0 ? const Color(0xFFFECDD3) : AppTheme.emerald200,
              ),
            ),
            child: Text(
              '$pendingCount Pending',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: pendingCount > 0 ? const Color(0xFFBE123C) : AppTheme.emerald700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- 1. INCOMING REQUESTS SECTION (ACCEPT / REJECT) ---
  Widget _buildIncomingRequestsSection() {
    final allItems = _queue;
    final complaints = allItems.where((i) => i['type'] == 'COMPLAINT').toList();
    final scans = allItems.where((i) => i['type'] == 'SCAN').toList();

    List<dynamic> targetList;
    if (_requestFilterIndex == 1) {
      targetList = complaints;
    } else if (_requestFilterIndex == 2) {
      targetList = scans;
    } else {
      targetList = allItems;
    }

    final pending = targetList.where((i) {
      if (i['type'] == 'COMPLAINT') return i['status'] == 'SUBMITTED';
      return i['is_resolved'] != true;
    }).toList();

    final resolved = targetList.where((i) {
      if (i['type'] == 'COMPLAINT') return i['status'] != 'SUBMITTED';
      return i['is_resolved'] == true;
    }).toList();

    final displayItems = _showResolved ? resolved : pending;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Title & Segment
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Expanded(
              child: Row(
                children: [
                  Icon(Icons.inbox_rounded, size: 16, color: AppTheme.slate700),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'INCOMING REQUESTS',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.slate700,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Toggle Pending / Resolved
            Container(
              decoration: BoxDecoration(
                color: AppTheme.slate100,
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.all(2),
              child: Row(
                children: [
                  _buildToggleTab('Pending (${pending.length})', !_showResolved, () => setState(() => _showResolved = false)),
                  _buildToggleTab('Resolved (${resolved.length})', _showResolved, () => setState(() => _showResolved = true)),
                ],
              ),
            ),
          ],
        ),

        const SizedBox(height: 10),

        // Filter Pills: All / Citizen Overpricing / AI Scans
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _buildFilterChip('All Requests (${targetList.length})', 0),
              const SizedBox(width: 6),
              _buildFilterChip('Citizen Overpricing (${complaints.length})', 1),
              const SizedBox(width: 6),
              _buildFilterChip('AI Flagged Scans (${scans.length})', 2),
            ],
          ),
        ),

        const SizedBox(height: 12),

        if (displayItems.isEmpty)
          GlassCard(
            padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
            borderRadius: 18,
            child: Center(
              child: Column(
                children: [
                  Icon(
                    _showResolved ? Icons.fact_check_outlined : Icons.check_circle_outline_rounded,
                    size: 40,
                    color: AppTheme.emerald500,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _showResolved
                        ? 'No resolved requests found under this filter.'
                        : 'No pending requests! All clear.',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.slate800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Incoming citizen grievances and flagged scans will appear here.',
                    style: TextStyle(fontSize: 11, color: AppTheme.slate500),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: displayItems.length,
            itemBuilder: (context, index) {
              final item = displayItems[index];
              return _buildRequestCard(item);
            },
          ),
      ],
    );
  }

  Widget _buildToggleTab(String label, bool isActive, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isActive ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          boxShadow: isActive
              ? [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4)]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: isActive ? FontWeight.w800 : FontWeight.w500,
            color: isActive ? AppTheme.slate900 : AppTheme.slate500,
          ),
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, int index) {
    final bool isSelected = _requestFilterIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _requestFilterIndex = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.slate900 : Colors.white.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppTheme.slate900 : AppTheme.slate200,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 4,
            ),
          ],
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
            color: isSelected ? Colors.white : AppTheme.slate700,
          ),
        ),
      ),
    );
  }

  // --- Request Card with Accept / Reject ---
  Widget _buildRequestCard(Map<dynamic, dynamic> item) {
    final bool isComplaint = item['type'] == 'COMPLAINT';
    final String id = isComplaint
        ? (item['complaint_id'] ?? '').toString()
        : (item['scan_id'] ?? '').toString();
    final String shortId = id.length > 8 ? '${id.substring(0, 8)}...' : id;

    final bool isResolved = isComplaint
        ? item['status'] != 'SUBMITTED'
        : item['is_resolved'] == true;

    final status = (isComplaint ? item['status'] : (item['overall_compliance'] ?? 'REVIEW')).toString();
    final dateStr = item['created_at']?.toString() ?? '';
    final formattedDate = dateStr.length >= 10 ? dateStr.substring(0, 10) : dateStr;

    return GlassCard(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(15),
      borderRadius: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row: Type Badge + ID + Status
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: isComplaint
                      ? const Color(0xFFFFF1F2) // Rose
                      : const Color(0xFFFFFBEB), // Amber
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isComplaint ? const Color(0xFFFECDD3) : const Color(0xFFFDE68A),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isComplaint ? Icons.price_change_rounded : Icons.scanner_rounded,
                      size: 12,
                      color: isComplaint ? const Color(0xFFE11D48) : const Color(0xFFD97706),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isComplaint ? 'OVERPRICING GRIEVANCE' : 'AI DISCREPANCY SCAN',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: isComplaint ? const Color(0xFFBE123C) : const Color(0xFFB45309),
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '#$shortId',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.slate500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: isResolved
                      ? AppTheme.slate100
                      : (status == 'FAIL' || status == 'SUBMITTED'
                          ? AppTheme.dangerRed.withValues(alpha: 0.12)
                          : AppTheme.warningAmberLight),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  isResolved ? (item['decision'] ?? item['status'] ?? 'RESOLVED') : status,
                  style: TextStyle(
                    color: isResolved
                        ? AppTheme.slate500
                        : (status == 'FAIL' || status == 'SUBMITTED'
                            ? AppTheme.dangerRed
                            : AppTheme.warningAmber),
                    fontWeight: FontWeight.bold,
                    fontSize: 9.5,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // Content Details
          if (isComplaint) ...[
            Text(
              item['shopkeeper_name'] ?? 'Retail Store / Vendor',
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 14,
                color: AppTheme.slate900,
              ),
            ),
            if (item['shop_address'] != null && item['shop_address'].toString().isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                item['shop_address'].toString(),
                style: const TextStyle(fontSize: 11, color: AppTheme.slate500),
              ),
            ],
            const SizedBox(height: 8),

            // Price Comparison Pill
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF1F2),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFECDD3)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('PAID AMOUNT', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFFBE123C))),
                        Text('₹${item['paid_price']}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Color(0xFFE11D48))),
                      ],
                    ),
                  ),
                  Container(width: 1, height: 26, color: const Color(0xFFFECDD3)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('PRINTED MRP', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: AppTheme.slate500)),
                        Text('₹${item['printed_mrp']}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppTheme.slate700)),
                      ],
                    ),
                  ),
                  if (item['paid_price'] != null && item['printed_mrp'] != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE11D48),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '+₹${((double.tryParse(item['paid_price'].toString()) ?? 0) - (double.tryParse(item['printed_mrp'].toString()) ?? 0)).toStringAsFixed(0)}',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            if (item['description'] != null && item['description'].toString().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Notes: ${item['description']}',
                style: const TextStyle(fontSize: 11.5, color: AppTheme.slate700),
              ),
            ],
          ] else ...[
            // AI Scan Details
            Text(
              item['generic_product_name'] ?? item['product_name'] ?? 'Pre-Packaged Commodity',
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 14,
                color: AppTheme.slate900,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              item['manufacturer_name'] ?? 'Manufacturer Identity Recorded',
              style: const TextStyle(fontSize: 11, color: AppTheme.slate500),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.slate100,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.slate200),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline_rounded, size: 14, color: AppTheme.slate600),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      item['reason'] ?? 'AI Flagged compliance discrepancy requiring officer review under LMPC Rules.',
                      style: const TextStyle(fontSize: 11.5, color: AppTheme.slate700),
                    ),
                  ),
                ],
              ),
            ),
            if (item['manufacturer_name'] != null) ...[
              const SizedBox(height: 6),
              GestureDetector(
                onTap: () => _showManufacturerHistory(item['manufacturer_name']),
                child: Text(
                  'View ${item['manufacturer_name']} Trust History →',
                  style: const TextStyle(color: AppTheme.emerald600, fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ],

          const SizedBox(height: 12),

          // Action Buttons: Accept / Reject OR Full Details Button
          Row(
            children: [
              // Inspect Full Details Button
              Expanded(
                flex: 3,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final refreshed = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => DetailsScreen(
                          item: Map<String, dynamic>.from(item),
                          isOfficer: true,
                        ),
                      ),
                    );
                    if (refreshed == true) {
                      _loadQueue();
                    }
                  },
                  icon: const Icon(Icons.visibility_outlined, size: 13, color: AppTheme.slate800),
                  label: const Text(
                    'INSPECT',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppTheme.slate800),
                  ),
                  style: OutlinedButton.styleFrom(
                    minimumSize: Size.zero,
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                    side: const BorderSide(color: AppTheme.slate300),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),

              if (!isResolved) ...[
                const SizedBox(width: 6),

                // ACCEPT Button
                Expanded(
                  flex: 4,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      if (isComplaint) {
                        _handleComplaintDecision(id, 'ACCEPT');
                      } else {
                        _handleDecision(id, 'ACCEPT');
                      }
                    },
                    icon: const Icon(Icons.check_circle_rounded, size: 13, color: Colors.white),
                    label: const Text(
                      'ACCEPT',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Colors.white),
                    ),
                    style: ElevatedButton.styleFrom(
                      minimumSize: Size.zero,
                      backgroundColor: AppTheme.emerald600,
                      foregroundColor: Colors.white,
                      elevation: 1,
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),

                const SizedBox(width: 6),

                // REJECT Button
                Expanded(
                  flex: 4,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      if (isComplaint) {
                        _handleComplaintDecision(id, 'REJECT');
                      } else {
                        _handleDecision(id, 'REJECT');
                      }
                    },
                    icon: const Icon(Icons.cancel_rounded, size: 13, color: Colors.white),
                    label: const Text(
                      'REJECT',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Colors.white),
                    ),
                    style: ElevatedButton.styleFrom(
                      minimumSize: Size.zero,
                      backgroundColor: AppTheme.dangerRed,
                      foregroundColor: Colors.white,
                      elevation: 1,
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ],
          ),

          if (formattedDate.isNotEmpty) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                'Received: $formattedDate',
                style: const TextStyle(fontSize: 9.5, color: AppTheme.slate400),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // --- 2. SINGLE SCANNER SECTION ---
  Widget _buildScannerSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GlassCard(
          padding: const EdgeInsets.all(16),
          borderRadius: 20,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Icon(Icons.qr_code_scanner_rounded, size: 16, color: AppTheme.slate700),
                        SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'ON-SITE ENFORCEMENT SCANNER',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.slate700,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Multi-Face Inspection',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: AppTheme.slate500),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Viewfinder frame identical to citizen design
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                decoration: BoxDecoration(
                  color: const Color(0xEE0F172A),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0x33475569)),
                  boxShadow: const [
                    BoxShadow(color: Color(0x40000000), blurRadius: 12, offset: Offset(0, 4)),
                  ],
                ),
                child: Column(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: const Color(0x1A10B981),
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0x4D10B981)),
                      ),
                      child: const Center(
                        child: Icon(Icons.document_scanner_rounded, color: AppTheme.emerald400, size: 26),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Ready for Package Verification',
                      style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Scan 4 faces (Front, Back, Left, Right) to evaluate LMPC Rule 6 statutory declarations.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () => context.push('/scan'),
                        icon: const Icon(Icons.camera_alt_rounded, size: 16, color: Colors.white),
                        label: const Text(
                          'LAUNCH ENFORCEMENT CAMERA',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.emerald600,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 14),

        // Quick checklist card
        GlassCard(
          padding: const EdgeInsets.all(16),
          borderRadius: 18,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'LMPC STATUTORY VERIFICATION CHECKLIST',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppTheme.slate700),
              ),
              const SizedBox(height: 8),
              _buildCheckItem('Rule 6(1)(a)', 'Manufacturer / Packer name & complete physical address with PIN code'),
              _buildCheckItem('Rule 6(1)(c)', 'Net Quantity declared in standard metric units (g, kg, ml, l) with USP'),
              _buildCheckItem('Rule 6(1)(e)', 'Maximum Retail Price (MRP) inclusive of all taxes in Rupees (₹)'),
              _buildCheckItem('Rule 6(1)(d)', 'Month and Year of manufacture or packing'),
              _buildCheckItem('Rule 6(8)', 'Complete Consumer Care phone, email, and grievance address'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCheckItem(String rule, String desc) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: AppTheme.slate100,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: AppTheme.slate200),
            ),
            child: Text(rule, style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: AppTheme.slate800)),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(desc, style: const TextStyle(fontSize: 11, color: AppTheme.slate600))),
        ],
      ),
    );
  }

  // --- 3. BULK SCANNING SUITE ---
  Widget _buildBulkScanningSection() {
    final int compliantCount = _bulkResults.where((r) {
      final res = r['result'] as Map<String, dynamic>?;
      final st = (res?['overall_compliance'] ?? '').toString().toUpperCase();
      return st == 'PASS' || st == 'COMPLIANT';
    }).length;

    final int violationCount = _bulkResults.where((r) {
      final res = r['result'] as Map<String, dynamic>?;
      final st = (res?['overall_compliance'] ?? '').toString().toUpperCase();
      return st == 'FAIL' || r['status'] == 'ERROR';
    }).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Bulk Scanner Launcher Card
        GlassCard(
          padding: const EdgeInsets.all(16),
          borderRadius: 20,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.dynamic_feed_rounded, size: 16, color: AppTheme.slate700),
                  SizedBox(width: 6),
                  Text(
                    'BULK INSPECTION SUITE',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.slate700,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'Select multiple product packaging images or invoices to run automated parallel LMPC compliance audits.',
                style: TextStyle(fontSize: 11.5, color: AppTheme.slate500),
              ),
              const SizedBox(height: 14),

              if (_isBulkScanning) ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.emerald50,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppTheme.emerald200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              'Processing $_bulkCompleted of $_bulkTotal Packages...',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: AppTheme.emerald800),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.emerald600),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: _bulkTotal > 0 ? _bulkCompleted / _bulkTotal : 0,
                          backgroundColor: AppTheme.emerald100,
                          color: AppTheme.emerald600,
                          minHeight: 6,
                        ),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _startBulkScanning,
                    icon: const Icon(Icons.add_photo_alternate_rounded, size: 18, color: Colors.white),
                    label: const Text(
                      'SELECT MULTIPLE PACKAGES (GALLERY)',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.slate900,
                      foregroundColor: Colors.white,
                      elevation: 2,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 14),

        // Bulk Summary Metrics (if results exist)
        if (_bulkResults.isNotEmpty) ...[
          Row(
            children: [
              Expanded(
                child: _buildMetricCard('TOTAL SCANNED', '${_bulkResults.length}', AppTheme.slate900, Icons.inventory_2_outlined),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMetricCard('COMPLIANT', '$compliantCount', AppTheme.successGreen, Icons.check_circle_outline_rounded),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMetricCard('VIOLATIONS', '$violationCount', AppTheme.dangerRed, Icons.warning_amber_rounded),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Bulk Results List
          const Text(
            'BATCH AUDIT RESULTS',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppTheme.slate700, letterSpacing: 0.8),
          ),
          const SizedBox(height: 8),

          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _bulkResults.length,
            itemBuilder: (context, index) {
              final item = _bulkResults[index];
              final scanResult = item['result'] as Map<String, dynamic>?;
              final status = (scanResult?['overall_compliance'] ?? (item['status'] == 'ERROR' ? 'FAIL' : 'REVIEW')).toString();
              final isPass = status == 'PASS' || status == 'COMPLIANT';

              final declarations = (scanResult?['extracted_declarations'] as Map?) ?? {};
              final prodName = declarations['generic_product_name'] ?? declarations['product_name'] ?? item['file_name'];
              final mrp = declarations['mrp']?.toString();

              return GlassCard(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                borderRadius: 16,
                onTap: scanResult != null
                    ? () async {
                        final refreshed = await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => DetailsScreen(
                              item: scanResult,
                              isOfficer: true,
                            ),
                          ),
                        );
                        if (refreshed == true) {
                          _loadQueue();
                        }
                      }
                    : null,
                child: Row(
                  children: [
                    // Thumbnail
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.file(
                        File(item['file_path']),
                        width: 48,
                        height: 48,
                        fit: BoxFit.cover,
                        errorBuilder: (ctx, err, stack) => Container(
                          width: 48,
                          height: 48,
                          color: AppTheme.slate100,
                          child: const Icon(Icons.image, size: 20, color: AppTheme.slate400),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            prodName.toString(),
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.slate900),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            mrp != null ? 'Printed MRP: ₹$mrp' : 'Package #${index + 1}',
                            style: const TextStyle(fontSize: 11, color: AppTheme.slate500),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: isPass ? AppTheme.successGreen.withValues(alpha: 0.12) : AppTheme.dangerRed.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        isPass ? 'COMPLIANT' : 'NON-COMPLIANT',
                        style: TextStyle(
                          color: isPass ? AppTheme.successGreen : AppTheme.dangerRed,
                          fontWeight: FontWeight.bold,
                          fontSize: 9.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(Icons.chevron_right_rounded, size: 18, color: AppTheme.slate400),
                  ],
                ),
              );
            },
          ),
        ],
      ],
    );
  }

  Widget _buildMetricCard(String label, String value, Color color, IconData icon) {
    return GlassCard(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
      borderRadius: 14,
      child: Column(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: color),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: AppTheme.slate500),
          ),
        ],
      ),
    );
  }

  // --- 4. TRUST PORTAL SECTION ---
  Widget _buildTrustPortalSection() {
    if (_isTrustLoading) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.emerald500));
    }
    if (_trustRatings.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text('No manufacturer trust records available.', style: TextStyle(color: AppTheme.slate500)),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'MANUFACTURER TRUST RATINGS',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppTheme.slate700, letterSpacing: 0.8),
        ),
        const SizedBox(height: 10),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _trustRatings.length,
          itemBuilder: (context, index) {
            final mfg = _trustRatings[index];
            final rating = mfg['rating'] ?? 'B';
            final score = mfg['compliance_score'] ?? 0;

            Color ratingColor = AppTheme.successGreen;
            if (rating == 'C' || rating == 'D') ratingColor = AppTheme.warningOrange;
            if (rating == 'F') ratingColor = AppTheme.dangerRed;

            return GlassCard(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              borderRadius: 16,
              onTap: () => _showManufacturerHistory(mfg['manufacturer_name']),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: ratingColor.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        rating,
                        style: TextStyle(color: ratingColor, fontWeight: FontWeight.w900, fontSize: 16),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          mfg['manufacturer_name'] ?? 'Unknown',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.slate900),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Total Audits: ${mfg['total_scans'] ?? 0} | Score: $score%',
                          style: const TextStyle(fontSize: 11, color: AppTheme.slate500),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AppTheme.slate400),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  // --- Floating Bottom Navigation Dock ---
  Widget _buildFloatingBottomNav() {
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      borderRadius: 24,
      backgroundColor: Colors.white.withValues(alpha: 0.88),
      child: Row(
        children: [
          Expanded(
            child: _buildNavItem(
              icon: Icons.inbox_rounded,
              label: 'Requests',
              isActive: _currentNavIndex == 0,
              onTap: () => setState(() => _currentNavIndex = 0),
            ),
          ),
          Expanded(
            child: _buildNavItem(
              icon: Icons.layers_rounded,
              label: 'Bulk Scan',
              isActive: _currentNavIndex == 2,
              onTap: () => setState(() => _currentNavIndex = 2),
            ),
          ),
          // Center Elevated Circular Scanner Button
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
              icon: Icons.center_focus_strong_rounded,
              label: 'Field Scan',
              isActive: _currentNavIndex == 1,
              onTap: () => setState(() => _currentNavIndex = 1),
            ),
          ),
          Expanded(
            child: _buildNavItem(
              icon: Icons.verified_user_outlined,
              label: 'Trust',
              isActive: _currentNavIndex == 3,
              onTap: () => setState(() => _currentNavIndex = 3),
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
