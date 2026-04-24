import 'package:equatable/equatable.dart';
import '../../models/claim.dart';

abstract class ClaimsEvent extends Equatable {
  const ClaimsEvent();

  @override
  List<Object?> get props => [];
}

/// Load the current snapshot of claims for [userId].
class LoadClaims extends ClaimsEvent {
  final String userId;
  const LoadClaims(this.userId);

  @override
  List<Object?> get props => [userId];
}

/// Start a 10-second polling loop for [userId]. The loop fires
/// [ClaimStatusUpdated] internally whenever a claim status changes.
class WatchClaims extends ClaimsEvent {
  final String userId;
  const WatchClaims(this.userId);

  @override
  List<Object?> get props => [userId];
}

/// Fired by the polling loop (or the MockDataService demo bridge) when a
/// claim's status changes. Causes the BLoC to recompute wallet amounts.
class ClaimStatusUpdated extends ClaimsEvent {
  final Claim updatedClaim;
  const ClaimStatusUpdated(this.updatedClaim);

  @override
  List<Object?> get props => [updatedClaim];
}

/// Re-fetch the wallet balance from the backend and merge into state.
class RefreshWallet extends ClaimsEvent {
  final String userId;
  const RefreshWallet(this.userId);

  @override
  List<Object?> get props => [userId];
}

/// Initiate a UPI withdrawal for [amount]. Emits failure if balance is
/// insufficient or the API call fails.
class WithdrawFunds extends ClaimsEvent {
  final String userId;
  final double amount;
  const WithdrawFunds({required this.userId, required this.amount});

  @override
  List<Object?> get props => [userId, amount];
}

class SubmitClaimAppeal extends ClaimsEvent {
  final String claimId;
  final String workerId;
  final String selectedReason;
  final String? additionalContext;

  const SubmitClaimAppeal({
    required this.claimId,
    required this.workerId,
    required this.selectedReason,
    this.additionalContext,
  });

  @override
  List<Object?> get props => [claimId, workerId, selectedReason, additionalContext];
}
