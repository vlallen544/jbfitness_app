import { readdir, readFile } from "node:fs/promises";
import { resolve } from "node:path";
import { Pool, type PoolClient } from "pg";
import { migrationFailure } from "./migration-error";

let stage = "configuration";
async function migrate() {
  if (!process.env.DATABASE_URL) {
    console.error("Migration configuration error: DATABASE_URL is missing. Set it in the hosting service's private environment variables.");
    process.exitCode = 1;
    return;
  }
  const pool = new Pool({
    connectionString: process.env.DATABASE_URL,
    connectionTimeoutMillis: 5000,
  });
  let client: PoolClient | undefined;
  let locked = false;
  try {
    stage = "database connection";
    client = await pool.connect();
    stage = "migration lock";
    await client.query("SELECT pg_advisory_lock(73121501)");
    locked = true;
    stage = "migration table setup";
    await client.query(
      "CREATE TABLE IF NOT EXISTS schema_migrations (version text PRIMARY KEY, applied_at timestamptz NOT NULL DEFAULT now())",
    );
    const folder = resolve(process.cwd(), "migrations");
    for (const file of (await readdir(folder))
      .filter((name) => /^\d+.*\.sql$/.test(name))
      .sort()) {
      stage = `migration ${file}`;
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
    try {
      if (client && locked) await client.query("SELECT pg_advisory_unlock(73121501)");
    } finally {
      client?.release();
      await pool.end();
    }
  }
}
migrate().catch((error: unknown) => {
  console.error(migrationFailure(error, stage));
  process.exitCode = 1;
});
