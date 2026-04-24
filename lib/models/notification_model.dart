class HustlrNotification {
  final String id;
  final String type;
  final String title;
  final String body;
  final String color;
  final DateTime createdAt;
  bool isRead;

  HustlrNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.color,
    required this.createdAt,
    this.isRead = false,
  });
}
