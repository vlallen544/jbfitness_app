import {BadRequestException,Body,Controller,ForbiddenException,Get,Inject,Injectable,NotFoundException,Param,Post,Put,Query,Req,UseGuards,ConflictException} from '@nestjs/common';
import {createHash,randomUUID} from 'node:crypto';
import {z} from 'zod';
import type {PoolClient} from 'pg';
import {AuthGuard,User} from './auth';
import {Database} from './database';
import {WorkoutService,customerOnly} from './workouts';
import {planSchema,todayInIndia,addDays} from './workout-schema';
import {equipmentMatches} from './ai-planning-schema';
import {CoachingService} from './coaching';

function parse<T>(schema:z.ZodType<T>,value:unknown):T{const r=schema.safeParse(value);if(!r.success)throw new BadRequestException('Check the submitted reference, feedback and workout values.');return r.data;}
function staff(user:User){if(!['admin','trainer'].includes(user.role))throw new ForbiddenException('Staff account required.');}
function admin(user:User){if(user.role!=='admin')throw new ForbiddenException('Administrator account required.');}
const kindSchema=z.enum(['planning','coaching']);
const hash=(value:unknown)=>createHash('sha256').update(JSON.stringify(value)).digest('hex');
const reviewSchema=z.object({requestId:z.uuid(),revision:z.number().int().min(0),decision:z.enum(['follow_up','resolved','publish_plan']),feedback:z.string().trim().min(1).max(2000),plan:planSchema.optional(),currentPlanId:z.uuid().nullable().optional()}).strict();
const sources=`SELECT 'planning'::text AS kind,r.id,r.customer_id,r.created_at FROM ai_planning_runs r WHERE r.status='review_needed' OR r.stage='trainer_published'
 UNION ALL SELECT 'coaching',c.id,c.customer_id,c.created_at FROM coaching_turns c WHERE NOT c.deleted AND c.status='completed' AND c.response->>'needsTrainerReview'='true'`;
@Injectable()
export class StaffService{
  constructor(@Inject(Database)private readonly db:Database,@Inject(WorkoutService)private readonly workouts:WorkoutService,@Inject(CoachingService)private readonly coaching:CoachingService){}
  private async shared(c:Pick<PoolClient,'query'>,user:User,customerId:string,review=false,lock=false){
    if(user.role!=='trainer')throw new ForbiddenException('Assigned trainer access is required for shared coaching details.');
    const row=(await c.query(`SELECT p.data FROM fitness_profiles p JOIN trainer_assignments a ON a.customer_id=p.user_id JOIN users t ON t.id=a.trainer_id JOIN users u ON u.id=p.user_id WHERE p.user_id=$1 AND a.trainer_id=$2 AND t.role='trainer' AND u.role='customer' AND p.share_with_trainer=true ${review?"AND p.data->>'shareCoachingWithTrainer'='true'":''} ${lock?'FOR SHARE OF p,a,t,u':''}`,[customerId,user.id])).rows[0];
    if(!row)throw new NotFoundException('Shared customer details are unavailable.');return row.data;
  }
  async overview(user:User){
    staff(user);
    const customers=(await this.db.pool.query(`SELECT u.id,u.display_name AS name,u.email,coalesce(p.share_with_trainer,false) AS "profileSharing",coalesce(p.data->>'shareCoachingWithTrainer','false')='true' AS "coachingSharing",coalesce((SELECT jsonb_agg(jsonb_build_object('id',t.id,'name',t.display_name) ORDER BY t.display_name) FROM trainer_assignments a JOIN users t ON t.id=a.trainer_id WHERE a.customer_id=u.id AND t.role='trainer'),'[]') AS trainers FROM users u LEFT JOIN fitness_profiles p ON p.user_id=u.id WHERE u.role='customer' AND ($1=true OR EXISTS(SELECT 1 FROM trainer_assignments a WHERE a.customer_id=u.id AND a.trainer_id=$2)) ORDER BY u.created_at DESC,u.id LIMIT 201`,[user.role==='admin',user.id])).rows;
    const trainers=user.role==='admin'?(await this.db.pool.query("SELECT id,display_name AS name,email FROM users WHERE role='trainer' ORDER BY display_name,id LIMIT 200")).rows:[];
    const reviews=(await this.db.pool.query(`SELECT q.kind,q.id,q.customer_id AS "customerId",u.display_name AS "customerName",q.created_at AS "createdAt",coalesce(s.status,'open') AS status,coalesce(s.revision,0) AS revision FROM (${sources}) q JOIN users u ON u.id=q.customer_id LEFT JOIN fitness_profiles p ON p.user_id=u.id LEFT JOIN staff_review_state s ON s.kind=q.kind AND s.source_id=q.id WHERE u.role='customer' AND ($1=true OR (p.share_with_trainer=true AND p.data->>'shareCoachingWithTrainer'='true' AND EXISTS(SELECT 1 FROM trainer_assignments a WHERE a.customer_id=u.id AND a.trainer_id=$2))) ORDER BY q.created_at DESC,q.id LIMIT 201`,[user.role==='admin',user.id])).rows;
    return{user,customers:customers.slice(0,200),trainers,reviews:reviews.slice(0,200),customersTruncated:customers.length>200,reviewsTruncated:reviews.length>200};
  }
  async assignment(user:User,idValue:string,input:unknown){
    admin(user);const customerId=parse(z.uuid(),idValue),body=parse(z.object({trainerId:z.uuid(),assigned:z.boolean()}).strict(),input),c=await this.db.pool.connect();
    try{
      await c.query('BEGIN');const customer=(await c.query("SELECT id FROM users WHERE id=$1 AND role='customer' FOR UPDATE",[customerId])).rows[0];if(!customer)throw new NotFoundException('Customer not found.');
      const actor=(await c.query("SELECT id FROM users WHERE id=$1 AND role='admin' FOR SHARE",[user.id])).rows[0];if(!actor)throw new ForbiddenException('Administrator access changed.');
      const trainer=(await c.query("SELECT id FROM users WHERE id=$1 AND role='trainer' FOR SHARE",[body.trainerId])).rows[0];if(!trainer)throw new NotFoundException('Trainer not found.');
      const changed=body.assigned?await c.query('INSERT INTO trainer_assignments(trainer_id,customer_id) VALUES($1,$2) ON CONFLICT DO NOTHING RETURNING trainer_id',[body.trainerId,customerId]):await c.query('DELETE FROM trainer_assignments WHERE trainer_id=$1 AND customer_id=$2 RETURNING trainer_id',[body.trainerId,customerId]);
      if(changed.rowCount)await c.query('INSERT INTO staff_audit VALUES($1,$2,$3,$4,$5,now())',[randomUUID(),user.id,customerId,body.assigned?'trainer_assigned':'trainer_unassigned',JSON.stringify({trainerId:body.trainerId})]);
      await c.query('COMMIT');return{assigned:body.assigned};
    }catch(e){await c.query('ROLLBACK');throw e;}finally{c.release();}
  }
  async customer(user:User,idValue:string){
    const id=parse(z.uuid(),idValue);const profile=await this.shared(this.db.pool,user,id);
    const canReview=profile.shareCoachingWithTrainer===true;
    const feedback=canReview?(await this.db.pool.query("SELECT id,kind,decision,feedback,created_at AS \"createdAt\" FROM staff_review_events WHERE customer_id=$1 AND feedback IS NOT NULL ORDER BY created_at DESC LIMIT 30",[id])).rows:[];
    return{profile,canReview,facts:canReview?(await this.coaching.context(id)).facts:null,feedback};
  }
  private async source(c:Pick<PoolClient,'query'>,kind:string,id:string,lock=false){
    const row=(await c.query(kind==='planning'?`SELECT id,customer_id,status,message,routine_review,draft,context,created_at FROM ai_planning_runs WHERE id=$1 AND (status='review_needed' OR stage='trainer_published') ${lock?'FOR UPDATE':''}`:`SELECT id,customer_id,input,response,facts,created_at FROM coaching_turns WHERE id=$1 AND NOT deleted AND status='completed' AND response->>'needsTrainerReview'='true' ${lock?'FOR UPDATE':''}`,[id])).rows[0];
    if(!row)throw new NotFoundException('Review item is unavailable.');return row;
  }
  async review(user:User,kindValue:string,idValue:string){
    staff(user);
    const kind=parse(kindSchema,kindValue),id=parse(z.uuid(),idValue),row=await this.source(this.db.pool,kind,id);
    const profile=await this.shared(this.db.pool,user,row.customer_id,true);
    const state=(await this.db.pool.query('SELECT status,revision FROM staff_review_state WHERE kind=$1 AND source_id=$2',[kind,id])).rows[0]??{status:'open',revision:0};
    const events=(await this.db.pool.query('SELECT e.id,e.feedback,e.decision,e.created_at AS "createdAt",u.display_name AS trainer FROM staff_review_events e LEFT JOIN users u ON u.id=e.actor_id WHERE e.kind=$1 AND e.source_id=$2 AND e.feedback IS NOT NULL ORDER BY e.created_at DESC LIMIT 30',[kind,id])).rows;
    const catalogue=kind==='planning'?(await this.db.pool.query("SELECT id,name,equipment FROM exercises WHERE review_status='approved' ORDER BY name LIMIT 500")).rows.filter(e=>equipmentMatches(e.equipment,profile.equipment)):[];
    const currentPlanId=(await this.db.pool.query('SELECT id FROM workout_plans WHERE customer_id=$1 AND superseded_at IS NULL',[row.customer_id])).rows[0]?.id??null;
    return{kind,id,customerId:row.customer_id,createdAt:row.created_at,profile,state,events,catalogue,currentPlanId,reason:kind==='planning'?row.message:row.response.reviewReason,routineReview:row.routine_review??null,draft:kind==='planning'?row.draft:null,question:row.input??null,reply:row.response?.reply??null,facts:kind==='coaching'?row.facts:null};
  }
  async decide(user:User,kindValue:string,idValue:string,input:unknown){
    staff(user);
    const kind=parse(kindSchema,kindValue),id=parse(z.uuid(),idValue),body=parse(reviewSchema,input);
    if((body.decision==='publish_plan')!==(body.plan!==undefined)||body.decision==='publish_plan'&&(kind!=='planning'||body.currentPlanId===undefined))throw new BadRequestException('Only a planning review can publish an explicitly supplied workout and current-plan reference.');
    const source=await this.source(this.db.pool,kind,id),c=await this.db.pool.connect();
    try{
      await c.query('BEGIN');await c.query('SELECT id FROM users WHERE id=$1 FOR UPDATE',[source.customer_id]);
      const profile=await this.shared(c,user,source.customer_id,true,true);
      await this.source(c,kind,id,true);
      const digest=hash({kind,id,...body});
      const old=(await c.query('SELECT payload_hash,result FROM staff_review_events WHERE actor_id=$1 AND request_id=$2',[user.id,body.requestId])).rows[0];
      if(old){if(old.payload_hash!==digest)throw new ConflictException('This review reference was used for different feedback.');await c.query('COMMIT');return old.result;}
      const state=(await c.query('SELECT revision FROM staff_review_state WHERE kind=$1 AND source_id=$2',[kind,id])).rows[0];
      if((state?.revision??0)!==body.revision)throw new ConflictException('Another review changed this item. Refresh before saving.');
      let published:{planId:string;version:number}|undefined;
      if(body.plan){
        const current=(await c.query('SELECT id FROM workout_plans WHERE customer_id=$1 AND superseded_at IS NULL',[source.customer_id])).rows[0]?.id??null;
        if(current!==body.currentPlanId)throw new ConflictException('The customer’s schedule changed. Reload this review before publishing.');
        const dates=body.plan.sessions.map(s=>s.date);
        if(new Set(dates).size!==dates.length||dates.some(d=>d<todayInIndia()||d>addDays(todayInIndia(),27)))throw new BadRequestException('Use one session per date within today and the next 27 days.');
        const ids=[...new Set(body.plan.sessions.flatMap(s=>s.exercises.map(e=>e.exerciseId)))];
        const definitions=(await c.query("SELECT id,equipment FROM exercises WHERE id=ANY($1::text[]) AND review_status='approved' FOR SHARE",[ids])).rows;
        if(definitions.length!==ids.length||definitions.some(e=>!equipmentMatches(e.equipment,profile.equipment)))throw new BadRequestException('Use approved exercises matching the saved equipment.');
        published=await this.workouts.publishPlan(source.customer_id,body.plan,'trainer',c);
        await c.query("UPDATE ai_planning_runs SET status='published',stage='trainer_published',plan_id=$2,plan_version=$3,message='Your trainer-reviewed workout is now available.',updated_at=now() WHERE id=$1",[id,published.planId,published.version]);
      }
      const revision=body.revision+1,status=body.decision==='follow_up'?'open':'resolved';
      await c.query("INSERT INTO staff_review_state(kind,source_id,customer_id,status,revision) VALUES($1,$2,$3,$4,$5) ON CONFLICT(kind,source_id) DO UPDATE SET status=excluded.status,revision=excluded.revision,updated_at=now()",[kind,id,source.customer_id,status,revision]);
      const dates=body.plan?.sessions.map(s=>s.date).sort();
      const result={revision,status,...published,...(dates?{startDate:dates[0],through:dates.at(-1)}:{})};
      await c.query('INSERT INTO staff_review_events(id,kind,source_id,customer_id,actor_id,request_id,payload_hash,decision,feedback,result) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)',[randomUUID(),kind,id,source.customer_id,user.id,body.requestId,digest,body.decision,body.feedback,JSON.stringify(result)]);
      await c.query('COMMIT');return result;
    }catch(e){await c.query('ROLLBACK');throw e;}finally{c.release();}
  }
  async feedback(customerId:string){return{feedback:(await this.db.pool.query(`SELECT e.id,e.kind,e.decision,e.feedback,e.result,e.created_at AS "createdAt",coalesce(u.display_name,'Trainer') AS trainer FROM staff_review_events e LEFT JOIN users u ON u.id=e.actor_id WHERE e.customer_id=$1 AND e.feedback IS NOT NULL AND (e.kind='planning' OR EXISTS(SELECT 1 FROM coaching_turns c WHERE c.id=e.source_id AND NOT c.deleted)) ORDER BY e.created_at DESC,e.id DESC LIMIT 50`,[customerId])).rows};}
}
@Controller('staff')
@UseGuards(AuthGuard)
export class StaffController{
  constructor(@Inject(StaffService)private readonly operations:StaffService){}
  @Get('overview')overview(@Req()r:{user:User}){return this.operations.overview(r.user);}
  @Put('customers/:id/assignment')assignment(@Req()r:{user:User},@Param('id')id:string,@Body()b:unknown){return this.operations.assignment(r.user,id,b);}
  @Get('customers/:id')customer(@Req()r:{user:User},@Param('id')id:string){return this.operations.customer(r.user,id);}
  @Get('reviews/:kind/:id')review(@Req()r:{user:User},@Param('kind')kind:string,@Param('id')id:string){return this.operations.review(r.user,kind,id);}
  @Post('reviews/:kind/:id')decide(@Req()r:{user:User},@Param('kind')kind:string,@Param('id')id:string,@Body()b:unknown){return this.operations.decide(r.user,kind,id,b);}
}
@Controller('me/trainer-feedback')
@UseGuards(AuthGuard)
export class TrainerFeedbackController{
  constructor(@Inject(StaffService)private readonly operations:StaffService){}
  @Get()feedback(@Req()r:{user:User}){return this.operations.feedback(customerOnly(r.user));}
}
