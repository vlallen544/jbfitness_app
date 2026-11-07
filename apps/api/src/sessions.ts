import {BadRequestException,Body,ConflictException,Controller,ForbiddenException,Get,Inject,Injectable,NotFoundException,Param,Post,Req,ServiceUnavailableException,UseGuards} from '@nestjs/common';
import {randomUUID} from 'node:crypto';
import {z} from 'zod';
import type {PoolClient} from 'pg';
import {Database} from './database';
import {AuthGuard,User} from './auth';
import {customerOnly} from './workouts';
import {MembershipService} from './memberships';
import {SessionPolicyService,SessionVideoProvider,SessionPolicy,sessionParse as parse,sessionHash,operation,saveOperation} from './session-policy';
const uuid=(v:string)=>parse(z.uuid(),v);
const view=(b:any)=>({id:b.id,slotId:b.slot_id,trainerId:b.trainer_id,trainerName:b.trainer_name,startsAt:b.starts_at.toISOString(),endsAt:b.ends_at.toISOString(),status:b.status,consumed:b.consumed,revision:b.revision,policy:b.policy,cancellationReason:b.cancellation_reason,attendanceNote:b.attendance_note});
@Injectable()
export class SessionService{
  constructor(@Inject(Database)private readonly db:Database,@Inject(SessionPolicyService)private readonly rules:SessionPolicyService,@Inject(SessionVideoProvider)private readonly video:SessionVideoProvider,@Inject(MembershipService)private readonly memberships:MembershipService){}
  private staff(user:User){if(!['admin','trainer'].includes(user.role))throw new ForbiddenException('Staff account required.');}
  private async lockTrainer(c:PoolClient,id:string|null){if(id)await c.query("SELECT pg_advisory_xact_lock(hashtext('coaching-calendar:' || $1))",[id]);}
  private async assigned(c:Pick<PoolClient,'query'>,trainerId:string|null,customerId:string,lock=false){if(!trainerId)return false;return Boolean((await c.query(`SELECT a.trainer_id FROM trainer_assignments a JOIN users t ON t.id=a.trainer_id WHERE a.trainer_id=$1 AND a.customer_id=$2 AND t.role='trainer' ${lock?'FOR SHARE OF a,t':''}`,[trainerId,customerId])).rowCount);}
  private async transaction<T>(action:(c:PoolClient)=>Promise<T>){const c=await this.db.pool.connect();try{await c.query('BEGIN');const result=await action(c);await c.query('COMMIT');return result;}catch(e){await c.query('ROLLBACK');throw e;}finally{c.release();}}
  private async slot(c:Pick<PoolClient,'query'>,id:string,lock=false){const row=(await c.query(`SELECT * FROM coaching_slots WHERE id=$1 AND (environment<>'development' OR $2=false) ${lock?'FOR UPDATE':''}`,[id,process.env.NODE_ENV==='production'])).rows[0];if(!row)throw new NotFoundException('Session time is unavailable.');return row;}
  private async booking(c:Pick<PoolClient,'query'>,id:string,lock=false){const row=(await c.query(`SELECT b.* FROM coaching_bookings b JOIN memberships m ON m.id=b.membership_id JOIN membership_receipts r ON r.id=m.receipt_id WHERE b.id=$1 AND (r.environment<>'development' OR $2=false) ${lock?'FOR UPDATE OF b':''}`,[id,process.env.NODE_ENV==='production'])).rows[0];if(!row)throw new NotFoundException('Booking is unavailable.');return row;}
  private async member(c:PoolClient,id:string,customerId:string){const row=(await c.query('SELECT m.*,r.environment FROM memberships m JOIN membership_receipts r ON r.id=m.receipt_id WHERE m.id=$1 AND m.customer_id=$2 FOR UPDATE OF m',[id,customerId])).rows[0];if(!row||(process.env.NODE_ENV==='production'&&row.environment==='development'))throw new NotFoundException('Membership is unavailable.');return row;}
  async customer(user:User){
    customerOnly(user);const membership=await this.memberships.summary(user.id),rule=await this.rules.get();
    const bookings=(await this.db.pool.query("SELECT b.* FROM coaching_bookings b JOIN memberships m ON m.id=b.membership_id JOIN membership_receipts r ON r.id=m.receipt_id WHERE b.customer_id=$1 AND (r.environment<>'development' OR $2=false) ORDER BY b.starts_at DESC,b.id DESC LIMIT 50",[user.id,process.env.NODE_ENV==='production'])).rows.map(view);
    let slots:any[]=[];
    if(rule.policy&&membership.current&&membership.current.videoSessionsTotal>0){
      const p=rule.policy;slots=(await this.db.pool.query(`SELECT s.id,s.trainer_id AS "trainerId",s.trainer_name AS "trainerName",s.starts_at AS "startsAt",s.ends_at AS "endsAt",s.revision FROM coaching_slots s JOIN trainer_assignments a ON a.trainer_id=s.trainer_id JOIN users t ON t.id=s.trainer_id WHERE a.customer_id=$1 AND t.role='trainer' AND s.status='open' AND (s.environment<>'development' OR $6=false) AND s.starts_at>=now()+($2::float8*interval '1 hour') AND s.starts_at<=now()+($3::int*interval '1 day') AND s.ends_at<=$4::timestamptz AND extract(epoch FROM(s.ends_at-s.starts_at))=$5*60 AND NOT EXISTS(SELECT 1 FROM coaching_bookings b WHERE b.slot_id=s.id AND b.status='booked') ORDER BY s.starts_at,s.id LIMIT 100`,[user.id,p.bookingLeadHours,p.horizonDays,membership.current.endsAt,p.durationMinutes,process.env.NODE_ENV==='production'])).rows;
    }
    return{...rule,bookingEnabled:process.env.ENABLE_SESSION_BOOKING==='true'&&this.video.configured&&rule.confirmed,providerConfigured:this.video.configured,membership:membership.current,slots,bookings,timezone:'Asia/Kolkata',serverTime:new Date().toISOString()};
  }
  async calendar(user:User){this.staff(user);const rule=await this.rules.get();const slots=(await this.db.pool.query(`SELECT s.id,s.trainer_id AS "trainerId",s.trainer_name AS "trainerName",s.starts_at AS "startsAt",s.ends_at AS "endsAt",s.status,s.revision,b.id AS "bookingId",b.customer_id AS "customerId",u.display_name AS "customerName",b.status AS "bookingStatus",b.revision AS "bookingRevision",b.consumed,b.attendance_note AS "attendanceNote" FROM coaching_slots s LEFT JOIN LATERAL (SELECT * FROM coaching_bookings k WHERE k.slot_id=s.id ORDER BY (k.status='booked') DESC,k.created_at DESC,k.id DESC LIMIT 1) b ON true LEFT JOIN users u ON u.id=b.customer_id WHERE ($1=true OR s.trainer_id=$2) AND (s.environment<>'development' OR $3=false) AND s.starts_at BETWEEN now()-interval '30 days' AND now()+interval '60 days' ORDER BY s.starts_at,s.id LIMIT 200`,[user.role==='admin',user.id,process.env.NODE_ENV==='production'])).rows;return{...rule,providerConfigured:this.video.configured,bookingEnabled:process.env.ENABLE_SESSION_BOOKING==='true'&&this.video.configured&&rule.confirmed,slots,serverTime:new Date().toISOString(),timezone:'Asia/Kolkata'};}
  async createSlot(user:User,input:unknown){
    if(user.role!=='trainer')throw new ForbiddenException('Trainers publish their own availability.');
    const body=parse(z.object({startsAt:z.iso.datetime({offset:true}),policyRevision:z.number().int().min(1),requestId:z.uuid()}).strict(),input),start=new Date(body.startsAt),digest=sessionHash({...body,startsAt:start.toISOString()});
    return this.transaction(async c=>{const rule=await this.rules.required(c);await this.lockTrainer(c,user.id);const old=await operation(c,user,body.requestId,'slot',digest);if(old){await this.slot(c,old.id);return old;}
      if(!(await c.query("SELECT id FROM users WHERE id=$1 AND role='trainer' FOR SHARE",[user.id])).rowCount)throw new ForbiddenException('Trainer access changed.');
      if(rule.revision!==body.policyRevision)throw new ConflictException('Booking rules changed. Refresh before publishing availability.');
      const p=rule.policy,now=Date.now();if(start.getTime()%300000!==0||start.getTime()<now+p.bookingLeadHours*3600000||start.getTime()>now+p.horizonDays*86400000)throw new BadRequestException('Choose a future five-minute boundary within the configured booking window.');
      const end=new Date(start.getTime()+p.durationMinutes*60000);
      if((await c.query("SELECT 1 FROM coaching_slots WHERE trainer_id=$1 AND status='open' AND starts_at<$3 AND ends_at>$2 AND (environment<>'development' OR $4=false)",[user.id,start,end,process.env.NODE_ENV==='production'])).rowCount)throw new ConflictException('This time overlaps existing availability.');
      const count=(await c.query("SELECT count(*)::int AS n FROM coaching_slots WHERE trainer_id=$1 AND status='open' AND starts_at>now() AND (environment<>'development' OR $2=false)",[user.id,process.env.NODE_ENV==='production'])).rows[0].n;if(count>=200)throw new BadRequestException('Keep at most 200 future availability slots.');
      const id=randomUUID();await c.query('INSERT INTO coaching_slots(id,trainer_id,trainer_name,starts_at,ends_at,environment) VALUES($1,$2,$3,$4,$5,$6)',[id,user.id,user.displayName,start,end,process.env.NODE_ENV==='production'?'production':'development']);const result={id,revision:1};await saveOperation(c,user,body.requestId,'slot',digest,result);return result;
    });
  }
  async reserve(user:User,input:unknown){
    customerOnly(user);const body=parse(z.object({slotId:z.uuid(),slotRevision:z.number().int().positive(),policyRevision:z.number().int().positive(),requestId:z.uuid()}).strict(),input),digest=sessionHash(body);
    const prior=(await this.db.pool.query('SELECT * FROM session_operations WHERE actor_id=$1 AND request_id=$2',[user.id,body.requestId])).rows[0];if(prior){if(prior.kind!=='reserve'||prior.payload_hash!==digest)throw new ConflictException('This request reference has different booking details.');await this.booking(this.db.pool,prior.result.id);return prior.result;}
    const selected=await this.slot(this.db.pool,body.slotId);
    return this.transaction(async c=>{
      const rule=await this.rules.required(c);await this.lockTrainer(c,selected.trainer_id);await c.query('SELECT id FROM users WHERE id=$1 FOR UPDATE',[user.id]);const old=await operation(c,user,body.requestId,'reserve',digest);if(old)return old;
      if(process.env.ENABLE_SESSION_BOOKING!=='true'||!this.video.configured)throw new ServiceUnavailableException('Live session booking is not connected yet.');
      if(rule.revision!==body.policyRevision)throw new ConflictException('Booking rules changed. Review the latest terms.');
      if(!await this.assigned(c,selected.trainer_id,user.id,true))throw new NotFoundException('This trainer is not available for your account.');
      const slot=await this.slot(c,body.slotId,true),p=rule.policy,now=new Date();
      if(slot.status!=='open'||slot.revision!==body.slotRevision||slot.starts_at.getTime()<now.getTime()+p.bookingLeadHours*3600000||slot.starts_at.getTime()>now.getTime()+p.horizonDays*86400000||slot.ends_at-slot.starts_at!==p.durationMinutes*60000)throw new ConflictException('This session time changed or is no longer bookable. Refresh the calendar.');
      const membership=(await c.query(`SELECT m.id FROM memberships m JOIN membership_receipts r ON r.id=m.receipt_id WHERE m.customer_id=$1 AND m.revoked_at IS NULL AND m.starts_at<=$2 AND m.ends_at>$2 AND (r.environment<>'development' OR $3=false) ORDER BY m.starts_at DESC LIMIT 1`,[user.id,now,process.env.NODE_ENV==='production'])).rows[0];if(!membership)throw new ForbiddenException('An active video-coaching membership is required.');
      const member=await this.member(c,membership.id,user.id);if(member.video_sessions_total<=0||slot.starts_at<member.starts_at||slot.ends_at>member.ends_at)throw new ForbiddenException('Choose a session inside your active membership period and allowance.');
      const used=(await c.query('SELECT count(*)::int AS n FROM membership_session_ledger WHERE membership_id=$1',[member.id])).rows[0].n,held=(await c.query("SELECT count(*)::int AS n FROM coaching_bookings WHERE membership_id=$1 AND status='booked'",[member.id])).rows[0].n;if(used+held>=member.video_sessions_total)throw new ForbiddenException('No unreserved sessions remain in this membership.');
      if((await c.query("SELECT 1 FROM coaching_bookings WHERE status='booked' AND ((slot_id=$1) OR (customer_id=$2 AND starts_at<$4 AND ends_at>$3))",[slot.id,user.id,slot.starts_at,slot.ends_at])).rowCount)throw new ConflictException('This time is already reserved or overlaps your booking.');
      const id=randomUUID();await c.query('INSERT INTO coaching_bookings(id,slot_id,customer_id,trainer_id,trainer_name,membership_id,starts_at,ends_at,policy) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9)',[id,slot.id,user.id,slot.trainer_id,slot.trainer_name,member.id,slot.starts_at,slot.ends_at,JSON.stringify(p)]);await c.query('UPDATE coaching_slots SET revision=revision+1 WHERE id=$1',[slot.id]);const result={id,revision:1,status:'booked',consumed:false};await saveOperation(c,user,body.requestId,'reserve',digest,result);return result;
    });
  }
  private async consume(c:PoolClient,b:any,reason:'completed'|'late_cancellation'|'no_show'){
    const used=(await c.query('SELECT count(*)::int AS n FROM membership_session_ledger WHERE membership_id=$1',[b.membership_id])).rows[0].n;
    const membership=(await c.query('SELECT video_sessions_total FROM memberships WHERE id=$1',[b.membership_id])).rows[0];if(used>=membership.video_sessions_total)throw new ConflictException('The session allowance changed. An owner must review this booking.');
    await c.query('INSERT INTO membership_session_ledger(id,membership_id,customer_id,session_reference,booking_id,reason) VALUES($1,$2,$3,$4,$5,$6)',[randomUUID(),b.membership_id,b.customer_id,`booking:${b.id}`,b.id,reason]);
  }
  async cancel(user:User,idValue:string,input:unknown){
    customerOnly(user);const id=uuid(idValue),body=parse(z.object({revision:z.number().int().positive(),requestId:z.uuid()}).strict(),input),digest=sessionHash({id,...body}),found=await this.booking(this.db.pool,id);if(found.customer_id!==user.id)throw new NotFoundException('Booking is unavailable.');
    return this.transaction(async c=>{await this.lockTrainer(c,found.trainer_id);await c.query('SELECT id FROM users WHERE id=$1 FOR UPDATE',[user.id]);const old=await operation(c,user,body.requestId,'cancel',digest);if(old)return old;const b=await this.booking(c,id,true);const member=await this.member(c,b.membership_id,user.id);
      if(b.status!=='booked'||b.revision!==body.revision)throw new ConflictException('This booking changed. Refresh before cancelling.');
      const available=await this.assigned(c,b.trainer_id,user.id,true),now=new Date();if(b.starts_at<=now&&available)throw new ConflictException('This session has started. Ask staff to record the outcome.');
      const charge=available&&!member.revoked_at&&member.ends_at>now&&b.starts_at>now&&b.policy.chargeLateCancellation&&(b.starts_at.getTime()-now.getTime())<b.policy.freeCancellationHours*3600000;
      if(charge)await this.consume(c,b,'late_cancellation');
      await c.query("UPDATE coaching_bookings SET status='cancelled',consumed=$2,cancellation_reason=$3,revision=revision+1 WHERE id=$1",[id,charge,charge?'late_cancellation':'customer_cancelled']);if(b.slot_id)await c.query('UPDATE coaching_slots SET revision=revision+1 WHERE id=$1',[b.slot_id]);const result={id,status:'cancelled',consumed:charge,revision:b.revision+1};await saveOperation(c,user,body.requestId,'cancel',digest,result);return result;
    });
  }
  async withdraw(user:User,idValue:string,input:unknown){
    this.staff(user);const id=uuid(idValue),body=parse(z.object({revision:z.number().int().positive(),requestId:z.uuid(),cancelExistingBooking:z.boolean(),reason:z.enum(['trainer_unavailable','schedule_change','technical_issue'])}).strict(),input),digest=sessionHash({id,...body}),selected=await this.slot(this.db.pool,id);
    if(user.role!=='admin'&&selected.trainer_id!==user.id)throw new NotFoundException('Availability is unavailable.');
    return this.transaction(async c=>{await this.lockTrainer(c,selected.trainer_id);const booked=(await c.query("SELECT * FROM coaching_bookings WHERE slot_id=$1 AND status='booked'",[id])).rows[0];if(booked)await c.query('SELECT id FROM users WHERE id=$1 FOR UPDATE',[booked.customer_id]);const old=await operation(c,user,body.requestId,'withdraw',digest);if(old)return old;
      const slot=await this.slot(c,id,true);if(slot.status!=='open'||slot.revision!==body.revision)throw new ConflictException('Availability changed. Refresh before withdrawing.');if(booked&&!body.cancelExistingBooking)throw new ConflictException('This slot has a customer booking. Confirm its cancellation explicitly.');
      if(booked){await this.member(c,booked.membership_id,booked.customer_id);await c.query("UPDATE coaching_bookings SET status='cancelled',consumed=false,cancellation_reason=$2,revision=revision+1 WHERE id=$1",[booked.id,body.reason]);}
      await c.query("UPDATE coaching_slots SET status='withdrawn',revision=revision+1 WHERE id=$1",[id]);const result={id,status:'withdrawn',revision:slot.revision+1};await saveOperation(c,user,body.requestId,'withdraw',digest,result);return result;
    });
  }
  async outcome(user:User,idValue:string,input:unknown){
    this.staff(user);const id=uuid(idValue),body=parse(z.object({revision:z.number().int().positive(),requestId:z.uuid(),outcome:z.enum(['completed','no_show']),attendanceNote:z.string().trim().min(1).max(300)}).strict(),input),digest=sessionHash({id,...body}),found=await this.booking(this.db.pool,id);
    if(user.role!=='admin'&&found.trainer_id!==user.id)throw new NotFoundException('Booking is unavailable.');
    return this.transaction(async c=>{await this.lockTrainer(c,found.trainer_id);await c.query('SELECT id FROM users WHERE id=$1 FOR UPDATE',[found.customer_id]);if(user.role!=='admin'&&!await this.assigned(c,user.id,found.customer_id,true))throw new NotFoundException('This customer is no longer assigned to you.');const old=await operation(c,user,body.requestId,'outcome',digest);if(old)return old;
      const b=await this.booking(c,id,true);await this.member(c,b.membership_id,b.customer_id);if(b.status!=='booked'||b.revision!==body.revision)throw new ConflictException('This booking already changed. Refresh its outcome.');if(b.ends_at>new Date())throw new BadRequestException('Record attendance only after the scheduled session ends.');
      const consumed=body.outcome==='completed'||b.policy.chargeNoShow;if(consumed)await this.consume(c,b,body.outcome);
      await c.query('UPDATE coaching_bookings SET status=$2,consumed=$3,attendance_note=$4,outcome_recorded_by=$5,outcome_recorded_at=now(),revision=revision+1 WHERE id=$1',[id,body.outcome,consumed,body.attendanceNote,user.id]);if(b.slot_id)await c.query('UPDATE coaching_slots SET revision=revision+1 WHERE id=$1',[b.slot_id]);const result={id,status:body.outcome,consumed,revision:b.revision+1};await saveOperation(c,user,body.requestId,'outcome',digest,result);return result;
    });
  }
  async join(user:User,idValue:string){const b=await this.booking(this.db.pool,uuid(idValue));if(user.role==='customer'){if(b.customer_id!==user.id)throw new NotFoundException('Booking is unavailable.');}else if(user.role!=='trainer'||b.trainer_id!==user.id)throw new NotFoundException('Booking is unavailable.');
    if(b.status!=='booked'||!await this.assigned(this.db.pool,b.trainer_id,b.customer_id))throw new ForbiddenException('This booking is not available to join.');
    const membership=await this.memberships.summary(b.customer_id);if(membership.current?.id!==b.membership_id)throw new ForbiddenException('An active matching membership is required to join.');
    if(Date.now()<b.starts_at.getTime()-15*60000||Date.now()>=b.ends_at.getTime())throw new ForbiddenException('Join is available from 15 minutes before the session until its scheduled end.');return this.video.join(b.id,user);
  }
}
@Controller('me/sessions')
@UseGuards(AuthGuard)
export class CustomerSessionsController{
  constructor(@Inject(SessionService)private readonly sessions:SessionService){}
  @Get()list(@Req()r:{user:User}){return this.sessions.customer(r.user);}
  @Post()reserve(@Req()r:{user:User},@Body()b:unknown){return this.sessions.reserve(r.user,b);}
  @Post(':id/cancel')cancel(@Req()r:{user:User},@Param('id')id:string,@Body()b:unknown){return this.sessions.cancel(r.user,id,b);}
  @Post(':id/join')join(@Req()r:{user:User},@Param('id')id:string){customerOnly(r.user);return this.sessions.join(r.user,id);}
}
@Controller('staff/sessions')
@UseGuards(AuthGuard)
export class StaffSessionsController{
  constructor(@Inject(SessionService)private readonly sessions:SessionService,@Inject(SessionPolicyService)private readonly policy:SessionPolicyService){}
  @Get()list(@Req()r:{user:User}){return this.sessions.calendar(r.user);}
  @Post('policy')savePolicy(@Req()r:{user:User},@Body()b:unknown){return this.policy.save(r.user,b);}
  @Post('slots')create(@Req()r:{user:User},@Body()b:unknown){return this.sessions.createSlot(r.user,b);}
  @Post('slots/:id/withdraw')withdraw(@Req()r:{user:User},@Param('id')id:string,@Body()b:unknown){return this.sessions.withdraw(r.user,id,b);}
  @Post('bookings/:id/outcome')outcome(@Req()r:{user:User},@Param('id')id:string,@Body()b:unknown){return this.sessions.outcome(r.user,id,b);}
  @Post('bookings/:id/join')join(@Req()r:{user:User},@Param('id')id:string){if(!['trainer','admin'].includes(r.user.role))throw new ForbiddenException('Staff account required.');return this.sessions.join(r.user,id);}
}
