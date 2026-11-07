import { BadRequestException, Body, ConflictException, Controller, Delete, Get, GoneException, Inject, Injectable, NotFoundException, Param, Post, Put, Req, Res, UploadedFile, UseGuards, UseInterceptors } from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import { createHash, randomUUID } from 'node:crypto';
import type { ServerResponse } from 'node:http';
import type { PoolClient } from 'pg';
import { z } from 'zod';
import { Database } from './database';
import { AuthGuard, User } from './auth';
import { customerOnly } from './workouts';
import { MembershipService } from './memberships';
import { nutritionDate } from './nutrition-schema';
import { todayInIndia } from './workout-schema';
import { normalizeMealPhoto, MAX_MEAL_PHOTO_BYTES } from './meal-estimates';

const number = (max: number) => z.number().gt(0).max(max).refine(n => Math.abs(n * 100 - Math.round(n * 100)) < .000001).nullable().default(null);
export const measurementsSchema = z.object({ weight: number(500), waist: number(400), chest: number(400), arms: number(200), thighs: number(250) }).strict();
const createSchema = z.object({ date: z.string(), measurements: measurementsSchema, requestId: z.uuid() }).strict();
const updateSchema = z.object({ measurements: measurementsSchema, revision: z.number().int().positive(), requestId: z.uuid() }).strict();
const photoSchema = z.object({ angle: z.enum(['front', 'side', 'back']), requestId: z.uuid() }).strict();
function parse<T>(schema: z.ZodType<T>, input: unknown): T { const r = schema.safeParse(input); if (!r.success) throw new BadRequestException('Check the date, measurements, photo angle and save reference. Use positive values with up to two decimal places.'); return r.data; }
const hash = (value: string | Buffer) => createHash('sha256').update(value).digest('hex');
const select = `SELECT id,to_char(day,'YYYY-MM-DD') AS date,measurements,revision FROM body_progress`;

@Injectable()
export class BodyProgressService {
  constructor(@Inject(Database) private readonly db: Database, @Inject(MembershipService) private readonly memberships: MembershipService) {}
  private async transaction<T>(customerId: string, action: (client: PoolClient) => Promise<T>) {
    const c = await this.db.pool.connect();
    try { await c.query('BEGIN'); await c.query('SELECT id FROM users WHERE id=$1 FOR UPDATE', [customerId]); const result = await action(c); await c.query('COMMIT'); return result; }
    catch (error) { await c.query('ROLLBACK'); throw error; } finally { c.release(); }
  }
  async list(customerId: string) {
    const c = await this.db.pool.connect();
    try {
      await c.query('BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY');
      const records = (await c.query(`${select} WHERE customer_id=$1 AND NOT deleted ORDER BY day DESC,id`, [customerId])).rows;
      const photos = (await c.query(`SELECT p.id,p.record_id AS "recordId",p.angle FROM body_progress_photos p JOIN body_progress r ON r.id=p.record_id WHERE p.customer_id=$1 AND p.jpeg IS NOT NULL AND NOT r.deleted ORDER BY p.angle`, [customerId])).rows;
      await c.query('COMMIT');
      const membership = await this.memberships.summary(customerId);
      return { today: todayInIndia(), timezone: 'Asia/Kolkata', canEdit: membership.entitlements.progressTracking === true, records: records.map(r => ({ ...r, photos: photos.filter(p => p.recordId === r.id).map(({ id, angle }) => ({ id, angle })) })) };
    } catch (error) { await c.query('ROLLBACK'); throw error; } finally { c.release(); }
  }
  async create(customerId: string, input: unknown) {
    const body = parse(createSchema, input); nutritionDate(body.date);
    await this.memberships.requireEntitlement(customerId, 'progressTracking');
    const digest = hash(JSON.stringify({ date: body.date, measurements: body.measurements }));
    return this.transaction(customerId, async c => {
      const old = (await c.query('SELECT * FROM body_progress WHERE customer_id=$1 AND create_request_id=$2', [customerId, body.requestId])).rows[0];
      if (old) { if (old.create_hash !== digest) throw new ConflictException('This reference was used for different measurements.'); if (old.deleted) throw new GoneException('This record was deleted. Refresh before adding it again.'); return { id: old.id }; }
      if ((await c.query('SELECT 1 FROM body_progress WHERE customer_id=$1 AND day=$2 AND NOT deleted', [customerId, body.date])).rowCount) throw new ConflictException('A record already exists for this date. Edit that record.');
      const count = (await c.query('SELECT count(*)::int AS count FROM body_progress WHERE customer_id=$1 AND NOT deleted', [customerId])).rows[0].count;
      if (count >= 3660) throw new BadRequestException('The progress record limit has been reached.');
      const id = randomUUID(); await c.query('INSERT INTO body_progress(id,customer_id,day,measurements,create_request_id,create_hash) VALUES($1,$2,$3,$4,$5,$6)', [id, customerId, body.date, JSON.stringify(body.measurements), body.requestId, digest]); return { id };
    });
  }
  async update(customerId: string, idValue: string, input: unknown) {
    const id = parse(z.uuid(), idValue); const body = parse(updateSchema, input);
    await this.memberships.requireEntitlement(customerId, 'progressTracking');
    return this.transaction(customerId, async c => {
      const row = (await c.query('SELECT * FROM body_progress WHERE id=$1 AND customer_id=$2 FOR UPDATE', [id, customerId])).rows[0];
      if (!row || row.deleted) throw new NotFoundException('Progress record not found.');
      const digest = hash(JSON.stringify(body));
      const old = (await c.query('SELECT * FROM body_progress_changes WHERE record_id=$1 AND request_id=$2', [id, body.requestId])).rows[0];
      if (old) { if (old.payload_hash !== digest) throw new ConflictException('This edit reference has different values.'); return { revision: old.result_revision }; }
      if (row.revision !== body.revision) throw new ConflictException('This record changed. Refresh before editing again.');
      const revision = row.revision + 1;
      await c.query('UPDATE body_progress SET measurements=$2,revision=$3 WHERE id=$1', [id, JSON.stringify(body.measurements), revision]);
      await c.query('INSERT INTO body_progress_changes VALUES($1,$2,$3,$4)', [id, body.requestId, digest, revision]); return { revision };
    });
  }
  async remove(customerId: string, idValue: string, input: unknown) {
    const id = parse(z.uuid(), idValue); const body = parse(z.object({ revision: z.number().int().positive() }).strict(), input);
    return this.transaction(customerId, async c => {
      const row = (await c.query('SELECT * FROM body_progress WHERE id=$1 AND customer_id=$2 FOR UPDATE', [id, customerId])).rows[0];
      if (!row) throw new NotFoundException('Progress record not found.');
      if (!row.deleted) {
        if (row.revision !== body.revision) throw new ConflictException('This record changed. Refresh before deleting.');
        await c.query('DELETE FROM body_progress_photos WHERE record_id=$1', [id]);
        await c.query("UPDATE body_progress SET deleted=true,measurements='{}'::jsonb,revision=revision+1 WHERE id=$1", [id]);
      }
      return { deleted: true };
    });
  }
  async upload(customerId: string, idValue: string, input: unknown, bytes?: Buffer) {
    const id = parse(z.uuid(), idValue); const body = parse(photoSchema, input);
    await this.memberships.requireEntitlement(customerId, 'progressTracking');
    if (!bytes) throw new BadRequestException('Choose a JPEG, PNG or WebP photo.');
    const jpeg = await normalizeMealPhoto(bytes);
    if (jpeg.length > 1024 * 1024) throw new BadRequestException('Choose a smaller photo. The processed photo must fit within 1 MB.');
    const digest = hash(JSON.stringify({ id, angle: body.angle, photo: hash(jpeg) }));
    return this.transaction(customerId, async c => {
      const row = (await c.query('SELECT id FROM body_progress WHERE id=$1 AND customer_id=$2 AND NOT deleted FOR UPDATE', [id, customerId])).rows[0];
      if (!row) throw new NotFoundException('Progress record not found.');
      const old = (await c.query('SELECT id,create_hash,jpeg IS NOT NULL AS available FROM body_progress_photos WHERE customer_id=$1 AND create_request_id=$2', [customerId, body.requestId])).rows[0];
      if (old) { if (old.create_hash !== digest) throw new ConflictException('This photo reference was used for another upload.'); if (!old.available) throw new GoneException('This photo was deleted. Choose it again to upload.'); return { id: old.id }; }
      if ((await c.query('SELECT 1 FROM body_progress_photos WHERE record_id=$1 AND angle=$2 AND jpeg IS NOT NULL', [id, body.angle])).rowCount) throw new ConflictException('A photo already exists for this angle. Delete it before replacing.');
      const count = (await c.query('SELECT count(*)::int AS count FROM body_progress_photos WHERE customer_id=$1 AND jpeg IS NOT NULL', [customerId])).rows[0].count;
      if (count >= 300) throw new BadRequestException('Keep up to 300 progress photos. Delete older photos before adding more.');
      const photoId = randomUUID(); await c.query('INSERT INTO body_progress_photos(id,record_id,customer_id,angle,jpeg,create_request_id,create_hash) VALUES($1,$2,$3,$4,$5,$6,$7)', [photoId, id, customerId, body.angle, jpeg, body.requestId, digest]); return { id: photoId };
    });
  }
  async photo(customerId: string, idValue: string) {
    const id = parse(z.uuid(), idValue);
    const row = (await this.db.pool.query('SELECT p.jpeg FROM body_progress_photos p JOIN body_progress r ON r.id=p.record_id WHERE p.id=$1 AND p.customer_id=$2 AND p.jpeg IS NOT NULL AND NOT r.deleted', [id, customerId])).rows[0];
    if (!row) throw new NotFoundException('Progress photo not found.'); return row.jpeg as Buffer;
  }
  async removePhoto(customerId: string, idValue: string) {
    const id = parse(z.uuid(), idValue);
    return this.transaction(customerId, async c => { const r = await c.query('UPDATE body_progress_photos SET jpeg=NULL WHERE id=$1 AND customer_id=$2 RETURNING id', [id, customerId]); if (!r.rowCount) throw new NotFoundException('Progress photo not found.'); return { deleted: true }; });
  }
}
@Controller('me/progress')
@UseGuards(AuthGuard)
export class BodyProgressController {
  constructor(@Inject(BodyProgressService) private readonly progress: BodyProgressService) {}
  @Get() list(@Req() r: { user: User }) { return this.progress.list(customerOnly(r.user)); }
  @Post() create(@Req() r: { user: User }, @Body() b: unknown) { return this.progress.create(customerOnly(r.user), b); }
  @Put(':id') update(@Req() r: { user: User }, @Param('id') id: string, @Body() b: unknown) { return this.progress.update(customerOnly(r.user), id, b); }
  @Put(':id/delete') remove(@Req() r: { user: User }, @Param('id') id: string, @Body() b: unknown) { return this.progress.remove(customerOnly(r.user), id, b); }
  @Post(':id/photos')
  @UseInterceptors(FileInterceptor('photo', { limits: { fileSize: MAX_MEAL_PHOTO_BYTES, files: 1, fields: 2, fieldSize: 100, parts: 3 } }))
  upload(@Req() r: { user: User }, @Param('id') id: string, @Body() b: unknown, @UploadedFile() file?: { buffer: Buffer }) { return this.progress.upload(customerOnly(r.user), id, b, file?.buffer); }
  @Get('photos/:id') async photo(@Req() r: { user: User }, @Param('id') id: string, @Res() res: ServerResponse) { const bytes = await this.progress.photo(customerOnly(r.user), id); res.setHeader('Content-Type', 'image/jpeg'); res.setHeader('Cache-Control', 'private, no-store'); res.setHeader('X-Content-Type-Options', 'nosniff'); res.setHeader('Content-Length', bytes.length); res.end(bytes); }
  @Delete('photos/:id') removePhoto(@Req() r: { user: User }, @Param('id') id: string) { return this.progress.removePhoto(customerOnly(r.user), id); }
}
