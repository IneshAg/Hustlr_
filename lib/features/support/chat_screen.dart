import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../l10n/app_localizations.dart';
import '../../core/secrets.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  static String get _geminiApiKey => Secrets.geminiApiKey;
  final TextEditingController _messageController = TextEditingController();

  bool _isTyping = false;

  static const _responses = {
    'claim': 'Claims are triggered automatically when disruptions hit official thresholds. Rain (>64.5mm), extreme heat (>43°C), air pollution (AQI >300), or platform outages all trigger payouts within minutes. You don\'t need to file anything—we monitor 24/7. If a local event was missed, you can file a manual claim from the app.',
    'payout': '💰 Here\'s how payouts work: 70% lands in your UPI instantly after the claim is verified. The remaining 30% follows within 48 hours. Total payout = (Trigger Probability × Average Daily Income × Exposed Days). No hidden charges, ever.',
    'rain': '🌧️ Heavy rain triggers automatic payouts when rainfall exceeds 64.5mm/hour in your zone (verified by IMD sensors). Standard Shield covers this. Full Shield adds additional rain-related coverage. If the alert was missed locally, you can report it manually.',
    'premium': '₹ Standard Shield costs ₹49/week. Full Shield is ₹79/week and includes additional perils. Your exact price depends on zone risk, platform uptime, and your claim history. Claim-free weeks earn you cheaper premiums. It\'s fair pricing.',
    'refund': 'We don\'t offer refunds, but here\'s the flip side: if your zone stays clear of disruptions for 4 consecutive weeks, you get 10% cashback (Full Shield). Plus, lower claim history = lower future premiums. You\'re rewarded for being safe.',
    'kyc': 'Your KYC was verified during onboarding using your delivery partner ID and a live selfie. This protects both you and the insurance pool from fraud. If you need to update your details, reach out to support.',
    'withdraw': '🏦 Super simple: Go to Wallet → tap Withdraw → enter your UPI ID. Transfers are instant and completely free. Money arrives in your bank within 2 hours via Razorpay. No minimum withdrawal amount.',
    'policy': 'Standard Shield (₹49/week) covers: Heavy rain, extreme heat, air pollution alerts, platform downtime, and bandh events. Full Shield (₹79/week) adds: Internet blackouts, dark store closures, and AQI >200 alerts. Upgrade anytime from Policy tab.',
    'zone': 'Your zone is auto-detected from your onboarding location. Disruptions are verified zone-specifically using live data from IMD (rain/heat), CPCB (air quality), and platform APIs (outages). Each zone has independent thresholds.',
    'heat': '🌡️ Extreme heat payouts trigger when your zone temperature exceeds 43°C (IMD verified) and stays that high for 2+ hours during your active delivery shifts. You must be logged in to the platform when the alert triggers.',
    'aqi': '😷 Air quality payouts trigger when AQI exceeds 300 (Hazardous level) as measured by CPCB sensors within 10km of your delivery zone. This protects you from pollution-related income loss.',
    'fraud': 'We take fraud seriously. We use Google Cloud Vision for facial liveness checks + phone sensor data (accelerometer patterns) to verify real delivery conditions. Suspicious claims get flagged for manual review. Fair system, built on trust.',
    'tracking': '📍 Your location is tracked in the background during active shifts. This proves you were in the disruption zone when it happened. Some phones with aggressive battery policies may pause tracking unless you optimize app permissions in settings.',
    'camera': '📸 If an automatic trigger is missed (rare but happens), you can file a manual claim. The app auto-opens your selfie camera. Live photos with timestamp + EXIF data prevent fraud. No gallery uploads allowed.',
    'ml': '🤖 Our backend uses Isolation Forest to detect anomalies in your phone\'s motion data, combined with your claim history patterns, to calculate fraud risk. The AI learns but never profiles unfairly—it\'s just pattern recognition.',
    'default': '👋 Hi! I\'m here to help with your Hustlr insurance. You can ask me about:\n• Claims & payouts\n• Premiums & coverage\n• Rain, heat, AQI, outages\n• Manual claims & withdrawals\n• Fraud prevention\n• Zone coverage\n\nWhat can I help you with?',
  };

  String _getAutoReply(String message) {
    final m = message.toLowerCase();
    if (m.contains('claim') || m.contains('status') || m.contains('filed') || m.contains('trigger')) return _responses['claim']!;
    if (m.contains('withdraw') || m.contains('upi') || m.contains('transfer') || m.contains('money out')) return _responses['withdraw']!;
    if (m.contains('payout') || m.contains('money') || m.contains('pay') || m.contains('payment')) return _responses['payout']!;
    if (m.contains('rain') || m.contains('flood') || m.contains('water') || m.contains('wet')) return _responses['rain']!;
    if (m.contains('premium') || m.contains('cost') || m.contains('price') || m.contains('49') || m.contains('fee')) return _responses['premium']!;
    if (m.contains('refund') || m.contains('cancel') || m.contains('return')) return _responses['refund']!;
    if (m.contains('kyc') || m.contains('identity') || m.contains('verify') || m.contains('document')) return _responses['kyc']!;
    if (m.contains('full shield') || m.contains('upgrade') || m.contains('79') || m.contains('better coverage')) return '🛡️ Full Shield (₹79/week) has everything Standard Shield offers, PLUS:\n• Internet blackouts\n• Dark store closures\n• Low AQI alerts (>200)\n• Bandh & curfew events\n\n10% cashback after 4 claim-free weeks! Upgrade from Policy tab.';
    if (m.contains('policy') || m.contains('plan') || m.contains('coverage') || m.contains('shield') || m.contains('what do')) return _responses['policy']!;
    if (m.contains('zone') || m.contains('location') || m.contains('area') || m.contains('place')) return _responses['zone']!;
    if (m.contains('heat') || m.contains('temperature') || m.contains('hot') || m.contains('degree')) return _responses['heat']!;
    if (m.contains('aqi') || m.contains('air') || m.contains('pollution') || m.contains('quality')) return _responses['aqi']!;
    if (m.contains('fraud') || m.contains('fake') || m.contains('liveness') || m.contains('vision') || m.contains('cheat')) return _responses['fraud']!;
    if (m.contains('track') || m.contains('gps') || m.contains('background') || m.contains('foreground') || m.contains('location')) return _responses['tracking']!;
    if (m.contains('camera') || m.contains('photo') || m.contains('picture') || m.contains('evidence')) return _responses['camera']!;
    if (m.contains('ml') || m.contains('machine learning') || m.contains('ai') || m.contains('model') || m.contains('algorithm')) return _responses['ml']!;
    return _responses['default']!;
  }

  final ScrollController _scrollController = ScrollController();

  Future<String> _queryGemini(String prompt) async {
    if (_geminiApiKey.isEmpty) return _getAutoReply(prompt);
    final url = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=$_geminiApiKey',
    );
    
    final contents = [
      {
         "role": "user",
         "parts": [{"text": "Hello, I am the Hustlr automated support bot. I help gig workers with parametric insurance claims, payouts, and coverage."}]
      },
      {
         "role": "model",
         "parts": [{"text": "Hello! I am ready to help you with your Hustlr insurance questions."}]
      }
    ];

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          "systemInstruction": {
            "parts": [{"text": "You are a customer support agent for Hustlr, a parametric insurance app for gig workers. Be concise, polite, and helpful. Default language is English. Answer their questions regarding app features, insurance, rain/heat/AQI triggers, wallet payouts."}]
          },
          "contents": [
            ...contents,
            {
              "role": "user",
              "parts": [{"text": prompt}]
            }
          ]
        }),
      );
      
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        return json['candidates'][0]['content']['parts'][0]['text']?.toString().trim() ?? _getAutoReply(prompt);
      }
      return _getAutoReply(prompt);
    } catch(e) {
      return _getAutoReply(prompt);
    }
  }

  void _sendMessage() {
    if (_messageController.text.trim().isEmpty) return;
    final userText = _messageController.text.trim();
    setState(() {
      _messages.add({'isUser': true, 'text': userText, 'time': 'Just now'});
      _messageController.clear();
      _isTyping = true;
    });
    _scrollToBottom();

    Future.delayed(const Duration(milliseconds: 100), () async {
      if (!mounted) return;
      final replyMsg = await _queryGemini(userText);
      
      if (!mounted) return;
      setState(() {
        _isTyping = false;
        _messages.add({
          'isUser': false,
          'text': replyMsg,
          'time': 'Just now',
        });
      });
      _scrollToBottom();
    });
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  final List<Map<String, dynamic>> _messages = [];
  bool _isInit = false;

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;
    final l10n = AppLocalizations.of(context)!;

    if (!_isInit) {
      _messages.add({
        'isUser': false,
        'text': l10n.chat_bot_greeting,
        'time': 'Just now',
      });
      _isInit = true;
    }

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: Text(
          l10n.chat_live_support,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: theme.colorScheme.onSurface,
            letterSpacing: -0.5,
          ),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: theme.colorScheme.onSurface),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.close_rounded, color: theme.colorScheme.onSurface),
            onPressed: () => context.pop(),
          )
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              itemCount: _messages.length + (_isTyping ? 1 : 0),
              itemBuilder: (context, index) {
                if (_isTyping && index == _messages.length) {
                  return _buildTypingIndicator(theme, primaryColor);
                }
                final msg = _messages[index];
                return _buildChatBubble(msg['text'], msg['time'], msg['isUser'], theme, primaryColor);
              },
            ),
          ),
          Flexible(
            flex: 0,
            child: SingleChildScrollView(
              child: _buildInputSection(theme, primaryColor, isDark, l10n),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatBubble(String text, String time, bool isUser, ThemeData theme, Color primaryColor) {
    final bubbleColor = isUser ? theme.cardColor : primaryColor;
    final textColor = isUser ? theme.colorScheme.onSurface : Colors.black;

    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) ...[
            CircleAvatar(
              radius: 18,
              backgroundColor: theme.cardColor,
              child: const Icon(Icons.support_agent_rounded, size: 20),
            ),
            const SizedBox(width: 12),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: bubbleColor,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(24),
                  topRight: const Radius.circular(24),
                  bottomLeft: isUser ? const Radius.circular(24) : const Radius.circular(4),
                  bottomRight: isUser ? const Radius.circular(4) : const Radius.circular(24),
                ),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4)),
                ],
              ),
              child: Text(
                text,
                style: TextStyle(
                  color: textColor,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            time,
            style: TextStyle(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: 12),
            CircleAvatar(
              radius: 18,
              backgroundColor: primaryColor.withValues(alpha: 0.2),
              child: Icon(Icons.person_outline_rounded, size: 20, color: primaryColor),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTypingIndicator(ThemeData theme, Color primaryColor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: theme.cardColor,
            child: const Icon(Icons.support_agent_rounded, size: 20),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: primaryColor,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(24),
                topRight: Radius.circular(24),
                bottomRight: Radius.circular(24),
                bottomLeft: Radius.circular(4),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _Dot(delay: 0),
                const SizedBox(width: 4),
                _Dot(delay: 200),
                const SizedBox(width: 4),
                _Dot(delay: 400),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputSection(ThemeData theme, Color primaryColor, bool isDark, AppLocalizations l10n) {
    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(32),
          topRight: Radius.circular(32),
        ),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 20, offset: const Offset(0, -5)),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 56,
                    decoration: BoxDecoration(
                      border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.1)),
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: Row(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Icon(Icons.emoji_emotions_outlined, color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
                        ),
                        Expanded(
                          child: TextField(
                            controller: _messageController,
                            style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.w600),
                            decoration: InputDecoration(
                              hintText: l10n.chat_hint,
                              hintStyle: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.4), fontWeight: FontWeight.w600),
                              border: InputBorder.none,
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Icon(Icons.mic_none_rounded, color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                InkWell(
                  onTap: _sendMessage,
                  borderRadius: BorderRadius.circular(28),
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: isDark ? theme.colorScheme.surface : primaryColor,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.send_rounded, color: isDark ? primaryColor : Colors.white, size: 24),
                  ),
                ),
              ],
            ),
          ),
          // Quick action chips — Hustlr relevant
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _buildQuickChip(Icons.receipt_long_rounded,   'Check my claim',     'What is the status of my claim?',              true,  theme, primaryColor),
                _buildQuickChip(Icons.water_drop_rounded,     'Rain payout',        'How does the rain payout work?',               false, theme, primaryColor),
                _buildQuickChip(Icons.location_on_rounded,    'My zone',            'Tell me about my zone coverage.',              false, theme, primaryColor),
                _buildQuickChip(Icons.currency_rupee_rounded, 'My premium',         'Why is my premium ₹49?',                       false, theme, primaryColor),
                _buildQuickChip(Icons.account_balance_wallet_rounded, 'Withdraw',   'How do I withdraw my payout balance to UPI?',  false, theme, primaryColor),
                _buildQuickChip(Icons.memory_rounded,         'ML Models',          'How does your ML tracking detect fraud?',      false, theme, primaryColor),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _sendPreset(String message) {
    setState(() {
      _messages.add({'isUser': true, 'text': message, 'time': 'Just now'});
      _isTyping = true;
    });
    _scrollToBottom();
    Future.delayed(const Duration(milliseconds: 100), () async {
      if (!mounted) return;
      final replyMsg = await _queryGemini(message);
      if (!mounted) return;
      setState(() {
        _isTyping = false;
        _messages.add({'isUser': false, 'text': replyMsg, 'time': 'Just now'});
      });
      _scrollToBottom();
    });
  }

  Widget _buildQuickChip(IconData icon, String label, String presetMessage, bool isFilled, ThemeData theme, Color primaryColor) {
    final isDark = theme.brightness == Brightness.dark;
    final filledBg = isDark ? const Color(0xFF1c1f1c) : primaryColor;
    final emptyBg  = isDark ? const Color(0xFF1c1f1c).withValues(alpha: 0.4) : theme.scaffoldBackgroundColor;
    final borderCol = isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.08);

    return GestureDetector(
      onTap: () => _sendPreset(presetMessage),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isFilled ? filledBg : emptyBg,
          borderRadius: BorderRadius.circular(24),
          border: isFilled ? null : Border.all(color: borderCol),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16,
              color: isFilled ? (isDark ? primaryColor : Colors.white) : theme.colorScheme.onSurface.withValues(alpha: 0.7)),
            const SizedBox(width: 6),
            Text(label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: isFilled ? Colors.white : theme.colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Animated bouncing dot for typing indicator
class _Dot extends StatefulWidget {
  final int delay;
  const _Dot({required this.delay});
  @override
  State<_Dot> createState() => _DotState();
}

class _DotState extends State<_Dot> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600))
      ..repeat(reverse: true);
    _anim = Tween(begin: 0.0, end: -6.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: Interval(widget.delay / 800, 1.0, curve: Curves.easeInOut),
      ),
    );
    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Transform.translate(
        offset: Offset(0, _anim.value),
        child: Container(
          width: 8, height: 8,
          decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
        ),
      ),
    );
  }
}
