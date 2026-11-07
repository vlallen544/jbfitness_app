import 'reflect-metadata';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {test} from 'node:test';
import type {AddressInfo} from 'node:net';
import {NestFactory} from '@nestjs/core';
import {AppModule} from '../src/app.module';
import {Database} from '../src/database';
import {MembershipService} from '../src/memberships';
import {todayInIndia,addDays} from '../src/workout-schema';
const profile={age:28,heightCm:170,weightKg:80,goal:'general_fitness',experience:'beginner',dietaryPreference:'vegetarian',equipment:[],workoutDays:[0,2,4],sessionMinutes:30,currentRoutine:'PRIVATE_ROUTINE_FIXTURE',limitations:'',foodNotes:'',healthDataConsent:true,shareWithTrainer:true,shareCoachingWithTrainer:false};
test('staff assignments, consent-controlled reviews and customer feedback',async t=>{
  const previous={NODE_ENV:process.env.NODE_ENV,ENABLE_DEV_MEMBERSHIPS:process.env.ENABLE_DEV_MEMBERSHIPS};Object.assign(process.env,{NODE_ENV:'test',ENABLE_DEV_MEMBERSHIPS:'true'});
  const app=await NestFactory.create(AppModule,{logger:false});app.setGlobalPrefix('api/v1');await app.listen(0,'127.0.0.1');const db=app.get(Database),users:string[]=[],exerciseId=`staff-fixture-${randomUUID()}`;
  const request=async(path:string,token?:string,method='GET',body?:unknown)=>{const r=await fetch(`http://127.0.0.1:${(app.getHttpServer().address() as AddressInfo).port}/api/v1${path}`,{method,headers:{'Content-Type':'application/json',...(token?{Authorization:`Bearer ${token}`}:{})},...(body===undefined?{}:{body:JSON.stringify(body)})});return{status:r.status,data:await r.json()};};
  const account=async(role='customer')=>{const r=await request('/auth/register',undefined,'POST',{email:`staff-${randomUUID()}@example.test`,password:'Staff-test-password-42!',displayName:`${role} fixture`});assert.equal(r.status,201);users.push(r.data.user.id);if(role!=='customer')await db.pool.query('UPDATE users SET role=$2 WHERE id=$1',[r.data.user.id,role]);return{id:r.data.user.id as string,token:r.data.token as string};};
  const grant=async(id:string)=>app.get(MembershipService).applyTestPurchase({customerId:id,planId:'normal',eventId:randomUUID(),paymentReference:randomUUID(),amountPaise:300000,currency:'INR'});
  const coachId=randomUUID(),planId=randomUUID();
  try{
    const owner=await account('admin'),trainer=await account('trainer'),other=await account('trainer'),a=await account(),b=await account();await request('/me/profile',a.token,'PUT',profile);await request('/me/profile',b.token,'PUT',{...profile,shareWithTrainer:false});await grant(a.id);
    const plan={title:'Trainer reviewed fixture',sessions:[{date:addDays(todayInIndia(),2),title:'Technical reviewed session',exercises:[{exerciseId,sets:3,repetitions:10,targetWeightKg:5,restSeconds:60}]}]};
    await db.pool.query("INSERT INTO exercises(id,name,muscle_group,equipment,instructions,review_status) VALUES($1,'Staff technical fixture','fixture','[]','[\"Technical only\"]','approved')",[exerciseId]);
    await db.pool.query("INSERT INTO ai_planning_runs(id,customer_id,request_id,status,stage,context,context_hash,message,draft) VALUES($1,$2,$3,'review_needed','review_needed',$4,'fixture','PRIVATE_PLANNING_REASON',$5)",[planId,a.id,randomUUID(),JSON.stringify({profile,dates:[addDays(todayInIndia(),-2)]}),JSON.stringify(plan)]);
    await db.pool.query("INSERT INTO coaching_turns(id,customer_id,request_id,kind,input,payload_hash,status,response) VALUES($1,$2,$3,'chat','PRIVATE_CUSTOMER_QUESTION','fixture','completed',$4)",[coachId,a.id,randomUUID(),JSON.stringify({reply:'PRIVATE_AI_REPLY',suggestions:[],needsTrainerReview:true,reviewReason:'PRIVATE_REVIEW_REASON'})]);
    await t.test('staff authentication and role separation precede registry and review access',async()=>{
      assert.equal((await request('/staff/overview')).status,401);assert.equal((await request('/staff/overview',a.token)).status,403);assert.equal((await request(`/staff/reviews/coaching/${coachId}`,a.token)).status,403);
      const list=(await request('/staff/overview',owner.token)).data;assert.ok(list.customers.some((c:any)=>c.id===a.id));assert.ok(list.reviews.some((r:any)=>r.id===coachId));assert.ok(!JSON.stringify(list).includes('PRIVATE_'));
      assert.equal((await request(`/staff/reviews/coaching/${coachId}`,owner.token)).status,403);assert.equal((await request(`/staff/customers/${a.id}`,owner.token)).status,403);
      assert.equal((await request('/staff/overview',trainer.token)).data.customers.length,0);
    });
    await t.test('only admins can assign valid trainers; duplicate assignments retain one audit event',async()=>{
      const path=`/staff/customers/${a.id}/assignment`,body={trainerId:trainer.id,assigned:true};assert.equal((await request(path,trainer.token,'PUT',body)).status,403);
      assert.equal((await request(path,owner.token,'PUT',{...body,trainerId:owner.id})).status,404);
      assert.equal((await request(path,owner.token,'PUT',body)).status,200);assert.equal((await request(path,owner.token,'PUT',body)).status,200);
      assert.equal((await db.pool.query("SELECT count(*)::int AS n FROM staff_audit WHERE customer_id=$1 AND action='trainer_assigned'",[a.id])).rows[0].n,1);
      assert.equal((await request('/staff/overview',trainer.token)).data.customers.length,1);
    });
    await t.test('legacy profile consent does not expose coaching; new consent is enforced on every read',async()=>{
      const customer=(await request(`/staff/customers/${a.id}`,trainer.token)).data;assert.equal(customer.profile.currentRoutine,profile.currentRoutine);assert.equal(customer.canReview,false);assert.equal(customer.facts,null);
      assert.equal((await request(`/staff/reviews/coaching/${coachId}`,trainer.token)).status,404);assert.equal((await request('/staff/overview',trainer.token)).data.reviews.length,0);
      await request('/me/profile',a.token,'PUT',{...profile,shareCoachingWithTrainer:true});
      assert.equal((await request(`/staff/reviews/coaching/${coachId}`,trainer.token)).data.question,'PRIVATE_CUSTOMER_QUESTION');assert.equal((await request(`/staff/reviews/coaching/${coachId}`,other.token)).status,404);
      assert.equal((await request('/staff/overview',trainer.token)).data.reviews.length,2);
    });
    let revision=0;
    await t.test('feedback is duplicate-safe, revisioned, visible only to its customer and separately marked trainer feedback',async()=>{
      const body={requestId:randomUUID(),revision:0,decision:'follow_up',feedback:'Please use a manageable session while we review your routine.'};
      const path=`/staff/reviews/coaching/${coachId}`;const[x,y]=await Promise.all([request(path,trainer.token,'POST',body),request(path,trainer.token,'POST',body)]);assert.equal(x.status,201);assert.deepEqual(x.data,y.data);revision=x.data.revision;assert.equal(revision,1);
      assert.equal((await request(path,trainer.token,'POST',{...body,feedback:'Changed text'})).status,409);assert.equal((await request(path,trainer.token,'POST',{...body,requestId:randomUUID()})).status,409);
      const feedback=(await request('/me/trainer-feedback',a.token)).data.feedback;assert.equal(feedback.length,1);assert.equal(feedback[0].feedback,body.feedback);assert.equal(feedback[0].decision,'follow_up');assert.equal((await request('/me/trainer-feedback',b.token)).data.feedback.length,0);assert.equal((await request('/me/trainer-feedback',trainer.token)).status,403);
      await request(`/staff/customers/${a.id}/assignment`,owner.token,'PUT',{trainerId:other.id,assigned:true});
      const changes=await Promise.all([request(path,trainer.token,'POST',{...body,requestId:randomUUID(),revision,decision:'resolved'}),request(path,other.token,'POST',{...body,requestId:randomUUID(),revision,decision:'resolved'})]);assert.deepEqual(changes.map(r=>r.status).sort(),[201,409]);revision=2;
    });
    await t.test('trainer publication validates dates/content/equipment and commits one plan with its resolution',async()=>{
      const path=`/staff/reviews/planning/${planId}`,body={requestId:randomUUID(),revision:0,decision:'publish_plan',feedback:'Your reviewed routine is ready.',plan,currentPlanId:null};
      assert.equal((await request(path,trainer.token,'POST',{...body,plan:{...plan,sessions:[{...plan.sessions[0],date:'2000-01-01'}]}})).status,400);
      assert.equal((await request(path,trainer.token,'POST',{...body,plan:{...plan,sessions:[{...plan.sessions[0],exercises:[{...plan.sessions[0].exercises[0],exerciseId:'not-approved'}]}]}})).status,400);
      assert.equal((await request(`/staff/reviews/coaching/${coachId}`,trainer.token,'POST',{...body,revision})).status,400);
      const[x,y]=await Promise.all([request(path,trainer.token,'POST',body),request(path,trainer.token,'POST',body)]);assert.equal(x.status,201);assert.equal(x.data.planId,y.data.planId);assert.equal(x.data.startDate,plan.sessions[0].date);
      const plans=(await db.pool.query('SELECT * FROM workout_plans WHERE customer_id=$1',[a.id])).rows;assert.equal(plans.length,1);assert.equal(plans[0].source,'trainer');
      const result=(await request(`/me/ai-planning/${planId}`,a.token)).data;assert.equal(result.stage,'trainer_published');assert.equal(result.startDate,plan.sessions[0].date);assert.equal(result.trainerReview.status,'resolved');
      assert.equal((await request(path,trainer.token,'POST',{...body,requestId:randomUUID(),revision:1})).status,409);
    });
    await t.test('consent withdrawal and assignment removal immediately prevent new review reads and writes',async()=>{
      await request('/me/profile',a.token,'PUT',{...profile,shareCoachingWithTrainer:false});assert.equal((await request(`/staff/reviews/coaching/${coachId}`,trainer.token)).status,404);
      assert.equal((await request(`/staff/reviews/coaching/${coachId}`,trainer.token,'POST',{requestId:randomUUID(),revision,decision:'resolved',feedback:'Must not be saved'})).status,404);
      assert.equal((await request('/staff/overview',trainer.token)).data.reviews.length,0);assert.ok((await request('/me/trainer-feedback',a.token)).data.feedback.length>0);
      await request('/me/profile',a.token,'PUT',{...profile,shareCoachingWithTrainer:true});await request(`/staff/customers/${a.id}/assignment`,owner.token,'PUT',{trainerId:trainer.id,assigned:false});assert.equal((await request(`/staff/customers/${a.id}`,trainer.token)).status,404);
    });
    await t.test('expired customers retain feedback; clearing coaching removes related feedback and review access',async()=>{
      await db.pool.query("UPDATE memberships SET ends_at=now()-interval '1 second',starts_at=now()-interval '2 days' WHERE customer_id=$1",[a.id]);assert.ok((await request('/me/trainer-feedback',a.token)).data.feedback.length>0);
      const currentPlanId=(await db.pool.query('SELECT id FROM workout_plans WHERE customer_id=$1 AND superseded_at IS NULL',[a.id])).rows[0].id;
      assert.equal((await request(`/staff/reviews/planning/${planId}`,other.token,'POST',{requestId:randomUUID(),revision:1,decision:'publish_plan',feedback:'Cannot publish after expiry',plan,currentPlanId})).status,403);
      assert.equal((await request('/me/coaching',a.token,'DELETE')).status,200);const feedback=(await request('/me/trainer-feedback',a.token)).data.feedback;assert.equal(feedback.length,1);assert.equal(feedback[0].kind,'planning');assert.equal((await request(`/staff/reviews/coaching/${coachId}`,other.token)).status,404);
      assert.equal((await db.pool.query("SELECT count(*)::int AS n FROM staff_review_events WHERE customer_id=$1 AND kind='coaching' AND feedback IS NOT NULL",[a.id])).rows[0].n,0);
    });
  }finally{if(users.length)await db.pool.query('DELETE FROM users WHERE id=ANY($1::uuid[])',[users]);await db.pool.query('DELETE FROM exercises WHERE id=$1',[exerciseId]);await app.close();for(const[k,v]of Object.entries(previous)){if(v===undefined)delete process.env[k];else process.env[k]=v;}}
});
