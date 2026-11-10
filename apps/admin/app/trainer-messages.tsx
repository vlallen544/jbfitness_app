'use client';
import {useEffect,useRef,useState} from 'react';

type Message={id:string;sequence:string;senderId:string;text:string;createdAt:string};
type Thread={peer:{id:string;name:string};messages:Message[];canSend:boolean;nextBefore:string|null};
type Person={id:string;name:string};
class Failure extends Error{constructor(public status:number,message:string){super(message);}}
async function request(query:string,body?:unknown){
  const response=await fetch(`/api/operations${query}`,{method:body===undefined?'GET':'POST',credentials:'same-origin',cache:'no-store',headers:{'Content-Type':'application/json'},signal:AbortSignal.timeout(20000),...(body===undefined?{}:{body:JSON.stringify(body)})});
  const data=await response.json();if(!response.ok)throw new Failure(response.status,data.message??'Messages could not load.');return data;
}
export default function TrainerMessages({userId}:{userId:string}){
  const [people,setPeople]=useState<Person[]>([]),[thread,setThread]=useState<Thread|null>(null),[text,setText]=useState(''),[busy,setBusy]=useState(false),[error,setError]=useState(''),[pending,setPending]=useState<{action:string;id:string;text:string;requestId:string;shareWithTrainer:true}|null>(null);
  const generation=useRef(0);
  function report(e:unknown){setError(e instanceof Failure?e.message:'Messages could not be loaded. Please retry.');if(e instanceof Failure&&[401,403,404].includes(e.status)){setThread(null);setPeople([]);setText('');setPending(null);}}
  async function list(){const version=++generation.current;setBusy(true);setError('');try{const data=await request('?resource=messages');if(version===generation.current){setPeople(data.conversations);setThread(null);}}catch(e){if(version===generation.current)report(e);}finally{if(version===generation.current)setBusy(false);}}
  useEffect(()=>{void list();return()=>{generation.current++;};},[]);
  async function open(id:string,older=false){const version=++generation.current;setBusy(true);setError('');try{
    const data:Thread=await request(`?resource=conversation&id=${id}${older&&thread?.nextBefore?`&before=${thread.nextBefore}`:''}`);
    if(version!==generation.current)return;
    if(older)data.messages=[...data.messages,...(thread?.messages??[])];
    setThread(data);if(thread?.peer.id!==id){setText('');setPending(null);}
  }catch(e){if(version===generation.current)report(e);}finally{if(version===generation.current)setBusy(false);}}
  async function send(){if(!thread||busy||!text.trim()&&!pending)return;const version=++generation.current,body=pending??{action:'trainer-message',id:thread.peer.id,text:text.trim(),requestId:crypto.randomUUID(),shareWithTrainer:true as const};setPending(body);setBusy(true);setError('');let saved=false;
    try{await request('',body);if(version===generation.current){setPending(null);setText('');saved=true;}}
    catch(e){if(version===generation.current)report(e);}
    finally{if(version===generation.current)setBusy(false);}
    if(saved)await open(body.id);
  }
  return <section className="workspace-card trainer-messages"><div className="section-heading"><div><span className="eyebrow">PERSONAL SUPPORT</span><h2>{thread?thread.peer.name:'Trainer messages'}</h2></div><button className="secondary compact" disabled={busy} onClick={()=>thread?open(thread.peer.id):list()}>Refresh messages</button></div>
    <p className="muted">Customers start the conversation in the app. Replies are saved for them to read. Refresh to see new messages.</p>
    {error&&<p role="alert" className="error-message">{error}</p>}{busy&&<p role="status">Loading…</p>}
    {!thread&&people.length===0&&!busy&&!error&&<div className="empty-state"><h3>No conversations yet.</h3><p>Your assigned customers can contact you from Profile → Message your trainer.</p></div>}
    {!thread&&people.map(person=><button className="conversation-person secondary" key={person.id} disabled={busy} onClick={()=>open(person.id)}>{person.name}<span>Open conversation →</span></button>)}
    {thread&&<><button className="text-button" disabled={busy||pending!==null} onClick={list}>← All conversations</button>{thread.nextBefore&&<button className="secondary" disabled={busy} onClick={()=>open(thread.peer.id,true)}>Load older messages</button>}
      <div className="message-history" aria-label="Saved conversation">{thread.messages.map(message=><article className={`message-bubble ${message.senderId===userId?'sent':''}`} key={message.id}><strong>{message.senderId===userId?'You':thread.peer.name}</strong><p>{message.text}</p><time dateTime={message.createdAt}>{new Date(message.createdAt).toLocaleString('en-IN')}</time></article>)}</div>
      {thread.canSend?<form onSubmit={e=>{e.preventDefault();void send();}}><label>Your reply<textarea rows={3} maxLength={2000} value={text} disabled={busy||pending!==null} onChange={e=>setText(e.target.value)} required/></label><p className="small muted">Only this customer can read your reply. No AI reply is sent here.</p><button disabled={busy||!text.trim()&&!pending}>{pending?'Retry same message':'Send reply'}</button>{pending&&<p className="small muted">Delivery has not been confirmed. Retry uses the same message reference.</p>}</form>:<p className="notice">This conversation is read-only while the customer has no active membership.</p>}
    </>}
  </section>;
}
