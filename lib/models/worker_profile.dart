import 'package:equatable/equatable.dart';

/// Immutable domain model for a Hustlr worker profile.
/// Separate from [WorkerModel] in mock_data_service.dart — that class is kept
/// intact for the demo/offline path.
class WorkerProfile extends Equatable {
  final String id;
  final String name;
  final String phone;
  final String platform;
  final String city;
  final String zone;
  final int weeklyIncomeEstimate;

  const WorkerProfile({
    required this.id,
    required this.name,
    required this.phone,
    required this.platform,
    required this.city,
    required this.zone,
    required this.weeklyIncomeEstimate,
  });

  factory WorkerProfile.fromJson(Map<String, dynamic> json) {
    return WorkerProfile(
      id: json['id'] as String? ?? json['user_id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      platform: json['platform'] as String? ?? 'Zepto',
      city: json['city'] as String? ?? '',
      zone: json['zone'] as String? ?? '',
      weeklyIncomeEstimate:
          (json['weekly_income_estimate'] as num?)?.toInt() ?? 4200,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'phone': phone,
        'platform': platform,
        'city': city,
        'zone': zone,
        'weekly_income_estimate': weeklyIncomeEstimate,
      };

  WorkerProfile copyWith({
    String? id,
    String? name,
    String? phone,
    String? platform,
    String? city,
    String? zone,
    int? weeklyIncomeEstimate,
  }) {
    return WorkerProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      platform: platform ?? this.platform,
      city: city ?? this.city,
      zone: zone ?? this.zone,
      weeklyIncomeEstimate: weeklyIncomeEstimate ?? this.weeklyIncomeEstimate,
    );
  }

  /// Fallback profile used before data loads.
  static const empty = WorkerProfile(
    id: '',
    name: '',
    phone: '',
    platform: 'Zepto',
    city: '',
    zone: '',
    weeklyIncomeEstimate: 4200,
  );

  bool get isEmpty => id.isEmpty;
  bool get isNotEmpty => id.isNotEmpty;

  @override
  List<Object?> get props => [
        id,
        name,
        phone,
        platform,
        city,
        zone,
        weeklyIncomeEstimate,
      ];
}
