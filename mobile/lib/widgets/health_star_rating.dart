import 'package:flutter/material.dart';

/// Configuration for nutrient benchmark thresholds per 100g.
/// Values are based on generic health guidelines (FSSAI / WHO).
const Map<String, double> _benchmarkLimits = {
  // Limiting nutrients – higher than this is considered unhealthy.
  'sugar': 10.0, // grams per 100g
  'saturated_fat': 5.0, // grams per 100g
  'trans_fat': 0.5, // grams per 100g
  'sodium': 0.3, // grams (300 mg) per 100g
  // Boost nutrients – higher is beneficial.
  'protein': 5.0, // grams per 100g
  'fibre': 3.0, // grams per 100g
};

/// Deterministic algorithm that converts nutrient ratios into a 0.5–5 star rating.
/// Supports Map, List of nutrient rows, or root item maps from the backend.
class HealthStarCalculator {
  final Map<String, double> parsedNutrients = {};
  bool _hasNutritionData = false;

  bool get hasNutritionData => _hasNutritionData;

  HealthStarCalculator(dynamic rawData) {
    _parse(rawData);
  }

  void _parse(dynamic rawData) {
    if (rawData == null) return;

    dynamic target = rawData;
    if (target is Map) {
      if (target['type'] == 'COMPLAINT') return;

      if (target.containsKey('nutrition_table') && target['nutrition_table'] != null) {
        target = target['nutrition_table'];
      } else if (target['extracted_declarations'] is Map &&
          (target['extracted_declarations'] as Map).containsKey('nutrition_table')) {
        target = target['extracted_declarations']['nutrition_table'];
      } else if (target['declarations'] is Map &&
          (target['declarations'] as Map).containsKey('nutrition_table')) {
        target = target['declarations']['nutrition_table'];
      }
    }

    if (target is List) {
      for (final item in target) {
        if (item is Map) {
          final name = (item['nutrient'] ?? item['name'] ?? item['key'] ?? '').toString();
          final val = item['per_100g'] ?? item['per100g'] ?? item['value'] ?? item['per_serving'];
          final unit = (item['unit'] ?? '').toString();
          _assignNutrient(name, val, unit);
        }
      }
    } else if (target is Map) {
      for (final entry in target.entries) {
        _assignNutrient(entry.key.toString(), entry.value, '');
      }
    }

    // Fallback: If no nutrients found yet and rawData contains all_detected_text
    if (!_hasNutritionData && rawData is Map) {
      final allText = (rawData['all_detected_text'] ?? '').toString();
      if (allText.isNotEmpty) {
        final reg = RegExp(
          r'(Energy|Calories|Protein|Carbohydrate|Sugar|Total Sugar|Added Sugar|Total Fat|Saturated Fat|Trans Fat|Sodium|Salt|Fiber|Fibre)[:\s]+([0-9.]+\s*[a-zA-Z%]*)',
          caseSensitive: false,
        );
        for (final match in reg.allMatches(allText)) {
          final name = match.group(1)!;
          final val = match.group(2)!;
          _assignNutrient(name, val, '');
        }
      }
    }
  }

  double _parseVal(dynamic v, String unitHint, {bool isSodium = false}) {
    if (v == null) return 0.0;
    if (v is num) {
      double numVal = v.toDouble();
      if (isSodium && numVal > 5.0) {
        return numVal / 1000.0; // mg to grams
      }
      return numVal;
    }
    final str = v.toString().trim().toLowerCase();
    if (str.isEmpty || str == 'null' || str == 'nil' || str == 'none' || str == '—' || str == '-') {
      return 0.0;
    }
    bool isLessThan = str.contains('<');
    final numMatch = RegExp(r'([0-9]+(?:\.[0-9]+)?)').firstMatch(str);
    if (numMatch == null) return 0.0;
    double parsed = double.tryParse(numMatch.group(1)!) ?? 0.0;
    if (isLessThan) parsed = parsed / 2.0;

    bool isMg = str.contains('mg') || unitHint.toLowerCase().contains('mg');
    if (isSodium) {
      if (isMg || parsed > 5.0) {
        parsed = parsed / 1000.0; // convert mg to grams
      }
    }
    return parsed;
  }

  void _assignNutrient(String rawName, dynamic rawVal, String unitHint) {
    if (rawVal == null) return;
    final nameLower = rawName.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), ' ');

    if (nameLower.contains('trans fat') || nameLower.contains('trans fatty')) {
      final val = _parseVal(rawVal, unitHint);
      parsedNutrients['trans_fat'] = val;
      _hasNutritionData = true;
    } else if (nameLower.contains('saturated') || nameLower.contains('sat fat')) {
      final val = _parseVal(rawVal, unitHint);
      parsedNutrients['saturated_fat'] = val;
      _hasNutritionData = true;
    } else if (nameLower.contains('sugar') || nameLower.contains('sugars')) {
      final val = _parseVal(rawVal, unitHint);
      parsedNutrients['sugar'] = val;
      _hasNutritionData = true;
    } else if (nameLower.contains('sodium')) {
      final val = _parseVal(rawVal, unitHint, isSodium: true);
      parsedNutrients['sodium'] = val;
      _hasNutritionData = true;
    } else if (nameLower.contains('salt')) {
      final val = _parseVal(rawVal, unitHint);
      parsedNutrients['sodium'] = val / 2.5; // Sodium is ~ Salt / 2.5
      _hasNutritionData = true;
    } else if (nameLower.contains('protein')) {
      final val = _parseVal(rawVal, unitHint);
      parsedNutrients['protein'] = val;
      _hasNutritionData = true;
    } else if (nameLower.contains('fibre') || nameLower.contains('fiber')) {
      final val = _parseVal(rawVal, unitHint);
      parsedNutrients['fibre'] = val;
      _hasNutritionData = true;
    }
  }

  double _rawScore() {
    if (!_hasNutritionData) return 3.0;
    double score = 2.5;

    // Penalties for limiting nutrients.
    const Map<String, double> limitWeights = {
      'sugar': 0.6,
      'saturated_fat': 0.5,
      'trans_fat': 0.8,
      'sodium': 0.4,
    };
    for (final entry in limitWeights.entries) {
      final name = entry.key;
      final weight = entry.value;
      final value = parsedNutrients[name] ?? 0.0;
      final limit = _benchmarkLimits[name] ?? 0.0;
      if (limit > 0 && value > 0) {
        final ratio = value / limit;
        if (ratio >= 1.0) {
          score -= weight * (ratio - 1.0).clamp(0.0, 2.0);
        } else {
          score += (1.0 - ratio) * 0.2; // Bonus for low limiting nutrient
        }
      }
    }

    // Rewards for beneficial nutrients.
    const Map<String, double> boostWeights = {
      'protein': 0.4,
      'fibre': 0.3,
    };
    for (final entry in boostWeights.entries) {
      final name = entry.key;
      final weight = entry.value;
      final value = parsedNutrients[name] ?? 0.0;
      final limit = _benchmarkLimits[name] ?? 0.0;
      if (limit > 0 && value > 0) {
        final ratio = value / limit;
        score += weight * ratio.clamp(0.0, 2.0);
      }
    }
    return score;
  }

  /// Convert raw score to a 0.5–5 star rating with 0.5 steps.
  double rating() {
    double raw = _rawScore();
    raw = raw.clamp(0.5, 5.0);
    return (raw * 2).round() / 2.0;
  }

  double toDouble(String nutrient) {
    return parsedNutrients[nutrient] ?? 0.0;
  }
}

/// Widget that displays the consumer health star rating.
/// Receives the full scan `item` map, extracts the nutrition table, and
/// displays a deterministic 0.5-5 star health rating with an informative tooltip.
class HealthStarRating extends StatelessWidget {
  final Map<String, dynamic> item;

  const HealthStarRating({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    if (item['type'] == 'COMPLAINT') {
      return const SizedBox.shrink();
    }

    final calculator = HealthStarCalculator(item);
    if (!calculator.hasNutritionData) {
      return const SizedBox.shrink();
    }

    final double stars = calculator.rating();

    // Build star icons (full, half, empty).
    List<Widget> starWidgets = [];
    for (int i = 1; i <= 5; i++) {
      if (stars >= i) {
        starWidgets.add(const Icon(Icons.star_rounded, size: 18, color: Color(0xFFFBBF24)));
      } else if (stars >= i - 0.5) {
        starWidgets.add(const Icon(Icons.star_half_rounded, size: 18, color: Color(0xFFFBBF24)));
      } else {
        starWidgets.add(const Icon(Icons.star_rounded, size: 18, color: Color(0xFFE2E8F0)));
      }
    }

    final String tooltip = _buildTooltip(calculator);

    return Padding(
      padding: const EdgeInsets.only(top: 8.0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.85),
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
            const Row(
              children: [
                Icon(Icons.health_and_safety_rounded, size: 16, color: Color(0xFF059669)),
                SizedBox(width: 8),
                Text(
                  'FSSAI Health Star Rating',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ],
            ),
            Tooltip(
              message: tooltip,
              child: Row(
                children: [
                  Row(children: starWidgets),
                  const SizedBox(width: 6),
                  Text(
                    '${stars.toStringAsFixed(1)} ★',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                      color: Color(0xFFD97706),
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

  String _buildTooltip(HealthStarCalculator calc) {
    final buffer = StringBuffer();
    buffer.writeln('FSSAI / WHO Nutrient Benchmarks (per 100g):');
    buffer.writeln('Limits (lower is healthier):');
    for (final key in ['sugar', 'saturated_fat', 'trans_fat', 'sodium']) {
      final val = calc.toDouble(key);
      final limit = _benchmarkLimits[key];
      buffer.writeln('• $key: ${val.toStringAsFixed(2)} g (Benchmark: ${limit?.toStringAsFixed(1)} g)');
    }
    buffer.writeln('Boosts (higher is healthier):');
    for (final key in ['protein', 'fibre']) {
      final val = calc.toDouble(key);
      final limit = _benchmarkLimits[key];
      buffer.writeln('• $key: ${val.toStringAsFixed(2)} g (Benchmark: ${limit?.toStringAsFixed(1)} g)');
    }
    buffer.writeln('Calculated Rating: ${calc.rating()} ★');
    return buffer.toString();
  }
}
