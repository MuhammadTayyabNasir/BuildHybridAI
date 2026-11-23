import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/th_threshold_model.dart';

class ThThresholdService {
  static const _collection = 'th_thresholds';
  static const _cacheKeyPrefix = 'th_threshold_cache_';

  final FirebaseFirestore _db = FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'remoxindatabase');

  final ValueNotifier<Map<String, ThThreshold>> current =
  ValueNotifier<Map<String, ThThreshold>>({});

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;

  Future<void> init() async {
    await _loadFromCache();

    // Native gRPC real-time listener (works seamlessly on Mobile & Windows)
    _sub ??= _db.collection(_collection).snapshots().listen((snap) {
      final map = Map<String, ThThreshold>.from(current.value);
      for (final doc in snap.docs) {
        map[doc.id] = ThThreshold.fromMap(doc.id, doc.data());
      }
      current.value = map;
      _saveToCache(map);
    }, onError: (e) {
      debugPrint('[ThThresholdService] Offline or permission error: $e');
    });
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
  }

  ThThreshold forSection(String sectionId) =>
      current.value[sectionId] ?? ThThreshold.defaults(sectionId);

  Future<void> save(ThThreshold threshold, {required String updatedBy}) async {
    await _db
        .collection(_collection)
        .doc(threshold.sectionId)
        .set(threshold.toMap(by: updatedBy), SetOptions(merge: true));

    final map = Map<String, ThThreshold>.from(current.value);
    map[threshold.sectionId] = threshold;
    current.value = map;
    await _saveToCache(map);
  }

  Future<void> _loadFromCache() async {
    final prefs = await SharedPreferences.getInstance();
    final map = <String, ThThreshold>{};
    for (final key in prefs.getKeys()) {
      if (!key.startsWith(_cacheKeyPrefix)) continue;
      final sectionId = key.substring(_cacheKeyPrefix.length);
      final raw = prefs.getString(key);
      if (raw == null) continue;
      try {
        map[sectionId] =
            ThThreshold.fromMap(sectionId, jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {}
    }
    current.value = map;
  }

  Future<void> _saveToCache(Map<String, ThThreshold> map) async {
    final prefs = await SharedPreferences.getInstance();
    for (final entry in map.entries) {
      final data = {
        'tempGreenMax': entry.value.tempGreenMax,
        'humGreenMax': entry.value.humGreenMax,
      };
      await prefs.setString('$_cacheKeyPrefix${entry.key}', jsonEncode(data));
    }
  }
}