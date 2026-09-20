import test from 'node:test';
import assert from 'node:assert/strict';
import { frameFor as engineFrameFor, chooseKeyboard, colorsEqual, viewerPayload, animationPayload, renderPlan as engineRenderPlan, previewSnapshot, AlertPlayback, runningGroups, runningHeads, normalizeSettings, powerPolicy, PowerPolicyController } from '../scripts/keyboard.mjs';

// Legacy geometry stays selectable; these regressions explicitly exercise classic mode.
const classic={mode1:'classic',mode2:'classic',mode3:'classic',mode4:'classic'};
const frameFor=(base,s,now,phase,options={})=>engineFrameFor(base,s,now,phase,{...classic,...options});
const renderPlan=(base,s,now,options={},previousKey=null)=>engineRenderPlan(base,s,now,{...classic,...options},previousKey);

const base = {infoMap:{PERKEY_KEYBOARD:{perKeyMap:{colorCodeMap:Object.fromEntries([4,...Array.from({length:12},(_,i)=>58+i),...Array.from({length:17},(_,i)=>83+i)].map(i=>[String(i),{rgba:{red:1,green:1,blue:1,alpha:1}}]))}},PERKEY_BRANDING:{perKeyMap:{colorCodeMap:{'1':{rgba:{red:1,green:1,blue:1,alpha:1}}}}}},persistent:true};
const snapshot=(extra={})=>({quotaAt:100,generatedAt:100,windows:[{bucket:'codex',remaining:50}],tasks:[],events:[],...extra});
const key=(frame,id)=>frame.infoMap.PERKEY_KEYBOARD.perKeyMap.colorCodeMap[String(id)].rgba;
const logo=frame=>frame.infoMap.PERKEY_BRANDING.perKeyMap.colorCodeMap['1'].rgba;
test('targets only a supported keyboard, not the mouse',()=>{
  assert.equal(chooseKeyboard([{id:'m',deviceModel:'g502',deviceType:'MOUSE',state:'ACTIVE'},{id:'k',deviceModel:'g913',deviceType:'KEYBOARD',state:'ACTIVE'}])?.id,'k');
});
test('lighting is transient, input snapshot is preserved, quota bar is correct',()=>{
  const before=JSON.stringify(base);
  const frame=frameFor(base,{quotaAt:100,windows:[{bucket:'codex',remaining:50}],tasks:[],events:[]},101,0);
  assert.equal(frame.persistent,false);
  assert.equal(JSON.stringify(base),before);
  const keys=frame.infoMap.PERKEY_KEYBOARD.perKeyMap.colorCodeMap;
  assert.ok(keys['58'].rgba.green > keys['67'].rgba.green);
});
test('F1-F10 are ten stable quota segments and F11/F12 stay untouched',()=>{
  const s=snapshot({windows:[{bucket:'codex',remaining:55}],tasks:[{status:'active'}]});
  const a=frameFor(base,s,101,0),b=frameFor(base,s,101,8);
  for(let id=58;id<=67;id++)assert.deepEqual(key(a,id),key(b,id));
  for(const id of [4,68,69])assert.deepEqual(key(a,id),key(base,id));
  assert.ok(key(a,62).green>key(a,63).green);
  assert.ok(key(a,63).green>key(a,64).green);
});
test('running animation moves on keypad while logo reports quota only',()=>{
  const s=snapshot({tasks:[{status:'active'}]});
  const a=frameFor(base,s,101,0),b=frameFor(base,s,101,8);
  assert.notDeepEqual(key(a,89),key(b,89));
  assert.deepEqual(logo(a),logo(b));
  assert.deepEqual(key(a,87),key(b,87));
});
test('reset flashes logo and all 17 keypad keys in sync, never the quota bar',()=>{
  const s=snapshot({events:[{kind:'reset',at:100}]});
  const a=frameFor(base,s,100.1,0),b=frameFor(base,s,100.1,1);
  assert.notDeepEqual(logo(a),logo(b));
  for(let id=83;id<=99;id++){
    assert.deepEqual(key(a,id),logo(a));assert.deepEqual(key(b,id),logo(b));
  }
  for(let id=58;id<=69;id++)assert.deepEqual(key(a,id),key(b,id));
});
test('completion animates keypad and prioritizes reset over simultaneous completion',()=>{
  const done=snapshot({tasks:[{status:'active'}],events:[{kind:'completed',at:100}]});
  const a=frameFor(base,done,100.1,0),b=frameFor(base,done,100.1,8);
  assert.notDeepEqual(key(a,98),key(b,98));assert.deepEqual(logo(a),logo(b));
  const both=snapshot({events:[{kind:'reset',at:100},{kind:'completed',at:100.1}]});
  const reset=snapshot({events:[{kind:'reset',at:100}]});
  assert.deepEqual(logo(frameFor(base,both,100.2,0)),logo(frameFor(base,reset,100.2,0)));
});
test('low quota is steady red and can be silenced independently',()=>{
  const s=snapshot({windows:[{bucket:'codex',remaining:20}]});
  const a=frameFor(base,s,101,0),b=frameFor(base,s,101,8);
  assert.deepEqual(logo(a),logo(b));assert.ok(logo(a).red>logo(a).green*3);
  const red=logo(frameFor(base,snapshot({windows:[{bucket:'codex',remaining:5}]}),101,0));
  assert.ok(red.red>red.green*3);
  const muted=frameFor(base,s,101,0,{lowAlertEnabled:false});
  assert.equal(logo(muted).red+logo(muted).green+logo(muted).blue,0);
  assert.deepEqual(key(muted,58),key(a,58));
});
test('unknown or stale quota must not show a full bar',()=>{
  const frame=frameFor(base,{quotaAt:1,windows:[{bucket:'codex',remaining:100}],tasks:[],events:[]},1000,0);
  const color=frame.infoMap.PERKEY_KEYBOARD.perKeyMap.colorCodeMap['58'].rgba;
  assert.equal(color.red,color.green);
  assert.equal(color.green,color.blue);
});
test('color comparison ignores protobuf map order but detects real color changes',()=>{
  const reordered=structuredClone(base);reordered.infoMap=Object.fromEntries(Object.entries(reordered.infoMap).reverse());
  assert.equal(colorsEqual(base,reordered),true);
  reordered.infoMap.PERKEY_KEYBOARD.perKeyMap.colorCodeMap['58'].rgba.red=0;
  assert.equal(colorsEqual(base,reordered),false);
});
test('temporary viewer streams to hardware and never saves a profile',()=>{
  const payload=viewerPayload('keyboard',base);
  assert.equal(payload.streaming.enabled,true);
  assert.equal(payload.effectPackage.info.fixedInfo.lightingSlots.infoMap.PERKEY_KEYBOARD.perKeyMap.colorCodeMap['58'].hex,'#FFFFFF');
  assert.equal(payload.actionType,'START');
  assert.equal(payload.persistent,undefined);
});
test('native animation uploads all frames in one temporary effect',()=>{
  const p=animationPayload('keyboard',[base,base],20);
  assert.equal(Object.keys(p.effectPackage.info.keyframeInfo?.keyframeMap??{}).length,2);
  assert.equal(p.effectMetadata.keyframeMetadata.direction,'CYCLE');
});
test('reset has a brief fast stage and settles back to live behavior',()=>{
  const s=snapshot({events:[{kind:'reset',at:100}],tasks:[{status:'active'}]});
  const flash=renderPlan(base,s,100.2);
  assert.equal(flash.mode,'reset-flash');assert.equal(flash.frames.length,4);
  assert.deepEqual(flash.frames[0],flash.frames[1]);
  assert.deepEqual(flash.frames[2],flash.frames[3]);
  assert.notDeepEqual(logo(flash.frames[0]),logo(flash.frames[2]));
  assert.equal(renderPlan(base,s,102.2).mode,'reset-glow');
  assert.equal(renderPlan(base,s,108.1).mode,'running');
});
test('demo expires and does not alter actual account or task data',()=>{
  const s=snapshot({tasks:[{status:'active'}]}),before=structuredClone(s);
  const p=previewSnapshot(s,{scene:'low',startedAt:100},101);
  assert.equal(p.windows[0].remaining,15);assert.deepEqual(s,before);
  assert.equal(previewSnapshot(s,{scene:'low',startedAt:100},108),s);
});
test('alerts begin on detection even when the task poll arrives late',()=>{
  const player=new AlertPlayback();
  const s=snapshot({events:[{kind:'completed',at:100}]});
  assert.equal(player.events(s,105)[0].at,105);
  assert.equal(player.events(s,106)[0].at,105);
  assert.deepEqual(player.events(s,114),[]);
});
test('a completion cannot interrupt a reset alert',()=>{
  const player=new AlertPlayback();player.events(snapshot({events:[{kind:'reset',at:100}]}),100);
  const e=player.events(snapshot({events:[{kind:'reset',at:100},{kind:'completed',at:101}]}),101);
  assert.equal(e[0].kind,'reset');
});
test('one, two and three task routes match the requested key groups',()=>{
  assert.deepEqual(runningGroups(1),[[98,89,92,95,96,97,94,91,99]]);
  assert.deepEqual(runningGroups(2).map(g=>[...g].sort((a,b)=>a-b)),[[89,90,91,92,93,94],[83,84,85,95,96,97]]);
  assert.deepEqual(runningGroups(3),[[89,92,95,83],[90,93,96,84],[91,94,97,85]]);
  assert.deepEqual(runningGroups(4),[[83,84,85],[95,96,97],[92,93,94],[89,90,91]]);
  assert.deepEqual(runningGroups(5),runningGroups(4));
});
test('task count changes invalidate the running effect',()=>{
  const one=snapshot({tasks:[{status:'active'}]}),two=snapshot({tasks:[{status:'active'},{status:'active'}]});
  assert.notEqual(renderPlan(base,one,101).key,renderPlan(base,two,101).key);
});
test('three task waves rise from 1 to 4 to 7 to Num in that order',()=>{
  const s=snapshot({tasks:Array.from({length:3},()=>({status:'active'}))});
  const column=[89,92,95,83];
  const peaks=[0,16,32,48].map(phase=>{
    const f=frameFor(base,s,101,phase);
    return [...column].sort((a,b)=>key(f,b).blue-key(f,a).blue)[0];
  });
  assert.deepEqual(peaks,column);
});
test('three task crests match 1, 5, 9 and remain one key-height apart',()=>{
  const s=snapshot({tasks:Array.from({length:3},()=>({status:'active'}))});
  const columns=[[91,94,97,85],[90,93,96,84],[89,92,95,83]];
  const bottoms=columns.map(c=>c[0]);
  const anchor=frameFor(base,s,101,0);
  for(const [column,expected]of[[[89,92,95,83],89],[[90,93,96,84],93],[[91,94,97,85],97]])
    assert.equal([...column].sort((a,b)=>key(anchor,b).blue-key(anchor,a).blue)[0],expected);
  const order=[32,48,64].map(phase=>{
    const f=frameFor(base,s,101,phase);
    return [...bottoms].sort((a,b)=>key(f,b).blue-key(f,a).blue)[0];
  });
  assert.deepEqual(order,bottoms);
  for(const phase of[5,13,29])for(let row=0;row<4;row++){
    const values=columns.map((column,i)=>key(frameFor(base,s,101,phase+i*16),column[row]).blue);
    assert.ok(Math.max(...values)-Math.min(...values)<1e-9);
  }
});
test('four task rows translate at equal speed with fixed diagonal offsets',()=>{
  const a=runningHeads(4,0),b=runningHeads(4,8);
  assert.deepEqual(a,[0,2/3,4/3,2]);
  for(let i=0;i<4;i++)assert.ok(Math.abs((b[i]-a[i])-3/8)<1e-10);
  for(let i=1;i<4;i++)assert.ok(Math.abs((b[i]-b[i-1])-2/3)<1e-10);
  const s=snapshot({tasks:Array.from({length:4},()=>({status:'active'}))});
  const f=frameFor(base,s,101,0);
  assert.equal(key(f,83).blue,1);assert.equal(key(f,91).blue,1);
  assert.ok(key(f,96).blue>key(f,95).blue);
  assert.ok(key(f,93).blue>key(f,94).blue);
  assert.notDeepEqual(key(f,84),key(frameFor(base,s,101,16),84));
});
test('four-task demo preserves the real task list and selects four-row rendering',()=>{
  const s=snapshot({tasks:[{status:'active'}]});
  const p=previewSnapshot(s,{scene:'running',taskCount:4,startedAt:100},101);
  assert.equal(p.tasks.length,4);assert.equal(s.tasks.length,1);
  assert.notEqual(renderPlan(base,p,101).key,renderPlan(base,s,101).key);
});
test('slash animates in both two-task and three-task modes',()=>{
  for(const count of[2,3]){
    const s=snapshot({tasks:Array.from({length:count},()=>({status:'active'}))});
    const values=Array.from({length:64},(_,phase)=>key(frameFor(base,s,101,phase),84).blue);
    assert.ok(Math.max(...values)-Math.min(...values)>.5);
  }
});
test('completion stays in the repeated rising-wave stage for three cycles before confirming',()=>{
  const s=snapshot({events:[{kind:'completed',at:100}]});
  for(const age of[.1,1.6,3.1,4.4])assert.equal(renderPlan(base,s,100+age).mode,'complete-wave');
  assert.equal(renderPlan(base,s,104.6).mode,'complete-settle');
  assert.equal(renderPlan(base,s,108.1).mode,'idle');
});
test('global and regional brightness multiply and global zero extinguishes every exposed LED',()=>{
  const s=snapshot({tasks:[{status:'active'}]});
  const original=frameFor(base,s,101,0),dim=frameFor(base,s,101,0,{globalBrightness:.5,quotaBrightness:.3,keypadBrightness:.4,logoBrightness:.7,otherBrightness:.2});
  for(const [id,multiplier]of[[58,.15],[98,.2],[4,.1]])assert.ok(Math.abs(key(dim,id).blue-key(original,id).blue*multiplier)<1e-10);
  assert.ok(Math.abs(logo(dim).blue-logo(original).blue*.35)<1e-10);
  const dark=frameFor(base,s,101,0,{globalBrightness:0});
  for(const slot of Object.values(dark.infoMap))for(const c of Object.values(slot.perKeyMap.colorCodeMap))assert.equal(c.rgba.red+c.rgba.green+c.rgba.blue,0);
});
test('custom ambient color affects other regions without replacing the functional palette',()=>{
  const f=frameFor(base,snapshot(),101,0,{otherColorEnabled:true,otherColor:'#FF0000'});
  assert.ok(key(f,4).red>0);assert.equal(key(f,4).blue,0);assert.equal(key(f,68).green,0);
  assert.ok(key(f,58).green>key(f,58).red);
});
test('slower cycle setting survives quota burn changes and participates in render identity',()=>{
  const s=snapshot({tasks:[{status:'active'}]});
  assert.equal(normalizeSettings().cycleSeconds,12);
  const fast=renderPlan(base,s,101,{cycleSeconds:6}),slow=renderPlan(base,s,101,{cycleSeconds:24});
  assert.notEqual(fast.key,slow.key);
  assert.ok(slow.frames.length*slow.length*slow.speed>fast.frames.length*fast.length*fast.speed);
});
test('settings clamp unsafe values and reject malformed ambient colors',()=>{
  const cfg=normalizeSettings({globalBrightness:-2,keypadBrightness:5,cycleSeconds:NaN,otherColor:'not-a-color'});
  assert.equal(cfg.globalBrightness,0);assert.equal(cfg.keypadBrightness,1);
  assert.equal(cfg.cycleSeconds,12);assert.match(cfg.otherColor,/^#[0-9A-F]{6}$/);
});
test('three-task preview lasts one slow cycle and does not change real task count',()=>{
  const s=snapshot({tasks:[{status:'active'}]});
  const p=previewSnapshot(s,{scene:'running',taskCount:3,startedAt:100,duration:22},115);
  assert.equal(p.tasks.length,3);assert.equal(s.tasks.length,1);
  assert.equal(previewSnapshot(s,{scene:'running',taskCount:3,startedAt:100,duration:22},123),s);
});
test('muting low-quota red does not mute reset notifications',()=>{
  const s=snapshot({windows:[{bucket:'codex',remaining:10}],events:[{kind:'reset',at:100}]});
  assert.deepEqual(logo(frameFor(base,s,100.1,0,{lowAlertEnabled:false})),logo(frameFor(base,s,100.1,0)));
});
test('reset brightness scales once per zone even though flash colors are shared',()=>{
  const s=snapshot({events:[{kind:'reset',at:100}]});
  const original=frameFor(base,s,100.1,0),dim=frameFor(base,s,100.1,0,{globalBrightness:.5,logoBrightness:.8,keypadBrightness:.4});
  assert.ok(Math.abs(logo(dim).blue-logo(original).blue*.4)<1e-10);
  for(let id=83;id<=99;id++)assert.ok(Math.abs(key(dim,id).blue-key(original,id).blue*.2)<1e-10);
});
test('hardware payload encodes exact RGB bytes and custom colors are opaque',()=>{
  const f=frameFor(base,snapshot(),101,0,{otherColorEnabled:true,otherColor:'#1A334D'});
  const payload=viewerPayload('keyboard',f);
  assert.equal(payload.effectPackage.info.fixedInfo.lightingSlots.infoMap.PERKEY_KEYBOARD.perKeyMap.colorCodeMap['4'].hex,'#1A334D');
  assert.ok(f.infoMap.PERKEY_KEYBOARD.perKeyMap.colorCodeMap['4'].rgba);
});
test('hardware color comparison uses byte values and tolerates one interpolation rounding step',()=>{
  const expected=structuredClone(base),actual=structuredClone(base);
  expected.infoMap.PERKEY_KEYBOARD.perKeyMap.colorCodeMap['58'].rgba.blue=.288;
  actual.infoMap.PERKEY_KEYBOARD.perKeyMap.colorCodeMap['58'].rgba.blue=72/255;
  assert.equal(colorsEqual(expected,actual),true);
  actual.infoMap.PERKEY_KEYBOARD.perKeyMap.colorCodeMap['58'].rgba.blue=68/255;
  assert.equal(colorsEqual(expected,actual),false);
});
test('one-task orbit follows the physical outer ring and its center still glows',()=>{
  const expected=[98,89,92,95,96,97,94,91,99];
  assert.deepEqual(runningGroups(1)[0],expected);
  const s=snapshot({tasks:[{status:'active'}]});
  for(const id of[90,93])assert.notDeepEqual(key(frameFor(base,s,101,0),id),key(frameFor(base,s,101,16),id));
});
test('100 percent functional brightness reaches the ambient peak, with a dim tail',()=>{
  const s=snapshot({tasks:[{status:'active'}]});
  const f=frameFor(base,s,101,0,{otherColorEnabled:true,otherColor:'#00F5FF'});
  assert.equal(key(f,98).blue,1);
  assert.equal(key(f,58).green,1);
  assert.equal(logo(f).green,1);
  assert.ok(key(f,98).green>=.9);
  assert.ok(key(f,98).blue>key(f,94).blue*4);
});
test('running speed range includes a two-second cycle',()=>{
  assert.equal(normalizeSettings({cycleSeconds:2}).cycleSeconds,2);
  const plan=renderPlan(base,snapshot({tasks:[{status:'active'}]}),101,{cycleSeconds:2});
  assert.ok(plan.frames.length*plan.length*plan.speed<=2100);
});
test('idle dimming defaults to 60 seconds at 50 percent and sleep to 300 seconds',()=>{
  assert.deepEqual(powerPolicy(),{brightness:.5,inactivity:{seconds:60},sleep:{seconds:300}});
});
test('idle time and brightness are independent of active-region brightness',()=>{
  const options={idleAfterSeconds:120,idleBrightness:.2,sleepAfterSeconds:600,globalBrightness:.8};
  assert.deepEqual(powerPolicy(options),{brightness:.2,inactivity:{seconds:120},sleep:{seconds:600}});
  const s=snapshot({tasks:[{status:'active'}]});
  assert.deepEqual(frameFor(base,s,101,0,options),frameFor(base,s,101,0,{globalBrightness:.8}));
});
test('sleep must occur after the configured dim delay',()=>{
  const p=powerPolicy({idleAfterSeconds:600,sleepAfterSeconds:60,idleBrightness:-1});
  assert.equal(p.sleep?.seconds,630);assert.equal(p.brightness,0);
});
test('brightness self-test is temporary, fully white and leaves real data intact',()=>{
  const s=snapshot(),before=structuredClone(s);
  const preview={scene:'brightness-test',startedAt:100,duration:5};
  const p=previewSnapshot(s,preview,101);
  const f=frameFor(base,p,101,0,{globalBrightness:.1,otherBrightness:.1});
  for(const slot of Object.values(f.infoMap))for(const c of Object.values(slot.perKeyMap.colorCodeMap))assert.deepEqual(c.rgba,{red:1,green:1,blue:1,alpha:1});
  assert.equal(renderPlan(base,p,101).frames.length,1);
  assert.deepEqual(s,before);assert.equal(previewSnapshot(s,preview,106),s);
});
test('power settings are applied once, read back and do not wake on every tick',async()=>{
  let actual=powerPolicy(),writes=0,wakes=0;
  const hub={call:async(verb,path,payload)=>{
    if(path.endsWith('/mode/wake')){wakes++;return {};}
    if(verb==='SET'){actual=structuredClone(payload);writes++;return {};}
    return actual;
  }};
  const controller=new PowerPolicyController(hub,{id:'keyboard'});
  await controller.apply({});await controller.apply({globalBrightness:.3});
  assert.equal(writes,0);assert.equal(wakes,0);
  await controller.apply({idleBrightness:.25});await controller.apply({idleBrightness:.25});
  assert.equal(writes,1);assert.equal(wakes,1);assert.equal(actual.brightness,.25);
});
test('failed power-setting readback cannot be reported as applied',async()=>{
  const hub={call:async()=>powerPolicy()};
  const controller=new PowerPolicyController(hub,{id:'keyboard'});
  await assert.rejects(controller.apply({idleBrightness:.1}),/读回/);
  assert.equal(controller.applied,null);
});
test('adjusting idle policy does not recreate the active animation',()=>{
  const s=snapshot({tasks:[{status:'active'}]});
  assert.equal(renderPlan(base,s,101).key,renderPlan(base,s,101,{idleBrightness:.1,idleAfterSeconds:600}).key);
});

test('unchanged semantic plan skips animation frames but time transitions still render',()=>{
  const s=snapshot({tasks:[{status:'active'}]});
  const first=renderPlan(base,s,101);
  const unchanged=renderPlan(base,{...s,generatedAt:102},102,{},first.key);
  assert.equal(unchanged.frames.length,0);
  assert.equal(unchanged.key,first.key);
  const changed=renderPlan(base,{...s,windows:[{bucket:'codex',remaining:25}]},103,{},first.key);
  assert.equal(changed.frames.length,64);
  const stale=renderPlan(base,s,10000,{},first.key);
  assert.notEqual(stale.key,first.key);
  assert.ok(stale.frames.length>0);
});
