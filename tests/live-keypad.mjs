// Explicit hardware test: run only with the normal lighting worker stopped.
import assert from 'node:assert/strict';
import {GHub,chooseKeyboard,frameFor,renderPlan,animationPayload,QUOTA_KEYS,NUMPAD_KEYS} from '../scripts/keyboard.mjs';
const hub=new GHub();await hub.connect();let owned=false,device;
const same=(a,b)=>['red','green','blue'].every(k=>Number.isFinite(a?.[k])&&Number.isFinite(b?.[k])&&Math.abs(Math.round(a[k]*255)-Math.round(b[k]*255))<=1);
const key=(s,id)=>s.infoMap.PERKEY_KEYBOARD.perKeyMap.colorCodeMap[String(id)].rgba;
const logo=s=>s.infoMap.PERKEY_BRANDING.perKeyMap.colorCodeMap['1'].rgba;
try {
  device=chooseKeyboard((await hub.call('GET','/devices/list')).deviceInfos);assert.ok(device);
  let busy=false;
  try{await hub.call('GET','/lighting/viewer/state',{devices:[device.id]});busy=true;}catch(error){if(error.code!=='INVALID_ARG')throw error;}
  assert.equal(busy,false,'Close the normal lighting worker or other G HUB preview first');
  const base=await hub.call('GET',`/lighting/${device.id}/state`);
  const profile=(await hub.call('GET','/profile/active')).id;
  const before=await hub.call('GET','/profile',{id:profile});
  const scenes=process.argv[2]?[process.argv[2]]:['running','completed','reset'];
  for(const scene of scenes) {
    assert.ok(['running','completed','reset'].includes(scene));
    const now=Date.now()/1000;
    const snapshot={quotaAt:now,generatedAt:now,windows:[{bucket:'codex',remaining:55}],tasks:scene==='running'?[{status:'active'}]:[],events:scene==='running'?[]:[{kind:scene,at:now}]};
    const plan=renderPlan(base,snapshot,now+.01);
    await hub.call('SET','/lighting/viewer',animationPayload(device.id,plan.frames,plan.speed,plan.length));owned=true;
    const samples=[];
    for(let i=0;i<16;i++) {
      await new Promise(r=>setTimeout(r,80));
      const current=await hub.call('GET',`/lighting/${device.id}/state`);
      for(const id of QUOTA_KEYS)assert.ok(same(key(current,id),key(plan.frames[0],id)),`${scene}: quota key ${id} changed`);
      for(const id of [4,68,69])assert.ok(same(key(current,id),key(base,id)),`${scene}: unrelated key ${id} changed`);
      if(scene==='reset')for(const id of NUMPAD_KEYS)assert.ok(same(key(current,id),logo(current)),`reset: keypad ${id} not synchronized`);
      else assert.ok(same(logo(current),logo(plan.frames[0])),`${scene}: task animation altered Logo`);
      samples.push(NUMPAD_KEYS.map(id=>key(current,id)));
    }
    const unique=new Set(samples.map(s=>JSON.stringify(s))).size;
    if(scene==='reset'){
      const levels=samples.map(s=>Math.round(s[0].blue*255));
      const transitions=levels.slice(1).filter((v,i)=>Math.abs(v-levels[i])>50).length;
      console.log(JSON.stringify({resetLevels:[...new Set(levels)],transitions}));
      assert.ok(unique>=2&&transitions>=3,'reset must visibly alternate bright/dark, not stay a fixed color');
    }else assert.ok(unique>2,`${scene}: no moving animation`);
    console.log(JSON.stringify({scene,distinctFrames:unique,quotaBarStable:true,F11F12Preserved:true,logoAndKeypadSync:scene==='reset'?true:undefined}));
    await hub.call('REMOVE','/lighting/viewer',{devices:[device.id]});owned=false;
  }
  assert.deepEqual(await hub.call('GET','/profile',{id:profile}),before);
  const mode=await hub.call('GET',`/lighting/${device.id}/mode`);
  assert.ok(!mode.sources.includes('EFFECT_TESTER'));
  console.log(`PASS: ${scenes.join('/')} regions, animation and return to G HUB`);
} finally {
  if(owned)await hub.call('REMOVE','/lighting/viewer',{devices:[device.id]});
  hub.close();
}
