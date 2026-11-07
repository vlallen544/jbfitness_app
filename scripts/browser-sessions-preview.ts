import assert from 'node:assert/strict';
import {dashboardFixture} from '../apps/api/test/support/staff-dashboard';
import {browserSession} from './browser-session.mjs';

// Actual local dashboard/API/database; policy values exist only in an owned QA schema.
async function main(){
  const fixture=await dashboardFixture();let browser:any;
  try{browser=await browserSession();}catch(e){await fixture.cleanup();throw e;}
  const pause=(ms:number)=>new Promise(r=>setTimeout(r,ms));
  const contains=(value:string)=>browser.evaluate(`document.body.innerText.includes(${JSON.stringify(value)})`);
  async function waitFor(check:()=>Promise<any>,label:string){for(let i=0;i<100;i++){if(await check())return;await pause(150);}throw new Error('Timed out: '+label);}
  async function click(label:string){assert.ok(await browser.evaluate(`(()=>{const e=Array.from(document.querySelectorAll('button')).find(e=>e.textContent.trim()===${JSON.stringify(label)});if(!e||e.disabled)return false;e.click();return true})()`),'Button missing or disabled: '+label);await pause(150);}
  async function fill(selector:string,value:string){const p=await browser.evaluate(`(()=>{const e=document.querySelector(${JSON.stringify(selector)});if(!e)return null;e.scrollIntoView({block:'center'});const r=e.getBoundingClientRect();return{x:r.x+r.width/2,y:r.y+r.height/2}})()`);assert.ok(p,'Input missing: '+selector);for(const type of ['mousePressed','mouseReleased'])await browser.call('Input.dispatchMouseEvent',{type,...p,button:'left',clickCount:1});await browser.call('Input.dispatchKeyEvent',{type:'keyDown',key:'a',code:'KeyA',windowsVirtualKeyCode:65,modifiers:2,commands:['selectAll']});await browser.call('Input.dispatchKeyEvent',{type:'keyUp',key:'a',code:'KeyA',windowsVirtualKeyCode:65,modifiers:0});await browser.call('Input.insertText',{text:value});}
  async function login(user:any){await waitFor(()=>contains('Sign in to operations'),'sign-in');await fill('input[type=email]',user.email);await fill('input[type=password]',user.password);await click('Sign in to operations');await waitFor(()=>contains('The right attention.'),'inbox');}
  async function navigate(path:string){await browser.call('Page.navigate',{url:fixture.origin+path});}
  async function capture(name:string){await browser.call('Input.dispatchMouseEvent',{type:'mouseMoved',x:2,y:2});await pause(300);await browser.screenshot(`docs/previews/${name}.png`);}
  try{
    await browser.call('Emulation.setDeviceMetricsOverride',{width:1440,height:1000,deviceScaleFactor:1,mobile:false});
    await navigate('/');await login(fixture.admin);await navigate('/sessions');await waitFor(()=>contains('Booking rules'),'owner calendar');
    assert.ok(await contains('Customer booking is not enabled'));assert.ok(await contains('In-app video is not connected.'));
    // Set each controlled number input with real keyboard events, indexed through its label.
    for(const [i,value]of ['30','0','14','12'].entries())await fill(`.form-grid label:nth-child(${i+1}) input`,value);
    await browser.evaluate(`document.querySelectorAll('select').forEach(e=>{e.value='true';e.dispatchEvent(new Event('change',{bubbles:true}));});document.querySelector('input[type=checkbox]').click();`);
    await click('Save confirmed rules');await waitFor(()=>contains('Booking rules confirmed.'),'saved fixture rules');
    await browser.evaluate('window.scrollTo(0,0)');await capture('sessions-owner-rules');
    const saved=(await fixture.db.pool.query('SELECT policy,revision FROM session_policy')).rows[0];assert.equal(saved.revision,1);assert.equal(saved.policy.durationMinutes,30);
    await navigate('/');await waitFor(()=>contains('The right attention.'),'owner inbox');await click('Sign out');await login(fixture.trainer);await navigate('/sessions');await waitFor(()=>contains('Publish availability'),'trainer calendar');
    const start=Math.ceil((Date.now()+86400000)/300000)*300000,local=new Date(start+330*60000).toISOString().slice(0,16);
    await browser.evaluate(`(()=>{const e=document.querySelector('input[type=datetime-local]');Object.getOwnPropertyDescriptor(HTMLInputElement.prototype,'value').set.call(e,${JSON.stringify(local)});e.dispatchEvent(new Event('input',{bubbles:true}));e.dispatchEvent(new Event('change',{bubbles:true}));})()`);
    await click('Publish availability');await waitFor(()=>contains('Availability saved.'),'published availability');
    const rows=(await fixture.db.pool.query('SELECT * FROM coaching_slots')).rows;assert.equal(rows.length,1);assert.equal(rows[0].starts_at.getTime(),start);
    await browser.evaluate('window.scrollTo(0,0)');await capture('sessions-trainer-calendar');
    await browser.call('Emulation.setDeviceMetricsOverride',{width:390,height:844,deviceScaleFactor:1,mobile:true});await browser.evaluate('window.scrollTo(0,0)');await capture('sessions-mobile-calendar');assert.ok(await browser.evaluate('document.documentElement.scrollWidth<=innerWidth+1'));
    await click('Manage time');await click('Withdraw availability');await waitFor(()=>contains('Availability withdrawn.'),'withdrawn availability');
    assert.equal((await fixture.db.pool.query('SELECT status FROM coaching_slots')).rows[0].status,'withdrawn');
    console.log('Session browser QA passed: real owner confirmation, trainer availability, IST conversion, mobile layout and withdrawal. Isolated technical rules only; video and customer booking remain disconnected.');
  }finally{browser.close();await fixture.cleanup();}
}
main().catch(e=>{console.error(e);process.exitCode=1;});
