import fs from 'node:fs';import assert from 'node:assert/strict';
import {GHub,chooseKeyboard,viewerPayload,animationPayload,updateOwnedViewer} from '../scripts/keyboard.mjs';
const h=new GHub();let device,owned=false,reading=true,brightSamples=0,samples=0;const wait=ms=>new Promise(r=>setTimeout(r,ms));
const color=(r,g,b)=>({rgba:{red:r,green:g,blue:b,alpha:1},tag:''});
try{
 await h.connect();device=chooseKeyboard((await h.call('GET','/devices/list')).deviceInfos);assert.ok(device);
 let busy=false;try{await h.call('GET','/lighting/viewer/state',{devices:[device.id]});busy=true;}catch(e){if(e.code!=='INVALID_ARG')throw e;}assert.equal(busy,false);
 const profile=(await h.call('GET','/profile/active')).id,saved=await h.call('GET','/profile',{id:profile});const base=await h.call('GET',`/lighting/${device.id}/state`);
 const frame=(r,g,b)=>{const f=structuredClone(base);for(const info of Object.values(f.infoMap))for(const k of Object.keys(info.perKeyMap?.colorCodeMap??{}))info.perKeyMap.colorCodeMap[k]=color(r,g,b);return f;};
 const a=frame(.06,.02,.08),b=frame(.02,.12,.04);
 await h.call('SET',`/lighting/${device.id}/mode/wake`,{});await h.call('SET','/lighting/viewer',animationPayload(device.id,[a,a],64,1));owned=true;await wait(250);
 const reader=(async()=>{while(reading){const f=await h.call('GET',`/lighting/${device.id}/state`);const c=f.infoMap.PERKEY_KEYBOARD.perKeyMap.colorCodeMap['4'].rgba;samples++;if(Math.max(c.red,c.green,c.blue)>.2)brightSamples++;await wait(8);}})();
 try{
 for(let i=0;i<18;i++){
 const target=i%2? a:b,payload=animationPayload(device.id,[target,target],64,1);
 await updateOwnedViewer(h,device.id,payload);await wait(80);
 const state=await h.call('GET','/lighting/viewer/state',{devices:[device.id]});assert.ok(state);
 const f=await h.call('GET',`/lighting/${device.id}/state`),actual=f.infoMap.PERKEY_KEYBOARD.perKeyMap.colorCodeMap['4'].rgba,expected=target.infoMap.PERKEY_KEYBOARD.perKeyMap.colorCodeMap['4'].rgba;
 for(const channel of ['red','green','blue'])assert.ok(Math.abs(actual[channel]-expected[channel])*255<3,`update ${i} ${channel}: ${actual[channel]} expected ${expected[channel]}`);
 }
 }finally{reading=false;await reader;}
 assert.equal(brightSamples,0,'full-bright profile must not appear while updating');assert.deepEqual(await h.call('GET','/profile',{id:profile}),saved);
 const result={at:new Date().toISOString(),updates:18,samples,brightSamples,profileUnchanged:true};fs.writeFileSync('build/viewer-update-validation.json',JSON.stringify(result,null,2));console.log(result);
}finally{reading=false;if(owned)await h.call('REMOVE','/lighting/viewer',{devices:[device.id]});h.close();}
