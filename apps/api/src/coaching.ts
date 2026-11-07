import { BadRequestException, Body, ConflictException, Controller, Delete, Get, GoneException, HttpException, Inject, Injectable, NotFoundException, Param, Post, Query, Req, ServiceUnavailableException, UseGuards } from '@nestjs/common';
import {createHash,randomUUID} from 'node:crypto';
import {z} from 'zod';
import {Database} from './database';
import {AuthGuard,User,profileSchema} from './auth';
import {MembershipService} from './memberships';
import {customerOnly} from './workouts';
import {addDays,todayInIndia} from './workout-schema';
import {nutritionTotals,scaleNutrients} from './nutrition-schema';
import {CoachingProvider,validateCoachingReply} from './coaching-provider';

const requestSchema=z.object({requestId:z.uuid(),kind:z.enum(['chat','summary']),message:z.string().trim().max(2000).default('')}).strict().refine(b=>b.kind==='chat'?b.message.length>0:b.message.length===0);
const hash=(input:unknown)=>createHash('sha256').update(JSON.stringify(input)).digest('hex');
function present(row:any){return{id:row.id,requestId:row.request_id,kind:row.kind,input:row.input,status:row.status,response:row.response,facts:row.kind==='summary'?row.facts:null,source:row.source,createdAt:row.created_at,finishedAt:row.finished_at};}
@Injectable()
export class CoachingService {
  constructor(@Inject(Database)private readonly db:Database,@Inject(MembershipService)private readonly memberships:MembershipService,@Inject(CoachingProvider)private readonly provider:CoachingProvider){}
  private async recover(customerId:string){await this.db.pool.query("UPDATE coaching_turns SET status='failed',finished_at=now() WHERE customer_id=$1 AND status='pending' AND created_at<now()-interval '2 minutes'",[customerId]);}
  async context(customerId:string){
    const today=todayInIndia(),from=addDays(today,-6),c=await this.db.pool.connect();
    try{
      await c.query('BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY');
      const data=(await c.query('SELECT data FROM fitness_profiles WHERE user_id=$1',[customerId])).rows[0]?.data;
      const parsed=profileSchema.safeParse(data);
      const keys=['age','goal','experience','dietaryPreference','equipment','workoutDays','sessionMinutes','currentRoutine','limitations','foodNotes'];
      const profile=parsed.success?Object.fromEntries(keys.map(k=>[k,(parsed.data as any)[k]])):null;
      const workouts=(await c.query(`SELECT to_char(w.scheduled_on,'YYYY-MM-DD') AS date,w.title,p.status FROM workout_progress p JOIN workout_sessions w ON w.id=p.workout_id JOIN workout_plans wp ON wp.id=w.plan_id WHERE p.customer_id=$1 AND w.scheduled_on BETWEEN $2::date AND $3::date AND (p.status='completed' OR p.status='skipped') AND (wp.source<>'development_fixture' OR $4=false) ORDER BY w.scheduled_on,w.id`,[customerId,from,today,process.env.NODE_ENV==='production'])).rows;
      const scheduled=(await c.query(`SELECT count(*)::int AS n FROM workout_sessions w JOIN workout_plans p ON p.id=w.plan_id WHERE w.customer_id=$1 AND p.superseded_at IS NULL AND w.scheduled_on BETWEEN $2::date AND $3::date AND (p.source<>'development_fixture' OR $4=false)`,[customerId,from,today,process.env.NODE_ENV==='production'])).rows[0].n;
      const foods=(await c.query(`SELECT to_char(day,'YYYY-MM-DD') AS date,grams::float8 AS grams,food_snapshot AS food FROM nutrition_entries WHERE customer_id=$1 AND NOT deleted AND day BETWEEN $2::date AND $3::date ORDER BY day,id`,[customerId,from,today])).rows;
      const days=Array.from({length:7},(_,i)=>addDays(from,i)).map(date=>{
        const entries=foods.filter(e=>e.date===date);
        return{date,entries:entries.length,estimatedEntries:entries.filter(e=>e.food.source.type==='ai_estimate').length,totals:entries.length?nutritionTotals(entries.map(e=>({nutrients:scaleNutrients(e.food.nutrients,e.grams)}))):null};
      });
      const habits=(await c.query(`SELECT count(*)::int AS completed,count(DISTINCT h.id)::int AS habits FROM habit_entries e JOIN habits h ON h.id=e.habit_id WHERE h.customer_id=$1 AND e.completed AND e.day BETWEEN $2::date AND $3::date AND e.day>=h.starts_on AND (h.archived_on IS NULL OR e.day<=h.archived_on)`,[customerId,from,today])).rows[0];
      const weight=(await c.query(`SELECT to_char(day,'YYYY-MM-DD') AS date,(measurements->>'weight')::float8 AS kg FROM body_progress WHERE customer_id=$1 AND NOT deleted AND measurements->>'weight' IS NOT NULL AND day BETWEEN $2::date AND $3::date ORDER BY day DESC LIMIT 2`,[customerId,from,today])).rows.reverse();
      const conversation=(await c.query(`SELECT input,response->>'reply' AS reply FROM coaching_turns WHERE customer_id=$1 AND NOT deleted AND kind='chat' AND status='completed' ORDER BY created_at DESC,id DESC LIMIT 6`,[customerId])).rows.reverse();
      await c.query('COMMIT');
      return{profile,conversation,facts:{from,through:today,timezone:'Asia/Kolkata',workouts:{completed:workouts.filter(w=>w.status==='completed').length,skipped:workouts.filter(w=>w.status==='skipped').length,scheduledInCurrentPlan:scheduled},nutrition:{loggedDays:days.filter(d=>d.entries>0).length,entries:foods.length,estimatedEntries:foods.filter(e=>e.food.source.type==='ai_estimate').length,days},habits:{completedCheckIns:habits.completed,habitsWithCheckIns:habits.habits},weight:{readings:weight,changeKg:weight.length===2?Math.round((weight[1].kg-weight[0].kg)*100)/100:null}}};
    }catch(e){await c.query('ROLLBACK');throw e;}finally{c.release();}
  }
  async history(customerId:string,before?:string){
    await this.recover(customerId);let cursor:any;
    if(before){if(!z.uuid().safeParse(before).success)throw new BadRequestException('Invalid conversation cursor.');cursor=(await this.db.pool.query('SELECT created_at::text AS created_at,id FROM coaching_turns WHERE customer_id=$1 AND id=$2 AND NOT deleted',[customerId,before])).rows[0];if(!cursor)throw new NotFoundException('Conversation cursor not found.');}
    const rows=(await this.db.pool.query(`SELECT * FROM coaching_turns WHERE customer_id=$1 AND NOT deleted AND ($2::timestamptz IS NULL OR (created_at,id)<($2::timestamptz,$3::uuid)) ORDER BY created_at DESC,id DESC LIMIT 31`,[customerId,cursor?.created_at??null,cursor?.id??null])).rows;
    const visible=rows.slice(0,30),membership=await this.memberships.summary(customerId);
    const used=(await this.db.pool.query("SELECT kind,count(*)::int AS n FROM coaching_turns WHERE customer_id=$1 AND (created_at AT TIME ZONE 'Asia/Kolkata')::date=$2::date GROUP BY kind",[customerId,todayInIndia()])).rows;
    return{turns:visible.reverse().map(present),nextBefore:rows.length>30?rows[29].id:null,configured:this.provider.configured,canSend:membership.entitlements.aiCoaching===true,limits:{chat:20,summary:2},remaining:{chat:Math.max(0,20-(used.find(r=>r.kind==='chat')?.n??0)),summary:Math.max(0,2-(used.find(r=>r.kind==='summary')?.n??0))}};
  }
  async get(customerId:string,id:string){await this.recover(customerId);if(!z.uuid().safeParse(id).success)throw new BadRequestException('Invalid coaching reference.');const row=(await this.db.pool.query('SELECT * FROM coaching_turns WHERE id=$1 AND customer_id=$2 AND NOT deleted',[id,customerId])).rows[0];if(!row)throw new NotFoundException('Coaching response not found.');return{turn:present(row)};}
  async send(customerId:string,input:unknown){
    const parsed=requestSchema.safeParse(input);if(!parsed.success)throw new BadRequestException('Write a message up to 2,000 characters, or request a summary with an empty message.');
    const body=parsed.data,digest=hash({kind:body.kind,message:body.message});await this.memberships.requireEntitlement(customerId,'aiCoaching');await this.recover(customerId);
    const c=await this.db.pool.connect();let id='';
    try{
      await c.query('BEGIN');await c.query('SELECT id FROM users WHERE id=$1 FOR UPDATE',[customerId]);
      const old=(await c.query('SELECT * FROM coaching_turns WHERE customer_id=$1 AND request_id=$2',[customerId,body.requestId])).rows[0];
      if(old){if(old.payload_hash!==digest)throw new ConflictException('This coaching reference was used for different input.');if(old.deleted)throw new GoneException('This conversation was deleted.');await c.query('COMMIT');return{turn:present(old)};}
      if(!this.provider.configured)throw new ServiceUnavailableException('AI coaching is not connected yet.');
      if((await c.query("SELECT 1 FROM coaching_turns WHERE customer_id=$1 AND status='pending'",[customerId])).rowCount)throw new ConflictException('A coaching response is still processing. Refresh the conversation.');
      const used=(await c.query("SELECT count(*)::int AS n FROM coaching_turns WHERE customer_id=$1 AND kind=$2 AND (created_at AT TIME ZONE 'Asia/Kolkata')::date=$3::date",[customerId,body.kind,todayInIndia()])).rows[0].n;
      if(used>=(body.kind==='chat'?20:2))throw new HttpException('Today’s allowance for this coaching feature has been used.',429);
      const count=(await c.query('SELECT count(*)::int AS n FROM coaching_turns WHERE customer_id=$1 AND NOT deleted',[customerId])).rows[0].n;if(count>=1000)throw new BadRequestException('Clear older coaching history before adding more messages.');
      const profile=(await c.query('SELECT data FROM fitness_profiles WHERE user_id=$1',[customerId])).rows[0]?.data;if(!profileSchema.safeParse(profile).success)throw new BadRequestException('Complete your fitness profile before using personalized coaching.');
      id=randomUUID();await c.query("INSERT INTO coaching_turns(id,customer_id,request_id,kind,input,payload_hash,status,model) VALUES($1,$2,$3,$4,$5,$6,'pending',$7)",[id,customerId,body.requestId,body.kind,body.message||null,digest,this.provider.model]);await c.query('COMMIT');
    }catch(e){await c.query('ROLLBACK');throw e;}finally{c.release();}
    try{
      const context=await this.context(customerId);if(!context.profile)throw new BadRequestException('Complete your fitness profile.');
      const active=await this.db.pool.query("UPDATE coaching_turns SET facts=$2 WHERE id=$1 AND NOT deleted AND status='pending' RETURNING id",[id,JSON.stringify(context.facts)]);if(!active.rowCount)throw new GoneException('This conversation was cleared.');
      const result=await this.provider.respond({kind:body.kind,message:body.message,profile:context.profile,facts:context.facts,conversation:body.kind==='chat'?context.conversation:[]});
      const response=validateCoachingReply(result.response);await this.memberships.requireEntitlement(customerId,'aiCoaching');
      const row=(await this.db.pool.query("UPDATE coaching_turns SET status='completed',response=$2,usage=$3,model=$4,finished_at=now() WHERE id=$1 AND status='pending' AND NOT deleted AND created_at>now()-interval '2 minutes' RETURNING *",[id,JSON.stringify(response),JSON.stringify(result.usage),result.model])).rows[0];
      if(!row)throw new GoneException('This response expired or the conversation was cleared. Refresh the conversation.');return{turn:present(row)};
    }catch(e){await this.db.pool.query("UPDATE coaching_turns SET status='failed',finished_at=now() WHERE id=$1 AND status='pending'",[id]);throw e;}
  }
  async clear(customerId:string){
    const c=await this.db.pool.connect();try{await c.query('BEGIN');await c.query('SELECT id FROM users WHERE id=$1 FOR UPDATE',[customerId]);await c.query('UPDATE coaching_turns SET deleted=true,input=NULL,response=NULL,facts=NULL,usage=NULL,model=NULL WHERE customer_id=$1 AND NOT deleted',[customerId]);await c.query("UPDATE staff_review_events SET feedback=NULL WHERE customer_id=$1 AND kind='coaching'",[customerId]);await c.query('COMMIT');return{cleared:true};}catch(e){await c.query('ROLLBACK');throw e;}finally{c.release();}
  }
}
@Controller('me/coaching')
@UseGuards(AuthGuard)
export class CoachingController {
  constructor(@Inject(CoachingService)private readonly coaching:CoachingService){}
  @Get() history(@Req()r:{user:User},@Query('before')before?:string){return this.coaching.history(customerOnly(r.user),before);}
  @Get('facts')async facts(@Req()r:{user:User}){return{facts:(await this.coaching.context(customerOnly(r.user))).facts};}
  @Get(':id') get(@Req()r:{user:User},@Param('id')id:string){return this.coaching.get(customerOnly(r.user),id);}
  @Post() send(@Req()r:{user:User},@Body()b:unknown){return this.coaching.send(customerOnly(r.user),b);}
  @Delete() clear(@Req()r:{user:User}){return this.coaching.clear(customerOnly(r.user));}
}
