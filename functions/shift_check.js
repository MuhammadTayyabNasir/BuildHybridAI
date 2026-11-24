'use strict';

// Pure helpers for the scheduled shift-end check. Kept free of Firebase
// imports so they can be unit-tested with `node --test`.

const SECTIONS = ['chips', 'peri_peri', 'nimko', 'wafer', 'chocolate'];
const SECTION_NAMES = {
  chips: 'Chips', peri_peri: 'Peri Peri', nimko: 'Nimko', wafer: 'Wafer', chocolate: 'Chocolate',
};

const DEFAULT_RULES = [
  { id: 'default-morning-check', kind: 'shift_end_check', time: '19:30', shift: 'morning', enabled: true, approved: true, notifyManager: true },
  { id: 'default-night-check', kind: 'shift_end_check', time: '07:30', shift: 'night', enabled: true, approved: true, notifyManager: true },
];

/** Factory-local wall clock for a UTC instant (fixed offset; Pakistan has no DST). */
function localParts(utcMs, offsetMinutes) {
  const d = new Date(utcMs + offsetMinutes * 60000);
  return { y: d.getUTCFullYear(), m: d.getUTCMonth() + 1, d: d.getUTCDate(), h: d.getUTCHours(), min: d.getUTCMinutes() };
}

/** UTC millis of local midnight for a local y/m/d. */
function localMidnightUtc(y, m, d, offsetMinutes) {
  return Date.UTC(y, m - 1, d) - offsetMinutes * 60000;
}

const pad = (n) => String(n).padStart(2, '0');

/**
 * Rules due in the window (now - windowMinutes, now]. Returns
 * [{rule, dayKey, dayStartUtc}] where the day is the one the shift's report is
 * filed under (a night shift checked in the morning belongs to yesterday).
 */
function dueChecks(rules, nowUtc, offsetMinutes, windowMinutes) {
  const out = [];
  for (const rule of rules) {
    if (rule.kind !== 'shift_end_check' || rule.enabled === false || rule.approved === false) continue;
    const m = /^(\d{1,2}):(\d{2})$/.exec(rule.time || '');
    if (!m) continue;
    const now = localParts(nowUtc, offsetMinutes);
    let dueUtc = localMidnightUtc(now.y, now.m, now.d, offsetMinutes) +
      (Number(m[1]) * 60 + Number(m[2])) * 60000;
    if (dueUtc > nowUtc) dueUtc -= 86400000;
    if (nowUtc - dueUtc >= windowMinutes * 60000) continue;
    const due = localParts(dueUtc, offsetMinutes);
    let dayStartUtc = localMidnightUtc(due.y, due.m, due.d, offsetMinutes);
    if (rule.shift === 'night' && due.h < 12) dayStartUtc -= 86400000;
    const day = localParts(dayStartUtc, offsetMinutes);
    out.push({ rule, dayStartUtc, dayKey: `${day.y}-${pad(day.m)}-${pad(day.d)}` });
  }
  return out;
}

/** Sections whose scheduled reading for [shift] is missing or incomplete. */
function missingFor(reports, shift, sectionIds) {
  const out = [];
  for (const sec of sectionIds) {
    const rows = reports
      .filter((r) => r.sectionId === sec && r.shift === shift)
      .flatMap((r) => (Array.isArray(r.rows) ? r.rows : []));
    const hasT = rows.some((r) => typeof r.temperature === 'number');
    const hasH = rows.some((r) => typeof r.humidity === 'number');
    if (!hasT && !hasH) out.push({ sectionId: sec, missing: 'both' });
    else if (!hasT) out.push({ sectionId: sec, missing: 'temperature' });
    else if (!hasH) out.push({ sectionId: sec, missing: 'humidity' });
  }
  return out;
}

/** Same document id the app uses (AutomationCloud.docId), so a phone and the
 *  function never push the same alert twice. */
function alertDocId(key) {
  return key.replace(/[^A-Za-z0-9_\-|.]/g, '_').split('|').join('__');
}

function describe(rule, miss) {
  const what = (m) => (m === 'both' ? 'temperature + humidity' : m);
  const shift = rule.shift === 'morning' ? 'Morning' : 'Night';
  return `${shift} shift ended with ${miss.length} missed ${miss.length === 1 ? 'reading' : 'readings'}: ` +
    miss.map((x) => `${SECTION_NAMES[x.sectionId] || x.sectionId} (${what(x.missing)})`).join(', ') + '.';
}

module.exports = { SECTIONS, DEFAULT_RULES, dueChecks, missingFor, alertDocId, describe, localParts };
