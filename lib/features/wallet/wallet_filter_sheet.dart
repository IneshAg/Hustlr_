import 'dart:ui';
import 'package:flutter/material.dart';

class _FilterChoice {
  final String label;
  final IconData icon;
  const _FilterChoice(this.label, this.icon);
}

const _typeFilters = [
  _FilterChoice('All', Icons.apps_rounded),
  _FilterChoice('Payouts', Icons.arrow_downward_rounded),
  _FilterChoice('Premiums', Icons.shield_rounded),
  _FilterChoice('Cashback', Icons.card_giftcard_rounded),
  _FilterChoice('Withdrawals', Icons.account_balance_wallet_rounded),
];

const _periodFilters = [
  _FilterChoice('This week', Icons.view_week_rounded),
  _FilterChoice('This month', Icons.calendar_today_rounded),
  _FilterChoice('Last 3 months', Icons.date_range_rounded),
];

void showWalletFilterSheet(
  BuildContext context, {
  String initialType = 'All',
  String initialPeriod = 'This month',
  required void Function(String type, String period) onApply,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.65),
    builder: (ctx) => _WalletFilterSheet(
      initialType: initialType,
      initialPeriod: initialPeriod,
      onApply: onApply,
    ),
  );
}

class _WalletFilterSheet extends StatefulWidget {
  final String initialType;
  final String initialPeriod;
  final void Function(String type, String period) onApply;

  const _WalletFilterSheet({
    required this.initialType,
    required this.initialPeriod,
    required this.onApply,
  });

  @override
  State<_WalletFilterSheet> createState() => _WalletFilterSheetState();
}

class _WalletFilterSheetState extends State<_WalletFilterSheet> with TickerProviderStateMixin {
  late String _selectedType;
  late String _selectedPeriod;

  late AnimationController _entryAnim;
  late AnimationController _shimmerAnim;

  @override
  void initState() {
    super.initState();
    _selectedType = widget.initialType;
    _selectedPeriod = widget.initialPeriod;

    _entryAnim = AnimationController(vsync: this, duration: const Duration(milliseconds: 600))..forward();
    _shimmerAnim = AnimationController(vsync: this, duration: const Duration(milliseconds: 2000))..repeat();
  }

  @override
  void dispose() {
    _entryAnim.dispose();
    _shimmerAnim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
            border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.04), width: 1),
            boxShadow: isDark ? [] : [
              const BoxShadow(color: Color(0x33000000), blurRadius: 40, offset: Offset(0, -8)),
            ],
          ),
          padding: EdgeInsets.only(
            left: 24, right: 24, top: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 32,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DragHandle(shimmerAnim: _shimmerAnim, theme: theme, isDark: isDark),
              const SizedBox(height: 20),

              Row(
                children: [
                  Text('Filter Transactions', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: theme.colorScheme.onSurface, letterSpacing: -0.3)),
                  const Spacer(),
                  GestureDetector(
                    onTap: () {
                      setState(() { _selectedType = 'All'; _selectedPeriod = 'This month'; });
                    },
                    child: Text('Reset', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: theme.colorScheme.primary.withValues(alpha: 0.8))),
                  ),
                ],
              ),
              const SizedBox(height: 28),

              _sectionLabel('TYPE', theme),
              const SizedBox(height: 14),

              _MagneticBubbleRow(
                choices: _typeFilters,
                selected: _selectedType,
                entryAnim: _entryAnim,
                onSelect: (v) => setState(() => _selectedType = v),
                theme: theme,
                isDark: isDark,
              ),
              const SizedBox(height: 26),

              _sectionLabel('PERIOD', theme),
              const SizedBox(height: 14),

              ..._periodFilters.asMap().entries.map((e) {
                final idx = e.key;
                final choice = e.value;
                return AnimatedBuilder(
                  animation: _entryAnim,
                  builder: (context, child) {
                    final delay = (idx * 0.12).clamp(0.0, 0.8);
                    final t = ((_entryAnim.value - delay) / (1 - delay)).clamp(0.0, 1.0);
                    return Transform.translate(
                      offset: Offset(0, 20 * (1 - t)),
                      child: Opacity(opacity: t.clamp(0.0, 1.0), child: child),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _PeriodRow(
                      choice: choice,
                      isSelected: _selectedPeriod == choice.label,
                      index: idx,
                      onTap: () => setState(() => _selectedPeriod = choice.label),
                      theme: theme,
                      isDark: isDark,
                    ),
                  ),
                );
              }),

              const SizedBox(height: 28),

              GestureDetector(
                onTap: () {
                  Navigator.of(context).pop();
                  widget.onApply(_selectedType, _selectedPeriod);
                },
                child: Container(
                  width: double.infinity,
                  height: 60,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    borderRadius: BorderRadius.circular(30),
                  ),
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Apply Filter', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: isDark ? theme.canvasColor : Colors.white, letterSpacing: 0.5)),
                      const SizedBox(width: 10),
                      Icon(Icons.tune_rounded, color: isDark ? theme.canvasColor : Colors.white, size: 18),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String text, ThemeData theme) => Text(text,
      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: theme.colorScheme.primary.withValues(alpha: 0.8), letterSpacing: 2.5));
}

class _DragHandle extends StatelessWidget {
  final AnimationController shimmerAnim;
  final ThemeData theme;
  final bool isDark;

  const _DragHandle({required this.shimmerAnim, required this.theme, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AnimatedBuilder(
        animation: shimmerAnim,
        builder: (context, _) {
          return Container(
            width: 48, height: 4,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(2),
              gradient: LinearGradient(
                colors: [
                  theme.colorScheme.primary.withValues(alpha: 0.2),
                  theme.colorScheme.primary.withValues(alpha: 0.5 + shimmerAnim.value * 0.3),
                  theme.colorScheme.primary.withValues(alpha: 0.2),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _MagneticBubbleRow extends StatelessWidget {
  final List<_FilterChoice> choices;
  final String selected;
  final AnimationController entryAnim;
  final ValueChanged<String> onSelect;
  final ThemeData theme;
  final bool isDark;

  const _MagneticBubbleRow({
    required this.choices, required this.selected, required this.entryAnim,
    required this.onSelect, required this.theme, required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 12,
      children: choices.asMap().entries.map((e) {
        final idx = e.key;
        final choice = e.value;
        final isSelected = selected == choice.label;

        return AnimatedBuilder(
          animation: entryAnim,
          builder: (context, child) {
            final delay = (idx * 0.1).clamp(0.0, 0.9);
            final progress = ((entryAnim.value - delay) / (1 - delay)).clamp(0.0, 1.0);
            final entryY = 18.0 * (1 - progress);

            return Transform.translate(
              offset: Offset(0, entryY),
              child: Opacity(
                opacity: progress.clamp(0.0, 1.0),
                child: child,
              ),
            );
          },
          child: GestureDetector(
            onTap: () => onSelect(choice.label),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: isSelected ? theme.colorScheme.primary.withValues(alpha: 0.15) : theme.cardColor,
                borderRadius: BorderRadius.circular(30),
                border: Border.all(
                  color: isSelected ? theme.colorScheme.primary.withValues(alpha: 0.7) : (isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.04)),
                  width: isSelected ? 1.5 : 1,
                ),
                boxShadow: isDark ? [] : [
                  BoxShadow(color: (isSelected ? theme.colorScheme.primary : Colors.black).withValues(alpha: isSelected ? 0.1 : 0.05), blurRadius: 8, offset: const Offset(0, 3)),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(choice.icon, size: 13, color: isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurface.withValues(alpha: 0.5)),
                  const SizedBox(width: 6),
                  Text(choice.label,
                      style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w800,
                        color: isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurface.withValues(alpha: 0.5),
                        letterSpacing: 0.2,
                      )),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _PeriodRow extends StatelessWidget {
  final _FilterChoice choice;
  final bool isSelected;
  final int index;
  final VoidCallback onTap;
  final ThemeData theme;
  final bool isDark;

  const _PeriodRow({
    required this.choice, required this.isSelected,
    required this.index, required this.onTap, required this.theme, required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            color: isSelected ? theme.colorScheme.primary.withValues(alpha: 0.1) : theme.cardColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected ? theme.colorScheme.primary.withValues(alpha: 0.6) : (isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.04)),
              width: isSelected ? 1.5 : 1,
            ),
            boxShadow: isDark ? [] : [
               BoxShadow(color: (isSelected ? theme.colorScheme.primary : Colors.black).withValues(alpha: 0.05), blurRadius: 6, offset: const Offset(0, 2)),
            ],
          ),
          child: Row(
            children: [
              Icon(choice.icon, size: 16, color: isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurface.withValues(alpha: 0.5)),
              const SizedBox(width: 14),
              Text(choice.label,
                  style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w800,
                    color: isSelected ? theme.colorScheme.onSurface : theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  )),
              const Spacer(),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 22, height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isSelected ? theme.colorScheme.primary.withValues(alpha: 0.2) : Colors.transparent,
                  border: Border.all(
                    color: isSelected ? theme.colorScheme.primary.withValues(alpha: 0.8) : theme.colorScheme.onSurface.withValues(alpha: 0.1),
                    width: 1.5,
                  ),
                ),
                child: isSelected
                    ? Icon(Icons.check_rounded, size: 13, color: theme.colorScheme.primary)
                    : null,
              ),
            ],
          ),
        ),
      );
  }
}
