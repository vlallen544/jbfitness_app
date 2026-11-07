import "reflect-metadata";
import { parseArgs } from "node:util";
import { Database } from "../src/database";
import { MembershipService } from "../src/memberships";
import { WorkoutService } from "../src/workouts";
import { addDays, isoDay, mondayOf, todayInIndia } from "../src/workout-schema";
async function main() {
  if (
    process.env.NODE_ENV === "production" ||
    process.env.ENABLE_DEV_WORKOUTS !== "true"
  )
    throw new Error(
      "Explicit ENABLE_DEV_WORKOUTS=true is required outside production.",
    );
  const { values } = parseArgs({
    options: { email: { type: "string" }, week: { type: "string" } },
  });
  if (!values.email)
    throw new Error("Use --email customer@example.test [--week YYYY-MM-DD].");
  const from = values.week ?? mondayOf(todayInIndia());
  if (!isoDay.safeParse(from).success) throw new Error("Invalid week date.");
  const db = new Database();
  try {
    const user = (
      await db.pool.query("SELECT id FROM users WHERE email=$1 AND role=$2", [
        values.email.trim().toLowerCase(),
        "customer",
      ])
    ).rows[0];
    if (!user) throw new Error("Register the test customer first.");
    const definitions = [
      {
        id: "dev-squat",
        name: "Bodyweight squat",
        muscle: "Legs",
        instructions: [
          "Stand with your feet comfortably apart.",
          "Bend your knees and hips through a comfortable range.",
          "Return to a standing position.",
        ],
      },
      {
        id: "dev-wall-pushup",
        name: "Wall push-up",
        muscle: "Upper body",
        instructions: [
          "Place your hands on a stable wall.",
          "Bend your elbows to move toward the wall.",
          "Press back to the starting position.",
        ],
      },
      {
        id: "dev-calf-raise",
        name: "Standing calf raise",
        muscle: "Lower legs",
        instructions: [
          "Stand upright near a stable support.",
          "Raise your heels through a comfortable range.",
          "Lower your heels with control.",
        ],
      },
    ];
    for (const exercise of definitions)
      await db.pool.query(
        `INSERT INTO exercises(id,name,muscle_group,equipment,instructions,review_status) VALUES($1,$2,$3,'[]',$4,'development_sample') ON CONFLICT(id) DO NOTHING`,
        [
          exercise.id,
          exercise.name,
          exercise.muscle,
          JSON.stringify(exercise.instructions),
        ],
      );
    const service = new WorkoutService(db, new MembershipService(db));
    const result = await service.publishPlan(
      user.id,
      {
        title: "Development sample routine",
        sessions: [0, 2, 4].map((offset, index) => ({
          date: addDays(from, offset),
          title: `Sample session ${index + 1}`,
          exercises: definitions.map((exercise) => ({
            exerciseId: exercise.id,
            sets: 3,
            repetitions: 10,
            targetWeightKg: null,
            restSeconds: 60,
          })),
        })),
      },
      "development_fixture",
    );
    console.log(
      `Published development sample version ${result.version}. Content requires trainer review; no videos are bundled.`,
    );
  } finally {
    await db.pool.end();
  }
}
main().catch((error: Error) => {
  console.error(error.message);
  process.exitCode = 1;
});
