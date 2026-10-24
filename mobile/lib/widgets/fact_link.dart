import 'package:flutter/material.dart';
import 'source_chip.dart';

/// Wraps any UI element with a source-chip lookup.
///
/// [factKey] - stable identifier for the fact (e.g. 'recommendation_who').
/// [searchQuery] - free-text used to fetch relevant sources.
/// [child] - the widget you want to display (usually a [Container] or [Text]).
class FactLink extends StatelessWidget {
  final String factKey;
  final String searchQuery;
  final Widget child;

  const FactLink({
    super.key,
    required this.factKey,
    required this.searchQuery,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        child,
        const SizedBox(height: 4),
        // Show source chips only when sources are found.
        SourceChipWrapper(factKey: factKey, searchQuery: searchQuery),
      ],
    );
  }
}
