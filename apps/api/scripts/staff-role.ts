import {parseArgs} from 'node:util';
import {randomUUID} from 'node:crypto';
import {Database} from '../src/database';
async function main(){
  const {values}=parseArgs({options:{email:{type:'string'},role:{type:'string'}}});
  if(!values.email||!['trainer','admin'].includes(values.role??''))throw new Error('Use --email staff@example.com --role trainer|admin for an existing dedicated staff account.');
  const db=new Database(),c=await db.pool.connect();
  try{await c.query('BEGIN');const row=(await c.query('SELECT id,role FROM users WHERE email=$1 FOR UPDATE',[values.email.trim().toLowerCase()])).rows[0];if(!row)throw new Error('Register the dedicated account first.');
    if((await c.query('SELECT 1 FROM memberships WHERE customer_id=$1 LIMIT 1',[row.id])).rowCount)throw new Error('Use a dedicated staff account without customer memberships.');
    await c.query('UPDATE users SET role=$2 WHERE id=$1',[row.id,values.role]);await c.query('DELETE FROM sessions WHERE user_id=$1',[row.id]);await c.query('INSERT INTO staff_audit(id,actor_id,customer_id,action,metadata) VALUES($1,NULL,NULL,\'staff_role_provisioned\',$2)',[randomUUID(),JSON.stringify({userId:row.id,previousRole:row.role,role:values.role})]);await c.query('COMMIT');console.log('Staff role saved and existing sessions revoked. Sign in again.');
  }catch(e){await c.query('ROLLBACK');throw e;}finally{c.release();await db.pool.end();}
}
main().catch(e=>{console.error(e instanceof Error?e.message:'Staff provisioning failed.');process.exitCode=1;});
