import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'automation_engine.dart';
import 'automation_rule.dart';

/// Firestore + FCM side of automations.
///
/// * The phone writes fired manager alerts to `alerts/{key}` (the dedupe key
///   is the document id, so a retried send never pushes twice).
/// * Cloud Function `pushAlert` (see /functions) sends each new alert to the
///   FCM topic `managers`.
/// * Admin rules are mirrored to `global_settings/automations`, so the
///   scheduled Cloud Function `shiftEndCheck` can check missed readings even
///   when nobody opens the app.
class AutomationCloud {
  AutomationCloud({FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;
  static const managersTopic = 'managers';

  static String docId(String key) =>
      key.replaceAll(RegExp(r'[^A-Za-z0-9_\-|.]'), '_').replaceAll('|', '__');

  Future<void> sendAlert(AutomationEvent e, {required String from}) =>
      _db.collection('alerts').doc(docId(e.key)).set({
        ...e.toMap(),
        'from': from,
        'createdAt': FieldValue.serverTimestamp(),
      });

  Future<void> publishRules(List<AutomationRule> rules, {required String by}) =>
      _db.collection('global_settings').doc('automations').set({
        'rules': [for (final r in rules) r.toMap()],
        'updatedBy': by,
        'updatedAt': FieldValue.serverTimestamp(),
      });

  /// Managers / admins receive pushes. Operators unsubscribe so a shared
  /// phone stops getting manager alerts after the manager signs out.
  static Future<void> configurePush({required bool manager}) async {
    if (kIsWeb) return; // Web push needs a service worker; not set up yet.
    try {
      final fcm = FirebaseMessaging.instance;
      if (manager) {
        await fcm.requestPermission();
        await fcm.subscribeToTopic(managersTopic);
      } else {
        await fcm.unsubscribeFromTopic(managersTopic);
      }
    } catch (e) {
      debugPrint('FCM not available: $e');
    }
  }
}
