import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/source_registry.dart';

/// A simple wrapper that fetches and displays source chips for a given fact.
class SourceChipWrapper extends StatelessWidget {
  final String factKey;
  final String searchQuery;

  const SourceChipWrapper({
    super.key,
    required this.factKey,
    required this.searchQuery,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<SourceInfo>>(
      future: SourceRegistry.getSources(factKey, searchQuery),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox.shrink(); // keep UI clean while loading
        }
        final sources = snapshot.data ?? [];
        if (sources.isEmpty) {
          return const SizedBox.shrink();
        }
        return Wrap(
          spacing: 8,
          runSpacing: 4,
          children: sources.map((src) => _buildChip(context, src)).toList(),
        );
      },
    );
  }

  Widget _buildChip(BuildContext context, SourceInfo src) {
    final tierBadge = _tierBadge(src.tier);
    return ActionChip(
      avatar: const Icon(Icons.open_in_new_rounded, size: 13, color: Color(0xFF0F766E)),
      backgroundColor: const Color(0xFFF0FDFA),
      side: const BorderSide(color: Color(0xFF99F6E4)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              src.publisher,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Color(0xFF0F766E),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 5),
          tierBadge,
        ],
      ),
      onPressed: () async {
        final uri = Uri.tryParse(src.url);
        if (uri != null) {
          try {
            if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
              await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
            }
          } catch (_) {
            try {
              await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
            } catch (_) {}
          }
        }
      },
    );
  }

  Widget _tierBadge(String tier) {
    Color bg;
    switch (tier) {
      case 'Official':
        bg = const Color(0xFF059669);
        break;
      case 'Research':
        bg = const Color(0xFF2563EB);
        break;
      case 'News':
        bg = const Color(0xFFD97706);
        break;
      default:
        bg = const Color(0xFF64748B);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
      child: Text(tier, style: const TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.bold)),
    );
  }
}
