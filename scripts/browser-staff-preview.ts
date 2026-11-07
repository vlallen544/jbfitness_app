import assert from 'node:assert/strict';
import {dashboardFixture} from '../apps/api/test/support/staff-dashboard';
import {browserSession} from './browser-session.mjs';

// Actual local Next/Nest/Postgres flow, with dedicated accounts in a temporary schema.
// The exercise and AI review inputs are technical fixtures, not client coaching content.
async function main(){
  const fixture=await dashboardFixture();let browser:any;
  try{browser=await browserSession();}catch(e){await fixture.cleanup();throw e;}
  const pause=(ms:number)=>new Promise(r=>setTimeout(r,ms));
  async function text(value:string){return browser.evaluate(`document.body.innerText.includes(${JSON.stringify(value)})`);}
  async function waitFor(check:()=>Promise<any>,label:string){for(let i=0;i<100;i++){if(await check())return;await pause(150);}throw new Error(`Timed out: ${label}`);}
  async function click(label:string){const ok=await browser.evaluate(`(()=>{const e=Array.from(document.querySelectorAll('button')).find(e=>e.textContent.trim()===${JSON.stringify(label)});if(!e)return false;e.click();return true})()`);assert.ok(ok,`Button missing: ${label}`);await pause(200);}
  async function fill(selector:string,value:string){const p=await browser.evaluate(`(()=>{const e=document.querySelector(${JSON.stringify(selector)});if(!e)return null;e.scrollIntoView({block:'center'});const r=e.getBoundingClientRect();return{x:r.x+r.width/2,y:r.y+r.height/2}})()`);assert.ok(p,`Input missing: ${selector}`);for(const type of ['mousePressed','mouseReleased'])await browser.call('Input.dispatchMouseEvent',{type,...p,button:'left',clickCount:1});await browser.call('Input.dispatchKeyEvent',{type:'keyDown',key:'a',code:'KeyA',windowsVirtualKeyCode:65,modifiers:2,commands:['selectAll']});await browser.call('Input.dispatchKeyEvent',{type:'keyUp',key:'a',code:'KeyA',windowsVirtualKeyCode:65,modifiers:0});await browser.call('Input.insertText',{text:value});}
  async function capture(name:string){await browser.call('Input.dispatchMouseEvent',{type:'mouseMoved',x:2,y:2});await pause(300);await browser.screenshot(`docs/previews/${name}.png`);}
  async function rowAction(kind:string){const ok=await browser.evaluate(`(()=>{const row=Array.from(document.querySelectorAll('tbody tr')).find(e=>e.textContent.includes(${JSON.stringify(kind)}));const button=row?.querySelector('button');if(!button)return false;button.click();return true;})()`);assert.ok(ok,'Expected review row');}
  async function login(user:{email:string;password:string}){await waitFor(()=>text('Sign in to operations'),'staff sign-in');await fill('input[type=email]',user.email);await fill('input[type=password]',user.password);await click('Sign in to operations');await waitFor(()=>text('The right attention.'),'operations inbox');}
  try{
    await browser.call('Emulation.setDeviceMetricsOverride',{width:1440,height:1000,deviceScaleFactor:1,mobile:false});
    await browser.call('Page.navigate',{url:fixture.origin});await waitFor(()=>text('Sign in to operations'),'login');await capture('staff-login');
    await login(fixture.admin);await click('Customers');await waitFor(()=>text('Alex Morgan'),'customer directory');
    await browser.evaluate(`(()=>{const s=document.querySelector('select');s.value=${JSON.stringify(fixture.trainer.id)};s.dispatchEvent(new Event('change',{bubbles:true}));})()`);
    await waitFor(()=>text('Trainer assigned.'),'assignment save');await capture('staff-assignments');await click('Sign out');
    await login(fixture.trainer);await waitFor(()=>text('Workout planning'),'shared review inbox');await capture('staff-trainer-inbox');
    assert.equal(await browser.evaluate('document.cookie.includes("jb_staff_session")'),false);
    await rowAction('AI coaching');await waitFor(()=>text('Feedback for the customer'),'coaching detail');await fill('textarea','Use a manageable session this week and keep your saved training days.');await click('Resolve with feedback');await waitFor(()=>text('Feedback saved to the customer app.'),'saved coaching feedback');
    await rowAction('Workout planning');await waitFor(()=>text('Review and edit the workout'),'plan review');await fill('textarea','Your reviewed routine is ready. Start with the supplied session and record how it feels.');await browser.evaluate('document.querySelector(".plan-editor").scrollIntoView({block:"start"});window.scrollBy(0,-25)');await capture('staff-workout-review');
    await click('Publish reviewed workout');await waitFor(()=>text('Reviewed workout published.'),'publication');
    const response=await fetch(`${fixture.apiBase}/me/trainer-feedback`,{headers:{Authorization:`Bearer ${fixture.customer.token}`}}),feedback=await response.json();assert.equal(feedback.feedback.length,2);assert.ok(feedback.feedback.some((f:any)=>f.decision==='publish_plan'));
    const plans=(await fixture.db.pool.query('SELECT source FROM workout_plans WHERE customer_id=$1',[fixture.customer.id])).rows;assert.deepEqual(plans,[{source:'trainer'}]);
    await browser.evaluate('document.querySelector("input[type=checkbox]").click()');await pause(200);
    await browser.call('Emulation.setDeviceMetricsOverride',{width:390,height:844,deviceScaleFactor:1,mobile:true});await browser.evaluate('window.scrollTo(0,0)');await capture('staff-mobile-inbox');assert.ok(await browser.evaluate('document.documentElement.scrollWidth<=innerWidth+1'));
    await browser.evaluate(`(()=>{const original=window.fetch;window.fetch=async(...args)=>{const response=await original(...args);if(args[1]?.method==='GET'&&String(args[0]).startsWith('/api/operations'))await new Promise(r=>setTimeout(r,900));return response;};})()`);
    await click('Refresh');await pause(150);await click('Sign out');await waitFor(()=>text('Sign in to operations'),'signed out');await pause(1200);assert.equal(await text('Sign in to operations'),true);assert.equal(await text('The right attention.'),false);
    console.log('Staff browser QA passed: actual cookie sign-in, owner assignment, trainer review, feedback delivery, one reviewed-plan publication and no stale refresh restoring a signed-out dashboard. Isolated technical fixtures only; no AI or messages to external people.');
  }finally{browser.close();await fixture.cleanup();}
}
main().catch(e=>{console.error(e);process.exitCode=1;});
