import 'package:equatable/equatable.dart';

/// A single wallet transaction line item.
class WalletTransaction extends Equatable {
  final String type; // 'credit' | 'debit'
  final String title;
  final String subtitle;
  final int amount;
  final DateTime createdAt;

  const WalletTransaction({
    required this.type,
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.createdAt,
  });

  factory WalletTransaction.fromJson(Map<String, dynamic> json) {
    final createdStr = json['created_at'] as String?;
    final type = json['type'] as String? ?? 'credit';
    return WalletTransaction(
      type: type,
      title: json['description'] as String? ??
          (type == 'credit' ? 'Payout Credited' : 'Premium Deducted'),
      subtitle: json['reference'] as String? ?? '',
      amount: (json['amount'] as num?)?.toInt() ?? 0,
      createdAt: createdStr != null
          ? DateTime.tryParse(createdStr) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  @override
  List<Object?> get props => [type, title, subtitle, amount, createdAt];
}

/// Immutable snapshot of a worker's wallet.
class WalletBalance extends Equatable {
  final int balance;
  final int totalPayouts;
  final int totalPremiums;
  final List<WalletTransaction> transactions;

  const WalletBalance({
    required this.balance,
    required this.totalPayouts,
    required this.totalPremiums,
    required this.transactions,
  });

  factory WalletBalance.fromJson(Map<String, dynamic> json) {
    final rawTx = json['transactions'] as List<dynamic>? ?? [];
    final txList = rawTx
        .map((t) => WalletTransaction.fromJson(t as Map<String, dynamic>))
        .toList();
    return WalletBalance(
      balance: (json['balance'] as num?)?.toInt() ?? 0,
      totalPayouts: (json['total_payouts'] as num?)?.toInt() ?? 0,
      totalPremiums: (json['total_premiums'] as num?)?.toInt() ?? 0,
      transactions: txList,
    );
  }

  WalletBalance copyWith({
    int? balance,
    int? totalPayouts,
    int? totalPremiums,
    List<WalletTransaction>? transactions,
  }) {
    return WalletBalance(
      balance: balance ?? this.balance,
      totalPayouts: totalPayouts ?? this.totalPayouts,
      totalPremiums: totalPremiums ?? this.totalPremiums,
      transactions: transactions ?? this.transactions,
    );
  }

  static const empty = WalletBalance(
    balance: 0,
    totalPayouts: 0,
    totalPremiums: 0,
    transactions: [],
  );

  @override
  List<Object?> get props =>
      [balance, totalPayouts, totalPremiums, transactions];
}
