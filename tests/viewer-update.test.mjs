import test from 'node:test';import assert from 'node:assert/strict';
import {updateOwnedViewer} from '../scripts/keyboard.mjs';
test('updates retain ownership and stop cached playback before starting replacement',async()=>{
 const calls=[],payload={devices:['keyboard'],actionType:'START',streaming:{enabled:true},effectPackage:{info:{}}};
 await updateOwnedViewer({call:async(...args)=>calls.push(args)},'keyboard',payload);
 assert.ok(calls.every(([verb,path])=>verb==='SET'&&path==='/lighting/viewer/update'),'No removal or profile fallback between input frames');
 assert.equal(calls[0][2].actionType,'STOP');assert.deepEqual(calls[1][2],payload);
});
test('failed stop must not start another viewer or silently release ownership',async()=>{
 const calls=[];await assert.rejects(updateOwnedViewer({call:async(...args)=>{calls.push(args);throw Error('offline');}},'keyboard',{}),/offline/);
 assert.equal(calls.length,1);assert.equal(calls[0][0],'SET');
});

test('a static frame uses the same keyframe transport as changing animation',async()=>{
 const {streamPayload}=await import('../scripts/keyboard.mjs');
 assert.equal(typeof streamPayload,'function');
 const frame={infoMap:{PERKEY_KEYBOARD:{perKeyMap:{colorCodeMap:{4:{rgba:{red:.1,green:.2,blue:.3,alpha:1}}}}}}};
 const payload=streamPayload('keyboard',frame);
 assert.ok(payload.effectPackage.info.keyframeInfo);
 assert.equal(Object.keys(payload.effectPackage.info.keyframeInfo.keyframeMap).length,2);
});
