import 'package:flutter/material.dart';
import '../../services/connectivity_service.dart';
import '../../l10n/app_localizations.dart';

class OfflineBanner extends StatefulWidget {
  const OfflineBanner({super.key});

  @override
  State<OfflineBanner> createState() => _OfflineBannerState();
}

class _OfflineBannerState extends State<OfflineBanner> {
  @override
  void initState() {
    super.initState();
    ConnectivityService.instance.addListener(_onConnChange);
  }

  void _onConnChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    ConnectivityService.instance.removeListener(_onConnChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (ConnectivityService.instance.isReachable) {
      return const SizedBox.shrink(); // Hide when online
    }

    return Container(
      width: double.infinity,
      color: Colors.red.shade600,
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
      child: SafeArea(
        bottom: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off, color: Colors.white, size: 16),
            const SizedBox(width: 8),
            Text(
              AppLocalizations.of(context)?.offline_banner_text ?? 'You are offline. Claims will be saved.',
              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}
