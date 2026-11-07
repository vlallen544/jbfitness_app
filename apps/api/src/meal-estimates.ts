import { BadRequestException, Body, ConflictException, Controller, Get, GoneException, Inject, Injectable, NotFoundException, Param, Post, Req, ServiceUnavailableException, UploadedFile, UseGuards, UseInterceptors, HttpException } from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import { createHash, randomUUID } from 'node:crypto';
import sharp from 'sharp';
import { z } from 'zod';
import { AuthGuard, User } from './auth';
import { Database } from './database';
import { MembershipService } from './memberships';
import { customerOnly } from './workouts';
import { nutritionDate, nutritionParse as parse, nutritionTotals, scaleNutrients } from './nutrition-schema';
import { estimateRequestSchema, reviewSaveSchema, validateMealDraft } from './meal-estimate-schema';
import { MealEstimateProvider } from './meal-estimate-provider';
import { todayInIndia } from './workout-schema';

export const MAX_MEAL_PHOTO_BYTES = 4 * 1024 * 1024;
const digest = (value: string | Buffer) => createHash('sha256').update(value).digest('hex');
export async function normalizeMealPhoto(buffer: Buffer) {
  if (!buffer.length || buffer.length > MAX_MEAL_PHOTO_BYTES) throw new BadRequestException('Choose a JPG, PNG or WebP photo up to 4 MB.');
  try {
    const image = sharp(buffer, { limitInputPixels: 16000000, failOn: 'error', animated: false });
    const metadata = await image.metadata();
    if (!['jpeg', 'png', 'webp'].includes(metadata.format ?? '') || (metadata.pages ?? 1) !== 1) throw new Error('Unsupported photo');
    return await image.rotate().resize({ width: 1600, height: 1600, fit: 'inside', withoutEnlargement: true }).jpeg({ quality: 82 }).toBuffer();
  } catch { throw new BadRequestException('This photo could not be read. Choose a non-animated JPG, PNG or WebP.'); }
}
function present(row: any) {
  const draft = row.draft;
  return { id: row.id, inputKind: row.input_kind, expiresAt: row.expires_at.toISOString(), ...draft, totals: nutritionTotals(draft.items.map((item: any) => ({ nutrients: scaleNutrients(item.nutrients, item.grams) }))), isEstimated: true };
}
@Injectable()
export class MealEstimateService {
  constructor(@Inject(Database) private readonly db: Database, @Inject(MembershipService) private readonly memberships: MembershipService, @Inject(MealEstimateProvider) private readonly provider: MealEstimateProvider) {}
  async status(customerId: string) {
    const count = (await this.db.pool.query(`SELECT count(*)::int AS count FROM meal_estimates WHERE customer_id=$1 AND (created_at AT TIME ZONE 'Asia/Kolkata')::date=$2::date`, [customerId, todayInIndia()])).rows[0].count;
    const entitled = (await this.memberships.summary(customerId)).entitlements.aiCoaching === true;
    return { configured: this.provider.configured, entitled, remainingToday: Math.max(0, 10 - count), dailyLimit: 10, maxPhotoBytes: MAX_MEAL_PHOTO_BYTES };
  }
  async create(customerId: string, input: unknown, photo?: Buffer) {
    const body = parse(estimateRequestSchema, input);
    if (!body.description && !photo) throw new BadRequestException('Describe a dish or choose a meal photo.');
    await this.memberships.requireEntitlement(customerId, 'aiCoaching');
    if (!this.provider.configured) throw new ServiceUnavailableException('Meal estimation is not connected yet. You can still use food labels and saved foods.');
    const jpeg = photo ? await normalizeMealPhoto(photo) : undefined;
    const payloadHash = digest(JSON.stringify({ description: body.description, image: jpeg ? digest(jpeg) : null }));
    const client = await this.db.pool.connect();
    let id = '';
    try {
      await client.query('BEGIN'); await client.query('SELECT id FROM users WHERE id=$1 FOR UPDATE', [customerId]);
      const existing = (await client.query('SELECT * FROM meal_estimates WHERE customer_id=$1 AND request_id=$2', [customerId, body.requestId])).rows[0];
      if (existing) {
        if (existing.input_hash !== payloadHash) throw new ConflictException('This estimate reference was used for different input. Start a new estimate.');
        if (existing.status === 'pending') throw new ConflictException('This estimate is still processing. Retry the same input shortly.');
        if (existing.status === 'failed') throw new ConflictException('The previous attempt could not complete. Start a new estimate to try again.');
        if (existing.expires_at <= new Date()) throw new GoneException('This estimate expired. Start a new estimate.');
        await client.query('COMMIT'); return present(existing);
      }
      const pending = (await client.query(`SELECT 1 FROM meal_estimates WHERE customer_id=$1 AND status='pending' AND created_at>now()-interval '2 minutes'`, [customerId])).rowCount;
      if (pending) throw new ConflictException('Another meal estimate is processing. Please wait.');
      const count = (await client.query(`SELECT count(*)::int AS count FROM meal_estimates WHERE customer_id=$1 AND (created_at AT TIME ZONE 'Asia/Kolkata')::date=$2::date`, [customerId, todayInIndia()])).rows[0].count;
      if (count >= 10) throw new HttpException('You have reached today’s 10 meal estimates. Food-label logging is still available.', 429);
      id = randomUUID();
      await client.query(`INSERT INTO meal_estimates(id,customer_id,request_id,input_hash,input_kind,status,model) VALUES($1,$2,$3,$4,$5,'pending',$6)`, [id, customerId, body.requestId, payloadHash, photo ? body.description ? 'photo_text' : 'photo' : 'text', this.provider.model]);
      await client.query('COMMIT');
    } catch (error) { await client.query('ROLLBACK'); throw error; } finally { client.release(); }
    try {
      const result = await this.provider.estimate(body.description, jpeg);
      const draft = validateMealDraft(result.draft);
      const row = (await this.db.pool.query(`UPDATE meal_estimates SET status='succeeded',draft=$2,usage=$3 WHERE id=$1 RETURNING *`, [id, JSON.stringify(draft), JSON.stringify(result.usage)])).rows[0];
      return present(row);
    } catch (error) { await this.db.pool.query(`UPDATE meal_estimates SET status='failed' WHERE id=$1`, [id]); throw error; }
  }
  async save(customerId: string, value: string, input: unknown) {
    const id = parse(z.uuid(), value); const body = parse(reviewSaveSchema, input); nutritionDate(body.date);
    if (body.items.reduce((sum, item) => sum + item.grams, 0) > 10000) throw new BadRequestException('The combined portion must be at most 10,000 g.');
    await this.memberships.requireEntitlement(customerId, 'nutritionTracking');
    const hash = digest(JSON.stringify({ id, ...body })); const client = await this.db.pool.connect();
    try {
      await client.query('BEGIN'); await client.query('SELECT id FROM users WHERE id=$1 FOR UPDATE', [customerId]);
      const previous = (await client.query('SELECT * FROM meal_estimate_saves WHERE customer_id=$1 AND request_id=$2', [customerId, body.requestId])).rows[0];
      if (previous) { if (previous.payload_hash !== hash) throw new ConflictException('This diary save reference has different values.'); await client.query('COMMIT'); return { entryIds: previous.entry_ids }; }
      const estimate = (await client.query('SELECT * FROM meal_estimates WHERE id=$1 AND customer_id=$2', [id, customerId])).rows[0];
      if (!estimate) throw new NotFoundException('Meal estimate not found.');
      if (estimate.expires_at <= new Date()) throw new GoneException('This estimate expired. Create a new estimate before saving.');
      if (estimate.status !== 'succeeded' || estimate.draft.status !== 'estimated') throw new BadRequestException('There is no usable estimate to save.');
      const count = (await client.query('SELECT count(*)::int AS count FROM nutrition_entries WHERE customer_id=$1 AND day=$2 AND deleted=false', [customerId, body.date])).rows[0].count;
      if (count + body.items.length > 200) throw new BadRequestException('Keep up to 200 food entries per day.');
      const original = estimate.draft.items.map((item: any) => ({ name: item.name, grams: item.grams, nutrients: item.nutrients }));
      const editedByUser = JSON.stringify(original) !== JSON.stringify(body.items);
      const entryIds = [];
      for (const item of body.items) {
        const entryId = randomUUID(); entryIds.push(entryId);
        const food = { name: item.name, nutrients: item.nutrients, source: { type: 'ai_estimate', label: 'AI estimate', estimateId: id, model: estimate.model, inputKind: estimate.input_kind, uncertainty: estimate.draft.uncertainty, assumptions: estimate.draft.assumptions, editedByUser } };
        await client.query(`INSERT INTO nutrition_entries(id,customer_id,day,meal,grams,food_snapshot,create_request_id,create_payload_hash) VALUES($1,$2,$3,$4,$5,$6,$7,$8)`, [entryId, customerId, body.date, body.meal, item.grams, JSON.stringify(food), randomUUID(), digest(JSON.stringify(item))]);
      }
      await client.query('INSERT INTO meal_estimate_saves(customer_id,request_id,estimate_id,payload_hash,entry_ids) VALUES($1,$2,$3,$4,$5)', [customerId, body.requestId, id, hash, JSON.stringify(entryIds)]);
      await client.query('COMMIT'); return { entryIds };
    } catch (error) { await client.query('ROLLBACK'); throw error; } finally { client.release(); }
  }
}
@Controller('me/meal-estimates')
@UseGuards(AuthGuard)
export class MealEstimateController {
  constructor(@Inject(MealEstimateService) private readonly service: MealEstimateService) {}
  @Get('status') status(@Req() req: { user: User }) { return this.service.status(customerOnly(req.user)); }
  @Post()
  @UseInterceptors(FileInterceptor('photo', { limits: { fileSize: MAX_MEAL_PHOTO_BYTES, files: 1, fields: 2, fieldSize: 6000, parts: 3 } }))
  create(@Req() req: { user: User }, @Body() body: unknown, @UploadedFile() photo?: { buffer: Buffer }) { return this.service.create(customerOnly(req.user), body, photo?.buffer); }
  @Post(':id/save') save(@Req() req: { user: User }, @Param('id') id: string, @Body() body: unknown) { return this.service.save(customerOnly(req.user), id, body); }
}
