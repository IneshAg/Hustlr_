import 'dart:async';
import 'dart:ui';


import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'core/router/app_router.dart';
import 'core/services/storage_service.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_provider.dart';
import 'l10n/app_localizations.dart';
import 'providers/locale_provider.dart';

import 'package:provider/provider.dart';
import 'services/mock_data_service.dart';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'blocs/claims/claims_bloc.dart';
import 'blocs/claims/claims_event.dart';
import 'blocs/policy/policy_bloc.dart';
import 'services/api_service.dart';
import 'services/shift_tracking_service.dart';
import 'services/notification_service.dart';
import 'firebase_options.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await NotificationService.showBackgroundNotification(message);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Setup fallback error UI immediately
  ErrorWidget.builder = (FlutterErrorDetails details) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 48),
                const SizedBox(height: 16),
                const Text('Hustlr failed to start.',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(details.exception.toString(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
          ),
        ),
      ),
    );
  };

  // 2. Core initialization (Hive + Storage)
  // We must have these to build the Provider tree.
  try {
    await Hive.initFlutter();
    if (!Hive.isBoxOpen('appData')) {
      await Hive.openBox('appData');
    }
    await StorageService.init();
  } catch (e) {
    debugPrint('FATAL: Storage init failed: $e');
  }

  // 3. Background Services (Firebase + GPS Restoration)
  // We trigger these but do NOT block the UI thread waiting for them.
  _startBackgroundServices();

  // 4. Mount App
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) {
            final provider = LocaleProvider();
            unawaited(provider.loadSavedLocale());
            return provider;
          },
        ),
        ChangeNotifierProvider(
          create: (_) => ThemeProvider(appBox: Hive.box('appData')),
        ),
        ChangeNotifierProvider(create: (_) => MockDataService()),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider<ClaimsBloc>(
            create: (context) {
              final bloc = ClaimsBloc(
                apiService: ApiService.instance,
                supabase: null,
              );
              final mockSvc = context.read<MockDataService>();
              mockSvc.onClaimApproved = (claim) {
                bloc.add(ClaimStatusUpdated(claim));
              };
              return bloc;
            },
          ),
          BlocProvider<PolicyBloc>(
            create: (_) => PolicyBloc(apiService: ApiService.instance),
          ),
        ],
        child: const ShieldGigApp(),
      ),
    ),
  );
}

/// Robust background initialization that won't block the splash screen.
Future<void> _startBackgroundServices() async {
  try {
    // Initialize Firebase
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // Setup Notifications
    await NotificationService.initialize();

    // Restore shift state
    await ShiftTrackingService.instance.restoreActiveShiftOnLaunch();
  } catch (e, stack) {
    debugPrint('Background init error: $e\n$stack');
  }
}


class ShieldGigApp extends StatelessWidget {
  const ShieldGigApp({super.key});

  @override
  Widget build(BuildContext context) {
    final locale = context.watch<LocaleProvider>().locale;
    final themeMode = context.watch<ThemeProvider>().themeMode;

    return MaterialApp.router(
      title: 'Hustlr',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      locale: locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: appRouter,
    );
  }
}
