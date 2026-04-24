import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../services/api_health_service.dart';

class ApiStatusScreen extends StatefulWidget {
  const ApiStatusScreen({super.key});

  @override
  State<ApiStatusScreen> createState() => _ApiStatusScreenState();
}

class _ApiStatusScreenState extends State<ApiStatusScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    Future.microtask(() => ApiHealthService.instance.checkAll());
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bg = theme.scaffoldBackgroundColor;
    final onSurface = theme.colorScheme.onSurface;

    return ListenableBuilder(
      listenable: ApiHealthService.instance,
      builder: (context, _) {
        final health = ApiHealthService.instance;
        final overall = health.overallStatus;
        final isChecking = health.isChecking;
        final lastChecked = health.lastChecked;

        return Scaffold(
          backgroundColor: bg,
          appBar: AppBar(
            backgroundColor: bg,
            elevation: 0,
            leading: IconButton(icon: Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: onSurface), onPressed: () => context.pop()),
            title: Text(
              'API Status',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: onSurface),
            ),
            centerTitle: true,
            actions: [
              IconButton(
                icon: isChecking
                    ? SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: theme.colorScheme.primary,
                        ),
                      )
                    : Icon(Icons.refresh_rounded, color: onSurface),
                onPressed: isChecking ? null : () => health.checkAll(),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
            children: [
              const SizedBox(height: 8),

              // ── Overall Banner ───────────────────────────────────────────
              _OverallBanner(
                status: overall,
                isChecking: isChecking,
                lastChecked: lastChecked,
                pulseController: _pulseController,
                isDark: isDark,
                theme: theme,
                totalServices: health.services.length,
                onlineCount: health.services
                    .where((s) => s.status == ApiStatus.online)
                    .length,
              ),
              const SizedBox(height: 28),

              // ── Grouped service cards ────────────────────────────────────
              if (health.services.isEmpty && isChecking)
                ..._shimmerCards(isDark)
              else ...[
                for (final cat in health.categories) ...[
                  _CategoryHeader(
                    label: cat,
                    services: health.forCategory(cat),
                    theme: theme,
                    onSurface: onSurface,
                  ),
                  const SizedBox(height: 10),
                  ...health.forCategory(cat).map((s) => _ServiceCard(
                        service: s,
                        isDark: isDark,
                        theme: theme,
                      )),
                  const SizedBox(height: 20),
                ],
              ],

              // ── Info note ────────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1A1D1A) : const Color(0xFFF5F5F5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline_rounded,
                        size: 16, color: onSurface.withValues(alpha: 0.4)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'When an API fails 3 times, the backend marks it DEGRADED and '
                        'serves fallback cached data for 5 minutes before retrying. '
                        'The app always works — this screen shows real-time health.',
                        style: TextStyle(
                          fontSize: 12,
                          color: onSurface.withValues(alpha: 0.5),
                          height: 1.6,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _shimmerCards(bool isDark) => List.generate(
        10,
        (i) => Container(
          margin: const EdgeInsets.only(bottom: 8),
          height: 70,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1c1f1c) : const Color(0xFFF0F0F0),
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      );
}

// ── Overall Banner ───────────────────────────────────────────────────────────
class _OverallBanner extends StatelessWidget {
  final ApiStatus status;
  final bool isChecking;
  final DateTime? lastChecked;
  final AnimationController pulseController;
  final bool isDark;
  final ThemeData theme;
  final int totalServices;
  final int onlineCount;

  const _OverallBanner({
    required this.status,
    required this.isChecking,
    required this.lastChecked,
    required this.pulseController,
    required this.isDark,
    required this.theme,
    required this.totalServices,
    required this.onlineCount,
  });

  @override
  Widget build(BuildContext context) {
    final (color, bgColor, label, icon) = switch (status) {
      ApiStatus.online   => (const Color(0xFF3FFF8B), const Color(0xFF003D2A), 'All Systems Operational', Icons.check_circle_rounded),
      ApiStatus.degraded => (const Color(0xFFFFD54F), const Color(0xFF3D3000), 'Partial Degradation', Icons.warning_amber_rounded),
      ApiStatus.offline  => (const Color(0xFFFF5252), const Color(0xFF3D0000), 'Backend Unreachable', Icons.cancel_rounded),
      ApiStatus.unknown  => (const Color(0xFF91938d), const Color(0xFF1A1D1A), 'Checking...', Icons.help_outline_rounded),
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? bgColor : color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.25), width: 1.5),
      ),
      child: Row(
        children: [
          AnimatedBuilder(
            animation: pulseController,
            builder: (_, __) => Container(
              width: 52, height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: 
                  isChecking || status == ApiStatus.online
                      ? 0.08 + 0.18 * pulseController.value
                      : 0.10,
                ),
              ),
              child: Icon(icon, color: color, size: 26),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isChecking ? 'Checking...' : label,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isDark ? color : theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                if (!isChecking && totalServices > 0)
                  Text(
                    '$onlineCount / $totalServices services online',
                    style: TextStyle(fontSize: 13, color: color.withValues(alpha: 0.8)),
                  ),
                if (lastChecked != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Last checked at ${_fmt(lastChecked!)}',
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _fmt(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}

// ── Category Header ──────────────────────────────────────────────────────────
class _CategoryHeader extends StatelessWidget {
  final String label;
  final List<ServiceHealth> services;
  final ThemeData theme;
  final Color onSurface;

  const _CategoryHeader({
    required this.label,
    required this.services,
    required this.theme,
    required this.onSurface,
  });

  @override
  Widget build(BuildContext context) {
    final allOnline = services.every((s) => s.status == ApiStatus.online);
    final allOffline = services.every((s) =>
        s.status == ApiStatus.offline || s.status == ApiStatus.unknown);
    final dotColor = allOffline
        ? const Color(0xFFFF5252)
        : allOnline
            ? const Color(0xFF3FFF8B)
            : const Color(0xFFFFD54F);

    return Row(
      children: [
        Container(
          width: 7, height: 7,
          decoration: BoxDecoration(
            shape: BoxShape.circle, color: dotColor,
            boxShadow: [BoxShadow(color: dotColor.withValues(alpha: 0.5), blurRadius: 5)],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.1,
            color: onSurface.withValues(alpha: 0.45),
          ),
        ),
      ],
    );
  }
}

// ── Service Card ─────────────────────────────────────────────────────────────
class _ServiceCard extends StatelessWidget {
  final ServiceHealth service;
  final bool isDark;
  final ThemeData theme;

  const _ServiceCard({
    required this.service,
    required this.isDark,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final (dotColor, badge) = switch (service.status) {
      ApiStatus.online   => (const Color(0xFF3FFF8B), 'Online'),
      ApiStatus.degraded => (const Color(0xFFFFD54F), 'Degraded'),
      ApiStatus.offline  => (const Color(0xFFFF5252), 'Offline'),
      ApiStatus.unknown  => (const Color(0xFF91938d), 'Unknown'),
    };

    final isError = service.status == ApiStatus.offline ||
        service.status == ApiStatus.degraded;
    final cardBg = isDark ? const Color(0xFF1c1f1c) : Colors.white;
    final sub = theme.colorScheme.onSurface.withValues(alpha: 0.45);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isError
              ? dotColor.withValues(alpha: 0.2)
              : isDark
                  ? Colors.white.withValues(alpha: 0.06)
                  : const Color(0xFFE5E7EB),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 9, height: 9,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: dotColor,
              boxShadow: [BoxShadow(color: dotColor.withValues(alpha: 0.45), blurRadius: 6)],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  service.name,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  service.description,
                  style: TextStyle(fontSize: 11, color: sub),
                ),
                if (service.detail != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    service.detail!,
                    style: TextStyle(
                      fontSize: 11,
                      color: isError ? dotColor : sub,
                      fontWeight: isError ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: dotColor.withValues(alpha: isDark ? 0.12 : 0.08),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              badge,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: dotColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
