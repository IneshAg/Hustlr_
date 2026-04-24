import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/router/app_router.dart';
import '../../services/storage_service.dart';
import '../../services/notification_service.dart';
import '../../shared/widgets/primary_button.dart';
import '../../l10n/app_localizations.dart';

/// Separate consent for location, identity photos / ML, and payouts (DPDP-style).
class KycDataConsentScreen extends StatefulWidget {
  const KycDataConsentScreen({super.key});

  @override
  State<KycDataConsentScreen> createState() => _KycDataConsentScreenState();
}

class _KycDataConsentScreenState extends State<KycDataConsentScreen> {
  bool _location = false;
  bool _identity = false;
  bool _payout = false;

  bool get _allChecked => _location && _identity && _payout;

  Future<void> _onContinue() async {
    if (!_allChecked) return;
    await StorageService.setKycDataConsentAccepted(true);

    // Ask runtime permissions only after explicit consent.
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS)) {
      await [
        Permission.notification,
        Permission.activityRecognition,
      ].request();

      try {
        await NotificationService.syncDevicePushToken();
      } catch (_) {}
    }

    if (!mounted) return;
    context.go(AppRoutes.onboarding);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: theme.canvasColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () => context.go(AppRoutes.carousel),
        ),
        title: Text(
          l10n.kyc_consent_title,
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                children: [
                  Text(
                    l10n.kyc_consent_intro,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      height: 1.5,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.85),
                    ),
                  ),
                  const SizedBox(height: 24),
                  _ConsentCard(
                    icon: Icons.location_on_outlined,
                    title: l10n.kyc_consent_location_title,
                    body: l10n.kyc_consent_location_body,
                    value: _location,
                    onChanged: (v) => setState(() => _location = v ?? false),
                  ),
                  const SizedBox(height: 16),
                  _ConsentCard(
                    icon: Icons.face_retouching_natural_outlined,
                    title: l10n.kyc_consent_identity_title,
                    body: l10n.kyc_consent_identity_body,
                    value: _identity,
                    onChanged: (v) => setState(() => _identity = v ?? false),
                  ),
                  const SizedBox(height: 16),
                  _ConsentCard(
                    icon: Icons.account_balance_outlined,
                    title: l10n.kyc_consent_payout_title,
                    body: l10n.kyc_consent_payout_body,
                    value: _payout,
                    onChanged: (v) => setState(() => _payout = v ?? false),
                  ),
                  const SizedBox(height: 16),
                  TextButton.icon(
                    onPressed: () => context.push(AppRoutes.insuranceCompliance),
                    icon: Icon(Icons.policy_outlined, size: 18, color: theme.colorScheme.primary),
                    label: Text(
                      l10n.kyc_consent_view_compliance,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: PrimaryButton(
                text: l10n.kyc_consent_continue,
                onPressed: _allChecked ? _onContinue : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConsentCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final bool value;
  final ValueChanged<bool?> onChanged;
  const _ConsentCard({
    required this.icon,
    required this.title,
    required this.body,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.cardColor,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () => onChanged(!value),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, color: theme.colorScheme.primary, size: 26),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Checkbox(
                    value: value,
                    onChanged: onChanged,
                    activeColor: theme.colorScheme.primary,
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(left: 38),
                child: Text(
                  body,
                  style: theme.textTheme.bodySmall?.copyWith(
                    height: 1.45,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.72),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
