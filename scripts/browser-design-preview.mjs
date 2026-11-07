import assert from 'node:assert/strict';
import { browserSession } from './browser-session.mjs';

// Visual QA only: all API requests are intercepted with local sample responses.
// Does not contact the API, create an account or grant an actual membership.
const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
const browser = await browserSession();
const errors = [];
let savedProgress;
let savedProfile;
const habitChecks = new Map();
function habitPreview(month) {
  const today = new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Kolkata' });
  month ??= today.slice(0, 7);
  const start = `${today.slice(0, 7)}-01`;
  const count = new Date(Number(month.slice(0, 4)), Number(month.slice(5)), 0).getDate();
  const names = ['Complete my workout', 'Log my meals', 'Take a walk'];
  const habits = month >= start.slice(0, 7) ? names.map((name, i) => ({ id: `habit-${i + 1}`, name, startsOn: start, archivedOn: null, targetDays: 25 - i * 3, goal: Math.min(count, 25 - i * 3) })) : [];
  const entries = [...habitChecks.entries()].filter(([key]) => key.split('|')[1].startsWith(month)).map(([key, completed]) => ({ habitId: key.split('|')[0], date: key.split('|')[1], completed }));
  for (const habit of habits) { habit.completed = entries.filter(e => e.habitId === habit.id && e.completed).length; habit.progress = Math.min(1, habit.completed / habit.goal); }
  const goal = habits.reduce((sum, habit) => sum + habit.goal, 0);
  return { month, today, timezone: 'Asia/Kolkata', canEdit: true, habits, entries,
    days: Array.from({ length: count }, (_, i) => { const date = `${month}-${String(i + 1).padStart(2, '0')}`; return { date, completed: entries.filter(e => e.date === date && e.completed).length, eligible: date >= start && date <= today ? habits.length : 0 }; }),
    summary: { completed: habits.reduce((sum, habit) => sum + habit.completed, 0), goal, progress: goal ? habits.reduce((sum, habit) => sum + Math.min(habit.goal, habit.completed), 0) / goal : 0 },
  };
}
const user = { id: 'design-preview', displayName: 'Alex Preview', email: 'preview@example.test', role: 'customer' };
const profile = { age: 28, heightCm: 175, weightKg: 80, goal: 'general_fitness', experience: 'beginner', dietaryPreference: 'vegetarian', equipment: ['Dumbbells'], workoutDays: [0, 2, 4], sessionMinutes: 40, currentRoutine: 'Walking', limitations: '', healthDataConsent: true, shareWithTrainer: false };
browser.onEvent(message => {
  if (message.method !== 'Fetch.requestPaused') return;
  const { requestId, request } = message.params;
  const path = new URL(request.url).pathname;
  let body = { user, profile, token: 'visual-preview-only' };
  if (path.endsWith('/me/habits')) body = habitPreview(new URL(request.url).searchParams.get('month'));
  if (path.includes('/me/habits/') && path.includes('/days/') && request.method === 'PUT') {
    const parts = path.split('/');
    habitChecks.set(`${parts.at(-3)}|${parts.at(-1)}`, JSON.parse(request.postData).completed);
    body = { saved: true };
  }
  if (path.endsWith('/plans')) body = { plans: [
    { id: 'normal', name: 'Normal', priceInPaise: 300000, videoSessions: 0, features: ['Stored exercise demonstrations', 'AI coaching chat', 'Personalized workout planning', 'Nutrition, habits and progress tracking'] },
    { id: 'premium', name: 'Premium', priceInPaise: 1000000, videoSessions: 10, features: ['All Normal features', '10 live video coaching sessions'] },
    { id: 'premium-plus', name: 'Premium Plus', priceInPaise: 2000000, videoSessions: 25, features: ['All lower-plan features', '25 live video coaching sessions in total'] },
  ] };
  if (path.endsWith('/me/membership')) body = {
    status: 'active', next: null, history: [], billing: { checkoutEnabled: false },
    current: { id: 'preview-membership', planId: 'premium', planName: 'Premium', startsAt: '2026-11-05T10:00:00Z', endsAt: '2026-12-05T10:00:00Z', videoSessionsTotal: 10, videoSessionsUsed: 3, videoSessionsRemaining: 7, environment: 'development' },
  };
  if (path.endsWith('/me/profile') && request.method === 'PUT') {
    savedProfile = JSON.parse(request.postData);
    body = { profile: savedProfile };
  }
  if (path.endsWith('/me/workouts')) body = {
    plan: { title: 'Preview strength routine', version: 1, source: 'development_fixture' },
    workouts: [
      { id: 'preview-one', title: 'Full body strength', date: new Date().toISOString().slice(0, 10), exerciseCount: 1, status: 'not_started' },
      { id: 'preview-two', title: 'Mobility & recovery', date: new Date().toISOString().slice(0, 10), exerciseCount: 4, status: 'completed' },
    ],
  };
  if (path.endsWith('/me/workouts/preview-one')) body = {
    workout: { id: 'preview-one', title: 'Full body strength', date: new Date().toISOString().slice(0, 10), archived: false, source: 'development_fixture', version: 1 },
    today: new Date().toISOString().slice(0, 10),
    items: [{ id: 'preview-item', exercise: { id: 'preview-exercise', name: 'Dumbbell squat', instructions: ['Keep your feet planted and lower with control.', 'Return to standing with a steady, controlled movement.'] }, sets: 3, repetitions: 10, restSeconds: 60, targetWeightKg: null }],
    progress: { status: 'not_started', revision: 0, notes: '', exerciseLogs: [], completedAt: null },
  };
  if (path.endsWith('/video')) body = { available: false };
  if (path.endsWith('/progress') && request.method === 'PUT') {
    savedProgress = JSON.parse(request.postData);
    body = { revision: 1, duplicate: false };
  }
  browser.call('Fetch.fulfillRequest', {
    requestId, responseCode: 200,
    responseHeaders: [
      { name: 'Content-Type', value: 'application/json' },
      { name: 'Access-Control-Allow-Origin', value: 'http://localhost:8080' },
      { name: 'Access-Control-Allow-Headers', value: 'content-type,authorization' },
      { name: 'Access-Control-Allow-Methods', value: 'GET,POST,PUT,OPTIONS' },
    ],
    body: Buffer.from(JSON.stringify(body)).toString('base64'),
  }).catch(error => errors.push(error));
});
async function waitFor(check, label) {
  for (let i = 0; i < 60; i++) {
    if (await check()) return;
    await pause(200);
  }
  throw new Error(`Timed out: ${label}`);
}
async function hasText(value) {
  return browser.evaluate(`document.body.innerText.includes(${JSON.stringify(value)}) || Array.from(document.querySelectorAll('[aria-label]')).some(e=>e.getAttribute('aria-label').includes(${JSON.stringify(value)}))`);
}
async function wheel(deltaY) {
  await browser.call('Input.dispatchMouseEvent', { type: 'mouseWheel', x: 300, y: 550, deltaX: 0, deltaY });
  await pause(350);
}
async function capture(name) {
  await browser.call('Input.dispatchMouseEvent', { type: 'mouseMoved', x: 2, y: 2 });
  await pause(800);
  await browser.screenshot(`docs/previews/${name}.png`);
}
async function clickPoint(point) {
  assert.ok(point, 'Expected a visible control');
  for (const type of ['mousePressed', 'mouseReleased']) await browser.call('Input.dispatchMouseEvent', { type, ...point, button: 'left', clickCount: 1 });
  await pause(200);
}
async function controlPoint(selector) {
  return browser.evaluate(`(()=>{const e=document.querySelector(${JSON.stringify(selector)});if(!e)return null;const r=e.getBoundingClientRect();return {x:r.x+r.width/2,y:r.y+r.height/2}})()`);
}
async function fill(label, text) {
  const selector = `input[aria-label="${label}"]`;
  for (let i = 0; i < 8; i++) {
    const point = await controlPoint(selector);
    if (point && point.y > 20 && point.y < 780) {
      await clickPoint(point);
      await browser.call('Input.insertText', { text });
      return;
    }
    await wheel(180);
  }
  throw new Error(`Input unavailable: ${label}`);
}
try {
  await browser.call('Fetch.enable', { patterns: [{ urlPattern: 'http://localhost:3001/*' }] });
  await browser.call('Page.navigate', { url: 'http://localhost:8080' });
  await pause(3000);
  await browser.evaluate('localStorage.clear()');
  await browser.call('Page.reload', { ignoreCache: true });
  await pause(3000);
  await browser.evaluate('document.querySelector("flt-semantics-placeholder")?.click()');
  await waitFor(() => browser.evaluate('document.body.innerText.includes("Welcome back.")'), 'sign in');
  await capture('redesign-sign-in');
  await fill('Email address', user.email);
  await fill('Password', 'visual-preview-password');
  await browser.evaluate('Array.from(document.querySelectorAll("[role=button]")).find(e=>e.innerText.trim()==="Sign in")?.click()');
  await waitFor(() => browser.evaluate('document.body.innerText.includes("Hello, Alex.")'), 'Today');
  await capture('redesign-today');
  await wheel(520);
  await capture('redesign-habits');
  await browser.evaluate('document.querySelector("[role=checkbox]")?.click()');
  await waitFor(() => hasText('1 / 3'), 'habit check');
  await wheel(300);
  await browser.evaluate('Array.from(document.querySelectorAll("[role=button]")).find(e=>e.innerText.trim()==="View tracking")?.click()');
  await waitFor(() => hasText('Daily check-ins'), 'saved habit tracking');
  await capture('habits-monthly-summary');
  await wheel(340);
  const firstGridDay = `${habitPreview().month}-01`;
  const wasChecked = habitChecks.get(`habit-1|${firstGridDay}`) === true;
  const firstGridCell = `[role="checkbox"][aria-label="Complete my workout, ${firstGridDay}"]`;
  await browser.evaluate(`document.querySelector(${JSON.stringify(firstGridCell)})?.click()`);
  await waitFor(async () => habitChecks.get(`habit-1|${firstGridDay}`) === !wasChecked, 'grid checkmark save request');
  await capture('habits-monthly-grid');
  await browser.evaluate('Array.from(document.querySelectorAll("[role=radio],[role=button],[role=checkbox]")).find(e=>(e.getAttribute("aria-label")??e.innerText??"").trim()==="Weekly")?.click()');
  await waitFor(() => browser.evaluate('document.body.innerText.includes("Days 1–7") || Array.from(document.querySelectorAll("[aria-label]")).some(e=>e.getAttribute("aria-label").includes("Days 1–7"))'), 'weekly habit view');
  await capture('habits-weekly-grid');
  await browser.evaluate('Array.from(document.querySelectorAll("[role=button]")).find(e=>e.innerText.trim()==="Back")?.click()');
  await waitFor(() => controlPoint('[role=tab][aria-label="Workouts"]'), 'return to Today');
  await clickPoint(await controlPoint('[role=tab][aria-label="Workouts"]'));
  await waitFor(() => browser.evaluate('document.body.innerText.includes("Full body strength")'), 'workout schedule');
  await capture('redesign-workouts');
  await browser.evaluate('Array.from(document.querySelectorAll("[role=button]")).find(e=>e.innerText.includes("Full body strength"))?.click()');
  await waitFor(() => browser.evaluate('document.body.innerText.includes("Your exercises")'), 'workout details');
  await capture('redesign-workout-details');
  await wheel(450);
  await browser.evaluate('Array.from(document.querySelectorAll("[role=button]")).find(e=>e.innerText.trim()==="Watch demonstration")?.click()');
  await waitFor(() => browser.evaluate('document.body.innerText.includes("Retry video")'), 'missing demonstration');
  await capture('redesign-exercise-video');
  await browser.evaluate('document.querySelector("[role=checkbox]")?.click()');
  for (let i = 0; i < 6; i++) {
    const found = await browser.evaluate('!!Array.from(document.querySelectorAll("[role=button]")).find(e=>e.innerText.trim()==="Complete workout")');
    if (found) break;
    await wheel(350);
  }
  await browser.evaluate('Array.from(document.querySelectorAll("[role=button]")).find(e=>e.innerText.trim()==="Complete workout")?.click()');
  await waitFor(async () => savedProgress?.status === 'completed', 'completion save request');
  assert.equal(savedProgress.exerciseLogs[0].completed, true);
  await wheel(-3000);
  await waitFor(() => browser.evaluate('document.body.innerText.includes("Session completed") || Array.from(document.querySelectorAll("[aria-label]")).some(e=>e.getAttribute("aria-label").includes("Session completed"))'), 'saved confirmation');
  await capture('redesign-workout-completed');
  await browser.evaluate('Array.from(document.querySelectorAll("[role=button]")).find(e=>e.innerText.trim()==="Back")?.click()');
  await waitFor(() => controlPoint('[role=tab][aria-label="Plans"]'), 'plan navigation');
  await clickPoint(await controlPoint('[role=tab][aria-label="Plans"]'));
  await waitFor(() => browser.evaluate('document.body.innerText.includes("Membership plans") || Array.from(document.querySelectorAll("[aria-label]")).some(e=>e.getAttribute("aria-label").includes("7 of 10 video sessions remaining"))'), 'membership data');
  await capture('redesign-membership');
  await wheel(600);
  await capture('redesign-plan-comparison');
  await clickPoint(await controlPoint('[role=tab][aria-label="Profile"]'));
  await waitFor(() => browser.evaluate('document.body.innerText.includes("Your fitness profile")'), 'profile form');
  await capture('redesign-profile');
  await wheel(1000);
  await capture('redesign-profile-preferences');
  await wheel(5000);
  await capture('redesign-profile-consent');
  await browser.evaluate('Array.from(document.querySelectorAll("[role=button]")).find(e=>e.innerText.trim()==="Save profile")?.click()');
  await waitFor(async () => savedProfile?.weightKg === 80, 'profile save');
  assert.equal(savedProfile.healthDataConsent, true);
  assert.equal(savedProfile.shareWithTrainer, false);
  assert.deepEqual(savedProfile.workoutDays, [0, 2, 4]);
  assert.equal(errors.length, 0);
  console.log('Visual QA passed: sign-in, saved habit checkmarks, monthly/weekly tracking, grid saves, workouts, details, missing video, completion, membership, profile and consent-preserving save requests. Screenshots use intercepted sample data; API integration and actual video playback are not tested here.');
} finally {
  try {
    await browser.call('Fetch.disable');
    await browser.evaluate('localStorage.clear()');
  } catch (error) {
    console.error(`Preview cleanup could not finish: ${error.message}`);
  } finally {
    browser.close();
  }
}
