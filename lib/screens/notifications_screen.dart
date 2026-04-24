import 'package:flutter/material.dart';
import '../models/notification_model.dart';
import '../services/notification_service.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  @override
  Widget build(BuildContext context) {
    final theme       = Theme.of(context);
    final isDark      = theme.brightness == Brightness.dark;
    final bg          = theme.scaffoldBackgroundColor;
    final titleColor  = theme.colorScheme.onSurface;
    final green       = theme.colorScheme.primary;
    final btnTxt      = isDark ? const Color(0xFF0A0B0A) : Colors.white;
    final notifications = NotificationService.instance.all;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: titleColor),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Row(
          children: [
            Text('Notifications',
                style: TextStyle(color: titleColor, fontSize: 18, fontWeight: FontWeight.w700)),
            if (NotificationService.instance.unreadCount > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: green, borderRadius: BorderRadius.circular(10)),
                child: Text(
                  '${NotificationService.instance.unreadCount}',
                  style: TextStyle(color: btnTxt, fontSize: 10, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ],
        ),
        actions: [
          if (NotificationService.instance.unreadCount > 0)
            TextButton(
              onPressed: () {
                NotificationService.instance.markAllRead();
                setState(() {});
              },
              child: Text('Mark all as read',
                  style: TextStyle(color: green, fontSize: 14, fontWeight: FontWeight.w500)),
            ),
        ],
      ),
      body: notifications.isEmpty
          ? const _EmptyState()
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: notifications.length,
              itemBuilder: (context, index) {
                final notification = notifications[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: _NotificationCard(
                    notification: notification,
                    onTap: () {
                      if (!notification.isRead) {
                        NotificationService.instance.markRead(notification.id);
                        setState(() {});
                      }
                    },
                  ),
                );
              },
            ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  final HustlrNotification notification;
  final VoidCallback onTap;

  const _NotificationCard({required this.notification, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme  = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final text   = theme.colorScheme.onSurface;
    final sub    = theme.colorScheme.onSurface.withValues(alpha: 0.5);
    final readBg = isDark ? const Color(0xFF141614) : const Color(0xFFF4F4EF);
    final unreadBg = theme.cardColor;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: notification.isRead ? readBg : unreadBg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            _buildIconCircle(context),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(notification.title,
                      style: TextStyle(color: text, fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(notification.body,
                      style: TextStyle(color: sub, fontSize: 12)),
                  const SizedBox(height: 4),
                  Text(_getTimeAgo(notification.createdAt),
                      style: TextStyle(color: sub, fontSize: 11)),
                ],
              ),
            ),
            if (!notification.isRead)
              Container(
                width: 8, height: 8,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildIconCircle(BuildContext context) {
    final isDark  = Theme.of(context).brightness == Brightness.dark;
    IconData icon;
    Color circleColor;

    switch (notification.type) {
      case 'rain_alert':
        icon = Icons.cloud;
        circleColor = const Color(0xFF2196F3);
        break;
      case 'claim_approved':
        icon = Icons.verified_rounded;
        circleColor = isDark ? const Color(0xFF3FFF8B) : const Color(0xFF125117);
        break;
      case 'premium_deducted':
        icon = Icons.security_rounded;
        circleColor = isDark ? const Color(0xFF3FFF8B) : const Color(0xFF125117);
        break;
      case 'missed_payout':
        icon = Icons.warning_rounded;
        circleColor = const Color(0xFFFF9800);
        break;
      default:
        icon = Icons.notifications_rounded;
        circleColor = isDark ? const Color(0xFF3A3D3A) : Colors.grey;
    }

    final iconColor = isDark && (notification.type == 'claim_approved' || notification.type == 'premium_deducted')
        ? const Color(0xFF0A0B0A)
        : Colors.white;

    return Container(
      width: 40, height: 40,
      decoration: BoxDecoration(color: circleColor, shape: BoxShape.circle),
      child: Icon(icon, color: iconColor, size: 20),
    );
  }

  String _getTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final diff = now.difference(dateTime);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${(diff.inDays / 7).floor()}w ago';
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sub   = theme.colorScheme.onSurface.withValues(alpha: 0.4);
    final text  = theme.colorScheme.onSurface;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.notifications_outlined, size: 80, color: sub),
          const SizedBox(height: 16),
          Text('You are all caught up',
              style: TextStyle(color: text, fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(
            'Notifications about your claims and payouts will appear here',
            style: TextStyle(color: sub, fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
