import assert from "node:assert/strict";
import { randomUUID, randomBytes } from "node:crypto";
import { Pool } from "pg";
import { browserSession } from "./browser-session.mjs";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { fileURLToPath } from "node:url";
import { mkdtemp, unlink, rmdir } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";

// Requires the local API, built mobile preview and dedicated Chromium on port 9234.
// Creates one uniquely identified test account and deletes only that account afterwards.
const api = "http://localhost:3001/api/v1";
const workoutQA = process.argv.includes("--workout");
const membershipQA = process.argv.includes("--membership") || workoutQA;
let workoutExerciseId;
let workoutMediaFile;
let technicalRoot;
let technicalClip;
let workoutId;
const email = `qa-${randomUUID().slice(0, 8)}@example.test`;
const password = randomBytes(24).toString("base64url");
const pool = new Pool({ connectionString: process.env.DATABASE_URL });
let userId;
let browser;
const pause = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
async function waitFor(check, message) {
  for (let attempt = 0; attempt < 40; attempt++) {
    if (await check()) return;
    await pause(300);
  }
  throw new Error(message);
}
try {
  const register = await fetch(`${api}/auth/register`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ email, password, displayName: "QA Customer" }),
  });
  assert.equal(register.status, 201);
  const session = await register.json();
  userId = session.user.id;
  const profile = {
    age: 28,
    heightCm: 175,
    weightKg: 80,
    goal: "general_fitness",
    experience: "beginner",
    dietaryPreference: "vegetarian",
    equipment: ["Dumbbells"],
    workoutDays: [0, 2, 4],
    sessionMinutes: 40,
    currentRoutine: "Walking",
    limitations: "",
    foodNotes: "",
    healthDataConsent: true,
    shareWithTrainer: false,
  };
  const saved = await fetch(`${api}/me/profile`, {
    method: "PUT",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${session.token}`,
    },
    body: JSON.stringify(profile),
  });
  assert.equal(saved.status, 200);
  if (membershipQA) {
    await promisify(execFile)(
      process.execPath,
      [
        "--env-file-if-exists=.env",
        "--import",
        "tsx",
        "scripts/grant-test-membership.ts",
        "--email",
        email,
        "--plan",
        "premium",
      ],
      {
        cwd: fileURLToPath(new URL("../apps/api/", import.meta.url)),
        env: { ...process.env, ENABLE_DEV_MEMBERSHIPS: "true" },
      },
    );
  }
  if (workoutQA) {
    const cwd = fileURLToPath(new URL("../apps/api/", import.meta.url));
    workoutExerciseId = `qa-playback-${randomUUID()}`;
    technicalRoot = await mkdtemp(join(tmpdir(), "jbfitness-browser-video-"));
    technicalClip = join(technicalRoot, "technical-test.mp4");
    await promisify(execFile)("ffmpeg", [
      "-nostdin",
      "-loglevel",
      "error",
      "-f",
      "lavfi",
      "-i",
      "color=c=0x245E48:s=320x180:r=12:d=2",
      "-vf",
      "drawtext=text=PLAYBACK TEST:fontcolor=white:fontsize=22:x=(w-text_w)/2:y=(h-text_h)/2",
      "-c:v",
      "libx264",
      "-preset",
      "ultrafast",
      "-pix_fmt",
      "yuv420p",
      "-movflags",
      "+faststart",
      technicalClip,
    ]);
    await promisify(execFile)(
      process.execPath,
      [
        "--env-file-if-exists=.env",
        "--import",
        "tsx",
        "test/fixtures/browser-workout.ts",
        "--email",
        email,
        "--id",
        workoutExerciseId,
      ],
      { cwd, env: { ...process.env, ENABLE_DEV_WORKOUTS: "true" } },
    );
    await promisify(execFile)(
      process.execPath,
      [
        "--env-file-if-exists=.env",
        "--import",
        "tsx",
        "scripts/attach-exercise-video.ts",
        "--exercise",
        workoutExerciseId,
        "--file",
        technicalClip,
      ],
      { cwd, env: process.env },
    );
    const key = (
      await pool.query("SELECT media_key FROM exercises WHERE id=$1", [
        workoutExerciseId,
      ])
    ).rows[0].media_key;
    assert.match(key, /^[a-f0-9-]{36}\.mp4$/);
    workoutMediaFile = resolve(
      process.env.EXERCISE_MEDIA_ROOT ?? resolve(cwd, "private-media"),
      key,
    );
    workoutId = (
      await pool.query(
        "SELECT id FROM workout_sessions WHERE customer_id=$1 ORDER BY scheduled_on DESC LIMIT 1",
        [userId],
      )
    ).rows[0].id;
  }
  browser = await browserSession();
  await browser.call("Page.navigate", { url: "http://localhost:8080" });
  await pause(3000);
  await browser.evaluate(
    'document.querySelector("flt-semantics-placeholder")?.click()',
  );
  const hasInput = (label) =>
    browser.evaluate(
      `!!document.querySelector('input[aria-label=${JSON.stringify(label)}]')`,
    );
  await waitFor(() => hasInput("Email address"), "Sign-in form was not ready.");
  const fill = async (label, value) => {
    const point = await browser.evaluate(
      `(()=>{const r=document.querySelector('input[aria-label=${JSON.stringify(label)}]').getBoundingClientRect();return {x:r.x+r.width/2,y:r.y+r.height/2}})()`,
    );
    await browser.call("Input.dispatchMouseEvent", {
      type: "mousePressed",
      ...point,
      button: "left",
      clickCount: 1,
    });
    await browser.call("Input.dispatchMouseEvent", {
      type: "mouseReleased",
      ...point,
      button: "left",
      clickCount: 1,
    });
    await pause(250);
    await browser.call("Input.insertText", { text: value });
    await pause(150);
  };
  const click = (label) =>
    browser.evaluate(
      `Array.from(document.querySelectorAll('[role="button"]')).find(e=>e.innerText.trim()===${JSON.stringify(label)})?.click()`,
    );
  const navigateTab = async (label) => {
    const point = await browser.evaluate(
      `(()=>{const e=Array.from(document.querySelectorAll('[role="tab"]')).find(e=>e.getAttribute('aria-label')===${JSON.stringify(label)});if(!e)return null;const r=e.getBoundingClientRect();return {x:r.x+r.width/2,y:r.y+r.height/2}})()`,
    );
    assert.ok(point, "Requested navigation tab was unavailable.");
    await browser.call("Input.dispatchMouseEvent", {
      type: "mousePressed",
      ...point,
      button: "left",
      clickCount: 1,
    });
    await browser.call("Input.dispatchMouseEvent", {
      type: "mouseReleased",
      ...point,
      button: "left",
      clickCount: 1,
    });
    await pause(500);
  };
  await fill("Email address", email);
  await fill("Password", password);
  await click("Sign in");
  await waitFor(
    () =>
      browser.evaluate('document.body.innerText.includes("Make time")'),
    "Browser sign-in did not reach the customer home.",
  );
  await browser.call("Page.reload", { ignoreCache: true });
  await pause(3000);
  await browser.evaluate(
    'document.querySelector("flt-semantics-placeholder")?.click()',
  );
  await waitFor(
    () =>
      browser.evaluate('document.body.innerText.includes("Make time")'),
    "Secure session did not restore after reload.",
  );
  const profileTab = await browser.evaluate(
    'Array.from(document.querySelectorAll("[role]")).filter(e=>(e.getAttribute("aria-label")??e.innerText).trim()==="Profile").map(e=>({role:e.getAttribute("role"),text:e.innerText}))',
  );
  if (!profileTab.length)
    throw new Error("Profile navigation was unavailable.");
  if (membershipQA) {
    await navigateTab("Plans");
    await waitFor(
      () =>
        browser.evaluate(
          'document.body.innerText.includes("10 of 10 video sessions remaining")',
        ),
      "Membership balance did not load from the API.",
    );
    assert.ok(
      await browser.evaluate(
        'document.body.innerText.includes("Development test membership • no payment collected")',
      ),
    );
    await browser.screenshot("docs/previews/mobile-membership.png");
  }
  if (workoutQA) {
    await navigateTab("Workouts");
    await waitFor(
      () =>
        browser.evaluate(
          'document.body.innerText.includes("Playback verification session")',
        ),
      "Stored workout schedule did not load.",
    );
    await browser.screenshot("docs/previews/mobile-workouts.png");
    await browser.evaluate(
      'Array.from(document.querySelectorAll("[role=button]")).find(e=>e.innerText.includes("Playback verification session"))?.click()',
    );
    await waitFor(
      () =>
        browser.evaluate(
          'document.body.innerText.includes("Watch demonstration")',
        ),
      "Workout details did not load.",
    );
    await click("Watch demonstration");
    await waitFor(
      () =>
        browser.evaluate(
          '!!document.querySelector("video") && document.querySelector("video").readyState>=2',
        ),
      "Protected video did not initialize.",
    );
    const pressPlayerButton = async (label) => {
      await waitFor(
        () =>
          browser.evaluate(
            `Array.from(document.querySelectorAll('[role="button"]')).some(e=>e.innerText.trim()===${JSON.stringify(label)})`,
          ),
        "Player controls did not initialize.",
      );
      const point = await browser.evaluate(
        `(()=>{const e=Array.from(document.querySelectorAll('[role="button"]')).find(e=>e.innerText.trim()===${JSON.stringify(label)});const r=e.getBoundingClientRect();return {x:r.x+r.width/2,y:r.y+r.height/2}})()`,
      );
      await browser.call("Input.dispatchMouseEvent", {
        type: "mousePressed",
        ...point,
        button: "left",
        clickCount: 1,
      });
      await browser.call("Input.dispatchMouseEvent", {
        type: "mouseReleased",
        ...point,
        button: "left",
        clickCount: 1,
      });
    };
    await pressPlayerButton("Play demonstration");
    await waitFor(
      () => browser.evaluate('document.querySelector("video").currentTime>0.1'),
      "Video playback did not advance.",
    );
    await pressPlayerButton("Pause demonstration");
    await waitFor(
      () => browser.evaluate('document.querySelector("video").paused'),
      "Video did not pause.",
    );
    await browser.screenshot("docs/previews/mobile-exercise-video.png");
    await browser.evaluate(
      'document.querySelector("[role=checkbox]")?.click()',
    );
    for (let attempt = 0; attempt < 7; attempt++) {
      const point = await browser.evaluate(
        '(()=>{const e=Array.from(document.querySelectorAll("[role=button]")).find(e=>e.innerText.trim()==="Complete workout");if(!e)return null;const r=e.getBoundingClientRect();return {y:r.y,h:r.height}})()',
      );
      if (point && point.y > 55 && point.y + point.h < 830) break;
      await browser.call("Input.dispatchMouseEvent", {
        type: "mouseWheel",
        x: 375,
        y: 550,
        deltaX: 0,
        deltaY: point && point.y < 55 ? -450 : 450,
      });
      await pause(300);
    }
    await click("Complete workout");
    await waitFor(async () => {
      const r = await fetch(`${api}/me/workouts/${workoutId}`, {
        headers: { Authorization: `Bearer ${session.token}` },
      });
      return r.ok && (await r.json()).progress.status === "completed";
    }, "Workout completion was not persisted.");
    await click("Back");
    await pause(400);
    await click("History");
    await waitFor(
      () => browser.evaluate('document.body.innerText.includes("completed")'),
      "Workout history did not show the saved session.",
    );
    await browser.screenshot("docs/previews/mobile-workout-history.png");
    await click("Back");
    await pause(300);
  }
  await navigateTab("Profile");
  await waitFor(
    () =>
      browser.evaluate(
        'document.body.innerText.includes("Your fitness profile")',
      ),
    "Profile did not open.",
  );
  await browser.screenshot("docs/previews/mobile-profile.png");
  const agePoint = await browser.evaluate(
    '(()=>{const r=document.querySelector("input[aria-label=Age]").getBoundingClientRect();return {x:r.x+r.width/2,y:r.y+r.height/2}})()',
  );
  await browser.call("Input.dispatchMouseEvent", {
    type: "mousePressed",
    ...agePoint,
    button: "left",
    clickCount: 1,
  });
  await browser.call("Input.dispatchMouseEvent", {
    type: "mouseReleased",
    ...agePoint,
    button: "left",
    clickCount: 1,
  });
  await pause(250);
  assert.equal(await browser.evaluate("document.activeElement?.value"), "28");
  await click("Sign out");
  await waitFor(
    () => hasInput("Email address"),
    "Sign-out did not return to sign-in.",
  );
  await browser.call("Page.reload", { ignoreCache: true });
  await pause(2500);
  await browser.evaluate(
    'document.querySelector("flt-semantics-placeholder")?.click()',
  );
  await waitFor(
    () => hasInput("Email address"),
    "Signed-out state did not persist.",
  );
  await browser.screenshot("docs/previews/mobile-sign-in.png");
  console.log(
    workoutQA
      ? "Real-browser checks passed: stored workout, actual protected video playback, completion/history, membership and account lifecycle."
      : membershipQA
        ? "Real-browser checks passed: test membership balance/unpaid label, login, session restoration, profile and logout."
        : "Real-browser checks passed: login, secure session persistence, saved profile and logout.",
  );
} finally {
  browser?.close();
  if (userId) await pool.query("DELETE FROM users WHERE id=$1", [userId]);
  if (workoutExerciseId)
    await pool.query("DELETE FROM exercises WHERE id=$1", [workoutExerciseId]);
  if (workoutMediaFile) await unlink(workoutMediaFile);
  if (technicalClip) await unlink(technicalClip);
  if (technicalRoot) await rmdir(technicalRoot);
  await pool.end();
}
