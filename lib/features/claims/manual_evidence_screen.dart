import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/router/app_router.dart';
import '../../l10n/app_localizations.dart';

class ManualEvidenceScreen extends StatefulWidget {
  const ManualEvidenceScreen({super.key});

  @override
  State<ManualEvidenceScreen> createState() => _ManualEvidenceScreenState();
}

class _ManualEvidenceScreenState extends State<ManualEvidenceScreen> {
  String? _selectedType;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    final l10n = AppLocalizations.of(context)!;

    final List<Map<String, dynamic>> types = [
      {
        'id': 'road_blocked',
        'title': l10n.manual_claim_road_blocked,
        'desc': l10n.manual_claim_road_desc,
        'icon': Icons.construction_rounded,
      },
      {
        'id': 'dark_store_closed',
        'title': l10n.manual_claim_dark_store,
        'desc': l10n.manual_claim_dark_desc,
        'icon': Icons.storefront_rounded,
      },
      {
        'id': 'internet_outage',
        'title': l10n.manual_claim_internet_outage,
        'desc': l10n.manual_claim_internet_desc,
        'icon': Icons.wifi_off_rounded,
      },
      {
        'id': 'other',
        'title': l10n.manual_claim_other,
        'desc': l10n.manual_claim_other_desc,
        'icon': Icons.warning_amber_rounded,
      },
    ];

    return Scaffold(
      backgroundColor: theme.canvasColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        title: Text(
          l10n.manual_claim_title,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: theme.colorScheme.onSurface,
            letterSpacing: -0.5,
          ),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: theme.colorScheme.onSurface),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                physics: const BouncingScrollPhysics(),
                children: types.map((type) => _buildCard(type, primaryColor)).toList(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  elevation: 0,
                  backgroundColor: _selectedType != null ? primaryColor : primaryColor.withValues(alpha: 0.3),
                  foregroundColor: Colors.black, // Dark text on green for Hustlr
                  minimumSize: const Size(double.infinity, 64),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
                ),
                onPressed: _selectedType != null
                    ? () {
                        // Pass disruption type to next screen
                        context.push(
                          Uri(
                            path: AppRoutes.manualClaimCamera,
                            queryParameters: {'disruptionType': _selectedType!},
                          ).toString(),
                        );
                      }
                    : null,
                child: Text(l10n.manual_claim_continue, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard(Map<String, dynamic> type, Color primaryColor) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isSelected = _selectedType == type['id'];
    return GestureDetector(
      onTap: () => setState(() => _selectedType = type['id']),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? primaryColor : theme.dividerColor,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isDark ? [] : [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: isSelected ? primaryColor : primaryColor.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                type['icon'],
                color: isSelected ? theme.colorScheme.onPrimary : primaryColor,
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    type['title'],
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    type['desc'],
                    style: TextStyle(
                      fontSize: 13,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
            ),
          ],
        ),
      ),
    );
  }
}
