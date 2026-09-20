// Run only with the regular worker stopped. Owns and releases temporary viewer.
import assert from 'node:assert/strict';import fs from 'node:fs';
import {GHub,chooseKeyboard,renderPlan,animationPayload,viewerPayload} from '../scripts/keyboard.mjs';
const h=new GHub();let d,owned=false;const result=[];
const rgb=(f,slot,id)=>f.infoMap[slot].perKeyMap.colorCodeMap[id].rgba;
const same=(a,b)=>['red','green','blue'].every(k=>Math.abs(Math.round(a[k]*255)-Math.round(b[k]*255))<=2);
try{
 await h.connect();d=chooseKeyboard((await h.call('GET','/devices/list')).deviceInfos);assert.ok(d,'G913 connected');
 let busy=false;try{await h.call('GET','/lighting/viewer/state',{devices:[d.id]});busy=true;}catch(e){if(e.code!=='INVALID_ARG')throw e;}assert.equal(busy,false,'single writer');
 const pid=(await h.call('GET','/profile/active')).id,saved=await h.call('GET','/profile',{id:pid});
 const base=await h.call('GET',`/lighting/${d.id}/state`);await h.call('SET',`/lighting/${d.id}/mode/wake`,{});
 for(const preset of ['g-jewels','g-ladder','g-lane']){
 const now=Date.now()/1000,snapshot={quotaAt:now,generatedAt:now,windows:[{bucket:'codex',remaining:55}],tasks:[],events:[],ambientEvents:preset==='g-lane'?[{id:'G3',at:now}]:[]};
 const p=renderPlan(base,snapshot,now,{ambientEnabled:true,ambientPreset:preset,ambientPeriod:3});
 const started=Date.now();await h.call('SET','/lighting/viewer',p.frames.length>1?animationPayload(d.id,p.frames,p.speed,p.length):viewerPayload(d.id,p.frames[0]));owned=true;
 const sendMs=Date.now()-started,seen=new Set();let good=false;
 for(let i=0;i<12;i++){await new Promise(r=>setTimeout(r,100));const f=await h.call('GET',`/lighting/${d.id}/state`);
 if(same(rgb(f,'PERKEY_KEYBOARD',58),rgb(p.frames[0],'PERKEY_KEYBOARD',58)))good=true;
 if(i>2){assert.ok(same(rgb(f,'PERKEY_KEYBOARD',58),rgb(p.frames[0],'PERKEY_KEYBOARD',58)),'quota preserved');seen.add(JSON.stringify([rgb(f,'PERKEY_GKEY',3),rgb(f,'PERKEY_KEYBOARD',4)]));}
 if(preset==='g-jewels'&&i>2)for(let g=1;g<=5;g++)assert.ok(same(rgb(f,'PERKEY_GKEY',g),rgb(p.frames[0],'PERKEY_GKEY',g)),'G slot RGB exact');
 }
 assert.ok(good,'effect active');if(preset!=='g-jewels')assert.ok(seen.size>2,'moving G/main samples');
 await h.call('REMOVE','/lighting/viewer',{devices:[d.id]});owned=false;
 result.push({preset,sendMs,distinctSamples:seen.size});
 }
 assert.deepEqual(await h.call('GET','/profile',{id:pid}),saved,'saved profile unchanged');
 fs.writeFileSync('build/ambient-hardware-validation.json',JSON.stringify({at:new Date().toISOString(),model:d.deviceModel,result,profileUnchanged:true},null,2));console.log(JSON.stringify(result));
}finally{if(owned)await h.call('REMOVE','/lighting/viewer',{devices:[d.id]});h.close();}
