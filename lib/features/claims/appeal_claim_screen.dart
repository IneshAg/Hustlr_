import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../blocs/claims/claims_bloc.dart';
import '../../blocs/claims/claims_event.dart';
import '../../blocs/claims/claims_state.dart';
import '../../models/claim.dart';
import 'package:intl/intl.dart';

class AppealClaimScreen extends StatefulWidget {
  final Claim rejectedClaim;

  const AppealClaimScreen({super.key, required this.rejectedClaim});

  @override
  State<AppealClaimScreen> createState() => _AppealClaimScreenState();
}

class _AppealClaimScreenState extends State<AppealClaimScreen> {
  final _appealTextController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  String? _selectedReason;
  bool _isSubmitting = false;

  // Structured reason list — parseable by backend, not free-form coaching vector
  static const List<String> _appealReasons = [
    'IMD data was correct but my shift overlap was not recognised',
    'I was in the zone but GPS signal dropped',
    'The disruption lasted longer than the system recorded',
    'My dark store was closed — orders were impossible',
    'Road blockage prevented all deliveries in my area',
    'Other — see explanation below',
  ];

  @override
  void dispose() {
    _appealTextController.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _selectedReason != null &&
      (_selectedReason != 'Other — see explanation below' ||
          _appealTextController.text.trim().length >= 20);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return BlocListener<ClaimsBloc, ClaimsState>(
      listener: (context, state) {
        if (state.status == LoadStatus.success && _isSubmitting) {
          setState(() => _isSubmitting = false);
          _showSuccessSheet(context);
        } else if (state.status == LoadStatus.failure && _isSubmitting) {
          setState(() => _isSubmitting = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.errorMessage ?? 'Appeal submission failed. Try again.'),
              backgroundColor: const Color(0xFFE24B4A),
            ),
          );
        }
      },
      child: Scaffold(
        backgroundColor: isDark ? const Color(0xFF0A0B0A) : const Color(0xFFF4F6F4),
        appBar: AppBar(
          backgroundColor: isDark ? const Color(0xFF0A0B0A) : const Color(0xFFF4F6F4),
          elevation: 0,
          leading: IconButton(
            icon: Icon(
              Icons.arrow_back_ios_new,
              size: 18,
              color: isDark ? Colors.white : Colors.black,
            ),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(
            'Appeal Claim',
            style: TextStyle(
              fontFamily: 'Manrope',
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
        ),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _RejectedClaimCard(claim: widget.rejectedClaim, isDark: isDark),
              const SizedBox(height: 24),
              _SectionLabel(text: 'What went wrong?', isDark: isDark),
              const SizedBox(height: 10),
              _ReasonSelector(
                reasons: _appealReasons,
                selected: _selectedReason,
                isDark: isDark,
                onChanged: (val) => setState(() => _selectedReason = val),
              ),
              if (_selectedReason == 'Other — see explanation below') ...[
                const SizedBox(height: 16),
                _SectionLabel(text: 'Explain what happened', isDark: isDark),
                const SizedBox(height: 10),
                _ExplanationField(
                  controller: _appealTextController,
                  isDark: isDark,
                  onChanged: (_) => setState(() {}),
                ),
                _CharCounter(
                  controller: _appealTextController,
                  isDark: isDark,
                ),
              ],
              const SizedBox(height: 24),
              _AppealInfoBanner(isDark: isDark),
              const SizedBox(height: 24),
              _SubmitButton(
                enabled: _canSubmit && !_isSubmitting,
                isSubmitting: _isSubmitting,
                isDark: isDark,
                onTap: _handleSubmit,
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  void _handleSubmit() {
    if (!_canSubmit) return;
    setState(() => _isSubmitting = true);

    context.read<ClaimsBloc>().add(
      SubmitClaimAppeal(
        claimId: widget.rejectedClaim.id,
        workerId: widget.rejectedClaim.userId,
        selectedReason: _selectedReason!,
        additionalContext: _appealTextController.text.trim().isEmpty
            ? null
            : _appealTextController.text.trim(),
      ),
    );
  }

  void _showSuccessSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      backgroundColor: Colors.transparent,
      builder: (_) => _AppealSuccessSheet(
        onDone: () {
          Navigator.of(context).popUntil((route) => route.isFirst);
        },
      ),
    );
  }
}

// ─── Rejected Claim Card ───────────────────────────────────────────────────

class _RejectedClaimCard extends StatelessWidget {
  final Claim claim;
  final bool isDark;

  const _RejectedClaimCard({required this.claim, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1B1A) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFE24B4A).withValues(alpha: 0.4),
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFFCEBEB),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'Rejected',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFFA32D2D),
                    fontFamily: 'Manrope',
                  ),
                ),
              ),
              const Spacer(),
              Text(
                DateFormat('MMM d, yyyy').format(claim.createdAt),
                style: TextStyle(
                  fontSize: 12,
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.45)
                      : Colors.black.withValues(alpha: 0.45),
                  fontFamily: 'Manrope',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            claim.displayLabel,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white : Colors.black,
              fontFamily: 'Manrope',
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Claim #${claim.id.length >= 8 ? claim.id.substring(0, 8) : claim.id} · ${claim.zone}',
            style: TextStyle(
              fontSize: 13,
              color: isDark
                  ? Colors.white.withValues(alpha: 0.55)
                  : Colors.black.withValues(alpha: 0.55),
              fontFamily: 'Manrope',
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Section Label ─────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  final bool isDark;

  const _SectionLabel({required this.text, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: isDark
            ? Colors.white.withValues(alpha: 0.55)
            : Colors.black.withValues(alpha: 0.55),
        fontFamily: 'Manrope',
        letterSpacing: 0.3,
      ),
    );
  }
}

// ─── Reason Selector ───────────────────────────────────────────────────────

class _ReasonSelector extends StatelessWidget {
  final List<String> reasons;
  final String? selected;
  final bool isDark;
  final ValueChanged<String?> onChanged;

  const _ReasonSelector({
    required this.reasons,
    required this.selected,
    required this.isDark,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: reasons.map((reason) {
        final isSelected = selected == reason;
        return GestureDetector(
          onTap: () => onChanged(reason),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              color: isSelected
                  ? (isDark
                      ? const Color(0xFF3FFF8B).withValues(alpha: 0.08)
                      : const Color(0xFF2E7D32).withValues(alpha: 0.06))
                  : (isDark ? const Color(0xFF1A1B1A) : Colors.white),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isSelected
                    ? (isDark
                        ? const Color(0xFF3FFF8B).withValues(alpha: 0.5)
                        : const Color(0xFF2E7D32).withValues(alpha: 0.5))
                    : (isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : Colors.black.withValues(alpha: 0.08)),
                width: isSelected ? 1.0 : 0.5,
              ),
            ),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSelected
                        ? (isDark
                            ? const Color(0xFF3FFF8B)
                            : const Color(0xFF2E7D32))
                        : Colors.transparent,
                    border: Border.all(
                      color: isSelected
                          ? Colors.transparent
                          : (isDark
                              ? Colors.white.withValues(alpha: 0.3)
                              : Colors.black.withValues(alpha: 0.3)),
                      width: 1.5,
                    ),
                  ),
                  child: isSelected
                      ? Icon(
                          Icons.check,
                          size: 11,
                          color: isDark ? Colors.black : Colors.white,
                        )
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    reason,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight:
                          isSelected ? FontWeight.w500 : FontWeight.w400,
                      color: isDark ? Colors.white : Colors.black,
                      fontFamily: 'Manrope',
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ─── Explanation Field ─────────────────────────────────────────────────────

class _ExplanationField extends StatelessWidget {
  final TextEditingController controller;
  final bool isDark;
  final ValueChanged<String> onChanged;

  const _ExplanationField({
    required this.controller,
    required this.isDark,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      maxLength: 300,
      maxLines: 4,
      minLines: 3,
      buildCounter: (_, {required currentLength, required isFocused, maxLength}) =>
          null, // hide default counter — we render our own
      style: TextStyle(
        fontSize: 14,
        fontFamily: 'Manrope',
        color: isDark ? Colors.white : Colors.black,
      ),
      decoration: InputDecoration(
        hintText: 'Describe what happened during the disruption...',
        hintStyle: TextStyle(
          fontSize: 14,
          fontFamily: 'Manrope',
          color: isDark
              ? Colors.white.withValues(alpha: 0.3)
              : Colors.black.withValues(alpha: 0.3),
        ),
        filled: true,
        fillColor: isDark ? const Color(0xFF1A1B1A) : Colors.white,
        contentPadding: const EdgeInsets.all(14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.08),
            width: 0.5,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.08),
            width: 0.5,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: isDark
                ? const Color(0xFF3FFF8B).withValues(alpha: 0.5)
                : const Color(0xFF2E7D32).withValues(alpha: 0.5),
            width: 1.0,
          ),
        ),
      ),
    );
  }
}

// ─── Char Counter ──────────────────────────────────────────────────────────

class _CharCounter extends StatelessWidget {
  final TextEditingController controller;
  final bool isDark;

  const _CharCounter({required this.controller, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, right: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          ValueListenableBuilder(
            valueListenable: controller,
            builder: (_, value, __) {
              final count = value.text.length;
              final tooShort = count > 0 && count < 20;
              return Text(
                tooShort
                    ? 'Minimum 20 characters ($count/300)'
                    : '$count/300',
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'Manrope',
                  color: tooShort
                      ? const Color(0xFFE24B4A)
                      : (isDark
                          ? Colors.white.withValues(alpha: 0.35)
                          : Colors.black.withValues(alpha: 0.35)),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ─── Info Banner ───────────────────────────────────────────────────────────

class _AppealInfoBanner extends StatelessWidget {
  final bool isDark;

  const _AppealInfoBanner({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.04)
            : Colors.black.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border(
          left: BorderSide(
            color: isDark
                ? const Color(0xFF3FFF8B).withValues(alpha: 0.4)
                : const Color(0xFF2E7D32).withValues(alpha: 0.4),
            width: 3,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'What happens next',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white : Colors.black,
              fontFamily: 'Manrope',
            ),
          ),
          const SizedBox(height: 6),
          _InfoRow(
            text: 'Your appeal is reviewed within 4 hours',
            isDark: isDark,
          ),
          _InfoRow(
            text: 'You will receive a push notification with the decision',
            isDark: isDark,
          ),
          _InfoRow(
            text: 'If approved, payout is credited to your wallet immediately',
            isDark: isDark,
          ),
          _InfoRow(
            text: 'Only one appeal per claim is permitted',
            isDark: isDark,
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String text;
  final bool isDark;

  const _InfoRow({required this.text, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 6, right: 8),
            width: 4,
            height: 4,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isDark
                  ? Colors.white.withValues(alpha: 0.4)
                  : Colors.black.withValues(alpha: 0.4),
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                color: isDark
                    ? Colors.white.withValues(alpha: 0.6)
                    : Colors.black.withValues(alpha: 0.6),
                fontFamily: 'Manrope',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Submit Button ─────────────────────────────────────────────────────────

class _SubmitButton extends StatelessWidget {
  final bool enabled;
  final bool isSubmitting;
  final bool isDark;
  final VoidCallback onTap;

  const _SubmitButton({
    required this.enabled,
    required this.isSubmitting,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 52,
        decoration: BoxDecoration(
          color: enabled
              ? (isDark ? const Color(0xFF3FFF8B) : const Color(0xFF2E7D32))
              : (isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.08)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: isSubmitting
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: isDark ? Colors.black : Colors.white,
                  ),
                )
              : Text(
                  'Submit Appeal',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'Manrope',
                    color: enabled
                        ? (isDark ? Colors.black : Colors.white)
                        : (isDark
                            ? Colors.white.withValues(alpha: 0.3)
                            : Colors.black.withValues(alpha: 0.3)),
                  ),
                ),
        ),
      ),
    );
  }
}

// ─── Success Bottom Sheet ──────────────────────────────────────────────────

class _AppealSuccessSheet extends StatelessWidget {
  final VoidCallback onDone;

  const _AppealSuccessSheet({required this.onDone});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1B1A) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF3FFF8B).withValues(alpha: 0.12)
                  : const Color(0xFF2E7D32).withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.check,
              color: isDark ? const Color(0xFF3FFF8B) : const Color(0xFF2E7D32),
              size: 24,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Appeal submitted',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w500,
              fontFamily: 'Manrope',
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Our team will review your appeal within 4 hours.\nYou will be notified of the decision.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              fontFamily: 'Manrope',
              color: isDark
                  ? Colors.white.withValues(alpha: 0.55)
                  : Colors.black.withValues(alpha: 0.55),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 24),
          GestureDetector(
            onTap: onDone,
            child: Container(
              width: double.infinity,
              height: 50,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF3FFF8B) : const Color(0xFF2E7D32),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  'Back to claims',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'Manrope',
                    color: isDark ? Colors.black : Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
