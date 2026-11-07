import 'reflect-metadata';
import {randomUUID} from 'node:crypto';
import {readFile,readdir} from 'node:fs/promises';
import {resolve} from 'node:path';
import {spawn} from 'node:child_process';
import {createServer,type AddressInfo} from 'node:net';
import {Pool} from 'pg';
import {NestFactory} from '@nestjs/core';
import {AppModule} from '../../src/app.module';
import {AuthService} from '../../src/auth';
import {Database} from '../../src/database';
import {MembershipService} from '../../src/memberships';
import {todayInIndia,addDays} from '../../src/workout-schema';
export async function dashboardFixture(options:{startDashboard?:boolean}={}){
  const repo=resolve(__dirname,'../../../..'),previous=Object.fromEntries(['DATABASE_URL','NODE_ENV','ENABLE_DEV_MEMBERSHIPS','ENABLE_WORKOUT_AI','ENABLE_COACHING_AI','ENABLE_SESSION_BOOKING'].map(k=>[k,process.env[k]]));
  if(!process.env.DATABASE_URL)throw new Error('Configure the local test database first.');
  const schema='staff_qa_'+randomUUID().replaceAll('-',''),base=new Pool({connectionString:process.env.DATABASE_URL});await base.query(`CREATE SCHEMA ${schema}`);
  const url=new URL(process.env.DATABASE_URL);url.searchParams.set('options',`-csearch_path=${schema}`);Object.assign(process.env,{DATABASE_URL:url.toString(),NODE_ENV:'test',ENABLE_DEV_MEMBERSHIPS:'true',ENABLE_WORKOUT_AI:'false',ENABLE_COACHING_AI:'false'});
  let app:any,child:ReturnType<typeof spawn>|undefined;
  const cleanup=async()=>{if(child&&child.exitCode===null){child.kill('SIGTERM');await Promise.race([new Promise(r=>child!.once('exit',r)),new Promise(r=>setTimeout(r,2000))]);if(child.exitCode===null)child.kill('SIGKILL');}if(app)await app.close();await base.query(`DROP SCHEMA ${schema} CASCADE`);await base.end();for(const[k,v]of Object.entries(previous)){if(v===undefined)delete process.env[k];else process.env[k]=v;}};
  try{
    const migrationDb=new Pool({connectionString:process.env.DATABASE_URL});try{for(const file of (await readdir(resolve(repo,'apps/api/migrations'))).filter(f=>f.endsWith('.sql')).sort())await migrationDb.query(await readFile(resolve(repo,'apps/api/migrations',file),'utf8'));}finally{await migrationDb.end();}
    app=await NestFactory.create(AppModule,{logger:false});app.setGlobalPrefix('api/v1');await app.listen(0,'127.0.0.1');const db:Database=app.get(Database),auth:AuthService=app.get(AuthService),password='Dedicated-QA-password-42!';
    async function account(name:string,role:string){const email=`${role}-${randomUUID()}@example.test`,data=await auth.register({email,password,displayName:name});if(role!=='customer')await db.pool.query('UPDATE users SET role=$2 WHERE id=$1',[data.user.id,role]);return{id:data.user.id,email,password,token:data.token};}
    const admin=await account('Jordan · Owner','admin'),trainer=await account('Sam · Coach','trainer'),customer=await account('Alex Morgan','customer');
    const profile={age:28,heightCm:170,weightKg:80,goal:'general_fitness',experience:'beginner',dietaryPreference:'vegetarian',equipment:[],workoutDays:[0,2,4],sessionMinutes:30,currentRoutine:'Walking most weekdays; starting a consistent strength routine.',limitations:'',foodNotes:'',healthDataConsent:true,shareWithTrainer:true,shareCoachingWithTrainer:true};
    await auth.saveProfile({id:customer.id,email:customer.email,displayName:'Alex Morgan',role:'customer'},profile);
    await app.get(MembershipService).applyTestPurchase({customerId:customer.id,planId:'normal',eventId:randomUUID(),paymentReference:randomUUID(),amountPaise:300000,currency:'INR'});
    const exerciseId='qa-approved-squat',planningId=randomUUID(),coachingId=randomUUID(),start=addDays(todayInIndia(),1);
    await db.pool.query("INSERT INTO exercises VALUES($1,'Bodyweight squat','Legs','[]','[\"Technical QA exercise definition\"]','approved',NULL,now())",[exerciseId]);
    const plan={title:'Full-body foundation',sessions:[{date:start,title:'Build a steady routine',exercises:[{exerciseId,sets:3,repetitions:10,targetWeightKg:null,restSeconds:60}]}]};
    await db.pool.query("INSERT INTO ai_planning_runs(id,customer_id,request_id,status,stage,context,context_hash,message,draft,routine_review) VALUES($1,$2,$3,'review_needed','review_needed',$4,'fixture','A trainer should review the starting routine before publication.',$5,$6)",[planningId,customer.id,randomUUID(),JSON.stringify({profile,dates:[start]}),JSON.stringify(plan),JSON.stringify({summary:'Use a short, repeatable training schedule.',notes:[]})]);
    await db.pool.query("INSERT INTO coaching_turns(id,customer_id,request_id,kind,input,payload_hash,status,response) VALUES($1,$2,$3,'chat','How should I adjust my sessions after a busy week?','fixture','completed',$4)",[coachingId,customer.id,randomUUID(),JSON.stringify({reply:'Start with a manageable session and ask your trainer to review the adjustment.',suggestions:[],needsTrainerReview:true,reviewReason:'A personal adjustment to the routine needs trainer judgment.'})]);
    const apiBase=`http://127.0.0.1:${(app.getHttpServer().address() as AddressInfo).port}/api/v1`;
    if(options.startDashboard===false)return{app,db,auth,admin,trainer,customer,planningId,coachingId,plan,origin:'',apiBase,cleanup};
    const listener=createServer();await new Promise<void>(r=>listener.listen(0,'127.0.0.1',r));const port=(listener.address() as AddressInfo).port;await new Promise<void>(r=>listener.close(()=>r()));const origin=`http://localhost:${port}`;
    let logs='';child=spawn(process.execPath,[resolve(repo,'node_modules/next/dist/bin/next'),'start','--hostname','127.0.0.1','-p',String(port)],{cwd:resolve(repo,'apps/admin'),env:{...process.env,NODE_ENV:'production',API_URL:apiBase,DASHBOARD_ORIGIN:origin},stdio:['ignore','pipe','pipe']});child.stdout?.on('data',b=>{logs=(logs+b).slice(-4000);});child.stderr?.on('data',b=>{logs=(logs+b).slice(-4000);});
    let ready=false;for(let i=0;i<70;i++){try{if((await fetch(origin)).ok){ready=true;break;}}catch{}if(child.exitCode!==null)break;await new Promise(r=>setTimeout(r,200));}if(!ready)throw new Error('Dashboard preview did not start: '+logs);
    return{app,db,auth,admin,trainer,customer,planningId,coachingId,plan,origin,apiBase,cleanup};
  }catch(e){await cleanup();throw e;}
}
