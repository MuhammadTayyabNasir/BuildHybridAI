// Walks the PMA web build in Chrome at phone and desktop sizes and saves a
// screenshot of every screen it can reach, plus any console errors.
//
//   cd flutter_app && flutter build web
//   python -m http.server 8787 --directory build/web   (in another shell)
//   node tools/playwright/screens.mjs [baseUrl] [outDir]
//
// It uses "Try the demo", so no account or password is needed.
import { chromium } from 'playwright';
import fs from 'node:fs';
import path from 'node:path';

const base = process.argv[2] ?? 'http://localhost:8787';
const out = process.argv[3] ?? 'build/screens';
fs.mkdirSync(out, { recursive: true });

const sizes = [
  { name: 'phone', width: 390, height: 844 },
  { name: 'desktop', width: 1440, height: 900 },
];

const wait = (ms) => new Promise((r) => setTimeout(r, ms));
const log = [];

async function enableSemantics(page) {
  // Flutter web draws to a canvas; its accessibility tree (real DOM nodes
  // with labels) appears after the hidden placeholder is activated.
  await page.waitForSelector('flt-semantics-placeholder', { state: 'attached', timeout: 60000 });
  await page.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click());
  await wait(800);
}

// True only when a click actually landed.
async function tryClick(locator) {
  if (!(await locator.count())) return false;
  try {
    await locator.click({ timeout: 5000 });
    return true;
  } catch {
    return false;
  }
}

async function tapText(page, text) {
  return (
    (await tryClick(page.getByRole('button', { name: new RegExp(text, 'i') }).first())) ||
    (await tryClick(page.getByText(text, { exact: false }).first()))
  );
}

async function shot(page, size, name) {
  await wait(1200);
  const file = path.join(out, `${size.name}-${name}.png`);
  await page.screenshot({ path: file });
  log.push(`shot ${file}`);
}

const browser = await chromium.launch({ channel: 'chrome' }).catch(() => chromium.launch());
for (const size of sizes) {
  const ctx = await browser.newContext({ viewport: { width: size.width, height: size.height } });
  const page = await ctx.newPage();
  page.on('console', (m) => {
    if (m.type() === 'error') log.push(`[${size.name}] console error: ${m.text().slice(0, 300)}`);
  });
  page.on('pageerror', (e) => log.push(`[${size.name}] page error: ${String(e).slice(0, 300)}`));

  await page.goto(base, { waitUntil: 'networkidle', timeout: 120000 });
  await enableSemantics(page);
  await shot(page, size, '01-login');

  if (!(await tapText(page, 'Try the demo'))) {
    log.push(`[${size.name}] demo button not found`);
    await ctx.close();
    continue;
  }
  await wait(6000); // seeding demo data
  await shot(page, size, '02-today');

  const tabs = [
    ['Assistant', '03-assistant'],
    ['Insights', '04-insights'],
    ['Sections', '05-sections'],
  ];
  for (const [label, name] of tabs) {
    if (await tapText(page, label)) await shot(page, size, name);
    else log.push(`[${size.name}] tab ${label} not found`);
  }

  // Assistant: type a command and a follow-up.
  if (await tapText(page, 'Assistant')) {
    const box = page.locator('input, textarea, [role=textbox]').first();
    if (await box.count()) {
      await box.click();
      await page.keyboard.type('peri peri humidity 45');
      await page.keyboard.press('Enter');
      await shot(page, size, '06-assistant-readback');
      await page.keyboard.type('haan');
      await page.keyboard.press('Enter');
      await shot(page, size, '07-assistant-saved');
      await page.keyboard.type('aaj meri koi entry miss to nahi hui');
      await page.keyboard.press('Enter');
      await shot(page, size, '08-assistant-missing');
    } else {
      log.push(`[${size.name}] assistant text box not found`);
    }
  }

  // Sections tab: open the first section and its sheets.
  if (await tapText(page, 'Sections')) {
    await wait(600);
    if (await tapText(page, 'Chips')) {
      await shot(page, size, '09-section-chips');
      if (await tapText(page, 'Temp')) await shot(page, size, '10-temp-humidity');
      await page.goBack().catch(() => {});
    }
  }

  // Today screen shortcuts (automations, scan).
  if (await tapText(page, 'Today')) {
    if (await tapText(page, 'utomation')) {
      await shot(page, size, '11-automations');
      await page.keyboard.press('Escape');
      await page.goBack().catch(() => {});
    }
    if (await tapText(page, 'Scan')) {
      await shot(page, size, '12-scan');
      await page.goBack().catch(() => {});
    }
  }

  await ctx.close();
}
await browser.close();
fs.writeFileSync(path.join(out, 'log.txt'), log.join('\n'));
console.log(log.join('\n'));
