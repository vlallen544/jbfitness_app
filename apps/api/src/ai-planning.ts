import { BadRequestException, Body, ConflictException, Controller, Get, Inject, Injectable, NotFoundException, OnModuleDestroy, OnModuleInit, Param, Post, Req, ServiceUnavailableException, UseGuards, HttpException } from '@nestjs/common';
import { createHash, randomUUID } from 'node:crypto';
import { z } from 'zod';
import { AuthGuard, User, profileSchema } from './auth';
import { Database } from './database';
import { MembershipService } from './memberships';
import { customerOnly, WorkoutService } from './workouts';
import { todayInIndia } from './workout-schema';
import { AiPlanningProvider } from './ai-planning-provider';
import { checkAiPlan, equipmentMatches, needsProfileReview, planningProfile, PlanningContext, planJudgeSchema, requestedDates, routineReviewSchema } from './ai-planning-schema';
import type { PoolClient } from 'pg';

const digest=(input:unknown)=>createHash('sha256').update(JSON.stringify(input)).digest('hex');
const unchanged=' Your current schedule is unchanged.';
function present(row:any) {
  if(!row)return null;
  return { id:row.id,requestId:row.request_id,status:row.status,stage:row.stage,message:row.message,routineReview:row.routine_review,planId:row.plan_id,version:row.plan_version,startDate:row.context.dates[0],through:row.context.dates.at(-1),createdAt:row.created_at,updatedAt:row.updated_at,callCount:row.trace.length };
}
class ClaimLost extends Error {}
@Injectable()
export class AiPlanningService {
  constructor(@Inject(Database) private readonly db:Database,@Inject(MembershipService) private readonly memberships:MembershipService,@Inject(AiPlanningProvider) private readonly provider:AiPlanningProvider,@Inject(WorkoutService) private readonly workouts:WorkoutService) {}
  private async catalogue(client:Pick<PoolClient,'query'>,equipment:string[]) {
    const rows=(await client.query("SELECT id,name,equipment,muscle_group,instructions FROM exercises WHERE review_status='approved' ORDER BY id")).rows;
    return rows.filter(e=>equipmentMatches(e.equipment,equipment)).slice(0,60).map(e=>({id:e.id,name:e.name,equipment:e.equipment,muscleGroup:e.muscle_group,instructions:e.instructions}));
  }
  async status(customerId:string) {
    const membership=await this.memberships.summary(customerId);
    const profile=(await this.db.pool.query('SELECT data FROM fitness_profiles WHERE user_id=$1',[customerId])).rows[0]?.data;
    const parsed=profileSchema.safeParse(profile);
    const catalogue=parsed.success?await this.catalogue(this.db.pool,parsed.data.equipment):[];
    const used=(await this.db.pool.query("SELECT count(*)::int AS n FROM ai_planning_runs WHERE customer_id=$1 AND (created_at AT TIME ZONE 'Asia/Kolkata')::date=$2::date",[customerId,todayInIndia()])).rows[0].n;
    const latest=(await this.db.pool.query('SELECT * FROM ai_planning_runs WHERE customer_id=$1 ORDER BY created_at DESC,id DESC LIMIT 1',[customerId])).rows[0];
    return { configured:this.provider.configured,entitled:membership.entitlements.workoutPlanning===true,profileReady:parsed.success,eligibleExerciseCount:catalogue.length,dailyLimit:2,remainingToday:Math.max(0,2-used),latest:await this.view(latest) };
  }
  async get(customerId:string,id:string) {
    if(!z.uuid().safeParse(id).success)throw new BadRequestException('Invalid planning reference.');
    const row=(await this.db.pool.query('SELECT * FROM ai_planning_runs WHERE id=$1 AND customer_id=$2',[id,customerId])).rows[0];
    if(!row)throw new NotFoundException('Planning request not found.');return this.view(row);
  }
  private async view(row:any) {
    if(!row)return null;
    const review=(await this.db.pool.query("SELECT s.status,s.revision,(SELECT e.feedback FROM staff_review_events e WHERE e.kind=s.kind AND e.source_id=s.source_id AND e.feedback IS NOT NULL ORDER BY e.created_at DESC LIMIT 1) AS feedback FROM staff_review_state s WHERE s.kind='planning' AND s.source_id=$1",[row.id])).rows[0]??null;
    const result={...present(row),trainerReview:review};
    if(row.stage==='trainer_published'){
      const dates=(await this.db.pool.query("SELECT to_char(min(scheduled_on),'YYYY-MM-DD') AS start,to_char(max(scheduled_on),'YYYY-MM-DD') AS through FROM workout_sessions WHERE plan_id=$1",[row.plan_id])).rows[0];
      return{...result,startDate:dates.start,through:dates.through};
    }
    return result;
  }
  async enqueue(customerId:string,input:unknown) {
    const body=z.object({requestId:z.uuid()}).strict().safeParse(input);
    if(!body.success)throw new BadRequestException('Use a valid planning request reference.');
    await this.memberships.requireEntitlement(customerId,'workoutPlanning');
    const c=await this.db.pool.connect();
    try {
      await c.query('BEGIN');await c.query('SELECT id FROM users WHERE id=$1 FOR UPDATE',[customerId]);
      const existing=(await c.query('SELECT * FROM ai_planning_runs WHERE customer_id=$1 AND request_id=$2',[customerId,body.data.requestId])).rows[0];
      if(existing){await c.query('COMMIT');return present(existing);}
      if(!this.provider.configured)throw new ServiceUnavailableException('AI workout planning is not connected yet.');
      if((await c.query("SELECT 1 FROM ai_planning_runs WHERE customer_id=$1 AND status IN ('queued','running')",[customerId])).rowCount)throw new ConflictException('A planning request is already in progress. Refresh its status.');
      const count=(await c.query("SELECT count(*)::int AS n FROM ai_planning_runs WHERE customer_id=$1 AND (created_at AT TIME ZONE 'Asia/Kolkata')::date=$2::date",[customerId,todayInIndia()])).rows[0].n;
      if(count>=2)throw new HttpException('Today’s two planning requests have been used. Your existing workouts remain available.',429);
      const profileRow=(await c.query('SELECT data FROM fitness_profiles WHERE user_id=$1 FOR SHARE',[customerId])).rows[0];
      const profile=profileSchema.safeParse(profileRow?.data);
      if(!profile.success)throw new BadRequestException('Complete your fitness profile before requesting a workout plan.');
      const catalogue=await this.catalogue(c,profile.data.equipment);
      if(!catalogue.length)throw new ServiceUnavailableException('Approved exercises matching your equipment have not been supplied yet.');
      const context:PlanningContext={profile:planningProfile(profile.data),dates:requestedDates(todayInIndia(),profile.data.workoutDays),catalogue,models:this.provider.models,recentWorkouts:(await c.query(`SELECT to_char(w.scheduled_on,'YYYY-MM-DD') AS date,p.status,left(p.notes,500) AS notes FROM workout_progress p JOIN workout_sessions w ON w.id=p.workout_id WHERE p.customer_id=$1 ORDER BY p.updated_at DESC LIMIT 14`,[customerId])).rows};
      if(JSON.stringify(context).length>150000)throw new ServiceUnavailableException('The exercise library needs a shorter planning catalogue.');
      const base=(await c.query('SELECT id FROM workout_plans WHERE customer_id=$1 AND superseded_at IS NULL',[customerId])).rows[0]?.id??null;
      const id=randomUUID();
      const row=(await c.query(`INSERT INTO ai_planning_runs(id,customer_id,request_id,status,stage,context,context_hash,base_plan_id,message) VALUES($1,$2,$3,'queued','queued',$4,$5,$6,'Your planning request is queued.') RETURNING *`,[id,customerId,body.data.requestId,JSON.stringify(context),digest({profile:context.profile,catalogue:context.catalogue}),base])).rows[0];
      await c.query('COMMIT');return present(row);
    }catch(error){await c.query('ROLLBACK');throw error;}finally{c.release();}
  }
  async processOne() {
    if(!this.provider.configured)return false;
    // An interrupted paid stage is never automatically replayed.
    await this.db.pool.query(`UPDATE ai_planning_runs SET status='review_needed',stage='interrupted',message=$1,updated_at=now(),claim_token=NULL WHERE status='running' AND lease_until<now()`,['Planning was interrupted and needs review.'+unchanged]);
    const c=await this.db.pool.connect();let job:any;
    try {
      await c.query('BEGIN');
      const next=(await c.query("SELECT id FROM ai_planning_runs WHERE status='queued' ORDER BY created_at,id FOR UPDATE SKIP LOCKED LIMIT 1")).rows[0];
      if(next)job=(await c.query("UPDATE ai_planning_runs SET status='running',stage='routine_review',claim_token=$2,lease_until=now()+interval '6 minutes',updated_at=now() WHERE id=$1 RETURNING *",[next.id,randomUUID()])).rows[0];
      await c.query('COMMIT');
    }catch(e){await c.query('ROLLBACK');throw e;}finally{c.release();}
    if(!job)return false;
    const context=job.context as PlanningContext;
    const trace:any[]=job.trace;
    const update=async(patch:Record<string,unknown>)=>{
      const allowed=['stage','routine_review','draft','trace','status','message'];
      const entries=Object.entries(patch);if(entries.some(([k])=>!allowed.includes(k)))throw new Error('Invalid job patch');
      const args=entries.map(([k,v])=>['routine_review','draft','trace'].includes(k)?JSON.stringify(v):v);
      const result=await this.db.pool.query(`UPDATE ai_planning_runs SET ${entries.map(([k],i)=>`${k}=$${i+1}`).join(',')},updated_at=now() WHERE id=$${args.length+1} AND claim_token=$${args.length+2} AND status='running' AND lease_until>now() RETURNING id`,[...args,job.id,job.claim_token]);
      if(!result.rowCount)throw new ClaimLost();
    };
    const finish=(status:string,message:string,stage=status)=>update({status,message,stage});
    const call=async<T extends {value:unknown;usage:unknown;model:string}>(stage:string,fn:()=>Promise<T>):Promise<T>=>{
      await this.memberships.requireEntitlement(job.customer_id,'workoutPlanning');
      if(trace.length>=5)throw new Error('Call budget exceeded');
      const item:any={stage,startedAt:new Date().toISOString(),status:'started'};trace.push(item);await update({stage,trace});
      const result=await fn();item.status='completed';item.model=result.model;item.usage=result.usage;item.finishedAt=new Date().toISOString();if(stage==='routine_review'||stage==='plan_review'||stage==='revision_review')item.assessment=result.value;await update({trace});return result;
    };
    try {
      await this.memberships.requireEntitlement(job.customer_id,'workoutPlanning');
      if(context.dates.some(d=>d<=todayInIndia())) {await finish('review_needed','This request’s training dates have passed. Request a fresh plan.'+unchanged,'stale');return true;}
      const block=needsProfileReview(context.profile);
      if(block){await finish('review_needed',block+unchanged);return true;}
      const reviewed=await call('routine_review',()=>this.provider.reviewRoutine(context));
      const review=routineReviewSchema.parse(reviewed.value);await update({routine_review:review});
      if(review.decision==='needs_review'){await finish('review_needed','Your routine needs trainer review before a new plan can be published.'+unchanged);return true;}
      let draft:unknown=null,issues:string[]=[];
      for(let attempt=0;attempt<2;attempt++) {
        const result=await call(attempt?'revision':'drafting',()=>this.provider.draft(context,review,draft,issues));draft=result.value;await update({draft,stage:'validation'});
        issues=checkAiPlan(draft,context);
        if(issues.length)continue;
        const judged=await call(attempt?'revision_review':'plan_review',()=>this.provider.judge(context,review,draft));
        const judge=planJudgeSchema.parse(judged.value);
        if(judge.decision==='needs_review'){await finish('review_needed','The workout review needs a trainer decision.'+unchanged);return true;}
        issues=judge.issues;
        if(judge.decision==='approved'&&issues.length===0){await this.publish(job,draft,context);return true;}
        if(!issues.length)issues=['Resolve the reviewer’s concerns: '+judge.summary];
      }
      await finish('review_needed','The plan did not pass its checks after one revision and needs trainer review.'+unchanged);
    }catch(error){
      if(!(error instanceof ClaimLost)) {
        try{await finish('failed','Planning could not finish. Refresh the status before requesting a new attempt.'+unchanged);}catch{/* A lost claim must never overwrite another outcome. */}
      }
    }
    return true;
  }
  private async publish(job:any,draft:unknown,context:PlanningContext) {
    const c=await this.db.pool.connect();
    try {
      await c.query('BEGIN');await c.query('SELECT id FROM users WHERE id=$1 FOR UPDATE',[job.customer_id]);
      const live=(await c.query("SELECT id FROM ai_planning_runs WHERE id=$1 AND status='running' AND claim_token=$2 AND lease_until>now() FOR UPDATE",[job.id,job.claim_token])).rows[0];
      if(!live)throw new ClaimLost();
      const profile=(await c.query('SELECT data FROM fitness_profiles WHERE user_id=$1 FOR SHARE',[job.customer_id])).rows[0]?.data;
      // Lock every supplied definition so content edits cannot race publication.
      const catalogue=(await c.query("SELECT id,name,equipment,muscle_group,instructions,review_status FROM exercises WHERE id=ANY($1::text[]) ORDER BY id FOR SHARE",[context.catalogue.map(e=>e.id)])).rows;
      const comparable=catalogue.filter(e=>e.review_status==='approved').map(e=>({id:e.id,name:e.name,equipment:e.equipment,muscleGroup:e.muscle_group,instructions:e.instructions}));
      const base=(await c.query('SELECT id FROM workout_plans WHERE customer_id=$1 AND superseded_at IS NULL',[job.customer_id])).rows[0]?.id??null;
      if(!profile||digest({profile:planningProfile(profile),catalogue:comparable})!==job.context_hash||base!==job.base_plan_id||context.dates.some(d=>d<=todayInIndia())) {
        await c.query("UPDATE ai_planning_runs SET status='review_needed',stage='stale',message=$2,updated_at=now() WHERE id=$1",[job.id,'Your profile, schedule or exercise library changed during planning. Request a fresh plan.'+unchanged]);
      }else {
        if(checkAiPlan(draft,context).length)throw new Error('Invalid publication');
        const result=await this.workouts.publishPlan(job.customer_id,draft,'ai',c);
        await c.query("UPDATE ai_planning_runs SET status='published',stage='published',plan_id=$2,plan_version=$3,message='Your AI workout plan passed the application checks and AI review and is now available.',updated_at=now() WHERE id=$1",[job.id,result.planId,result.version]);
      }
      await c.query('COMMIT');
    }catch(error){await c.query('ROLLBACK');throw error;}finally{c.release();}
  }
}

@Injectable()
export class AiPlanningWorker implements OnModuleInit,OnModuleDestroy {
  private timer?:ReturnType<typeof setInterval>;
  private active?:Promise<unknown>;
  constructor(@Inject(AiPlanningService) private readonly planning:AiPlanningService,@Inject(AiPlanningProvider) private readonly provider:AiPlanningProvider) {}
  onModuleInit() { if(this.provider.configured&&process.env.WORKOUT_AI_WORKER_ENABLED!=='false'){this.timer=setInterval(()=>{if(!this.active)this.active=this.planning.processOne().catch(()=>console.error('AI planning worker could not complete its queue check.')).finally(()=>{this.active=undefined;});},1500);this.timer.unref();} }
  async onModuleDestroy() {if(this.timer)clearInterval(this.timer);await this.active;}
}
@Controller('me/ai-planning')
@UseGuards(AuthGuard)
export class AiPlanningController {
  constructor(@Inject(AiPlanningService) private readonly planning:AiPlanningService) {}
  @Get('status') status(@Req() r:{user:User}) {return this.planning.status(customerOnly(r.user));}
  @Get(':id') get(@Req() r:{user:User},@Param('id') id:string) {return this.planning.get(customerOnly(r.user),id);}
  @Post() enqueue(@Req() r:{user:User},@Body() b:unknown) {return this.planning.enqueue(customerOnly(r.user),b);}
}
