import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/router/app_router.dart';
import '../../shared/widgets/primary_button.dart';

class OnboardingCarouselScreen extends StatefulWidget {
  const OnboardingCarouselScreen({super.key});

  @override
  State<OnboardingCarouselScreen> createState() => _OnboardingCarouselScreenState();
}

class _OnboardingCarouselScreenState extends State<OnboardingCarouselScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  final List<Map<String, dynamic>> _slides = [
    {
      'icon': Icons.shield_rounded,
      'title': 'Honest workers always get paid.',
      'subtitle': '7-layer fraud check runs in 2 seconds.',
      'chip': 'Fair & Verified',
    },
    {
      'icon': Icons.thunderstorm_rounded,
      'title': 'No forms.\nNo calls.',
      'subtitle': 'Rain hits your zone — automatic instant payout before you notice.',
      'chip': 'Instant Release',
    },
    {
      'icon': Icons.savings_rounded,
      'title': 'Starts at ₹35/week.',
      'subtitle': 'Affordable, transparent, and cancel anytime.',
      'chip': 'Pricing',
    },
    {
      'icon': Icons.trending_up_rounded,
      'title': 'Keep your Core Score high',
      'subtitle': 'The fewer non-verified claims you submit, the higher your score stays.',
      'chip': 'Rewards',
    },
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onNext() {
    if (_currentPage == _slides.length - 1) {
      if (mounted) context.go(AppRoutes.kycConsent);
    } else {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 600),
        curve: Curves.fastOutSlowIn,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.canvasColor,
      body: SafeArea(
        child: Column(
          children: [
            // Floating Top Indicator / Chip
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
              child: Align(
                alignment: Alignment.centerLeft,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: Container(
                    key: ValueKey(_currentPage),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: isDark ? theme.colorScheme.surface : theme.colorScheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.2)),
                    ),
                    child: Text(
                      _slides[_currentPage]['chip'].toString().toUpperCase(),
                      style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.primary),
                    ),
                  ),
                ),
              ),
            ),
            
            // Headline Section
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Align(
                alignment: Alignment.centerLeft,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 400),
                  child: Column(
                    key: ValueKey(_currentPage),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _slides[_currentPage]['title'],
                        style: theme.textTheme.displayMedium,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _slides[_currentPage]['subtitle'],
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const Spacer(),

            // Static Central Graphic
            SizedBox(
              height: 300,
              child: PageView.builder(
                controller: _pageController,
                physics: const BouncingScrollPhysics(),
                onPageChanged: (idx) => setState(() => _currentPage = idx),
                itemCount: _slides.length,
                itemBuilder: (context, index) {
                  final slide = _slides[index];
                  final isActive = _currentPage == index;

                  return AnimatedOpacity(
                    duration: const Duration(milliseconds: 300),
                    opacity: isActive ? 1.0 : 0.0,
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
                      decoration: BoxDecoration(
                        color: theme.cardColor,
                        shape: BoxShape.circle,
                        boxShadow: isDark ? [
                          BoxShadow(color: theme.colorScheme.primary.withValues(alpha: 0.04), blurRadius: 40, offset: const Offset(0, 20)),
                        ] : [
                          BoxShadow(color: theme.colorScheme.primary.withValues(alpha: 0.1), blurRadius: 40, offset: const Offset(0, 20)),
                        ],
                        border: isDark ? null : Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.1)),
                      ),
                      child: Icon(
                        slide['icon'],
                        size: 120,
                        color: theme.colorScheme.primary.withValues(alpha: isDark ? 0.8 : 1.0),
                      ),
                    ),
                  );
                },
              ),
            ),

            const Spacer(),

            // Footer (Progress + Button)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // Progress Dots
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(_slides.length, (idx) {
                      final isActive = _currentPage == idx;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        margin: const EdgeInsets.only(right: 8),
                        height: 8,
                        width: isActive ? 32 : 8,
                        decoration: BoxDecoration(
                          color: isActive ? theme.colorScheme.primary : theme.colorScheme.onSurface.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                          boxShadow: isActive && isDark ? [
                            BoxShadow(color: theme.colorScheme.primary.withValues(alpha: 0.3), blurRadius: 8),
                          ] : [],
                        ),
                      );
                    }),
                  ),

                  // Asymmetric CTA
                  SizedBox(
                    width: 140, // Not full width to match asymmetric style
                    child: PrimaryButton(
                      text: _currentPage == _slides.length - 1 ? 'Start' : 'Next',
                      onPressed: _onNext,
                    ),
                  )
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
