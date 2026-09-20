// Explicit hardware verification: stop the normal lighting worker first.
import assert from 'node:assert/strict';
import {GHub,chooseKeyboard,renderPlan,animationPayload,NUMPAD_KEYS,QUOTA_KEYS} from '../scripts/keyboard.mjs';
const h=new GHub();await h.connect();let d,owned=false;
const key=(f,id)=>f.infoMap.PERKEY_KEYBOARD.perKeyMap.colorCodeMap[id].rgba;
const same=(a,b)=>['red','green','blue'].every(k=>Math.abs(Math.round(a[k]*255)-Math.round(b[k]*255))<=1);
try {
 d=chooseKeyboard((await h.call('GET','/devices/list')).deviceInfos);assert.ok(d);
 let busy=false;try{await h.call('GET','/lighting/viewer/state',{devices:[d.id]});busy=true;}catch(e){if(e.code!=='INVALID_ARG')throw e;}assert.equal(busy,false);
 await h.call('SET',`/lighting/${d.id}/mode/wake`,{});
 const base=await h.call('GET',`/lighting/${d.id}/state`),pid=(await h.call('GET','/profile/active')).id;
 const saved=await h.call('GET','/profile',{id:pid});
 for(const count of [1,2,3,4])for(const style of ['classic','wave','pulse','ripple','comet']){
  const now=Date.now()/1000,s={quotaAt:now,generatedAt:now,windows:[{bucket:'codex',remaining:55}],tasks:Array.from({length:count},()=>({status:'active'})),events:[]};
  const p=renderPlan(base,s,now,{cycleSeconds:3,[`mode${count}`]:style});
  await h.call('SET','/lighting/viewer',animationPayload(d.id,p.frames,p.speed,p.length));owned=true;
  let ready=false;
  for(let n=0;n<20;n++) { await new Promise(r=>setTimeout(r,100));const f=await h.call('GET',`/lighting/${d.id}/state`);if(QUOTA_KEYS.every(id=>same(key(f,id),key(p.frames[0],id)))){ready=true;break;} }
  if(!ready){const f=await h.call('GET',`/lighting/${d.id}/state`);console.log(JSON.stringify({expected:key(p.frames[0],58),actual:key(f,58),mode:await h.call('GET',`/lighting/${d.id}/mode`)}));}
  assert.ok(ready,`${count} ${style}: effect did not become active`);
  const seen=new Set();
  for(let i=0;i<6;i++){
   await new Promise(r=>setTimeout(r,100));const f=await h.call('GET',`/lighting/${d.id}/state`);
   for(const id of QUOTA_KEYS)assert.ok(same(key(f,id),key(p.frames[0],id)));
   for(const id of [4,68,69])assert.ok(same(key(f,id),key(base,id)));
   seen.add(JSON.stringify(NUMPAD_KEYS.map(id=>key(f,id))));
  }
  assert.ok(seen.size>2,`${count} ${style} static`);
  await h.call('REMOVE','/lighting/viewer',{devices:[d.id]});owned=false;
  console.log(`${count} ${style}: ${seen.size} moving samples; quota and other keys stable`);
 }
 assert.deepEqual(await h.call('GET','/profile',{id:pid}),saved);
 console.log('PASS: all 20 styles, protected regions and saved profile integrity');
}finally{if(owned)await h.call('REMOVE','/lighting/viewer',{devices:[d.id]});h.close();}
