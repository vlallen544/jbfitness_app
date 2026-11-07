import assert from 'node:assert/strict';
import {browserSession} from './browser-session.mjs';

// Technical UI QA: all records/replies are fixtures, with no AI/provider requests.
const browser=await browserSession(),pause=ms=>new Promise(r=>setTimeout(r,ms));
const today=new Date().toLocaleDateString('en-CA',{timeZone:'Asia/Kolkata'}),add=(day,n)=>new Date(Date.parse(day+'T00:00:00Z')+n*86400000).toISOString().slice(0,10);
const facts={from:add(today,-6),through:today,workouts:{completed:2,skipped:1,scheduledInCurrentPlan:3},nutrition:{loggedDays:1,entries:2,estimatedEntries:1,days:Array.from({length:7},(_,i)=>({date:add(today,i-6),entries:i===6?2:0,estimatedEntries:i===6?1:0,totals:i===6?{calories:{known:650,complete:true}}:null}))},habits:{completedCheckIns:5,habitsWithCheckIns:2},weight:{readings:[{date:add(today,-6),kg:80.5},{date:today,kg:80}],changeKg:-.5}};
let rows=[],posts=0,clears=0;
const errors=[];
browser.onEvent(({method,params})=>{
  if(method!=='Fetch.requestPaused')return;
  const {requestId,request}=params,path=new URL(request.url).pathname;
  let body={token:'coaching-fixture',user:{id:'preview-user',displayName:'Alex Preview',email:'preview@example.test',role:'customer'},profile:{workoutDays:[0,2,4],sessionMinutes:30}};
  if(path.endsWith('/me/habits'))body={month:today.slice(0,7),today,canEdit:true,habits:[],entries:[],days:[],summary:{completed:0,goal:0,progress:0}};
  if(path.endsWith('/me/coaching/facts'))body={facts};
  if(path.endsWith('/me/coaching')){
    if(request.method==='POST'){
      const input=JSON.parse(request.postData);assert.deepEqual(Object.keys(input).sort(),['kind','message','requestId']);posts++;
      const summary=input.kind==='summary';
      const turn={id:summary?'summary':'chat',requestId:input.requestId,kind:input.kind,input:input.message,status:'completed',source:'ai',facts:summary?facts:null,createdAt:new Date(Date.now()+posts*1000).toISOString(),response:{reply:summary?'Your records show two completed workouts and five habit check-ins in this period. Food was logged on one day, so it cannot describe your full week’s intake.':'Choose a manageable time for your next scheduled session. Use your saved training days to build consistency.',suggestions:summary?['Choose a repeatable time for your next workout.','Log food when practical to make the next summary more useful.']:['Use a calendar reminder for your next session.'],needsTrainerReview:false,reviewReason:null}};
      rows.push(turn);body={turn};
    }else if(request.method==='DELETE'){clears++;rows=[];body={cleared:true};}
    else body={turns:rows,nextBefore:null,configured:true,canSend:true,limits:{chat:20,summary:2},remaining:{chat:20-rows.filter(r=>r.kind==='chat').length,summary:2-rows.filter(r=>r.kind==='summary').length}};
  }
  browser.call('Fetch.fulfillRequest',{requestId,responseCode:200,responseHeaders:[{name:'Content-Type',value:'application/json'},{name:'Access-Control-Allow-Origin',value:'http://localhost:8080'},{name:'Access-Control-Allow-Headers',value:'content-type,authorization'},{name:'Access-Control-Allow-Methods',value:'GET,POST,DELETE,OPTIONS'}],body:Buffer.from(JSON.stringify(body)).toString('base64')}).catch(e=>errors.push(e));
});
async function hasText(value){return browser.evaluate(`document.body.innerText.includes(${JSON.stringify(value)}) || Array.from(document.querySelectorAll('[aria-label]')).some(e=>e.getAttribute('aria-label').includes(${JSON.stringify(value)}))`);}
async function waitFor(check,label){for(let i=0;i<100;i++){if(await check())return;await pause(200);}throw new Error(`Timed out: ${label}`);}
async function wheel(deltaY){await browser.call('Input.dispatchMouseEvent',{type:'mouseWheel',x:300,y:550,deltaX:0,deltaY});await pause(350);}
async function click(label){const found=await browser.evaluate(`(()=>{const e=Array.from(document.querySelectorAll('[role=button]')).find(e=>(e.innerText||e.getAttribute('aria-label')||'').trim()===${JSON.stringify(label)});if(!e)return false;e.click();return true;})()`);if(!found)throw new Error(`Button missing: ${label}`);await pause(250);}
async function seek(label){for(let i=0;i<30;i++){if(await hasText(label))return;await wheel(300);}throw new Error(`Not visible: ${label}`);}
async function fill(label,value){for(let i=0;i<30;i++){const p=await browser.evaluate(`(()=>{const e=document.querySelector(${JSON.stringify(`input[aria-label="${label}"],textarea[aria-label="${label}"]`)});if(!e)return null;const r=e.getBoundingClientRect();return{x:r.x+r.width/2,y:r.y+r.height/2}})()`);if(p&&p.y>50&&p.y<780){for(const type of ['mousePressed','mouseReleased'])await browser.call('Input.dispatchMouseEvent',{type,...p,button:'left',clickCount:1});await browser.call('Input.insertText',{text:value});return;}await wheel(p&&p.y<50?-200:200);}throw new Error(`Input missing: ${label}`);}
async function capture(name){await browser.call('Input.dispatchMouseEvent',{type:'mouseMoved',x:2,y:2});await pause(650);await browser.screenshot(`docs/previews/${name}.png`);}
try{
  await browser.call('Fetch.enable',{patterns:[{urlPattern:'http://localhost:3001/*'}]});await browser.call('Page.navigate',{url:'http://localhost:8080'});await pause(2500);await browser.evaluate('localStorage.clear()');await browser.call('Page.reload',{ignoreCache:true});await pause(2500);
  await waitFor(async()=>{await browser.evaluate('document.querySelector("flt-semantics-placeholder")?.click()');return hasText('Welcome back.');},'login');await fill('Email address','preview@example.test');await fill('Password','coaching-preview-password');await click('Sign in');await waitFor(()=>hasText('Hello, Alex.'),'Today');
  await seek('Open AI coach');await click('Open AI coach');await waitFor(()=>hasText('Your recorded week'),'coach facts');await capture('coaching-recorded-week');
  await fill('Ask your AI coach','How can I make my routine more consistent?');await seek('Send to AI coach');assert.equal(posts,0);await click('Send to AI coach');await waitFor(()=>hasText('Choose a manageable time'),'AI reply');await wheel(300);await capture('coaching-chat');assert.equal(posts,1);
  await wheel(-5000);await seek('Summarize my last 7 days');await click('Summarize my last 7 days');await seek('Your records show two completed workouts');await wheel(500);await capture('coaching-summary');assert.equal(posts,2);assert.equal(rows[1].facts.nutrition.loggedDays,1);
  await click('Clear coaching history');await waitFor(()=>hasText('Clear history'),'deletion confirmation');assert.equal(clears,0);await click('Clear history');await waitFor(async()=>clears===1,'clear saved history');await wheel(-5000);await waitFor(()=>hasText('Your recorded week'),'facts preserved');assert.equal(rows.length,0);assert.equal(errors.length,0);
  console.log('Coaching visual QA passed: recorded facts, explicit chat, labelled AI reply, weekly summary snapshot and confirmed deletion preserving tracking records. All responses are fixtures; no provider was called.');
}finally{
  try{await browser.call('Fetch.disable');await browser.evaluate('localStorage.clear()');}catch{/* preserve original error */}
  browser.close();
}
