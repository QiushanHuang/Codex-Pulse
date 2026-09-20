// Explicit G913 hardware check; run with the normal lighting worker stopped.
import assert from 'node:assert/strict';
import {GHub,chooseKeyboard,renderPlan,animationPayload}from'../scripts/keyboard.mjs';
const h=new GHub();await h.connect();let owned=false,d;
try{
 d=chooseKeyboard((await h.call('GET','/devices/list')).deviceInfos);assert.ok(d);
 let busy=false;try{await h.call('GET','/lighting/viewer/state',{devices:[d.id]});busy=true;}catch(e){if(e.code!=='INVALID_ARG')throw e;}
 assert.equal(busy,false,'Stop the lighting worker first');
 const base=await h.call('GET',`/lighting/${d.id}/state`),profile=(await h.call('GET','/profile/active')).id;
 const before=await h.call('GET','/profile',{id:profile});
 for(const count of[2,3]){
  const now=Date.now()/1000,s={quotaAt:now,generatedAt:now,windows:[{bucket:'codex',remaining:55}],tasks:Array.from({length:count},()=>({status:'active'})),events:[]};
  const p=renderPlan(base,s,now,{cycleSeconds:3,mode1:"classic",mode2:"classic",mode3:"classic",mode4:"classic"});
  await h.call('SET','/lighting/viewer',animationPayload(d.id,p.frames,p.speed,p.length));owned=true;
  const slash=[],edges=[],previous={},start=Date.now();
  while(Date.now()-start<(count===3?6500:4500)){
   await new Promise(r=>setTimeout(r,90));const f=await h.call('GET',`/lighting/${d.id}/state`),keys=f.infoMap.PERKEY_KEYBOARD.perKeyMap.colorCodeMap;
   slash.push(keys['84'].rgba.blue);
   if(count===3)for(const id of[91,90,89]){
    const high=keys[String(id)].rgba.blue>.8;
    if(high&&!previous[id])edges.push({id,seconds:(Date.now()-start)/1000});previous[id]=high;
   }
  }
  assert.ok(Math.max(...slash)>.8&&Math.min(...slash)<.2,'Slash did not participate in the wave');
  if(count===3){
   const afterAnchor=edges.filter(e=>e.seconds>.35);
   assert.deepEqual(afterAnchor.slice(0,3).map(e=>e.id),[91,90,89]);
   const gaps=afterAnchor.slice(1,3).map((e,i)=>e.seconds-afterAnchor[i].seconds);
   assert.ok(gaps.length>=2&&Math.max(...gaps)-Math.min(...gaps)<.35,'Column spacing is uneven');
   console.log(JSON.stringify({tasks:count,order:edges.slice(0,5),gaps}));
  }else console.log(JSON.stringify({tasks:count,slashMin:Math.min(...slash),slashMax:Math.max(...slash)}));
  await h.call('REMOVE','/lighting/viewer',{devices:[d.id]});owned=false;
 }
 const now=Date.now()/1000,s={quotaAt:now,generatedAt:now,windows:[{bucket:'codex',remaining:55}],tasks:[],events:[{kind:'completed',at:now}]};
 const p=renderPlan(base,s,now);
 await h.call('SET','/lighting/viewer',animationPayload(d.id,p.frames,p.speed,p.length));owned=true;
 let peaks=0,high=false;const start=Date.now();
 while(Date.now()-start<4400){await new Promise(r=>setTimeout(r,60));const f=await h.call('GET',`/lighting/${d.id}/state`);const next=f.infoMap.PERKEY_KEYBOARD.perKeyMap.colorCodeMap['98'].rgba.green>.8;if(next&&!high)peaks++;high=next;}
 assert.ok(peaks>=3,'Completion did not repeat its upward wave three times');console.log(JSON.stringify({completionWavePeaks:peaks}));
 await h.call('REMOVE','/lighting/viewer',{devices:[d.id]});owned=false;
 assert.deepEqual(await h.call('GET','/profile',{id:profile}),before);
 console.log('PASS: slash in both modes, equally spaced right-center-left waves, repeated completion and original profile integrity');
}finally{if(owned)await h.call('REMOVE','/lighting/viewer',{devices:[d.id]});h.close();}
