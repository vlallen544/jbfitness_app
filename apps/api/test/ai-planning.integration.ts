import 'reflect-metadata';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {test} from 'node:test';
import type {AddressInfo} from 'node:net';
import {NestFactory} from '@nestjs/core';
import {AppModule} from '../src/app.module';
import {Database} from '../src/database';
import {MembershipService} from '../src/memberships';
import {AiPlanningProvider} from '../src/ai-planning-provider';
import {AiPlanningService} from '../src/ai-planning';
import {checkAiPlan,PlanningContext,requestedDates} from '../src/ai-planning-schema';
import {todayInIndia} from '../src/workout-schema';

const profile={age:25,heightCm:170,weightKg:80,goal:'general_fitness',experience:'beginner',dietaryPreference:'vegetarian',equipment:[],workoutDays:[0,2,4],sessionMinutes:30,currentRoutine:'Walks most days',limitations:'',foodNotes:'',healthDataConsent:true,shareWithTrainer:false};
test('bounded AI routine review, planning, validation and atomic publication',async t=>{
  const keys=['NODE_ENV','ENABLE_DEV_MEMBERSHIPS','ENABLE_WORKOUT_AI','WORKOUT_AI_PLANNER_MODEL','WORKOUT_AI_REVIEW_MODEL','WORKOUT_AI_WORKER_ENABLED','OPENAI_API_KEY'];
  const previous=Object.fromEntries(keys.map(k=>[k,process.env[k]]));
  Object.assign(process.env,{NODE_ENV:'test',ENABLE_DEV_MEMBERSHIPS:'true',ENABLE_WORKOUT_AI:'false',WORKOUT_AI_PLANNER_MODEL:'test-planner',WORKOUT_AI_REVIEW_MODEL:'test-reviewer',WORKOUT_AI_WORKER_ENABLED:'false',OPENAI_API_KEY:'test-key-never-sent'});
  const start=async()=>{const a=await NestFactory.create(AppModule,{logger:false});a.setGlobalPrefix('api/v1');await a.listen(0,'127.0.0.1');return a;};
  let app=await start(),db=app.get(Database),service=app.get(AiPlanningService),provider=app.get(AiPlanningProvider);
  const users:string[]=[],exerciseId=`ai-fixture-${randomUUID()}`,unapprovedId=`ai-draft-${randomUUID()}`;
  const request=async(path:string,token?:string,method='GET',body?:unknown)=>{const r=await fetch(`http://127.0.0.1:${(app.getHttpServer().address() as AddressInfo).port}/api/v1${path}`,{method,headers:{'Content-Type':'application/json',...(token?{Authorization:`Bearer ${token}`}:{})},...(body===undefined?{}:{body:JSON.stringify(body)})});return{status:r.status,data:await r.json()};};
  const customer=async(overrides:Record<string,unknown>={},save=true)=>{
    const r=await request('/auth/register',undefined,'POST',{email:`plan-${randomUUID()}@example.test`,password:'Planning-test-password-42!',displayName:'Planner fixture'});assert.equal(r.status,201);users.push(r.data.user.id);
    await app.get(MembershipService).applyTestPurchase({customerId:r.data.user.id,planId:'normal',eventId:randomUUID(),paymentReference:randomUUID(),amountPaise:300000,currency:'INR'});
    if(save)assert.equal((await request('/me/profile',r.data.token,'PUT',{...profile,...overrides})).status,200);
    return {id:r.data.user.id as string,token:r.data.token as string};
  };
  let calls:string[]=[];
  const output=<T>(value:T,model='test-reviewer')=>({value,model,usage:{inputTokens:10,outputTokens:10}});
  const draft=(c:PlanningContext)=>({title:'Fixture AI schedule',sessions:c.dates.map(date=>({date,title:'Fixture full-body session',exercises:[{exerciseId,sets:2,repetitions:10,targetWeightKg:null,restSeconds:60}]}))});
  const defaults=()=>{
    calls=[];
    provider.reviewRoutine=async()=>{calls.push('routine');return output({decision:'proceed' as const,summary:'Use a consistent short routine.',notes:['Keep recovery days between sessions.']});};
    provider.draft=async c=>{calls.push('draft');return output(draft(c),'test-planner');};
    provider.judge=async()=>{calls.push('judge');return output({decision:'approved' as const,summary:'Draft matches the supplied profile.',issues:[]});};
  };
  const enqueue=async(token:string,ref=randomUUID())=>request('/me/ai-planning',token,'POST',{requestId:ref});
  const run=async(id:string)=>(await db.pool.query('SELECT * FROM ai_planning_runs WHERE id=$1',[id])).rows[0];
  try{
    const a=await customer(),b=await customer();defaults();
    await db.pool.query(`INSERT INTO exercises(id,name,muscle_group,equipment,instructions,review_status) VALUES($1,'Planning technical fixture','fixture','[]','["Technical test only"]','approved'),($2,'Unapproved fixture','fixture','[]','["Not for publication"]','draft')`,[exerciseId,unapprovedId]);
    await t.test('authentication, role, configuration, profile and strict input gates precede paid work',async()=>{
      assert.equal((await request('/me/ai-planning/status')).status,401);
      await db.pool.query("UPDATE users SET role='trainer' WHERE id=$1",[b.id]);assert.equal((await request('/me/ai-planning/status',b.token)).status,403);await db.pool.query("UPDATE users SET role='customer' WHERE id=$1",[b.id]);
      assert.equal((await enqueue(a.token)).status,503);assert.equal(calls.length,0);
      process.env.ENABLE_WORKOUT_AI='true';
      assert.equal((await request('/me/ai-planning',a.token,'POST',{requestId:randomUUID(),model:'client-override'})).status,400);
      const missing=await customer({},false);assert.equal((await enqueue(missing.token)).status,400);
      const status=(await request('/me/ai-planning/status',a.token)).data;assert.equal(status.configured,true);assert.equal(status.profileReady,true);assert.ok(status.eligibleExerciseCount>0);
    });
    let firstId='';
    await t.test('durable queued requests deduplicate; only the owner can read them; publication is versioned',async()=>{
      const ref=randomUUID();const [x,y]=await Promise.all([enqueue(a.token,ref),enqueue(a.token,ref)]);assert.equal(x.status,201);assert.equal(y.data.id,x.data.id);firstId=x.data.id;assert.equal(x.data.status,'queued');assert.equal(calls.length,0);
      assert.equal((await enqueue(a.token)).status,409);assert.equal((await request(`/me/ai-planning/${firstId}`,b.token)).status,404);
      assert.deepEqual((await Promise.all([service.processOne(),service.processOne()])).sort(),[false,true]);const result=await run(firstId);assert.equal(result.status,'published');assert.deepEqual(calls,['routine','draft','judge']);assert.equal(result.trace.length,3);assert.equal(result.trace[2].assessment.decision,'approved');
      assert.equal((await enqueue(a.token,ref)).data.planId,result.plan_id);assert.equal(calls.length,3);
      const plan=(await db.pool.query('SELECT * FROM workout_plans WHERE id=$1',[result.plan_id])).rows[0];assert.equal(plan.source,'ai');assert.equal(plan.version,1);
      assert.equal((await db.pool.query('SELECT count(*)::int AS n FROM workout_sessions WHERE plan_id=$1',[plan.id])).rows[0].n,3);
      const view=(await request(`/me/ai-planning/${firstId}`,a.token)).data;assert.equal(view.callCount,3);assert.equal(view.context,undefined);assert.equal(view.draft,undefined);assert.ok(!JSON.stringify(view).includes('test-key-never-sent'));
    });
    await t.test('a rejected first draft is revised once; repeated invalid drafts never replace the old plan',async()=>{
      defaults();let number=0;provider.draft=async c=>{calls.push('draft');number++;return output({...draft(c),sessions:draft(c).sessions.map(s=>({...s,exercises:[{...s.exercises[0],exerciseId:unapprovedId,targetWeightKg:100}]}))},'test-planner');};
      const old=(await run(firstId)).plan_id;const queued=await enqueue(a.token);await service.processOne();const result=await run(queued.data.id);assert.equal(result.status,'review_needed');assert.equal(number,2);assert.deepEqual(calls,['routine','draft','draft']);
      assert.equal((await db.pool.query('SELECT id FROM workout_plans WHERE customer_id=$1 AND superseded_at IS NULL',[a.id])).rows[0].id,old);
      assert.equal((await enqueue(a.token)).status,429);assert.equal((await request('/me/ai-planning/status',a.token)).data.remainingToday,0);
    });
    await t.test('an independent judge revision consumes at most five calls and can publish the corrected plan',async()=>{
      defaults();let judges=0;provider.judge=async()=>{calls.push('judge');judges++;return output(judges===1?{decision:'revise' as const,summary:'Adjust the exercise balance.',issues:['Use a simpler session.']}:{decision:'approved' as const,summary:'Revision accepted.',issues:[]});};
      const user=await customer();const queued=await enqueue(user.token);await service.processOne();const result=await run(queued.data.id);assert.equal(result.status,'published');assert.deepEqual(calls,['routine','draft','judge','draft','judge']);assert.equal(result.trace.length,5);
    });
    await t.test('code checks enforce exact dates, equipment, duration, dosage and unverified loads',async()=>{
      const context=(await run(firstId)).context as PlanningContext;
      assert.deepEqual(checkAiPlan(draft(context),context),[]);
      const bad=draft(context);bad.sessions[0].date='2000-01-01';bad.sessions[0].exercises[0].sets=12;bad.sessions[0].exercises[0].repetitions=100;bad.sessions[0].exercises[0].restSeconds=0;bad.sessions[0].exercises[0].targetWeightKg=20 as any;
      const errors=checkAiPlan(bad,context);assert.ok(errors.some(e=>e.includes('requested date')));assert.ok(errors.some(e=>e.includes('1–5')));assert.ok(errors.some(e=>e.includes('load')));assert.ok(errors.some(e=>e.includes('time')));
      const equipmentContext={...context,catalogue:context.catalogue.map(e=>e.id===exerciseId?{...e,equipment:['not-owned-machine']}:e)};assert.ok(checkAiPlan(draft(context),equipmentContext).some(e=>e.includes('equipment')));
      assert.deepEqual(requestedDates(todayInIndia(),[0,2,4]),context.dates);
    });
    await t.test('age, limitations and short-session boundaries request human review without model calls',async()=>{
      for(const override of [{age:17},{limitations:'Persistent knee discomfort'},{sessionMinutes:10}]){
        defaults();const user=await customer(override);const queued=await enqueue(user.token);await service.processOne();assert.equal((await run(queued.data.id)).status,'review_needed');assert.equal(calls.length,0);
      }
    });
    await t.test('model review can stop the workflow; approval with unresolved issues cannot publish',async()=>{
      defaults();provider.reviewRoutine=async()=>{calls.push('routine');return output({decision:'needs_review' as const,summary:'A trainer should clarify the routine.',notes:[]});};
      const user=await customer();const queued=await enqueue(user.token);await service.processOne();assert.equal((await run(queued.data.id)).status,'review_needed');assert.equal(calls.length,1);
      defaults();provider.judge=async()=>{calls.push('judge');return output({decision:'approved' as const,summary:'Contradictory reviewer fixture',issues:['Unresolved issue']});};
      const other=await customer();const second=await enqueue(other.token);await service.processOne();assert.equal((await run(second.data.id)).status,'review_needed');assert.equal(calls.length,5);
    });
    await t.test('changed profile or revoked content prevents publication after a passing AI review',async()=>{
      for(const mode of ['profile','catalogue']){
        defaults();const user=await customer();const queued=await enqueue(user.token);
        provider.judge=async()=>{calls.push('judge');if(mode==='profile')await db.pool.query("UPDATE fitness_profiles SET data=jsonb_set(data,'{currentRoutine}','\"Changed during planning\"') WHERE user_id=$1",[user.id]);else await db.pool.query("UPDATE exercises SET review_status='draft' WHERE id=$1",[exerciseId]);return output({decision:'approved' as const,summary:'Passing fixture',issues:[]});};
        await service.processOne();const result=await run(queued.data.id);assert.equal(result.status,'review_needed');assert.equal(result.stage,'stale');assert.equal(result.plan_id,null);
        await db.pool.query("UPDATE exercises SET review_status='approved' WHERE id=$1",[exerciseId]);
      }
    });
    await t.test('queued work survives restart; interrupted paid stages are not replayed',async()=>{
      defaults();const user=await customer();const queued=await enqueue(user.token);await app.close();app=await start();db=app.get(Database);service=app.get(AiPlanningService);provider=app.get(AiPlanningProvider);defaults();
      await service.processOne();assert.equal((await run(queued.data.id)).status,'published');assert.equal(calls.length,3);
      const other=await customer();const interrupted=await enqueue(other.token);await db.pool.query("UPDATE ai_planning_runs SET status='running',lease_until=now()-interval '1 second',claim_token=$2,trace='[{\"stage\":\"drafting\",\"status\":\"started\"}]' WHERE id=$1",[interrupted.data.id,randomUUID()]);
      const before=calls.length;assert.equal(await service.processOne(),false);assert.equal((await run(interrupted.data.id)).status,'review_needed');assert.equal(calls.length,before);
    });
    await t.test('provider failures and membership expiry cannot publish or trigger automatic retries',async()=>{
      defaults();provider.reviewRoutine=async()=>{calls.push('routine');throw new Error('Technical timeout fixture');};const user=await customer();const queued=await enqueue(user.token);await service.processOne();assert.equal((await run(queued.data.id)).status,'failed');assert.equal(calls.length,1);assert.equal(await service.processOne(),false);assert.equal(calls.length,1);
      defaults();const expired=await customer();const second=await enqueue(expired.token);await db.pool.query("UPDATE memberships SET ends_at=now()-interval '1 second',starts_at=now()-interval '2 days' WHERE customer_id=$1",[expired.id]);await service.processOne();assert.equal((await run(second.data.id)).status,'failed');assert.equal(calls.length,0);assert.equal((await enqueue(expired.token)).status,403);assert.equal((await request(`/me/ai-planning/${second.data.id}`,expired.token)).status,200);
    });
    await t.test('provider transport uses the configured reviewer and strict schema with no stored response',async()=>{
      const original=globalThis.fetch;
      globalThis.fetch=async(url,init)=>{assert.equal(url,'https://api.openai.com/v1/responses');const body=JSON.parse(init!.body as string);assert.equal(body.model,'test-reviewer');assert.equal(body.store,false);assert.equal(body.text.format.strict,true);assert.equal(body.text.format.type,'json_schema');assert.equal(body.tools,undefined);assert.ok(!JSON.stringify(body).includes('test-key-never-sent'));return new Response(JSON.stringify({status:'completed',output:[{content:[{type:'output_text',text:JSON.stringify({decision:'proceed',summary:'Transport fixture',notes:[]})}]}],usage:{input_tokens:10,output_tokens:20}}));};
      try{const result=await new AiPlanningProvider().reviewRoutine((await run(firstId)).context);assert.equal(result.value.decision,'proceed');assert.equal(result.usage.outputTokens,20);}finally{globalThis.fetch=original;}
    });
  }finally{
    if(users.length)await db.pool.query('DELETE FROM users WHERE id=ANY($1::uuid[])',[users]);await db.pool.query('DELETE FROM exercises WHERE id=ANY($1::text[])',[[exerciseId,unapprovedId]]);await app.close();for(const[k,v]of Object.entries(previous)){if(v===undefined)delete process.env[k];else process.env[k]=v;}
  }
});
