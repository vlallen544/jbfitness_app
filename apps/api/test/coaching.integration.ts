import 'reflect-metadata';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {test} from 'node:test';
import type {AddressInfo} from 'node:net';
import {NestFactory} from '@nestjs/core';
import {AppModule} from '../src/app.module';
import {Database} from '../src/database';
import {MembershipService} from '../src/memberships';
import {CoachingProvider} from '../src/coaching-provider';
import {WorkoutService} from '../src/workouts';
import {todayInIndia,addDays} from '../src/workout-schema';

const profile={age:28,heightCm:170,weightKg:80,goal:'general_fitness',experience:'beginner',dietaryPreference:'vegetarian',equipment:[],workoutDays:[0,2,4],sessionMinutes:30,currentRoutine:'Walking on weekdays',limitations:'',foodNotes:'Private dietary preference fixture',healthDataConsent:true,shareWithTrainer:false};
const reply=()=>({reply:'Keep your next session manageable and use your recorded training days.',suggestions:['Choose a practical time for your next session.'],needsTrainerReview:false,reviewReason:null});
test('private contextual coaching, recorded facts and weekly summaries',async t=>{
  const previous={NODE_ENV:process.env.NODE_ENV,ENABLE_DEV_MEMBERSHIPS:process.env.ENABLE_DEV_MEMBERSHIPS,ENABLE_COACHING_AI:process.env.ENABLE_COACHING_AI,COACHING_AI_MODEL:process.env.COACHING_AI_MODEL,OPENAI_API_KEY:process.env.OPENAI_API_KEY};
  Object.assign(process.env,{NODE_ENV:'test',ENABLE_DEV_MEMBERSHIPS:'true',ENABLE_COACHING_AI:'false',COACHING_AI_MODEL:'test-coach',OPENAI_API_KEY:'test-key-never-sent'});
  const start=async()=>{const a=await NestFactory.create(AppModule,{logger:false});a.setGlobalPrefix('api/v1');await a.listen(0,'127.0.0.1');return a;};
  let app=await start(),db=app.get(Database),provider=app.get(CoachingProvider);
  const users:string[]=[],exerciseId=`coach-fixture-${randomUUID()}`;
  const request=async(path:string,token?:string,method='GET',body?:unknown)=>{const r=await fetch(`http://127.0.0.1:${(app.getHttpServer().address() as AddressInfo).port}/api/v1${path}`,{method,headers:{'Content-Type':'application/json',...(token?{Authorization:`Bearer ${token}`}:{})},...(body===undefined?{}:{body:JSON.stringify(body)})});return{status:r.status,data:await r.json()};};
  const customer=async()=>{const r=await request('/auth/register',undefined,'POST',{email:`coach-${randomUUID()}@example.test`,password:'Coach-test-password-42!',displayName:'PRIVATE_NAME_NOT_FOR_AI'});assert.equal(r.status,201);users.push(r.data.user.id);await request('/me/profile',r.data.token,'PUT',profile);return{id:r.data.user.id as string,token:r.data.token as string};};
  const purchase=async(id:string)=>app.get(MembershipService).applyTestPurchase({customerId:id,planId:'normal',eventId:randomUUID(),paymentReference:randomUUID(),amountPaise:300000,currency:'INR'});
  const send=(token:string,message='Help me stay consistent',ref=randomUUID(),kind='chat')=>request('/me/coaching',token,'POST',{kind,message,requestId:ref});
  let calls=0,context:any;let firstId='';
  const defaultProvider=()=>{provider.respond=async c=>{calls++;context=c;return{response:reply(),usage:{inputTokens:10,outputTokens:20},model:'test-coach'};};};
  try{
    const a=await customer(),b=await customer();defaultProvider();
    await t.test('authentication, roles, membership, provider configuration and strict requests are enforced',async()=>{
      assert.equal((await request('/me/coaching')).status,401);assert.equal((await send(a.token)).status,403);
      await db.pool.query("UPDATE users SET role='trainer' WHERE id=$1",[b.id]);assert.equal((await request('/me/coaching',b.token)).status,403);await db.pool.query("UPDATE users SET role='customer' WHERE id=$1",[b.id]);
      await purchase(a.id);await purchase(b.id);assert.equal((await send(a.token)).status,503);assert.equal(calls,0);process.env.ENABLE_COACHING_AI='true';
      assert.equal((await send(a.token,'')).status,400);assert.equal((await send(a.token,'x'.repeat(2001))).status,400);assert.equal((await send(a.token,'not empty',randomUUID(),'summary')).status,400);
      assert.equal((await request('/me/coaching',a.token,'POST',{kind:'chat',message:'Hello',requestId:randomUUID(),userId:b.id})).status,400);
    });
    await t.test('facts preserve missing data, deterministic nutrients, AI estimate labels and dated weights',async()=>{
      const today=todayInIndia(),from=addDays(today,-6);
      const empty=(await request('/me/coaching/facts',a.token)).data.facts;assert.equal(empty.nutrition.loggedDays,0);assert.equal(empty.nutrition.days[0].totals,null);assert.equal(empty.weight.changeKg,null);
      for(const [date,weight] of [[from,80.5],[today,79]])await db.pool.query('INSERT INTO body_progress(id,customer_id,day,measurements,create_request_id,create_hash) VALUES($1,$2,$3,$4,$5,\'fixture\')',[randomUUID(),a.id,date,JSON.stringify({weight}),randomUUID()]);
      const nutrients={calories:130,protein:2.7,carbs:28,fat:.3,fiber:null,sugar:null,sodium:null};
      await db.pool.query("INSERT INTO nutrition_entries(id,customer_id,day,meal,grams,food_snapshot,create_request_id,create_payload_hash) VALUES($1,$2,$3,'lunch',150,$4,$5,'fixture')",[randomUUID(),a.id,today,JSON.stringify({name:'Estimated rice fixture',nutrients,source:{type:'ai_estimate',label:'AI estimate'}}),randomUUID()]);
      const habit=randomUUID();await db.pool.query("INSERT INTO habits(id,customer_id,name,target_days,create_request_id,starts_on) VALUES($1,$2,'Technical habit',20,$3,$4)",[habit,a.id,randomUUID(),from]);await db.pool.query('INSERT INTO habit_entries(habit_id,day,completed) VALUES($1,$2,true)',[habit,today]);
      await db.pool.query("INSERT INTO exercises(id,name,muscle_group,equipment,instructions,review_status) VALUES($1,'Technical coaching fixture','fixture','[]','[\"Technical test only\"]','approved')",[exerciseId]);
      await app.get(WorkoutService).publishPlan(a.id,{title:'Technical summary fixture',sessions:[{date:today,title:'Technical session',exercises:[{exerciseId,sets:2,repetitions:10,targetWeightKg:null,restSeconds:60}]}]},'trainer');
      const workout=(await db.pool.query('SELECT w.id,i.id AS item FROM workout_sessions w JOIN workout_items i ON i.workout_id=w.id WHERE w.customer_id=$1',[a.id])).rows[0];
      await app.get(WorkoutService).saveProgress(a.id,workout.id,{requestId:randomUUID(),revision:0,status:'completed',notes:'Technical completion',exerciseLogs:[{itemId:workout.item,completed:true,actualSets:2,actualRepetitions:10,actualWeightKg:null,difficulty:'moderate',notes:''}]});
      const facts=(await request('/me/coaching/facts',a.token)).data.facts;assert.equal(facts.nutrition.loggedDays,1);assert.equal(facts.nutrition.estimatedEntries,1);assert.equal(facts.nutrition.days[6].totals.calories.known,195);assert.equal(facts.nutrition.days[6].totals.fiber.complete,false);assert.equal(facts.habits.completedCheckIns,1);assert.equal(facts.weight.changeKg,-1.5);assert.equal(facts.workouts.completed,1);assert.equal(facts.workouts.scheduledInCurrentPlan,1);
      assert.equal((await request('/me/coaching/facts',b.token)).data.facts.nutrition.entries,0);
    });
    await t.test('saved chat is owner-only, duplicate-safe and contextual without leaking identifiers or photos',async()=>{
      const ref=randomUUID();const r=await send(a.token,'How can I make my routine consistent?',ref);assert.equal(r.status,201);firstId=r.data.turn.id;assert.equal(r.data.turn.response.reply,reply().reply);assert.equal(calls,1);
      assert.equal((await send(a.token,'How can I make my routine consistent?',ref)).data.turn.id,firstId);assert.equal(calls,1);assert.equal((await send(a.token,'Different question',ref)).status,409);
      assert.equal((await request(`/me/coaching/${firstId}`,b.token)).status,404);assert.equal((await request('/me/coaching',b.token)).data.turns.length,0);
      assert.equal(context.profile.goal,profile.goal);assert.equal(context.facts.nutrition.loggedDays,1);assert.equal(context.profile.foodNotes,profile.foodNotes);assert.ok(!JSON.stringify(context).includes('PRIVATE_NAME_NOT_FOR_AI'));assert.ok(!JSON.stringify(context).includes('@example.test'));assert.equal(context.profile.heightCm,undefined);assert.equal(context.photos,undefined);
      const next=await send(a.token,'What about a simple meal idea?');assert.equal(next.status,201);assert.equal(context.conversation.length,1);assert.equal(context.conversation[0].input,'How can I make my routine consistent?');
      assert.equal((await db.pool.query('SELECT count(*)::int AS n FROM workout_plans WHERE customer_id=$1',[a.id])).rows[0].n,1);
    });
    await t.test('summary snapshots retain deterministic facts and do not change after later diary edits',async()=>{
      const result=await send(a.token,'',randomUUID(),'summary');assert.equal(result.status,201);const turn=result.data.turn;assert.equal(turn.facts.nutrition.loggedDays,1);assert.equal(turn.facts.weight.changeKg,-1.5);assert.deepEqual(context.conversation,[]);
      await db.pool.query('UPDATE nutrition_entries SET deleted=true WHERE customer_id=$1',[a.id]);assert.equal((await request('/me/coaching/facts',a.token)).data.facts.nutrition.loggedDays,0);
      assert.equal((await request(`/me/coaching/${turn.id}`,a.token)).data.turn.facts.nutrition.loggedDays,1);
    });
    await t.test('one in-flight request blocks duplicates without charging twice; clearing prevents late replies from returning',async()=>{
      let entered!:()=>void,release!:()=>void;const started=new Promise<void>(r=>entered=r),gate=new Promise<void>(r=>release=r);provider.respond=async()=>{calls++;entered();await gate;return{response:reply(),usage:{inputTokens:1,outputTokens:1},model:'test-coach'};};
      const user=await customer();await purchase(user.id);const ref=randomUUID(),first=send(user.token,'Concurrent message',ref);await started;const before=calls;
      const duplicate=await send(user.token,'Concurrent message',ref);assert.equal(duplicate.status,201);assert.equal(duplicate.data.turn.status,'pending');assert.equal(calls,before);assert.equal((await send(user.token,'Another message')).status,409);
      assert.equal((await request('/me/coaching',user.token,'DELETE')).status,200);release();assert.equal((await first).status,410);assert.equal((await request('/me/coaching',user.token)).data.turns.length,0);
      const row=(await db.pool.query('SELECT * FROM coaching_turns WHERE customer_id=$1',[user.id])).rows[0];assert.equal(row.input,null);assert.equal(row.response,null);assert.equal(row.facts,null);assert.equal((await send(user.token,'Concurrent message',ref)).status,410);defaultProvider();
    });
    await t.test('review flags persist, invalid provider output fails, and failed references do not call again',async()=>{
      provider.respond=async()=>({response:{...reply(),needsTrainerReview:true,reviewReason:'A trainer should review this question.'},usage:{inputTokens:1,outputTokens:1},model:'test-coach'});
      const result=await send(b.token);assert.equal(result.data.turn.response.needsTrainerReview,true);
      provider.respond=async()=>{calls++;return{response:{...reply(),needsTrainerReview:true,reviewReason:null},usage:{inputTokens:1,outputTokens:1},model:'test-coach'};};
      const ref=randomUUID(),before=calls;assert.equal((await send(b.token,'Invalid output fixture',ref)).status,502);const retry=await send(b.token,'Invalid output fixture',ref);assert.equal(retry.data.turn.status,'failed');assert.equal(calls,before+1);defaultProvider();
    });
    await t.test('quotas count failed/deleted attempts; history pagination is stable and owner-scoped',async()=>{
      const user=await customer();await purchase(user.id);
      for(let i=0;i<35;i++)await db.pool.query("INSERT INTO coaching_turns(id,customer_id,request_id,kind,input,payload_hash,status,created_at) VALUES($1,$2,$3,'chat',$4,'fixture','failed',now()-interval '1 day'-($5::int*interval '1 second'))",[randomUUID(),user.id,randomUUID(),`Earlier message ${i}`,i]);
      const page=(await request('/me/coaching',user.token)).data;assert.equal(page.turns.length,30);assert.ok(page.nextBefore);const older=(await request(`/me/coaching?before=${page.nextBefore}`,user.token)).data;assert.equal(older.turns.length,5);assert.equal(older.nextBefore,null);assert.equal((await request(`/me/coaching?before=${page.nextBefore}`,a.token)).status,404);
      for(let i=0;i<20;i++)await db.pool.query("INSERT INTO coaching_turns(id,customer_id,request_id,kind,payload_hash,status,deleted) VALUES($1,$2,$3,'chat','fixture','failed',true)",[randomUUID(),user.id,randomUUID()]);
      assert.equal((await send(user.token)).status,429);assert.equal((await request('/me/coaching',user.token)).data.remaining.chat,0);
      assert.equal((await send(user.token,'',randomUUID(),'summary')).status,201);assert.equal((await send(user.token,'',randomUUID(),'summary')).status,201);assert.equal((await send(user.token,'',randomUUID(),'summary')).status,429);
    });
    await t.test('restart, stale-request recovery and expiry preserve history and allow deletion',async()=>{
      const ref=randomUUID();await db.pool.query("INSERT INTO coaching_turns(id,customer_id,request_id,kind,input,payload_hash,status,created_at) VALUES($1,$2,$3,'chat','Interrupted fixture','fixture','pending',now()-interval '3 minutes')",[randomUUID(),b.id,ref]);
      await app.close();app=await start();db=app.get(Database);provider=app.get(CoachingProvider);defaultProvider();
      const history=(await request('/me/coaching',b.token)).data;assert.ok(history.turns.some((r:any)=>r.requestId===ref&&r.status==='failed'));assert.ok(history.turns.some((r:any)=>r.response?.needsTrainerReview));
      await db.pool.query("UPDATE memberships SET ends_at=now()-interval '1 second',starts_at=now()-interval '2 days' WHERE customer_id=$1",[b.id]);assert.equal((await send(b.token)).status,403);assert.equal((await request('/me/coaching',b.token)).data.canSend,false);
      assert.equal((await request('/me/coaching',b.token,'DELETE')).status,200);assert.equal((await request('/me/coaching',b.token)).data.turns.length,0);assert.equal((await request('/me/coaching',a.token)).data.turns.length,3);
    });
    await t.test('real transport uses a strict response schema, server model and no action tools',async()=>{
      const original=globalThis.fetch;globalThis.fetch=async(url,init)=>{assert.equal(url,'https://api.openai.com/v1/responses');const body=JSON.parse(init!.body as string);assert.equal(body.model,'test-coach');assert.equal(body.store,false);assert.equal(body.text.format.strict,true);assert.equal(body.tools,undefined);assert.ok(!JSON.stringify(body).includes('test-key-never-sent'));return new Response(JSON.stringify({status:'completed',output:[{content:[{type:'output_text',text:JSON.stringify(reply())}]}],usage:{input_tokens:10,output_tokens:20}}));};
      try{const result=await new CoachingProvider().respond({message:'Technical fixture'});assert.equal(result.response.reply,reply().reply);assert.equal(result.usage.outputTokens,20);}finally{globalThis.fetch=original;}
    });
  }finally{if(users.length)await db.pool.query('DELETE FROM users WHERE id=ANY($1::uuid[])',[users]);await db.pool.query('DELETE FROM exercises WHERE id=$1',[exerciseId]);await app.close();for(const[k,v]of Object.entries(previous)){if(v===undefined)delete process.env[k];else process.env[k]=v;}}
});
