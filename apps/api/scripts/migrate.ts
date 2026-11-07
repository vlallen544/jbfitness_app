import { readdir, readFile } from "node:fs/promises";
import { resolve } from "node:path";
import { Pool } from "pg";

async function migrate() {
  if (!process.env.DATABASE_URL)
    throw new Error("Set DATABASE_URL; run npm run setup:db first.");
  const pool = new Pool({
    connectionString: process.env.DATABASE_URL,
    connectionTimeoutMillis: 5000,
  });
  const client = await pool.connect();
  try {
    await client.query("SELECT pg_advisory_lock(73121501)");
    await client.query(
      "CREATE TABLE IF NOT EXISTS schema_migrations (version text PRIMARY KEY, applied_at timestamptz NOT NULL DEFAULT now())",
    );
    const folder = resolve(process.cwd(), "migrations");
    for (const file of (await readdir(folder))
      .filter((name) => /^\d+.*\.sql$/.test(name))
      .sort()) {
      if (
        (
          await client.query(
            "SELECT 1 FROM schema_migrations WHERE version=$1",
            [file],
          )
        ).rowCount
      )
        continue;
      await client.query("BEGIN");
      try {
        await client.query(await readFile(resolve(folder, file), "utf8"));
        await client.query(
          "INSERT INTO schema_migrations(version) VALUES($1)",
          [file],
        );
        await client.query("COMMIT");
        console.log(`Applied ${file}`);
      } catch (error) {
        await client.query("ROLLBACK");
        throw error;
      }
    }
    console.log("Database migrations are up to date.");
  } finally {
    await client.query("SELECT pg_advisory_unlock(73121501)");
    client.release();
    await pool.end();
  }
}
migrate().catch(() => {
  console.error(
    "Migration failed. Check database connectivity and migration state.",
  );
  process.exitCode = 1;
});
