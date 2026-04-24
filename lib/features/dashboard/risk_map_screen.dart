import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Full-screen 3D risk map powered by Deck.gl + H3 hexagons.
/// Uses CARTO dark basemap — zero API key required.
///
/// The map displays H3 resolution-8 hexagons for every Hustlr zone in
/// Chennai, extruded to a height proportional to the live risk score.
/// Red = Critical (81–100), Orange = High (61–80), Yellow = Moderate,
/// Green = Low.
class RiskMapScreen extends StatefulWidget {
  /// Optional live risk data to push into the map after load.
  /// List of { "name": "Adyar", "risk": 87, "claims": 12 }
  final List<Map<String, dynamic>>? liveRiskData;

  const RiskMapScreen({super.key, this.liveRiskData});

  @override
  State<RiskMapScreen> createState() => _RiskMapScreenState();
}

class _RiskMapScreenState extends State<RiskMapScreen> {
  late final WebViewController _controller;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF050A12))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) async {
            setState(() => _ready = true);
            // Push live data into the map if provided
            if (widget.liveRiskData != null) {
              _pushLiveData(widget.liveRiskData!);
            }
          },
        ),
      )
      ..loadFlutterAsset('assets/html/risk_map.html');
  }

  /// Calls window.updateRiskData(jsonString) inside the WebView.
  Future<void> _pushLiveData(List<Map<String, dynamic>> data) async {
    final json = jsonEncode(data);
    await _controller.runJavaScript(
      "window.updateRiskData(${jsonEncode(json)});",
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050A12),
      extendBodyBehindAppBar: true,
      appBar: _buildAppBar(context),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (!_ready) _buildLoader(),
          // Bottom live-stats strip
          if (_ready) _buildStatsStrip(context),
        ],
      ),
    );
  }

  AppBar _buildAppBar(BuildContext context) {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      leading: GestureDetector(
        onTap: () => Navigator.of(context).maybePop(),
        child: Container(
          margin: const EdgeInsets.only(left: 16, top: 8, bottom: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF050A12).withValues(alpha: 0.75),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF3FFF8B).withValues(alpha: 0.2)),
          ),
          child: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 20),
        ),
      ),
      actions: [
        // Refresh button
        GestureDetector(
          onTap: () => _controller.reload(),
          child: Container(
            width: 40, height: 40,
            margin: const EdgeInsets.only(right: 16, top: 8, bottom: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF050A12).withValues(alpha: 0.75),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF3FFF8B).withValues(alpha: 0.2)),
            ),
            child: const Icon(Icons.refresh_rounded, color: Color(0xFF3FFF8B), size: 18),
          ),
        ),
      ],
    );
  }

  Widget _buildLoader() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 32, height: 32,
            child: CircularProgressIndicator(
              color: Color(0xFF3FFF8B),
              strokeWidth: 2,
            ),
          ),
          SizedBox(height: 16),
          Text(
            'Rendering H3 hexagons…',
            style: TextStyle(
              color: Color(0xFF3FFF8B),
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsStrip(BuildContext context) {
    final stats = [
      ('13', 'Zones tracked'),
      ('87', 'Peak risk score'),
      ('84', 'Workers online'),
      ('H3 Res-8', '0.74 km² cells'),
    ];

    return Positioned(
      bottom: 0,
      left: 0, right: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFF050A12).withValues(alpha: 0.0),
              const Color(0xFF050A12).withValues(alpha: 0.9),
            ],
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: stats.map((s) => _StatChip(value: s.$1, label: s.$2)).toList(),
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String value;
  final String label;

  const _StatChip({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w900,
            color: Color(0xFF3FFF8B),
            height: 1.0,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w600,
            color: Colors.white.withValues(alpha: 0.5),
            letterSpacing: 0.3,
          ),
        ),
      ],
    );
  }
}
