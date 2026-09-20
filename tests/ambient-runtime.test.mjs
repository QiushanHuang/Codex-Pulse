import test from 'node:test';import assert from 'node:assert/strict';
import {renderPlan,frameFor,previewPacket,normalizeSettings} from '../scripts/keyboard.mjs';
const color={rgba:{red:.5,green:.4,blue:.3,alpha:1}};
const map=ids=>({perKeyMap:{colorCodeMap:Object.fromEntries(ids.map(id=>[id,structuredClone(color)]))}});
const base={infoMap:{PERKEY_KEYBOARD:map([4,20,58,68,83,88]),PERKEY_GKEY:map([1,2,3,4,5]),PERKEY_BRANDING:map([1]),PERKEY_CONSUMER:map([181])}};
const snapshot={generatedAt:100,quotaAt:100,windows:[{bucket:'codex',remaining:55}],tasks:[],events:[]};
const opts={ambientEnabled:true,ambientPreset:'g-ladder',ambientPalette:'glacier',ambientProfile:'balanced',ambientPeriod:12,ambientZones:{gkeys:.8}};
test('ambient selection survives normalization with safe fallback',()=>{assert.equal(normalizeSettings(opts).ambientPreset,'g-ladder');assert.equal(normalizeSettings({ambientEnabled:true,ambientPreset:'missing'}).ambientEnabled,false);});
test('idle ambient animates real G slot and preserves protected/unknown slots',()=>{
 const plan=renderPlan(base,snapshot,101,opts);assert.ok(plan.frames.length>1);
 assert.notDeepEqual(plan.frames[0].infoMap.PERKEY_GKEY,plan.frames[15].infoMap.PERKEY_GKEY);
 const old=frameFor(base,snapshot,101,0,{});
 for(const f of plan.frames){assert.deepEqual(f.infoMap.PERKEY_BRANDING,old.infoMap.PERKEY_BRANDING);assert.deepEqual(f.infoMap.PERKEY_CONSUMER,old.infoMap.PERKEY_CONSUMER);assert.deepEqual(f.infoMap.PERKEY_KEYBOARD.perKeyMap.colorCodeMap[58],old.infoMap.PERKEY_KEYBOARD.perKeyMap.colorCodeMap[58]);}
 const packet=previewPacket(plan,101);assert.ok(packet.keys.includes('G1'));assert.ok(packet.keys.includes('4'));
});
test('ambient clock is independent of task state and zero G brightness does not affect letters',()=>{
 const a=renderPlan(base,snapshot,101,opts),b=renderPlan(base,{...snapshot,tasks:[{status:'active'}]},101,opts);
 assert.deepEqual(a.frames[0].infoMap.PERKEY_GKEY,b.frames[0].infoMap.PERKEY_GKEY);
 const dark=renderPlan(base,snapshot,101,{...opts,ambientZones:{gkeys:0}});
 assert.equal(dark.frames[0].infoMap.PERKEY_GKEY.perKeyMap.colorCodeMap[1].rgba.blue,0);
 assert.deepEqual(a.frames[0].infoMap.PERKEY_KEYBOARD.perKeyMap.colorCodeMap[4],dark.frames[0].infoMap.PERKEY_KEYBOARD.perKeyMap.colorCodeMap[4]);
});
test('static ambient retains cached output and legacy config retains old path',()=>{
 const settings={...opts,ambientPreset:'g-jewels'};const a=renderPlan(base,snapshot,101,settings);
 assert.equal(a.frames.length,1);assert.equal(renderPlan(base,snapshot,102,settings,a.key).frames.length,0);
 assert.equal(renderPlan(base,snapshot,101,{}).frames.length,1);
});

test('reactive effects use short current frames rather than stale multi-second playback',()=>{
 const p=renderPlan(base,{...snapshot,ambientEvents:[{id:4,at:100.95}]},101,{...opts,ambientPreset:'splash'});
 assert.equal(p.frames.length,2);assert.equal(p.speed,64);
 const next=renderPlan(base,{...snapshot,ambientEvents:[{id:4,at:100.95}]},101.1,{...opts,ambientPreset:'splash'},p.key);
 assert.notEqual(p.key,next.key);assert.equal(next.frames.length,2);
});

test('reactive preset without recent input lets G HUB play the task animation',()=>{
 const live={...snapshot,tasks:[{status:'active'}]};
 const settings={...opts,ambientPreset:'splash'};
 const first=renderPlan(base,live,100.1,settings);
 assert.equal(first.frames.length,64);
 const unchanged=renderPlan(base,live,100.2,settings,first.key);
 assert.equal(unchanged.frames.length,0);
 const input=renderPlan(base,{...live,ambientEvents:[{id:4,at:100.21}]},100.22,settings,first.key);
 assert.equal(input.frames.length,2);
 const expired=renderPlan(base,{...live,ambientEvents:[{id:4,at:100.21}]},108.3,settings,input.key);
 assert.equal(expired.frames.length,64);
 assert.notEqual(expired.key,input.key);
});
test('nonmoving ambient does not restart an unchanged task animation on a wall-clock segment',()=>{
 const live={...snapshot,tasks:[{status:'active'}]};
 for(const ambientPreset of ['splash','g-jewels']){
  const settings={...opts,ambientPreset};const a=renderPlan(base,live,100.1,settings);
  assert.equal(renderPlan(base,live,105.1,settings,a.key).frames.length,0);
  assert.ok(renderPlan(base,live,105.1,{...settings,otherBrightness:.2},a.key).frames.length>0);
 }
});

test('resting and input playback share functional phase after many cached cycles and input expiry',()=>{
 const live={...snapshot,tasks:[{status:'active'}]};
 const settings={...opts,ambientPreset:'splash',cycleSeconds:12};
 const cached=renderPlan(base,live,100,settings);
 const dt=previewPacket(cached,100).frameSeconds;
 for(const index of [0,3,63,64,131]){
  const at=100+index*dt;
  const streaming=renderPlan(base,{...live,generatedAt:at,ambientEvents:[{id:4,at}]},at,settings,cached.key);
  for(const id of [83,88]) {
   const a=cached.frames[index%64].infoMap.PERKEY_KEYBOARD.perKeyMap.colorCodeMap[id].rgba;
   const b=streaming.frames[0].infoMap.PERKEY_KEYBOARD.perKeyMap.colorCodeMap[id].rgba;
   for(const ch of ['red','green','blue'])assert.ok(Math.abs(a[ch]-b[ch])<1e-8,`phase differs at ${index}/${id}/${ch}`);
  }
 }
 const at=109;
 const streaming=renderPlan(base,{...live,ambientEvents:[{id:4,at:108.999}]},at,settings);
 const resting=renderPlan(base,{...live,ambientEvents:[{id:4,at:100}]},at,settings,streaming.key);
 assert.deepEqual(resting.frames[0].infoMap.PERKEY_KEYBOARD.perKeyMap.colorCodeMap[83],streaming.frames[0].infoMap.PERKEY_KEYBOARD.perKeyMap.colorCodeMap[83]);
});

test('reactive functional alerts keep short-frame scheduling even without key input',()=>{
 const settings={...opts,ambientPreset:'splash'};
 for(const kind of ['reset','completed']){
  const plan=renderPlan(base,{...snapshot,events:[{kind,at:100}]},100.5,settings);
  assert.equal(plan.frames.length,2);assert.equal(plan.pollMs,64);
  const unchanged=renderPlan(base,{...snapshot,events:[{kind,at:100}]},100.501,settings,plan.key);
  assert.equal(unchanged.pollMs,64);
 }
 const resting=renderPlan(base,{...snapshot,tasks:[{status:'active'}]},101,settings);
 assert.equal(resting.pollMs,500);
});
