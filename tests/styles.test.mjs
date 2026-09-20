import test from 'node:test';
import assert from 'node:assert/strict';
import {RUNNING_STYLES,runningStyleFor,normalizeSettings,frameFor,renderPlan,previewPacket}from'../scripts/keyboard.mjs';
const ids=[4,...Array.from({length:12},(_,i)=>58+i),...Array.from({length:17},(_,i)=>83+i)];
const base={infoMap:{PERKEY_KEYBOARD:{perKeyMap:{colorCodeMap:Object.fromEntries(ids.map(id=>[id,{rgba:{red:.4,green:.3,blue:.2,alpha:1}}]))}},PERKEY_BRANDING:{perKeyMap:{colorCodeMap:{1:{rgba:{red:1,green:1,blue:1,alpha:1}}}}}}};
const snapshot=count=>({quotaAt:100,generatedAt:100,windows:[{bucket:'codex',remaining:55}],tasks:Array.from({length:count},()=>({status:'active'})),events:[]});
const key=(f,id)=>f.infoMap.PERKEY_KEYBOARD.perKeyMap.colorCodeMap[id].rgba;
test('each task count has an independent saved style and expressive defaults',()=>{
 assert.equal(normalizeSettings().mode3,'wave');
 for(let count=1;count<=4;count++)assert.equal(runningStyleFor(count,{['mode'+count]:'pulse'}),'pulse');
 assert.equal(runningStyleFor(7,{mode4:'ripple'}),'ripple');
 assert.equal(runningStyleFor(3,{mode3:'garbage'}),'wave');
});
test('all twenty style/count combinations animate, stay bounded, and preserve other zones',()=>{
 for(let count=1;count<=4;count++){
  const fingerprints=[];
  for(const style of RUNNING_STYLES){
   const options={['mode'+count]:style};
   const frames=Array.from({length:16},(_,i)=>frameFor(base,snapshot(count),101,i*4,options));
   const values=frames.map(f=>Array.from({length:17},(_,i)=>key(f,83+i)));
   assert.ok(new Set(values.map(JSON.stringify)).size>5,`${count}/${style} must animate`);
   for(const f of frames){
    for(const id of[4,68,69])assert.deepEqual(key(f,id),key(base,id));
    assert.deepEqual(key(f,58),key(frames[0],58));
    for(const v of values.flat())for(const c of['red','green','blue'])assert.ok(Number.isFinite(v[c])&&v[c]>=0&&v[c]<=1);
   }
   fingerprints.push(JSON.stringify(values));
  }
  assert.equal(new Set(fingerprints).size,5,'Styles must not be merely renamed copies');
 }
});
test('style changes invalidate cached plans; unchanged plans retain the no-generation optimization',()=>{
 const s=snapshot(3),a=renderPlan(base,s,101,{mode3:'wave'}),b=renderPlan(base,s,101,{mode3:'pulse'});
 assert.notEqual(a.key,b.key);
 assert.equal(renderPlan(base,s,101,{mode3:'wave'},a.key).frames.length,0);
});
test('diagram packet contains the same RGB bytes as the emitted keyframes',()=>{
 const plan=renderPlan(base,snapshot(3),101,{mode3:'wave'});
 const packet=previewPacket(plan,101.25);
 assert.ok(packet);
 assert.equal(packet.startedAt,101.25);assert.equal(packet.taskCount,3);assert.equal(packet.style,'wave');
 assert.equal(packet.frames.length,plan.frames.length);
 const at=packet.keys.indexOf('93');assert.ok(at>=0);
 for(let i=0;i<packet.frames.length;i++){
  const c=key(plan.frames[i],93),expected=(Math.round(c.red*255)<<16)|(Math.round(c.green*255)<<8)|Math.round(c.blue*255);
  assert.equal(packet.frames[i][at],expected);
 }
 assert.ok(packet.frameSeconds>0);assert.equal(packet.active,true);
});
