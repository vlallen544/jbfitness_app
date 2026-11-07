import { Body, ConflictException, Controller, Get, Inject, Injectable, NotFoundException, Param, Post, Put, Query, Req, UseGuards, BadRequestException } from '@nestjs/common';
import { createHash, randomUUID } from 'node:crypto';
import { z } from 'zod';
import { Database } from './database';
import { AuthGuard, User } from './auth';
import { customerOnly } from './workouts';
import { MembershipService } from './memberships';
import { NutritionProvider } from './nutrition-provider';
import { editSchema, entrySchema, foodSchema, nutritionDate, nutritionParse as parse, nutritionTotals, scaleNutrients, targetsSaveSchema } from './nutrition-schema';
import { todayInIndia } from './workout-schema';

const hash = (body: unknown) => createHash('sha256').update(JSON.stringify(body)).digest('hex');
const foodSelect = `SELECT id,name,nutrients,source FROM nutrition_foods`;
const entrySelect = `SELECT id,food_id AS "foodId",to_char(day,'YYYY-MM-DD') AS date,meal,grams::float8 AS grams,food_snapshot AS food,revision,deleted FROM nutrition_entries`;
@Injectable()
export class NutritionService {
  constructor(@Inject(Database) private readonly db: Database, @Inject(MembershipService) private readonly memberships: MembershipService, @Inject(NutritionProvider) private readonly provider: NutritionProvider) {}
  async day(customerId: string, requested?: string) {
    const date = nutritionDate(requested);
    const client = await this.db.pool.connect();
    try {
      await client.query('BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY');
      const rows = (await client.query(`${entrySelect} WHERE customer_id=$1 AND day=$2 AND deleted=false ORDER BY created_at,id`, [customerId, date])).rows;
      const entries = rows.map(row => ({ ...row, nutrients: scaleNutrients(row.food.nutrients, row.grams) }));
      const previous = (await client.query(`SELECT to_char(effective_from,'YYYY-MM-DD') AS "effectiveFrom",nutrients,revision FROM nutrition_targets WHERE customer_id=$1 AND effective_from<=$2::date ORDER BY effective_from DESC LIMIT 1`, [customerId, date])).rows[0];
      await client.query('COMMIT');
      const targets = previous ? { ...previous, revision: previous.effectiveFrom === todayInIndia() ? previous.revision : 0 } : null;
      return { date, today: todayInIndia(), timezone: 'Asia/Kolkata', entries, totals: nutritionTotals(entries), estimatedEntryCount: entries.filter(entry => entry.food.source.type === 'ai_estimate').length, targets, canEdit: (await this.memberships.summary(customerId)).entitlements.nutritionTracking === true };
    } catch (error) { await client.query('ROLLBACK'); throw error; } finally { client.release(); }
  }
  async foods(customerId: string, value?: string) {
    const query = parse(z.string().trim().max(100), value ?? '');
    const foods = (await this.db.pool.query(`${foodSelect} WHERE customer_id=$1 AND strpos(lower(name),lower($2))>0 ORDER BY created_at DESC,id LIMIT 25`, [customerId, query])).rows;
    let external: unknown[] = []; let notice: string | null = null;
    if (query.length >= 2 && this.provider.configured) {
      await this.memberships.requireEntitlement(customerId, 'nutritionTracking');
      try { external = await this.provider.search(query); } catch { notice = 'USDA search is unavailable. You can use saved foods or enter a food label.'; }
    }
    return { foods, external, providerConfigured: this.provider.configured, notice };
  }
  async food(customerId: string, input: unknown) {
    const body = parse(foodSchema, input);
    await this.memberships.requireEntitlement(customerId, 'nutritionTracking');
    return this.storeFood(customerId, { name: body.name, nutrients: body.nutrients, source: { type: 'label', label: 'Values entered by you', note: body.sourceNote } }, body.requestId, hash(body));
  }
  async usda(customerId: string, value: string) {
    const id = parse(z.coerce.number().int().min(1).max(2147483647), value);
    await this.memberships.requireEntitlement(customerId, 'nutritionTracking');
    const cached = (await this.db.pool.query(`${foodSelect} WHERE customer_id=$1 AND usda_id=$2`, [customerId, id])).rows[0];
    if (cached) return { food: cached };
    return this.storeFood(customerId, await this.provider.detail(id), null, null, id);
  }
  private async storeFood(customerId: string, food: { name: string; nutrients: unknown; source: unknown }, requestId: string | null, payload: string | null, usdaId: number | null = null) {
    const client = await this.db.pool.connect();
    try {
      await client.query('BEGIN');
      await client.query('SELECT id FROM users WHERE id=$1 FOR UPDATE', [customerId]);
      const existing = (await client.query(`SELECT id,name,nutrients,source,create_payload_hash FROM nutrition_foods WHERE customer_id=$1 AND (($2::uuid IS NOT NULL AND create_request_id=$2) OR ($3::integer IS NOT NULL AND usda_id=$3))`, [customerId, requestId, usdaId])).rows[0];
      if (existing) {
        if (requestId && existing.create_payload_hash !== payload) throw new ConflictException('This food save reference has different values.');
        await client.query('COMMIT'); const { create_payload_hash: _, ...visible } = existing; return { food: visible };
      }
      const count = (await client.query('SELECT count(*)::int AS count FROM nutrition_foods WHERE customer_id=$1', [customerId])).rows[0].count;
      if (count >= 1000) throw new BadRequestException('The saved-food limit has been reached.');
      const id = randomUUID();
      await client.query('INSERT INTO nutrition_foods(id,customer_id,name,nutrients,source,create_request_id,create_payload_hash,usda_id) VALUES($1,$2,$3,$4,$5,$6,$7,$8)', [id, customerId, food.name, JSON.stringify(food.nutrients), JSON.stringify(food.source), requestId, payload, usdaId]);
      await client.query('COMMIT'); return { food: { id, ...food } };
    } catch (error) { await client.query('ROLLBACK'); throw error; } finally { client.release(); }
  }
  async log(customerId: string, input: unknown) {
    const body = parse(entrySchema, input); nutritionDate(body.date);
    await this.memberships.requireEntitlement(customerId, 'nutritionTracking');
    const client = await this.db.pool.connect();
    try {
      await client.query('BEGIN'); await client.query('SELECT id FROM users WHERE id=$1 FOR UPDATE', [customerId]);
      const existing = (await client.query('SELECT id,create_payload_hash FROM nutrition_entries WHERE customer_id=$1 AND create_request_id=$2', [customerId, body.requestId])).rows[0];
      if (existing) { if (existing.create_payload_hash !== hash(body)) throw new ConflictException('This meal save reference has different values.'); await client.query('COMMIT'); return { id: existing.id }; }
      const food = (await client.query(`${foodSelect} WHERE id=$1 AND customer_id=$2`, [body.foodId, customerId])).rows[0];
      if (!food) throw new NotFoundException('Food not found in your saved foods.');
      const count = (await client.query('SELECT count(*)::int AS count FROM nutrition_entries WHERE customer_id=$1 AND day=$2 AND deleted=false', [customerId, body.date])).rows[0].count;
      if (count >= 200) throw new BadRequestException('Keep up to 200 food entries per day.');
      const id = randomUUID(); await client.query('INSERT INTO nutrition_entries(id,customer_id,food_id,day,meal,grams,food_snapshot,create_request_id,create_payload_hash) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9)', [id, customerId, body.foodId, body.date, body.meal, body.grams, JSON.stringify(food), body.requestId, hash(body)]);
      await client.query('COMMIT'); return { id };
    } catch (error) { await client.query('ROLLBACK'); throw error; } finally { client.release(); }
  }
  async edit(customerId: string, value: string, input: unknown) {
    const id = parse(z.uuid(), value); const body = parse(editSchema, input);
    await this.memberships.requireEntitlement(customerId, 'nutritionTracking');
    const client = await this.db.pool.connect();
    try {
      await client.query('BEGIN');
      const row = (await client.query('SELECT * FROM nutrition_entries WHERE id=$1 AND customer_id=$2 FOR UPDATE', [id, customerId])).rows[0];
      if (!row) throw new NotFoundException('Meal entry not found.');
      if (row.last_request_id === body.requestId) { if (row.last_payload_hash !== hash(body)) throw new ConflictException('This save reference has different values.'); await client.query('COMMIT'); return { revision: row.revision }; }
      if (row.deleted || row.revision !== body.revision) throw new ConflictException('This entry changed on another device. Refresh before editing.');
      await client.query('UPDATE nutrition_entries SET grams=$3,meal=$4,deleted=$5,revision=revision+1,last_request_id=$6,last_payload_hash=$7,updated_at=now() WHERE id=$1 AND customer_id=$2', [id, customerId, body.grams, body.meal, body.deleted, body.requestId, hash(body)]);
      await client.query('COMMIT'); return { revision: row.revision + 1 };
    } catch (error) { await client.query('ROLLBACK'); throw error; } finally { client.release(); }
  }
  async targets(customerId: string, input: unknown) {
    const body = parse(targetsSaveSchema, input); await this.memberships.requireEntitlement(customerId, 'nutritionTracking');
    const today = todayInIndia(); const client = await this.db.pool.connect();
    try {
      if (body.date !== today) throw new ConflictException('The calendar date changed. Refresh before setting today’s targets.');
      await client.query('BEGIN'); await client.query('SELECT id FROM users WHERE id=$1 FOR UPDATE', [customerId]);
      const previous = (await client.query('SELECT * FROM nutrition_targets WHERE customer_id=$1 AND effective_from=$2 FOR UPDATE', [customerId, today])).rows[0];
      if (previous?.last_request_id === body.requestId) { if (previous.last_payload_hash !== hash(body)) throw new ConflictException('This save reference has different target values.'); await client.query('COMMIT'); return { revision: previous.revision }; }
      if ((previous?.revision ?? 0) !== body.revision) throw new ConflictException('Targets changed on another device. Refresh before saving.');
      const revision = body.revision + 1;
      await client.query('INSERT INTO nutrition_targets(customer_id,effective_from,nutrients,revision,last_request_id,last_payload_hash) VALUES($1,$2,$3,$4,$5,$6) ON CONFLICT(customer_id,effective_from) DO UPDATE SET nutrients=excluded.nutrients,revision=excluded.revision,last_request_id=excluded.last_request_id,last_payload_hash=excluded.last_payload_hash,updated_at=now()', [customerId, today, JSON.stringify(body.nutrients), revision, body.requestId, hash(body)]);
      await client.query('COMMIT'); return { revision };
    } catch (error) { await client.query('ROLLBACK'); throw error; } finally { client.release(); }
  }
}
@Controller('me/nutrition')
@UseGuards(AuthGuard)
export class NutritionController {
  constructor(@Inject(NutritionService) private readonly nutrition: NutritionService) {}
  @Get() day(@Req() req: { user: User }, @Query('date') date?: string) { return this.nutrition.day(customerOnly(req.user), date); }
  @Get('foods') foods(@Req() req: { user: User }, @Query('q') q?: string) { return this.nutrition.foods(customerOnly(req.user), q); }
  @Post('foods') food(@Req() req: { user: User }, @Body() body: unknown) { return this.nutrition.food(customerOnly(req.user), body); }
  @Post('foods/usda/:id') usda(@Req() req: { user: User }, @Param('id') id: string, @Body() body: unknown) { parse(z.object({}).strict(), body); return this.nutrition.usda(customerOnly(req.user), id); }
  @Post('entries') log(@Req() req: { user: User }, @Body() body: unknown) { return this.nutrition.log(customerOnly(req.user), body); }
  @Put('entries/:id') edit(@Req() req: { user: User }, @Param('id') id: string, @Body() body: unknown) { return this.nutrition.edit(customerOnly(req.user), id, body); }
  @Put('targets') targets(@Req() req: { user: User }, @Body() body: unknown) { return this.nutrition.targets(customerOnly(req.user), body); }
}
