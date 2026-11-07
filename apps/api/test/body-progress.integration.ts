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
import { todayInIndia, addDays } from '../src/workout-schema';

test('private dated body measurements, photos and history', async t => {
  const previous = { NODE_ENV: process.env.NODE_ENV, ENABLE_DEV_MEMBERSHIPS: process.env.ENABLE_DEV_MEMBERSHIPS };
  Object.assign(process.env, { NODE_ENV: 'test', ENABLE_DEV_MEMBERSHIPS: 'true' });
  const start = async () => { const a = await NestFactory.create(AppModule, { logger: false }); a.setGlobalPrefix('api/v1'); await a.listen(0, '127.0.0.1'); return a; };
  let app = await start(), db = app.get(Database);
  const users: string[] = [];
  const base = () => `http://127.0.0.1:${(app.getHttpServer().address() as AddressInfo).port}/api/v1/me/progress`;
  const request = async (path: string, token?: string, method = 'GET', body?: unknown) => {
    const response = await fetch(base()+path, { method, headers: { 'Content-Type': 'application/json', ...(token ? {Authorization: `Bearer ${token}`} : {}) }, ...(body === undefined ? {} : {body: JSON.stringify(body)}) });
    return { status: response.status, data: await response.json() };
  };
  const customer = async () => {
    const response = await fetch(base().replace('/me/progress','/auth/register'), {method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({email:`body-${randomUUID()}@example.test`,password:'Progress-test-password-42!',displayName:'Progress fixture'})});
    const body = await response.json(); assert.equal(response.status,201); users.push(body.user.id); return {id:body.user.id,token:body.token};
  };
  const purchase = async (id: string) => app.get(MembershipService).applyTestPurchase({customerId:id,planId:'normal',eventId:randomUUID(),paymentReference:randomUUID(),amountPaise:300000,currency:'INR'});
  const upload = async (record: string, token: string, photo: Buffer, angle='front', ref=randomUUID()) => {
    const form=new FormData(); form.set('photo',new Blob([new Uint8Array(photo)]),'progress'); form.set('angle',angle); form.set('requestId',ref);
    const response=await fetch(`${base()}/${record}/photos`,{method:'POST',headers:{Authorization:`Bearer ${token}`},body:form});return {status:response.status,data:await response.json()};
  };
  let id='', photoId='';
  const date=todayInIndia();
  const photo=await sharp({create:{width:30,height:20,channels:3,background:'#295e48'}}).jpeg().withMetadata({orientation:6}).toBuffer();
  try {
    const a=await customer(), b=await customer();
    await t.test('authentication, customer roles and paid writes are enforced',async()=>{
      assert.equal((await request('')).status,401);
      assert.equal((await request('',a.token)).data.canEdit,false);
      assert.equal((await request('',a.token,'POST',{date,measurements:{weight:80},requestId:randomUUID()})).status,403);
      await db.pool.query("UPDATE users SET role='trainer' WHERE id=$1",[b.id]); assert.equal((await request('',b.token)).status,403); await db.pool.query("UPDATE users SET role='customer' WHERE id=$1",[b.id]);
      await purchase(a.id); await purchase(b.id);
    });
    await t.test('real dates and positive optional measurements; duplicate creates are serialized',async()=>{
      for(const body of [{date:addDays(date,1),measurements:{}},{date:'2026-02-30',measurements:{}},{date,measurements:{weight:0}},{date,measurements:{waist:80.123}},{date,measurements:{weight:'Infinity'}},{date,measurements:{bodyFat:20}}]) assert.equal((await request('',a.token,'POST',{...body,requestId:randomUUID()})).status,400);
      const body={date,measurements:{weight:80.5,waist:88},requestId:randomUUID()};
      const [x,y]=await Promise.all([request('',a.token,'POST',body),request('',a.token,'POST',body)]); assert.equal(x.status,201);assert.equal(x.data.id,y.data.id);id=x.data.id;
      assert.equal((await request('',a.token,'POST',{...body,measurements:{weight:81}})).status,409);
      assert.equal((await request('',a.token,'POST',{...body,requestId:randomUUID()})).status,409);
      const list=(await request('',a.token)).data; assert.equal(list.records.length,1);assert.equal(list.records[0].measurements.chest,null);
      assert.equal((await request('',b.token)).data.records.length,0);
    });
    await t.test('revision checks prevent lost edits and retry references preserve a single update',async()=>{
      const body={measurements:{weight:79,waist:86},revision:1,requestId:randomUUID()};
      assert.equal((await request(`/${id}`,b.token,'PUT',body)).status,404);
      const [x,y]=await Promise.all([request(`/${id}`,a.token,'PUT',body),request(`/${id}`,a.token,'PUT',body)]);assert.equal(x.status,200);assert.equal(x.data.revision,2);assert.equal(y.data.revision,2);
      assert.equal((await request(`/${id}`,a.token,'PUT',{...body,requestId:randomUUID()})).status,409);
      assert.equal((await request(`/${id}`,a.token,'PUT',{...body,measurements:{weight:78}})).status,409);
      assert.equal((await request(`/${id}/delete`,a.token,'PUT',{revision:1})).status,409);
    });
    await t.test('photo uploads strip metadata, preserve orientation and deduplicate concurrent requests',async()=>{
      assert.equal((await upload(id,b.token,photo)).status,404);
      const ref=randomUUID();const [x,y]=await Promise.all([upload(id,a.token,photo,'front',ref),upload(id,a.token,photo,'front',ref)]);assert.equal(x.status,201);assert.equal(y.data.id,x.data.id);photoId=x.data.id;
      assert.equal((await upload(id,a.token,photo)).status,409);
      assert.equal((await upload(id,a.token,photo,'side',ref)).status,409);
      assert.equal((await upload(id,a.token,Buffer.from('<svg/>'),'side')).status,400);
      assert.equal((await upload(id,a.token,Buffer.alloc(4*1024*1024+1),'side')).status,413);
      assert.equal((await upload(id,a.token,photo,'unknown')).status,400);
      const own=await fetch(`${base()}/photos/${photoId}`,{headers:{Authorization:`Bearer ${a.token}`}});assert.equal(own.status,200);assert.equal(own.headers.get('cache-control'),'private, no-store');assert.equal(own.headers.get('content-type'),'image/jpeg');
      const meta=await sharp(Buffer.from(await own.arrayBuffer())).metadata();assert.equal(meta.width,20);assert.equal(meta.height,30);assert.equal(meta.exif,undefined);assert.equal(meta.orientation,undefined);
      assert.equal((await request(`/photos/${photoId}`)).status,401);assert.equal((await request(`/photos/${photoId}`,b.token)).status,404);
      const list=(await request('',a.token)).data;assert.equal(list.records[0].photos.length,1);assert.ok(!JSON.stringify(list).includes('jpeg'));assert.ok(!JSON.stringify(list).includes('Bearer'));
    });
    await t.test('photo deletion removes bytes, retries safely and permits a new upload for the angle',async()=>{
      assert.equal((await request(`/photos/${photoId}`,b.token,'DELETE')).status,404);
      assert.equal((await request(`/photos/${photoId}`,a.token,'DELETE')).status,200);assert.equal((await request(`/photos/${photoId}`,a.token,'DELETE')).status,200);
      assert.equal((await request(`/photos/${photoId}`,a.token)).status,404);
      assert.equal((await db.pool.query('SELECT jpeg FROM body_progress_photos WHERE id=$1',[photoId])).rows[0].jpeg,null);
      const x=await upload(id,a.token,photo);assert.equal(x.status,201);photoId=x.data.id;
      await upload(id,a.token,photo,'side');await upload(id,a.token,photo,'back');assert.equal((await request('',a.token)).data.records[0].photos.length,3);
    });
    await t.test('historical records and private photos survive restart and membership expiry',async()=>{
      assert.equal((await request('',a.token,'POST',{date:addDays(date,-7),measurements:{weight:82},requestId:randomUUID()})).status,201);
      await app.close();app=await start();db=app.get(Database);
      const list=(await request('',a.token)).data;assert.equal(list.records.length,2);assert.equal(list.records[0].measurements.weight,79);assert.equal(list.records[1].measurements.weight,82);
      await db.pool.query("UPDATE memberships SET ends_at=now()-interval '1 second',starts_at=now()-interval '2 days' WHERE customer_id=$1",[a.id]);
      assert.equal((await request('',a.token)).data.canEdit,false);
      assert.equal((await request(`/${id}`,a.token,'PUT',{measurements:{weight:78},revision:2,requestId:randomUUID()})).status,403);
      assert.equal((await upload(id,a.token,photo)).status,403);
      assert.equal((await fetch(`${base()}/photos/${photoId}`,{headers:{Authorization:`Bearer ${a.token}`}})).status,200);
    });
    await t.test('owners can delete expired records and all their photos; deleted references cannot resurrect them',async()=>{
      assert.equal((await request(`/${id}/delete`,b.token,'PUT',{revision:2})).status,404);
      assert.equal((await request(`/${id}/delete`,a.token,'PUT',{revision:2})).status,200);assert.equal((await request(`/${id}/delete`,a.token,'PUT',{revision:2})).status,200);
      assert.equal((await request(`/photos/${photoId}`,a.token)).status,404);
      assert.equal((await db.pool.query('SELECT count(*)::int AS n FROM body_progress_photos WHERE record_id=$1',[id])).rows[0].n,0);
      assert.deepEqual((await db.pool.query('SELECT measurements FROM body_progress WHERE id=$1',[id])).rows[0].measurements,{});
      assert.equal((await request('',a.token)).data.records.length,1);
      await purchase(a.id);
      const original=(await db.pool.query('SELECT create_request_id FROM body_progress WHERE id=$1',[id])).rows[0].create_request_id;
      assert.equal((await request('',a.token,'POST',{date,measurements:{weight:80.5,waist:88},requestId:original})).status,410);
    });
  } finally {
    if(users.length) await db.pool.query('DELETE FROM users WHERE id=ANY($1::uuid[])',[users]);
    await app.close(); for(const [key,value] of Object.entries(previous)) { if(value===undefined)delete process.env[key];else process.env[key]=value; }
  }
});
