import { randomBytes } from "node:crypto";
import { readFile, writeFile, mkdir } from "node:fs/promises";

const infra = new URL("../infra/", import.meta.url);
const dbEnv = new URL(".env", infra);
const apiEnv = new URL("../apps/api/.env", import.meta.url);
await mkdir(infra, { recursive: true });
let secret;
try {
  secret = (await readFile(dbEnv, "utf8")).match(
    /^POSTGRES_PASSWORD=([a-f0-9]+)$/m,
  )?.[1];
  if (!secret)
    throw new Error(
      "Existing infra/.env has an unsupported password format; configure DATABASE_URL manually.",
    );
} catch (error) {
  if (error.code !== "ENOENT") throw error;
  secret = randomBytes(32).toString("hex");
  await writeFile(dbEnv, `POSTGRES_PASSWORD=${secret}\n`, {
    mode: 0o600,
    flag: "wx",
  });
}
try {
  await writeFile(
    apiEnv,
    `DATABASE_URL=postgresql://jbfitness:${secret}@127.0.0.1:55432/jbfitness\nPORT=3001\nHOST=127.0.0.1\n`,
    { mode: 0o600, flag: "wx" },
  );
  console.log(
    "Created private local database configuration. Credentials are not printed.",
  );
} catch (error) {
  if (error.code !== "EEXIST") throw error;
  console.log(
    "Preserved existing apps/api/.env. Ensure its DATABASE_URL matches infra/.env.",
  );
}
