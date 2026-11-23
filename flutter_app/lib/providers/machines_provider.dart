import '../core/constants/firebase_config.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import '../models/machine_model.dart';
import '../services/firestore_service.dart';
import '../services/local_storage_service.dart';

class MachinesProvider extends ChangeNotifier {
  final FirestoreService _firestore;
  final LocalStorageService _local;

  final Map<String, List<MachineModel>> _cache = {};
  bool _loading = false;
  StreamSubscription? _sub;

  MachinesProvider(this._firestore, this._local);

  bool get loading => _loading;

  List<MachineModel> forSection(String section) => _cache[section] ?? [];

  List<MachineModel> get allMachines {
    final out = <MachineModel>[];
    for (final list in _cache.values) {
      out.addAll(list);
    }
    return out;
  }

  // ── gRPC Real-Time Listener ────────────────────────────────────────────────
  void startListening() {
    _sub?.cancel();
    _sub = FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: FirebaseConfig.databaseId).collection('machines').snapshots().listen((snap) async {
      final machines = snap.docs.map((d) => MachineModel.fromMap(d.data(), d.id)).toList();

      _cache.clear();
      for (final m in machines) {
        _cache.putIfAbsent(m.section, () => []).add(m);
      }

      await _local.saveMachines(machines);

      _loading = false;
      notifyListeners();
    }, onError: (e) {
      debugPrint('[MachinesProvider] Snapshot listener error: $e');
    });
  }

  void stopListening() {
    _sub?.cancel();
    _sub = null;
  }
  // ───────────────────────────────────────────────────────────────────────────

  void reloadFromLocal() {
    final cached = _local.getMachines();
    _cache.clear();
    for (final m in cached) {
      _cache.putIfAbsent(m.section, () => []).add(m);
    }
    _loading = false;
    notifyListeners();
  }

  Future<void> loadSection(String section) async {
    if (_cache[section] == null) {
      final local = _local.getMachines().where((m) => m.section == section).toList();
      if (local.isNotEmpty) {
        _cache[section] = local;
        notifyListeners();
      } else {
        _loading = true;
        notifyListeners();
      }
    }
  }

  Future<void> loadAll() async {
    final cached = _local.getMachines();
    if (cached.isNotEmpty) {
      _cache.clear();
      for (final m in cached) {
        _cache.putIfAbsent(m.section, () => []).add(m);
      }
      notifyListeners();
    } else {
      _loading = true;
      notifyListeners();
    }
  }

  Future<String?> save(MachineModel machine) async {
    try {
      await _firestore.saveMachine(machine);
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  Future<String?> delete(MachineModel machine) async {
    try {
      await _firestore.deleteMachine(machine.id);
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}