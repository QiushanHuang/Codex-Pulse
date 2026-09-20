import test from 'node:test';
import assert from 'node:assert/strict';
import {presets,keys,render} from '../docs/ambient-lighting/engine.mjs';
test('catalog covers four distinct effect families',()=>{
 assert.equal(presets.length,48);assert.equal(new Set(presets.map(p=>p.id)).size,48);
 assert.equal(new Set(presets.map(p=>p.category)).size,4);
});
test('every preset preserves functional keys and produces finite RGB',()=>{
 assert.ok(keys.length>90);
 for(const p of presets)for(const t of [0,.3,2,8]){
 const frame=render(p,t,{events:[{id:4,at:0}]});
 for(const k of keys){if(k.protected){assert.equal(frame[k.id],undefined);continue;}
 assert.equal(frame[k.id].length,3);
 assert.ok(frame[k.id].every(c=>Number.isFinite(c)&&c>=0&&c<=255));}
 }
});
test('static presets remain still; all loop presets move',()=>{
 assert.ok(presets.length);
 for(const p of presets){if(p.category==='static'||p.category==='zones')assert.deepEqual(render(p,0),render(p,3));
 if(p.category==='loop')assert.notDeepEqual(render(p,0),render(p,2));}
});
test('interactive effects respond and settle after event expiration',()=>{
 assert.ok(presets.length);
 for(const p of presets.filter(p=>p.category==='reactive')){
 assert.notDeepEqual(render(p,.2),render(p,.2,{events:[{id:4,at:0}]}),p.id);
 assert.deepEqual(render(p,20),render(p,20,{events:[{id:4,at:0}]}),p.id);}
});
test('zero master or zone brightness extinguishes only ambient keys',()=>{
 assert.ok(presets.length);
 for(const p of presets){assert.ok(Object.values(render(p,1,{brightness:0})).every(rgb=>rgb.every(c=>c===0)));
 const f=render(p,1,{zones:{letters:0}});for(const k of keys.filter(k=>k.zone==='letters'))assert.deepEqual(f[k.id],[0,0,0]);}
});

test('G1-G5 occupy the left column with separate G HUB addresses',()=>{
 const g=keys.filter(k=>k.zone==='gkeys');assert.equal(g.length,5);
 assert.deepEqual(g.map(k=>k.id),['G1','G2','G3','G4','G5']);
 assert.equal(new Set(keys.map(k=>k.id)).size,keys.length);
 g.forEach((k,i)=>{assert.equal(k.slot,'PERKEY_GKEY');assert.equal(k.slotKey,String(i+1));assert.ok(k.x<0);assert.equal(k.y,1.3+i);});
});
test('G-key brightness is independent and every preset includes the new zone',()=>{
 for(const p of presets){const a=render(p,1),b=render(p,1,{zones:{gkeys:0}});
 for(const k of keys.filter(k=>!k.protected)){assert.equal(a[k.id].length,3);if(k.zone==='gkeys')assert.deepEqual(b[k.id],[0,0,0]);else assert.deepEqual(b[k.id],a[k.id]);}}
});
test('G-key interactions reach the main keyboard and main input reaches G keys',()=>{
 const linked=presets.filter(p=>p.gkeyFocus&&p.category==='reactive');assert.equal(linked.length,4);
 for(const p of linked){const base=render(p,.2),fromG=render(p,.2,{events:[{id:'G3',at:0}]}),fromMain=render(p,.2,{events:[{id:4,at:0}]});
 assert.ok(keys.filter(k=>!k.protected&&k.zone!=='gkeys').some(k=>JSON.stringify(base[k.id])!==JSON.stringify(fromG[k.id])),p.id+' G -> main');
 assert.ok(keys.filter(k=>k.zone==='gkeys').some(k=>JSON.stringify(base[k.id])!==JSON.stringify(fromMain[k.id])),p.id+' main -> G');
 assert.deepEqual(render(p,20,{events:[{id:'G3',at:0}]}),render(p,20));}
});
