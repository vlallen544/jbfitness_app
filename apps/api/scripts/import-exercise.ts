import { parseArgs } from "node:util";
import { readFile } from "node:fs/promises";
import { z } from "zod";
import { Database } from "../src/database";

// Trusted owner/operator command. Mobile customers cannot create or approve catalogue entries.
async function main() {
  const { values } = parseArgs({
    options: {
      file: { type: "string" },
      approved: { type: "boolean", default: false },
    },
  });
  if (!values.file)
    throw new Error(
      "Use --file /path/exercise.json; add --approved only after the client/trainer reviews the content.",
    );
  const schema = z
    .object({
      id: z.string().regex(/^[a-zA-Z0-9_-]{1,100}$/),
      name: z.string().trim().min(1).max(120),
      muscleGroup: z.string().trim().min(1).max(100),
      equipment: z.array(z.string().trim().min(1).max(80)).max(30),
      instructions: z.array(z.string().trim().min(1).max(1000)).min(1).max(20),
    })
    .strict();
  const parsed = schema.safeParse(
    JSON.parse(await readFile(values.file, "utf8")),
  );
  if (!parsed.success)
    throw new Error(
      "Invalid exercise definition. Supply id, name, muscleGroup, equipment and instructions.",
    );
  const item = parsed.data;
  const db = new Database();
  try {
    await db.pool.query(
      `INSERT INTO exercises(id,name,muscle_group,equipment,instructions,review_status) VALUES($1,$2,$3,$4,$5,$6) ON CONFLICT(id) DO UPDATE SET name=excluded.name,muscle_group=excluded.muscle_group,equipment=excluded.equipment,instructions=excluded.instructions,review_status=excluded.review_status,updated_at=now()`,
      [
        item.id,
        item.name,
        item.muscleGroup,
        JSON.stringify(item.equipment),
        JSON.stringify(item.instructions),
        values.approved ? "approved" : "draft",
      ],
    );
    console.log(
      values.approved
        ? "Imported the operator-approved exercise. Attach its reviewed video separately."
        : "Imported a draft exercise. It is not available to customers until approved.",
    );
  } finally {
    await db.pool.end();
  }
}
main().catch((error: Error) => {
  console.error(
    error instanceof SyntaxError
      ? "Exercise definition must be valid JSON."
      : error.message,
  );
  process.exitCode = 1;
});
