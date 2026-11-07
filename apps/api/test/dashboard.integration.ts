import assert from 'node:assert/strict';
import {test} from 'node:test';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {randomUUID} from 'node:crypto';
import {dashboardFixture} from './support/staff-dashboard';
test('dashboard server boundary and cookie sessions',async t=>{
  const f=await dashboardFixture();let adminCookie='',trainerCookie='';
  const request=async(query='',body?:unknown,cookie='',origin:string|null=f.origin)=>{const r=await fetch(`${f.origin}/api/operations${query}`,{method:body===undefined?'GET':'POST',headers:{'Content-Type':'application/json',...(cookie?{Cookie:cookie}:{}),...(origin?{Origin:origin}:{})},...(body===undefined?{}:{body:JSON.stringify(body)})});return{status:r.status,data:await r.json(),headers:r.headers};};
  try{
    await t.test('trusted provisioning revokes sessions and rejects customer membership accounts',async()=>{
      const email=`provision-${randomUUID()}@example.test`,created=await f.auth.register({email,password:'Provisioning-QA-password-42!',displayName:'Dedicated role fixture'});
      await promisify(execFile)(process.execPath,['--import','tsx','scripts/staff-role.ts','--email',email,'--role','trainer'],{cwd:process.cwd(),env:process.env});
      assert.equal((await f.db.pool.query('SELECT role FROM users WHERE id=$1',[created.user.id])).rows[0].role,'trainer');await assert.rejects(()=>f.auth.authenticate(created.token));
      await assert.rejects(()=>promisify(execFile)(process.execPath,['--import','tsx','scripts/staff-role.ts','--email',f.customer.email,'--role','trainer'],{cwd:process.cwd(),env:process.env}));
      assert.equal((await f.db.pool.query('SELECT role FROM users WHERE id=$1',[f.customer.id])).rows[0].role,'customer');
    });
    await t.test('unauthenticated reads and cross-origin mutations are rejected',async()=>{assert.equal((await request()).status,401);const body={action:'login',email:f.admin.email,password:f.admin.password};assert.equal((await request('',body,'',null)).status,403);assert.equal((await request('',body,'','https://foreign.example')).status,403);assert.equal((await request('',{...body,password:'x'.repeat(20000)})).status,413);});
    await t.test('customer login cannot create a dashboard session',async()=>{const r=await request('',{action:'login',email:f.customer.email,password:f.customer.password});assert.equal(r.status,403);assert.equal(r.headers.get('set-cookie'),null);});
    await t.test('staff login uses a private secure HttpOnly cookie without returning its token',async()=>{const r=await request('',{action:'login',email:f.admin.email,password:f.admin.password});assert.equal(r.status,200);assert.equal(r.data.user.role,'admin');assert.equal(r.data.token,undefined);const header=r.headers.get('set-cookie')!;assert.match(header,/HttpOnly/i);assert.match(header,/Secure/i);assert.match(header,/SameSite=strict/i);adminCookie=header.split(';')[0];assert.match(r.headers.get('cache-control')! ,/no-store/);});
    await t.test('admin assignment works while coaching content remains trainer-only',async()=>{const overview=await request('',undefined,adminCookie);assert.equal(overview.data.customers.length,1);assert.equal(overview.data.profile,undefined);assert.equal((await request(`?resource=review&kind=coaching&id=${f.coachingId}`,undefined,adminCookie)).status,403);assert.equal((await request('',{action:'assignment',customerId:f.customer.id,trainerId:f.trainer.id,assigned:true},adminCookie)).status,200);assert.equal((await request('?resource=https://foreign.example',undefined,adminCookie)).status,400);});
    await t.test('trainer resolves a shared review and the customer receives the saved feedback',async()=>{const login=await request('',{action:'login',email:f.trainer.email,password:f.trainer.password});trainerCookie=login.headers.get('set-cookie')!.split(';')[0];const detail=await request(`?resource=review&kind=coaching&id=${f.coachingId}`,undefined,trainerCookie);assert.equal(detail.status,200);const body={action:'review',kind:'coaching',id:f.coachingId,revision:0,requestId:crypto.randomUUID(),decision:'resolved',feedback:'Use a manageable session and keep your saved training days.'};assert.equal((await request('',body,trainerCookie,'https://foreign.example')).status,403);assert.equal((await request('',body,trainerCookie)).status,200);const feedback=await fetch(`${f.apiBase}/me/trainer-feedback`,{headers:{Authorization:`Bearer ${f.customer.token}`}});assert.equal((await feedback.json()).feedback[0].feedback,body.feedback);});
    await t.test('calendar actions retain cookie, role and origin boundaries',async()=>{
      assert.equal((await request('?resource=session-calendar')).status,401);
      const calendar=await request('?resource=session-calendar',undefined,adminCookie);assert.equal(calendar.status,200);assert.equal(calendar.data.confirmed,false);assert.equal(calendar.data.bookingEnabled,false);
      const body={action:'session-policy',policy:{durationMinutes:30,bookingLeadHours:0,horizonDays:14,freeCancellationHours:12,chargeLateCancellation:true,chargeNoShow:true},revision:0,confirmed:true,requestId:randomUUID()};
      assert.equal((await request('',body,trainerCookie)).status,403);assert.equal((await request('',body,adminCookie,'https://foreign.example')).status,403);assert.equal((await request('',body,adminCookie)).status,200);
      const startsAt=new Date(Math.ceil((Date.now()+86400000)/300000)*300000).toISOString();
      const created=await request('',{action:'create-slot',startsAt,policyRevision:1,requestId:randomUUID()},trainerCookie);assert.equal(created.status,200);
      assert.equal((await request('?resource=session-calendar',undefined,trainerCookie)).data.slots[0].id,created.data.id);
      assert.equal((await request('',{action:'withdraw-slot',id:created.data.id,revision:1,requestId:randomUUID(),cancelExistingBooking:false,reason:'schedule_change'},trainerCookie)).status,200);
    });
    await t.test('logout revokes the backend token and invalid sessions clear the cookie',async()=>{const token=adminCookie.slice(adminCookie.indexOf('=')+1);await f.auth.authenticate(token);assert.equal((await request('',{action:'logout'},adminCookie)).status,200);await assert.rejects(()=>f.auth.authenticate(token));const expired=await request('',undefined,adminCookie);assert.equal(expired.status,401);assert.match(expired.headers.get('set-cookie')!,/Max-Age=0/);await f.db.pool.query("UPDATE users SET role='customer' WHERE id=$1",[f.trainer.id]);const removed=await request('',undefined,trainerCookie);assert.equal(removed.status,401);assert.match(removed.headers.get('set-cookie')!,/Max-Age=0/);});
  }finally{await f.cleanup();}
});
