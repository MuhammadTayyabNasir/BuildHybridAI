import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../assistant/app_assistant_store.dart';
import '../assistant/assistant_service.dart';
import '../providers/auth_provider.dart';
import '../providers/connectivity_provider.dart';
import '../services/firestore_service.dart';
import '../services/local_storage_service.dart';
import '../services/th_threshold_service.dart';
import '../ui/pma_ui.dart';
import 'automation_cloud.dart';
import 'automation_engine.dart';
import 'automation_service.dart';
import '../assistant/hybrid_ai_factory.dart';

/// Creates the [AutomationService] for the signed-in user, runs it while the
/// home screens are open, shows fired events as banners and registers the
/// manager's phone for FCM pushes.
class AutomationHost extends StatefulWidget {
  const AutomationHost({super.key, required this.child});
  final Widget child;

  @override
  State<AutomationHost> createState() => _AutomationHostState();
}

class _AutomationHostState extends State<AutomationHost> with WidgetsBindingObserver {
  late final AutomationService _service;
  final _cloud = AutomationCloud();

  @override
  void initState() {
    super.initState();
    final local = context.read<LocalStorageService>();
    final thresholds = context.read<ThThresholdService>();
    final auth = context.read<AuthProvider>();
    final connectivity = context.read<ConnectivityProvider>();
    final user = auth.user;
    final assistant = AssistantService(
      ai: createHybridAi(),
      isOnline: () async => connectivity.isOnline,
      store: AppAssistantStore(
        local: local,
        firestore: context.read<FirestoreService>(),
        thresholds: thresholds,
        isOnline: () => connectivity.isOnline,
        userId: user?.id ?? '',
        userName: user?.username ?? '',
      ),
    );
    _service = AutomationService(
      readMeta: local.getMeta,
      writeMeta: local.setMeta,
      reports: local.getTempHumidityReports,
      threshold: thresholds.forSection,
      missing: (day) => assistant.missingReadings(day),
      isOnline: () => connectivity.isOnline,
      sendAlert: (e) => _cloud.sendAlert(e, from: user?.username ?? ''),
      publishRules: auth.isAdmin
          ? (rules) => _cloud.publishRules(rules, by: user?.username ?? '')
          : null,
    )..onEvent = _show;
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _service.start());
    AutomationCloud.configurePush(manager: _isManager(user?.role));
  }

  static bool _isManager(String? role) {
    final r = (role ?? '').toLowerCase();
    return r == 'admin' || r == 'manager';
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _service.tick();
  }

  void _show(AutomationEvent e) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: switch (e.severity) {
        'critical' => Pma.bad,
        'warning' => Pma.ember,
        _ => Pma.ink,
      },
      duration: const Duration(seconds: 6),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(e.en, style: const TextStyle(fontWeight: FontWeight.w600)),
          Text(e.ur, textDirection: TextDirection.rtl),
        ],
      ),
    ));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _service.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      ChangeNotifierProvider<AutomationService>.value(value: _service, child: widget.child);
}
