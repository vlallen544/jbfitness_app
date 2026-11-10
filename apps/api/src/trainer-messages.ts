import {BadRequestException, Body, ConflictException, Controller, Delete, ForbiddenException, Get, HttpException, Inject, Injectable, NotFoundException, Param, Post, Query, Req, UseGuards} from '@nestjs/common';
import {randomUUID} from 'node:crypto';
import {z} from 'zod';
import type {PoolClient} from 'pg';
import {AuthGuard, User} from './auth';
import {Database} from './database';
import {MembershipService} from './memberships';
import {customerOnly} from './workouts';

const sendSchema=z.object({text:z.string().trim().min(1).max(2000),requestId:z.uuid(),shareWithTrainer:z.literal(true)}).strict();
const columns=`id,sequence::text AS sequence,sender_id AS "senderId",body AS text,created_at AS "createdAt"`;
function parse<T>(schema:z.ZodType<T>,input:unknown):T{const r=schema.safeParse(input);if(!r.success)throw new BadRequestException('Use a valid conversation, a message of 1–2,000 characters and confirm sharing with this trainer.');return r.data;}

@Injectable()
export class TrainerMessageService {
  constructor(@Inject(Database)private readonly db:Database,@Inject(MembershipService)private readonly memberships:MembershipService){}
  private pair(user:User,other:string){
    const id=parse(z.uuid(),other);
    if(user.role==='customer')return{customerId:user.id,trainerId:id};
    if(user.role==='trainer')return{customerId:id,trainerId:user.id};
    throw new ForbiddenException('Conversations are private to the customer and their trainer.');
  }
  private async assigned(c:Pick<PoolClient,'query'>,customerId:string,trainerId:string,lock=false){
    return (await c.query(`SELECT a.trainer_id FROM trainer_assignments a JOIN users t ON t.id=a.trainer_id JOIN users u ON u.id=a.customer_id WHERE a.customer_id=$1 AND a.trainer_id=$2 AND t.role='trainer' AND u.role='customer' ${lock?'FOR SHARE OF a,t':''}`,[customerId,trainerId])).rowCount!==0;
  }
  async list(user:User){
    if(user.role==='admin')throw new ForbiddenException('Conversations are private to the customer and their trainer.');
    // A trainer sees only conversations the customer has explicitly started.
    const conversations=(await this.db.pool.query(user.role==='customer'?`
      SELECT t.id,t.display_name AS name,EXISTS(SELECT 1 FROM trainer_assignments a WHERE a.customer_id=$1 AND a.trainer_id=t.id) AS assigned,
      (SELECT max(m.created_at) FROM trainer_messages m WHERE m.customer_id=$1 AND m.trainer_id=t.id) AS "lastMessageAt"
      FROM users t WHERE t.role='trainer' AND (EXISTS(SELECT 1 FROM trainer_assignments a WHERE a.customer_id=$1 AND a.trainer_id=t.id) OR EXISTS(SELECT 1 FROM trainer_messages m WHERE m.customer_id=$1 AND m.trainer_id=t.id)) ORDER BY "lastMessageAt" DESC NULLS LAST,t.display_name,t.id LIMIT 201`:`
      SELECT u.id,u.display_name AS name,true AS assigned,max(m.created_at) AS "lastMessageAt" FROM trainer_messages m
      JOIN users u ON u.id=m.customer_id JOIN trainer_assignments a ON a.customer_id=u.id AND a.trainer_id=m.trainer_id
      WHERE m.trainer_id=$1 AND u.role='customer' GROUP BY u.id ORDER BY "lastMessageAt" DESC,u.id LIMIT 201`,[user.id])).rows;
    return{conversations:conversations.slice(0,200),truncated:conversations.length>200};
  }
  async history(user:User,other:string,beforeValue?:string){
    const {customerId,trainerId}=this.pair(user,other);
    const before=beforeValue===undefined?null:parse(z.string().regex(/^[1-9][0-9]{0,17}$/),beforeValue);
    const c=await this.db.pool.connect();
    try{
      await c.query('BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY');
      const assigned=await this.assigned(c,customerId,trainerId);
      const hasHistory=(await c.query('SELECT 1 FROM trainer_messages WHERE customer_id=$1 AND trainer_id=$2 LIMIT 1',[customerId,trainerId])).rowCount!==0;
      if(user.role==='trainer'&&(!assigned||!hasHistory)||user.role==='customer'&&!assigned&&!hasHistory)throw new NotFoundException('Conversation is unavailable.');
      const peer=(await c.query('SELECT display_name AS name FROM users WHERE id=$1',[other])).rows[0];
      const rows=(await c.query(`SELECT ${columns} FROM trainer_messages WHERE customer_id=$1 AND trainer_id=$2 AND ($3::bigint IS NULL OR sequence<$3) ORDER BY trainer_messages.sequence DESC LIMIT 51`,[customerId,trainerId,before])).rows;
      await c.query('COMMIT');
      const membership=await this.memberships.summary(customerId,c);
      const messages=rows.slice(0,50).reverse();
      return{peer:{id:other,name:peer.name},assigned,canSend:assigned&&membership.status==='active',messages,nextBefore:rows.length>50?messages[0].sequence:null};
    }catch(e){await c.query('ROLLBACK');throw e;}finally{c.release();}
  }
  async send(user:User,other:string,input:unknown){
    const {customerId,trainerId}=this.pair(user,other),body=parse(sendSchema,input),c=await this.db.pool.connect();
    try{
      await c.query('BEGIN');
      // The same customer lock serializes sends, history clearing and assignment changes.
      await c.query('SELECT id FROM users WHERE id=$1 FOR UPDATE',[customerId]);
      if(!await this.assigned(c,customerId,trainerId,true))throw new NotFoundException('An assigned trainer is required to send messages.');
      await c.query('SELECT pg_advisory_xact_lock(hashtextextended($1,13013))',[user.id]);
      const old=(await c.query(`SELECT ${columns},customer_id,trainer_id FROM trainer_messages WHERE sender_id=$1 AND request_id=$2`,[user.id,body.requestId])).rows[0];
      if(old){
        if(old.customer_id!==customerId||old.trainer_id!==trainerId||old.text!==body.text)throw new ConflictException('This message reference was already used.');
        const {customer_id:_,trainer_id:__,...message}=old;await c.query('COMMIT');return{message};
      }
      if(user.role==='trainer'&&!(await c.query('SELECT 1 FROM trainer_messages WHERE customer_id=$1 AND trainer_id=$2 LIMIT 1',[customerId,trainerId])).rowCount)throw new NotFoundException('The customer must start this conversation first.');
      if((await this.memberships.summary(customerId,c)).status!=='active')throw new ForbiddenException('An active membership is required to send messages.');
      // Sender-wide cap; the advisory lock covers a trainer replying across multiple customers.
      const count=(await c.query("SELECT count(*)::int AS n FROM trainer_messages WHERE sender_id=$1 AND created_at>now()-interval '24 hours'",[user.id])).rows[0].n;
      if(count>=100)throw new HttpException('You have reached the 100-message daily limit. Try again later.',429);
      const message=(await c.query(`INSERT INTO trainer_messages(id,customer_id,trainer_id,sender_id,request_id,body) VALUES($1,$2,$3,$4,$5,$6) RETURNING ${columns}`,[randomUUID(),customerId,trainerId,user.id,body.requestId,body.text])).rows[0];
      await c.query('COMMIT');return{message};
    }catch(e){await c.query('ROLLBACK');throw e;}finally{c.release();}
  }
  async clear(user:User,other:string){
    customerOnly(user);const {customerId,trainerId}=this.pair(user,other),c=await this.db.pool.connect();
    try{await c.query('BEGIN');await c.query('SELECT id FROM users WHERE id=$1 FOR UPDATE',[customerId]);await c.query('DELETE FROM trainer_messages WHERE customer_id=$1 AND trainer_id=$2',[customerId,trainerId]);await c.query('COMMIT');return{cleared:true};}catch(e){await c.query('ROLLBACK');throw e;}finally{c.release();}
  }
}
@Controller('me/trainer-messages')
@UseGuards(AuthGuard)
export class TrainerMessageController {
  constructor(@Inject(TrainerMessageService)private readonly messages:TrainerMessageService){}
  @Get() list(@Req()r:{user:User}){return this.messages.list(r.user);}
  @Get(':id') history(@Req()r:{user:User},@Param('id')id:string,@Query('before')before?:string){return this.messages.history(r.user,id,before);}
  @Post(':id') send(@Req()r:{user:User},@Param('id')id:string,@Body()body:unknown){return this.messages.send(r.user,id,body);}
  @Delete(':id') clear(@Req()r:{user:User},@Param('id')id:string){return this.messages.clear(r.user,id);}
}
