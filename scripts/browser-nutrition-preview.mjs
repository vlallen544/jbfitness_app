import assert from 'node:assert/strict';
import { browserSession } from './browser-session.mjs';

// Visual QA uses intercepted sample responses; it never contacts the API or creates customer records.
const browser = await browserSession();
const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
const today = new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Kolkata' });
const values = { calories: 400, protein: 10, carbs: 70, fat: 8, fiber: 6, sugar: 12, sodium: 100 };
const food = { id: 'preview-label', name: 'Sample cereal label', nutrients: values, source: { type: 'label', label: 'Values entered by you', note: 'Sample label · design preview only' } };
let entries = [];
const requests = [];
const errors = [];
function day() {
  return { date: today, today, timezone: 'Asia/Kolkata', canEdit: true, entries,
    targets: { effectiveFrom: today, revision: 1, nutrients: { calories: 2000, protein: 120, carbs: 250, fat: 65, fiber: 30, sugar: null, sodium: null } },
    totals: Object.fromEntries(Object.keys(values).map(key => [key, { known: entries.reduce((sum, entry) => sum + entry.nutrients[key], 0), complete: true, missingEntries: 0 }])),
  };
}
browser.onEvent(({ method, params }) => {
  if (method !== 'Fetch.requestPaused') return;
  const { requestId, request } = params;
  const path = new URL(request.url).pathname;
  let body = { token: 'nutrition-preview', user: { id: 'preview-user', displayName: 'Alex Preview', email: 'preview@example.test', role: 'customer' }, profile: { sessionMinutes: 40, workoutDays: [0, 2, 4] } };
  if (path.endsWith('/me/habits')) body = { month: today.slice(0, 7), today, canEdit: true, habits: [], entries: [], days: [], summary: { completed: 0, goal: 0, progress: 0 } };
  if (path.endsWith('/me/nutrition')) body = day();
  if (path.endsWith('/me/nutrition/foods')) body = { foods: [food], external: [], providerConfigured: false, notice: null };
  if (path.endsWith('/me/nutrition/entries') && request.method === 'POST') {
    const entry = JSON.parse(request.postData); requests.push(entry);
    entries = [{ id: 'preview-entry', revision: 1, date: entry.date, meal: entry.meal, grams: entry.grams, food, nutrients: Object.fromEntries(Object.entries(values).map(([key, value]) => [key, value * entry.grams / 100])) }];
    body = { id: 'preview-entry' };
  }
  browser.call('Fetch.fulfillRequest', { requestId, responseCode: 200, responseHeaders: [
    { name: 'Content-Type', value: 'application/json' }, { name: 'Access-Control-Allow-Origin', value: 'http://localhost:8080' }, { name: 'Access-Control-Allow-Headers', value: 'content-type,authorization' }, { name: 'Access-Control-Allow-Methods', value: 'GET,POST,PUT,OPTIONS' },
  ], body: Buffer.from(JSON.stringify(body)).toString('base64') }).catch(error => errors.push(error));
});
async function hasText(value) { return browser.evaluate(`document.body.innerText.includes(${JSON.stringify(value)}) || Array.from(document.querySelectorAll('[aria-label]')).some(e=>e.getAttribute('aria-label').includes(${JSON.stringify(value)}))`); }
async function waitFor(check, name) { for (let i = 0; i < 60; i++) { if (await check()) return; await pause(200); } throw new Error(`Timed out: ${name}`); }
async function wheel(deltaY) { await browser.call('Input.dispatchMouseEvent', { type: 'mouseWheel', x: 300, y: 550, deltaX: 0, deltaY }); await pause(350); }
async function point(selector) { return browser.evaluate(`(()=>{const e=document.querySelector(${JSON.stringify(selector)});if(!e)return null;const r=e.getBoundingClientRect();return {x:r.x+r.width/2,y:r.y+r.height/2}})()`); }
async function clickPoint(p) { assert.ok(p); for (const type of ['mousePressed', 'mouseReleased']) await browser.call('Input.dispatchMouseEvent', { type, ...p, button: 'left', clickCount: 1 }); await pause(200); }
async function fill(label, value) {
  const selector = `input[aria-label="${label}"]`;
  for (let i = 0; i < 10; i++) {
    const p = await point(selector);
    if (p && p.y > 20 && p.y < 780) {
      await clickPoint(p);
      await browser.call('Input.dispatchKeyEvent', { type: 'keyDown', key: 'a', code: 'KeyA', windowsVirtualKeyCode: 65, modifiers: 2, commands: ['selectAll'] });
      await browser.call('Input.dispatchKeyEvent', { type: 'keyUp', key: 'a', code: 'KeyA', windowsVirtualKeyCode: 65, modifiers: 0 });
      await browser.call('Input.insertText', { text: value }); return;
    }
    await wheel(180);
  }
  throw new Error(`Input not visible: ${label}`);
}
async function click(label) { await browser.evaluate(`Array.from(document.querySelectorAll('[role=button]')).find(e=>(e.innerText??e.getAttribute('aria-label')??'').trim()===${JSON.stringify(label)})?.click()`); await pause(250); }
async function capture(name) { await browser.call('Input.dispatchMouseEvent', { type: 'mouseMoved', x: 2, y: 2 }); await pause(800); await browser.screenshot(`docs/previews/${name}.png`); }
try {
  await browser.call('Fetch.enable', { patterns: [{ urlPattern: 'http://localhost:3001/*' }] });
  await browser.call('Page.navigate', { url: 'http://localhost:8080' }); await pause(3000);
  await browser.evaluate('localStorage.clear()'); await browser.call('Page.reload', { ignoreCache: true }); await pause(3000);
  await browser.evaluate('document.querySelector("flt-semantics-placeholder")?.click()');
  await waitFor(() => hasText('Welcome back.'), 'sign-in');
  await fill('Email address', 'preview@example.test'); await fill('Password', 'nutrition-preview-password'); await click('Sign in');
  await waitFor(() => hasText('Hello, Alex.'), 'Today');
  await wheel(400); await click('Open food diary');
  await waitFor(() => hasText('0 kcal'), 'empty diary');
  await capture('nutrition-empty');
  await click('Log a food');
  await waitFor(() => hasText('Sample cereal label'), 'food picker');
  await capture('nutrition-food-picker');
  await browser.evaluate('Array.from(document.querySelectorAll("[role=button]")).find(e=>(e.innerText??e.getAttribute("aria-label")??"").includes("Sample cereal label"))?.click()');
  await waitFor(() => point('input[aria-label="Quantity (g)"]'), 'portion form');
  await fill('Quantity (g)', '150'); await capture('nutrition-portion'); await click('Log food');
  await waitFor(async () => requests.length === 1, 'meal save'); assert.equal(requests[0].grams, 150); assert.equal(requests[0].meal, 'breakfast');
  await wheel(-4000); await waitFor(() => hasText('600 kcal'), 'calculated daily energy');
  await capture('nutrition-daily-summary');
  await wheel(1100); await capture('nutrition-meals');
  assert.equal(errors.length, 0);
  console.log('Nutrition visual QA passed: Today navigation, food picker, 150 g portion, saved request and 600 kcal daily total. Sample responses; database integration is tested separately.');
} finally {
  try { await browser.call('Fetch.disable'); await browser.evaluate('localStorage.clear()'); } catch { /* Keep the original QA error. */ }
  browser.close();
}
