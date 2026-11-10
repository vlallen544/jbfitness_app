import assert from 'node:assert/strict';
import {test} from 'node:test';
import {randomUUID} from 'node:crypto';
import {dashboardFixture} from './support/staff-dashboard';

test('private saved trainer messaging',async t=>{
  const f=await dashboardFixture({startDashboard:false});
  const request=async(path:string,token?:string,method='GET',body?:unknown)=>{
    const r=await fetch(`${f.apiBase}/me/trainer-messages${path}`,{method,headers:{'Content-Type':'application/json',...(token?{Authorization:`Bearer ${token}`}:{})},...(body===undefined?{}:{body:JSON.stringify(body)})});return{status:r.status,data:await r.json()};
  };
  const message=(text='Can we check my squat next session?')=>({text,requestId:randomUUID(),shareWithTrainer:true});
  try{
    const other=await f.auth.register({email:`messages-${randomUUID()}@example.test`,password:'Messaging-test-password-42!',displayName:'Other customer'});
    await f.db.pool.query('INSERT INTO trainer_assignments VALUES($1,$2)',[f.trainer.id,f.customer.id]);
    const customerPath=`/${f.trainer.id}`,trainerPath=`/${f.customer.id}`;
    await t.test('authentication, owner boundaries and customer initiation',async()=>{
      assert.equal((await request('')).status,401);
      assert.equal((await request('',f.admin.token)).status,403);
      assert.equal((await request(customerPath,other.token)).status,404);
      assert.equal((await request(trainerPath,f.trainer.token,'POST',message())).status,404);
      assert.equal((await request('',f.trainer.token)).data.conversations.length,0);
      assert.equal((await request('',f.customer.token)).data.conversations[0].id,f.trainer.id);
      assert.equal((await request(customerPath,f.customer.token,'POST',{...message(),shareWithTrainer:false})).status,400);
      assert.equal((await request(customerPath,f.customer.token,'POST',{...message(),customerId:other.user.id})).status,400);
      assert.equal((await request(customerPath,f.customer.token,'POST',message(' '))).status,400);
      assert.equal((await request(customerPath,f.customer.token,'POST',message('x'.repeat(2001)))).status,400);
    });
    await t.test('concurrent retries save one message; private profile consent is independent',async()=>{
      await f.db.pool.query("UPDATE fitness_profiles SET share_with_trainer=false,data=jsonb_set(data,'{shareCoachingWithTrainer}','false') WHERE user_id=$1",[f.customer.id]);
      const body=message();const [a,b]=await Promise.all([request(customerPath,f.customer.token,'POST',body),request(customerPath,f.customer.token,'POST',body)]);
      assert.equal(a.status,201);assert.deepEqual(a.data,b.data);
      assert.equal((await request(customerPath,f.customer.token,'POST',{...body,text:'Changed'})).status,409);
      const history=(await request(trainerPath,f.trainer.token)).data;
      assert.equal(history.messages.length,1);assert.equal(history.messages[0].text,body.text);
      assert.equal(history.profile,undefined);assert.equal(history.canSend,true);
      assert.equal((await request('',f.trainer.token)).data.conversations[0].id,f.customer.id);
      const reply=await request(trainerPath,f.trainer.token,'POST',message('Yes, we can review your technique.'));
      assert.equal(reply.status,201);
      assert.equal((await request(customerPath,f.customer.token)).data.messages[1].senderId,f.trainer.id);
      assert.equal((await request(`/${other.user.id}`,f.trainer.token)).status,404);
    });
    await t.test('bounded chronological history paginates without overlap',async()=>{
      for(let i=0;i<51;i++)await f.db.pool.query('INSERT INTO trainer_messages(id,customer_id,trainer_id,sender_id,request_id,body) VALUES($1,$2,$3,$2,$4,$5)',[randomUUID(),f.customer.id,f.trainer.id,randomUUID(),`Earlier message ${i}`]);
      const latest=(await request(customerPath,f.customer.token)).data;
      assert.equal(latest.messages.length,50);assert.ok(latest.nextBefore);
      const previous=(await request(`${customerPath}?before=${latest.nextBefore}`,f.customer.token)).data;
      assert.equal(previous.messages.length,3);assert.equal(previous.nextBefore,null);
      assert.ok(BigInt(previous.messages.at(-1).sequence)<BigInt(latest.messages[0].sequence));
      assert.equal((await request(`${customerPath}?before=bad`,f.customer.token)).status,400);
    });
    await t.test('assignment removal revokes trainer history immediately; customer keeps history',async()=>{
      await f.db.pool.query('DELETE FROM trainer_assignments WHERE trainer_id=$1 AND customer_id=$2',[f.trainer.id,f.customer.id]);
      assert.equal((await request(trainerPath,f.trainer.token)).status,404);
      assert.equal((await request(trainerPath,f.trainer.token,'POST',message())).status,404);
      assert.equal((await request('',f.trainer.token)).data.conversations.length,0);
      const history=(await request(customerPath,f.customer.token)).data;assert.equal(history.assigned,false);assert.equal(history.canSend,false);assert.equal(history.messages.length,50);
      await f.db.pool.query('INSERT INTO trainer_assignments VALUES($1,$2)',[f.trainer.id,f.customer.id]);
    });
    await t.test('daily send bound, expired membership and production exclude test memberships',async()=>{
      for(let i=0;i<50;i++)await f.db.pool.query('INSERT INTO trainer_messages(id,customer_id,trainer_id,sender_id,request_id,body) VALUES($1,$2,$3,$2,$4,$5)',[randomUUID(),f.customer.id,f.trainer.id,randomUUID(),`Rate fixture ${i}`]);
      assert.equal((await request(customerPath,f.customer.token,'POST',message())).status,429);
      const old=process.env.NODE_ENV;try{process.env.NODE_ENV='production';assert.equal((await request(customerPath,f.customer.token)).data.canSend,false);assert.equal((await request(trainerPath,f.trainer.token,'POST',message())).status,403);}finally{process.env.NODE_ENV=old;}
      await f.db.pool.query("UPDATE memberships SET starts_at=now()-interval '2 days',ends_at=now()-interval '1 second' WHERE customer_id=$1",[f.customer.id]);
      assert.equal((await request(customerPath,f.customer.token)).data.canSend,false);
      assert.equal((await request(trainerPath,f.trainer.token,'POST',message())).status,403);
    });
    await t.test('customer clearing removes both copies; trainer cannot delete or restart it',async()=>{
      assert.equal((await request(trainerPath,f.trainer.token,'DELETE')).status,403);
      assert.equal((await request(customerPath,f.customer.token,'DELETE')).status,200);
      assert.equal((await request(customerPath,f.customer.token)).data.messages.length,0);
      assert.equal((await request(trainerPath,f.trainer.token)).status,404);
      assert.equal((await request('',f.trainer.token)).data.conversations.length,0);
      const rls=(await f.db.pool.query("SELECT relrowsecurity FROM pg_class WHERE oid='trainer_messages'::regclass")).rows[0];assert.equal(rls.relrowsecurity,true);
    });
  }finally{await f.cleanup();}
});
