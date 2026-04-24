import 'package:flutter/material.dart';



class TrustScoreCard extends StatelessWidget {

  final Map<String, dynamic>? trustProfile;



  const TrustScoreCard({super.key, this.trustProfile});



  @override

  Widget build(BuildContext context) {

    if (trustProfile == null) return const SizedBox.shrink();



    final theme = Theme.of(context);

    final isDark = theme.brightness == Brightness.dark;

    final cardColor = isDark ? const Color(0xFF1c1f1c) : Colors.white;



    final int score = (trustProfile?['score'] as num?)?.toInt() ?? 100;

    final List<dynamic> rawEvents = trustProfile?['events'] ?? [];

    

    // Tier Definitions

    String tierName = 'Full';

    Color barColor = const Color(0xFF43A047);

    String subtitle = "Full Shield — maximum coverage, priority support.";

    

    if (score <= 24) {

      tierName = 'Starter';

      barColor = Colors.grey;

      subtitle = "Keep completing shifts to build your trust score.";

    } else if (score <= 49) {

      tierName = 'Reliable';

      barColor = Colors.blue;

      subtitle = "You're building a strong record. Claims process faster.";

    } else if (score <= 74) {

      tierName = 'Trusted';

      barColor = const Color(0xFF00897B); // Teal

      subtitle = "You're eligible for claim-free cashback.";

    }



    return Container(

      width: double.infinity,

      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),

      padding: const EdgeInsets.all(24),

      decoration: BoxDecoration(

        color: cardColor,

        borderRadius: BorderRadius.circular(16),

        boxShadow: [

          BoxShadow(

            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),

            blurRadius: 20,

            offset: const Offset(0, 8),

          )

        ],

      ),

      child: Column(

        crossAxisAlignment: CrossAxisAlignment.start,

        children: [

          Row(

            mainAxisAlignment: MainAxisAlignment.spaceBetween,

            children: [

              Text(

                'Trust score',

                style: TextStyle(

                  color: theme.colorScheme.onSurface.withValues(alpha: 0.9),

                  fontSize: 16,

                  fontWeight: FontWeight.bold,

                  fontFamily: 'Manrope',

                ),

              ),

              Row(

                children: [

                  Text(

                    score.toString(),

                    style: TextStyle(

                      color: theme.colorScheme.onSurface,

                      fontSize: 24,

                      fontWeight: FontWeight.w900,

                      fontFamily: 'Manrope',

                    ),

                  ),

                  const SizedBox(width: 8),

                  Container(

                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),

                    decoration: BoxDecoration(

                      color: barColor.withValues(alpha: 0.15),

                      borderRadius: BorderRadius.circular(20),

                    ),

                    child: Text(

                      tierName,

                      style: TextStyle(

                        color: barColor,

                        fontSize: 12,

                        fontWeight: FontWeight.bold,

                      ),

                    ),

                  ),

                ],

              ),

            ],

          ),

          const SizedBox(height: 16),

          ClipRRect(

            borderRadius: BorderRadius.circular(4),

            child: LinearProgressIndicator(

              value: score / 100.0,

              backgroundColor: isDark ? const Color(0xFF2E332E) : const Color(0xFFECEFF1),

              valueColor: AlwaysStoppedAnimation<Color>(barColor),

              minHeight: 8,

            ),

          ),

          const SizedBox(height: 16),

          Text(

            subtitle,

            style: TextStyle(

              fontSize: 13,

              height: 1.4,

              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),

            ),

          ),

          const SizedBox(height: 16),

          _buildBullet(barColor, "Claims process instantly 24/7"),

          const SizedBox(height: 8),

          _buildBullet(barColor, "Premium cashback eligibility"),

          const SizedBox(height: 8),

          _buildBullet(barColor, "Skip the manual review queue"),

          const SizedBox(height: 20),

          SizedBox(

            width: double.infinity,

            child: OutlinedButton(

              onPressed: () => _showHistorySheet(context, rawEvents, isDark),

              style: OutlinedButton.styleFrom(

                side: BorderSide(color: theme.colorScheme.onSurface.withValues(alpha: 0.2)),

                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),

              ),

              child: const Text('View history', style: TextStyle(fontWeight: FontWeight.bold)),

            ),

          )

        ],

      ),

    );

  }



  Widget _buildBullet(Color color, String text) {

    return Row(

      crossAxisAlignment: CrossAxisAlignment.start,

      children: [

        Icon(Icons.check_circle_rounded, color: color, size: 16),

        const SizedBox(width: 8),

        Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),

      ],

    );

  }



  void _showHistorySheet(BuildContext context, List<dynamic> events, bool isDark) {

    final bg = isDark ? const Color(0xFF1c1f1c) : Colors.white;

    showModalBottomSheet(

      context: context,

      backgroundColor: bg,

      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),

      builder: (ctx) {

        return Padding(

          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),

          child: Column(

            mainAxisSize: MainAxisSize.min,

            crossAxisAlignment: CrossAxisAlignment.start,

            children: [

              Text('Score History', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),

              const SizedBox(height: 16),

              if (events.isEmpty)

                const Padding(

                  padding: EdgeInsets.symmetric(vertical: 24),

                  child: Center(child: Text('No events recorded yet')),

                ),

              ...events.map((e) {

                final adj = e['adjustment'] as int? ?? 0;

                final reason = e['reason'] as String? ?? 'Adjustment';

                final days = e['days_ago'] as int? ?? 0;

                final isPositive = adj > 0;

                

                return Padding(

                  padding: const EdgeInsets.only(bottom: 12),

                  child: Row(

                    children: [

                      Container(

                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),

                        decoration: BoxDecoration(

                          color: isPositive ? const Color(0xFF43A047).withValues(alpha: 0.1) : const Color(0xFFE53935).withValues(alpha: 0.1),

                          borderRadius: BorderRadius.circular(6),

                        ),

                        child: Text('${isPositive ? '+' : ''}$adj', 

                          style: TextStyle(color: isPositive ? const Color(0xFF43A047) : const Color(0xFFE53935), fontWeight: FontWeight.bold)),

                      ),

                      const SizedBox(width: 12),

                      Expanded(

                        child: Text(reason, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),

                      ),

                      Text('$days days ago', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5))),

                    ],

                  ),

                );

              }),

              const SizedBox(height: 24),

            ],

          ),

        );

      },

    );

  }

}

