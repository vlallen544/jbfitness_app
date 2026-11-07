import {cookies} from 'next/headers';
import {NextResponse} from 'next/server';
export const dynamic='force-dynamic';
const cookieName='jb_staff_session',uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
class Failure extends Error{constructor(public status:number,message:string){super(message);}}
async function api(path:string,token?:string,method='GET',body?:unknown){const r=await fetch(`${process.env.API_URL??'http://127.0.0.1:3001/api/v1'}${path}`,{method,headers:{'Content-Type':'application/json',...(token?{Authorization:`Bearer ${token}`}:{})},cache:'no-store',redirect:'error',signal:AbortSignal.timeout(15000),...(body===undefined?{}:{body:JSON.stringify(body)})});const data=await r.json();if(!r.ok)throw new Failure(r.status,typeof data.message==='string'?data.message:'The request could not be completed.');return data;}
async function identity(token?:string){if(!token)throw new Failure(401,'Sign in to operations.');const data=await api('/auth/me',token);if(!['trainer','admin'].includes(data.user.role))throw new Failure(401,'Staff access changed. Sign in with a staff account.');return data.user;}
function json(data:unknown,status=200){return NextResponse.json(data,{status,headers:{'Cache-Control':'private, no-store','X-Content-Type-Options':'nosniff'}});}
function expire(r:NextResponse){r.cookies.set(cookieName,'',{httpOnly:true,sameSite:'strict',secure:process.env.NODE_ENV==='production',path:'/',maxAge:0});return r;}
function invalid():never{throw new Failure(400,'Invalid operations request.');}
async function boundedBody(request:Request){
  const reader=request.body?.getReader();if(!reader)invalid();const decoder=new TextDecoder();let size=0,text='';
  while(true){const part=await reader.read();if(part.done)break;size+=part.value.byteLength;if(size>16000){await reader.cancel();throw new Failure(413,'Use fewer sessions or shorter notes.');}text+=decoder.decode(part.value,{stream:true});}
  return text+decoder.decode();
}
async function handle(request:Request){try{
  const token=(await cookies()).get(cookieName)?.value,url=new URL(request.url);
  if(request.method==='GET'){
    const user=await identity(token),resource=url.searchParams.get('resource')??'overview';
    if(resource==='session')return json({user});if(resource==='overview')return json(await api('/staff/overview',token));
    if(resource==='session-calendar')return json({...await api('/staff/sessions',token),user});
    const id=url.searchParams.get('id')??'';if(!uuid.test(id))invalid();if(resource==='customer')return json(await api(`/staff/customers/${id}`,token));
    const kind=url.searchParams.get('kind');if(resource==='review'&&['planning','coaching'].includes(kind??''))return json(await api(`/staff/reviews/${kind}/${id}`,token));invalid();
  }
  if(request.headers.get('origin')!==(process.env.DASHBOARD_ORIGIN??url.origin))throw new Failure(403,'Use the operations dashboard to submit this request.');
  if(!request.headers.get('content-type')?.startsWith('application/json'))throw new Failure(415,'Use JSON.');
  const text=await boundedBody(request);let body:any;try{body=JSON.parse(text);}catch{invalid();}if(!body||typeof body!=='object'||Array.isArray(body))invalid();
  if(body.action==='login'){
    if(typeof body.email!=='string'||typeof body.password!=='string'||body.email.length>254||body.password.length>128)invalid();
    const data=await api('/auth/login',undefined,'POST',{email:body.email,password:body.password});
    if(!['admin','trainer'].includes(data.user.role)){await api('/auth/logout',data.token,'POST');throw new Failure(403,'Customers use the mobile app. Staff access is provisioned by the owner.');}
    if(token&&token!==data.token){try{await api('/auth/logout',token,'POST');}catch{/* Old sessions expire independently. */}}
    const r=json({user:data.user});r.cookies.set(cookieName,data.token,{httpOnly:true,sameSite:'strict',secure:process.env.NODE_ENV==='production',path:'/',expires:new Date(data.expiresAt)});return r;
  }
  if(body.action==='logout'){let revoked=true;try{if(token)await api('/auth/logout',token,'POST');}catch{revoked=false;}return expire(json({signedOut:true,revoked}));}
  await identity(token);
  if(body.action==='session-policy')return json(await api('/staff/sessions/policy',token,'POST',{policy:body.policy,revision:body.revision,requestId:body.requestId,confirmed:body.confirmed}));
  if(body.action==='create-slot')return json(await api('/staff/sessions/slots',token,'POST',{startsAt:body.startsAt,policyRevision:body.policyRevision,requestId:body.requestId}));
  if(body.action==='withdraw-slot'&&uuid.test(body.id??''))return json(await api(`/staff/sessions/slots/${body.id}/withdraw`,token,'POST',{revision:body.revision,requestId:body.requestId,cancelExistingBooking:body.cancelExistingBooking,reason:body.reason}));
  if(body.action==='booking-outcome'&&uuid.test(body.id??''))return json(await api(`/staff/sessions/bookings/${body.id}/outcome`,token,'POST',{revision:body.revision,requestId:body.requestId,outcome:body.outcome,attendanceNote:body.attendanceNote}));
  if(body.action==='assignment'&&uuid.test(body.customerId??''))return json(await api(`/staff/customers/${body.customerId}/assignment`,token,'PUT',{trainerId:body.trainerId,assigned:body.assigned}));
  if(body.action==='review'&&uuid.test(body.id??'')&&['planning','coaching'].includes(body.kind))return json(await api(`/staff/reviews/${body.kind}/${body.id}`,token,'POST',{requestId:body.requestId,revision:body.revision,decision:body.decision,feedback:body.feedback,...(body.plan===undefined?{}:{plan:body.plan,currentPlanId:body.currentPlanId})}));invalid();
}catch(e){const r=e instanceof Failure?json({message:e.message},e.status):json({message:'Operations service is unavailable. Please retry.'},503);return e instanceof Failure&&e.status===401?expire(r):r;}}
export async function GET(r:Request){return handle(r);}
export async function POST(r:Request){return handle(r);}
