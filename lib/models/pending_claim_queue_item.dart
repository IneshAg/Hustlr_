import 'dart:convert';

class PendingClaimQueueItem {
  final String localId;
  final String userId;
  final String type;
  final String description;
  final List<String> evidenceUrls;
  final int? deviceSignalStrength;
  final Map<String, dynamic>? sensorFeatures;
  final String? integrityToken;
  final int retryCount;
  final DateTime lastAttemptAt;
  final DateTime nextRetryAt;
  final String? lastError;
  final DateTime createdAt;

  PendingClaimQueueItem({
    required this.localId,
    required this.userId,
    required this.type,
    required this.description,
    this.evidenceUrls = const [],
    this.deviceSignalStrength,
    this.sensorFeatures,
    this.integrityToken,
    this.retryCount = 0,
    required this.lastAttemptAt,
    required this.nextRetryAt,
    this.lastError,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'localId': localId,
      'userId': userId,
      'type': type,
      'description': description,
      'evidenceUrls': evidenceUrls,
      'deviceSignalStrength': deviceSignalStrength,
      'sensorFeatures': sensorFeatures,
      'integrityToken': integrityToken,
      'retryCount': retryCount,
      'lastAttemptAt': lastAttemptAt.toIso8601String(),
      'nextRetryAt': nextRetryAt.toIso8601String(),
      'lastError': lastError,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory PendingClaimQueueItem.fromMap(Map<String, dynamic> map) {
    return PendingClaimQueueItem(
      localId: map['localId'] ?? '',
      userId: map['userId'] ?? '',
      type: map['type'] ?? '',
      description: map['description'] ?? '',
        evidenceUrls: (map['evidenceUrls'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
          const [],
        deviceSignalStrength: map['deviceSignalStrength'] as int?,
        sensorFeatures: map['sensorFeatures'] is Map
          ? Map<String, dynamic>.from(map['sensorFeatures'] as Map)
          : null,
        integrityToken: map['integrityToken'] as String?,
      retryCount: map['retryCount'] ?? 0,
      lastAttemptAt: DateTime.tryParse(map['lastAttemptAt'] ?? '') ?? DateTime.now(),
      nextRetryAt: DateTime.tryParse(map['nextRetryAt'] ?? '') ?? DateTime.now(),
      lastError: map['lastError'],
      createdAt: DateTime.tryParse(map['createdAt'] ?? '') ?? DateTime.now(),
    );
  }

  String toJson() => json.encode(toMap());

  factory PendingClaimQueueItem.fromJson(String source) => PendingClaimQueueItem.fromMap(json.decode(source));

  PendingClaimQueueItem copyWith({
    String? localId,
    String? userId,
    String? type,
    String? description,
    List<String>? evidenceUrls,
    int? deviceSignalStrength,
    Map<String, dynamic>? sensorFeatures,
    String? integrityToken,
    int? retryCount,
    DateTime? lastAttemptAt,
    DateTime? nextRetryAt,
    String? lastError,
    DateTime? createdAt,
  }) {
    return PendingClaimQueueItem(
      localId: localId ?? this.localId,
      userId: userId ?? this.userId,
      type: type ?? this.type,
      description: description ?? this.description,
      evidenceUrls: evidenceUrls ?? this.evidenceUrls,
      deviceSignalStrength: deviceSignalStrength ?? this.deviceSignalStrength,
      sensorFeatures: sensorFeatures ?? this.sensorFeatures,
      integrityToken: integrityToken ?? this.integrityToken,
      retryCount: retryCount ?? this.retryCount,
      lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
      nextRetryAt: nextRetryAt ?? this.nextRetryAt,
      lastError: lastError ?? this.lastError,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
