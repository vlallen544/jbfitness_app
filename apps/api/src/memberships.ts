import {
  BadRequestException,
  ConflictException,
  Controller,
  ForbiddenException,
  Get,
  Inject,
  Injectable,
  NotFoundException,
  Req,
  UseGuards,
} from "@nestjs/common";
import { createHash, randomUUID } from "node:crypto";
import { z } from "zod";
import type { PoolClient } from 'pg';
import { Database } from "./database";
import { AuthGuard, User } from "./auth";
import { plans } from "./plans";
import {
  baseEntitlements,
  developmentMembershipPolicy,
  Entitlement,
  oneCalendarMonthAfter,
} from "./membership-policy";

const testPurchaseSchema = z
  .object({
    customerId: z.uuid(),
    planId: z.enum(["normal", "premium", "premium-plus"]),
    eventId: z.string().min(1).max(200),
    paymentReference: z.string().min(1).max(200),
    amountPaise: z.number().int().positive(),
    currency: z.literal("INR"),
  })
  .strict();
type TestPurchase = z.infer<typeof testPurchaseSchema>;
type MembershipRow = {
  id: string;
  customer_id: string;
  plan_snapshot: {
    id: string;
    name: string;
    priceInPaise: number;
    entitlements: typeof baseEntitlements;
  };
  starts_at: Date;
  ends_at: Date;
  video_sessions_total: number;
  revoked_at: Date | null;
  environment: string;
  used: number;
  reserved: number;
};

@Injectable()
export class MembershipService {
  constructor(@Inject(Database) private readonly db: Database) {}

  // Only an explicit local CLI/test can call this. There is no HTTP grant endpoint.
  // Real billing must supply a separate server-verified provider adapter before checkout is enabled.
  async applyTestPurchase(input: TestPurchase) {
    if (
      process.env.NODE_ENV === "production" ||
      process.env.ENABLE_DEV_MEMBERSHIPS !== "true"
    )
      throw new ForbiddenException(
        "Development membership fixtures are disabled.",
      );
    const parsed = testPurchaseSchema.safeParse(input);
    if (!parsed.success)
      throw new BadRequestException("Invalid development purchase.");
    const purchase = parsed.data;
    const plan = plans.find((item) => item.id === purchase.planId)!;
    if (purchase.amountPaise !== plan.priceInPaise)
      throw new BadRequestException(
        "Amount does not match the server plan price.",
      );
    const fingerprint = createHash("sha256")
      .update(
        JSON.stringify([
          purchase.customerId,
          purchase.planId,
          purchase.amountPaise,
          purchase.currency,
        ]),
      )
      .digest("hex");
    const client = await this.db.pool.connect();
    try {
      await client.query("BEGIN");
      const customer = await client.query(
        "SELECT role FROM users WHERE id=$1 FOR UPDATE",
        [purchase.customerId],
      );
      if (customer.rows[0]?.role !== "customer")
        throw new BadRequestException("A customer account is required.");
      const previousEvent = await client.query(
        "SELECT r.id,r.payload_hash FROM membership_events e JOIN membership_receipts r ON r.id=e.receipt_id WHERE e.event_id=$1",
        [purchase.eventId],
      );
      if (
        previousEvent.rows[0] &&
        previousEvent.rows[0].payload_hash !== fingerprint
      )
        throw new ConflictException(
          "Purchase event does not match its original customer or plan.",
        );
      if (previousEvent.rows[0]) {
        const receipt = await client.query(
          "SELECT payment_reference FROM membership_receipts WHERE id=$1",
          [previousEvent.rows[0].id],
        );
        if (receipt.rows[0].payment_reference !== purchase.paymentReference)
          throw new ConflictException(
            "Purchase event has a different payment reference.",
          );
      }
      await client.query(
        `INSERT INTO membership_receipts(id,payment_reference,customer_id,plan_id,amount_paise,currency,environment,payload_hash) VALUES($1,$2,$3,$4,$5,$6,'development',$7) ON CONFLICT(payment_reference) DO NOTHING`,
        [
          randomUUID(),
          purchase.paymentReference,
          purchase.customerId,
          plan.id,
          plan.priceInPaise,
          purchase.currency,
          fingerprint,
        ],
      );
      const receipt = (
        await client.query(
          "SELECT id,payload_hash FROM membership_receipts WHERE payment_reference=$1 FOR UPDATE",
          [purchase.paymentReference],
        )
      ).rows[0];
      if (receipt.payload_hash !== fingerprint)
        throw new ConflictException(
          "Payment reference belongs to a different purchase.",
        );
      await client.query(
        "INSERT INTO membership_events(event_id,receipt_id) VALUES($1,$2) ON CONFLICT(event_id) DO NOTHING",
        [purchase.eventId, receipt.id],
      );
      const event = (
        await client.query(
          "SELECT receipt_id FROM membership_events WHERE event_id=$1",
          [purchase.eventId],
        )
      ).rows[0];
      if (event.receipt_id !== receipt.id)
        throw new ConflictException(
          "Event reference belongs to another purchase.",
        );
      const existing = (
        await client.query("SELECT id FROM memberships WHERE receipt_id=$1", [
          receipt.id,
        ])
      ).rows[0];
      if (existing) {
        await client.query("COMMIT");
        return { membershipId: existing.id as string, duplicate: true };
      }
      const now = new Date();
      const latest = (
        await client.query(
          "SELECT ends_at,plan_snapshot FROM memberships WHERE customer_id=$1 AND revoked_at IS NULL AND ends_at>$2 ORDER BY ends_at DESC LIMIT 1",
          [purchase.customerId, now],
        )
      ).rows[0];
      if (latest && latest.plan_snapshot.id !== plan.id)
        throw new ConflictException(
          "Plan changes are not enabled while a membership period is active or scheduled.",
        );
      const startsAt: Date = latest?.ends_at ?? now;
      const endsAt = oneCalendarMonthAfter(startsAt);
      const membershipId = randomUUID();
      await client.query(
        "INSERT INTO memberships(id,customer_id,receipt_id,plan_snapshot,starts_at,ends_at,video_sessions_total) VALUES($1,$2,$3,$4,$5,$6,$7)",
        [
          membershipId,
          purchase.customerId,
          receipt.id,
          { ...plan, entitlements: baseEntitlements },
          startsAt,
          endsAt,
          plan.videoSessions,
        ],
      );
      await client.query("COMMIT");
      return { membershipId, duplicate: false };
    } catch (error) {
      await client.query("ROLLBACK");
      throw error;
    } finally {
      client.release();
    }
  }

  async summary(customerId: string, connection: Pick<PoolClient, 'query'> = this.db.pool) {
    const rows = (
      await connection.query<MembershipRow>(
        `SELECT m.*,r.environment,count(l.id)::int AS used,(SELECT count(*)::int FROM coaching_bookings b WHERE b.membership_id=m.id AND b.status='booked') AS reserved FROM memberships m JOIN membership_receipts r ON r.id=m.receipt_id LEFT JOIN membership_session_ledger l ON l.membership_id=m.id WHERE m.customer_id=$1 AND (r.environment<>'development' OR $2=false) GROUP BY m.id,r.environment ORDER BY m.starts_at DESC,m.id`,
        [customerId, process.env.NODE_ENV === "production"],
      )
    ).rows;
    const now = new Date();
    const state = (row: MembershipRow) =>
      row.revoked_at
        ? "revoked"
        : row.starts_at > now
          ? "scheduled"
          : row.ends_at <= now
            ? "expired"
            : "active";
    const view = (row: MembershipRow) => ({
      id: row.id,
      planId: row.plan_snapshot.id,
      planName: row.plan_snapshot.name,
      priceInPaise: row.plan_snapshot.priceInPaise,
      currency: "INR",
      startsAt: row.starts_at.toISOString(),
      endsAt: row.ends_at.toISOString(),
      status: state(row),
      videoSessionsTotal: row.video_sessions_total,
      videoSessionsUsed: row.used,
      videoSessionsReserved: row.reserved,
      videoSessionsRemaining: Math.max(0, row.video_sessions_total - row.used - row.reserved),
      environment: row.environment,
      paymentStatus:
        row.environment === "development"
          ? "test_no_payment_collected"
          : "verified",
    });
    const current = rows.find((row) => state(row) === "active");
    const next = rows
      .filter((row) => state(row) === "scheduled")
      .sort((a, b) => a.starts_at.getTime() - b.starts_at.getTime())[0];
    return {
      status: current
        ? "active"
        : next
          ? "scheduled"
          : rows.some((row) => state(row) === "expired")
            ? "expired"
            : "none",
      current: current ? view(current) : null,
      next: next ? view(next) : null,
      history: rows.map(view),
      entitlements: Object.fromEntries(
        Object.keys(baseEntitlements).map((key) => [
          key,
          current?.plan_snapshot.entitlements[key as Entitlement] === true,
        ]),
      ),
      billing: {
        checkoutEnabled: false,
        providerConfigured: false,
        policy: developmentMembershipPolicy,
      },
      serverTime: now.toISOString(),
    };
  }

  async requireEntitlement(customerId: string, capability: Entitlement) {
    const summary = await this.summary(customerId);
    if (!summary.entitlements[capability])
      throw new ForbiddenException(
        "An active membership with this feature is required.",
      );
    return summary.current!;
  }

  // Called by the future trusted coaching completion handler, never by a customer endpoint.
  async recordCompletedVideoSession(
    customerId: string,
    membershipId: string,
    sessionReference: string,
  ) {
    const reference = z.string().trim().min(1).max(200).safeParse(sessionReference);
    if (
      !z.uuid().safeParse(membershipId).success ||
      !reference.success
    )
      throw new BadRequestException("Invalid video session reference.");
    sessionReference = reference.data;
    const client = await this.db.pool.connect();
    try {
      await client.query("BEGIN");
      const row = (
        await client.query(
          `SELECT m.*,r.environment FROM memberships m JOIN membership_receipts r ON r.id=m.receipt_id WHERE m.id=$1 AND m.customer_id=$2 FOR UPDATE OF m`,
          [membershipId, customerId],
        )
      ).rows[0];
      if (
        !row ||
        (process.env.NODE_ENV === "production" &&
          row.environment === "development")
      )
        throw new NotFoundException("Membership is unavailable.");
      const duplicate = (
        await client.query(
          "SELECT membership_id FROM membership_session_ledger WHERE customer_id=$1 AND session_reference=$2",
          [customerId, sessionReference],
        )
      ).rows[0];
      if (duplicate) {
        if (duplicate.membership_id !== membershipId)
          throw new ConflictException(
            "Session reference was already used in another membership.",
          );
        await client.query("COMMIT");
        return { duplicate: true };
      }
      const now = new Date();
      if (row.revoked_at || row.starts_at > now || row.ends_at <= now)
        throw new ForbiddenException("An active membership is required.");
      const count = Number(
        (
          await client.query(
            "SELECT count(*) FROM membership_session_ledger WHERE membership_id=$1",
            [membershipId],
          )
        ).rows[0].count,
      );
      const reserved = (await client.query("SELECT count(*)::int AS n FROM coaching_bookings WHERE membership_id=$1 AND status='booked'", [membershipId])).rows[0].n;
      if (count + reserved >= row.video_sessions_total)
        throw new ForbiddenException(
          "No video sessions remain in this membership period.",
        );
      await client.query(
        "INSERT INTO membership_session_ledger(id,membership_id,customer_id,session_reference) VALUES($1,$2,$3,$4)",
        [randomUUID(), membershipId, customerId, sessionReference],
      );
      await client.query("COMMIT");
      return { duplicate: false };
    } catch (error) {
      await client.query("ROLLBACK");
      throw error;
    } finally {
      client.release();
    }
  }
}

@Controller("me/membership")
@UseGuards(AuthGuard)
export class MembershipController {
  constructor(
    @Inject(MembershipService) private readonly memberships: MembershipService,
  ) {}
  @Get() summary(@Req() request: { user: User }) {
    if (request.user.role !== "customer")
      throw new ForbiddenException("Customer account required.");
    return this.memberships.summary(request.user.id);
  }
}
