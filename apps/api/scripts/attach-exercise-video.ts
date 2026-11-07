import { parseArgs } from "node:util";
import { randomUUID } from "node:crypto";
import { constants } from "node:fs";
import { copyFile, mkdir, open, stat, unlink } from "node:fs/promises";
import { extname, resolve } from "node:path";
import { Database } from "../src/database";
async function main() {
  const { values } = parseArgs({
    options: { exercise: { type: "string" }, file: { type: "string" } },
  });
  if (!values.exercise || !values.file)
    throw new Error(
      "Use --exercise exercise-id --file /absolute/path/video.mp4",
    );
  const source = resolve(values.file);
  const extension = extname(source).toLowerCase();
  if (![".mp4", ".webm"].includes(extension))
    throw new Error("Supply MP4 or WebM.");
  const info = await stat(source);
  if (!info.isFile() || info.size < 12 || info.size > 250 * 1024 * 1024)
    throw new Error("Supply a regular video file smaller than 250 MB.");
  const handle = await open(source, "r");
  const header = Buffer.alloc(12);
  try {
    await handle.read(header, 0, 12, 0);
  } finally {
    await handle.close();
  }
  if (
    extension === ".mp4"
      ? header.toString("ascii", 4, 8) !== "ftyp"
      : header.subarray(0, 4).toString("hex") !== "1a45dfa3"
  )
    throw new Error("The file header does not match its video extension.");
  const db = new Database();
  let copied: string | undefined;
  try {
    const exercise = (
      await db.pool.query("SELECT id FROM exercises WHERE id=$1", [
        values.exercise,
      ])
    ).rows[0];
    if (!exercise)
      throw new Error("Create and review the exercise catalogue entry first.");
    const root = resolve(
      process.env.EXERCISE_MEDIA_ROOT ??
        resolve(process.cwd(), "private-media"),
    );
    await mkdir(root, { recursive: true, mode: 0o700 });
    const key = `${randomUUID()}${extension}`;
    copied = resolve(root, key);
    await copyFile(source, copied, constants.COPYFILE_EXCL);
    const updated = await db.pool.query(
      "UPDATE exercises SET media_key=$1,updated_at=now() WHERE id=$2",
      [key, exercise.id],
    );
    if (!updated.rowCount)
      throw new Error(
        "The exercise was removed before the video could be attached.",
      );
    copied = undefined;
    console.log(
      "Stored the exercise video privately. Original file and content-review status were preserved.",
    );
  } finally {
    if (copied) await unlink(copied);
    await db.pool.end();
  }
}
main().catch((error: Error) => {
  console.error(error.message);
  process.exitCode = 1;
});
