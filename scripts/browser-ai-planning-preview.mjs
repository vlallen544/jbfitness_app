import assert from 'node:assert/strict';
import { browserSession } from './browser-session.mjs';

// UI fixtures only: no model is called and no real fitness plan is evaluated.
const browser=await browserSession(),pause=ms=>new Promise(r=>setTimeout(r,ms));
const today=new Date().toLocaleDateString('en-CA',{timeZone:'Asia/Kolkata'});
const add=(date,days)=>new Date(Date.parse(date+'T00:00:00Z')+days*86400000).toISOString().slice(0,10);
const dates=[1,3,5].map(d=>add(today,d));
let requested=0,publishAllowed=false,latest=null,published=false,statusReads=0;
const errors=[];
browser.onEvent(({method,params})=>{
  if(method!=='Fetch.requestPaused')return;
  const {requestId,request}=params,url=new URL(request.url),path=url.pathname;
  let body={token:'ai-planning-fixture',user:{id:'preview-user',displayName:'Alex Preview',email:'preview@example.test',role:'customer'},profile:{workoutDays:[0,2,4],sessionMinutes:30}};
  if(path.endsWith('/me/habits'))body={month:today.slice(0,7),today,canEdit:true,habits:[],entries:[],days:[],summary:{completed:0,goal:0,progress:0}};
  if(path.endsWith('/me/workouts')){
    const from=url.searchParams.get('from')??today;
    body={from,through:add(from,6),plan:published?{id:'fixture-ai-plan',title:'Your reviewed routine',version:2,source:'ai'}:null,workouts:published?dates.filter(d=>d>=from&&d<=add(from,6)).map((date,i)=>({id:`fixture-workout-${i}`,date,title:'Full-body foundation',exerciseCount:3,status:'not_started'})):[]};
  }
  if(path.endsWith('/me/ai-planning')&&request.method==='POST'){
    requested++;const input=JSON.parse(request.postData);assert.deepEqual(Object.keys(input),['requestId']);
    latest={id:'fixture-run',requestId:input.requestId,status:'queued',stage:'queued',message:'Your planning request is queued.',startDate:dates[0],through:dates.at(-1),routineReview:null};body=latest;
  }
  if(path.endsWith('/me/ai-planning/status')){
    statusReads++;
    if(latest){
      latest={...latest,status:publishAllowed?'published':'running',stage:publishAllowed?'published':'plan_review',message:publishAllowed?'Your AI workout plan passed the application checks and AI review and is now available.':'Reviewing the workout draft.',routineReview:{summary:'Build on your walking routine with short, consistent strength sessions.',notes:['Use your saved training days and equipment.','Keep the sessions within your 30-minute availability.']},...(publishAllowed?{planId:'fixture-ai-plan',version:2}:{} )};published=publishAllowed;
    }
    body={configured:true,entitled:true,profileReady:true,eligibleExerciseCount:12,dailyLimit:2,remainingToday:2-requested,latest};
  }
  browser.call('Fetch.fulfillRequest',{requestId,responseCode:200,responseHeaders:[{name:'Content-Type',value:'application/json'},{name:'Access-Control-Allow-Origin',value:'http://localhost:8080'},{name:'Access-Control-Allow-Headers',value:'content-type,authorization'},{name:'Access-Control-Allow-Methods',value:'GET,POST,PUT,OPTIONS'}],body:Buffer.from(JSON.stringify(body)).toString('base64')}).catch(e=>errors.push(e));
});
async function hasText(value){return browser.evaluate(`document.body.innerText.includes(${JSON.stringify(value)}) || Array.from(document.querySelectorAll('[aria-label]')).some(e=>e.getAttribute('aria-label').includes(${JSON.stringify(value)}))`);}
async function waitFor(check,label){for(let i=0;i<80;i++){if(await check())return;await pause(200);}throw new Error(`Timed out: ${label}`);}
async function wheel(deltaY){await browser.call('Input.dispatchMouseEvent',{type:'mouseWheel',x:300,y:550,deltaX:0,deltaY});await pause(350);}
async function click(label){const found=await browser.evaluate(`(()=>{const e=Array.from(document.querySelectorAll('[role=button]')).find(e=>(e.innerText||e.getAttribute('aria-label')||'').trim()===${JSON.stringify(label)});if(!e)return false;e.click();return true;})()`);if(!found)throw new Error(`Button missing: ${label}`);await pause(250);}
async function seek(label){for(let i=0;i<25;i++){if(await hasText(label))return;await wheel(300);}throw new Error(`Not visible: ${label}`);}
async function fill(label,value){for(let i=0;i<12;i++){const p=await browser.evaluate(`(()=>{const e=document.querySelector(${JSON.stringify(`input[aria-label="${label}"]`)});if(!e)return null;const r=e.getBoundingClientRect();return{x:r.x+r.width/2,y:r.y+r.height/2}})()`);if(p&&p.y>30&&p.y<780){for(const type of ['mousePressed','mouseReleased'])await browser.call('Input.dispatchMouseEvent',{type,...p,button:'left',clickCount:1});await browser.call('Input.insertText',{text:value});return;}await wheel(180);}throw new Error(`Input missing: ${label}`);}
async function capture(name){await browser.call('Input.dispatchMouseEvent',{type:'mouseMoved',x:2,y:2});await pause(650);await browser.screenshot(`docs/previews/${name}.png`);}
try{
  await browser.call('Fetch.enable',{patterns:[{urlPattern:'http://localhost:3001/*'}]});await browser.call('Page.navigate',{url:'http://localhost:8080'});await pause(2500);await browser.evaluate('localStorage.clear()');await browser.call('Page.reload',{ignoreCache:true});await pause(2500);await browser.evaluate('document.querySelector("flt-semantics-placeholder")?.click()');
  await waitFor(async()=>{await browser.evaluate('document.querySelector("flt-semantics-placeholder")?.click()');return hasText('Welcome back.');},'login');await fill('Email address','preview@example.test');await fill('Password','planning-preview-password');await click('Sign in');await waitFor(()=>hasText('Hello, Alex.'),'Today');
  await browser.evaluate('document.querySelector("[role=tab][aria-label=Workouts]")?.click()');await waitFor(()=>hasText('Plan with AI'),'Workouts');await click('Plan with AI');await waitFor(()=>hasText('A routine built'),'planner');await capture('ai-planning-intro');
  await seek('Generate my workout plan');assert.equal(requested,0);await click('Generate my workout plan');await waitFor(()=>hasText('Reviewing the workout draft'),'review stage');await wheel(400);await capture('ai-planning-review');assert.equal(requested,1);
  publishAllowed=true;await waitFor(()=>hasText('View published workouts'),'published');await seek('View published workouts');await capture('ai-planning-published');await click('View published workouts');await waitFor(()=>hasText('Your reviewed routine'),'published workout list');await capture('ai-planning-workouts');
  assert.equal(requested,1);assert.ok(statusReads>=3);assert.equal(errors.length,0);console.log('AI planning visual QA passed: request-only submission, polled review, routine summary, published navigation and AI-labelled workout version. All provider/API responses are fixtures; no AI service was called.');
}finally{
  try{await browser.call('Fetch.disable');await browser.evaluate('localStorage.clear()');}catch{/* preserve original error */}
  browser.close();
}
