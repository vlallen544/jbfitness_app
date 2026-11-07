import "reflect-metadata";
import { parseArgs } from "node:util";
import { Database } from "../../src/database";
import { MembershipService } from "../../src/memberships";
import { WorkoutService } from "../../src/workouts";
import { todayInIndia } from "../../src/workout-schema";

// Creates an explicitly labelled technical playback fixture for one browser QA account.
async function main() {
  if (
    process.env.NODE_ENV === "production" ||
    process.env.ENABLE_DEV_WORKOUTS !== "true"
  )
    throw new Error("Development QA opt-in required.");
  const { values } = parseArgs({
    options: { email: { type: "string" }, id: { type: "string" } },
  });
  if (
    !values.email ||
    !values.id ||
    !/^qa-playback-[a-f0-9-]{36}$/.test(values.id)
  )
    throw new Error("Supply the unique QA email and exercise reference.");
  const db = new Database();
  let inserted = false;
  try {
    const user = (
      await db.pool.query("SELECT id FROM users WHERE email=$1 AND role=$2", [
        values.email,
        "customer",
      ])
    ).rows[0];
    if (!user) throw new Error("QA customer unavailable.");
    await db.pool.query(
      `INSERT INTO exercises(id,name,muscle_group,equipment,instructions,review_status) VALUES($1,'Technical playback test','Playback verification','[]','["Technical test clip. Trainer-reviewed demonstration content is pending."]','development_sample')`,
      [values.id],
    );
    inserted = true;
    const published = await new WorkoutService(
      db,
      new MembershipService(db),
    ).publishPlan(
      user.id,
      {
        title: "Playback verification routine",
        sessions: [
          {
            date: todayInIndia(),
            title: "Playback verification session",
            exercises: [
              {
                exerciseId: values.id,
                sets: 3,
                repetitions: 10,
                targetWeightKg: null,
                restSeconds: 60,
              },
            ],
          },
        ],
      },
      "development_fixture",
    );
    console.log(JSON.stringify(published));
  } catch (error) {
    if (inserted)
      await db.pool.query("DELETE FROM exercises WHERE id=$1", [values.id]);
    throw error;
  } finally {
    await db.pool.end();
  }
}
main().catch(() => {
  console.error("Could not create the temporary browser workout fixture.");
  process.exitCode = 1;
});
