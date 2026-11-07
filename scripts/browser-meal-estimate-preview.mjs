import assert from 'node:assert/strict';
import { mkdtemp, unlink, rmdir } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import sharp from 'sharp';
import { browserSession } from './browser-session.mjs';

// Technical UI QA only: a generated colour image tests upload; all AI/API responses are fixtures.
const folder = await mkdtemp(join(tmpdir(), 'jb-meal-upload-'));
const photoPath = join(folder, 'technical-upload.png');
await sharp({ create: { width: 480, height: 320, channels: 3, background: '#245e48' } }).png().toFile(photoPath);
const browser = await browserSession();
const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
const today = new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Kolkata' });
const keys = ['calories', 'protein', 'carbs', 'fat', 'fiber', 'sugar', 'sodium'];
const items = [
  { name: 'Cooked rice (estimate)', grams: 150, nutrients: { calories: 130, protein: 2.7, carbs: 28, fat: .3, fiber: .4, sugar: null, sodium: 0 } },
  { name: 'Dal (estimate)', grams: 200, nutrients: { calories: 100, protein: 6, carbs: 15, fat: 2, fiber: 4, sugar: null, sodium: null } },
];
let analysisCalls = 0, savedBody, uploadChosen = false;
let entries = [];
const errors = [];
const totals = portions => Object.fromEntries(keys.map(key => [key, {
  known: Math.round(portions.reduce((sum, item) => sum + (item.nutrients[key] ?? 0), 0) * 100) / 100,
  complete: portions.every(item => item.nutrients[key] !== null), missingEntries: portions.filter(item => item.nutrients[key] === null).length,
}]));
const scaled = item => Object.fromEntries(keys.map(key => [key, item.nutrients[key] === null ? null : item.nutrients[key] * item.grams / 100]));
browser.onEvent(({ method, params }) => {
  if (method === 'Page.fileChooserOpened') {
    browser.call('DOM.setFileInputFiles', { backendNodeId: params.backendNodeId, files: [photoPath] }).then(() => uploadChosen = true).catch(error => errors.push(error)); return;
  }
  if (method !== 'Fetch.requestPaused') return;
  const { requestId, request } = params;
  const path = new URL(request.url).pathname;
  let body = { token: 'meal-review-fixture', user: { id: 'preview-user', displayName: 'Alex Preview', email: 'preview@example.test', role: 'customer' }, profile: { workoutDays: [0, 2, 4], sessionMinutes: 40 } };
  if (path.endsWith('/me/habits')) body = { month: today.slice(0, 7), today, canEdit: true, habits: [], entries: [], days: [], summary: { completed: 0, goal: 0, progress: 0 } };
  if (path.endsWith('/me/nutrition')) body = { date: today, today, canEdit: true, entries, totals: totals(entries), targets: null, estimatedEntryCount: entries.length };
  if (path.endsWith('/me/meal-estimates/status')) body = { configured: true, entitled: true, remainingToday: 10 - analysisCalls, dailyLimit: 10 };
  if (path.endsWith('/me/meal-estimates') && request.method === 'POST') {
    analysisCalls++; body = { id: 'estimate-fixture', status: 'estimated', inputKind: 'photo_text', uncertainty: 'high', clarification: null, assumptions: ['Assumed 150 g cooked rice and a 200 g bowl of dal.', 'Cooking oil and bowl size are uncertain.'], items, totals: totals(items.map(item => ({ nutrients: scaled(item) }))), isEstimated: true };
  }
  if (path.endsWith('/meal-estimates/estimate-fixture/save') && request.method === 'POST') {
    savedBody = JSON.parse(request.postData);
    entries = savedBody.items.map((item, index) => ({ id: `meal-estimate-${index}`, date: today, meal: savedBody.meal, grams: item.grams, revision: 1, food: { name: item.name, nutrients: item.nutrients, source: { type: 'ai_estimate', label: 'AI estimate', editedByUser: true } }, nutrients: scaled(item) }));
    body = { entryIds: entries.map(item => item.id) };
  }
  browser.call('Fetch.fulfillRequest', { requestId, responseCode: 200, responseHeaders: [
    { name: 'Content-Type', value: 'application/json' }, { name: 'Access-Control-Allow-Origin', value: 'http://localhost:8080' }, { name: 'Access-Control-Allow-Headers', value: 'content-type,authorization' }, { name: 'Access-Control-Allow-Methods', value: 'GET,POST,PUT,OPTIONS' },
  ], body: Buffer.from(JSON.stringify(body)).toString('base64') }).catch(error => errors.push(error));
});
async function hasText(value) { return browser.evaluate(`document.body.innerText.includes(${JSON.stringify(value)}) || Array.from(document.querySelectorAll('[aria-label]')).some(e=>e.getAttribute('aria-label').includes(${JSON.stringify(value)}))`); }
async function waitFor(check, label) { for (let i = 0; i < 70; i++) { if (await check()) return; await pause(200); } throw new Error(`Timed out: ${label}`); }
async function wheel(deltaY) { await browser.call('Input.dispatchMouseEvent', { type: 'mouseWheel', x: 300, y: 550, deltaX: 0, deltaY }); await pause(350); }
async function click(label) { await browser.evaluate(`Array.from(document.querySelectorAll('[role=button]')).find(e=>(e.innerText??e.getAttribute('aria-label')??'').trim()===${JSON.stringify(label)})?.click()`); await pause(250); }
async function fill(label, value) {
  for (let i = 0; i < 16; i++) {
    const p = await browser.evaluate(`(()=>{const e=document.querySelector(${JSON.stringify(`input[aria-label="${label}"],textarea[aria-label="${label}"]`)});if(!e)return null;const r=e.getBoundingClientRect();return {x:r.x+r.width/2,y:r.y+r.height/2}})()`);
    if (p && p.y > 50 && p.y < 780) {
      for (const type of ['mousePressed', 'mouseReleased']) await browser.call('Input.dispatchMouseEvent', { type, ...p, button: 'left', clickCount: 1 });
      await browser.call('Input.dispatchKeyEvent', { type: 'keyDown', key: 'a', code: 'KeyA', windowsVirtualKeyCode: 65, modifiers: 2, commands: ['selectAll'] });
      await browser.call('Input.dispatchKeyEvent', { type: 'keyUp', key: 'a', code: 'KeyA', windowsVirtualKeyCode: 65, modifiers: 0 });
      await browser.call('Input.insertText', { text: value }); return;
    }
    await wheel(p && p.y < 50 ? -200 : 200);
  }
  throw new Error(`Input not visible: ${label}`);
}
async function capture(name) { await browser.call('Input.dispatchMouseEvent', { type: 'mouseMoved', x: 2, y: 2 }); await pause(800); await browser.screenshot(`docs/previews/${name}.png`); }
try {
  await browser.call('DOM.enable'); await browser.call('Page.setInterceptFileChooserDialog', { enabled: true });
  await browser.call('Fetch.enable', { patterns: [{ urlPattern: 'http://localhost:3001/*' }] });
  await browser.call('Page.navigate', { url: 'http://localhost:8080' }); await pause(3000);
  await browser.evaluate('localStorage.clear()'); await browser.call('Page.reload', { ignoreCache: true }); await pause(3000); await browser.evaluate('document.querySelector("flt-semantics-placeholder")?.click()');
  await waitFor(() => hasText('Welcome back.'), 'login');
  await fill('Email address', 'preview@example.test'); await fill('Password', 'meal-preview-password'); await click('Sign in'); await waitFor(() => hasText('Hello, Alex.'), 'Today');
  await wheel(450); await click('Open food diary'); await waitFor(() => hasText('Estimate from photo or text'), 'food diary');
  await click('Estimate from photo or text'); await waitFor(() => hasText('10 of 10 estimates left today'), 'estimator status');
  await fill('Describe your dish', 'A bowl of cooked rice and dal'); await click('Upload photo'); await waitFor(async () => uploadChosen, 'photo chooser'); await waitFor(() => hasText('Remove photo'), 'photo preview');
  await capture('meal-estimate-input');
  assert.equal(analysisCalls, 0); await click('Estimate meal'); await waitFor(() => hasText('Approx. 395 kcal'), 'estimate review'); assert.equal(entries.length, 0);
  await wheel(600); await capture('meal-estimate-review');
  await fill('Estimated portion (g)', '200'); await waitFor(() => hasText('Approx. 460 kcal'), 'portion adjustment');
  await wheel(4000); await click('Save estimate to diary'); await waitFor(async () => entries.length === 2, 'diary save');
  assert.equal(savedBody.items[0].grams, 200); assert.equal(analysisCalls, 1);
  await wheel(-5000); await waitFor(() => hasText('Includes AI estimates'), 'persistent estimate label'); await capture('meal-estimate-diary');
  assert.equal(errors.length, 0);
  console.log('Meal estimate visual QA passed: actual file selection with a technical image, text/photo request, editable review and explicit estimated diary save. All AI responses are fixtures; no provider was called.');
} finally {
  try { await browser.call('Page.setInterceptFileChooserDialog', { enabled: false }); await browser.call('Fetch.disable'); await browser.evaluate('localStorage.clear()'); } catch { /* Preserve QA errors. */ }
  browser.close(); await unlink(photoPath); await rmdir(folder);
}
