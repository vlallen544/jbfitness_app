import "reflect-metadata";
import { randomUUID } from "node:crypto";
import { parseArgs } from "node:util";
import { Database } from "../src/database";
import { MembershipService } from "../src/memberships";
import { plans } from "../src/plans";

async function main() {
  if (
    process.env.NODE_ENV === "production" ||
    process.env.ENABLE_DEV_MEMBERSHIPS !== "true"
  )
    throw new Error(
      "Explicit ENABLE_DEV_MEMBERSHIPS=true is required outside production.",
    );
  const { values } = parseArgs({
    options: { email: { type: "string" }, plan: { type: "string" } },
  });
  const plan = plans.find((item) => item.id === values.plan);
  if (!values.email || !plan)
    throw new Error(
      "Use --email customer@example.test --plan normal|premium|premium-plus",
    );
  const db = new Database();
  try {
    const customer = (
      await db.pool.query("SELECT id FROM users WHERE email=$1 AND role=$2", [
        values.email.trim().toLowerCase(),
        "customer",
      ])
    ).rows[0];
    if (!customer) throw new Error("Register the test customer first.");
    await new MembershipService(db).applyTestPurchase({
      customerId: customer.id,
      planId: plan.id,
      eventId: `fixture-event-${randomUUID()}`,
      paymentReference: `fixture-payment-${randomUUID()}`,
      amountPaise: plan.priceInPaise,
      currency: "INR",
    });
    console.log(
      "Development test membership recorded. No payment collected. Refresh the Plans screen.",
    );
  } finally {
    await db.pool.end();
  }
}
main().catch((error: Error) => {
  console.error(error.message);
  process.exitCode = 1;
});
