import "reflect-metadata";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import type { AddressInfo } from "node:net";
import { test } from "node:test";
import { NestFactory } from "@nestjs/core";
import {
  ForbiddenException,
  BadRequestException,
  ConflictException,
  NotFoundException,
} from "@nestjs/common";
import { AppModule } from "../src/app.module";
import { Database } from "../src/database";
import { MembershipService } from "../src/memberships";
import { plans } from "../src/plans";
import { baseEntitlements } from "../src/membership-policy";

test("membership activation, renewal, expiry and session-ledger invariants", async (t) => {
  const originalMode = process.env.NODE_ENV;
  const originalFlag = process.env.ENABLE_DEV_MEMBERSHIPS;
  process.env.NODE_ENV = "test";
  process.env.ENABLE_DEV_MEMBERSHIPS = "true";
  const start = async () => {
    const app = await NestFactory.create(AppModule, { logger: false });
    app.setGlobalPrefix("api/v1");
    await app.listen(0, "127.0.0.1");
    return app;
  };
  let app = await start();
  let db = app.get(Database);
  let service = app.get(MembershipService);
  const ids: string[] = [];
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
      ...(body === undefined ? {} : { body: JSON.stringify(body) }),
    });
    return { status: response.status, data: await response.json() };
  };
  const customer = async () => {
    const result = await request("/auth/register", "POST", {
      email: `membership-${randomUUID()}@example.test`,
      password: "A-test-password-42!",
      displayName: "Membership fixture",
    });
    assert.equal(result.status, 201);
    ids.push(result.data.user.id);
    return {
      id: result.data.user.id as string,
      token: result.data.token as string,
    };
  };
  const purchase = (
    customerId: string,
    planId: "normal" | "premium" | "premium-plus",
  ) => ({
    customerId,
    planId,
    eventId: randomUUID(),
    paymentReference: randomUUID(),
    amountPaise: plans.find((plan) => plan.id === planId)!.priceInPaise,
    currency: "INR" as const,
  });
  try {
    const normal = await customer();
    const premium = await customer();
    const plus = await customer();
    let premiumId = "";
    let plusId = "";
    await t.test(
      "membership reads require a customer session and no customer can activate a purchase",
      async () => {
        assert.equal((await request("/me/membership")).status, 401);
        const summary = await request(
          "/me/membership",
          "GET",
          undefined,
          normal.token,
        );
        assert.equal(summary.status, 200);
        assert.equal(summary.data.status, "none");
        assert.ok(
          Object.values(summary.data.entitlements).every(
            (value) => value === false,
          ),
        );
        assert.equal(summary.data.billing.checkoutEnabled, false);
        assert.equal(
          (
            await request(
              "/me/membership",
              "POST",
              { planId: "premium", paid: true },
              normal.token,
            )
          ).status,
          404,
        );
        assert.equal(
          (await request("/billing/webhook", "POST", { paid: true })).status,
          404,
        );
      },
    );
    await t.test(
      "development grants require opt-in and the exact server-side price",
      async () => {
        process.env.ENABLE_DEV_MEMBERSHIPS = "false";
        await assert.rejects(
          service.applyTestPurchase(purchase(normal.id, "normal")),
          ForbiddenException,
        );
        process.env.ENABLE_DEV_MEMBERSHIPS = "true";
        await assert.rejects(
          service.applyTestPurchase({
            ...purchase(normal.id, "normal"),
            amountPaise: 1,
          }),
          BadRequestException,
        );
        assert.equal((await service.summary(normal.id)).status, "none");
      },
    );
    await t.test(
      "base membership grants inherited features but no live video sessions",
      async () => {
        await service.applyTestPurchase(purchase(normal.id, "normal"));
        const summary = await service.summary(normal.id);
        assert.equal(summary.status, "active");
        assert.deepEqual(summary.entitlements, baseEntitlements);
        assert.equal(summary.current!.videoSessionsRemaining, 0);
        assert.equal(
          summary.current!.paymentStatus,
          "test_no_payment_collected",
        );
        await assert.rejects(
          service.recordCompletedVideoSession(
            normal.id,
            summary.current!.id,
            "not-included",
          ),
          ForbiddenException,
        );
      },
    );
    await t.test(
      "concurrent duplicate receipts and new delivery IDs activate only one period",
      async () => {
        const input = purchase(premium.id, "premium");
        const results = await Promise.all([
          service.applyTestPurchase(input),
          service.applyTestPurchase(input),
          service.applyTestPurchase(input),
        ]);
        premiumId = results[0].membershipId;
        assert.equal(results.filter((result) => !result.duplicate).length, 1);
        const replay = await service.applyTestPurchase({
          ...input,
          eventId: randomUUID(),
        });
        assert.equal(replay.membershipId, premiumId);
        assert.equal(replay.duplicate, true);
        await assert.rejects(
          service.applyTestPurchase({
            ...input,
            paymentReference: randomUUID(),
          }),
          ConflictException,
        );
        await assert.rejects(
          service.applyTestPurchase({
            ...purchase(plus.id, "premium"),
            eventId: input.eventId,
          }),
          ConflictException,
        );
        assert.equal((await service.summary(premium.id)).history.length, 1);
        assert.equal((await service.summary(plus.id)).history.length, 0);
      },
    );
    await t.test(
      "video completions are idempotent and cannot overspend a 10-session allowance",
      async () => {
        await service.recordCompletedVideoSession(
          premium.id,
          premiumId,
          "first-session",
        );
        assert.equal(
          (
            await service.recordCompletedVideoSession(
              premium.id,
              premiumId,
              "first-session",
            )
          ).duplicate,
          true,
        );
        const outcomes = await Promise.allSettled(
          Array.from({ length: 15 }, (_, index) =>
            service.recordCompletedVideoSession(
              premium.id,
              premiumId,
              `concurrent-${index}`,
            ),
          ),
        );
        assert.equal(
          outcomes.filter((result) => result.status === "fulfilled").length,
          9,
        );
        assert.equal(
          outcomes.filter((result) => result.status === "rejected").length,
          6,
        );
        const summary = await service.summary(premium.id);
        assert.equal(summary.current!.videoSessionsUsed, 10);
        assert.equal(summary.current!.videoSessionsRemaining, 0);
      },
    );
    await t.test(
      "early renewal queues a new period without resetting the current balance",
      async () => {
        const previous = (await service.summary(premium.id)).current!;
        await service.applyTestPurchase(purchase(premium.id, "premium"));
        const summary = await service.summary(premium.id);
        assert.equal(summary.current!.id, previous.id);
        assert.equal(summary.current!.videoSessionsRemaining, 0);
        assert.equal(summary.next!.startsAt, previous.endsAt);
        assert.equal(summary.next!.videoSessionsRemaining, 10);
        assert.equal(summary.history.length, 2);
        await assert.rejects(
          service.applyTestPurchase(purchase(premium.id, "premium-plus")),
          ConflictException,
        );
        assert.equal((await service.summary(premium.id)).history.length, 2);
      },
    );
    await t.test(
      "Premium Plus includes lower-tier features with 25 total sessions, not 35",
      async () => {
        plusId = (
          await service.applyTestPurchase(purchase(plus.id, "premium-plus"))
        ).membershipId;
        assert.equal(
          (await service.summary(plus.id)).current!.videoSessionsTotal,
          25,
        );
        assert.deepEqual(
          (await service.summary(plus.id)).entitlements,
          baseEntitlements,
        );
        const outcomes = await Promise.allSettled(
          Array.from({ length: 28 }, (_, index) =>
            service.recordCompletedVideoSession(
              plus.id,
              plusId,
              `plus-${index}`,
            ),
          ),
        );
        assert.equal(
          outcomes.filter((result) => result.status === "fulfilled").length,
          25,
        );
        assert.equal(
          (await service.summary(plus.id)).current!.videoSessionsRemaining,
          0,
        );
      },
    );
    await t.test(
      "customer identities cannot be overridden and another membership cannot be consumed",
      async () => {
        const result = await request(
          `/me/membership?customerId=${premium.id}`,
          "GET",
          undefined,
          normal.token,
        );
        assert.equal(result.data.current.planId, "normal");
        assert.equal(result.data.current.videoSessionsTotal, 0);
        await assert.rejects(
          service.recordCompletedVideoSession(
            normal.id,
            premiumId,
            "foreign-session",
          ),
          NotFoundException,
        );
      },
    );
    await t.test(
      "expiry removes entitlements, preserves history, and renewal starts a fresh allowance",
      async () => {
        await db.pool.query(
          "UPDATE memberships SET starts_at=now()-interval '2 months',ends_at=now()-interval '1 second' WHERE id=$1",
          [plusId],
        );
        const expired = await service.summary(plus.id);
        assert.equal(expired.status, "expired");
        assert.equal(expired.current, null);
        assert.equal(expired.history[0].videoSessionsUsed, 25);
        await assert.rejects(
          service.requireEntitlement(plus.id, "storedExerciseVideos"),
          ForbiddenException,
        );
        await assert.rejects(
          service.recordCompletedVideoSession(plus.id, plusId, "after-expiry"),
          ForbiddenException,
        );
        await service.applyTestPurchase(purchase(plus.id, "premium-plus"));
        const renewed = await service.summary(plus.id);
        assert.equal(renewed.current!.videoSessionsRemaining, 25);
        assert.equal(renewed.history.length, 2);
        await service.requireEntitlement(plus.id, "storedExerciseVideos");
      },
    );
    await t.test(
      "development fixtures cannot grant or expose paid access in production",
      async () => {
        process.env.NODE_ENV = "production";
        try {
          assert.equal((await service.summary(normal.id)).current, null);
          assert.equal((await service.summary(normal.id)).history.length, 0);
          await assert.rejects(
            service.applyTestPurchase(purchase(normal.id, "normal")),
            ForbiddenException,
          );
          await assert.rejects(
            service.requireEntitlement(normal.id, "aiCoaching"),
            ForbiddenException,
          );
        } finally {
          process.env.NODE_ENV = "test";
        }
      },
    );
    await t.test(
      "membership periods and completed balances survive API restart",
      async () => {
        await app.close();
        app = await start();
        db = app.get(Database);
        service = app.get(MembershipService);
        const summary = await request(
          "/me/membership",
          "GET",
          undefined,
          premium.token,
        );
        assert.equal(summary.status, 200);
        assert.equal(summary.data.current.videoSessionsUsed, 10);
        assert.equal(summary.data.next.videoSessionsTotal, 10);
      },
    );
  } finally {
    if (ids.length)
      await db.pool.query("DELETE FROM users WHERE id=ANY($1::uuid[])", [ids]);
    await app.close();
    if (originalMode === undefined) delete process.env.NODE_ENV;
    else process.env.NODE_ENV = originalMode;
    if (originalFlag === undefined) delete process.env.ENABLE_DEV_MEMBERSHIPS;
    else process.env.ENABLE_DEV_MEMBERSHIPS = originalFlag;
  }
});
