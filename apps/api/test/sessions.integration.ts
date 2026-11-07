import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {test} from 'node:test';
import {dashboardFixture} from './support/staff-dashboard';
import {MembershipService} from '../src/memberships';
import {SessionVideoProvider} from '../src/session-policy';
import {plans} from '../src/plans';

// Rules and video readiness below are technical fixtures in an isolated schema.
// No client policy is confirmed and no real video service is contacted.
test('session reservations, attendance and membership credits',async t=>{
  const f=await dashboardFixture({startDashboard:false});
  const provider=f.app.get(SessionVideoProvider),members:MembershipService=f.app.get(MembershipService);
  const policy={durationMinutes:30,bookingLeadHours:0,horizonDays:60,freeCancellationHours:12,chargeLateCancellation:true,chargeNoShow:true};
  const request=async(path:string,actor:any,body?:unknown,method=body===undefined?'GET':'POST')=>{
    const r=await fetch(f.apiBase+path,{method,headers:{'Content-Type':'application/json',...(actor?{Authorization:`Bearer ${actor.token}`}:{})},...(body===undefined?{}:{body:JSON.stringify(body)})});return{status:r.status,data:await r.json()};
  };
  const assign=async(customer:any,trainer=f.trainer,assigned=true)=>{const r=await request(`/staff/customers/${customer.id}/assignment`,f.admin,{trainerId:trainer.id,assigned},'PUT');assert.equal(r.status,200,JSON.stringify(r.data));};
  const account=async(plan:'premium'|'premium-plus'|null='premium',role='customer')=>{
    const data=await f.auth.register({email:`calendar-${randomUUID()}@example.test`,password:'Calendar-fixture-password-42!',displayName:'Calendar QA'});
    const a={id:data.user.id,token:data.token};if(role!=='customer')await f.db.pool.query('UPDATE users SET role=$2 WHERE id=$1',[a.id,role]);
    if(plan)await members.applyTestPurchase({customerId:a.id,planId:plan,eventId:randomUUID(),paymentReference:randomUUID(),amountPaise:plans.find(p=>p.id===plan)!.priceInPaise,currency:'INR'});
    if(role==='customer')await assign(a);return a;
  };
  let revision=0,cursor=Math.ceil((Date.now()+86400000)/300000)*300000;
  const configure=async(p=policy)=>{const r=await request('/staff/sessions/policy',f.admin,{policy:p,revision,confirmed:true,requestId:randomUUID()});assert.equal(r.status,201,JSON.stringify(r.data));revision=r.data.revision;};
  const slot=async(trainer=f.trainer,at?:number)=>{const r=await request('/staff/sessions/slots',trainer,{startsAt:new Date(at??cursor).toISOString(),policyRevision:revision,requestId:randomUUID()});if(at===undefined)cursor+=3600000;assert.equal(r.status,201,JSON.stringify(r.data));return r.data;};
  const reserve=async(a:any,s:any,requestId=randomUUID())=>request('/me/sessions',a,{slotId:s.id,slotRevision:s.revision,policyRevision:revision,requestId});
  const balance=async(a:any)=>(await request('/me/sessions',a)).data.membership;
  const finishTime=async(b:any)=>{await f.db.pool.query("UPDATE memberships SET starts_at=now()-interval '2 days' WHERE id=(SELECT membership_id FROM coaching_bookings WHERE id=$1)",[b.id]);await f.db.pool.query("UPDATE coaching_bookings SET starts_at=now()-interval '60 minutes',ends_at=now()-interval '30 minutes' WHERE id=$1",[b.id]);};
  try{
    const premium=await account();await assign(f.customer);
    await t.test('authentication, roles and unconfirmed rules prevent admission',async()=>{
      assert.equal((await request('/me/sessions',null)).status,401);
      assert.equal((await request('/staff/sessions',premium)).status,403);
      assert.equal((await request('/me/sessions',f.trainer)).status,403);
      const initial=(await request('/me/sessions',premium)).data;assert.equal(initial.confirmed,false);assert.equal(initial.bookingEnabled,false);assert.equal(initial.policy,null);
      assert.equal((await request('/staff/sessions/slots',f.trainer,{startsAt:new Date(cursor).toISOString(),policyRevision:1,requestId:randomUUID()})).status,503);
      assert.equal((await request('/staff/sessions/policy',f.trainer,{policy,revision:0,confirmed:true,requestId:randomUUID()})).status,403);
      assert.equal((await request('/staff/sessions/policy',f.admin,{policy,revision:0,confirmed:false,requestId:randomUUID()})).status,400);
    });
    await t.test('owner confirmation is revisioned, retry-safe and validates terms',async()=>{
      const body={policy,revision:0,confirmed:true,requestId:randomUUID()};
      const results=await Promise.all([request('/staff/sessions/policy',f.admin,body),request('/staff/sessions/policy',f.admin,body)]);assert.deepEqual(results.map(r=>r.status),[201,201]);assert.deepEqual(results[0].data,results[1].data);revision=1;
      assert.equal((await request('/staff/sessions/policy',f.admin,{...body,policy:{...policy,durationMinutes:35}})).status,409);
      assert.equal((await request('/staff/sessions/policy',f.admin,{...body,requestId:randomUUID()})).status,409);
      assert.equal((await request('/staff/sessions/policy',f.admin,{...body,revision,policy:{...policy,durationMinutes:31},requestId:randomUUID()})).status,400);
    });
    await t.test('availability rejects overlaps and permits adjacent slots; concurrent retries create one',async()=>{
      const body={startsAt:new Date(cursor).toISOString(),policyRevision:revision,requestId:randomUUID()};cursor+=3600000;
      const r=await Promise.all([request('/staff/sessions/slots',f.trainer,body),request('/staff/sessions/slots',f.trainer,body)]);assert.deepEqual(r.map(v=>v.status),[201,201]);assert.equal(r[0].data.id,r[1].data.id);
      assert.equal((await request('/staff/sessions/slots',f.trainer,{...body,requestId:randomUUID()})).status,409);
      await slot(f.trainer,new Date(body.startsAt).getTime()+30*60000);
      assert.equal((await request('/staff/sessions/slots',f.trainer,{...body,startsAt:new Date(Date.now()-60000).toISOString(),requestId:randomUUID()})).status,400);
      assert.equal((await request('/staff/sessions/slots',f.admin,body)).status,403);
    });
    await t.test('both a configured video adapter and activation flag are required',async()=>{
      const s=await slot();process.env.ENABLE_SESSION_BOOKING='true';assert.equal((await reserve(premium,s)).status,503);
      Object.defineProperty(provider,'configured',{configurable:true,get:()=>true});process.env.ENABLE_SESSION_BOOKING='false';assert.equal((await reserve(premium,s)).status,503);
      process.env.ENABLE_SESSION_BOOKING='true';assert.equal((await request('/me/sessions',premium)).data.bookingEnabled,true);
    });
    await t.test('normal, inactive, unassigned and out-of-period memberships cannot book',async()=>{
      const s=await slot();assert.equal((await reserve(f.customer,s)).status,403);assert.equal((await request('/me/sessions',f.customer)).data.slots.length,0);
      const empty=await account(null);assert.equal((await reserve(empty,s)).status,403);
      await assign(premium,f.trainer,false);assert.equal((await reserve(premium,s)).status,404);await assign(premium);
      const beyond=await slot(f.trainer,Math.ceil((Date.now()+40*86400000)/300000)*300000);assert.equal((await reserve(premium,beyond)).status,403);
      assert.ok(!(await request('/me/sessions',premium)).data.slots.some((v:any)=>v.id===beyond.id));
    });
    await t.test('concurrent customer competition reserves a slot once and hides it from availability',async()=>{
      const s=await slot(),other=await account();const r=await Promise.all([reserve(premium,s),reserve(other,s)]);assert.deepEqual(r.map(v=>v.status).sort(),[201,409]);
      const owner=r[0].status===201?premium:other,b=r.find(v=>v.status===201)!.data;
      assert.equal((await balance(owner)).videoSessionsReserved,1);assert.equal((await balance(owner)).videoSessionsRemaining,9);
      assert.ok(!(await request('/me/sessions',owner)).data.slots.some((v:any)=>v.id===s.id));
      assert.equal((await request(`/me/sessions/${b.id}/cancel`,owner===premium?other:premium,{revision:1,requestId:randomUUID()})).status,404);
      const body={revision:1,requestId:randomUUID()};const cancel=await Promise.all([request(`/me/sessions/${b.id}/cancel`,owner,body),request(`/me/sessions/${b.id}/cancel`,owner,body)]);assert.deepEqual(cancel.map(v=>v.status),[201,201]);assert.equal(cancel[0].data.consumed,false);assert.equal((await balance(owner)).videoSessionsReserved,0);
    });
    await t.test('reservation retries and changed payload references cannot duplicate holds',async()=>{
      const s=await slot(),id=randomUUID(),r=await Promise.all([reserve(premium,s,id),reserve(premium,s,id)]);assert.deepEqual(r.map(v=>v.status),[201,201]);assert.equal(r[0].data.id,r[1].data.id);
      assert.equal((await reserve(premium,{...s,revision:99},id)).status,409);
      await request(`/me/sessions/${r[0].data.id}/cancel`,premium,{revision:1,requestId:randomUUID()});
    });
    await t.test('customers cannot hold overlapping appointments with different trainers',async()=>{
      const second=await account(null,'trainer');await assign(premium,second);const start=cursor;const a=await slot(),b=await slot(second,start);const held=await reserve(premium,a);assert.equal(held.status,201);assert.equal((await reserve(premium,b)).status,409);
      assert.equal((await request(`/staff/sessions/slots/${a.id}/withdraw`,second,{revision:2,requestId:randomUUID(),cancelExistingBooking:true,reason:'trainer_unavailable'})).status,404);
      assert.ok(!(await request('/staff/sessions',second)).data.slots.some((v:any)=>v.id===a.id));
      await request(`/me/sessions/${held.data.id}/cancel`,premium,{revision:1,requestId:randomUUID()});
    });
    await t.test('staff withdrawal needs explicit confirmation and releases a hold without penalty',async()=>{
      const s=await slot(),b=await reserve(premium,s);const body={revision:2,requestId:randomUUID(),cancelExistingBooking:false,reason:'trainer_unavailable'};
      assert.equal((await request(`/staff/sessions/slots/${s.id}/withdraw`,f.trainer,body)).status,409);
      body.cancelExistingBooking=true;assert.equal((await request(`/staff/sessions/slots/${s.id}/withdraw`,f.trainer,body)).status,201);assert.equal((await request(`/staff/sessions/slots/${s.id}/withdraw`,f.trainer,body)).status,201);
      const saved=(await request('/me/sessions',premium)).data.bookings.find((v:any)=>v.id===b.data.id);assert.equal(saved.status,'cancelled');assert.equal(saved.consumed,false);assert.equal(saved.cancellationReason,'trainer_unavailable');
    });
    await t.test('late cancellation follows the saved terms after the owner changes policy',async()=>{
      const s=await slot(f.trainer,Math.ceil((Date.now()+3*3600000)/300000)*300000),b=await reserve(premium,s);assert.equal(b.status,201);
      await configure({...policy,chargeLateCancellation:false,chargeNoShow:false});
      const r=await request(`/me/sessions/${b.data.id}/cancel`,premium,{revision:1,requestId:randomUUID()});assert.equal(r.status,201);assert.equal(r.data.consumed,true);
      assert.equal((await f.db.pool.query('SELECT reason FROM membership_session_ledger WHERE booking_id=$1',[b.data.id])).rows[0].reason,'late_cancellation');
    });
    await t.test('attendance requires staff and elapsed time; completion consumes one hold exactly once',async()=>{
      const s=await slot(),b=(await reserve(premium,s)).data,body={revision:1,requestId:randomUUID(),outcome:'completed',attendanceNote:'Technical fixture: attended the scheduled session.'};
      assert.equal((await request(`/staff/sessions/bookings/${b.id}/outcome`,premium,body)).status,403);
      assert.equal((await request(`/staff/sessions/bookings/${b.id}/outcome`,f.trainer,body)).status,400);
      await finishTime(b);const r=await Promise.all([request(`/staff/sessions/bookings/${b.id}/outcome`,f.trainer,body),request(`/staff/sessions/bookings/${b.id}/outcome`,f.trainer,body)]);assert.deepEqual(r.map(v=>v.status),[201,201]);assert.equal(r[0].data.consumed,true);
      assert.equal((await f.db.pool.query('SELECT count(*)::int n FROM membership_session_ledger WHERE booking_id=$1',[b.id])).rows[0].n,1);
      const saved=(await request('/me/sessions',premium)).data.bookings.find((v:any)=>v.id===b.id);assert.equal(saved.attendanceNote,body.attendanceNote);
    });
    await t.test('saved no-show policy determines whether attendance consumes a credit',async()=>{
      for(const chargeNoShow of [false,true]){
        await configure({...policy,chargeNoShow});const s=await slot(),b=(await reserve(premium,s)).data;await finishTime(b);
        const r=await request(`/staff/sessions/bookings/${b.id}/outcome`,f.trainer,{revision:1,requestId:randomUUID(),outcome:'no_show',attendanceNote:'Technical fixture: no attendance observed.'});assert.equal(r.status,201);assert.equal(r.data.consumed,chargeNoShow);
        const count=(await f.db.pool.query('SELECT count(*)::int n FROM membership_session_ledger WHERE booking_id=$1',[b.id])).rows[0].n;assert.equal(count,chargeNoShow?1:0);
      }
    });
    await t.test('removed assignments prevent joining and permit free cancellation',async()=>{
      const s=await slot(),b=(await reserve(premium,s)).data;await assign(premium,f.trainer,false);
      assert.equal((await request(`/me/sessions/${b.id}/join`,premium,{})).status,403);
      assert.equal((await request(`/me/sessions/${b.id}/cancel`,premium,{revision:1,requestId:randomUUID()})).data.consumed,false);await assign(premium);
    });
    await t.test('join is participant-only, time-bounded and never fabricates a video URL',async()=>{
      const s=await slot(),b=(await reserve(premium,s)).data;
      assert.equal((await request(`/staff/sessions/bookings/${b.id}/join`,premium,{})).status,403);
      assert.equal((await request(`/staff/sessions/bookings/${b.id}/join`,f.admin,{})).status,404);
      assert.equal((await request(`/me/sessions/${b.id}/join`,premium,{})).status,403);
      await f.db.pool.query("UPDATE coaching_bookings SET starts_at=now()+interval '5 minutes',ends_at=now()+interval '35 minutes' WHERE id=$1",[b.id]);
      assert.equal((await request(`/me/sessions/${b.id}/join`,premium,{})).status,503);
      assert.equal((await request(`/staff/sessions/bookings/${b.id}/join`,f.trainer,{})).status,503);
      await request(`/me/sessions/${b.id}/cancel`,premium,{revision:1,requestId:randomUUID()});
    });
    await t.test('all 10 or 25 credits can be held, and legacy completion cannot spend held credits',async()=>{
      for(const [plan,total]of [['premium',10],['premium-plus',25]] as const){
        const a=await account(plan);for(let i=0;i<total;i++){const s=await slot();assert.equal((await reserve(a,s)).status,201);}
        const summary=await balance(a);assert.equal(summary.videoSessionsReserved,total);assert.equal(summary.videoSessionsRemaining,0);assert.equal(summary.videoSessionsUsed,0);
        assert.equal((await reserve(a,await slot())).status,403);
        await assert.rejects(()=>members.recordCompletedVideoSession(a.id,summary.id,randomUUID()));
      }
    });
    await t.test('production excludes development slots, bookings and replayed reservations',async()=>{
      const s=await slot(),ref=randomUUID(),b=await reserve(premium,s,ref);assert.equal(b.status,201);process.env.NODE_ENV='production';
      try{const customer=(await request('/me/sessions',premium)).data;assert.equal(customer.membership,null);assert.equal(customer.slots.length,0);assert.equal(customer.bookings.length,0);assert.equal((await request('/staff/sessions',f.admin)).data.slots.length,0);assert.equal((await reserve(premium,s,ref)).status,404);
        const devSlot=(await f.db.pool.query('SELECT starts_at FROM coaching_slots WHERE id=$1',[s.id])).rows[0];
        await slot(f.trainer,devSlot.starts_at.getTime());assert.equal((await request('/staff/sessions',f.admin)).data.slots.length,1);
      }finally{process.env.NODE_ENV='test';}
    });
  }finally{await f.cleanup();}
});
