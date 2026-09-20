// Explicit keyboard test: stop Codex Pulse lighting before running.
import assert from 'node:assert/strict';
import {GHub,chooseKeyboard,runningGroups,frameFor,renderPlan,viewerPayload,animationPayload,colorsEqual}from'../scripts/keyboard.mjs';
const h=new GHub();await h.connect();let d,owned=false;
const color=(f,id)=>f.infoMap.PERKEY_KEYBOARD.perKeyMap.colorCodeMap[String(id)].rgba;
try{
 d=chooseKeyboard((await h.call('GET','/devices/list')).deviceInfos);assert.ok(d);
 let busy=false;try{await h.call('GET','/lighting/viewer/state',{devices:[d.id]});busy=true;}catch(e){if(e.code!=='INVALID_ARG')throw e;}assert.equal(busy,false);
 const base=await h.call('GET',`/lighting/${d.id}/state`),pid=(await h.call('GET','/profile/active')).id;
 const saved=await h.call('GET','/profile',{id:pid});
 for(const count of[3,4]){
  const now=Date.now()/1000,s={quotaAt:now,generatedAt:now,windows:[{bucket:'codex',remaining:55}],tasks:Array.from({length:count},()=>({status:'active'})),events:[]};
  const anchor=frameFor(base,s,now,0,{mode3:"classic",mode4:"classic"});
  await h.call('SET','/lighting/viewer',viewerPayload(d.id,anchor));owned=true;
  let matched=false;for(let i=0;i<12;i++){await new Promise(r=>setTimeout(r,80));const f=await h.call('GET',`/lighting/${d.id}/state`);if(colorsEqual(anchor,f)){matched=true;break;}}
  assert.ok(matched,`Incorrect ${count}-task starting positions`);
  await h.call('REMOVE','/lighting/viewer',{devices:[d.id]});owned=false;
  const p=renderPlan(base,s,now,{cycleSeconds:3,mode1:"classic",mode2:"classic",mode3:"classic",mode4:"classic"});
  await h.call('SET','/lighting/viewer',animationPayload(d.id,p.frames,p.speed,p.length));owned=true;
  let samples=0;const seen=new Set(),groups=runningGroups(count);
  for(let n=0;n<30;n++){
   await new Promise(r=>setTimeout(r,100));const f=await h.call('GET',`/lighting/${d.id}/state`);
   if(count===3){
    const peaks=groups.map(g=>g.map(id=>color(f,id).blue).reduce((best,v,i,a)=>v>a[best]?i:best,0));
    assert.equal((peaks[1]-peaks[0]+4)%4,1);assert.equal((peaks[2]-peaks[1]+4)%4,1);
    seen.add(peaks.join(','));
   }else{
    const indices=groups.map(group=>{
     let best=0,error=Infinity;
     p.frames.forEach((expected,index)=>{let e=0;for(const id of group)for(const c of['red','green','blue'])e+=(color(f,id)[c]-color(expected,id)[c])**2;if(e<error){error=e;best=index;}});
     return best;
    });
    for(const i of indices){const delta=Math.abs(i-indices[0]);assert.ok(Math.min(delta,64-delta)<=2,'Rows lost common phase');}
    seen.add(indices[0]);
   }
   samples++;
  }
  assert.ok(seen.size>=3);
  console.log(JSON.stringify({tasks:count,anchorVerified:true,coherentSamples:samples,distinctPositions:seen.size}));
  await h.call('REMOVE','/lighting/viewer',{devices:[d.id]});owned=false;
 }
 assert.deepEqual(await h.call('GET','/profile',{id:pid}),saved);
 console.log('PASS: 1/5/9 anchor, one-key column spacing, Num/3 simultaneous start, four-row fixed diagonal and original profile');
}finally{if(owned)await h.call('REMOVE','/lighting/viewer',{devices:[d.id]});h.close();}
