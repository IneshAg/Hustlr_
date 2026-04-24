import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/notification_service.dart';
import '../core/router/app_router.dart';

class NotificationBell extends StatelessWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context) {
    return StatefulBuilder(
      builder: (context, setState) {
        final unreadCount = NotificationService.instance.unreadCount;
        final hasUnread = unreadCount > 0;
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final primaryColor = Theme.of(context).colorScheme.primary;
        
        return GestureDetector(
          onTap: () async {
            NotificationService.instance.markAllRead();
            GoRouter.of(context).push(AppRoutes.notifications);
            setState(() {});
          },
          behavior: HitTestBehavior.opaque,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: hasUnread 
                  ? (isDark ? primaryColor.withValues(alpha: 0.15) : primaryColor.withValues(alpha: 0.1))
                  : Colors.transparent,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  Icon(
                    hasUnread ? Icons.notifications_rounded : Icons.notifications_outlined,
                    size: 24,
                    color: hasUnread 
                        ? (isDark ? const Color(0xFF3FFF8B) : primaryColor)
                        : (isDark ? Colors.white70 : Colors.black54),
                  ),
                  if (hasUnread)
                    Positioned(
                      right: -6,
                      top: -6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFFFF5252) : const Color(0xFFD32F2F),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isDark ? const Color(0xFF0a0b0a) : Colors.white,
                            width: 2,
                          ),
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 18,
                          minHeight: 18,
                        ),
                        child: Text(
                          unreadCount > 9 ? '9+' : '$unreadCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
