// Explicit hardware test. Stop the normal lighting worker first.
import assert from 'node:assert/strict';
import {GHub,chooseKeyboard,renderPlan,animationPayload,frameFor,viewerPayload,colorsEqual,NUMPAD_KEYS}from'../scripts/keyboard.mjs';
const hub=new GHub();await hub.connect();let owned=false,device;
const rgba=(s,id)=>s.infoMap.PERKEY_KEYBOARD.perKeyMap.colorCodeMap[String(id)].rgba;
const closest=(sample,frames)=>{
 let best=0,error=Infinity;
 frames.forEach((f,i)=>{let e=0;for(const id of NUMPAD_KEYS)for(const c of['red','green','blue'])e+=Math.pow(rgba(sample,id)[c]-rgba(f,id)[c],2);if(e<error){error=e;best=i;}});
 return best;
};
try{
 device=chooseKeyboard((await hub.call('GET','/devices/list')).deviceInfos);assert.ok(device);
 let busy=false;try{await hub.call('GET','/lighting/viewer/state',{devices:[device.id]});busy=true;}catch(e){if(e.code!=='INVALID_ARG')throw e;}
 assert.equal(busy,false,'Stop the existing lighting worker before the test');
 const base=await hub.call('GET',`/lighting/${device.id}/state`);
 const profileId=(await hub.call('GET','/profile/active')).id;
 const before=await hub.call('GET','/profile',{id:profileId});
 const fast=process.argv.includes('--fast');
 for(const count of fast?[1]:[1,2,3]){
  const now=Date.now()/1000,s={generatedAt:now,quotaAt:now,windows:[{bucket:'codex',remaining:55}],tasks:Array.from({length:count},()=>({status:'active'})),events:[]};
  const plan=renderPlan(base,s,now,fast?{cycleSeconds:2}:{});
  await hub.call('SET','/lighting/viewer',animationPayload(device.id,plan.frames,plan.speed,plan.length));owned=true;
  const stable=sample=>[58,67,68,69].every(id=>['red','green','blue'].every(c=>Math.abs(Math.round(rgba(sample,id)[c]*255)-Math.round(rgba(plan.frames[0],id)[c]*255))<=1));
  let ready=false,lastSample;
  for(let i=0;i<25;i++){await new Promise(r=>setTimeout(r,80));lastSample=await hub.call('GET',`/lighting/${device.id}/state`);if(stable(lastSample)){ready=true;break;}}
  assert.ok(ready,JSON.stringify({message:'viewer did not reach hardware',actual:rgba(lastSample,58),expected:rgba(plan.frames[0],58)}));
  const observations=[];
  for(let i=0;i<13;i++){
   await new Promise(r=>setTimeout(r,fast?60:180));
   const sample=await hub.call('GET',`/lighting/${device.id}/state`);
   observations.push({time:Date.now(),index:closest(sample,plan.frames)});
   if(!stable(sample)){
    console.log(JSON.stringify({mismatches:[58,67,68,69].map(id=>({id,actual:rgba(sample,id),expected:rgba(plan.frames[0],id)})),mode:await hub.call('GET',`/lighting/${device.id}/mode`)}));
    assert.fail('quota/other region changed during a task animation');
   }
  }
  const first=observations[0],last=observations.at(-1),steps=(last.index-first.index+64)%64;
  const period=(last.time-first.time)/1000*64/steps;
  console.log(JSON.stringify({tasks:count,phaseStart:first.index,phaseEnd:last.index,estimatedCycleSeconds:Number(period.toFixed(1))}));
  assert.ok(steps>0&&period>=(fast?1.7:9.5)&&period<=(fast?2.5:16),'Running cycle differs from its configured duration');
  await hub.call('REMOVE','/lighting/viewer',{devices:[device.id]});owned=false;
 }
 const now=Date.now()/1000,s={generatedAt:now,quotaAt:now,windows:[{bucket:'codex',remaining:15}],tasks:[],events:[]};
 for(const options of[{globalBrightness:.5,keypadBrightness:.6,quotaBrightness:.8,logoBrightness:.7,otherBrightness:.2,otherColorEnabled:true,otherColor:'#FF8040'},{lowAlertEnabled:false},{globalBrightness:0}]){
  const expected=frameFor(base,s,now,0,options);await hub.call('SET','/lighting/viewer',viewerPayload(device.id,expected));owned=true;
  let matches=false;for(let i=0;i<10;i++){await new Promise(r=>setTimeout(r,80));if(colorsEqual(expected,await hub.call('GET',`/lighting/${device.id}/state`))){matches=true;break;}}
  assert.ok(matches,'Brightness, ambient color or red-alert mute did not reach keyboard');
  await hub.call('REMOVE','/lighting/viewer',{devices:[device.id]});owned=false;
 }
 assert.deepEqual(await hub.call('GET','/profile',{id:profileId}),before);
 console.log('PASS: '+(fast?'2-second outer orbit':'all task-count slow animations')+', brightness/color controls, red-alert mute and saved profile integrity');
}finally{if(owned)await hub.call('REMOVE','/lighting/viewer',{devices:[device.id]});hub.close();}
