import 'package:equatable/equatable.dart';

/// Flat-priced plan tiers. Prices never vary per worker — they are fixed product SKUs.
enum PlanTier { basic, standard, full }

extension PlanTierPrice on PlanTier {
  int get weeklyPremium => switch (this) {
        PlanTier.basic    => 35,
        PlanTier.standard => 49,
        PlanTier.full     => 79,
      };

  String get displayName => switch (this) {
        PlanTier.basic    => 'Basic Shield',
        PlanTier.standard => 'Standard Shield',
        PlanTier.full     => 'Full Shield',
      };

  String get apiKey => switch (this) {
        PlanTier.basic    => 'basic',
        PlanTier.standard => 'standard',
        PlanTier.full     => 'full',
      };

  static PlanTier fromString(String s) {
    return PlanTier.values.firstWhere(
      (t) => t.apiKey == s.toLowerCase(),
      orElse: () => PlanTier.standard,
    );
  }
}

// Maps all values from the new policy_status_enum (active, expired, cancelled, suspended, renewed)
enum PolicyStatus { active, expired, cancelled, pending, suspended, renewed }

extension PolicyStatusLabel on PolicyStatus {
  static PolicyStatus fromString(String s) {
    return switch (s.toLowerCase()) {
      'active'    => PolicyStatus.active,
      'expired'   => PolicyStatus.expired,
      'cancelled' => PolicyStatus.cancelled,
      'suspended' => PolicyStatus.suspended,
      'renewed'   => PolicyStatus.renewed,
      _           => PolicyStatus.pending,
    };
  }

  String get displayLabel => switch (this) {
        PolicyStatus.active    => 'ACTIVE',
        PolicyStatus.expired   => 'EXPIRED',
        PolicyStatus.cancelled => 'CANCELLED',
        PolicyStatus.pending   => 'PENDING',
        PolicyStatus.suspended => 'SUSPENDED',
        PolicyStatus.renewed   => 'RENEWED',
      };

  bool get isCoverageActive => this == PolicyStatus.active || this == PolicyStatus.renewed;
}

/// Immutable domain model for an insurance policy.
/// Separate from [PolicyModel] in mock_data_service.dart.
class Policy extends Equatable {
  final String id;
  final String userId;
  final PlanTier tier;
  final PolicyStatus status;
  final String? planName;
  final String? policyNumber;
  final DateTime? startDate;
  final DateTime? endDate;
  final DateTime? createdAt;
  final DateTime? expiresAt;
  final int basePremium;
  final int weeklyPremium;
  final int? maxWeeklyPayout;
  final int? maxDailyPayout;
  final List<Map<String, dynamic>> riders;

  const Policy({
    required this.id,
    required this.userId,
    required this.tier,
    required this.status,
    this.planName,
    this.policyNumber,
    this.startDate,
    this.endDate,
    this.createdAt,
    this.expiresAt,
    required this.basePremium,
    required this.weeklyPremium,
    this.maxWeeklyPayout,
    this.maxDailyPayout,
    this.riders = const [],
  });

  factory Policy.fromJson(Map<String, dynamic> json) {
    final tierStr = json['plan_tier'] as String? ?? 'standard';
    final statusStr = json['status'] as String? ?? 'pending';

    // Support both old schema (start_date/end_date) and new schema (coverage_start/commitment_end)
    final startStr = (json['coverage_start'] ?? json['start_date']) as String?;
    final endStr   = (json['commitment_end'] ?? json['paid_until'] ?? json['end_date']) as String?;
    final createdStr = json['created_at'] as String?;
    final expiresStr = (json['expires_at'] ?? json['commitment_end'] ?? json['paid_until']) as String?;

    final tier = PlanTierPrice.fromString(tierStr);

    // If DB has a stale/wrong premium value, fall back to the canonical tier price
    final rawPremium = (json['weekly_premium'] as num?)?.toInt() ?? 0;
    final canonicalPremium = tier.weeklyPremium;
    final weeklyPremium = (rawPremium > 0 && rawPremium <= 200)
        ? rawPremium
        : canonicalPremium;

    int? parsePositiveInt(dynamic raw) {
      final value = raw is num ? raw.toInt() : int.tryParse('${raw ?? ''}');
      if (value == null || value <= 0) return null;
      return value;
    }

    final maxWeekly = parsePositiveInt(
      json['max_weekly_payout'] ?? json['max_weekly_payout_paise'],
    );
    final maxDaily = parsePositiveInt(
      json['max_daily_payout'] ?? json['max_daily_payout_paise'],
    );

    final ridersRaw = json['riders'] as List<dynamic>?;
    final riders = ridersRaw == null
        ? <Map<String, dynamic>>[]
        : ridersRaw
            .whereType<Map>()
            .map((r) => Map<String, dynamic>.from(r))
            .toList();

    return Policy(
      id: json['id'] as String? ?? '',
      userId: json['user_id'] as String? ?? '',
      tier: tier,
      status: PolicyStatusLabel.fromString(statusStr),
      planName: json['plan_name'] as String?,
      policyNumber: json['policy_number'] as String?,
      startDate: startStr != null ? DateTime.tryParse(startStr) : null,
      endDate: endStr != null ? DateTime.tryParse(endStr) : null,
      createdAt: createdStr != null ? DateTime.tryParse(createdStr) : null,
      expiresAt: expiresStr != null ? DateTime.tryParse(expiresStr) : null,
      basePremium: (json['base_premium'] as num?)?.toInt() ?? canonicalPremium,
      weeklyPremium: weeklyPremium,
      maxWeeklyPayout: maxWeekly,
      maxDailyPayout: maxDaily,
      riders: riders,
    );
  }

  Policy copyWith({
    String? id,
    String? userId,
    PlanTier? tier,
    PolicyStatus? status,
    String? planName,
    String? policyNumber,
    DateTime? startDate,
    DateTime? endDate,
    DateTime? createdAt,
    DateTime? expiresAt,
    int? basePremium,
    int? weeklyPremium,
    int? maxWeeklyPayout,
    int? maxDailyPayout,
    List<Map<String, dynamic>>? riders,
  }) {
    return Policy(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      tier: tier ?? this.tier,
      status: status ?? this.status,
      planName: planName ?? this.planName,
      policyNumber: policyNumber ?? this.policyNumber,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      createdAt: createdAt ?? this.createdAt,
      expiresAt: expiresAt ?? this.expiresAt,
      basePremium: basePremium ?? this.basePremium,
      weeklyPremium: weeklyPremium ?? this.weeklyPremium,
      maxWeeklyPayout: maxWeeklyPayout ?? this.maxWeeklyPayout,
      maxDailyPayout: maxDailyPayout ?? this.maxDailyPayout,
      riders: riders ?? this.riders,
    );
  }

  /// True for 'active' OR 'renewed' — covers the new schema's renewed status
  bool get isActive => status.isCoverageActive;

  @override
  List<Object?> get props => [
        id,
        userId,
        tier,
        status,
        planName,
        policyNumber,
        startDate,
        endDate,
        createdAt,
        expiresAt,
        basePremium,
        weeklyPremium,
        maxWeeklyPayout,
        maxDailyPayout,
        riders,
      ];
}
