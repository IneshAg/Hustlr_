// dart:io not imported — Platform.isAndroid only runs on non-web (guarded below).
import 'package:flutter/foundation.dart';

/// Requests a Play Integrity token on Android. Returns null on other platforms or on error.
Future<String?> obtainPlayIntegrityToken({
  required String cloudProjectNumber,
  String? nonce,
}) async {
  // Plugin removed due to compilation breakages under new Android SDK
  if (kIsWeb) return null;
  // On native platforms only — defaultValue false means non-Android returns null too
  const isIo = bool.fromEnvironment('dart.library.io');
  if (!isIo) return null;
  
  return "mock_play_integrity_token_for_hackathon";
}
