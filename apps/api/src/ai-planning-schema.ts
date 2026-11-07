import { z } from 'zod';
import { addDays, planSchema } from './workout-schema';

const text = z.string().max(500);
export const routineReviewSchema = z.object({ decision: z.enum(['proceed','needs_review']), summary: text, notes: z.array(text).max(6) }).strict();
export const planJudgeSchema = z.object({ decision: z.enum(['approved','revise','needs_review']), summary: text, issues: z.array(text).max(8) }).strict();
export const aiDraftSchema = planSchema;
export const planningProfileKeys = ['age','heightCm','weightKg','goal','experience','equipment','workoutDays','sessionMinutes','currentRoutine','limitations'] as const;
export function planningProfile(data: Record<string, any>) { return Object.fromEntries(planningProfileKeys.map(k => [k,data[k]])); }
export function requestedDates(today: string, days: number[]) {
  return Array.from({length:7},(_,i)=>addDays(today,i+1)).filter(day=>days.includes((new Date(day+'T00:00:00Z').getUTCDay()+6)%7));
}
const equipmentName = (s: string) => s.trim().toLowerCase().replace(/\s+/g,' ');
export function equipmentMatches(required: string[], available: string[]) {
  const has = new Set(available.map(equipmentName));
  return required.every(item=>equipmentName(item)==='bodyweight'||has.has(equipmentName(item)));
}
export type PlanningContext = {
  profile: Record<string, any>;
  dates: string[];
  catalogue: {id:string;name:string;equipment:string[];muscleGroup:string;instructions:string[]}[];
  recentWorkouts: unknown[];
  models: {planner:string;reviewer:string};
};
export function needsProfileReview(profile: Record<string,any>) {
  if(profile.age<18) return 'This profile needs trainer review before automatic workout planning.';
  if(profile.sessionMinutes<15) return 'This session length needs trainer review before automatic workout planning.';
  const limitations=String(profile.limitations??'').trim().toLowerCase();
  if(!['','none','no','no limitations','no injuries'].includes(limitations)) return 'Your recorded limitations need trainer review before automatic workout planning.';
  return null;
}
export function checkAiPlan(value: unknown, context: PlanningContext) {
  const parsed=aiDraftSchema.safeParse(value);
  if(!parsed.success)return ['The draft did not meet the workout data format.'];
  const plan=parsed.data, errors:string[]=[];
  const dates=plan.sessions.map(s=>s.date).sort();
  if(JSON.stringify(dates)!==JSON.stringify([...context.dates].sort()))errors.push('Use exactly one session on each requested date, with no extra dates.');
  for(const session of plan.sessions) {
    if(session.exercises.length>8)errors.push('Use at most eight exercises per session.');
    if(new Set(session.exercises.map(e=>e.exerciseId)).size!==session.exercises.length)errors.push('Do not repeat an exercise within a session.');
    let seconds=300;
    for(const item of session.exercises) {
      const exercise=context.catalogue.find(e=>e.id===item.exerciseId);
      if(!exercise || !equipmentMatches(exercise.equipment,context.profile.equipment)) errors.push('Use only the supplied approved exercises and available equipment.');
      if(item.sets>5||item.repetitions>30||item.restSeconds<30||item.restSeconds>180)errors.push('Use 1–5 sets, 1–30 repetitions and 30–180 seconds rest.');
      if(item.targetWeightKg!==null)errors.push('Do not prescribe an unverified load; targetWeightKg must be null.');
      seconds+=60+item.sets*(item.repetitions*4+item.restSeconds);
    }
    if(seconds>context.profile.sessionMinutes*60)errors.push('The estimated session time exceeds the saved availability.');
  }
  return [...new Set(errors)];
}
