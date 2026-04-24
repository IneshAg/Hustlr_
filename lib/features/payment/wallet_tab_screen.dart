import 'package:flutter/material.dart';

import 'checkout_screen.dart'
    show
        kDarkGreen,
        kLightGreen,
        kTextDark,
        kTextGrey,
        kTextLight,
        kRed,
        kRedLight;

// ─── Wallet tab screen ────────────────────────────────────────────────────────
class WalletTabScreen extends StatefulWidget {
  final double amount;
  final String planName;
  final bool isEligible;
  final int activeDays;
  final VoidCallback onSwitchToCard;

  const WalletTabScreen({
    required this.amount,
    required this.planName,
    required this.isEligible,
    required this.activeDays,
    required this.onSwitchToCard,
    super.key,
  });

  @override
  State<WalletTabScreen> createState() => _WalletTabScreenState();
}

class _WalletTabScreenState extends State<WalletTabScreen> {
  double walletBalance = 0.0;
  double? selectedTopUp;

  @override
  Widget build(BuildContext context) {
    final shortfall =
        (widget.amount - walletBalance).clamp(0.0, widget.amount);
    final hasSufficient = walletBalance >= widget.amount;

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),

                // ── Wallet balance card ──────────────────────────────────────
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.07),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      // Wallet icon + label
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: const BoxDecoration(
                              color: kLightGreen,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.account_balance_wallet,
                              color: kDarkGreen,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'HUSTLR WALLET',
                            style: TextStyle(
                              color: kTextGrey,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Balance amount
                      Text(
                        '₹${walletBalance.toInt()}',
                        style: const TextStyle(
                          color: kTextDark,
                          fontSize: 48,
                          fontWeight: FontWeight.bold,
                          height: 1.0,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'current balance',
                        style: TextStyle(color: kTextGrey, fontSize: 13),
                      ),
                      const SizedBox(height: 16),

                      const Divider(
                        color: Color(0xFFF3F4F6),
                        thickness: 1,
                      ),
                      const SizedBox(height: 12),

                      // Required vs Shortfall
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              children: [
                                Text(
                                  '₹${widget.amount.toInt()}',
                                  style: const TextStyle(
                                    color: kRed,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const Text(
                                  'required',
                                  style: TextStyle(
                                    color: kTextLight,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            width: 1,
                            height: 36,
                            color: const Color(0xFFE5E7EB),
                          ),
                          Expanded(
                            child: Column(
                              children: [
                                Text(
                                  '₹${shortfall.toInt()}',
                                  style: const TextStyle(
                                    color: kDarkGreen,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const Text(
                                  'shortfall',
                                  style: TextStyle(
                                    color: kTextLight,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // ── Insufficient balance notice ──────────────────────────────
                if (!hasSufficient) ...[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: kRedLight,
                      border: const Border(
                        left: BorderSide(color: kRed, width: 3),
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.error_outline,
                            color: kRed, size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Insufficient balance',
                                style: TextStyle(
                                  color: Color(0xFF991B1B),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Add ₹${shortfall.toInt()} more to your wallet '
                                'to proceed with this payment.',
                                style: const TextStyle(
                                  color: kTextGrey,
                                  fontSize: 12,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],

                // ── Eligibility Lock Notice ──────────────────────────────────
                if (!widget.isEligible) ...[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0F9FF),
                      border: const Border(
                        left: BorderSide(color: Color(0xFF0EA5E9), width: 3),
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.lock_outline,
                            color: Color(0xFF0284C7), size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Plan Locked',
                                style: TextStyle(
                                  color: Color(0xFF075985),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Premium plans are locked during your first 5 active days. '
                                'You have ${widget.activeDays} days completed.',
                                style: const TextStyle(
                                  color: kTextGrey,
                                  fontSize: 12,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],

                // ── Add money label ──────────────────────────────────────────
                const Text(
                  'Add money to wallet:',
                  style: TextStyle(color: kTextDark, fontSize: 14),
                ),
                const SizedBox(height: 10),

                // ── Amount chips row ─────────────────────────────────────────
                Row(
                  children: [49.0, 79.0, 100.0].map((amt) {
                    final isSelected = selectedTopUp == amt;
                    final isLast = amt == 100.0;
                    return Expanded(
                      child: GestureDetector(
                        onTap: () =>
                            setState(() => selectedTopUp = amt),
                        child: Container(
                          margin: EdgeInsets.only(right: isLast ? 0 : 10),
                          padding:
                              const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? kDarkGreen
                                : Colors.white,
                            border: Border.all(
                              color: isSelected
                                  ? kDarkGreen
                                  : const Color(0xFFE5E7EB),
                              width: 1.5,
                            ),
                            borderRadius: BorderRadius.circular(100),
                          ),
                          child: Text(
                            '₹${amt.toInt()}',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: isSelected
                                  ? Colors.white
                                  : kDarkGreen,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 20),

                // ── OR PAY DIRECTLY divider ──────────────────────────────────
                Row(
                  children: [
                    const Expanded(
                        child: Divider(color: Color(0xFFE5E7EB))),
                    Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 12),
                      child: const Text(
                        'OR PAY DIRECTLY',
                        style: TextStyle(
                          color: kTextLight,
                          fontSize: 11,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                    const Expanded(
                        child: Divider(color: Color(0xFFE5E7EB))),
                  ],
                ),
                const SizedBox(height: 16),

                // ── Switch to Card button ────────────────────────────────────
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: OutlinedButton(
                    onPressed: widget.onSwitchToCard,
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(
                          color: kDarkGreen, width: 1.5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(28),
                      ),
                    ),
                    child: Text(
                      'Pay ₹${widget.amount.toInt()} with Card / UPI →',
                      style: const TextStyle(
                        color: kDarkGreen,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 80),
              ],
            ),
          ),
        ),

        // ── Sticky bottom bar ────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(
              top: BorderSide(color: Color(0xFFE5E7EB), width: 1),
            ),
          ),
          child: Row(
            children: [
              // Cancel
              Expanded(
                child: GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.close, color: kTextLight, size: 20),
                      SizedBox(height: 4),
                      Text(
                        'CANCEL',
                        style: TextStyle(
                          color: kTextLight,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Add Balance / Pay Now button
              Expanded(
                flex: 2,
                child: SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: (hasSufficient && widget.isEligible)
                        ? () {
                            // process wallet payment
                          }
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: hasSufficient
                          ? kDarkGreen
                          : const Color(0xFFE5E7EB),
                      foregroundColor: hasSufficient
                          ? Colors.white
                          : kTextLight,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(28),
                      ),
                      elevation: 0,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          hasSufficient
                              ? Icons.shield
                              : Icons.add,
                          size: 16,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          !widget.isEligible
                              ? 'PLAN LOCKED'
                              : (hasSufficient ? 'PAY NOW' : 'ADD BALANCE TO PAY'),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
