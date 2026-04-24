import 'package:equatable/equatable.dart';

enum ClaimStatus { pending, processing, approved, rejected }

extension ClaimStatusLabel on ClaimStatus {
  static ClaimStatus fromString(String s) {
    return switch (s.toLowerCase()) {
      'approved' => ClaimStatus.approved,
      'rejected' => ClaimStatus.rejected,
      'processing' => ClaimStatus.processing,
      _ => ClaimStatus.pending,
    };
  }

  String get displayLabel => switch (this) {
        ClaimStatus.pending => 'PENDING',
        ClaimStatus.processing => 'PROCESSING',
        ClaimStatus.approved => 'APPROVED',
        ClaimStatus.rejected => 'REJECTED',
      };

  bool get isSettled =>
      this == ClaimStatus.approved || this == ClaimStatus.rejected;
}

/// Maps backend trigger_type to a human-readable label.
String triggerDisplayLabel(String type) {
  const map = {
    'rain_heavy': 'Rain Disruption',
    'rain_moderate': 'Rain Disruption',
    'rain_light': 'Rain Disruption',
    'heat_severe': 'Extreme Heat',
    'heat_stress': 'Extreme Heat',
    'aqi_hazardous': 'Air Quality Alert',
    'aqi_very_unhealthy': 'Air Quality Alert',
    'platform_outage': 'Platform Downtime',
    'dark_store_closure': 'Dark Store Closure',
  };
  return map[type] ?? type;
}

/// Immutable domain model for an insurance claim.
/// Separate from [ClaimModel] in mock_data_service.dart.
class Claim extends Equatable {
  final String id;
  final String userId;
  final String triggerType;
  final String displayLabel;
  final ClaimStatus status;

  /// Total payout before split (tranche1 + tranche2).
  final int grossPayout;

  /// 70% released immediately after approval.
  final int tranche1;

  /// 30% held for 48-hour fraud review.
  final int tranche2;

  final String zone;
  final DateTime createdAt;

  // ── Tamper-evident audit receipt ────────────────────────────────────
  final String? auditReceiptHash;
  final String? auditReceiptVersion;
  final String? auditGeneratedAt;
  final Map<String, dynamic>? auditReceiptPayload;

  const Claim({
    required this.id,
    required this.userId,
    required this.triggerType,
    required this.displayLabel,
    required this.status,
    required this.grossPayout,
    required this.tranche1,
    required this.tranche2,
    required this.zone,
    required this.createdAt,
    this.auditReceiptHash,
    this.auditReceiptVersion,
    this.auditGeneratedAt,
    this.auditReceiptPayload,
  });

  factory Claim.fromJson(Map<String, dynamic> json) {
    final trigger = json['trigger_type'] as String? ?? '';
    final createdStr = json['created_at'] as String?;
    final gross = (json['gross_payout'] as num?)?.toInt() ?? 0;
    final t1 = (json['tranche1'] as num?)?.toInt() ?? (gross * 0.7).round();
    final t2 = (json['tranche2'] as num?)?.toInt() ?? (gross * 0.3).round();

    return Claim(
      id: json['id'] as String? ?? '',
      userId: json['user_id'] as String? ?? '',
      triggerType: trigger,
      displayLabel: triggerDisplayLabel(trigger),
      status: ClaimStatusLabel.fromString(json['status'] as String? ?? ''),
      grossPayout: gross,
      tranche1: t1,
      tranche2: t2,
      zone: json['zone'] as String? ?? '',
      createdAt:
          createdStr != null ? DateTime.tryParse(createdStr) ?? DateTime.now() : DateTime.now(),
      auditReceiptHash:    json['audit_receipt_hash'] as String?,
      auditReceiptVersion: json['audit_receipt_version'] as String?,
      auditGeneratedAt:    json['audit_generated_at'] as String?,
      auditReceiptPayload: json['audit_receipt_payload'] != null
          ? Map<String, dynamic>.from(json['audit_receipt_payload'] as Map)
          : null,
    );
  }

  Claim copyWith({
    String? id,
    String? userId,
    String? triggerType,
    String? displayLabel,
    ClaimStatus? status,
    int? grossPayout,
    int? tranche1,
    int? tranche2,
    String? zone,
    DateTime? createdAt,
    String? auditReceiptHash,
    String? auditReceiptVersion,
    String? auditGeneratedAt,
    Map<String, dynamic>? auditReceiptPayload,
  }) {
    return Claim(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      triggerType: triggerType ?? this.triggerType,
      displayLabel: displayLabel ?? this.displayLabel,
      status: status ?? this.status,
      grossPayout: grossPayout ?? this.grossPayout,
      tranche1: tranche1 ?? this.tranche1,
      tranche2: tranche2 ?? this.tranche2,
      zone: zone ?? this.zone,
      createdAt: createdAt ?? this.createdAt,
      auditReceiptHash:    auditReceiptHash    ?? this.auditReceiptHash,
      auditReceiptVersion: auditReceiptVersion ?? this.auditReceiptVersion,
      auditGeneratedAt:    auditGeneratedAt    ?? this.auditGeneratedAt,
      auditReceiptPayload: auditReceiptPayload ?? this.auditReceiptPayload,
    );
  }

  @override
  List<Object?> get props => [
        id,
        userId,
        triggerType,
        status,
        grossPayout,
        tranche1,
        tranche2,
        zone,
        createdAt,
        auditReceiptHash,
        auditReceiptVersion,
      ];
}
