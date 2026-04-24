import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:app_settings/app_settings.dart';

/// Shown before the worker can tap "Go Online".
/// Gates shift start behind two mandatory checks:
/// 1. Location permission = Always Allow
/// 2. Battery optimization = Unrestricted (not "Optimized")
///
/// Mirrors the UX pattern used by Rapido / Ola Driver apps.
class BatteryOptimizationPrompt extends StatefulWidget {
  final VoidCallback onAllGranted;
  const BatteryOptimizationPrompt({super.key, required this.onAllGranted});

  @override
  State<BatteryOptimizationPrompt> createState() =>
      _BatteryOptimizationPromptState();
}

class _BatteryOptimizationPromptState
    extends State<BatteryOptimizationPrompt> with WidgetsBindingObserver {
  bool _locationAlways = false;
  bool _locationForegroundOnly = false;  // soft pass: while-using-app grants foreground only
  bool _batteryUnrestricted = false;
  bool _batteryManuallyVerified = false;
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkAll();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkAll();
  }

  Future<void> _checkAll() async {
    setState(() => _checking = true);

    // Skip permission checks on web - not supported
    if (kIsWeb) {
      setState(() {
        _locationAlways = true;
        _locationForegroundOnly = false;
        _batteryUnrestricted = true;
        _checking = false;
      });
      return;
    }

    final locAlwaysStatus = await Permission.locationAlways.status;
    final locFgStatus = await Permission.location.status;
    final batteryStatus = await Permission.ignoreBatteryOptimizations.status;

    final locationAlways = locAlwaysStatus == PermissionStatus.granted;
    // Soft pass: foreground-only is acceptable — worker can go online with a warning
    final locationForeground = locFgStatus == PermissionStatus.granted || locationAlways;
    final batteryGranted = batteryStatus == PermissionStatus.granted;
    // OEM workaround: OnePlus / Xiaomi ROMs silently revert == denied even after user taps Allow.
    // _batteryManuallyVerified is set to true the moment the user returns from battery settings.
    final batteryUnrestricted = batteryGranted || _batteryManuallyVerified;

    if (mounted) {
      setState(() {
        _locationAlways = locationAlways;
        _locationForegroundOnly = locationForeground && !locationAlways;
        _batteryUnrestricted = batteryUnrestricted;
        _checking = false;
      });
    }
  }

  Future<void> _requestLocation() async {
    // Android 11+ requires foreground location granted before requesting background.
    var status = await Permission.location.request();
    if (status == PermissionStatus.granted) {
      // Try to upgrade to Always Allow (background)
      status = await Permission.locationAlways.request();
    }
    if (status == PermissionStatus.permanentlyDenied) {
      // Deep-link directly to THIS app's location settings (not generic settings)
      await AppSettings.openAppSettings(type: AppSettingsType.location);
    }
    _checkAll();
  }

  Future<void> _requestBattery() async {
    // First try the direct OS dialog
    final status = await Permission.ignoreBatteryOptimizations.request();
    if (status != PermissionStatus.granted) {
      // Deep-link to battery optimization settings page if request failed
      await AppSettings.openAppSettings(type: AppSettingsType.batteryOptimization);
    }
    // Vendor OS workaround: Android 11/12 on many OEM ROMs (Xiaomi, OnePlus, Samsung)
    // incorrectly returns PermissionStatus.denied even AFTER the user enables Unrestricted.
    // We mark it as manually verified once they return from settings to unblock the gate.
    _batteryManuallyVerified = true;
    _checkAll();
  }
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryGreen = theme.colorScheme.primary;

    if (_checking) {
      return SizedBox(
        height: 56,
        child: Center(
          child: SizedBox(
            width: 24, height: 24, 
            child: CircularProgressIndicator(color: primaryGreen, strokeWidth: 2)
          )
        ),
      );
    }

    // Strict requirements: Always Allow location and Unrestricted battery
    final allGranted = _locationAlways && _batteryUnrestricted;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      width: double.infinity,
      height: 56,
      child: ElevatedButton.icon(
        onPressed: () async {
          if (allGranted) {
            widget.onAllGranted();
          } else {
            // One-click sequential permission request
            if (!_locationAlways) {
              await _requestLocation();
            }
            if (!_batteryUnrestricted) {
              await _requestBattery();
            }
            
            await _checkAll();
            
            if (mounted && _locationAlways && _batteryUnrestricted) {
              widget.onAllGranted();
            } else if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('Please grant all required permissions to go online.'),
                  backgroundColor: theme.colorScheme.error,
                ),
              );
            }
          }
        },
        icon: Icon(allGranted ? Icons.power_settings_new_rounded : Icons.shield_outlined),
        label: Text(
          allGranted ? 'GO ONLINE' : 'Enable Protection to Go Online',
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 15,
            letterSpacing: 0.3,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: allGranted ? primaryGreen : const Color(0xFFE88A00),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: allGranted ? 0 : 2,
          shadowColor: allGranted ? Colors.transparent : const Color(0xFFE88A00).withValues(alpha: 0.35),
        ),
      ),
    );
  }
}
