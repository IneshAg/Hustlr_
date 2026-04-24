import 'package:equatable/equatable.dart';
import '../../models/claim.dart';
import '../../models/wallet_balance.dart';

enum LoadStatus { initial, loading, success, failure }

class ClaimsState extends Equatable {
  final List<Claim> claims;
  final WalletBalance wallet;

  /// Sum of tranche2 for all non-settled claims. Computed from [claims] —
  /// never fetched separately.
  final double pendingAmount;

  /// The cleared wallet balance (70% tranches already released). Kept in sync
  /// with [wallet.balance] — no extra API call needed on approve.
  final double availableAmount;

  final LoadStatus status;
  final String? errorMessage;

  const ClaimsState({
    this.claims = const [],
    this.wallet = WalletBalance.empty,
    this.pendingAmount = 0.0,
    this.availableAmount = 0.0,
    this.status = LoadStatus.initial,
    this.errorMessage,
  });

  ClaimsState copyWith({
    List<Claim>? claims,
    WalletBalance? wallet,
    double? pendingAmount,
    double? availableAmount,
    LoadStatus? status,
    String? errorMessage,
  }) {
    return ClaimsState(
      claims: claims ?? this.claims,
      wallet: wallet ?? this.wallet,
      pendingAmount: pendingAmount ?? this.pendingAmount,
      availableAmount: availableAmount ?? this.availableAmount,
      status: status ?? this.status,
      errorMessage: errorMessage,
    );
  }

  @override
  List<Object?> get props => [
        claims,
        wallet,
        pendingAmount,
        availableAmount,
        status,
        errorMessage,
      ];
}
