import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../services/notification_service.dart';
import '../../core/router/app_router.dart';

class NotificationBell extends StatelessWidget {
  final Color? color;
  const NotificationBell({super.key, this.color});

  @override
  Widget build(BuildContext context) {
    return StatefulBuilder(
      builder: (context, setState) {
        final hasUnread = NotificationService.instance.unreadCount > 0;
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final red = isDark ? const Color(0xFFFF5252) : const Color(0xFFB71C1C);
        final defaultColor = isDark ? Colors.white : const Color(0xFF0D1B0F);
        
        return Stack(
          alignment: Alignment.center,
          children: [
            IconButton(
              icon: Icon(Icons.notifications_rounded, color: color ?? defaultColor),
              onPressed: () async {
                NotificationService.instance.markAllRead();
                await GoRouter.of(context).push(AppRoutes.notifications);
                if (context.mounted) setState(() {});
              },
            ),
            if (hasUnread)
              Positioned(
                top: 8, right: 8,
                child: Container(
                  width: 8, height: 8,
                  decoration: BoxDecoration(color: red, shape: BoxShape.circle),
                ),
              ),
          ],
        );
      },
    );
  }
}
