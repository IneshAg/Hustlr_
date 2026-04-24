import 'package:equatable/equatable.dart';
import '../../models/policy.dart';

abstract class PolicyEvent extends Equatable {
  const PolicyEvent();

  @override
  List<Object?> get props => [];
}

/// Fetch the active policy for [userId] from the backend.
class LoadPolicy extends PolicyEvent {
  final String userId;
  const LoadPolicy(this.userId);

  @override
  List<Object?> get props => [userId];
}

/// Purchase and activate a new policy for [userId] at the given [tier].
/// Coverage window starts AFTER payment confirmation, never before.
class ActivatePolicy extends PolicyEvent {
  final PlanTier tier;
  final String userId;
  const ActivatePolicy({required this.tier, required this.userId});

  @override
  List<Object?> get props => [tier, userId];
}

/// Cancel the active policy. Blocked if a claim is currently pending.
class CancelPolicy extends PolicyEvent {
  final String userId;
  const CancelPolicy(this.userId);

  @override
  List<Object?> get props => [userId];
}

/// Verify that coverage is currently active (i.e. within the current week
/// window and the policy is in ACTIVE status).
class CheckCoverage extends PolicyEvent {
  final String userId;
  const CheckCoverage(this.userId);

  @override
  List<Object?> get props => [userId];
}
