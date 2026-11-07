import { z } from "zod";
export const isoDay = z
  .string()
  .regex(/^\d{4}-\d{2}-\d{2}$/)
  .refine((day) => {
    const date = new Date(`${day}T00:00:00Z`);
    return (
      Number.isFinite(date.getTime()) && date.toISOString().slice(0, 10) === day
    );
  }, "Invalid calendar date");
export function addDays(day: string, count: number) {
  const result = new Date(`${day}T00:00:00Z`);
  result.setUTCDate(result.getUTCDate() + count);
  return result.toISOString().slice(0, 10);
}
export function todayInIndia() {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: "Asia/Kolkata",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(new Date());
  return ["year", "month", "day"]
    .map((type) => parts.find((part) => part.type === type)!.value)
    .join("-");
}
export function mondayOf(day: string) {
  const date = new Date(`${day}T00:00:00Z`);
  return addDays(day, -((date.getUTCDay() + 6) % 7));
}
export const planSchema = z
  .object({
    title: z.string().trim().min(1).max(120),
    sessions: z
      .array(
        z
          .object({
            date: isoDay,
            title: z.string().trim().min(1).max(120),
            exercises: z
              .array(
                z
                  .object({
                    exerciseId: z.string().regex(/^[a-zA-Z0-9_-]{1,100}$/),
                    sets: z.number().int().min(1).max(12),
                    repetitions: z.number().int().min(1).max(100),
                    targetWeightKg: z.number().min(0).max(1000).nullable(),
                    restSeconds: z.number().int().min(0).max(600),
                  })
                  .strict(),
              )
              .min(1)
              .max(20),
          })
          .strict(),
      )
      .min(1)
      .max(28),
  })
  .strict();
export const progressSchema = z
  .object({
    requestId: z.uuid(),
    revision: z.number().int().min(0),
    status: z.enum(["in_progress", "completed", "skipped"]),
    notes: z.string().trim().max(2000),
    exerciseLogs: z
      .array(
        z
          .object({
            itemId: z.uuid(),
            completed: z.boolean(),
            actualSets: z.number().int().min(0).max(30).nullable(),
            actualRepetitions: z.number().int().min(0).max(500).nullable(),
            actualWeightKg: z.number().min(0).max(1000).nullable(),
            difficulty: z.enum(["easy", "moderate", "hard"]).nullable(),
            notes: z.string().trim().max(500),
          })
          .strict(),
      )
      .max(20)
      .refine(
        (logs) => new Set(logs.map((log) => log.itemId)).size === logs.length,
        "Duplicate exercise log",
      ),
  })
  .strict();
