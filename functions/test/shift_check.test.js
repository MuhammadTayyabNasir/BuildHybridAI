'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { dueChecks, missingFor, alertDocId } = require('../shift_check');

const PKT = 300;
// 2026-11-24 19:40 PKT == 14:40 UTC
const now = Date.UTC(2026, 10, 24, 14, 40);

test('morning check is due at 19:30 PKT for the same day', () => {
  const r = dueChecks([{ id: 'm', kind: 'shift_end_check', time: '19:30', shift: 'morning' }], now, PKT, 30);
  assert.strictEqual(r.length, 1);
  assert.strictEqual(r[0].dayKey, '2026-11-24');
  assert.strictEqual(r[0].dayStartUtc, Date.UTC(2026, 10, 24) - PKT * 60000);
});

test('night check at 07:30 PKT belongs to the previous day', () => {
  const morning = Date.UTC(2026, 10, 24, 2, 40); // 07:40 PKT
  const r = dueChecks([{ id: 'n', kind: 'shift_end_check', time: '07:30', shift: 'night' }], morning, PKT, 30);
  assert.strictEqual(r[0].dayKey, '2026-11-23');
});

test('checks outside the window or paused are skipped', () => {
  const rules = [
    { id: 'a', kind: 'shift_end_check', time: '18:00', shift: 'morning' },
    { id: 'b', kind: 'shift_end_check', time: '19:30', shift: 'morning', enabled: false },
  ];
  assert.deepStrictEqual(dueChecks(rules, now, PKT, 30), []);
});

test('missing readings per section', () => {
  const reports = [
    { sectionId: 'chips', shift: 'morning', rows: [{ temperature: 30, humidity: 40 }] },
    { sectionId: 'nimko', shift: 'morning', rows: [{ temperature: 30 }] },
  ];
  assert.deepStrictEqual(missingFor(reports, 'morning', ['chips', 'nimko', 'wafer']), [
    { sectionId: 'nimko', missing: 'humidity' },
    { sectionId: 'wafer', missing: 'both' },
  ]);
});

test('alert doc id matches the app', () => {
  assert.strictEqual(alertDocId('default-morning-check|2026-11-24'), 'default-morning-check__2026-11-24');
});
