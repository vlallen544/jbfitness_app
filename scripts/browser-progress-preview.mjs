import assert from 'node:assert/strict';
import { mkdtemp, unlink, rmdir } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import sharp from 'sharp';
import { browserSession } from './browser-session.mjs';

// All records are QA fixtures. Solid-colour images test private media, not body transformations.
const folder=await mkdtemp(join(tmpdir(),'jb-progress-qa-'));
const photoPath=join(folder,'technical-progress.jpg');
const image=await sharp({create:{width:400,height:600,channels:3,background:'#376e59'}}).jpeg().toBuffer();
await sharp(image).toFile(photoPath);
const browser=await browserSession();
const pause=ms=>new Promise(resolve=>setTimeout(resolve,ms));
const today=new Date().toLocaleDateString('en-CA',{timeZone:'Asia/Kolkata'});
const oldDate=new Date(Date.now()-7*86400000).toLocaleDateString('en-CA',{timeZone:'Asia/Kolkata'});
const measurements=weight=>({weight,waist:null,chest:null,arms:null,thighs:null});
const records=[{id:'recent',date:today,measurements:measurements(79.2),revision:1,photos:[]}, {id:'older',date:oldDate,measurements:measurements(80.5),revision:1,photos:[{id:'front-old',angle:'front'}]}];
let uploads=0, photoReads=0, uploadChosen=false, edits=0;
const errors=[];
browser.onEvent(({method,params})=>{
  if(method==='Page.fileChooserOpened') {browser.call('DOM.setFileInputFiles',{backendNodeId:params.backendNodeId,files:[photoPath]}).then(()=>uploadChosen=true).catch(e=>errors.push(e));return;}
  if(method!=='Fetch.requestPaused')return;
  const {requestId,request}=params,path=new URL(request.url).pathname;
  let body={token:'progress-fixture',user:{id:'preview-user',displayName:'Alex Preview',email:'preview@example.test',role:'customer'},profile:{workoutDays:[0,2,4],sessionMinutes:40}};
  let bytes, contentType='application/json';
  if(path.endsWith('/me/habits'))body={month:today.slice(0,7),today,canEdit:true,habits:[],entries:[],days:[],summary:{completed:0,goal:0,progress:0}};
  if(path.endsWith('/me/progress'))body={today,canEdit:true,timezone:'Asia/Kolkata',records};
  if(path.endsWith('/me/progress/recent')&&request.method==='PUT'){records[0].measurements=JSON.parse(request.postData).measurements;records[0].revision++;edits++;body={revision:records[0].revision};}
  if(path.endsWith('/me/progress/recent/photos')&&request.method==='POST'){uploads++;records[0].photos.push({id:'front-recent',angle:'front'});body={id:'front-recent'};}
  if(path.includes('/me/progress/photos/')&&request.method==='GET'){
    assert.equal(request.headers.Authorization??request.headers.authorization,'Bearer progress-fixture');photoReads++;bytes=image;contentType='image/jpeg';
  }
  browser.call('Fetch.fulfillRequest',{requestId,responseCode:200,responseHeaders:[{name:'Content-Type',value:contentType},{name:'Cache-Control',value:'private, no-store'},{name:'Access-Control-Allow-Origin',value:'http://localhost:8080'},{name:'Access-Control-Allow-Headers',value:'content-type,authorization'},{name:'Access-Control-Allow-Methods',value:'GET,POST,PUT,DELETE,OPTIONS'}],body:(bytes??Buffer.from(JSON.stringify(body))).toString('base64')}).catch(e=>errors.push(e));
});
async function hasText(value){return browser.evaluate(`document.body.innerText.includes(${JSON.stringify(value)}) || Array.from(document.querySelectorAll('[aria-label]')).some(e=>e.getAttribute('aria-label').includes(${JSON.stringify(value)}))`);}
async function waitFor(check,label){for(let i=0;i<80;i++){if(await check())return;await pause(200);}throw new Error(`Timed out: ${label}`);}
async function wheel(deltaY){await browser.call('Input.dispatchMouseEvent',{type:'mouseWheel',x:300,y:550,deltaX:0,deltaY});await pause(350);}
async function click(label,partial=false){const found=await browser.evaluate(`(()=>{const e=Array.from(document.querySelectorAll('[role=button]')).find(e=>{const text=(e.innerText||e.getAttribute('aria-label')||'').trim();return ${partial?'text.includes':'text==='}(${JSON.stringify(label)})});if(!e)return false;e.click();return true;})()`);if(!found)throw new Error(`Button missing: ${label}`);await pause(250);}
async function fill(label,value){
  for(let i=0;i<24;i++){
    const p=await browser.evaluate(`(()=>{const e=document.querySelector(${JSON.stringify(`input[aria-label="${label}"],textarea[aria-label="${label}"]`)});if(!e)return null;const r=e.getBoundingClientRect();return{x:r.x+r.width/2,y:r.y+r.height/2}})()`);
    if(p&&p.y>55&&p.y<780){for(const type of ['mousePressed','mouseReleased'])await browser.call('Input.dispatchMouseEvent',{type,...p,button:'left',clickCount:1});await browser.call('Input.dispatchKeyEvent',{type:'keyDown',key:'a',code:'KeyA',windowsVirtualKeyCode:65,modifiers:2,commands:['selectAll']});await browser.call('Input.dispatchKeyEvent',{type:'keyUp',key:'a',code:'KeyA',windowsVirtualKeyCode:65,modifiers:0});await browser.call('Input.insertText',{text:value});return;}
    await wheel(p&&p.y<55?-250:250);
  }throw new Error(`Input not visible: ${label}`);
}
async function seek(label){for(let i=0;i<24;i++){if(await hasText(label))return;await wheel(350);}throw new Error(`Not visible: ${label}`);}
async function capture(name){await browser.call('Input.dispatchMouseEvent',{type:'mouseMoved',x:2,y:2});await pause(650);await browser.screenshot(`docs/previews/${name}.png`);}
try{
  await browser.call('DOM.enable');await browser.call('Page.setInterceptFileChooserDialog',{enabled:true});
  await browser.call('Fetch.enable',{patterns:[{urlPattern:'http://localhost:3001/*'}]});
  await browser.call('Page.navigate',{url:'http://localhost:8080'});await pause(2500);await browser.evaluate('localStorage.clear()');await browser.call('Page.reload',{ignoreCache:true});await pause(2500);await browser.evaluate('document.querySelector("flt-semantics-placeholder")?.click()');
  await waitFor(()=>hasText('Welcome back.'),'login');await fill('Email address','preview@example.test');await fill('Password','progress-preview-password');await click('Sign in');await waitFor(()=>hasText('Hello, Alex.'),'Today');
  await seek('View body progress');await click('View body progress');await waitFor(()=>hasText('79.2 kg'),'progress chart');await capture('progress-chart');
  await seek('Weight (kg): 79.2');await click('Weight (kg): 79.2',true);await waitFor(()=>hasText('Save measurements'),'editor');
  await fill('Weight (kg)','78.6');await seek('Save measurements');await capture('progress-measurements');await click('Save measurements');await waitFor(()=>hasText('78.6 kg'),'saved value');assert.equal(edits,1);
  await seek('Weight (kg): 78.6');await click('Weight (kg): 78.6',true);await waitFor(()=>hasText('Save measurements'),'editor again');
  await seek('Choose progress photo');await click('Choose progress photo');await waitFor(async()=>uploadChosen,'file chooser');await seek('Save private photo');assert.equal(uploads,0);await click('Save private photo');await waitFor(()=>hasText('Delete front photo'),'saved private photo');assert.equal(uploads,1);assert.ok(photoReads>0);await wheel(350);await capture('progress-private-photo');
  assert.equal(errors.length,0);console.log('Progress visual QA passed: dated trend, measurement edit/save, actual file chooser, explicit private photo upload and authenticated image display. All values and colour images are technical fixtures.');
}finally{
  try{await browser.call('Page.setInterceptFileChooserDialog',{enabled:false});await browser.call('Fetch.disable');await browser.evaluate('localStorage.clear()');}catch{/* preserve original error */}
  browser.close();await unlink(photoPath);await rmdir(folder);
}
