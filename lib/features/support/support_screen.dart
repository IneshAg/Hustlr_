import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/router/app_router.dart';
import '../../shared/widgets/mobile_container.dart';
import '../../l10n/app_localizations.dart';

Future<void> _launch(String url) async {
  final uri = Uri.parse(url);
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}


class SupportScreen extends StatelessWidget {
  const SupportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n   = AppLocalizations.of(context)!;
    final theme  = Theme.of(context);
    final bgColor   = theme.scaffoldBackgroundColor;
    final titleColor = theme.colorScheme.onSurface;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        leading: BackButton(color: titleColor, onPressed: () => context.pop()),
        title: Text(
          l10n.support_title,
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: titleColor),
        ),
        centerTitle: true,
      ),
      body: MobileContainer(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              const _SearchBar(),
              const SizedBox(height: 24),
              const _QuickHelpGrid(),
              const SizedBox(height: 32),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  l10n.support_faq,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: titleColor),
                ),
              ),
              const SizedBox(height: 16),
              const _FaqAccordion(),
              const SizedBox(height: 32),
              const _TicketCard(),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Search Bar ───────────────────────────────────────────────────────────────
class _SearchBar extends StatelessWidget {
  const _SearchBar();

  @override
  Widget build(BuildContext context) {
    final l10n     = AppLocalizations.of(context)!;
    final theme    = Theme.of(context);
    final isDark   = theme.brightness == Brightness.dark;
    final cardBg   = theme.cardColor;
    final hintColor = theme.colorScheme.onSurface.withValues(alpha: 0.4);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(28),
          boxShadow: isDark ? [] : [
            const BoxShadow(color: Color(0x05000000), blurRadius: 10, offset: Offset(0, 2))
          ],
        ),
        child: Row(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Icon(Icons.search_rounded, color: hintColor, size: 20),
            ),
            Expanded(
              child: TextField(
                decoration: InputDecoration(
                  hintText: l10n.support_search,
                  hintStyle: TextStyle(color: hintColor, fontSize: 14),
                  border: InputBorder.none,
                  fillColor: Colors.transparent,
                  filled: true,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Quick Help Grid ──────────────────────────────────────────────────────────
class _QuickHelpGrid extends StatelessWidget {
  const _QuickHelpGrid();

  @override
  Widget build(BuildContext context) {
    final l10n   = AppLocalizations.of(context)!;
    final theme  = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final green  = theme.colorScheme.primary;
    final lightGreen = isDark ? const Color(0xFF004734) : const Color(0xFFE8F5E9);
    final blue      = isDark ? const Color(0xFF3FFF8B) : const Color(0xFF1976D2);
    final lightBlue = isDark ? const Color(0xFF003D2A) : const Color(0xFFE3F2FD);
    final purple     = isDark ? const Color(0xFFCE93D8) : const Color(0xFF7B1FA2);
    final lightPurple = isDark ? const Color(0xFF1A0027) : const Color(0xFFF3E5F5);

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.2,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        _GridCard(
          icon: Icons.chat_bubble_outline_rounded,
          iconColor: green,
          iconBg: lightGreen,
          title: l10n.support_live_chat,
          subtitle: l10n.support_live_chat_sub.toUpperCase(),
          isGreenCaps: true,
          onTap: () {
            context.push(AppRoutes.supportChat);
          },
        ),
        _GridCard(
          icon: Icons.phone_outlined,
          iconColor: blue,
          iconBg: lightBlue,
          title: l10n.support_call,
          subtitle: l10n.support_call_sub,
          onTap: () => _launch('tel:+911234567890'),
        ),
        _GridCard(
          icon: Icons.message_rounded,
          iconColor: green,
          iconBg: lightGreen,
          title: l10n.support_whatsapp,
          subtitle: l10n.support_whatsapp_sub,
          onTap: () => _launch('https://wa.me/911234567890'),
        ),
        _GridCard(
          icon: Icons.email_outlined,
          iconColor: purple,
          iconBg: lightPurple,
          title: l10n.support_email,
          subtitle: l10n.support_email_sub,
          onTap: () => _launch('mailto:support@hustlr.in'),
        ),
      ],
    );
  }
}

class _GridCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String title;
  final String subtitle;
  final bool isGreenCaps;
  final VoidCallback? onTap;

  const _GridCard({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
    required this.subtitle,
    this.isGreenCaps = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme    = Theme.of(context);
    final isDark   = theme.brightness == Brightness.dark;
    final cardBg   = theme.cardColor;
    final titleColor = theme.colorScheme.onSurface;
    final subColor   = theme.colorScheme.onSurface.withValues(alpha: 0.5);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(16),
          boxShadow: isDark ? [] : [
            const BoxShadow(color: Color(0x05000000), blurRadius: 10, offset: Offset(0, 2))
          ],
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
              child: Icon(icon, color: iconColor, size: 24),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: titleColor),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: isGreenCaps ? 10 : 12,
                fontWeight: isGreenCaps ? FontWeight.bold : FontWeight.normal,
                color: isGreenCaps ? iconColor : subColor,
                letterSpacing: isGreenCaps ? 0.5 : 0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── FAQ Accordion ────────────────────────────────────────────────────────────
class _FaqAccordion extends StatelessWidget {
  const _FaqAccordion();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          _FaqItem(
            question: l10n.support_faq_1_q,
            answer: l10n.support_faq_1_a,
          ),
          const SizedBox(height: 12),
          _FaqItem(
            question: l10n.support_faq_2_q,
            answer: l10n.support_faq_2_a,
          ),
          const SizedBox(height: 12),
          _FaqItem(
            question: l10n.support_faq_3_q,
            answer: l10n.support_faq_3_a,
          ),
          const SizedBox(height: 12),
          _FaqItem(
            question: l10n.support_faq_4_q,
            answer: l10n.support_faq_4_a,
          ),
          const SizedBox(height: 12),
          _FaqItem(
            question: l10n.support_faq_5_q,
            answer: l10n.support_faq_5_a,
          ),
          const SizedBox(height: 12),
          _FaqItem(
            question: l10n.support_faq_6_q,
            answer: l10n.support_faq_6_a,
          ),
          const SizedBox(height: 12),
          _FaqItem(
            question: l10n.support_faq_7_q,
            answer: l10n.support_faq_7_a,
          ),
        ],
      ),
    );
  }
}

class _FaqItem extends StatefulWidget {
  final String question;
  final String answer;
  const _FaqItem({required this.question, required this.answer});

  @override
  State<_FaqItem> createState() => _FaqItemState();
}

class _FaqItemState extends State<_FaqItem> {

  @override
  Widget build(BuildContext context) {
    final theme    = Theme.of(context);
    final isDark   = theme.brightness == Brightness.dark;
    final cardBg   = theme.cardColor;
    final qColor   = theme.colorScheme.onSurface;
    final aColor   = theme.colorScheme.onSurface.withValues(alpha: 0.6);
    final chevron  = theme.colorScheme.onSurface.withValues(alpha: 0.4);

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        boxShadow: isDark ? [] : [
          const BoxShadow(color: Color(0x05000000), blurRadius: 10, offset: Offset(0, 2))
        ],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          title: Text(widget.question, style: TextStyle(fontSize: 14, color: qColor)),
          iconColor: chevron,
          collapsedIconColor: chevron,
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          onExpansionChanged: (_) {},
          children: [
            Text(widget.answer, style: TextStyle(fontSize: 13, color: aColor, height: 1.5)),
          ],
        ),
      ),
    );
  }
}

// ─── Raise Ticket Card ────────────────────────────────────────────────────────
class _TicketCard extends StatelessWidget {
  const _TicketCard();

  @override
  Widget build(BuildContext context) {
    final l10n     = AppLocalizations.of(context)!;
    final theme    = Theme.of(context);
    final isDark   = theme.brightness == Brightness.dark;
    final cardBg   = theme.cardColor;
    final inputBg  = theme.scaffoldBackgroundColor;
    final dividerColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : const Color(0xFFE5E7EB);
    final hintColor = theme.colorScheme.onSurface.withValues(alpha: 0.4);
    final green = theme.colorScheme.primary;
    final titleColor = theme.colorScheme.onSurface;
    final btnTxt = isDark ? const Color(0xFF0A0B0A) : Colors.white;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(16),
          boxShadow: isDark ? [] : [
            const BoxShadow(color: Color(0x05000000), blurRadius: 10, offset: Offset(0, 2))
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.support_raise_ticket,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: titleColor),
            ),
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                color: inputBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: dividerColor),
              ),
              child: TextField(
                maxLines: 4,
                style: TextStyle(color: titleColor),
                decoration: InputDecoration(
                  hintText: l10n.support_ticket_placeholder,
                  hintStyle: TextStyle(color: hintColor, fontSize: 14),
                  border: InputBorder.none,
                  fillColor: Colors.transparent,
                  filled: true,
                  contentPadding: const EdgeInsets.all(16),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.attach_file_rounded, color: green, size: 16),
                const SizedBox(width: 4),
                Text('Attach screenshot',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: green)),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        "Ticket submitted! We'll get back to you shortly.",
                        style: TextStyle(fontWeight: FontWeight.w700, color: btnTxt),
                      ),
                      backgroundColor: green,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      margin: const EdgeInsets.all(16),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: green,
                  foregroundColor: btnTxt,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                ),
                child: Text(l10n.support_submit,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: btnTxt)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
