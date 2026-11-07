import "reflect-metadata";
import assert from "node:assert/strict";
import { randomUUID, createHash } from "node:crypto";
import type { AddressInfo } from "node:net";
import { test } from "node:test";
import { NestFactory } from "@nestjs/core";
import { AppModule } from "../src/app.module";
import { Database } from "../src/database";

test("accounts, persistence, session lifecycle and customer/trainer isolation", async (t) => {
  const start = async () => {
    const app = await NestFactory.create(AppModule, { logger: false });
    app.setGlobalPrefix("api/v1");
    await app.listen(0, "127.0.0.1");
    return app;
  };
  let app = await start();
  let db = app.get(Database);
  const ids: string[] = [];
  const email = `integration-${randomUUID()}@example.test`;
  const password = "A-test-password-42!";
  const request = async (
    path: string,
    method = "GET",
    body?: unknown,
    token?: string,
  ) => {
    const port = (app.getHttpServer().address() as AddressInfo).port;
    const response = await fetch(`http://127.0.0.1:${port}/api/v1${path}`, {
      method,
      headers: {
        "Content-Type": "application/json",
        ...(token ? { Authorization: `Bearer ${token}` } : {}),
      },
      ...(body !== undefined ? { body: JSON.stringify(body) } : {}),
    });
    return { status: response.status, data: await response.json() };
  };
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
    currentRoutine: "Walking three days a week",
    limitations: "",
    foodNotes: "",
    healthDataConsent: true,
    shareWithTrainer: false,
    shareCoachingWithTrainer: false,
  };
  let token = "";
  let customerId = "";
  let secondToken = "";
  let trainerToken = "";
  let trainerId = "";
  try {
    await t.test(
      "registration rejects role injection and hashes credentials",
      async () => {
        assert.equal(
          (
            await request("/auth/register", "POST", {
              email,
              password,
              displayName: "Test",
              role: "admin",
            })
          ).status,
          400,
        );
        const registered = await request("/auth/register", "POST", {
          email: ` ${email.toUpperCase()} `,
          password,
          displayName: "Test Customer",
        });
        assert.equal(registered.status, 201);
        token = registered.data.token;
        customerId = registered.data.user.id;
        ids.push(customerId);
        assert.equal(registered.data.user.email, email);
        assert.equal(registered.data.user.role, "customer");
        assert.equal(registered.data.user.password_hash, undefined);
        const saved = (
          await db.pool.query("SELECT password_hash FROM users WHERE id=$1", [
            customerId,
          ])
        ).rows[0];
        assert.ok(saved.password_hash.startsWith("scrypt$"));
        assert.notEqual(saved.password_hash, password);
        const session = (
          await db.pool.query(
            "SELECT token_hash FROM sessions WHERE user_id=$1",
            [customerId],
          )
        ).rows[0];
        assert.equal(
          session.token_hash,
          createHash("sha256").update(token).digest("hex"),
        );
        assert.equal(
          (
            await request("/auth/register", "POST", {
              email,
              password,
              displayName: "Duplicate",
            })
          ).status,
          409,
        );
      },
    );
    await t.test(
      "profiles require authentication, valid fields and consent",
      async () => {
        assert.equal((await request("/me/profile")).status, 401);
        assert.equal(
          (
            await request(
              "/me/profile",
              "PUT",
              { ...profile, healthDataConsent: false },
              token,
            )
          ).status,
          400,
        );
        assert.equal(
          (
            await request(
              "/me/profile",
              "PUT",
              { ...profile, heightCm: -1 },
              token,
            )
          ).status,
          400,
        );
        assert.equal(
          (
            await request(
              "/me/profile",
              "PUT",
              { ...profile, workoutDays: [1, 1] },
              token,
            )
          ).status,
          400,
        );
        assert.equal(
          (await request("/me/profile", "PUT", profile, token)).status,
          200,
        );
        assert.deepEqual(
          (await request("/me/profile", "GET", undefined, token)).data.profile,
          profile,
        );
      },
    );
    await t.test(
      "another customer cannot read or replace this profile",
      async () => {
        const second = await request("/auth/register", "POST", {
          email: `second-${randomUUID()}@example.test`,
          password,
          displayName: "Second",
        });
        assert.equal(second.status, 201);
        ids.push(second.data.user.id);
        secondToken = second.data.token;
        assert.equal(
          (await request("/me/profile", "GET", undefined, secondToken)).data
            .profile,
          null,
        );
        assert.equal(
          (
            await request(
              "/me/profile",
              "PUT",
              { ...profile, userId: customerId },
              secondToken,
            )
          ).status,
          400,
        );
        assert.equal(
          (
            await request(
              `/coach/customers/${customerId}/profile`,
              "GET",
              undefined,
              secondToken,
            )
          ).status,
          403,
        );
        assert.deepEqual(
          (await request("/me/profile", "GET", undefined, token)).data.profile,
          profile,
        );
      },
    );
    await t.test(
      "trainer access requires assignment and customer sharing consent",
      async () => {
        const trainer = await request("/auth/register", "POST", {
          email: `trainer-${randomUUID()}@example.test`,
          password,
          displayName: "Trainer fixture",
        });
        assert.equal(trainer.status, 201);
        trainerId = trainer.data.user.id;
        trainerToken = trainer.data.token;
        ids.push(trainerId);
        await db.pool.query("UPDATE users SET role=$1 WHERE id=$2", [
          "trainer",
          trainerId,
        ]);
        const path = `/coach/customers/${customerId}/profile`;
        assert.equal(
          (await request(path, "GET", undefined, trainerToken)).status,
          404,
        );
        await db.pool.query(
          "INSERT INTO trainer_assignments(trainer_id,customer_id) VALUES($1,$2)",
          [trainerId, customerId],
        );
        assert.equal(
          (await request(path, "GET", undefined, trainerToken)).status,
          404,
        );
        await request(
          "/me/profile",
          "PUT",
          { ...profile, shareWithTrainer: true },
          token,
        );
        assert.equal(
          (await request(path, "GET", undefined, trainerToken)).status,
          200,
        );
        await request("/me/profile", "PUT", profile, token);
        assert.equal(
          (await request(path, "GET", undefined, trainerToken)).status,
          404,
        );
      },
    );
    await t.test("profile and sessions survive an API restart", async () => {
      await app.close();
      app = await start();
      db = app.get(Database);
      assert.deepEqual(
        (await request("/auth/me", "GET", undefined, token)).data.profile,
        profile,
      );
    });
    await t.test(
      "wrong passwords fail; login restores saved profile; logout revokes session",
      async () => {
        assert.equal(
          (
            await request("/auth/login", "POST", {
              email,
              password: "incorrect-password",
            })
          ).status,
          401,
        );
        const login = await request("/auth/login", "POST", { email, password });
        assert.equal(login.status, 200);
        assert.deepEqual(login.data.profile, profile);
        assert.equal(
          (await request("/auth/logout", "POST", {}, login.data.token)).status,
          200,
        );
        assert.equal(
          (await request("/auth/me", "GET", undefined, login.data.token))
            .status,
          401,
        );
        await db.pool.query(
          "UPDATE sessions SET expires_at=now()-interval '1 second' WHERE token_hash=$1",
          [createHash("sha256").update(token).digest("hex")],
        );
        assert.equal(
          (await request("/auth/me", "GET", undefined, token)).status,
          401,
        );
      },
    );
    await t.test("repeated login attempts are limited", async () => {
      for (let index = 0; index < 31; index++)
        await request("/auth/login", "POST", {});
      assert.equal((await request("/auth/login", "POST", {})).status, 429);
    });
  } finally {
    if (ids.length)
      await db.pool.query("DELETE FROM users WHERE id=ANY($1::uuid[])", [ids]);
    await app.close();
  }
});
