import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../services/connectivity_service.dart';
import '../services/sync_service.dart';

class ConnectivityProvider extends ChangeNotifier {
  final ConnectivityService _connectivity;
  final SyncService _sync;

  bool _isOnline = true;
  bool _syncing = false;
  StreamSubscription<bool>? _sub;

  ConnectivityProvider(this._connectivity, this._sync);

  bool get isOnline => _isOnline;
  bool get syncing => _syncing;

  Future<void> init() async {
    _isOnline = await _connectivity.isOnline();
    notifyListeners();

    if (_isOnline) {
      debugPrint('[Connectivity] online at startup — triggering sync');
      _runSync();
    }

    _sub = _connectivity.onChanged.listen((online) {
      _isOnline = online;
      notifyListeners();
      if (online) {
        debugPrint('[Connectivity] back online — triggering sync');
        _runSync();
      } else {
        debugPrint('[Connectivity] went offline');
      }
    });
  }

  void triggerSync() => _runSync();

  Future<void> _runSync() async {
    if (_syncing) return;
    _syncing = true;
    notifyListeners();
    try {
      await _sync.syncPendingEntries();
      await _sync.pullFromFirestore();
    } finally {
      _syncing = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}