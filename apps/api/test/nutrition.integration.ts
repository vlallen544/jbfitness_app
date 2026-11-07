import 'reflect-metadata';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import type { AddressInfo } from 'node:net';
import { test } from 'node:test';
import { NestFactory } from '@nestjs/core';
import { AppModule } from '../src/app.module';
import { Database } from '../src/database';
import { MembershipService } from '../src/memberships';
import { NutritionProvider, mapUsdaFood } from '../src/nutrition-provider';
import { nutritionTotals, scaleNutrients } from '../src/nutrition-schema';
import { addDays, todayInIndia } from '../src/workout-schema';

test('nutrition persistence, calculations, food provenance and ownership', async t => {
  const previous = { mode: process.env.NODE_ENV, enabled: process.env.ENABLE_DEV_MEMBERSHIPS, key: process.env.USDA_API_KEY };
  process.env.NODE_ENV = 'test'; process.env.ENABLE_DEV_MEMBERSHIPS = 'true'; delete process.env.USDA_API_KEY;
  const start = async () => { const app = await NestFactory.create(AppModule, { logger: false }); app.setGlobalPrefix('api/v1'); await app.listen(0, '127.0.0.1'); return app; };
  let app = await start(); let db = app.get(Database);
  const users: string[] = [];
  const request = async (path: string, token?: string, method = 'GET', body?: unknown) => {
    const r = await fetch(`http://127.0.0.1:${(app.getHttpServer().address() as AddressInfo).port}/api/v1${path}`, { method, headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) }, ...(body === undefined ? {} : { body: JSON.stringify(body) }) });
    return { status: r.status, data: await r.json() };
  };
  const customer = async () => { const r = await request('/auth/register', undefined, 'POST', { email: `nutrition-${randomUUID()}@example.test`, password: 'A-test-password-42!', displayName: 'Nutrition fixture' }); assert.equal(r.status, 201); users.push(r.data.user.id); return { id: r.data.user.id as string, token: r.data.token as string }; };
  const today = todayInIndia();
  const nutrients = { calories: 120, protein: 5, carbs: 20, fat: 2, fiber: 3, sugar: null, sodium: 200 };
  let foodId = ''; let entryId = ''; let missingEntryId = '';
  try {
    const a = await customer(); const b = await customer();
    await t.test('authentication, role and membership boundaries preserve readable history', async () => {
      assert.equal((await request('/me/nutrition')).status, 401);
      const empty = await request('/me/nutrition', a.token); assert.equal(empty.status, 200); assert.equal(empty.data.canEdit, false); assert.equal(empty.data.targets, null); assert.equal(empty.data.totals.calories.known, 0);
      assert.equal((await request('/me/nutrition/foods', a.token, 'POST', { name: 'Label fixture', sourceNote: 'Technical test values', nutrients, requestId: randomUUID() })).status, 403);
      await db.pool.query("UPDATE users SET role='trainer' WHERE id=$1", [b.id]); assert.equal((await request('/me/nutrition', b.token)).status, 403); await db.pool.query("UPDATE users SET role='customer' WHERE id=$1", [b.id]);
      for (const user of [a, b]) await app.get(MembershipService).applyTestPurchase({ customerId: user.id, planId: 'normal', eventId: randomUUID(), paymentReference: randomUUID(), amountPaise: 300000, currency: 'INR' });
    });
    await t.test('label foods reject invalid values and concurrent creation retries deduplicate', async () => {
      const body = { name: 'Technical label fixture', sourceNote: 'Test data, not a real food', nutrients, requestId: randomUUID() };
      for (const change of [{ name: '' }, { sourceNote: '' }, { nutrients: { ...nutrients, protein: -1 } }, { nutrients: { ...nutrients, calories: null } }, { customerId: b.id }]) assert.equal((await request('/me/nutrition/foods', a.token, 'POST', { ...body, ...change })).status, 400);
      const [one, two] = await Promise.all([request('/me/nutrition/foods', a.token, 'POST', body), request('/me/nutrition/foods', a.token, 'POST', body)]);
      assert.equal(one.status, 201); assert.equal(two.status, 201); assert.equal(one.data.food.id, two.data.food.id); foodId = one.data.food.id;
      assert.equal(one.data.food.source.type, 'label'); assert.equal((await request('/me/nutrition/foods', a.token, 'POST', { ...body, name: 'Different' })).status, 409);
      assert.deepEqual((await request('/me/nutrition/foods', b.token)).data.foods, []);
      assert.equal((await request('/me/nutrition/foods?q=Technical', a.token)).data.providerConfigured, false);
      assert.equal((await request('/me/nutrition/foods/usda/1234', a.token, 'POST', {})).status, 503);
    });
    await t.test('gram calculations, real dates, private foods and retry references are enforced', async () => {
      const body = { foodId, date: today, meal: 'lunch', grams: 250, requestId: randomUUID() };
      assert.equal((await request('/me/nutrition/entries', b.token, 'POST', body)).status, 404);
      for (const change of [{ grams: 0 }, { grams: -5 }, { grams: 1.001 }, { date: addDays(today, 1) }, { date: '2026-02-30' }, { meal: 'unknown' }, { customerId: b.id }]) assert.equal((await request('/me/nutrition/entries', a.token, 'POST', { ...body, ...change })).status, 400);
      const [one, two] = await Promise.all([request('/me/nutrition/entries', a.token, 'POST', body), request('/me/nutrition/entries', a.token, 'POST', body)]); assert.equal(one.status, 201); assert.equal(one.data.id, two.data.id); entryId = one.data.id;
      assert.equal((await request('/me/nutrition/entries', a.token, 'POST', { ...body, grams: 100 })).status, 409);
      const day = (await request('/me/nutrition', a.token)).data;
      assert.equal(day.entries.length, 1); assert.equal(day.totals.calories.known, 300); assert.equal(day.totals.protein.known, 12.5); assert.equal(day.totals.carbs.known, 50); assert.equal(day.totals.fat.known, 5); assert.equal(day.totals.fiber.known, 7.5); assert.equal(day.totals.sodium.known, 500); assert.equal(day.totals.sugar.complete, false);
      await db.pool.query(`UPDATE nutrition_foods SET nutrients=$2 WHERE id=$1`, [foodId, JSON.stringify({ ...nutrients, calories: 900 })]);
      assert.equal((await request('/me/nutrition', a.token)).data.totals.calories.known, 300);
      assert.deepEqual((await request('/me/nutrition', b.token)).data.entries, []);
    });
    await t.test('unknown optional nutrients stay unknown and known subtotals remain available', async () => {
      const food = await request('/me/nutrition/foods', a.token, 'POST', { name: 'Incomplete label fixture', sourceNote: 'Technical data with missing fiber', nutrients: { ...nutrients, fiber: null }, requestId: randomUUID() });
      const entry = await request('/me/nutrition/entries', a.token, 'POST', { foodId: food.data.food.id, date: today, meal: 'snack', grams: 50, requestId: randomUUID() }); missingEntryId = entry.data.id;
      const day = (await request('/me/nutrition', a.token)).data;
      assert.deepEqual(day.totals.fiber, { known: 7.5, complete: false, missingEntries: 1 }); assert.equal(day.totals.calories.known, 360);
      const scaled = scaleNutrients({ ...nutrients, fiber: null }, 33.33); assert.equal(scaled.fiber, null);
      assert.equal(nutritionTotals([{ nutrients: scaleNutrients(nutrients, .01) }, { nutrients: scaleNutrients(nutrients, .01) }]).calories.known, .02);
    });
    await t.test('edit/delete revisions reject stale writes and save retries do not duplicate changes', async () => {
      const body = { grams: 100, meal: 'dinner', revision: 1, requestId: randomUUID() };
      assert.equal((await request(`/me/nutrition/entries/${entryId}`, b.token, 'PUT', body)).status, 404);
      const save = await request(`/me/nutrition/entries/${entryId}`, a.token, 'PUT', body); assert.equal(save.status, 200); assert.equal(save.data.revision, 2);
      assert.equal((await request(`/me/nutrition/entries/${entryId}`, a.token, 'PUT', body)).data.revision, 2);
      assert.equal((await request(`/me/nutrition/entries/${entryId}`, a.token, 'PUT', { ...body, requestId: randomUUID() })).status, 409);
      const remove = { grams: 50, meal: 'snack', deleted: true, revision: 1, requestId: randomUUID() };
      assert.equal((await request(`/me/nutrition/entries/${missingEntryId}`, a.token, 'PUT', remove)).status, 200); assert.equal((await request(`/me/nutrition/entries/${missingEntryId}`, a.token, 'PUT', remove)).status, 200);
      const day = (await request('/me/nutrition', a.token)).data; assert.equal(day.entries.length, 1); assert.equal(day.entries[0].meal, 'dinner'); assert.equal(day.totals.calories.known, 120); assert.equal(day.totals.fiber.complete, true);
    });
    await t.test('targets apply from today, retain history, deduplicate saves and reject stale revisions', async () => {
      await db.pool.query('INSERT INTO nutrition_targets(customer_id,effective_from,nutrients,revision,last_request_id,last_payload_hash) VALUES($1,$2,$3,1,$4,$5)', [a.id, addDays(today, -1), JSON.stringify({ ...nutrients, calories: 1800 }), randomUUID(), 'fixture']);
      const inherited = (await request('/me/nutrition', a.token)).data.targets; assert.equal(inherited.nutrients.calories, 1800); assert.equal(inherited.revision, 0);
      const body = { date: today, nutrients: { ...nutrients, calories: 2000, protein: 100, carbs: 250, fat: 70 }, revision: 0, requestId: randomUUID() };
      assert.equal((await request('/me/nutrition/targets', a.token, 'PUT', { ...body, date: addDays(today, -1) })).status, 409);
      assert.equal((await request('/me/nutrition/targets', a.token, 'PUT', body)).status, 200); assert.equal((await request('/me/nutrition/targets', a.token, 'PUT', body)).data.revision, 1);
      assert.equal((await request('/me/nutrition/targets', a.token, 'PUT', { ...body, requestId: randomUUID() })).status, 409);
      assert.equal((await request(`/me/nutrition?date=${addDays(today, -1)}`, a.token)).data.targets.nutrients.calories, 1800); assert.equal((await request('/me/nutrition', a.token)).data.targets.nutrients.calories, 2000);
      assert.equal((await request('/me/nutrition', b.token)).data.targets, null);
    });
    await t.test('provider adapter uses full per-100-g nutrient IDs and handles incomplete data without guessing', async () => {
      const food = { fdcId: 1234, description: 'Technical provider fixture', dataType: 'SR Legacy', foodNutrients: [
        { nutrient: { id: 1008, unitName: 'KCAL' }, amount: 120 }, { nutrient: { id: 1003, unitName: 'G' }, amount: 5 }, { nutrient: { id: 1005, unitName: 'G' }, amount: 20 }, { nutrient: { id: 1004, unitName: 'G' }, amount: 2 },
      ] };
      assert.equal(mapUsdaFood(food).nutrients.fiber, null);
      assert.throws(() => mapUsdaFood({ ...food, foodNutrients: [] }));
      assert.equal(mapUsdaFood({ ...food, foodNutrients: food.foodNutrients.map(value => value.nutrient.id === 1008 ? { ...value, nutrient: { id: 2047, unitName: 'KCAL' } } : value) }).nutrients.calories, 120);
      process.env.USDA_API_KEY = 'test-placeholder-never-sent';
      const provider = app.get(NutritionProvider); provider.search = async () => [{ fdcId: 1234, name: food.description, dataType: food.dataType }]; provider.detail = async () => mapUsdaFood(food);
      assert.equal((await request('/me/nutrition/foods?q=test', a.token)).data.external[0].fdcId, 1234);
      const imported = await request('/me/nutrition/foods/usda/1234', a.token, 'POST', {}); assert.equal(imported.status, 201); assert.equal(imported.data.food.source.type, 'usda');
      assert.equal((await request('/me/nutrition/foods/usda/1234', a.token, 'POST', {})).data.food.id, imported.data.food.id);
      provider.search = async () => { throw new Error('Provider unavailable'); };
      const unavailable = await request('/me/nutrition/foods?q=Technical', a.token); assert.equal(unavailable.status, 200); assert.ok(unavailable.data.notice); assert.ok(unavailable.data.foods.length > 0);
      delete process.env.USDA_API_KEY;
    });
    await t.test('API restart preserves diary and expiry keeps history while blocking writes', async () => {
      await app.close(); app = await start(); db = app.get(Database);
      const day = (await request('/me/nutrition', a.token)).data; assert.equal(day.totals.calories.known, 120); assert.equal(day.targets.nutrients.calories, 2000);
      await db.pool.query("UPDATE memberships SET ends_at=now()-interval '1 second',starts_at=now()-interval '2 days' WHERE customer_id=$1", [a.id]);
      assert.equal((await request('/me/nutrition', a.token)).data.canEdit, false);
      assert.equal((await request(`/me/nutrition/entries/${entryId}`, a.token, 'PUT', { grams: 50, meal: 'dinner', revision: 2, requestId: randomUUID() })).status, 403);
      assert.equal((await request('/me/nutrition/entries', a.token, 'POST', { foodId, date: today, meal: 'lunch', grams: 100, requestId: randomUUID() })).status, 403);
    });
  } finally {
    if (users.length) await db.pool.query('DELETE FROM users WHERE id=ANY($1::uuid[])', [users]);
    await app.close();
    for (const [key, value] of Object.entries({ NODE_ENV: previous.mode, ENABLE_DEV_MEMBERSHIPS: previous.enabled, USDA_API_KEY: previous.key })) { if (value === undefined) delete process.env[key]; else process.env[key] = value; }
  }
});
