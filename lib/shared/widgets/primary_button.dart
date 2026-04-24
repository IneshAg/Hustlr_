import 'package:flutter/material.dart';

class PrimaryButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;

  const PrimaryButton({
    super.key,
    required this.text,
    this.onPressed,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final gradColors = isDark 
      ? const [Color(0xFF3FFF8B), Color(0xFF00E676)]
      : const [Color(0xFF125117), Color(0xFF2D6A2D)];

    final textColor = isDark ? const Color(0xFF141614) : Colors.white;

    return Opacity(
      opacity: onPressed == null ? 0.5 : 1.0,
      child: Container(
        width: double.infinity,
        height: 56,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: gradColors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(28),
          boxShadow: isDark 
            ? [BoxShadow(color: gradColors[0].withValues(alpha: 0.15), blurRadius: 20, offset: const Offset(0, 10))]
            : [BoxShadow(color: gradColors[0].withValues(alpha: 0.25), blurRadius: 16, offset: const Offset(0, 8))],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(28),
            onTap: isLoading ? null : onPressed,
            child: Center(
              child: isLoading 
                  ? SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: textColor, strokeWidth: 3))
                  : Text(
                      text,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: textColor,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
