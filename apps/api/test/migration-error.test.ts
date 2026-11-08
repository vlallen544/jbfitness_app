import { strict as assert } from "node:assert";
import { test } from "node:test";
import { migrationFailure } from "../scripts/migration-error";

test("migration diagnostics identify connection failures without logging secrets", () => {
  for (const code of ["28P01", "ENOTFOUND", "ENETUNREACH", "SELF_SIGNED_CERT_IN_CHAIN", "42501"]) {
    const message = migrationFailure({ code, message: "postgres://user:PRIVATE_PASSWORD@host/db", detail: "PRIVATE_CUSTOMER_DATA" }, "database connection");
    assert.ok(message.includes(`[${code}]`));
    assert.ok(!message.includes("PRIVATE_"));
    assert.ok(!message.includes("postgres://"));
  }
});

test("nested network failures are classified and unknown driver messages stay private", () => {
  const nested = new AggregateError([{ code: "ENETUNREACH", message: "PRIVATE_PASSWORD" }]);
  assert.match(migrationFailure(nested, "database connection"), /ENETUNREACH/);
  assert.match(migrationFailure({cause:{code:"28P01"}}, "database connection"), /28P01/);
  const unknown = new Error("PRIVATE_PASSWORD");
  (unknown as Error & {cause: unknown}).cause = unknown;
  const message = migrationFailure(unknown, "migration 001_accounts.sql");
  assert.match(message, /001_accounts.sql/);
  assert.ok(!message.includes("PRIVATE_PASSWORD"));
});
