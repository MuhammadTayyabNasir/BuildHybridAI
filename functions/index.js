'use strict';

// PMA Cloud Functions (needs the Blaze plan).
//
// pushAlert      alerts/{id} created  -> FCM push to topic "managers".
// shiftEndCheck  every 30 min         -> missed scheduled readings become
//                                       alerts, so the manager is told even
//                                       if no phone opens the app.

const { initializeApp } = require('firebase-admin/app');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');
const { getMessaging } = require('firebase-admin/messaging');
const { onDocumentCreated } = require('firebase-functions/v2/firestore');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const { setGlobalOptions } = require('firebase-functions/v2');
const logger = require('firebase-functions/logger');
const { SECTIONS, DEFAULT_RULES, dueChecks, missingFor, alertDocId, describe } = require('./shift_check');

// Keep the region next to the Firestore database (set FUNCTION_REGION in
// functions/.env if the database is not in a US location).
setGlobalOptions({ region: process.env.FUNCTION_REGION || 'us-central1', maxInstances: 5 });

initializeApp();
const db = getFirestore();

const MANAGERS_TOPIC = 'managers';
const TZ_OFFSET_MINUTES = Number(process.env.FACTORY_UTC_OFFSET_MINUTES || 300); // Asia/Karachi
const WINDOW_MINUTES = 30;

exports.pushAlert = onDocumentCreated('alerts/{id}', async (event) => {
  const a = event.data && event.data.data();
  if (!a || a.notifyManager === false) return;
  const title = a.severity === 'critical' ? 'PMA alert'
    : a.severity === 'warning' ? 'PMA warning' : 'PMA reminder';
  await getMessaging().send({
    topic: MANAGERS_TOPIC,
    notification: { title, body: String(a.en || '').slice(0, 240) },
    data: {
      alertId: event.params.id,
      ruleId: String(a.ruleId || ''),
      severity: String(a.severity || 'info'),
      ur: String(a.ur || '').slice(0, 240),
    },
    android: { priority: 'high' },
  });
  await event.data.ref.update({ pushedAt: FieldValue.serverTimestamp() });
  logger.info('Pushed alert', event.params.id);
});

exports.shiftEndCheck = onSchedule(
  { schedule: 'every 30 minutes', timeZone: 'Asia/Karachi' },
  async () => {
    const settings = await db.collection('global_settings').doc('automations').get();
    const rules = settings.exists && Array.isArray(settings.get('rules'))
      ? settings.get('rules')
      : DEFAULT_RULES;
    const checks = dueChecks(rules, Date.now(), TZ_OFFSET_MINUTES, WINDOW_MINUTES);
    for (const { rule, dayStartUtc, dayKey } of checks) {
      const snap = await db.collection('temp_humidity')
        .where('date', '>=', dayStartUtc)
        .where('date', '<', dayStartUtc + 86400000)
        .get();
      const reports = snap.docs.map((d) => d.data());
      const sections = rule.sectionId ? [rule.sectionId] : SECTIONS;
      const miss = missingFor(reports, rule.shift, sections);
      if (miss.length === 0) continue;
      const key = `${rule.id}|${dayKey}`;
      try {
        // create() fails when a phone already raised the same alert.
        await db.collection('alerts').doc(alertDocId(key)).create({
          ruleId: rule.id,
          key,
          en: describe(rule, miss),
          ur: '',
          severity: 'warning',
          notifyManager: rule.notifyManager !== false,
          at: Date.now(),
          from: 'cloud-function',
          createdAt: FieldValue.serverTimestamp(),
        });
      } catch (e) {
        if (e.code !== 6) throw e; // 6 = ALREADY_EXISTS
      }
    }
  },
);
