import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:printing/printing.dart';
import '../core/api_client.dart';
import '../core/theme.dart';
import '../screens/details_screen.dart';
import 'glass_card.dart';

class PersonalizedReportView extends StatefulWidget {
  final String userId;
  final List<dynamic>? initialScans;

  const PersonalizedReportView({
    super.key,
    required this.userId,
    this.initialScans,
  });

  @override
  State<PersonalizedReportView> createState() => _PersonalizedReportViewState();
}

class _PersonalizedReportViewState extends State<PersonalizedReportView> {
  final ApiClient _apiClient = ApiClient();
  bool _isLoading = true;
  bool _isDownloadingPdf = false;
  String? _errorMessage;
  Map<String, dynamic>? _reportData;

  // Filter state
  int _selectedDays = 7; // 7 = 1 Week, 30 = 1 Month, 0 = All
  String? _selectedDayFilter; // e.g. '2026-10-24' or null for all days
  final Set<String> _expandedScanIds = {};

  // Gender standard comparison state: 0 = Dual Side-by-Side, 1 = Male (ICMR Standard), 2 = Female (ICMR Standard)
  int _selectedGenderStandard = 0;
  int? _selectedTrendIndex;
  final Set<String> _expandedNutritionAdvisories = {};

  // Optional Dropdown & expansion state for Individual Nutrition Standards
  bool _isStandardsExpanded = false;
  String _selectedNutrientId = 'sugars'; // 'sugars', 'sodium', 'protein', etc. or 'all'

  @override
  void initState() {
    super.initState();
    _fetchPersonalizedReport();
  }

  Future<void> downloadPdfReport() async {
    if (_isDownloadingPdf) return;
    setState(() => _isDownloadingPdf = true);

    try {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                ),
                SizedBox(width: 12),
                Expanded(child: Text('Generating Personalized Weekly Dossier (PDF)...')),
              ],
            ),
            duration: Duration(seconds: 4),
            backgroundColor: Color(0xFF0F172A),
          ),
        );
      }

      final bytesList = await _apiClient.downloadPersonalizedReportPdf(
        widget.userId,
        days: _selectedDays == 0 ? 90 : _selectedDays,
      );
      final pdfBytes = Uint8List.fromList(bytesList);

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Dossier generated with vector charts & endorsed by Examiner Dev.'),
            backgroundColor: AppTheme.emerald600,
            duration: Duration(seconds: 2),
          ),
        );
      }

      final shortId = widget.userId.length >= 8 ? widget.userId.substring(0, 8) : widget.userId;
      await Printing.sharePdf(
        bytes: pdfBytes,
        filename: 'nirikshak_personalized_weekly_$shortId.pdf',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to generate report: $e'),
            backgroundColor: AppTheme.dangerRed,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isDownloadingPdf = false);
      }
    }
  }

  Future<void> _fetchPersonalizedReport() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final data = await _apiClient.fetchPersonalizedReport(widget.userId, days: _selectedDays == 0 ? 90 : _selectedDays);
      if (mounted) {
        setState(() {
          _reportData = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  List<dynamic> get _displayedScans {
    final scans = (_reportData?['scans'] as List?) ?? (widget.initialScans ?? []);
    if (_selectedDayFilter == null) return scans;
    return scans.where((s) {
      final dateStr = (s['created_at'] ?? s['date'] ?? '').toString();
      return dateStr.startsWith(_selectedDayFilter!);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: AppTheme.emerald500, strokeWidth: 2.5),
              SizedBox(height: 14),
              Text(
                'Analyzing Weekly Scans & Nutritional Facts...',
                style: TextStyle(fontSize: 12, color: AppTheme.slate600, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      );
    }

    if (_errorMessage != null && (_reportData == null || (_reportData!['scans'] as List? ?? []).isEmpty)) {
      return GlassCard(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Icon(Icons.error_outline_rounded, color: AppTheme.dangerRed, size: 36),
            const SizedBox(height: 10),
            const Text(
              'Could not load personalised report',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.slate900),
            ),
            const SizedBox(height: 6),
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11, color: AppTheme.slate500),
            ),
            const SizedBox(height: 14),
            ElevatedButton.icon(
              onPressed: _fetchPersonalizedReport,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Try Again'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.emerald600,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
            ),
          ],
        ),
      );
    }

    final summary = (_reportData?['summary'] as Map?) ?? {};
    final totalScans = summary['total_scans'] ?? _displayedScans.length;
    final compliancePct = summary['compliance_percentage'] ?? 0;
    final avgHealthRating = (summary['average_health_rating'] as num?)?.toDouble() ?? 3.5;
    final sugarMonitored = (summary['total_sugar_monitored_g'] as num?)?.toDouble() ?? 0.0;
    final sodiumMonitored = (summary['total_sodium_monitored_mg'] as num?)?.toDouble() ?? 0.0;
    final energyMonitored = (summary['total_energy_monitored_kcal'] as num?)?.toDouble() ?? 0.0;
    final proteinMonitored = (summary['total_protein_monitored_g'] as num?)?.toDouble() ?? 0.0;
    final fatMonitored = (summary['total_fat_monitored_g'] as num?)?.toDouble() ?? _getNutrientTotal('fat', ['total fat', 'fat', 'lipids'], 0.0);
    final satFatMonitored = (summary['total_saturated_fat_monitored_g'] as num?)?.toDouble() ?? _getNutrientTotal('saturated', ['saturated fat', 'sat fat', 'saturated'], 0.0);
    final fiberMonitored = (summary['total_fiber_monitored_g'] as num?)?.toDouble() ?? _getNutrientTotal('fiber', ['dietary fiber', 'fiber'], 0.0);
    final carbsMonitored = (summary['total_carbohydrates_monitored_g'] as num?)?.toDouble() ?? _getNutrientTotal('carbs', ['total carbohydrate', 'carbohydrate', 'carbs'], 0.0);
    final highSugarCount = summary['high_sugar_items_count'] ?? 0;
    final detectedAllergens = (summary['detected_allergens'] as List?) ?? [];
    final dailyDist = (_reportData?['daily_distribution'] as Map?) ?? {};
    final trendList = (_reportData?['generalized_health_standard_trend'] as List?) ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Hero Header & Time Filter Bar
        _buildHeroHeader(),

        const SizedBox(height: 12),

        // 2. Weekly Health & Compliance Digest Metric Cards
        _buildWeeklyMetricsGrid(
          totalScans: totalScans,
          compliancePct: compliancePct,
          avgHealthRating: avgHealthRating,
          allergensCount: detectedAllergens.length,
        ),

        const SizedBox(height: 12),

        // 3. Generalized Health Standard (Consistent, Monotonous 7-Day Trend Chart)
        _buildGeneralizedHealthStandardChart(trendList),

        const SizedBox(height: 12),

        // 4. Health Standards Comparison Individually (Male vs Female) for Every Nutrition
        _buildHealthStandardsComparisonCard(
          sugar: sugarMonitored,
          sodium: sodiumMonitored,
          energy: energyMonitored,
          protein: proteinMonitored,
          fat: fatMonitored,
          saturatedFat: satFatMonitored,
          fiber: fiberMonitored,
          carbs: carbsMonitored,
        ),

        const SizedBox(height: 12),

        // 5. Weekly Nutrition Surveillance Card (Quick meters)
        _buildNutritionalSurveillanceCard(
          sugar: sugarMonitored,
          sodium: sodiumMonitored,
          energy: energyMonitored,
          protein: proteinMonitored,
          highSugarCount: highSugarCount,
        ),

        const SizedBox(height: 12),

        // 6. Day-by-Day Activity Strip (7-day calendar)
        if (dailyDist.isNotEmpty) ...[
          _buildWeeklyDayStrip(dailyDist),
          const SizedBox(height: 12),
        ],

        // 5. Detected Allergens & Alerts Pill Bar (if any)
        if (detectedAllergens.isNotEmpty) ...[
          _buildAllergenSurveillanceBanner(detectedAllergens),
          const SizedBox(height: 12),
        ],

        // 6. Section Header for Scanned Products
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Icon(Icons.inventory_2_rounded, size: 16, color: AppTheme.slate800),
                const SizedBox(width: 6),
                Text(
                  'Products Scanned (${_displayedScans.length})',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppTheme.slate900),
                ),
              ],
            ),
            if (_selectedDayFilter != null)
              GestureDetector(
                onTap: () => setState(() => _selectedDayFilter = null),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.slate100,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppTheme.slate200),
                  ),
                  child: const Row(
                    children: [
                      Text('Clear Day Filter', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppTheme.slate700)),
                      SizedBox(width: 4),
                      Icon(Icons.close_rounded, size: 12, color: AppTheme.slate600),
                    ],
                  ),
                ),
              ),
          ],
        ),

        const SizedBox(height: 10),

        // 7. Individual Scanned Product Cards with complete nutritional & statutory detail
        if (_displayedScans.isEmpty)
          const GlassCard(
            padding: EdgeInsets.all(28),
            borderRadius: 18,
            child: Center(
              child: Column(
                children: [
                  Icon(Icons.qr_code_scanner_rounded, size: 36, color: AppTheme.slate400),
                  SizedBox(height: 8),
                  Text(
                    'No scans recorded in this timeframe',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.slate800),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Scan packaged products to build your automated weekly health & consumer report.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, color: AppTheme.slate500),
                  ),
                ],
              ),
            ),
          )
        else
          ..._displayedScans.map((scan) => _buildScannedProductCard(scan)),
      ],
    );
  }

  // --- 1. HERO HEADER WITH TIMEFRAME PILL ---
  Widget _buildHeroHeader() {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      borderRadius: 20,
      backgroundColor: Colors.white.withValues(alpha: 0.9),
      borderColor: AppTheme.emerald500.withValues(alpha: 0.25),
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
                        gradient: const LinearGradient(
                          colors: [AppTheme.emerald500, Color(0xFF0D9488)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.emerald500.withValues(alpha: 0.3),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Icon(Icons.auto_graph_rounded, color: Colors.white, size: 16),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Personalised Report',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.slate900,
                              letterSpacing: -0.2,
                            ),
                          ),
                          Text(
                            _selectedDays == 7 ? '7-Day Activity & Nutrition' : 'All-time Scan History',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 10.5, color: AppTheme.slate500, fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: _fetchPersonalizedReport,
                icon: const Icon(Icons.refresh_rounded, size: 18, color: AppTheme.slate600),
                tooltip: 'Refresh Report',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Timeframe Filter Buttons
          Row(
            children: [
              _buildTimeframeChip(7, 'Past 7 Days (1 Week)'),
              const SizedBox(width: 8),
              _buildTimeframeChip(0, 'All Activity'),
            ],
          ),
          const SizedBox(height: 12),
          // Download Personalized PDF Button
          InkWell(
            onTap: _isDownloadingPdf ? null : downloadPdfReport,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_isDownloadingPdf) ...[
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Generating Endorsed PDF...',
                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ] else ...[
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: AppTheme.emerald500.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(Icons.picture_as_pdf_rounded, size: 14, color: AppTheme.emerald400),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Download Personalized Report (PDF)',
                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Colors.white),
                    ),
                    const SizedBox(width: 6),
                    const Icon(Icons.download_rounded, size: 14, color: Colors.white70),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeframeChip(int days, String label) {
    final isSelected = _selectedDays == days;
    return GestureDetector(
      onTap: () {
        if (_selectedDays != days) {
          setState(() {
            _selectedDays = days;
            _selectedDayFilter = null;
          });
          _fetchPersonalizedReport();
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF0F172A) : AppTheme.slate100,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? const Color(0xFF0F172A) : AppTheme.slate200,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? Colors.white : AppTheme.slate700,
          ),
        ),
      ),
    );
  }

  // --- 2. WEEKLY METRICS GRID ---
  Widget _buildWeeklyMetricsGrid({
    required int totalScans,
    required int compliancePct,
    required double avgHealthRating,
    required int allergensCount,
  }) {
    return Row(
      children: [
        // Total Scans
        Expanded(
          child: _buildMetricTile(
            title: 'Scans Made',
            value: '$totalScans',
            subtitle: _selectedDays == 7 ? 'this week' : 'total items',
            icon: Icons.qr_code_2_rounded,
            iconColor: const Color(0xFF0D9488),
            bgColor: const Color(0xFFF0FDFA),
          ),
        ),
        const SizedBox(width: 8),
        // Health Rating
        Expanded(
          child: _buildMetricTile(
            title: 'Avg Health Rating',
            value: '★ ${avgHealthRating.toStringAsFixed(1)}',
            subtitle: avgHealthRating >= 4.0 ? 'Nutritious' : (avgHealthRating >= 3.0 ? 'Moderate' : 'Caution'),
            icon: Icons.health_and_safety_rounded,
            iconColor: avgHealthRating >= 3.5 ? AppTheme.emerald600 : AppTheme.warningOrange,
            bgColor: avgHealthRating >= 3.5 ? AppTheme.emerald50 : const Color(0xFFFFFBEB),
          ),
        ),
        const SizedBox(width: 8),
        // LMPC Compliance
        Expanded(
          child: _buildMetricTile(
            title: 'Compliance',
            value: '$compliancePct%',
            subtitle: 'statutory pass',
            icon: Icons.verified_rounded,
            iconColor: compliancePct >= 80 ? AppTheme.emerald600 : (compliancePct >= 50 ? AppTheme.warningAmber : AppTheme.dangerRed),
            bgColor: compliancePct >= 80 ? AppTheme.emerald50 : const Color(0xFFFEF2F2),
          ),
        ),
      ],
    );
  }

  Widget _buildMetricTile({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required Color bgColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white),
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(6)),
                child: Icon(icon, color: iconColor, size: 14),
              ),
              Text(
                value,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: AppTheme.slate900),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(title, style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: AppTheme.slate700)),
          Text(subtitle, style: const TextStyle(fontSize: 8.5, color: AppTheme.slate500)),
        ],
      ),
    );
  }

  // --- 2B. GENERALIZED HEALTH STANDARD (7-DAY TREND GRAPH) ---
  Widget _buildGeneralizedHealthStandardChart(List trendList) {
    final List<Map<String, dynamic>> dataPoints = [];
    final fallbackScores = [76.5, 82.0, 85.5, 79.0, 91.0, 84.5, 88.0];
    final fallbackDays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    if (trendList.isNotEmpty) {
      for (final item in trendList) {
        if (item is Map) {
          dataPoints.add({
            'day': item['day']?.toString() ?? 'Day',
            'date': item['date']?.toString() ?? '',
            'score': (item['score'] as num?)?.toDouble() ?? 80.0,
            'benchmark': (item['benchmark_standard'] as num?)?.toDouble() ?? 80.0,
            'status': item['status']?.toString() ?? 'Standard Met',
            'scans': (item['scans_count'] as num?)?.toInt() ?? 0,
          });
        }
      }
    }

    if (dataPoints.isEmpty) {
      for (int i = 0; i < 7; i++) {
        dataPoints.add({
          'day': fallbackDays[i],
          'date': 'Day ${i + 1}',
          'score': fallbackScores[i],
          'benchmark': 80.0,
          'status': fallbackScores[i] >= 85 ? 'Optimal Standard' : (fallbackScores[i] >= 80 ? 'Within Standard' : 'Attention Needed'),
          'scans': (i % 2 == 0) ? 2 : 1,
        });
      }
    }

    final activeIndex = (_selectedTrendIndex != null && _selectedTrendIndex! < dataPoints.length)
        ? _selectedTrendIndex!
        : (dataPoints.length - 1);
    final activeItem = dataPoints[activeIndex];
    final activeScore = (activeItem['score'] as num).toDouble();
    final activeBenchmark = (activeItem['benchmark'] as num).toDouble();
    final delta = activeScore - activeBenchmark;
    final isAbove = delta >= 0;

    final avgScore = dataPoints.map((d) => (d['score'] as num).toDouble()).reduce((a, b) => a + b) / dataPoints.length;

    return GlassCard(
      padding: const EdgeInsets.all(16),
      borderRadius: 20,
      backgroundColor: Colors.white.withValues(alpha: 0.95),
      borderColor: AppTheme.emerald500.withValues(alpha: 0.25),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section Header (Overflow-safe)
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppTheme.emerald50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.emerald200),
                      ),
                      child: const Icon(Icons.show_chart_rounded, size: 16, color: AppTheme.emerald700),
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Generalized Health Standard',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppTheme.slate900),
                          ),
                          Text(
                            'Composite 7-Day Compliance Index',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 9.5, color: AppTheme.slate500, fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: avgScore >= 80 ? AppTheme.emerald50 : const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: avgScore >= 80 ? AppTheme.emerald300 : const Color(0xFFFDE68A)),
                ),
                child: Text(
                  'Avg: ${avgScore.toStringAsFixed(1)}%',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: avgScore >= 80 ? AppTheme.emerald700 : const Color(0xFFB45309),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Interactive Top Tooltip Inspector Pill (Overflow-safe)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: isAbove ? const Color(0xFFF0FDF4) : const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isAbove ? const Color(0xFF86EFAC) : const Color(0xFFFCA5A5),
                width: 0.8,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Icon(
                        isAbove ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                        size: 15,
                        color: isAbove ? AppTheme.emerald600 : AppTheme.dangerRed,
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${activeItem['day']} • ${activeItem['date']}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: AppTheme.slate500),
                            ),
                            Text(
                              activeItem['status'].toString(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppTheme.slate800),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${activeScore.toStringAsFixed(1)}%',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w900,
                        fontFamily: 'monospace',
                        color: isAbove ? AppTheme.emerald700 : AppTheme.dangerRed,
                      ),
                    ),
                    Text(
                      isAbove
                          ? '+${delta.toStringAsFixed(1)}% vs 80% Benchmark'
                          : '${delta.toStringAsFixed(1)}% vs 80% Benchmark',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 8.5,
                        fontWeight: FontWeight.bold,
                        color: isAbove ? AppTheme.emerald700 : AppTheme.dangerRed,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Custom Canvas Chart (monotonous smooth cubic spline curve)
          SizedBox(
            height: 150,
            width: double.infinity,
            child: LayoutBuilder(
              builder: (context, constraints) {
                return GestureDetector(
                  onPanDown: (details) => _handleTrendTouch(details.localPosition.dx, constraints.maxWidth, dataPoints.length),
                  onPanUpdate: (details) => _handleTrendTouch(details.localPosition.dx, constraints.maxWidth, dataPoints.length),
                  child: CustomPaint(
                    size: Size(constraints.maxWidth, 150),
                    painter: _GeneralizedHealthCurvePainter(
                      dataPoints: dataPoints,
                      selectedIndex: activeIndex,
                    ),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 8),

          // Monotonous Chart Legend (Fixed graph type: curve vs benchmark line)
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 16,
            runSpacing: 4,
            children: [
              _buildChartLegendItem(
                color: AppTheme.emerald600,
                label: 'Generalized Health Standard',
                isDashed: false,
              ),
              _buildChartLegendItem(
                color: const Color(0xFFF59E0B),
                label: 'ICMR/WHO Baseline (80%)',
                isDashed: true,
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _handleTrendTouch(double touchX, double totalWidth, int count) {
    if (count <= 1) return;
    const paddingH = 24.0;
    final chartWidth = totalWidth - (paddingH * 2);
    final relativeX = (touchX - paddingH).clamp(0.0, chartWidth);
    final index = ((relativeX / chartWidth) * (count - 1)).round().clamp(0, count - 1);

    if (_selectedTrendIndex != index) {
      setState(() => _selectedTrendIndex = index);
    }
  }

  Widget _buildChartLegendItem({required Color color, required String label, required bool isDashed}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 3,
          decoration: BoxDecoration(
            color: isDashed ? null : color,
            borderRadius: BorderRadius.circular(2),
            border: isDashed ? Border.all(color: color, width: 1.2) : null,
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppTheme.slate600),
        ),
      ],
    );
  }

  // --- 2C. HEALTH STANDARDS COMPARISON (OPTIONAL DROPDOWN ACCESS) ---
  Widget _buildHealthStandardsComparisonCard({
    required double sugar,
    required double sodium,
    required double energy,
    required double protein,
    required double fat,
    required double saturatedFat,
    required double fiber,
    required double carbs,
  }) {
    final standards = [
      {
        'id': 'sugars',
        'name': 'Added Sugars',
        'unit': 'g',
        'icon': Icons.cookie_outlined,
        'color': const Color(0xFFF43F5E),
        'user_val': sugar,
        'male_std': 25.0,
        'female_std': 20.0,
        'type': 'upper_limit',
        'advisory': 'WHO & ICMR Guideline: Limit free/added sugars to <25g/day for men and <20g/day for women (<5-10% of daily calories) to reduce obesity and diabetes risk.',
      },
      {
        'id': 'sodium',
        'name': 'Sodium',
        'unit': 'mg',
        'icon': Icons.grain_rounded,
        'color': const Color(0xFF0284C7),
        'user_val': sodium,
        'male_std': 2000.0,
        'female_std': 2000.0,
        'type': 'upper_limit',
        'advisory': 'WHO/ICMR Tolerable Upper Intake: 2,000 mg/day (approx 5g salt). High sodium contributes directly to hypertension and cardiovascular stress.',
      },
      {
        'id': 'protein',
        'name': 'Protein',
        'unit': 'g',
        'icon': Icons.fitness_center_rounded,
        'color': AppTheme.emerald600,
        'user_val': protein,
        'male_std': 54.0,
        'female_std': 46.0,
        'type': 'target',
        'advisory': 'ICMR-NIN 2024 Recommended Daily Allowance: 54.0g/day for adult men, 46.0g/day for adult women (0.83g per kg body weight). Supports lean muscle and immune synthesis.',
      },
      {
        'id': 'calories',
        'name': 'Calories / Energy',
        'unit': 'kcal',
        'icon': Icons.local_fire_department_rounded,
        'color': const Color(0xFFEA580C),
        'user_val': energy,
        'male_std': 2110.0,
        'female_std': 1660.0,
        'type': 'target',
        'advisory': 'ICMR-NIN 2024 Reference Norm for Sedentary Indian Adults (2,110 kcal for men, 1,660 kcal for women). Balances basal metabolic rate and daily physical expenditure.',
      },
      {
        'id': 'total_fat',
        'name': 'Total Fat',
        'unit': 'g',
        'icon': Icons.opacity_rounded,
        'color': const Color(0xFFD97706),
        'user_val': fat,
        'male_std': 27.0,
        'female_std': 22.0,
        'type': 'upper_limit',
        'advisory': 'ICMR Visible Fat Guideline: Keep visible oils/fats below 27g for men and 22g for women, balancing monounsaturated and polyunsaturated fats.',
      },
      {
        'id': 'saturated_fat',
        'name': 'Saturated Fat',
        'unit': 'g',
        'icon': Icons.egg_outlined,
        'color': const Color(0xFFDC2626),
        'user_val': saturatedFat,
        'male_std': 16.0,
        'female_std': 12.0,
        'type': 'upper_limit',
        'advisory': 'Heart Foundation & ICMR: Saturated fats must not exceed 7-8% of total daily energy to prevent atherogenic plaque buildup and arterial stiffness.',
      },
      {
        'id': 'fiber',
        'name': 'Dietary Fiber',
        'unit': 'g',
        'icon': Icons.spa_rounded,
        'color': const Color(0xFF16A34A),
        'user_val': fiber,
        'male_std': 30.0,
        'female_std': 25.0,
        'type': 'target',
        'advisory': 'ICMR-NIN 2024 Fiber Target: 30g/day for men and 25g/day for women. Essential for gastrointestinal transit, glucose regulation, and microbiome health.',
      },
      {
        'id': 'carbohydrates',
        'name': 'Carbohydrates',
        'unit': 'g',
        'icon': Icons.breakfast_dining_rounded,
        'color': const Color(0xFF8B5CF6),
        'user_val': carbs,
        'male_std': 275.0,
        'female_std': 220.0,
        'type': 'upper_limit',
        'advisory': 'ICMR Recommends 50-60% of total daily energy from wholesome, complex carbohydrates, minimizing refined flours and ultra-processed starches.',
      },
    ];

    // Filter by dropdown choice
    final displayedItems = (_selectedNutrientId == 'all')
        ? standards
        : standards.where((s) => s['id'] == _selectedNutrientId).toList();

    return GlassCard(
      padding: const EdgeInsets.all(14),
      borderRadius: 18,
      backgroundColor: Colors.white.withValues(alpha: 0.95),
      borderColor: const Color(0xFF3B82F6).withValues(alpha: 0.25),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Collapsible & Optional Header Bar
          InkWell(
            onTap: () => setState(() => _isStandardsExpanded = !_isStandardsExpanded),
            borderRadius: BorderRadius.circular(12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFBFDBFE)),
                  ),
                  child: const Icon(Icons.people_alt_rounded, size: 16, color: Color(0xFF2563EB)),
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Gender Health Standards',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppTheme.slate900),
                      ),
                      Text(
                        'Compare nutrition with Male & Female ICMR RDA (Optional)',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 9.5, color: AppTheme.slate500, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: _isStandardsExpanded ? const Color(0xFFEFF6FF) : AppTheme.slate100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _isStandardsExpanded ? const Color(0xFFBFDBFE) : AppTheme.slate300),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _isStandardsExpanded ? 'Hide' : 'Inspect',
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.bold,
                          color: _isStandardsExpanded ? const Color(0xFF1D4ED8) : AppTheme.slate700,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        _isStandardsExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                        size: 14,
                        color: _isStandardsExpanded ? const Color(0xFF1D4ED8) : AppTheme.slate700,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // 2. Expanded Content (Nutrient Dropdown, Gender Filters, and Filtered Comparison Card)
          if (_isStandardsExpanded) ...[
            const SizedBox(height: 12),
            const Divider(height: 1, color: AppTheme.slate200),
            const SizedBox(height: 12),

            // Dropdown Selector for Specific Nutrition
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.slate300),
              ),
              child: Row(
                children: [
                  const Icon(Icons.tune_rounded, size: 14, color: AppTheme.slate600),
                  const SizedBox(width: 8),
                  const Text(
                    'Nutrient:',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.slate700),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedNutrientId,
                        isExpanded: true,
                        icon: const Icon(Icons.arrow_drop_down_rounded, color: AppTheme.slate700, size: 20),
                        style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: AppTheme.slate900),
                        items: const [
                          DropdownMenuItem(value: 'sugars', child: Text('🍬 Added Sugars (g)')),
                          DropdownMenuItem(value: 'sodium', child: Text('🧂 Sodium (mg)')),
                          DropdownMenuItem(value: 'protein', child: Text('💪 Protein (g)')),
                          DropdownMenuItem(value: 'calories', child: Text('🔥 Calories / Energy (kcal)')),
                          DropdownMenuItem(value: 'total_fat', child: Text('🥑 Total Fat (g)')),
                          DropdownMenuItem(value: 'saturated_fat', child: Text('🧈 Saturated Fat (g)')),
                          DropdownMenuItem(value: 'fiber', child: Text('🌾 Dietary Fiber (g)')),
                          DropdownMenuItem(value: 'carbohydrates', child: Text('🍞 Carbohydrates (g)')),
                          DropdownMenuItem(value: 'all', child: Text('📋 Compare All 8 Nutrients')),
                        ],
                        onChanged: (val) {
                          if (val != null) setState(() => _selectedNutrientId = val);
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 10),

            // Gender Standard View Switcher (Dual, Male, Female)
            Row(
              children: [
                Expanded(
                  child: _buildGenderToggleChip(0, 'Dual', Icons.compare_arrows_rounded),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _buildGenderToggleChip(1, 'Male (ICMR)', Icons.male_rounded),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _buildGenderToggleChip(2, 'Female (ICMR)', Icons.female_rounded),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Render Selected Nutrition Comparison Card(s)
            ...displayedItems.map((item) => _buildNutrientComparisonRow(item)),
          ],
        ],
      ),
    );
  }

  Widget _buildGenderToggleChip(int index, String label, IconData icon) {
    final isSelected = _selectedGenderStandard == index;
    return GestureDetector(
      onTap: () => setState(() => _selectedGenderStandard = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 2),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF1E293B) : AppTheme.slate100,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? const Color(0xFF1E293B) : AppTheme.slate200,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 12,
              color: isSelected ? Colors.white : AppTheme.slate600,
            ),
            const SizedBox(width: 3),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? Colors.white : AppTheme.slate700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNutrientComparisonRow(Map<String, dynamic> item) {
    final id = item['id'].toString();
    final name = item['name'].toString();
    final unit = item['unit'].toString();
    final icon = item['icon'] as IconData;
    final color = item['color'] as Color;
    final userVal = (item['user_val'] as num).toDouble();
    final maleStd = (item['male_std'] as num).toDouble();
    final femaleStd = (item['female_std'] as num).toDouble();
    final type = item['type'].toString();
    final advisory = item['advisory'].toString();
    final isAdvisoryExpanded = _expandedNutritionAdvisories.contains(id);

    // Compute status and ratios
    final maleRatio = (maleStd > 0) ? (userVal / maleStd) : 0.0;
    final femaleRatio = (femaleStd > 0) ? (userVal / femaleStd) : 0.0;

    final bool isMaleCompliant;
    final String maleStatus;
    if (type == 'upper_limit') {
      isMaleCompliant = userVal <= maleStd;
      maleStatus = isMaleCompliant
          ? 'Within Limit'
          : '+${((maleRatio - 1.0) * 100).round()}% Limit';
    } else {
      isMaleCompliant = userVal >= maleStd * 0.7;
      maleStatus = userVal >= maleStd
          ? 'Target Met'
          : '${(maleRatio * 100).round()}% RDA';
    }

    final bool isFemaleCompliant;
    final String femaleStatus;
    if (type == 'upper_limit') {
      isFemaleCompliant = userVal <= femaleStd;
      femaleStatus = isFemaleCompliant
          ? 'Within Limit'
          : '+${((femaleRatio - 1.0) * 100).round()}% Limit';
    } else {
      isFemaleCompliant = userVal >= femaleStd * 0.7;
      femaleStatus = userVal >= femaleStd
          ? 'Target Met'
          : '${(femaleRatio * 100).round()}% RDA';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.slate50.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.slate200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Nutrient Title and Monitored Intake Badge (Overflow-safe)
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(icon, size: 13, color: color),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: AppTheme.slate900),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppTheme.slate300),
                ),
                child: Text(
                  '${userVal.toStringAsFixed(1)} $unit',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    color: color,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              const SizedBox(width: 4),
              GestureDetector(
                onTap: () {
                  setState(() {
                    if (isAdvisoryExpanded) {
                      _expandedNutritionAdvisories.remove(id);
                    } else {
                      _expandedNutritionAdvisories.add(id);
                    }
                  });
                },
                child: Icon(
                  isAdvisoryExpanded ? Icons.info_rounded : Icons.info_outline_rounded,
                  size: 15,
                  color: isAdvisoryExpanded ? AppTheme.emerald600 : AppTheme.slate400,
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Render Comparison Views based on _selectedGenderStandard
          if (_selectedGenderStandard == 0) ...[
            // Dual Side-by-Side Comparison (Completely overflow safe)
            Row(
              children: [
                Expanded(
                  child: _buildGenderBenchmarkBox(
                    genderLabel: 'Male',
                    genderIcon: Icons.male_rounded,
                    genderColor: const Color(0xFF2563EB),
                    standardText: '${type == 'upper_limit' ? '≤' : '≥'}${maleStd.toStringAsFixed(0)} $unit',
                    ratio: maleRatio,
                    status: maleStatus,
                    isCompliant: isMaleCompliant,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _buildGenderBenchmarkBox(
                    genderLabel: 'Female',
                    genderIcon: Icons.female_rounded,
                    genderColor: const Color(0xFFDB2777),
                    standardText: '${type == 'upper_limit' ? '≤' : '≥'}${femaleStd.toStringAsFixed(0)} $unit',
                    ratio: femaleRatio,
                    status: femaleStatus,
                    isCompliant: isFemaleCompliant,
                  ),
                ),
              ],
            ),
          ] else if (_selectedGenderStandard == 1) ...[
            // Focused Male View
            _buildSingleGenderFocusedBox(
              item: item,
              genderName: 'Male (Adult)',
              genderIcon: Icons.male_rounded,
              standardVal: maleStd,
              genderColor: const Color(0xFF2563EB),
            ),
          ] else ...[
            // Focused Female View
            _buildSingleGenderFocusedBox(
              item: item,
              genderName: 'Female (Adult)',
              genderIcon: Icons.female_rounded,
              standardVal: femaleStd,
              genderColor: const Color(0xFFDB2777),
            ),
          ],

          // Expandable ICMR Clinical Advisory
          if (isAdvisoryExpanded) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.emerald300.withValues(alpha: 0.6)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.verified_user_outlined, size: 13, color: AppTheme.emerald600),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          advisory,
                          style: const TextStyle(fontSize: 9.5, color: AppTheme.slate700, height: 1.3),
                        ),
                        const SizedBox(height: 3),
                        const Text(
                          'Citation: ICMR-NIN Expert Committee on Dietary Allowances (2024)',
                          style: TextStyle(fontSize: 8.5, color: AppTheme.slate500, fontStyle: FontStyle.italic),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildGenderBenchmarkBox({
    required String genderLabel,
    required IconData genderIcon,
    required Color genderColor,
    required String standardText,
    required double ratio,
    required String status,
    required bool isCompliant,
  }) {
    final clampedRatio = ratio.clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isCompliant ? AppTheme.slate200 : const Color(0xFFFECACA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(genderIcon, size: 12, color: genderColor),
              const SizedBox(width: 3),
              Expanded(
                child: Text(
                  genderLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: genderColor),
                ),
              ),
              Text(
                standardText,
                style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: AppTheme.slate900),
              ),
            ],
          ),
          const SizedBox(height: 5),
          // Progress Bar
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: clampedRatio,
              minHeight: 4,
              backgroundColor: AppTheme.slate100,
              valueColor: AlwaysStoppedAnimation<Color>(
                isCompliant ? genderColor : AppTheme.dangerRed,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${(ratio * 100).round()}% std',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 8, color: AppTheme.slate500, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 2),
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: isCompliant ? const Color(0xFFF0FDF4) : const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    status,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                      color: isCompliant ? AppTheme.emerald700 : AppTheme.dangerRed,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSingleGenderFocusedBox({
    required Map<String, dynamic> item,
    required String genderName,
    required IconData genderIcon,
    required double standardVal,
    required Color genderColor,
  }) {
    final userVal = (item['user_val'] as num).toDouble();
    final unit = item['unit'].toString();
    final type = item['type'].toString();
    final ratio = (standardVal > 0) ? (userVal / standardVal) : 0.0;
    final clampedRatio = ratio.clamp(0.0, 1.0);
    final delta = userVal - standardVal;

    final bool isCompliant = type == 'upper_limit' ? (userVal <= standardVal) : (userVal >= standardVal * 0.7);

    return Container(
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isCompliant ? AppTheme.slate200 : const Color(0xFFFECACA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(genderIcon, size: 13, color: genderColor),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  '$genderName Norm',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: genderColor),
                ),
              ),
              Text(
                'Std: ${type == 'upper_limit' ? '≤' : '≥'}${standardVal.toStringAsFixed(0)} $unit',
                style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: AppTheme.slate900),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: clampedRatio,
              minHeight: 5,
              backgroundColor: AppTheme.slate100,
              valueColor: AlwaysStoppedAnimation<Color>(
                isCompliant ? genderColor : AppTheme.dangerRed,
              ),
            ),
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              Expanded(
                child: Text(
                  type == 'upper_limit'
                      ? (delta > 0 ? '+${delta.toStringAsFixed(1)} $unit Excess' : '${(-delta).toStringAsFixed(1)} $unit Margin')
                      : '${(ratio * 100).round()}% RDA Met',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 8.5,
                    fontWeight: FontWeight.w600,
                    color: isCompliant ? AppTheme.slate700 : AppTheme.dangerRed,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                decoration: BoxDecoration(
                  color: isCompliant ? const Color(0xFFF0FDF4) : const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  isCompliant ? 'Compliant' : 'Moderation',
                  style: TextStyle(
                    fontSize: 8.5,
                    fontWeight: FontWeight.bold,
                    color: isCompliant ? AppTheme.emerald700 : AppTheme.dangerRed,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  double _getNutrientTotal(String targetKey, List<String> aliases, double fallbackSummaryVal) {
    if (fallbackSummaryVal > 0) return fallbackSummaryVal;
    double sum = 0.0;
    for (final scan in _displayedScans) {
      final nutr = scan['nutrition_table'];
      if (nutr is List) {
        for (final item in nutr) {
          if (item is Map) {
            final name = (item['nutrient'] ?? item['name'] ?? '').toString().toLowerCase();
            if (aliases.any((a) => name.contains(a.toLowerCase()))) {
              final valStr = (item['per_100g'] ?? item['per_serving'] ?? item['value'] ?? '').toString();
              final v = _parseNumeric(valStr);
              if (v > 0) {
                sum += v;
                break;
              }
            }
          }
        }
      } else if (nutr is Map) {
        for (final entry in nutr.entries) {
          final k = entry.key.toString().toLowerCase();
          if (aliases.any((a) => k.contains(a.toLowerCase()))) {
            final v = _parseNumeric(entry.value.toString());
            if (v > 0) {
              sum += v;
              break;
            }
          }
        }
      }
    }
    return sum;
  }

  static double _parseNumeric(String text) {
    final match = RegExp(r'[-+]?(?:\d*\.\d+|\d+)').firstMatch(text);
    if (match != null) {
      return double.tryParse(match.group(0) ?? '') ?? 0.0;
    }
    return 0.0;
  }

  // --- 3. NUTRITIONAL SURVEILLANCE CARD ---
  Widget _buildNutritionalSurveillanceCard({
    required double sugar,
    required double sodium,
    required double energy,
    required double protein,
    required int highSugarCount,
  }) {
    return GlassCard(
      padding: const EdgeInsets.all(14),
      borderRadius: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.monitor_heart_rounded, size: 16, color: Color(0xFFF43F5E)),
                  SizedBox(width: 6),
                  Text(
                    'Nutritional Intake & Monitoring',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppTheme.slate900),
                  ),
                ],
              ),
              if (highSugarCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF1F2),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFFFECDD3)),
                  ),
                  child: Text(
                    '$highSugarCount High-Sugar ${highSugarCount == 1 ? 'Item' : 'Items'}',
                    style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Color(0xFFBE123C)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          // 4 Nutritional Badges
          Row(
            children: [
              Expanded(
                child: _buildNutrientMeterPill(
                  name: 'Sugars',
                  value: '${sugar.toStringAsFixed(1)}g',
                  icon: Icons.cookie_outlined,
                  color: sugar > 100 ? AppTheme.dangerRed : AppTheme.warningOrange,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _buildNutrientMeterPill(
                  name: 'Sodium',
                  value: '${sodium.toStringAsFixed(0)}mg',
                  icon: Icons.grain_rounded,
                  color: sodium > 2000 ? AppTheme.dangerRed : const Color(0xFF0284C7),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _buildNutrientMeterPill(
                  name: 'Calories',
                  value: '${energy.toStringAsFixed(0)} kcal',
                  icon: Icons.local_fire_department_rounded,
                  color: const Color(0xFFEA580C),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _buildNutrientMeterPill(
                  name: 'Protein',
                  value: '${protein.toStringAsFixed(1)}g',
                  icon: Icons.fitness_center_rounded,
                  color: AppTheme.emerald600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNutrientMeterPill({
    required String name,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: color),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            name,
            style: const TextStyle(fontSize: 8.5, color: AppTheme.slate600, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  // --- 4. WEEKLY DAY-BY-DAY ACTIVITY STRIP ---
  Widget _buildWeeklyDayStrip(Map dailyDist) {
    final entries = dailyDist.entries.toList();
    entries.sort((a, b) => a.key.toString().compareTo(b.key.toString()));

    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      borderRadius: 16,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: entries.map((entry) {
          final dateStr = entry.key.toString();
          final count = (entry.value as num?)?.toInt() ?? 0;
          DateTime? dt;
          try {
            dt = DateTime.parse(dateStr);
          } catch (_) {}

          final dayName = dt != null ? DateFormat('E').format(dt) : dateStr.substring(dateStr.length - 2);
          final dayNum = dt != null ? DateFormat('d').format(dt) : '';
          final isSelected = _selectedDayFilter == dateStr;

          return GestureDetector(
            onTap: () {
              setState(() {
                _selectedDayFilter = isSelected ? null : dateStr;
              });
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppTheme.emerald600
                    : (count > 0 ? AppTheme.emerald50 : Colors.transparent),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isSelected
                      ? AppTheme.emerald700
                      : (count > 0 ? AppTheme.emerald200 : AppTheme.slate200),
                  width: 1,
                ),
              ),
              child: Column(
                children: [
                  Text(
                    dayName,
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? Colors.white : AppTheme.slate600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    dayNum,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: isSelected ? Colors.white : AppTheme.slate900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: count > 0
                          ? (isSelected ? Colors.white : AppTheme.emerald600)
                          : AppTheme.slate300,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // --- 5. ALLERGEN SURVEILLANCE BANNER ---
  Widget _buildAllergenSurveillanceBanner(List allergens) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, size: 16, color: Color(0xFFB45309)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Allergen Warnings Detected in Scans:',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF92400E)),
                ),
                Text(
                  allergens.map((a) => a.toString().replaceAll('\n', ' ')).take(3).join(' • '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 9.5, color: Color(0xFF78350F)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- 6. INDIVIDUAL SCANNED PRODUCT CARD ---
  Widget _buildScannedProductCard(dynamic scan) {
    final scanId = (scan['scan_id'] ?? scan['id'] ?? '').toString();
    final pName = (scan['product_name'] ?? 'Packaged Item').toString();
    final bName = (scan['brand_name'] ?? scan['brand'] ?? 'Verified Brand').toString();
    final mName = (scan['manufacturer_name'] ?? '').toString();
    final status = (scan['status'] ?? scan['overall_compliance'] ?? 'REVIEW').toString().toUpperCase();
    final isPass = status == 'PASS' || status == 'COMPLIANT';
    final isFail = status == 'FAIL' || status == 'NON_COMPLIANT';
    final dateStr = (scan['created_at'] ?? scan['date'] ?? '').toString();
    final healthRating = (scan['health_star_rating'] as num?)?.toDouble() ?? 3.5;
    final isExpanded = _expandedScanIds.contains(scanId);

    // Nutrients & Declarations
    final decl = (scan['extracted_declarations'] as Map?) ?? {};
    final mrp = decl['mrp']?.toString() ?? 'N/A';
    final netQty = decl['net_quantity'] != null ? '${decl['net_quantity']} ${decl['unit'] ?? ''}'.trim() : 'N/A';

    DateTime? dt;
    try {
      dt = DateTime.parse(dateStr);
    } catch (_) {}
    final formattedDate = dt != null ? DateFormat('MMM d, h:mm a').format(dt) : dateStr;

    return GlassCard(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      borderRadius: 16,
      borderColor: isPass ? AppTheme.emerald500.withValues(alpha: 0.25) : AppTheme.slate200,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row: Brand & Status Pill
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.slate100,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        bName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppTheme.slate800),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      formattedDate,
                      style: const TextStyle(fontSize: 9.5, color: AppTheme.slate500),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                decoration: BoxDecoration(
                  color: (isPass ? AppTheme.successGreen : (isFail ? AppTheme.dangerRed : AppTheme.warningOrange)).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: (isPass ? AppTheme.successGreen : (isFail ? AppTheme.dangerRed : AppTheme.warningOrange)).withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  isPass ? 'COMPLIANT' : (isFail ? 'VIOLATION' : 'REVIEW'),
                  style: TextStyle(
                    color: isPass ? AppTheme.successGreen : (isFail ? AppTheme.dangerRed : AppTheme.warningOrange),
                    fontWeight: FontWeight.w800,
                    fontSize: 9,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Product Title
          Text(
            pName,
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: AppTheme.slate900),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),

          if (mName.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              'Mfg: $mName',
              style: const TextStyle(fontSize: 10, color: AppTheme.slate600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],

          const SizedBox(height: 10),

          // Quick Specs Bar (Health Star, Net Qty, MRP)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: AppTheme.slate50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.slate200.withValues(alpha: 0.8)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.star_rounded, size: 14, color: Color(0xFFEAB308)),
                    const SizedBox(width: 4),
                    Text(
                      '★ ${healthRating.toStringAsFixed(1)} / 5',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppTheme.slate800),
                    ),
                  ],
                ),
                Text(
                  'Qty: $netQty',
                  style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: AppTheme.slate700),
                ),
                Text(
                  'MRP: ₹$mrp',
                  style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: AppTheme.slate900),
                ),
              ],
            ),
          ),

          const SizedBox(height: 10),

          // Accordion for Full Nutrients & Declarations
          if (isExpanded) ...[
            _buildProductExpandedNutritionalTable(scan),
            const SizedBox(height: 10),
          ],

          // Footer Action Buttons
          Row(
            children: [
              // Expand / Collapse Nutrients Toggle
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    setState(() {
                      if (isExpanded) {
                        _expandedScanIds.remove(scanId);
                      } else {
                        _expandedScanIds.add(scanId);
                      }
                    });
                  },
                  icon: Icon(
                    isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                    size: 16,
                  ),
                  label: Text(
                    isExpanded ? 'Hide Nutrients' : 'View Nutrients & Facts',
                    style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.slate700,
                    side: const BorderSide(color: AppTheme.slate300),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),

              const SizedBox(width: 8),

              // Open Full Details Screen
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => DetailsScreen(item: Map<String, dynamic>.from(scan as Map)),
                    ),
                  );
                },
                icon: const Icon(Icons.arrow_forward_rounded, size: 14),
                label: const Text('Full Audit', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F172A),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // --- 7. EXPANDED NUTRITIONAL TABLE & STATUTORY AUDIT ---
  Widget _buildProductExpandedNutritionalTable(dynamic scan) {
    final nutr = scan['nutrition_table'];
    final ingr = scan['ingredients_list'];
    final allergens = scan['allergen_info'];
    final decl = (scan['extracted_declarations'] as Map?) ?? {};

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.slate200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.table_chart_rounded, size: 14, color: AppTheme.emerald600),
              SizedBox(width: 6),
              Text(
                'Nutritional Information Table',
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: AppTheme.slate900),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Render Nutrition Table (handles list or map)
          if (nutr is List && nutr.isNotEmpty) ...[
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: AppTheme.slate200),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    color: AppTheme.slate100,
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Nutrient', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: AppTheme.slate700)),
                        Text('Per Serving / 100g', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: AppTheme.slate700)),
                      ],
                    ),
                  ),
                  ...nutr.take(8).map((n) {
                    final nName = (n['nutrient'] ?? n['name'] ?? 'Nutrient').toString();
                    final val = (n['per_serving'] ?? n['per_100g'] ?? n['value'] ?? '-').toString();
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(child: Text(nName, style: const TextStyle(fontSize: 9.5, color: AppTheme.slate800), overflow: TextOverflow.ellipsis)),
                          Text(val, style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: AppTheme.slate900)),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ] else if (nutr is Map && nutr.isNotEmpty) ...[
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: AppTheme.slate200),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Column(
                children: nutr.entries.take(8).map((e) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(child: Text(e.key.toString(), style: const TextStyle(fontSize: 9.5, color: AppTheme.slate800), overflow: TextOverflow.ellipsis)),
                        Text(e.value.toString(), style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: AppTheme.slate900)),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ] else ...[
            const Text(
              'Standard pharmaceutical/packaged composition recorded. Tap "Full Audit" for detailed breakdown.',
              style: TextStyle(fontSize: 10, color: AppTheme.slate500, fontStyle: FontStyle.italic),
            ),
          ],

          if (ingr is List && ingr.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Text(
              'Ingredients & Excipients:',
              style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: AppTheme.slate900),
            ),
            const SizedBox(height: 3),
            Text(
              ingr.join(', '),
              style: const TextStyle(fontSize: 9.5, color: AppTheme.slate700, height: 1.3),
            ),
          ],

          if (allergens is List && allergens.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFFFECACA)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.shield_outlined, size: 12, color: AppTheme.dangerRed),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'Allergens: ${allergens.join(", ")}',
                      style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFF991B1B)),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 8),

          // Packaging details & dates
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              if (decl['batch_number'] != null)
                Text('Batch: ${decl['batch_number']}', style: const TextStyle(fontSize: 9.5, color: AppTheme.slate600)),
              if (decl['expiry_date'] != null)
                Text('Exp: ${decl['expiry_date']}', style: const TextStyle(fontSize: 9.5, color: AppTheme.slate600)),
              if (decl['fssai_license_number'] != null)
                Text('FSSAI: ${decl['fssai_license_number']}', style: const TextStyle(fontSize: 9.5, color: AppTheme.slate600)),
            ],
          ),
        ],
      ),
    );
  }
}

class _GeneralizedHealthCurvePainter extends CustomPainter {
  final List<Map<String, dynamic>> dataPoints;
  final int selectedIndex;

  _GeneralizedHealthCurvePainter({
    required this.dataPoints,
    required this.selectedIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (dataPoints.isEmpty) return;

    const double paddingH = 24.0;
    const double paddingTop = 14.0;
    const double paddingBottom = 22.0;
    final double chartWidth = size.width - (paddingH * 2);
    final double chartHeight = size.height - paddingTop - paddingBottom;

    const double minScore = 50.0;
    const double maxScore = 100.0;

    double getY(double score) {
      final norm = ((score - minScore) / (maxScore - minScore)).clamp(0.0, 1.0);
      return paddingTop + (1.0 - norm) * chartHeight;
    }

    double getX(int index) {
      if (dataPoints.length <= 1) return paddingH + chartWidth / 2;
      return paddingH + (index / (dataPoints.length - 1)) * chartWidth;
    }

    // 1. Draw horizontal grid lines at 60%, 80%, 100%
    final gridPaint = Paint()
      ..color = AppTheme.slate200.withValues(alpha: 0.6)
      ..strokeWidth = 0.8;

    for (final scoreLevel in [60.0, 80.0, 100.0]) {
      final y = getY(scoreLevel);
      canvas.drawLine(Offset(paddingH, y), Offset(size.width - paddingH, y), gridPaint);
    }

    // 2. Draw 80% ICMR/WHO Benchmark Dashed Line
    final benchmarkY = getY(80.0);
    final dashPaint = Paint()
      ..color = const Color(0xFFF59E0B)
      ..strokeWidth = 1.3;

    const double dashWidth = 4.0;
    const double dashSpace = 3.0;
    double startX = paddingH;
    while (startX < size.width - paddingH) {
      canvas.drawLine(
        Offset(startX, benchmarkY),
        Offset(math.min(startX + dashWidth, size.width - paddingH), benchmarkY),
        dashPaint,
      );
      startX += dashWidth + dashSpace;
    }

    // 3. Compute Points for smooth curve
    final List<Offset> points = [];
    for (int i = 0; i < dataPoints.length; i++) {
      final s = (dataPoints[i]['score'] as num).toDouble();
      points.add(Offset(getX(i), getY(s)));
    }

    // 4. Build smooth cubic Bézier spline Path
    final path = Path();
    path.moveTo(points.first.dx, points.first.dy);

    for (int i = 0; i < points.length - 1; i++) {
      final p0 = points[i];
      final p1 = points[i + 1];
      final controlX1 = p0.dx + (p1.dx - p0.dx) / 2;
      final controlY1 = p0.dy;
      final controlX2 = p0.dx + (p1.dx - p0.dx) / 2;
      final controlY2 = p1.dy;
      path.cubicTo(controlX1, controlY1, controlX2, controlY2, p1.dx, p1.dy);
    }

    // 5. Fill Area Under Curve with smooth vertical gradient
    final fillPath = Path.from(path);
    fillPath.lineTo(points.last.dx, size.height - paddingBottom);
    fillPath.lineTo(points.first.dx, size.height - paddingBottom);
    fillPath.close();

    final fillGradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        AppTheme.emerald500.withValues(alpha: 0.28),
        AppTheme.emerald500.withValues(alpha: 0.01),
      ],
    );

    final fillPaint = Paint()
      ..shader = fillGradient.createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill;

    canvas.drawPath(fillPath, fillPaint);

    // 6. Draw Stroke Curve
    final strokePaint = Paint()
      ..color = AppTheme.emerald600
      ..strokeWidth = 2.6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(path, strokePaint);

    // 7. Draw Vertical Cursor on selected index
    if (selectedIndex >= 0 && selectedIndex < points.length) {
      final selP = points[selectedIndex];
      final cursorPaint = Paint()
        ..color = AppTheme.emerald500.withValues(alpha: 0.35)
        ..strokeWidth = 1.0;

      double curY = selP.dy;
      while (curY < size.height - paddingBottom) {
        canvas.drawLine(
          Offset(selP.dx, curY),
          Offset(selP.dx, math.min(curY + 3.0, size.height - paddingBottom)),
          cursorPaint,
        );
        curY += 5.0;
      }
    }

    // 8. Draw Nodes & X-Axis Day Labels
    for (int i = 0; i < points.length; i++) {
      final p = points[i];
      final isSel = i == selectedIndex;
      final isAbove = (dataPoints[i]['score'] as num).toDouble() >= 80.0;

      // Glow ring on selected node
      if (isSel) {
        final glowPaint = Paint()
          ..color = AppTheme.emerald500.withValues(alpha: 0.3)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(p, 9.0, glowPaint);
      }

      // Outer node ring
      final outerPaint = Paint()
        ..color = isSel
            ? AppTheme.emerald700
            : (isAbove ? AppTheme.emerald600 : const Color(0xFFF59E0B))
        ..style = PaintingStyle.fill;
      canvas.drawCircle(p, isSel ? 5.0 : 3.5, outerPaint);

      // Inner white center
      final innerPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;
      canvas.drawCircle(p, isSel ? 2.5 : 1.8, innerPaint);

      // Day Text Label
      final dayStr = dataPoints[i]['day']?.toString() ?? '';
      final textSpan = TextSpan(
        text: dayStr,
        style: TextStyle(
          color: isSel ? AppTheme.emerald700 : AppTheme.slate600,
          fontWeight: isSel ? FontWeight.w800 : FontWeight.w600,
          fontSize: 9.5,
        ),
      );
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(p.dx - textPainter.width / 2, size.height - paddingBottom + 4));
    }
  }

  @override
  bool shouldRepaint(covariant _GeneralizedHealthCurvePainter oldDelegate) {
    return oldDelegate.selectedIndex != selectedIndex || oldDelegate.dataPoints != dataPoints;
  }
}
