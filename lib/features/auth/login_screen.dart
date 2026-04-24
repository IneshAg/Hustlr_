import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../core/router/app_router.dart';
import '../../shared/widgets/primary_button.dart';
import '../../widgets/language_switcher.dart';
import '../../l10n/app_localizations.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phoneController = TextEditingController();

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  void _sendOtp() {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty || phone.length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please enter a valid 10-digit number'),
          backgroundColor: Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ),
      );
      return;
    }
    
    // Always start in non-demo mode so real backend persistence is used.
    final box = Hive.isBoxOpen('appData')
        ? Hive.box('appData')
        : null;
    if (box != null) {
      box.put('isDemoSession', false);
    }
    
    context.push('${AppRoutes.otp}?phone=${Uri.encodeComponent(phone)}');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: theme.canvasColor,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, // Left aligned asymmetric
            children: [
              const SizedBox(height: 20),

              Text(
                'Hustlr',
                style: theme.textTheme.displayLarge?.copyWith(
                  color: theme.colorScheme.primary,
                  fontSize: 40,
                  shadows: [
                    Shadow(
                      color: theme.colorScheme.primary.withValues(alpha: isDark ? 0.3 : 0.15),
                      blurRadius: isDark ? 24 : 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                l10n.login_title,
                style: theme.textTheme.displayMedium?.copyWith(height: 1.1),
              ),
              const SizedBox(height: 8),
              Text(
                l10n.login_subtitle,
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.textTheme.bodySmall?.color),
              ),
              const SizedBox(height: 16),

              // ── Static Graphic ───────────────────────────────
              Center(
                child: Container(
                  width: double.infinity,
                  height: 100,
                  decoration: BoxDecoration(
                    color: theme.cardColor,
                    borderRadius: BorderRadius.circular(24),
                    // Elevation defined purely by ambient shadow or zero shadow
                    boxShadow: isDark ? [] : [
                      BoxShadow(
                        color: const Color(0xFF125117).withValues(alpha: 0.08),
                        blurRadius: 40, offset: const Offset(0, 20),
                      )
                    ],
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.electric_moped_rounded,
                    size: 72,
                    color: theme.colorScheme.primary.withValues(alpha: isDark ? 1.0 : 0.7),
                    shadows: isDark ? [
                      Shadow(color: theme.colorScheme.primary.withValues(alpha: 0.5), blurRadius: 40, offset: const Offset(0, 10))
                    ] : [],
                  ),
                ),
              ),
              
              const SizedBox(height: 16),

              // ── Input Section ──────────────────────────────────
              Text(
                l10n.login_phone_label.toUpperCase(),
                style: theme.textTheme.labelSmall,
              ),
              const SizedBox(height: 12),

              TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(10),
                ],
                style: theme.textTheme.bodyLarge,
                decoration: InputDecoration(
                  hintText: l10n.login_phone_hint,
                  prefixIcon: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('+91', style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w800)),
                        const SizedBox(width: 8),
                      ],
                    ),
                  ),
                ),
              ),
              
              const SizedBox(height: 20),

              // ── CTA Bottom Right (Flex) ────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Expanded(
                    child: PrimaryButton(
                      text: l10n.login_send_otp,
                      onPressed: _sendOtp,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              const Divider(color: Color(0xFFE5E7EB)),
              const SizedBox(height: 16),
              const Center(child: LanguageSwitcher()),
              const SizedBox(height: 32),

              // ── Terms ──────────────────────────────────────────
              Center(
                child: RichText(
                  textAlign: TextAlign.center,
                  text: TextSpan(
                    style: theme.textTheme.bodySmall?.copyWith(height: 1.5),
                    children: [
                      const TextSpan(text: 'By continuing you agree to our '),
                      TextSpan(
                        text: 'Terms of Service',
                        style: TextStyle(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w800,
                          decoration: TextDecoration.underline,
                          decorationColor: theme.colorScheme.primary,
                        ),
                      ),
                      const TextSpan(text: ' & '),
                      TextSpan(
                        text: 'Privacy Policy',
                        style: TextStyle(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w800,
                          decoration: TextDecoration.underline,
                          decorationColor: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
