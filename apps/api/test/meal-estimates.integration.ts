import 'reflect-metadata';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { test } from 'node:test';
import type { AddressInfo } from 'node:net';
import sharp from 'sharp';
import { NestFactory } from '@nestjs/core';
import { AppModule } from '../src/app.module';
import { Database } from '../src/database';
import { MembershipService } from '../src/memberships';
import { MealEstimateProvider } from '../src/meal-estimate-provider';
import { MAX_MEAL_PHOTO_BYTES } from '../src/meal-estimates';
import { todayInIndia } from '../src/workout-schema';

const draft = () => ({ status: 'estimated' as const, clarification: null, uncertainty: 'high' as const, assumptions: ['Assumed 150 g cooked rice; cooking oil is uncertain.'], items: [{ name: 'Cooked rice (estimated fixture)', grams: 150, nutrients: { calories: 130, protein: 2.7, carbs: 28, fat: .3, fiber: null, sugar: null, sodium: 0 } }] });
test('photo/text meal estimate drafts, privacy, review and usage controls', async t => {
  const previous = { NODE_ENV: process.env.NODE_ENV, ENABLE_DEV_MEMBERSHIPS: process.env.ENABLE_DEV_MEMBERSHIPS, ENABLE_MEAL_AI: process.env.ENABLE_MEAL_AI, OPENAI_API_KEY: process.env.OPENAI_API_KEY, MEAL_AI_MODEL: process.env.MEAL_AI_MODEL };
  Object.assign(process.env, { NODE_ENV: 'test', ENABLE_DEV_MEMBERSHIPS: 'true', ENABLE_MEAL_AI: 'false', OPENAI_API_KEY: 'test-key-never-sent', MEAL_AI_MODEL: 'test-model' });
  const start = async () => { const app = await NestFactory.create(AppModule, { logger: false }); app.setGlobalPrefix('api/v1'); await app.listen(0, '127.0.0.1'); return app; };
  let app = await start(); let db = app.get(Database);
  const users: string[] = [];
  const request = async (path: string, token?: string, method = 'GET', body?: unknown) => {
    const r = await fetch(`http://127.0.0.1:${(app.getHttpServer().address() as AddressInfo).port}/api/v1${path}`, { method, headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) }, ...(body === undefined ? {} : { body: JSON.stringify(body) }) });
    return { status: r.status, data: await r.json() };
  };
  const upload = async (token: string, bytes: Buffer, ref = randomUUID(), description = '') => {
    const form = new FormData(); form.set('description', description); form.set('requestId', ref); form.set('photo', new Blob([new Uint8Array(bytes)], { type: 'application/octet-stream' }), 'meal');
    const r = await fetch(`http://127.0.0.1:${(app.getHttpServer().address() as AddressInfo).port}/api/v1/me/meal-estimates`, { method: 'POST', headers: { Authorization: `Bearer ${token}` }, body: form }); return { status: r.status, data: await r.json() };
  };
  const customer = async () => { const r = await request('/auth/register', undefined, 'POST', { email: `meal-ai-${randomUUID()}@example.test`, password: 'A-test-password-42!', displayName: 'Meal estimate fixture' }); assert.equal(r.status, 201); users.push(r.data.user.id); return { id: r.data.user.id as string, token: r.data.token as string }; };
  let calls = 0; let lastPhoto: Buffer | undefined; let estimateId = '';
  try {
    const a = await customer(); const b = await customer();
    const provider = app.get(MealEstimateProvider);
    provider.estimate = async (_description, jpeg) => { calls++; lastPhoto = jpeg; return { draft: draft(), usage: { inputTokens: 10, outputTokens: 10 } }; };
    await t.test('authentication, role, membership and disabled-provider states do not charge a call', async () => {
      assert.equal((await request('/me/meal-estimates/status')).status, 401);
      assert.equal((await request('/me/meal-estimates', a.token, 'POST', { requestId: randomUUID(), description: 'Rice' })).status, 403);
      await db.pool.query("UPDATE users SET role='trainer' WHERE id=$1", [b.id]); assert.equal((await request('/me/meal-estimates/status', b.token)).status, 403); await db.pool.query("UPDATE users SET role='customer' WHERE id=$1", [b.id]);
      for (const user of [a, b]) await app.get(MembershipService).applyTestPurchase({ customerId: user.id, planId: 'normal', eventId: randomUUID(), paymentReference: randomUUID(), amountPaise: 300000, currency: 'INR' });
      assert.equal((await request('/me/meal-estimates/status', a.token)).data.configured, false);
      assert.equal((await request('/me/meal-estimates', a.token, 'POST', { requestId: randomUUID(), description: 'Rice' })).status, 503); assert.equal(calls, 0);
      process.env.ENABLE_MEAL_AI = 'true';
    });
    await t.test('text estimate is a labelled draft, not an automatic diary entry; retries reuse it', async () => {
      const body = { requestId: randomUUID(), description: 'MARKER_PRIVATE_DESCRIPTION rice with dal' };
      assert.equal((await request('/me/meal-estimates', a.token, 'POST', { requestId: randomUUID(), description: '' })).status, 400);
      assert.equal((await request('/me/meal-estimates', a.token, 'POST', { ...body, model: 'override' })).status, 400);
      const result = await request('/me/meal-estimates', a.token, 'POST', body); assert.equal(result.status, 201); estimateId = result.data.id;
      assert.equal(result.data.isEstimated, true); assert.equal(result.data.inputKind, 'text'); assert.equal(result.data.totals.calories.known, 195); assert.equal(result.data.totals.fiber.complete, false);
      assert.equal((await request('/me/nutrition', a.token)).data.entries.length, 0);
      assert.equal((await request('/me/meal-estimates', a.token, 'POST', body)).data.id, estimateId); assert.equal(calls, 1);
      assert.equal((await request('/me/meal-estimates', a.token, 'POST', { ...body, description: 'Different dish' })).status, 409);
      const row = (await db.pool.query('SELECT * FROM meal_estimates WHERE id=$1', [estimateId])).rows[0]; assert.ok(!JSON.stringify(row).includes('MARKER_PRIVATE_DESCRIPTION')); assert.ok(!JSON.stringify(row).includes('test-key-never-sent'));
    });
    await t.test('photo uploads are decoded, metadata stripped, bounded and never stored as raw media', async () => {
      const photo = await sharp({ create: { width: 20, height: 10, channels: 3, background: '#245e48' } }).jpeg().withMetadata({ orientation: 6 }).toBuffer();
      const result = await upload(a.token, photo); assert.equal(result.status, 201); assert.equal(result.data.inputKind, 'photo');
      assert.ok(lastPhoto); const metadata = await sharp(lastPhoto!).metadata(); assert.equal(metadata.format, 'jpeg'); assert.equal(metadata.exif, undefined); assert.equal(metadata.orientation, undefined); assert.equal(metadata.width, 10); assert.equal(metadata.height, 20);
      const combined = await upload(a.token, photo, randomUUID(), 'अ'.repeat(1200)); assert.equal(combined.status, 201); assert.equal(combined.data.inputKind, 'photo_text');
      assert.equal((await upload(a.token, Buffer.from('<svg><script>bad</script></svg>'))).status, 400);
      assert.equal((await upload(a.token, Buffer.alloc(MAX_MEAL_PHOTO_BYTES + 1))).status, 413);
      const row = (await db.pool.query('SELECT * FROM meal_estimates WHERE id=$1', [result.data.id])).rows[0]; assert.ok(!JSON.stringify(row).includes(photo.toString('base64')));
    });
    await t.test('reviewed corrections save atomically with estimate provenance and duplicate-save protection', async () => {
      const body = { requestId: randomUUID(), date: todayInIndia(), meal: 'lunch', items: [{ ...draft().items[0], grams: 200 }] };
      assert.equal((await request(`/me/meal-estimates/${estimateId}/save`, b.token, 'POST', body)).status, 404);
      const [one, two] = await Promise.all([request(`/me/meal-estimates/${estimateId}/save`, a.token, 'POST', body), request(`/me/meal-estimates/${estimateId}/save`, a.token, 'POST', body)]);
      assert.equal(one.status, 201); assert.deepEqual(one.data.entryIds, two.data.entryIds);
      const day = (await request('/me/nutrition', a.token)).data; assert.equal(day.entries.length, 1); assert.equal(day.totals.calories.known, 260); assert.equal(day.estimatedEntryCount, 1); assert.equal(day.entries[0].food.source.label, 'AI estimate'); assert.equal(day.entries[0].food.source.editedByUser, true);
      assert.equal((await request(`/me/meal-estimates/${estimateId}/save`, a.token, 'POST', { ...body, meal: 'dinner' })).status, 409);
      assert.equal((await request(`/me/meal-estimates/${estimateId}/save`, a.token, 'POST', { ...body, requestId: randomUUID(), items: [{ ...body.items[0], grams: -1 }] })).status, 400);
      await db.pool.query("UPDATE meal_estimates SET expires_at=now()-interval '1 second' WHERE id=$1", [estimateId]);
      assert.equal((await request(`/me/meal-estimates/${estimateId}/save`, a.token, 'POST', { ...body, requestId: randomUUID() })).status, 410);
      assert.equal((await request(`/me/meal-estimates/${estimateId}/save`, a.token, 'POST', body)).status, 201);
    });
    await t.test('unclear, invalid and failed provider results cannot become food logs', async () => {
      provider.estimate = async () => ({ draft: { ...draft(), status: 'unclear' as any, clarification: 'Describe the dish or choose another photo.', items: [] }, usage: { inputTokens: null, outputTokens: null } });
      const unclear = await request('/me/meal-estimates', a.token, 'POST', { requestId: randomUUID(), description: 'Unclear input fixture' }); assert.equal(unclear.status, 201); assert.equal(unclear.data.status, 'unclear');
      assert.equal((await request(`/me/meal-estimates/${unclear.data.id}/save`, a.token, 'POST', { requestId: randomUUID(), date: todayInIndia(), meal: 'dinner', items: draft().items })).status, 400);
      provider.estimate = async () => ({ draft: { ...draft(), items: [{ ...draft().items[0], nutrients: { ...draft().items[0].nutrients, calories: 99999 } }] }, usage: { inputTokens: null, outputTokens: null } });
      const bad = { requestId: randomUUID(), description: 'Invalid provider fixture' }; assert.equal((await request('/me/meal-estimates', a.token, 'POST', bad)).status, 502); assert.equal((await request('/me/meal-estimates', a.token, 'POST', bad)).status, 409);
      assert.equal((await request('/me/nutrition', a.token)).data.entries.length, 1);
    });
    await t.test('concurrent analysis attempts cannot double-charge the same or another request', async () => {
      let release!: () => void; let entered!: () => void;
      const started = new Promise<void>(resolve => entered = resolve); const gate = new Promise<void>(resolve => release = resolve);
      provider.estimate = async () => { calls++; entered(); await gate; return { draft: draft(), usage: { inputTokens: 1, outputTokens: 1 } }; };
      const body = { requestId: randomUUID(), description: 'Concurrent analysis fixture' }; const first = request('/me/meal-estimates', a.token, 'POST', body); await started;
      assert.equal((await request('/me/meal-estimates', a.token, 'POST', body)).status, 409);
      assert.equal((await request('/me/meal-estimates', a.token, 'POST', { ...body, requestId: randomUUID() })).status, 409);
      release(); assert.equal((await first).status, 201);
    });
    await t.test('real provider transport uses image input, strict JSON and disabled response storage', async () => {
      const originalFetch = globalThis.fetch;
      globalThis.fetch = async (url, init) => {
        assert.equal(url, 'https://api.openai.com/v1/responses');
        const body = JSON.parse(init!.body as string);
        assert.equal(body.model, 'test-model'); assert.equal(body.store, false); assert.equal(body.text.format.strict, true); assert.equal(body.text.format.type, 'json_schema'); assert.equal(body.tools, undefined);
        assert.equal(body.input[0].content[1].type, 'input_image'); assert.match(body.input[0].content[1].image_url, /^data:image\/jpeg;base64,/);
        assert.ok(!JSON.stringify(body).includes('test-key-never-sent'));
        return new Response(JSON.stringify({ status: 'completed', output: [{ content: [{ type: 'output_text', text: JSON.stringify(draft()) }] }], usage: { input_tokens: 20, output_tokens: 30 } }), { status: 200 });
      };
      try {
        const result = await new MealEstimateProvider().estimate('Rice fixture', Buffer.from('technical image fixture'));
        assert.equal(result.draft.items.length, 1); assert.equal(result.usage.inputTokens, 20);
      } finally { globalThis.fetch = originalFetch; }
    });
    await t.test('daily usage limit and restart/expiry preserve recorded estimate history', async () => {
      const count = (await db.pool.query('SELECT count(*)::int AS count FROM meal_estimates WHERE customer_id=$1', [a.id])).rows[0].count;
      for (let i = count; i < 10; i++) await db.pool.query(`INSERT INTO meal_estimates(id,customer_id,request_id,input_hash,input_kind,status,model) VALUES($1,$2,$3,'fixture','text','failed','test')`, [randomUUID(), a.id, randomUUID()]);
      assert.equal((await request('/me/meal-estimates/status', a.token)).data.remainingToday, 0);
      assert.equal((await request('/me/meal-estimates', a.token, 'POST', { requestId: randomUUID(), description: 'Over quota' })).status, 429);
      await app.close(); app = await start(); db = app.get(Database);
      const day = (await request('/me/nutrition', a.token)).data; assert.equal(day.estimatedEntryCount, 1); assert.equal(day.totals.calories.known, 260);
      await db.pool.query("UPDATE memberships SET ends_at=now()-interval '1 second',starts_at=now()-interval '2 days' WHERE customer_id=$1", [a.id]);
      assert.equal((await request('/me/meal-estimates/status', a.token)).data.entitled, false);
      assert.equal((await request(`/me/meal-estimates/${estimateId}/save`, a.token, 'POST', { requestId: randomUUID(), date: todayInIndia(), meal: 'lunch', items: draft().items })).status, 403);
      assert.equal((await request('/me/nutrition', a.token)).data.estimatedEntryCount, 1);
    });
  } finally {
    if (users.length) await db.pool.query('DELETE FROM users WHERE id=ANY($1::uuid[])', [users]);
    await app.close(); for (const [key, value] of Object.entries(previous)) { if (value === undefined) delete process.env[key]; else process.env[key] = value; }
  }
});
