import 'package:flutter/material.dart';

/// Configuration for nutrient benchmark thresholds per 100g.
/// Values are based on generic health guidelines (FSSAI / WHO). Adjust as needed.
const Map<String, double> _benchmarkLimits = {
  // Limiting nutrients – higher than this is considered unhealthy.
  'sugar': 10.0, // grams per 100g
  'saturated_fat': 5.0, // grams per 100g
  'trans_fat': 0.5, // grams per 100g
  'sodium': 0.3, // grams (300 mg) per 100g
  // Boost nutrients – higher is beneficial.
  'protein': 5.0, // grams per 100g
  'fibre': 3.0, // grams per 100g
};

/// Deterministic algorithm that converts nutrient ratios into a 0‑5 star rating.
/// The algorithm is fully transparent – each nutrient contributes a weighted
/// increment/decrement. The final rating is clamped to the nearest 0.5 step.
class _HealthStarCalculator {
  final Map<String, dynamic> nutritionTable;

  _HealthStarCalculator(this.nutritionTable);

  double _toDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  /// Compute the raw score before rounding. Starts from a neutral base of 2.5.
  double _rawScore() {
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
      final value = _toDouble(nutritionTable[name]);
      final limit = _benchmarkLimits[name] ?? 0.0;
      if (limit > 0 && value > 0) {
        final ratio = value / limit;
        if (ratio >= 1) {
          // Penalty proportional to excess (capped to 2× limit).
          score -= weight * (ratio - 1).clamp(0.0, 2.0);
        }
      }
    }
    // Rewards for beneficial nutrients.
    const Map<String, double> boostWeights = {
      'protein': 0.3,
      'fibre': 0.2,
    };
    for (final entry in boostWeights.entries) {
      final name = entry.key;
      final weight = entry.value;
      final value = _toDouble(nutritionTable[name]);
      final limit = _benchmarkLimits[name] ?? 0.0;
      if (limit > 0 && value > 0) {
        final ratio = value / limit;
        if (ratio >= 1) {
          score += weight * (ratio - 1).clamp(0.0, 2.0);
        }
      }
    }
    return score;
  }

  /// Convert raw score to a 0‑5 star rating with 0.5 steps.
  double rating() {
    double raw = _rawScore();
    raw = raw.clamp(0.0, 5.0);
    return (raw * 2).round() / 2.0;
  }
}

/// Widget that displays the consumer health star rating.
/// It receives the full scan `item` map, extracts the nutrition table and
/// calculates a deterministic rating. The UI shows star icons and a tooltip
/// explaining the breakdown.
class HealthStarRating extends StatelessWidget {
  final Map<String, dynamic> item;

  const HealthStarRating({Key? key, required this.item}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final Map<String, dynamic> nutrition = (item['nutrition_table'] as Map?)?.cast<String, dynamic>() ?? {};
    final calculator = _HealthStarCalculator(nutrition);
    final double stars = calculator.rating();

    // Build star icons (full, half, empty).
    List<Widget> starWidgets = [];
    for (int i = 1; i <= 5; i++) {
      if (stars >= i) {
        starWidgets.add(const Icon(Icons.star, size: 20, color: Colors.amber));
      } else if (stars >= i - 0.5) {
        starWidgets.add(const Icon(Icons.star_half, size: 20, color: Colors.amber));
      } else {
        starWidgets.add(const Icon(Icons.star_border, size: 20, color: Colors.grey));
      }
    }

    final String tooltip = _buildTooltip(calculator, nutrition);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          const Text('Health Rating', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(width: 8),
          Tooltip(
            message: tooltip,
            child: Row(children: starWidgets),
          ),
        ],
      ),
    );
  }

  String _buildTooltip(_HealthStarCalculator calc, Map<String, dynamic> nutrition) {
    final buffer = StringBuffer();
    buffer.writeln('Rating derived from per‑100g nutrition values.');
    buffer.writeln('Limits (higher → penalty):');
    for (final key in ['sugar', 'saturated_fat', 'trans_fat', 'sodium']) {
      final val = calc._toDouble(nutrition[key]);
      final limit = _benchmarkLimits[key];
      buffer.writeln('- $key: ${val.toStringAsFixed(1)} g / ${limit?.toStringAsFixed(1)} g');
    }
    buffer.writeln('Boosts (higher → reward):');
    for (final key in ['protein', 'fibre']) {
      final val = calc._toDouble(nutrition[key]);
      final limit = _benchmarkLimits[key];
      buffer.writeln('- $key: ${val.toStringAsFixed(1)} g / ${limit?.toStringAsFixed(1)} g');
    }
    buffer.writeln('Final rating: ${calc.rating()} ★');
    return buffer.toString();
  }
}
