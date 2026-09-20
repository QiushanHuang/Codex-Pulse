import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import * as runtime from '../scripts/keyboard.mjs';

test('JSON cache avoids repeated parse but observes replacement and rejects damaged/missing files',()=>{
 assert.equal(typeof runtime.JsonFileCache,'function');
 const dir=fs.mkdtempSync(path.join(os.tmpdir(),'pulse-cache-'));
 try {
  const file=path.join(dir,'state.json');fs.writeFileSync(file,'{"value":1}');
  const cache=new runtime.JsonFileCache(file),first=cache.read();
  for(let i=0;i<100;i++)assert.equal(cache.read(),first);
  const replacement=path.join(dir,'next.json');fs.writeFileSync(replacement,'{"value":2}');fs.renameSync(replacement,file);
  assert.equal(cache.read().value,2);
  fs.writeFileSync(file,'{broken');assert.throws(()=>cache.read());
  fs.writeFileSync(file,'{"value":3}');assert.equal(cache.read().value,3);
  fs.unlinkSync(file);assert.throws(()=>cache.read());
 } finally {fs.rmSync(dir,{recursive:true,force:true});}
});

test('preview publisher performs no encoding without a viewer, throttles and serves late viewers',()=>{
 assert.equal(typeof runtime.PreviewPublisher,'function');
 let lease=0,packets=[],encodes=0;
 const publisher=new runtime.PreviewPublisher({viewerAt:()=>lease,encode:(p,at)=>{encodes++;return {key:p.key,startedAt:at};},write:p=>packets.push(p)});
 publisher.update({key:'a'},100,{demo:false});publisher.publish(100);assert.equal(encodes,0);
 lease=101;publisher.publish(101);assert.deepEqual(packets,[{key:'a',startedAt:100,demo:false}]);
 publisher.update({key:'b'},101.01,{demo:true});publisher.publish(101.01);assert.equal(encodes,1);
 publisher.publish(101.3);assert.equal(encodes,2);assert.equal(packets[1].key,'b');
 publisher.update({key:'c'},105);publisher.publish(105);assert.equal(encodes,2);
 lease=106;publisher.publish(106);assert.equal(encodes,3);
 publisher.clear();lease=107;publisher.publish(107);assert.equal(encodes,3);
});

test('input wakeup interrupts idle wait and preserves events arriving before wait',async()=>{
 assert.equal(typeof runtime.WakeSignal,'function');
 const signal=new runtime.WakeSignal();signal.wake();
 await signal.wait(60_000);
 const pending=signal.wait(60_000);signal.wake();await pending;
});

test('same preview recovers after a transient service error without requiring a changed effect',()=>{
 let output=[];
 const publisher=new runtime.PreviewPublisher({viewerAt:()=>100,encode:p=>({key:p.key}),write:p=>output.push(p)});
 publisher.update({key:'same'},100);publisher.publish(100);
 assert.equal(typeof publisher.invalidate,'function');publisher.invalidate();
 publisher.publish(100.3);assert.equal(output.length,2);assert.equal(output[1].key,'same');
});
