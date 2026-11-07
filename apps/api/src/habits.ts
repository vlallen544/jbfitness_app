import { BadRequestException, Body, ConflictException, Controller, Get, Inject, Injectable, NotFoundException, Param, Post, Put, Query, Req, UseGuards } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import { z } from 'zod';
import { Database } from './database';
import { AuthGuard, User } from './auth';
import { customerOnly } from './workouts';
import { MembershipService } from './memberships';
import { addDays, isoDay, todayInIndia } from './workout-schema';

const createSchema = z.object({ name: z.string().trim().min(1).max(60), targetDays: z.number().int().min(1).max(31), requestId: z.uuid() }).strict();
const entrySchema = z.object({ completed: z.boolean() }).strict();
function parse<T>(schema: z.ZodType<T>, input: unknown): T {
  const result = schema.safeParse(input);
  if (!result.success) throw new BadRequestException('Check the habit name, monthly target, reference and calendar date.');
  return result.data;
}
type Habit = { id: string; name: string; targetDays: number; startsOn: string; archivedOn: string | null };
const select = `SELECT id,name,target_days AS "targetDays",to_char(starts_on,'YYYY-MM-DD') AS "startsOn",to_char(archived_on,'YYYY-MM-DD') AS "archivedOn" FROM habits`;
export function habitMonth(value: string) {
  if (!/^\d{4}-\d{2}$/.test(value)) throw new BadRequestException('Use a month in YYYY-MM format.');
  const first = parse(isoDay, `${value}-01`);
  if (Number(value.slice(0, 4)) < 2020 || Number(value.slice(0, 4)) > 2100) throw new BadRequestException('Choose a month between 2020 and 2100.');
  const date = new Date(`${first}T00:00:00Z`);
  date.setUTCMonth(date.getUTCMonth() + 1);
  return { first, last: addDays(date.toISOString().slice(0, 10), -1) };
}
export function habitStats(habits: Habit[], entries: { habitId: string; date: string; completed: boolean }[], first: string, last: string, today: string) {
  const rows = habits.map(habit => {
    const from = habit.startsOn > first ? habit.startsOn : first;
    const until = habit.archivedOn && habit.archivedOn < last ? habit.archivedOn : last;
    const eligible = Math.max(0, Math.round((Date.parse(until) - Date.parse(from)) / 86400000) + 1);
    const goal = Math.min(habit.targetDays, eligible);
    const completed = entries.filter(entry => entry.habitId === habit.id && entry.completed && entry.date >= from && entry.date <= until && entry.date <= today).length;
    return { ...habit, goal, completed, progress: goal ? Math.min(1, completed / goal) : 0 };
  });
  const days = [];
  for (let day = first; day <= last; day = addDays(day, 1)) {
    days.push({ date: day, completed: entries.filter(entry => entry.date === day && entry.completed && rows.some(habit => habit.id === entry.habitId && day >= habit.startsOn && (!habit.archivedOn || day <= habit.archivedOn)) && day <= today).length,
      eligible: rows.filter(habit => day >= habit.startsOn && (!habit.archivedOn || day <= habit.archivedOn) && day <= today).length });
  }
  const goal = rows.reduce((sum, row) => sum + row.goal, 0);
  return { habits: rows, days, summary: { completed: rows.reduce((sum, row) => sum + row.completed, 0), goal, progress: goal ? rows.reduce((sum, row) => sum + Math.min(row.goal, row.completed), 0) / goal : 0 } };
}

@Injectable()
export class HabitService {
  constructor(@Inject(Database) private readonly db: Database, @Inject(MembershipService) private readonly memberships: MembershipService) {}
  async month(customerId: string, requested?: string) {
    const today = todayInIndia();
    const month = requested ?? today.slice(0, 7);
    const { first, last } = habitMonth(month);
    const client = await this.db.pool.connect();
    try {
      // A grid and its totals must describe the same database snapshot.
      await client.query('BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY');
      const habits = (await client.query<Habit>(`${select} WHERE customer_id=$1 AND starts_on<=$3::date AND (archived_on IS NULL OR archived_on>=$2::date) ORDER BY created_at,id`, [customerId, first, last])).rows;
      const entries = (await client.query(`SELECT e.habit_id AS "habitId",to_char(e.day,'YYYY-MM-DD') AS date,e.completed FROM habit_entries e JOIN habits h ON h.id=e.habit_id WHERE h.customer_id=$1 AND e.day BETWEEN $2::date AND $3::date ORDER BY e.day,e.habit_id`, [customerId, first, last])).rows;
      await client.query('COMMIT');
      const membership = await this.memberships.summary(customerId);
      return { month, today, timezone: 'Asia/Kolkata', canEdit: membership.entitlements.habitTracking === true, entries, ...habitStats(habits, entries, first, last, today) };
    } catch (error) { await client.query('ROLLBACK'); throw error; } finally { client.release(); }
  }
  async create(customerId: string, input: unknown) {
    const body = parse(createSchema, input);
    await this.memberships.requireEntitlement(customerId, 'habitTracking');
    const client = await this.db.pool.connect();
    try {
      await client.query('BEGIN');
      await client.query('SELECT id FROM users WHERE id=$1 FOR UPDATE', [customerId]);
      const existing = (await client.query(`${select} WHERE customer_id=$1 AND create_request_id=$2`, [customerId, body.requestId])).rows[0] as Habit | undefined;
      if (existing) {
        if (existing.name !== body.name || existing.targetDays !== body.targetDays) throw new ConflictException('This creation reference was already used for a different habit.');
        await client.query('COMMIT');
        return { id: existing.id };
      }
      const count = (await client.query('SELECT count(*)::int AS count FROM habits WHERE customer_id=$1 AND archived_on IS NULL', [customerId])).rows[0].count;
      if (count >= 20) throw new BadRequestException('Keep up to 20 active habits. Archive one before adding another.');
      const id = randomUUID();
      await client.query('INSERT INTO habits(id,customer_id,name,target_days,create_request_id,starts_on) VALUES($1,$2,$3,$4,$5,$6)', [id, customerId, body.name, body.targetDays, body.requestId, todayInIndia()]);
      await client.query('COMMIT');
      return { id };
    } catch (error) { await client.query('ROLLBACK'); throw error; } finally { client.release(); }
  }
  async change(customerId: string, idValue: string, dateValue?: string, input?: unknown) {
    const id = parse(z.uuid(), idValue);
    const date = dateValue === undefined ? undefined : parse(isoDay, dateValue);
    const body = date === undefined ? null : parse(entrySchema, input);
    await this.memberships.requireEntitlement(customerId, 'habitTracking');
    const client = await this.db.pool.connect();
    try {
      await client.query('BEGIN');
      const row = (await client.query<Habit>(`${select} WHERE id=$1 AND customer_id=$2 FOR UPDATE`, [id, customerId])).rows[0];
      if (!row) throw new NotFoundException('Habit not found.');
      if (date === undefined) {
        await client.query('UPDATE habits SET archived_on=coalesce(archived_on,$2::date) WHERE id=$1', [id, todayInIndia()]);
      } else {
        if (row.archivedOn) throw new ConflictException('Archived habits are read-only.');
        if (date < row.startsOn || date > todayInIndia()) throw new BadRequestException('Choose a date from the habit start date through today.');
        await client.query('INSERT INTO habit_entries(habit_id,day,completed) VALUES($1,$2,$3) ON CONFLICT(habit_id,day) DO UPDATE SET completed=excluded.completed,updated_at=now()', [id, date, body!.completed]);
      }
      await client.query('COMMIT');
      return { saved: true };
    } catch (error) { await client.query('ROLLBACK'); throw error; } finally { client.release(); }
  }
}
@Controller('me/habits')
@UseGuards(AuthGuard)
export class HabitController {
  constructor(@Inject(HabitService) private readonly habits: HabitService) {}
  @Get() month(@Req() req: { user: User }, @Query('month') month?: string) { return this.habits.month(customerOnly(req.user), month); }
  @Post() create(@Req() req: { user: User }, @Body() body: unknown) { return this.habits.create(customerOnly(req.user), body); }
  @Put(':id/archive') archive(@Req() req: { user: User }, @Param('id') id: string, @Body() body: unknown) { parse(z.object({}).strict(), body); return this.habits.change(customerOnly(req.user), id); }
  @Put(':id/days/:date') save(@Req() req: { user: User }, @Param('id') id: string, @Param('date') date: string, @Body() body: unknown) { return this.habits.change(customerOnly(req.user), id, date, body); }
}
