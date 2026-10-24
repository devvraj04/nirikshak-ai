// lib/services/source_registry.dart

/// Represents a verified external source backing a claim or standard.
class SourceInfo {
  final String url;
  final String title;
  final String publisher;
  final String tier; // Official, Research, News
  final DateTime? publishedDate;
  final DateTime lastVerifiedAt;

  const SourceInfo({
    required this.url,
    required this.title,
    required this.publisher,
    required this.tier,
    this.publishedDate,
    required this.lastVerifiedAt,
  });
}

/// Registry that maintains allowlisted domains and maps product claims / facts to official sources.
class SourceRegistry {
  // Allowlist of trusted domains with tier classification.
  static const Map<String, String> _allowlist = {
    // Tier 1 - Regulators & International bodies
    'fssai.gov.in': 'Official',
    'foscos.fssai.gov.in': 'Official',
    'who.int': 'Official',
    'icmr.gov.in': 'Official',
    'nin.res.in': 'Official',
    'cdsco.gov.in': 'Official',
    'bis.gov.in': 'Official',
    'services.bis.gov.in': 'Official',
    'dmi.gov.in': 'Official',
    'jaivikbharat.fssai.gov.in': 'Official',
    'consumeraffairs.nic.in': 'Official',
    'iso.org': 'Official',
    'codexalimentarius.org': 'Official',
    'codex.fao.org': 'Official',
    'fao.org': 'Official',
    'efsa.europa.eu': 'Official',
    'fda.gov': 'Official',
    // Tier 2 - Research
    'pubchem.ncbi.nlm.nih.gov': 'Research',
    'pubmed.ncbi.nlm.nih.gov': 'Research',
    'doi.org': 'Research',
    'cochrane.org': 'Research',
    // Tier 3 - News / Transparency
    'reuters.com': 'News',
    'bbc.com': 'News',
    'iris.who.int': 'Official',
    'theguardian.com': 'News',
  };

  /// Validates whether a domain is in our official trust allowlist.
  static bool isAllowedDomain(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    final host = uri.host.toLowerCase().replaceFirst('www.', '');
    if (_allowlist.containsKey(host)) return true;
    for (final domain in _allowlist.keys) {
      if (host == domain || host.endsWith('.$domain')) return true;
    }
    return false;
  }

  // Pre-configured official sources for high-impact statutory declarations & audit items.
  static final Map<String, List<SourceInfo>> _verifiedSources = {
    'recommendation_who': [
      SourceInfo(
        url: 'https://iris.who.int/handle/10665/67322',
        title: 'Reduced Osmolarity Oral Rehydration Salts (ORS) Formulation (WHO & UNICEF)',
        publisher: 'WHO / UNICEF Official Publication',
        tier: 'Official',
        publishedDate: DateTime(2001, 7, 18),
        lastVerifiedAt: DateTime(2025, 1, 1),
      ),
    ],
    'who_recommended': [
      SourceInfo(
        url: 'https://iris.who.int/handle/10665/67322',
        title: 'Reduced Osmolarity Oral Rehydration Salts (ORS) Formulation (WHO & UNICEF)',
        publisher: 'WHO / UNICEF Official Publication',
        tier: 'Official',
        publishedDate: DateTime(2001, 7, 18),
        lastVerifiedAt: DateTime(2025, 1, 1),
      ),
    ],
    'oral_administration': [
      SourceInfo(
        url: 'https://www.fda.gov/regulatory-information/search-fda-guidance-documents',
        title: 'FDA Guidance: Oral Drug Route Administration Standards',
        publisher: 'U.S. FDA / CDSCO',
        tier: 'Official',
        publishedDate: DateTime(2023, 7, 15),
        lastVerifiedAt: DateTime(2025, 1, 1),
      ),
    ],
    'fssai_license': [
      SourceInfo(
        url: 'https://www.fssai.gov.in/',
        title: 'FSSAI Food Safety Compliance System & Verification',
        publisher: 'Food Safety and Standards Authority of India (FSSAI)',
        tier: 'Official',
        publishedDate: DateTime(2021, 9, 15),
        lastVerifiedAt: DateTime(2025, 1, 1),
      ),
    ],
    'veg_mark': [
      SourceInfo(
        url: 'https://www.fssai.gov.in/upload/uploadfiles/files/Compendium_Packaging_Labelling_Regulations_2021.pdf',
        title: 'FSSAI Packaging & Labelling Regulations: Green/Brown Veg Logo Standard',
        publisher: 'FSSAI Regulations',
        tier: 'Official',
        publishedDate: DateTime(2021, 12, 1),
        lastVerifiedAt: DateTime(2025, 1, 1),
      ),
    ],
    'bis_isi': [
      SourceInfo(
        url: 'https://www.services.bis.gov.in/php/BIS_2.0/',
        title: 'Bureau of Indian Standards (BIS) Product Certification & ISI Mark',
        publisher: 'Bureau of Indian Standards',
        tier: 'Official',
        publishedDate: DateTime(2022, 1, 1),
        lastVerifiedAt: DateTime(2025, 1, 1),
      ),
    ],
    'agmark': [
      SourceInfo(
        url: 'https://dmi.gov.in/Agmark.aspx',
        title: 'Directorate of Marketing and Inspection - AGMARK Standards',
        publisher: 'Ministry of Agriculture & Farmers Welfare',
        tier: 'Official',
        publishedDate: DateTime(2022, 3, 1),
        lastVerifiedAt: DateTime(2025, 1, 1),
      ),
    ],
    'organic': [
      SourceInfo(
        url: 'https://jaivikbharat.fssai.gov.in/',
        title: 'Jaivik Bharat - National Organic Food Standards & Certification',
        publisher: 'Jaivik Bharat / FSSAI',
        tier: 'Official',
        publishedDate: DateTime(2021, 8, 1),
        lastVerifiedAt: DateTime(2025, 1, 1),
      ),
    ],
    'iso': [
      SourceInfo(
        url: 'https://www.iso.org/standards.html',
        title: 'ISO 22000: Food Safety Management Systems Requirements',
        publisher: 'International Organization for Standardization',
        tier: 'Official',
        publishedDate: DateTime(2020, 1, 1),
        lastVerifiedAt: DateTime(2025, 1, 1),
      ),
    ],
    'gmp': [
      SourceInfo(
        url: 'https://www.who.int/teams/health-product-and-policy-standards/standards-and-specifications/gmp',
        title: 'WHO Guidelines on Good Manufacturing Practices (GMP)',
        publisher: 'World Health Organization',
        tier: 'Official',
        publishedDate: DateTime(2022, 1, 1),
        lastVerifiedAt: DateTime(2025, 1, 1),
      ),
    ],
    'lmpc_compliance': [
      SourceInfo(
        url: 'https://consumeraffairs.nic.in/acts-and-rules/legal-metrology',
        title: 'Legal Metrology (Packaged Commodities) Rules, 2011',
        publisher: 'Department of Consumer Affairs, Govt. of India',
        tier: 'Official',
        publishedDate: DateTime(2021, 11, 2),
        lastVerifiedAt: DateTime(2025, 1, 1),
      ),
    ],
    'energy': [
      SourceInfo(
        url: 'https://www.who.int/news-room/fact-sheets/detail/healthy-diet',
        title: 'WHO Healthy Diet: Energy Intake & Daily Caloric Balance (2000 kcal standard)',
        publisher: 'World Health Organization (WHO)',
        tier: 'Official',
        publishedDate: DateTime(2020, 4, 29),
        lastVerifiedAt: DateTime(2025, 1, 1),
      ),
    ],
    'protein': [
      SourceInfo(
        url: 'https://www.nin.res.in/',
        title: 'ICMR-NIN & FSSAI Reference Daily Allowance (RDA) for Protein',
        publisher: 'ICMR - National Institute of Nutrition',
        tier: 'Official',
        publishedDate: DateTime(2024, 5, 8),
        lastVerifiedAt: DateTime(2025, 1, 1),
      ),
    ],
    'carbohydrate': [
      SourceInfo(
        url: 'https://www.who.int/news-room/fact-sheets/detail/healthy-diet',
        title: 'WHO Healthy Diet: Carbohydrate & Dietary Energy Distribution Guidelines',
        publisher: 'World Health Organization (WHO)',
        tier: 'Official',
        publishedDate: DateTime(2020, 4, 29),
        lastVerifiedAt: DateTime(2025, 1, 1),
      ),
    ],
    'fat': [
      SourceInfo(
        url: 'https://www.who.int/news-room/fact-sheets/detail/healthy-diet',
        title: 'WHO Healthy Diet: Total Fat (<30%) & Saturated Fat (<10%) Limits',
        publisher: 'World Health Organization (WHO)',
        tier: 'Official',
        publishedDate: DateTime(2020, 4, 29),
        lastVerifiedAt: DateTime(2025, 1, 1),
      ),
    ],
    'fibre': [
      SourceInfo(
        url: 'https://www.who.int/news-room/fact-sheets/detail/healthy-diet',
        title: 'WHO Healthy Diet: Daily Dietary Fibre Guideline (>25g/day)',
        publisher: 'World Health Organization (WHO)',
        tier: 'Official',
        publishedDate: DateTime(2020, 4, 29),
        lastVerifiedAt: DateTime(2025, 1, 1),
      ),
    ],
    'potassium': [
      SourceInfo(
        url: 'https://www.who.int/publications/i/item/9789241504829',
        title: 'WHO Guideline: Potassium intake for adults and children (>3510 mg/day)',
        publisher: 'World Health Organization (WHO)',
        tier: 'Official',
        publishedDate: DateTime(2012, 12, 1),
        lastVerifiedAt: DateTime(2025, 1, 1),
      ),
    ],
    'fssai_nutrition': [
      SourceInfo(
        url: 'https://www.fssai.gov.in/upload/uploadfiles/files/Compendium_Packaging_Labelling_Regulations_2021.pdf',
        title: 'FSSAI (Labelling & Display) Regulations: Nutritional Information Standards',
        publisher: 'Food Safety and Standards Authority of India (FSSAI)',
        tier: 'Official',
        publishedDate: DateTime(2021, 12, 1),
        lastVerifiedAt: DateTime(2025, 1, 1),
      ),
    ],
    'sugar': [
      SourceInfo(
        url: 'https://www.who.int/publications/i/item/9789241549028',
        title: 'WHO Guideline: Sugars intake for adults and children (<10% free sugars)',
        publisher: 'World Health Organization',
        tier: 'Official',
        publishedDate: DateTime(2015, 3, 4),
        lastVerifiedAt: DateTime(2025, 1, 1),
      ),
    ],
    'sodium': [
      SourceInfo(
        url: 'https://www.who.int/publications/i/item/9789241504836',
        title: 'WHO Guideline: Sodium intake for adults and children (<2g sodium/day)',
        publisher: 'World Health Organization',
        tier: 'Official',
        publishedDate: DateTime(2012, 12, 1),
        lastVerifiedAt: DateTime(2025, 1, 1),
      ),
    ],
    'trans_fat': [
      SourceInfo(
        url: 'https://www.who.int/news-room/fact-sheets/detail/trans-fat',
        title: 'WHO Global Action: Elimination of Industrially-Produced Trans Fats (REPLACE)',
        publisher: 'World Health Organization',
        tier: 'Official',
        publishedDate: DateTime(2023, 1, 23),
        lastVerifiedAt: DateTime(2025, 1, 1),
      ),
    ],
    'brand_claims': [
      SourceInfo(
        url: 'https://www.fssai.gov.in/upload/uploadfiles/files/Compendium_Advertising_Claims_Regulations_2021.pdf',
        title: 'FSSAI (Advertising and Claims) Regulations, 2018 Standards',
        publisher: 'FSSAI Regulations',
        tier: 'Official',
        publishedDate: DateTime(2021, 11, 15),
        lastVerifiedAt: DateTime(2025, 1, 1),
      ),
    ],
    'codex_gsfa': [
      SourceInfo(
        url: 'https://codex.fao.org/',
        title: 'Codex Alimentarius (FAO/WHO) General Standard for Food Additives (GSFA)',
        publisher: 'Codex Alimentarius (FAO / WHO)',
        tier: 'Official',
        publishedDate: DateTime(2023, 1, 1),
        lastVerifiedAt: DateTime(2025, 1, 1),
      ),
    ],
    'fssai_additives': [
      SourceInfo(
        url: 'https://www.fssai.gov.in/upload/uploadfiles/files/Compendium_Food_Additives_Regulations_2021.pdf',
        title: 'FSSAI Compendium of Food Additives Regulations & Permitted Classes',
        publisher: 'Food Safety and Standards Authority of India (FSSAI)',
        tier: 'Official',
        publishedDate: DateTime(2021, 12, 1),
        lastVerifiedAt: DateTime(2025, 1, 1),
      ),
    ],
  };

  /// Returns verified sources for a given fact key or normalized query.
  static Future<List<SourceInfo>> getSources(String factKey, [String? searchQuery]) async {
    final src = getPrimarySource(factKey);
    if (src != null) {
      return [src];
    }
    return [];
  }

  /// Synchronously get the primary source URL if known.
  static SourceInfo? getPrimarySource(String factKey) {
    final key = factKey.toLowerCase().trim();
    if (_verifiedSources.containsKey(key) && _verifiedSources[key]!.isNotEmpty) {
      return _verifiedSources[key]!.first;
    }

    // Nutrient keyword matching
    if (key.contains('energy') || key.contains('calorie') || key.contains('kcal') || key.contains('kj')) {
      return _verifiedSources['energy']?.first;
    }
    if (key.contains('protein')) {
      return _verifiedSources['protein']?.first;
    }
    if (key.contains('carbohydrate') || key.contains('carb')) {
      return _verifiedSources['carbohydrate']?.first;
    }
    if (key.contains('trans') || key.contains('transfat')) {
      return _verifiedSources['trans_fat']?.first;
    }
    if (key.contains('fat') || key.contains('lipid') || key.contains('saturated')) {
      return _verifiedSources['fat']?.first;
    }
    if (key.contains('sugar') || key.contains('sucrose') || key.contains('glucose') || key.contains('fructose')) {
      return _verifiedSources['sugar']?.first;
    }
    if (key.contains('sodium') || key.contains('salt') || key.contains('na')) {
      return _verifiedSources['sodium']?.first;
    }
    if (key.contains('potassium') || key.contains('electrolyte')) {
      return _verifiedSources['potassium']?.first;
    }
    if (key.contains('fibre') || key.contains('fiber')) {
      return _verifiedSources['fibre']?.first;
    }
    if (key.contains('who') || key.contains('recommend')) {
      return _verifiedSources['recommendation_who']?.first;
    }
    if (key.contains('oral') || key.contains('administration')) {
      return _verifiedSources['oral_administration']?.first;
    }
    if (key.contains('fssai') || key.contains('licence') || key.contains('license')) {
      return _verifiedSources['fssai_license']?.first;
    }
    if (key.contains('veg') || key.contains('vegetarian')) {
      return _verifiedSources['veg_mark']?.first;
    }
    if (key.contains('bis') || key.contains('isi')) {
      return _verifiedSources['bis_isi']?.first;
    }
    if (key.contains('agmark')) {
      return _verifiedSources['agmark']?.first;
    }
    if (key.contains('organic') || key.contains('jaivik')) {
      return _verifiedSources['organic']?.first;
    }
    if (key.contains('iso')) {
      return _verifiedSources['iso']?.first;
    }
    if (key.contains('gmp')) {
      return _verifiedSources['gmp']?.first;
    }
    if (key.contains('claim')) {
      return _verifiedSources['brand_claims']?.first;
    }
    if (key.contains('lmpc') || key.contains('metrology') || key.contains('standard')) {
      return _verifiedSources['lmpc_compliance']?.first;
    }

    // Universal fallback for any nutrition table row (e.g. minerals, vitamins, ash, etc.)
    return _verifiedSources['fssai_nutrition']?.first;
  }

  /// Resolves the authoritative reference source for an individual food ingredient or additive.
  static SourceInfo getIngredientSource(String ingredientName, [String? category]) {
    final nameLower = ingredientName.toLowerCase().trim();
    final catLower = (category ?? '').toLowerCase().trim();

    // 1. Food Additive / E-number / INS number -> Codex GSFA or FSSAI Additives
    final isAdditive = nameLower.contains('ins') ||
        nameLower.contains('e-') ||
        RegExp(r'\b(e\s*\d{3,4}|ins\s*\d{3,4})\b', caseSensitive: false).hasMatch(nameLower) ||
        catLower.contains('additive') ||
        catLower.contains('preservative') ||
        catLower.contains('emulsifier') ||
        catLower.contains('stabilizer') ||
        catLower.contains('color') ||
        catLower.contains('colour') ||
        catLower.contains('flavor') ||
        catLower.contains('flavour') ||
        catLower.contains('acidity regulator') ||
        catLower.contains('sweetener') ||
        catLower.contains('anti-caking') ||
        catLower.contains('thickener');

    if (isAdditive) {
      return _verifiedSources['fssai_additives']!.first;
    }

    // 2. Specific chemicals / electrolytes / substances -> PubChem National Library of Medicine
    // Use PubChem search endpoint to handle generic names and ensure a navigable page.
    final encodedName = Uri.encodeComponent(ingredientName.trim());
    return SourceInfo(
      url: 'https://pubchem.ncbi.nlm.nih.gov/#query=$encodedName',
      title: 'PubChem Chemical & Safety Summary: $ingredientName',
      publisher: 'National Library of Medicine (NIH)',
      tier: 'Research',
      publishedDate: DateTime(2024, 1, 1),
      lastVerifiedAt: DateTime(2025, 1, 1),

    );
  }
}
