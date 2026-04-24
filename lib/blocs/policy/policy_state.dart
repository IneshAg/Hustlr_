import 'package:equatable/equatable.dart';
import '../../models/policy.dart';
import '../../models/claim.dart';

class PolicyState extends Equatable {
  final Policy? activePolicy;
  final PlanTier? selectedTier;
  final bool coverageActive;
  final DateTime? coverageStartTime;

  /// Pending claims that block policy cancellation.
  final List<Claim> pendingClaims;

  final LoadStatus status;
  final String? errorMessage;

  const PolicyState({
    this.activePolicy,
    this.selectedTier,
    this.coverageActive = false,
    this.coverageStartTime,
    this.pendingClaims = const [],
    this.status = LoadStatus.initial,
    this.errorMessage,
  });

  PolicyState copyWith({
    Policy? activePolicy,
    PlanTier? selectedTier,
    bool? coverageActive,
    DateTime? coverageStartTime,
    List<Claim>? pendingClaims,
    LoadStatus? status,
    String? errorMessage,
  }) {
    return PolicyState(
      activePolicy: activePolicy ?? this.activePolicy,
      selectedTier: selectedTier ?? this.selectedTier,
      coverageActive: coverageActive ?? this.coverageActive,
      coverageStartTime: coverageStartTime ?? this.coverageStartTime,
      pendingClaims: pendingClaims ?? this.pendingClaims,
      status: status ?? this.status,
      errorMessage: errorMessage,
    );
  }

  @override
  List<Object?> get props => [
        activePolicy,
        selectedTier,
        coverageActive,
        coverageStartTime,
        pendingClaims,
        status,
        errorMessage,
      ];
}

// Re-export LoadStatus so policy and user states share one definition.
enum LoadStatus { initial, loading, success, failure }
