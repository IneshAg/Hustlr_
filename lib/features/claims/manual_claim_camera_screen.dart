import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../l10n/app_localizations.dart';
import '../../shared/widgets/primary_button.dart';

class ManualClaimCameraScreen extends StatefulWidget {
  final String disruptionType;
  const ManualClaimCameraScreen({super.key, required this.disruptionType});

  @override
  State<ManualClaimCameraScreen> createState() => _ManualClaimCameraScreenState();
}

class _ManualClaimCameraScreenState extends State<ManualClaimCameraScreen> {
  final ImagePicker _picker = ImagePicker();

  // We are taking evidence photos, so no selfie intro needed.
  bool _showSelfieIntro = false;

  @override
  void initState() {
    super.initState();

    if (widget.disruptionType == 'internet_outage') {
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          context.pushReplacement('/claims/evidence/review', extra: {
            'disruptionType': widget.disruptionType,
            'images': const [],
            'signalStrength': 1,
          });
        }
      });
      return;
    }

    if (kIsWeb) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _capturePhoto());
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _capturePhoto());
    }
  }

  Future<void> _capturePhoto() async {
    try {
      final XFile? photo = await _picker.pickImage(
        source: kIsWeb ? ImageSource.gallery : ImageSource.camera,
        preferredCameraDevice: CameraDevice.rear,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 88,
      );
      if (photo != null && mounted) {
        context.pushReplacement('/claims/evidence/review', extra: {
          'disruptionType': widget.disruptionType,
          'images': [photo],
        });
      } else if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
    }
  }

  void _onOpenSelfieCamera() {
    setState(() => _showSelfieIntro = false);
    _capturePhoto();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    final l10n = AppLocalizations.of(context)!;

    if (widget.disruptionType == 'internet_outage') {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.wifi_off_rounded, color: primaryColor, size: 64),
              const SizedBox(height: 24),
              Text(l10n.camera_internet_auto, style: const TextStyle(color: Colors.white, fontSize: 16)),
              const SizedBox(height: 8),
              Text(l10n.camera_no_photo, style: TextStyle(color: Colors.white.withValues(alpha: 0.5))),
            ],
          ),
        ),
      );
    }

    if (kIsWeb) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(color: primaryColor),
        ),
      );
    }

    if (_showSelfieIntro) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 24),
                Icon(Icons.camera_front_outlined, color: primaryColor, size: 56),
                const SizedBox(height: 24),
                Text(
                  l10n.claim_camera_selfie_title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'Manrope',
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.claim_camera_selfie_body,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.72),
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  l10n.step_up_face_ml_notice,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.amber.shade200,
                    fontSize: 12,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.claim_camera_selfie_hint,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.45),
                    fontSize: 12,
                  ),
                ),
                const Spacer(),
                PrimaryButton(
                  text: l10n.claim_camera_selfie_cta,
                  onPressed: _onOpenSelfieCamera,
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: CircularProgressIndicator(color: primaryColor),
      ),
    );
  }
}
