import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/auth_provider.dart';
import '../services/settings_service.dart';
class ShiftMonitor extends StatefulWidget {
  final Widget child;
  const ShiftMonitor({super.key, required this.child});

  @override
  State<ShiftMonitor> createState() => _ShiftMonitorState();
}

// 1. Added WidgetsBindingObserver to catch background-to-foreground transitions instantly
class _ShiftMonitorState extends State<ShiftMonitor> with WidgetsBindingObserver {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Still run every minute while the app is actively open on the screen
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _checkShift());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  // 2. Triggers instantly when the tablet wakes up or the app comes back from the background
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkShift();
    }
  }

  Future<void> _checkShift() async {
    if (!mounted) return;
    final auth = context.read<AuthProvider>();
    final user = auth.user;

    final shiftSettings = context.read<SettingsService>().shiftSettings;
    if (user == null || user.isAdmin || user.role != 'operator') return;

    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();

    // 1. READ FROM CENTRALIZED SETTINGS INSTEAD OF PREFS!
    final mH = shiftSettings.morningEnd.hour;
    final mM = shiftSettings.morningEnd.minute;
    final nH = shiftSettings.nightEnd.hour;
    final nM = shiftSettings.nightEnd.minute;

    // The tablet's exact last active time remains in local prefs
    // because it is specific to this physical device.
    final lastActiveMs = prefs.getInt('last_active_time') ?? now.millisecondsSinceEpoch;
    final lastActive = DateTime.fromMillisecondsSinceEpoch(lastActiveMs);

    final todayMorning = DateTime(now.year, now.month, now.day, mH, mM);
    final todayNight = DateTime(now.year, now.month, now.day, nH, nM);
    final yesterdayNight = todayNight.subtract(const Duration(days: 1));

    DateTime lastPassedCutoff;
    if (now.isAfter(todayNight)) {
      lastPassedCutoff = todayNight;
    } else if (now.isAfter(todayMorning)) {
      lastPassedCutoff = todayMorning;
    } else {
      lastPassedCutoff = yesterdayNight;
    }

    if (lastActive.isBefore(lastPassedCutoff)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Shift ended. You have been automatically logged out.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 5),
          ),
        );
      }
      await auth.logout();
    } else {
      await prefs.setInt('last_active_time', now.millisecondsSinceEpoch);
    }
  }
  @override
  Widget build(BuildContext context) => widget.child;
}