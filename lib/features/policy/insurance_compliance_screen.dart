import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class InsuranceComplianceScreen extends StatelessWidget {
  const InsuranceComplianceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0a0b0a) : const Color(0xFFFFFFFF);
    final text = isDark ? Colors.white : const Color(0xFF111827);
    final subtext = isDark ? Colors.white70 : const Color(0xFF6B7280);
    final green = isDark ? const Color(0xFF3FFF8B) : const Color(0xFF16A34A);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.close_rounded, color: text),
          onPressed: () => context.pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 48),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.verified_user_rounded, color: green, size: 40),
            const SizedBox(height: 16),
            Text(
              'Regulatory & Data Disclosure',
              style: TextStyle(color: text, fontWeight: FontWeight.w800, fontSize: 28, height: 1.2),
            ),
            const SizedBox(height: 8),
            Text(
              'Hustlr strictly adheres to IRDAI guidelines for parametric insurance and the DPDP Act 2023.',
              style: TextStyle(color: subtext, fontSize: 16, height: 1.5),
            ),
            const SizedBox(height: 32),

            _buildSection(
              title: 'What we track (and why)',
              text: 'We only monitor active delivery zones via background GPS during your shift. Bank accounts and UPI identifiers are exclusively stored for autonomous claim disbursement over verified network events (AQI data, rainfall thresholds).',
              textCol: text,
              subtextCol: subtext,
            ),

            _buildSection(
              title: 'Social Security Code (2020)',
              text: 'By tracking your engagement timeline natively, Hustlr automatically verifies your eligibility for independent worker benefits, ensuring continuity without manual documentation.',
              textCol: text,
              subtextCol: subtext,
            ),

            _buildSection(
              title: 'Automated Payouts (Parametric)',
              text: 'Policies function on triggers (e.g., 3+ hours of active rainfall or platform outages). Zero human interference prevents systemic bias. Pricing directly scales based on historical zone risk.',
              textCol: text,
              subtextCol: subtext,
            ),

            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1F2937) : const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded, color: subtext, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'By continuing, you agree to Hustlr\'s fully anonymized data pooling and the terms governed by the Insurance Regulatory and Development Authority of India.',
                      style: TextStyle(color: subtext, fontSize: 12, height: 1.5),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required String text,
    required Color textCol,
    required Color subtextCol,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(color: textCol, fontWeight: FontWeight.bold, fontSize: 18),
          ),
          const SizedBox(height: 8),
          Text(
            text,
            style: TextStyle(color: subtextCol, fontSize: 14, height: 1.6),
          ),
        ],
      ),
    );
  }
}
