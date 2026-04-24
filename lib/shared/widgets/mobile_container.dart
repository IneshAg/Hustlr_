import 'package:flutter/material.dart';

/// Constrains content to a max width of 480px, centered.
/// Used on every screen so the app looks like a mobile app even in Chrome.
class MobileContainer extends StatelessWidget {
  final Widget child;
  const MobileContainer({required this.child, super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: child,
      ),
    );
  }
}
