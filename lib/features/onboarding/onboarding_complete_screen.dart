import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../core/router/app_router.dart';
import '../../core/services/storage_service.dart';
import '../../services/mock_data_service.dart';
import '../../shared/widgets/primary_button.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

class OnboardingCompleteScreen extends StatelessWidget {
  const OnboardingCompleteScreen({super.key});

  Future<void> _goToDashboard(BuildContext context) async {
    try {
      if (Hive.isBoxOpen('appData')) {
        await Hive.box('appData').put('onboardingComplete', true);
      }
    } catch (_) {
      // Keep flow alive even if Hive is temporarily unavailable.
    }
    await StorageService.setLoggedIn(true);
    await StorageService.setOnboarded(true);
    context.go(AppRoutes.dashboard);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final mockData = Provider.of<MockDataService>(context);
    final worker = mockData.worker;

    final chips = [
      ('Zone', '${worker.zone}, ${worker.city}'),
      ('Platform', worker.platform),
    ];

    return Scaffold(
      backgroundColor: theme.canvasColor,
      body: SafeArea(
        top: true,
        bottom: false,
        child: Column(
          children: [
            // Top App Bar Area
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 20, 28, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'HUSTLR',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: theme.colorScheme.primary,
                      letterSpacing: 2.0,
                    ),
                  ),
                  IconButton(
                    onPressed: () => _goToDashboard(context),
                    icon: Icon(Icons.close_rounded, color: theme.colorScheme.onSurface),
                  )
                ],
              ),
            ),

            const Spacer(),

            // Graphic / Illustration
            Container(
              width: 140, height: 140,
              decoration: BoxDecoration(
                color: theme.cardColor,
                shape: BoxShape.circle,
                boxShadow: isDark ? [
                  BoxShadow(color: theme.colorScheme.primary.withValues(alpha: 0.05), blurRadius: 40, offset: const Offset(0, 10))
                ] : [
                  BoxShadow(color: theme.colorScheme.primary.withValues(alpha: 0.15), blurRadius: 50, offset: const Offset(0, 20))
                ],
              ),
              child: Icon(Icons.verified_rounded, size: 64, color: theme.colorScheme.primary),
            ),

            const SizedBox(height: 48),

            // Headline
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    'SUCCESS',
                    style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.primary),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    worker.name.trim().isEmpty 
                        ? "You're all set!"
                        : "You're all set, ${worker.name.trim()}.",
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 48),

            // Info Card — Zone + Platform chips only; no ISS score shown to workers
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 28),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: theme.cardColor,
                borderRadius: BorderRadius.circular(isDark ? 32 : 24),
                boxShadow: isDark ? [] : [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 20, offset: const Offset(0, 8))
                ],
              ),
              child: Column(
                children: [
                  ...chips.map((chip) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        Icon(Icons.check_circle_rounded, color: theme.colorScheme.primary, size: 20),
                        const SizedBox(width: 12),
                        Text('${chip.$1}: ', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6))),
                        Expanded(child: Text(chip.$2, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold))),
                      ],
                    ),
                  )),
                  const SizedBox(height: 8),
                  Text(
                    'Your personalized protection plan is ready.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),

            const Spacer(),

            // Permission Request & Continue Button Strip
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                children: [
                  Text(
                    "Hustlr monitors your zone position during shifts to protect your payouts. Location tracking runs only when you are working.",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 24),
                    child: PrimaryButton(
                      text: 'Enable Zone Protection →',
                      onPressed: () async {
                        if (kIsWeb) {
                          // permission_handler is not implemented on web.
                          try {
                            await Geolocator.getCurrentPosition(
                              locationSettings: const LocationSettings(
                                accuracy: LocationAccuracy.high,
                                timeLimit: Duration(seconds: 8),
                              ),
                            );
                          } catch (_) {}
                          if (context.mounted) await _goToDashboard(context);
                          return;
                        }
                        final status = await Permission.locationWhenInUse.request();
                        if (!status.isGranted) return;

                        try {
                          await Geolocator.getCurrentPosition(
                            locationSettings: const LocationSettings(
                              accuracy: LocationAccuracy.high,
                              timeLimit: Duration(seconds: 8),
                            ),
                          );
                        } catch (_) {}

                        if (context.mounted) await _goToDashboard(context);
                      },
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
}
