import fs from 'node:fs';import assert from 'node:assert/strict';
import {GHub,chooseKeyboard,renderPlan,animationPayload,updateOwnedViewer}from'../scripts/keyboard.mjs';
const h=new GHub();let d,owned=false;const wait=ms=>new Promise(r=>setTimeout(r,ms));
try{await h.connect();d=chooseKeyboard((await h.call('GET','/devices/list')).deviceInfos);assert.ok(d);
 const base=await h.call('GET',`/lighting/${d.id}/state`),pid=(await h.call('GET','/profile/active')).id,saved=await h.call('GET','/profile',{id:pid});
 const results=[];await h.call('SET',`/lighting/${d.id}/mode/wake`,{});
 for(let press=0;press<5;press++){
 const started=Date.now()/1000;let max=0,brightF10=0;
 for(let i=0;i<17;i++){
 const now=Date.now()/1000,s={generatedAt:now,quotaAt:now,windows:[{bucket:'codex',remaining:55}],tasks:[],events:[],ambientEvents:[{id:4,at:started}]};
 const p=renderPlan(base,s,now,{ambientEnabled:true,ambientPreset:'splash',ambientPalette:'neon',ambientProfile:'focus',ambientPeriod:2.4});
 const payload=animationPayload(d.id,p.frames.length===1?[p.frames[0],p.frames[0]]:p.frames,64,1);
 if(!owned){await h.call('SET','/lighting/viewer',payload);owned=true;}else await updateOwnedViewer(h,d.id,payload);
 await wait(65);const state=await h.call('GET',`/lighting/${d.id}/state`),map=state.infoMap.PERKEY_KEYBOARD.perKeyMap.colorCodeMap;
 for(let k=4;k<=29;k++){const c=map[k]?.rgba;if(c)max=Math.max(max,c.red*255,c.green*255,c.blue*255);}
 const c=map[67].rgba;if(Math.max(c.red,c.green,c.blue)>.1)brightF10++;
 }
 assert.ok(max>75,`press ${press} must visibly respond: ${max}`);assert.equal(brightF10,0);results.push({press,max,brightF10});
 }
 assert.deepEqual(await h.call('GET','/profile',{id:pid}),saved);fs.writeFileSync('build/reactive-stream-validation.json',JSON.stringify(results,null,2));console.log(results);
}finally{if(owned)await h.call('REMOVE','/lighting/viewer',{devices:[d.id]});h.close();}
