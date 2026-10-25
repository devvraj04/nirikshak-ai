import 'dart:async';
import 'package:flutter/material.dart';
import '../core/api_client.dart';
import '../core/theme.dart';
import 'glass_card.dart';
import '../screens/details_screen.dart';

class ProductCatalogView extends StatefulWidget {
  final VoidCallback? onSwitchToCurrentAudits;

  const ProductCatalogView({super.key, this.onSwitchToCurrentAudits});

  @override
  State<ProductCatalogView> createState() => _ProductCatalogViewState();
}

class _ProductCatalogViewState extends State<ProductCatalogView> {
  final ApiClient _apiClient = ApiClient();
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounceTimer;

  bool _isLoading = true;
  String? _errorMessage;
  List<dynamic> _items = [];
  int _totalCount = 0;

  // Facet data from API
  List<String> _availableManufacturers = [];
  List<String> _availableCategories = [];
  Map<String, int> _complianceCounts = {};

  // Active filters
  String _selectedStatus = 'ALL'; // 'ALL', 'PASS', 'FAIL', 'REVIEW'
  String _selectedCategory = 'ALL';
  String? _selectedManufacturer;
  double? _minTrust;
  String _sortBy = 'recent'; // 'recent', 'trust_desc', 'mrp_desc', 'name_asc'

  @override
  void initState() {
    super.initState();
    _fetchCatalog();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 350), () {
      _fetchCatalog();
    });
  }

  Future<void> _fetchCatalog() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final res = await _apiClient.fetchProductCatalog(
        query: _searchController.text.trim(),
        manufacturer: _selectedManufacturer,
        status: _selectedStatus == 'ALL' ? null : _selectedStatus,
        category: _selectedCategory == 'ALL' ? null : _selectedCategory,
        minTrust: _minTrust,
        sortBy: _sortBy,
      );

      if (!mounted) return;

      final filters = res['filters'] as Map<String, dynamic>? ?? {};
      final mfgList = (filters['available_manufacturers'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList();
      final catList = (filters['available_categories'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList();
      final compMap = (filters['compliance_counts'] as Map<String, dynamic>? ?? {})
          .map((k, v) => MapEntry(k, (v as num).toInt()));

      setState(() {
        _items = res['items'] ?? [];
        _totalCount = res['total'] ?? 0;
        _availableManufacturers = mfgList;
        _availableCategories = catList;
        _complianceCounts = compMap;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  void _resetAllFilters() {
    _searchController.clear();
    setState(() {
      _selectedStatus = 'ALL';
      _selectedCategory = 'ALL';
      _selectedManufacturer = null;
      _minTrust = null;
      _sortBy = 'recent';
    });
    _fetchCatalog();
  }

  bool get _hasActiveFilters =>
      _searchController.text.isNotEmpty ||
      _selectedStatus != 'ALL' ||
      _selectedCategory != 'ALL' ||
      _selectedManufacturer != null ||
      _minTrust != null;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. Search Box with dual search hint (generic name, brand, manufacturer)
        _buildSearchBar(),

        const SizedBox(height: 12),

        // 2. Status & Category Filter Chips
        _buildFilterChips(),

        const SizedBox(height: 10),

        // 3. Manufacturer Filter Row (if available)
        if (_availableManufacturers.isNotEmpty) ...[
          _buildManufacturerFilterRow(),
          const SizedBox(height: 10),
        ],

        // 4. Results Header & Active Filters Bar
        _buildResultsHeader(),

        const SizedBox(height: 10),

        // 5. Main Catalog Content (List / Loading / Empty / Error)
        _buildCatalogContent(),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
        border: Border.all(color: AppTheme.slate200),
      ),
      child: TextField(
        controller: _searchController,
        onChanged: _onSearchChanged,
        decoration: InputDecoration(
          hintText: 'Search by Generic Name, Brand, or Manufacturer...',
          hintStyle: const TextStyle(fontSize: 12.5, color: AppTheme.slate400),
          prefixIcon: const Icon(Icons.search_rounded, color: AppTheme.emerald600, size: 20),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear_rounded, size: 18, color: AppTheme.slate400),
                  onPressed: () {
                    _searchController.clear();
                    _fetchCatalog();
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
      ),
    );
  }

  Widget _buildFilterChips() {
    final int passCount = _complianceCounts['PASS'] ?? 0;
    final int failCount = _complianceCounts['FAIL'] ?? 0;
    final int reviewCount = _complianceCounts['REVIEW'] ?? 0;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: [
          // All Status
          _buildChip(
            label: 'All (${_totalCount})',
            isSelected: _selectedStatus == 'ALL',
            onTap: () {
              setState(() => _selectedStatus = 'ALL');
              _fetchCatalog();
            },
          ),
          const SizedBox(width: 8),

          // PASS
          _buildChip(
            label: 'Compliant ($passCount✓)',
            isSelected: _selectedStatus == 'PASS',
            selectedColor: AppTheme.emerald100,
            textColor: AppTheme.emerald800,
            borderColor: AppTheme.emerald500,
            onTap: () {
              setState(() => _selectedStatus = _selectedStatus == 'PASS' ? 'ALL' : 'PASS');
              _fetchCatalog();
            },
          ),
          const SizedBox(width: 8),

          // FAIL
          _buildChip(
            label: 'Violations ($failCount✗)',
            isSelected: _selectedStatus == 'FAIL',
            selectedColor: Colors.red.withValues(alpha: 0.12),
            textColor: AppTheme.dangerRed,
            borderColor: AppTheme.dangerRed,
            onTap: () {
              setState(() => _selectedStatus = _selectedStatus == 'FAIL' ? 'ALL' : 'FAIL');
              _fetchCatalog();
            },
          ),
          const SizedBox(width: 8),

          // REVIEW
          if (reviewCount > 0) ...[
            _buildChip(
              label: 'Review Needed ($reviewCount)',
              isSelected: _selectedStatus == 'REVIEW',
              selectedColor: Colors.amber.withValues(alpha: 0.15),
              textColor: Colors.amber.shade900,
              borderColor: Colors.amber.shade700,
              onTap: () {
                setState(() => _selectedStatus = _selectedStatus == 'REVIEW' ? 'ALL' : 'REVIEW');
                _fetchCatalog();
              },
            ),
            const SizedBox(width: 8),
          ],

          // Trust Filter Chip
          _buildChip(
            label: _minTrust != null ? 'High Trust (>80%)' : 'Trust: All',
            isSelected: _minTrust != null,
            icon: Icons.verified_user_outlined,
            onTap: () {
              setState(() => _minTrust = _minTrust == null ? 80.0 : null);
              _fetchCatalog();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildManufacturerFilterRow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.factory_outlined, size: 13, color: AppTheme.slate600),
            const SizedBox(width: 5),
            const Text(
              'FILTER BY MANUFACTURER',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: AppTheme.slate600,
              ),
            ),
            if (_selectedManufacturer != null) ...[
              const Spacer(),
              GestureDetector(
                onTap: () {
                  setState(() => _selectedManufacturer = null);
                  _fetchCatalog();
                },
                child: const Text('Clear', style: TextStyle(fontSize: 10, color: AppTheme.emerald700, fontWeight: FontWeight.bold)),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(
            children: _availableManufacturers.take(8).map((mfg) {
              final isSelected = _selectedManufacturer == mfg;
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedManufacturer = isSelected ? null : mfg;
                    });
                    _fetchCatalog();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: isSelected ? AppTheme.slate900 : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected ? AppTheme.slate900 : AppTheme.slate200,
                      ),
                    ),
                    child: Text(
                      mfg,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                        color: isSelected ? Colors.white : AppTheme.slate800,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildResultsHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Text(
              '$_totalCount Products in Catalog',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.slate900),
            ),
            if (_isLoading) ...[
              const SizedBox(width: 8),
              const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.emerald600),
              ),
            ],
          ],
        ),
        if (_hasActiveFilters)
          GestureDetector(
            onTap: _resetAllFilters,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.filter_alt_off_rounded, size: 12, color: AppTheme.dangerRed),
                  SizedBox(width: 4),
                  Text('Reset Filters', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: AppTheme.dangerRed)),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildCatalogContent() {
    if (_isLoading && _items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: Column(
            children: [
              CircularProgressIndicator(color: AppTheme.emerald600),
              SizedBox(height: 12),
              Text('Fetching verified product digital twins...', style: TextStyle(fontSize: 12, color: AppTheme.slate500)),
            ],
          ),
        ),
      );
    }

    if (_errorMessage != null && _items.isEmpty) {
      return GlassCard(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Icon(Icons.cloud_off_rounded, size: 36, color: AppTheme.dangerRed),
            const SizedBox(height: 10),
            const Text('Could not load Product Catalog', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 6),
            Text(_errorMessage!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, color: AppTheme.slate500)),
            const SizedBox(height: 14),
            ElevatedButton.icon(
              onPressed: _fetchCatalog,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.slate900,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
      );
    }

    if (_items.isEmpty) {
      return GlassCard(
        padding: const EdgeInsets.all(30),
        child: Center(
          child: Column(
            children: [
              const Icon(Icons.search_off_rounded, size: 40, color: AppTheme.slate400),
              const SizedBox(height: 10),
              const Text(
                'No products match your search or filters.',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.slate800),
              ),
              const SizedBox(height: 4),
              const Text(
                'Try searching by generic name (e.g., Atta, Rice, Oil) or clear active filters.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: AppTheme.slate500),
              ),
              const SizedBox(height: 14),
              OutlinedButton(
                onPressed: _resetAllFilters,
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('Clear All Filters', style: TextStyle(fontSize: 11.5)),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: _items.map((item) => _buildProductCard(item)).toList(),
    );
  }

  Widget _buildProductCard(Map<String, dynamic> product) {
    final String name = product['product_name'] ?? 'Unknown Product';
    final String genericName = product['generic_name'] ?? name;
    final String brand = product['brand'] ?? 'Verified Brand';
    final String mfr = product['manufacturer'] ?? 'Registered Manufacturer';
    final String? heroImg = product['hero_image_url'];
    final double trustScore = (product['trust_score'] as num?)?.toDouble() ?? 100.0;
    final String status = product['latest_compliance_status'] ?? 'PASS';
    final int totalScans = product['total_scans'] ?? 1;
    final int violationsCount = product['violations_count'] ?? 0;
    final Map<String, dynamic> decls = product['latest_declarations'] ?? {};
    final num? mrp = decls['mrp'];
    final num? netQty = decls['net_quantity'];
    final String unit = decls['unit'] ?? '';

    final bool isPass = status == 'PASS';
    final Color statusColor = isPass ? AppTheme.emerald700 : AppTheme.dangerRed;
    final Color statusBg = isPass ? AppTheme.emerald100 : Colors.red.withValues(alpha: 0.12);

    // Resolve hero image URL (Supabase or full URL or fallback)
    final String? fullHeroUrl = heroImg != null && heroImg.isNotEmpty
        ? (heroImg.startsWith('http') ? heroImg : '${ApiClient.getBaseUrl}$heroImg')
        : null;

    return GlassCard(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      borderRadius: 16,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _openProductDetails(product),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Product Pack Image (Supabase Storage with fallback)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: 76,
                height: 84,
                color: AppTheme.slate100,
                child: fullHeroUrl != null
                    ? Image.network(
                        fullHeroUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _buildFallbackThumbnail(name),
                      )
                    : _buildFallbackThumbnail(name),
              ),
            ),
            const SizedBox(width: 12),

            // Product Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Brand & Status Badge Row
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '$brand • $genericName',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.slate500,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: statusBg,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          isPass ? 'COMPLIANT' : '$violationsCount ISSUES',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: statusColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),

                  // Complete Product Name
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.slate900,
                    ),
                  ),
                  const SizedBox(height: 3),

                  // Manufacturer Line
                  Row(
                    children: [
                      const Icon(Icons.business_rounded, size: 12, color: AppTheme.slate400),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          mfr,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11, color: AppTheme.slate600),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),

                  // Metrics Row (MRP, Net Qty, Trust Score)
                  Row(
                    children: [
                      if (mrp != null && mrp > 0) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.slate100,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '₹$mrp',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.slate900,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      if (netQty != null && netQty > 0) ...[
                        Text(
                          '$netQty $unit',
                          style: const TextStyle(fontSize: 10.5, color: AppTheme.slate600),
                        ),
                        const SizedBox(width: 6),
                        const Text('•', style: TextStyle(color: AppTheme.slate300)),
                        const SizedBox(width: 6),
                      ],
                      Text(
                        '${trustScore.toInt()}% Trust',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: trustScore >= 80 ? AppTheme.emerald700 : Colors.amber.shade900,
                        ),
                      ),
                      const Spacer(),
                      const Icon(Icons.arrow_forward_ios_rounded, size: 11, color: AppTheme.slate400),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFallbackThumbnail(String name) {
    return Center(
      child: Icon(
        Icons.inventory_2_rounded,
        size: 30,
        color: AppTheme.slate400.withValues(alpha: 0.6),
      ),
    );
  }

  void _openProductDetails(Map<String, dynamic> product) {
    // Construct item map conforming to DetailsScreen format
    final Map<String, dynamic> item = {
      'product_id': product['product_id'],
      'product_name': product['product_name'],
      'generic_product_name': product['generic_name'],
      'brand': product['brand'],
      'manufacturer_name': product['manufacturer'],
      'status': product['latest_compliance_status'],
      'trust_score': product['trust_score'],
      'hero_image_url': product['hero_image_url'],
      'image_urls': {
        'front': product['hero_image_url'],
      },
      'declarations': product['latest_declarations'],
      'created_at': product['updated_at'],
      'from_catalog': true,
    };

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DetailsScreen(item: item),
      ),
    );
  }

  Widget _buildChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    Color? selectedColor,
    Color? textColor,
    Color? borderColor,
    IconData? icon,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? (selectedColor ?? AppTheme.slate900) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? (borderColor ?? AppTheme.slate900) : AppTheme.slate200,
            width: isSelected ? 1.5 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 12, color: isSelected ? (textColor ?? Colors.white) : AppTheme.slate600),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? (textColor ?? Colors.white) : AppTheme.slate700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
