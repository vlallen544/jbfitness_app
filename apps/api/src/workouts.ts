import {
  BadRequestException,
  Body,
  ConflictException,
  Controller,
  ForbiddenException,
  Get,
  Inject,
  Injectable,
  NotFoundException,
  Param,
  Put,
  Query,
  Req,
  UseGuards,
} from "@nestjs/common";
import { createHash, randomUUID } from "node:crypto";
import { z } from "zod";
import type { PoolClient } from 'pg';
import { Database } from "./database";
import { AuthGuard, User } from "./auth";
import { MembershipService } from "./memberships";
import {
  addDays,
  isoDay,
  mondayOf,
  planSchema,
  progressSchema,
  todayInIndia,
} from "./workout-schema";

export type Exercise = {
  id: string;
  name: string;
  muscle_group: string;
  equipment: string[];
  instructions: string[];
  review_status: string;
  media_key: string | null;
};
export const visibleExercise = (row: Exercise) =>
  row.review_status === "approved" ||
  (process.env.NODE_ENV !== "production" &&
    row.review_status === "development_sample");
function id(value: string) {
  if (!z.uuid().safeParse(value).success)
    throw new BadRequestException("Invalid workout reference.");
  return value;
}
export function customerOnly(user: User) {
  if (user.role !== "customer")
    throw new ForbiddenException("Customer account required.");
  return user.id;
}

@Injectable()
export class WorkoutService {
  constructor(
    @Inject(Database) private readonly db: Database,
    @Inject(MembershipService) private readonly memberships: MembershipService,
  ) {}

  async publishPlan(
    customerId: string,
    input: unknown,
    source: "trainer" | "ai" | "development_fixture",
    transactionClient?: PoolClient,
  ) {
    if (!["trainer", "ai", "development_fixture"].includes(source))
      throw new BadRequestException("Invalid plan source.");
    if (
      source === "development_fixture" &&
      (process.env.NODE_ENV === "production" ||
        process.env.ENABLE_DEV_WORKOUTS !== "true")
    )
      throw new ForbiddenException(
        "Development workout fixtures are disabled.",
      );
    const parsed = planSchema.safeParse(input);
    if (!parsed.success)
      throw new BadRequestException(
        "Invalid workout plan. Check dates, exercise IDs, sets, reps and rest times.",
      );
    await this.memberships.requireEntitlement(customerId, "workoutPlanning");
    const client = transactionClient ?? await this.db.pool.connect();
    try {
      if (!transactionClient) await client.query("BEGIN");
      const owner = (
        await client.query("SELECT role FROM users WHERE id=$1 FOR UPDATE", [
          customerId,
        ])
      ).rows[0];
      if (owner?.role !== "customer")
        throw new ForbiddenException("Customer account required.");
      const exerciseIds = [
        ...new Set(
          parsed.data.sessions.flatMap((session) =>
            session.exercises.map((item) => item.exerciseId),
          ),
        ),
      ];
      const exercises = (
        await client.query<Exercise>(
          "SELECT * FROM exercises WHERE id=ANY($1::text[])",
          [exerciseIds],
        )
      ).rows;
      if (
        exercises.length !== exerciseIds.length ||
        exercises.some((exercise) =>
          source === "development_fixture"
            ? !visibleExercise(exercise)
            : exercise.review_status !== "approved",
        )
      )
        throw new BadRequestException(
          "Every planned exercise must exist and have an appropriate content review status.",
        );
      const planId = randomUUID();
      const version = Number(
        (
          await client.query(
            "SELECT COALESCE(max(version),0)+1 AS version FROM workout_plans WHERE customer_id=$1",
            [customerId],
          )
        ).rows[0].version,
      );
      await client.query(
        "UPDATE workout_plans SET superseded_at=now() WHERE customer_id=$1 AND superseded_at IS NULL",
        [customerId],
      );
      await client.query(
        "INSERT INTO workout_plans(id,customer_id,version,title,source) VALUES($1,$2,$3,$4,$5)",
        [planId, customerId, version, parsed.data.title, source],
      );
      for (const session of parsed.data.sessions) {
        const workoutId = randomUUID();
        await client.query(
          "INSERT INTO workout_sessions(id,plan_id,customer_id,scheduled_on,title) VALUES($1,$2,$3,$4,$5)",
          [workoutId, planId, customerId, session.date, session.title],
        );
        for (const [position, item] of session.exercises.entries()) {
          const exercise = exercises.find((row) => row.id === item.exerciseId)!;
          const snapshot = {
            id: exercise.id,
            name: exercise.name,
            muscleGroup: exercise.muscle_group,
            equipment: exercise.equipment,
            instructions: exercise.instructions,
            reviewStatus: exercise.review_status,
          };
          await client.query(
            "INSERT INTO workout_items(id,workout_id,exercise_id,exercise_snapshot,position,sets,repetitions,target_weight_kg,rest_seconds) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9)",
            [
              randomUUID(),
              workoutId,
              exercise.id,
              snapshot,
              position,
              item.sets,
              item.repetitions,
              item.targetWeightKg,
              item.restSeconds,
            ],
          );
        }
      }
      if (!transactionClient) await client.query("COMMIT");
      return { planId, version };
    } catch (error) {
      if (!transactionClient) await client.query("ROLLBACK");
      throw error;
    } finally {
      if (!transactionClient) client.release();
    }
  }

  async week(customerId: string, from?: string) {
    await this.memberships.requireEntitlement(customerId, "workoutPlanning");
    const parsed = isoDay.safeParse(from ?? mondayOf(todayInIndia()));
    if (!parsed.success)
      throw new BadRequestException("Use a valid YYYY-MM-DD date.");
    const through = addDays(parsed.data, 6);
    const plan = (
      await this.db.pool.query(
        `SELECT id,title,version,source FROM workout_plans WHERE customer_id=$1 AND superseded_at IS NULL AND (source<>'development_fixture' OR $2=false)`,
        [customerId, process.env.NODE_ENV === "production"],
      )
    ).rows[0];
    const workouts = plan
      ? (
          await this.db.pool.query(
            `SELECT w.id,w.title,to_char(w.scheduled_on,'YYYY-MM-DD') AS date,COALESCE(p.status,'not_started') AS status,count(i.id)::int AS "exerciseCount" FROM workout_sessions w JOIN workout_items i ON i.workout_id=w.id LEFT JOIN workout_progress p ON p.workout_id=w.id WHERE w.plan_id=$1 AND w.customer_id=$2 AND w.scheduled_on BETWEEN $3::date AND $4::date GROUP BY w.id,p.status ORDER BY w.scheduled_on,w.id`,
            [plan.id, customerId, parsed.data, through],
          )
        ).rows
      : [];
    return {
      plan: plan ?? null,
      from: parsed.data,
      through,
      calendarTimeZone: "Asia/Kolkata",
      workouts,
    };
  }

  async detail(customerId: string, workoutId: string) {
    id(workoutId);
    await this.memberships.requireEntitlement(customerId, "workoutPlanning");
    const workout = (
      await this.db.pool.query(
        `SELECT w.id,w.title,to_char(w.scheduled_on,'YYYY-MM-DD') AS date,wp.version,wp.source,(wp.superseded_at IS NOT NULL) AS archived FROM workout_sessions w JOIN workout_plans wp ON wp.id=w.plan_id WHERE w.id=$1 AND w.customer_id=$2 AND (wp.source<>'development_fixture' OR $3=false)`,
        [workoutId, customerId, process.env.NODE_ENV === "production"],
      )
    ).rows[0];
    if (!workout) throw new NotFoundException("Workout is unavailable.");
    const items = (
      await this.db.pool.query(
        `SELECT id,exercise_snapshot AS exercise,sets,repetitions,target_weight_kg::float8 AS "targetWeightKg",rest_seconds AS "restSeconds" FROM workout_items WHERE workout_id=$1 ORDER BY position`,
        [workoutId],
      )
    ).rows;
    const progress = (
      await this.db.pool.query(
        `SELECT status,exercise_logs AS "exerciseLogs",notes,revision,completed_at AS "completedAt",updated_at AS "updatedAt" FROM workout_progress WHERE workout_id=$1 AND customer_id=$2`,
        [workoutId, customerId],
      )
    ).rows[0] ?? {
      status: "not_started",
      exerciseLogs: [],
      notes: "",
      revision: 0,
      completedAt: null,
    };
    return {
      workout,
      items,
      progress,
      calendarTimeZone: "Asia/Kolkata",
      today: todayInIndia(),
    };
  }

  async saveProgress(customerId: string, workoutId: string, input: unknown) {
    id(workoutId);
    await this.memberships.requireEntitlement(customerId, "workoutPlanning");
    const parsed = progressSchema.safeParse(input);
    if (!parsed.success)
      throw new BadRequestException(
        "Invalid workout log. Check repetitions, weights and feedback.",
      );
    const body = parsed.data;
    const hash = createHash("sha256")
      .update(
        JSON.stringify({ ...body, revision: undefined, requestId: undefined }),
      )
      .digest("hex");
    const client = await this.db.pool.connect();
    try {
      await client.query("BEGIN");
      const workout = (
        await client.query(
          `SELECT w.*,to_char(w.scheduled_on,'YYYY-MM-DD') AS scheduled_day,wp.superseded_at,wp.source FROM workout_sessions w JOIN workout_plans wp ON wp.id=w.plan_id WHERE w.id=$1 AND w.customer_id=$2 FOR UPDATE OF w,wp`,
          [workoutId, customerId],
        )
      ).rows[0];
      if (
        !workout ||
        (process.env.NODE_ENV === "production" &&
          workout.source === "development_fixture")
      )
        throw new NotFoundException("Workout is unavailable.");
      const previous = (
        await client.query(
          "SELECT * FROM workout_progress WHERE workout_id=$1",
          [workoutId],
        )
      ).rows[0];
      if (previous?.last_request_id === body.requestId) {
        if (previous.last_payload_hash !== hash)
          throw new ConflictException(
            "This save reference was already used for different feedback.",
          );
        await client.query("COMMIT");
        return { revision: previous.revision, duplicate: true };
      }
      if (workout.superseded_at)
        throw new ConflictException(
          "This plan has been replaced. Refresh your current routine.",
        );
      const date = workout.scheduled_day as string;
      if (date > todayInIndia())
        throw new BadRequestException(
          "You can log a workout on its scheduled day or later.",
        );
      if ((previous?.revision ?? 0) !== body.revision)
        throw new ConflictException(
          "This workout was updated on another device. Reload before saving.",
        );
      const items = (
        await client.query("SELECT id FROM workout_items WHERE workout_id=$1", [
          workoutId,
        ])
      ).rows as { id: string }[];
      if (
        body.exerciseLogs.some(
          (log) => !items.some((item) => item.id === log.itemId),
        )
      )
        throw new BadRequestException(
          "An exercise log does not belong to this workout.",
        );
      if (
        body.status === "completed" &&
        !items.every((item) =>
          body.exerciseLogs.some(
            (log) => log.itemId === item.id && log.completed,
          ),
        )
      )
        throw new BadRequestException(
          "Mark every exercise complete before completing the workout.",
        );
      const revision = body.revision + 1;
      const completedAt =
        body.status === "completed"
          ? (previous?.completed_at ?? new Date())
          : null;
      await client.query(
        `INSERT INTO workout_progress(workout_id,customer_id,status,exercise_logs,notes,revision,last_request_id,last_payload_hash,completed_at) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9) ON CONFLICT(workout_id) DO UPDATE SET status=excluded.status,exercise_logs=excluded.exercise_logs,notes=excluded.notes,revision=excluded.revision,last_request_id=excluded.last_request_id,last_payload_hash=excluded.last_payload_hash,completed_at=excluded.completed_at,updated_at=now()`,
        [
          workoutId,
          customerId,
          body.status,
          JSON.stringify(body.exerciseLogs),
          body.notes,
          revision,
          body.requestId,
          hash,
          completedAt,
        ],
      );
      await client.query("COMMIT");
      return { revision, duplicate: false };
    } catch (error) {
      await client.query("ROLLBACK");
      throw error;
    } finally {
      client.release();
    }
  }

  async history(customerId: string) {
    const workouts = (
      await this.db.pool.query(
        `SELECT w.id,w.title,to_char(w.scheduled_on,'YYYY-MM-DD') AS date,p.status,p.notes,p.exercise_logs AS "exerciseLogs",p.completed_at AS "completedAt",p.updated_at AS "updatedAt",wp.version FROM workout_progress p JOIN workout_sessions w ON w.id=p.workout_id JOIN workout_plans wp ON wp.id=w.plan_id WHERE p.customer_id=$1 AND (wp.source<>'development_fixture' OR $2=false) ORDER BY p.updated_at DESC,w.id LIMIT 50`,
        [customerId, process.env.NODE_ENV === "production"],
      )
    ).rows;
    return { workouts, limit: 50 };
  }

  async catalogue(customerId: string) {
    await this.memberships.requireEntitlement(
      customerId,
      "storedExerciseVideos",
    );
    const rows = (
      await this.db.pool.query<Exercise>(
        "SELECT * FROM exercises ORDER BY name",
      )
    ).rows.filter(visibleExercise);
    return {
      exercises: rows.map((row) => ({
        id: row.id,
        name: row.name,
        muscleGroup: row.muscle_group,
        equipment: row.equipment,
        instructions: row.instructions,
        reviewStatus: row.review_status,
        videoSupplied: row.media_key !== null,
      })),
    };
  }
}

@Controller("me/workouts")
@UseGuards(AuthGuard)
export class WorkoutController {
  constructor(
    @Inject(WorkoutService) private readonly workouts: WorkoutService,
  ) {}
  @Get() week(@Req() req: { user: User }, @Query("from") from?: string) {
    return this.workouts.week(customerOnly(req.user), from);
  }
  @Get("history") history(@Req() req: { user: User }) {
    return this.workouts.history(customerOnly(req.user));
  }
  @Get(":id") detail(
    @Req() req: { user: User },
    @Param("id") workoutId: string,
  ) {
    return this.workouts.detail(customerOnly(req.user), workoutId);
  }
  @Put(":id/progress") save(
    @Req() req: { user: User },
    @Param("id") workoutId: string,
    @Body() body: unknown,
  ) {
    return this.workouts.saveProgress(customerOnly(req.user), workoutId, body);
  }
}
@Controller("me/exercises")
@UseGuards(AuthGuard)
export class ExerciseController {
  constructor(
    @Inject(WorkoutService) private readonly workouts: WorkoutService,
  ) {}
  @Get() get(@Req() req: { user: User }) {
    return this.workouts.catalogue(customerOnly(req.user));
  }
}
