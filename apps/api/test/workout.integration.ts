import "reflect-metadata";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import type { AddressInfo } from "node:net";
import { test } from "node:test";
import { mkdtemp, readFile, unlink, rmdir, symlink } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { NestFactory } from "@nestjs/core";
import { BadRequestException, ForbiddenException } from "@nestjs/common";
import { AppModule } from "../src/app.module";
import { Database } from "../src/database";
import { MembershipService } from "../src/memberships";
import { WorkoutService } from "../src/workouts";
import { ExerciseMedia } from "../src/exercise-media";
import { addDays, mondayOf, todayInIndia } from "../src/workout-schema";

test("workout ownership, versioned progress and protected video streaming", async (t) => {
  const previous = {
    mode: process.env.NODE_ENV,
    memberships: process.env.ENABLE_DEV_MEMBERSHIPS,
    workouts: process.env.ENABLE_DEV_WORKOUTS,
    root: process.env.EXERCISE_MEDIA_ROOT,
  };
  process.env.NODE_ENV = "test";
  process.env.ENABLE_DEV_MEMBERSHIPS = "true";
  process.env.ENABLE_DEV_WORKOUTS = "true";
  const root = await mkdtemp(join(tmpdir(), "jbfitness-workout-"));
  process.env.EXERCISE_MEDIA_ROOT = root;
  const videoPath = join(root, "technical-test.mp4");
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
    videoPath,
  ]);
  const video = await readFile(videoPath);
  const start = async () => {
    const app = await NestFactory.create(AppModule, { logger: false });
    app.setGlobalPrefix("api/v1");
    await app.listen(0, "127.0.0.1");
    return app;
  };
  let app = await start();
  let db = app.get(Database);
  let service = app.get(WorkoutService);
  const users: string[] = [];
  const exerciseId = `qa-${randomUUID()}`;
  const draftId = `qa-draft-${randomUUID()}`;
  let linked = false;
  const request = async (
    path: string,
    method = "GET",
    body?: unknown,
    token?: string,
  ) => {
    const port = (app.getHttpServer().address() as AddressInfo).port;
    const r = await fetch(`http://127.0.0.1:${port}/api/v1${path}`, {
      method,
      headers: {
        "Content-Type": "application/json",
        ...(token ? { Authorization: `Bearer ${token}` } : {}),
      },
      ...(body === undefined ? {} : { body: JSON.stringify(body) }),
    });
    return { status: r.status, data: await r.json() };
  };
  const stream = async (path: string, options: RequestInit = {}) => {
    const port = (app.getHttpServer().address() as AddressInfo).port;
    return fetch(`http://127.0.0.1:${port}${path}`, options);
  };
  const customer = async () => {
    const result = await request("/auth/register", "POST", {
      email: `workout-${randomUUID()}@example.test`,
      password: "A-test-password-42!",
      displayName: "Workout fixture",
    });
    assert.equal(result.status, 201);
    users.push(result.data.user.id);
    return {
      id: result.data.user.id as string,
      token: result.data.token as string,
    };
  };
  const plan = (date = todayInIndia()) => ({
    title: "QA routine",
    sessions: [
      {
        date,
        title: "QA session",
        exercises: [
          {
            exerciseId,
            sets: 3,
            repetitions: 10,
            targetWeightKg: null,
            restSeconds: 60,
          },
        ],
      },
    ],
  });
  let workoutId = "";
  let itemId = "";
  let playbackPath = "";
  let revision = 0;
  try {
    const a = await customer();
    const b = await customer();
    await db.pool.query(
      `INSERT INTO exercises(id,name,muscle_group,equipment,instructions,review_status) VALUES($1,'Technical playback test','QA','[]','["Playback verification only"]','development_sample'),($2,'Draft fixture','QA','[]','[]','draft')`,
      [exerciseId, draftId],
    );
    await t.test(
      "membership gates workout/video access but history remains available",
      async () => {
        assert.equal((await request("/me/workouts")).status, 401);
        assert.equal(
          (await request("/me/workouts", "GET", undefined, a.token)).status,
          403,
        );
        assert.equal(
          (await request("/me/workouts/history", "GET", undefined, a.token))
            .status,
          200,
        );
        for (const [user, planId, amount] of [
          [a, "normal", 300000],
          [b, "premium-plus", 2000000],
        ] as const)
          await app
            .get(MembershipService)
            .applyTestPurchase({
              customerId: user.id,
              planId,
              eventId: randomUUID(),
              paymentReference: randomUUID(),
              amountPaise: amount,
              currency: "INR",
            });
      },
    );
    await t.test(
      "publishing rejects invalid prescriptions, dates, unknown exercises and drafts",
      async () => {
        const input = plan();
        input.sessions[0].exercises[0].sets = 0;
        await assert.rejects(
          service.publishPlan(a.id, input, "development_fixture"),
          BadRequestException,
        );
        await assert.rejects(
          service.publishPlan(a.id, plan("2026-02-30"), "development_fixture"),
          BadRequestException,
        );
        const missing = plan();
        missing.sessions[0].exercises[0].exerciseId = "missing";
        await assert.rejects(
          service.publishPlan(a.id, missing, "development_fixture"),
          BadRequestException,
        );
        const draft = plan();
        draft.sessions[0].exercises[0].exerciseId = draftId;
        await assert.rejects(
          service.publishPlan(a.id, draft, "development_fixture"),
          BadRequestException,
        );
        await assert.rejects(
          service.publishPlan(a.id, plan(), "trainer"),
          BadRequestException,
        );
      },
    );
    await t.test(
      "weekly schedule, exercise prescription and missing-video state are persisted",
      async () => {
        await service.publishPlan(a.id, plan(), "development_fixture");
        const week = await request(
          `/me/workouts?from=${mondayOf(todayInIndia())}`,
          "GET",
          undefined,
          a.token,
        );
        assert.equal(week.status, 200);
        assert.equal(week.data.workouts.length, 1);
        workoutId = week.data.workouts[0].id;
        const detail = await request(
          `/me/workouts/${workoutId}`,
          "GET",
          undefined,
          a.token,
        );
        itemId = detail.data.items[0].id;
        assert.equal(detail.data.items[0].restSeconds, 60);
        assert.equal(detail.data.items[0].sets, 3);
        assert.equal(detail.data.progress.revision, 0);
        const media = await request(
          `/me/exercises/${exerciseId}/video`,
          "GET",
          undefined,
          a.token,
        );
        assert.equal(media.data.available, false);
        const library = await request(
          "/me/exercises",
          "GET",
          undefined,
          b.token,
        );
        assert.ok(
          library.data.exercises.some(
            (row: { id: string }) => row.id === exerciseId,
          ),
        );
        assert.ok(
          !library.data.exercises.some(
            (row: { id: string }) => row.id === draftId,
          ),
        );
      },
    );
    const log = (completed = true) => ({
      itemId,
      completed,
      actualSets: 3,
      actualRepetitions: 10,
      actualWeightKg: null,
      difficulty: "moderate",
      notes: "Test feedback",
    });
    await t.test(
      "foreign workouts and exercise-log IDs cannot be read or modified",
      async () => {
        assert.equal(
          (
            await request(
              `/me/workouts/${workoutId}`,
              "GET",
              undefined,
              b.token,
            )
          ).status,
          404,
        );
        const bad = {
          requestId: randomUUID(),
          revision: 0,
          status: "in_progress",
          exerciseLogs: [{ ...log(), itemId: randomUUID() }],
          notes: "",
        };
        assert.equal(
          (
            await request(
              `/me/workouts/${workoutId}/progress`,
              "PUT",
              bad,
              a.token,
            )
          ).status,
          400,
        );
        assert.equal(
          (
            await request(
              `/me/workouts/${workoutId}/progress`,
              "PUT",
              { ...bad, exerciseLogs: [log()] },
              b.token,
            )
          ).status,
          404,
        );
        assert.equal(
          (await request("/me/workouts", "POST", plan(), a.token)).status,
          404,
        );
      },
    );
    await t.test(
      "completion requires all items and duplicate retries do not add history or revisions",
      async () => {
        const payload = {
          requestId: randomUUID(),
          revision: 0,
          status: "completed",
          exerciseLogs: [log(false)],
          notes: "Session feedback",
        };
        assert.equal(
          (
            await request(
              `/me/workouts/${workoutId}/progress`,
              "PUT",
              payload,
              a.token,
            )
          ).status,
          400,
        );
        payload.exerciseLogs = [log()];
        const first = await request(
          `/me/workouts/${workoutId}/progress`,
          "PUT",
          payload,
          a.token,
        );
        assert.equal(first.status, 200);
        revision = first.data.revision;
        const retry = await request(
          `/me/workouts/${workoutId}/progress`,
          "PUT",
          payload,
          a.token,
        );
        assert.equal(retry.data.duplicate, true);
        assert.equal(retry.data.revision, revision);
        assert.equal(
          (
            await request(
              `/me/workouts/${workoutId}/progress`,
              "PUT",
              { ...payload, notes: "Different" },
              a.token,
            )
          ).status,
          409,
        );
        assert.equal(
          (await request("/me/workouts/history", "GET", undefined, a.token))
            .data.workouts.length,
          1,
        );
      },
    );
    await t.test(
      "simultaneous saves with the same revision cannot overwrite each other",
      async () => {
        const body = {
          revision,
          status: "completed",
          exerciseLogs: [log()],
          notes: "First device",
        };
        const responses = await Promise.all([
          request(
            `/me/workouts/${workoutId}/progress`,
            "PUT",
            { ...body, requestId: randomUUID() },
            a.token,
          ),
          request(
            `/me/workouts/${workoutId}/progress`,
            "PUT",
            { ...body, notes: "Second device", requestId: randomUUID() },
            a.token,
          ),
        ]);
        assert.deepEqual(
          responses.map((response) => response.status).sort(),
          [200, 409],
        );
      },
    );
    await t.test(
      "new plan versions archive old edits while keeping saved history",
      async () => {
        const published = await service.publishPlan(
          a.id,
          plan(),
          "development_fixture",
        );
        assert.equal(published.version, 2);
        const old = await request(
          `/me/workouts/${workoutId}`,
          "GET",
          undefined,
          a.token,
        );
        assert.equal(old.data.workout.archived, true);
        assert.equal(
          (
            await request(
              `/me/workouts/${workoutId}/progress`,
              "PUT",
              {
                requestId: randomUUID(),
                revision: old.data.progress.revision,
                status: "completed",
                exerciseLogs: [log()],
                notes: "",
              },
              a.token,
            )
          ).status,
          409,
        );
        assert.equal(
          (await request("/me/workouts/history", "GET", undefined, a.token))
            .data.workouts.length,
          1,
        );
        const future = await service.publishPlan(
          b.id,
          plan(addDays(todayInIndia(), 1)),
          "development_fixture",
        );
        const futureWorkout = (
          await db.pool.query(
            "SELECT id FROM workout_sessions WHERE plan_id=$1",
            [future.planId],
          )
        ).rows[0].id;
        assert.equal(
          (
            await request(
              `/me/workouts/${futureWorkout}/progress`,
              "PUT",
              {
                requestId: randomUUID(),
                revision: 0,
                status: "skipped",
                exerciseLogs: [],
                notes: "",
              },
              b.token,
            )
          ).status,
          400,
        );
      },
    );
    await t.test(
      "signed playback supports ranges, suffixes, HEAD and rejects tampering",
      async () => {
        await db.pool.query("UPDATE exercises SET media_key=$1 WHERE id=$2", [
          "technical-test.mp4",
          exerciseId,
        ]);
        playbackPath = (
          await request(
            `/me/exercises/${exerciseId}/video`,
            "GET",
            undefined,
            a.token,
          )
        ).data.playbackPath;
        const full = await stream(playbackPath);
        assert.equal(full.status, 200);
        assert.equal(full.headers.get("content-type"), "video/mp4");
        assert.deepEqual(Buffer.from(await full.arrayBuffer()), video);
        const range = await stream(playbackPath, {
          headers: { Range: "bytes=0-15" },
        });
        assert.equal(range.status, 206);
        assert.deepEqual(
          Buffer.from(await range.arrayBuffer()),
          video.subarray(0, 16),
        );
        assert.equal(
          range.headers.get("content-range"),
          `bytes 0-15/${video.length}`,
        );
        const suffix = await stream(playbackPath, {
          headers: { Range: "bytes=-8" },
        });
        assert.deepEqual(
          Buffer.from(await suffix.arrayBuffer()),
          video.subarray(-8),
        );
        const head = await stream(playbackPath, { method: "HEAD" });
        assert.equal(head.status, 200);
        assert.equal(head.headers.get("content-length"), String(video.length));
        assert.equal((await head.arrayBuffer()).byteLength, 0);
        assert.equal(
          (
            await stream(playbackPath, {
              headers: { Range: "bytes=999999999-" },
            })
          ).status,
          416,
        );
        const tampered = new URL(playbackPath, "http://localhost");
        tampered.searchParams.set("uid", b.id);
        assert.equal(
          (await stream(tampered.pathname + tampered.search)).status,
          403,
        );
        tampered.searchParams.set("expires", "1000000000");
        assert.equal(
          (await stream(tampered.pathname + tampered.search)).status,
          403,
        );
      },
    );
    await t.test(
      "private files cannot escape the configured media root",
      async () => {
        await symlink("/etc/hostname", join(root, "escape.mp4"));
        linked = true;
        await db.pool.query("UPDATE exercises SET media_key=$1 WHERE id=$2", [
          "escape.mp4",
          exerciseId,
        ]);
        assert.equal(
          (
            await request(
              `/me/exercises/${exerciseId}/video`,
              "GET",
              undefined,
              a.token,
            )
          ).data.available,
          false,
        );
        await db.pool.query("UPDATE exercises SET media_key=$1 WHERE id=$2", [
          "../outside.mp4",
          exerciseId,
        ]);
        assert.equal(
          (
            await request(
              `/me/exercises/${exerciseId}/video`,
              "GET",
              undefined,
              a.token,
            )
          ).data.available,
          false,
        );
        await db.pool.query("UPDATE exercises SET media_key=$1 WHERE id=$2", [
          "technical-test.mp4",
          exerciseId,
        ]);
      },
    );
    await t.test(
      "expired membership revokes playback/workout access but keeps owned history",
      async () => {
        await db.pool.query(
          "UPDATE memberships SET starts_at=now()-interval '2 months',ends_at=now()-interval '1 second' WHERE customer_id=$1",
          [a.id],
        );
        assert.equal((await stream(playbackPath)).status, 403);
        assert.equal(
          (await request("/me/workouts", "GET", undefined, a.token)).status,
          403,
        );
        assert.equal(
          (await request("/me/workouts/history", "GET", undefined, a.token))
            .data.workouts.length,
          1,
        );
      },
    );
    await t.test(
      "saved logs survive an API restart and development content cannot publish in production",
      async () => {
        await app.close();
        app = await start();
        db = app.get(Database);
        service = app.get(WorkoutService);
        assert.equal(
          (await request("/me/workouts/history", "GET", undefined, a.token))
            .data.workouts.length,
          1,
        );
        process.env.NODE_ENV = "production";
        try {
          await assert.rejects(
            service.publishPlan(b.id, plan(), "development_fixture"),
            ForbiddenException,
          );
        } finally {
          process.env.NODE_ENV = "test";
        }
      },
    );
  } finally {
    if (users.length)
      await db.pool.query("DELETE FROM users WHERE id=ANY($1::uuid[])", [
        users,
      ]);
    await db.pool.query("DELETE FROM exercises WHERE id=ANY($1::text[])", [
      [exerciseId, draftId],
    ]);
    await app.close();
    if (linked) await unlink(join(root, "escape.mp4"));
    await unlink(videoPath);
    await rmdir(root);
    for (const [key, value] of Object.entries({
      NODE_ENV: previous.mode,
      ENABLE_DEV_MEMBERSHIPS: previous.memberships,
      ENABLE_DEV_WORKOUTS: previous.workouts,
      EXERCISE_MEDIA_ROOT: previous.root,
    })) {
      if (value === undefined) delete process.env[key];
      else process.env[key] = value;
    }
  }
});
