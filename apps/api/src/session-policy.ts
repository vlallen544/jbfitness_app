import {BadRequestException,ConflictException,ForbiddenException,Inject,Injectable,ServiceUnavailableException} from '@nestjs/common';
import {z} from 'zod';
import type {PoolClient} from 'pg';
import {createHash} from 'node:crypto';
import {Database} from './database';
import {User} from './auth';
export const sessionPolicySchema=z.object({durationMinutes:z.number().int().min(15).max(120).multipleOf(5),bookingLeadHours:z.number().min(0).max(168),horizonDays:z.number().int().min(1).max(60),freeCancellationHours:z.number().min(0).max(168),chargeLateCancellation:z.boolean(),chargeNoShow:z.boolean()}).strict();
export type SessionPolicy=z.infer<typeof sessionPolicySchema>;
export function sessionParse<T>(schema:z.ZodType<T>,input:unknown):T{const r=schema.safeParse(input);if(!r.success)throw new BadRequestException('Check the session times, policy, revision and request reference.');return r.data;}
export const sessionHash=(input:unknown)=>createHash('sha256').update(JSON.stringify(input)).digest('hex');
export async function operation(c:PoolClient,user:User,requestId:string,kind:string,hash:string){const old=(await c.query('SELECT * FROM session_operations WHERE actor_id=$1 AND request_id=$2',[user.id,requestId])).rows[0];if(old){if(old.kind!==kind||old.payload_hash!==hash)throw new ConflictException('This request reference was used for a different session operation.');return old.result;}return null;}
export async function saveOperation(c:PoolClient,user:User,requestId:string,kind:string,hash:string,result:unknown){await c.query('INSERT INTO session_operations(actor_id,request_id,kind,payload_hash,result) VALUES($1,$2,$3,$4,$5)',[user.id,requestId,kind,hash,JSON.stringify(result)]);}
@Injectable()
export class SessionPolicyService{
  constructor(@Inject(Database)private readonly db:Database){}
  async get(client:Pick<PoolClient,'query'>=this.db.pool,lock=false){const row=(await client.query(`SELECT policy,revision FROM session_policy WHERE id=true ${lock?'FOR SHARE':''}`)).rows[0];return{policy:row?.policy?sessionParse(sessionPolicySchema,row.policy):null,revision:row?.revision??0,confirmed:Boolean(row?.policy)};}
  async save(user:User,input:unknown){
    if(user.role!=='admin')throw new ForbiddenException('Administrator account required.');
    const body=sessionParse(z.object({policy:sessionPolicySchema,revision:z.number().int().min(0),requestId:z.uuid(),confirmed:z.literal(true)}).strict(),input),digest=sessionHash(body),c=await this.db.pool.connect();
    try{await c.query('BEGIN');const row=(await c.query('SELECT revision FROM session_policy WHERE id=true FOR UPDATE')).rows[0];const old=await operation(c,user,body.requestId,'policy',digest);if(old){await c.query('COMMIT');return old;}
      if(row.revision!==body.revision)throw new ConflictException('Booking rules changed. Refresh before confirming.');
      if(!(await c.query("SELECT id FROM users WHERE id=$1 AND role='admin' FOR SHARE",[user.id])).rowCount)throw new ForbiddenException('Administrator access changed.');
      const revision=body.revision+1;await c.query('UPDATE session_policy SET policy=$1,revision=$2,updated_at=now() WHERE id=true',[JSON.stringify(body.policy),revision]);const result={policy:body.policy,revision,confirmed:true};await saveOperation(c,user,body.requestId,'policy',digest,result);await c.query('COMMIT');return result;
    }catch(e){await c.query('ROLLBACK');throw e;}finally{c.release();}
  }
  async required(c:Pick<PoolClient,'query'>,lock=true){const value=await this.get(c,lock);if(!value.policy)throw new ServiceUnavailableException('Booking rules have not been confirmed by the owner.');return{policy:value.policy,revision:value.revision};}
}
@Injectable()
export class SessionVideoProvider{
  // A real provider adapter is deliberately required; an environment flag cannot fabricate a working call.
  get configured(){return false;}
  async join(_bookingId:string,_user:User):Promise<{url:string}>{throw new ServiceUnavailableException('The in-app video provider is not connected yet.');}
}
