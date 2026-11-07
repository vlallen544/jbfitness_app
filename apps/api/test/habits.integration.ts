import 'reflect-metadata';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import type { AddressInfo } from 'node:net';
import { test } from 'node:test';
import { NestFactory } from '@nestjs/core';
import { AppModule } from '../src/app.module';
import { Database } from '../src/database';
import { MembershipService } from '../src/memberships';
import { addDays, todayInIndia } from '../src/workout-schema';
import { habitMonth, habitStats } from '../src/habits';

test('habits persist, respect ownership and calendar eligibility, and keep correct totals', async t => {
  const previous = { mode: process.env.NODE_ENV, enabled: process.env.ENABLE_DEV_MEMBERSHIPS };
  process.env.NODE_ENV = 'test'; process.env.ENABLE_DEV_MEMBERSHIPS = 'true';
  const start = async () => { const app = await NestFactory.create(AppModule, { logger: false }); app.setGlobalPrefix('api/v1'); await app.listen(0, '127.0.0.1'); return app; };
  let app = await start();
  let db = app.get(Database);
  const users: string[] = [];
  const request = async (path: string, token?: string, method = 'GET', body?: unknown) => {
    const r = await fetch(`http://127.0.0.1:${(app.getHttpServer().address() as AddressInfo).port}/api/v1${path}`, { method, headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) }, ...(body === undefined ? {} : { body: JSON.stringify(body) }) });
    return { status: r.status, data: await r.json() };
  };
  const customer = async () => { const r = await request('/auth/register', undefined, 'POST', { email: `habit-${randomUUID()}@example.test`, password: 'A-test-password-42!', displayName: 'Habit fixture' }); assert.equal(r.status, 201); users.push(r.data.user.id); return { id: r.data.user.id as string, token: r.data.token as string }; };
  const today = todayInIndia();
  let id = '';
  try {
    const a = await customer(); const b = await customer();
    await t.test('authentication, roles and membership gate writes while history remains readable', async () => {
      assert.equal((await request('/me/habits')).status, 401);
      const read = await request('/me/habits', a.token); assert.equal(read.status, 200); assert.equal(read.data.canEdit, false); assert.deepEqual(read.data.habits, []);
      assert.equal((await request('/me/habits', a.token, 'POST', { name: 'Walk', targetDays: 20, requestId: randomUUID() })).status, 403);
      await db.pool.query("UPDATE users SET role='trainer' WHERE id=$1", [b.id]);
      assert.equal((await request('/me/habits', b.token)).status, 403);
      await db.pool.query("UPDATE users SET role='customer' WHERE id=$1", [b.id]);
      for (const user of [a, b]) await app.get(MembershipService).applyTestPurchase({ customerId: user.id, planId: 'normal', eventId: randomUUID(), paymentReference: randomUUID(), amountPaise: 300000, currency: 'INR' });
    });
    await t.test('strict validation and concurrent creation retries cannot duplicate a habit', async () => {
      for (const body of [{ name: '', targetDays: 20 }, { name: 'Walk', targetDays: 32 }, { name: 'Walk', targetDays: 1.2 }, { name: 'Walk', targetDays: 20, customerId: b.id }]) assert.equal((await request('/me/habits', a.token, 'POST', { requestId: randomUUID(), ...body })).status, 400);
      const body = { name: 'Take a walk', targetDays: 25, requestId: randomUUID() };
      const [one, two] = await Promise.all([request('/me/habits', a.token, 'POST', body), request('/me/habits', a.token, 'POST', body)]);
      assert.equal(one.status, 201); assert.equal(two.status, 201); assert.equal(one.data.id, two.data.id); id = one.data.id;
      assert.equal((await request('/me/habits', a.token, 'POST', { ...body, name: 'Changed' })).status, 409);
      assert.equal((await request('/me/habits?month=2026-13', a.token)).status, 400);
      assert.equal((await request('/me/habits?month=bad', a.token)).status, 400);
    });
    await t.test('owner-only idempotent day saves and date bounds', async () => {
      const path = `/me/habits/${id}/days/${today}`;
      assert.equal((await request(path, b.token, 'PUT', { completed: true })).status, 404);
      assert.equal((await request(`/me/habits/${id}/archive`, b.token, 'PUT', {})).status, 404);
      for (const day of [addDays(today, 1), addDays(today, -1), '2026-02-30']) assert.equal((await request(`/me/habits/${id}/days/${day}`, a.token, 'PUT', { completed: true })).status, 400);
      assert.equal((await request(path, a.token, 'PUT', { completed: 'true' })).status, 400);
      const saves = await Promise.all([request(path, a.token, 'PUT', { completed: true }), request(path, a.token, 'PUT', { completed: true })]); assert.ok(saves.every(r => r.status === 200));
      const month = (await request('/me/habits', a.token)).data;
      assert.equal(month.entries.length, 1); assert.equal(month.summary.completed, 1);
      assert.equal(month.habits[0].goal, Math.min(25, Number(habitMonth(today.slice(0, 7)).last.slice(8)) - Number(today.slice(8)) + 1));
      assert.deepEqual((await request('/me/habits', b.token)).data.entries, []);
      assert.equal((await request(path, a.token, 'PUT', { completed: false })).status, 200);
      assert.equal((await request('/me/habits', a.token)).data.summary.completed, 0);
      await request(path, a.token, 'PUT', { completed: true });
    });
    await t.test('restart keeps saved checkmarks; archive retains history and locks edits', async () => {
      await app.close(); app = await start(); db = app.get(Database);
      assert.equal((await request('/me/habits', a.token)).data.summary.completed, 1);
      assert.equal((await request(`/me/habits/${id}/archive`, a.token, 'PUT', {})).status, 200);
      assert.equal((await request(`/me/habits/${id}/archive`, a.token, 'PUT', {})).status, 200);
      assert.equal((await request(`/me/habits/${id}/days/${today}`, a.token, 'PUT', { completed: false })).status, 409);
      const month = (await request('/me/habits', a.token)).data; assert.equal(month.habits[0].archivedOn, today); assert.equal(month.summary.completed, 1); assert.equal(month.habits[0].goal, 1);
      await db.pool.query("UPDATE memberships SET ends_at=now()-interval '1 second',starts_at=now()-interval '2 days' WHERE customer_id=$1", [a.id]);
      const expired = await request('/me/habits', a.token); assert.equal(expired.status, 200); assert.equal(expired.data.canEdit, false); assert.equal(expired.data.summary.completed, 1);
      assert.equal((await request('/me/habits', a.token, 'POST', { name: 'Read', targetDays: 5, requestId: randomUUID() })).status, 403);
    });
    await t.test('leap months, eligible-day targets and capped per-habit goal totals agree', () => {
      assert.equal(habitMonth('2028-02').last, '2028-02-29');
      const result = habitStats([{ id: 'a', name: 'Walk', targetDays: 31, startsOn: '2028-02-28', archivedOn: null }, { id: 'b', name: 'Read', targetDays: 1, startsOn: '2028-02-01', archivedOn: '2028-02-02' }], [{ habitId: 'a', date: '2028-02-28', completed: true }, { habitId: 'b', date: '2028-02-01', completed: true }, { habitId: 'b', date: '2028-02-02', completed: true }], '2028-02-01', '2028-02-29', '2028-02-29');
      assert.equal(result.habits[0].goal, 2); assert.equal(result.summary.completed, 3); assert.equal(result.summary.goal, 3); assert.equal(result.summary.progress, 2 / 3);
      assert.equal(result.days.reduce((sum, day) => sum + day.completed, 0), 3);
    });
  } finally {
    if (users.length) await db.pool.query('DELETE FROM users WHERE id=ANY($1::uuid[])', [users]);
    await app.close();
    if (previous.mode === undefined) delete process.env.NODE_ENV; else process.env.NODE_ENV = previous.mode;
    if (previous.enabled === undefined) delete process.env.ENABLE_DEV_MEMBERSHIPS; else process.env.ENABLE_DEV_MEMBERSHIPS = previous.enabled;
  }
});
