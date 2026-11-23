import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

class ShiftSettings {
  final TimeOfDay morningEnd;
  final TimeOfDay nightEnd;

  ShiftSettings({required this.morningEnd, required this.nightEnd});

  factory ShiftSettings.defaults() => ShiftSettings(
    morningEnd: const TimeOfDay(hour: 8, minute: 0),
    nightEnd: const TimeOfDay(hour: 20, minute: 0),
  );
}

class SettingsService extends ChangeNotifier {
  final FirebaseFirestore _db = FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'remoxindatabase');
  StreamSubscription? _sub;
  ShiftSettings _shiftSettings = ShiftSettings.defaults();

  ShiftSettings get shiftSettings => _shiftSettings;

  void startListening() {
    _sub?.cancel();
    _sub = _db.collection('global_settings').doc('shifts').snapshots().listen((snap) {
      if (snap.exists && snap.data() != null) {
        final data = snap.data()!;
        _shiftSettings = ShiftSettings(
          morningEnd: TimeOfDay(hour: data['morning_h'] ?? 8, minute: data['morning_m'] ?? 0),
          nightEnd: TimeOfDay(hour: data['night_h'] ?? 20, minute: data['night_m'] ?? 0),
        );
        notifyListeners();
      }
    });
  }

  void stopListening() {
    _sub?.cancel();
    _sub = null;
  }

  Future<void> updateShiftTimes(TimeOfDay morning, TimeOfDay night) async {
    await _db.collection('global_settings').doc('shifts').set({
      'morning_h': morning.hour,
      'morning_m': morning.minute,
      'night_h': night.hour,
      'night_m': night.minute,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}