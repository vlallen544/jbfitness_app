export function oneCalendarMonthAfter(start: Date): Date {
  if (!Number.isFinite(start.getTime()))
    throw new Error("Invalid membership start date.");
  const result = new Date(start);
  const day = result.getUTCDate();
  result.setUTCDate(1);
  result.setUTCMonth(result.getUTCMonth() + 1);
  const lastDay = new Date(
    Date.UTC(result.getUTCFullYear(), result.getUTCMonth() + 1, 0),
  ).getUTCDate();
  result.setUTCDate(Math.min(day, lastDay));
  return result;
}

export const developmentMembershipPolicy = {
  provisional: true,
  duration: "calendar_month",
  renewal: "manual",
  earlyRenewal: "same_plan_starts_after_existing_period",
  sessionCarryForward: false,
  planChanges: "not_available_until_rules_are_confirmed",
} as const;

export const baseEntitlements = {
  storedExerciseVideos: true,
  aiCoaching: true,
  workoutPlanning: true,
  nutritionTracking: true,
  habitTracking: true,
  progressTracking: true,
} as const;
export type Entitlement = keyof typeof baseEntitlements;
