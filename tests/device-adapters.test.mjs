import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {fileURLToPath} from 'node:url';

const device=(signature='a',extra={})=>({id:signature,deviceSignature:signature,deviceType:'KEYBOARD',deviceModel:'g913',displayName:'G913',displayConnectionType:'LIGHTSPEED',state:'ACTIVE',onboardMode:false,...extra});
const colors=ids=>({perKeyMap:{colorCodeMap:Object.fromEntries(ids.map(id=>[String(id),{rgba:{red:1,green:1,blue:1,alpha:1}}]))}});
const base={infoMap:{PERKEY_KEYBOARD:colors([...Array.from({length:98},(_,i)=>i+4),...Array.from({length:8},(_,i)=>i+224)]),PERKEY_BRANDING:colors([1]),PERKEY_GKEY:colors([1,2,3,4,5])}};
const adapterURL=new URL('../scripts/device-adapters.mjs',import.meta.url);
const load=async()=>{assert.ok(fs.existsSync(adapterURL),'identity-safe device adapter must exist');return import(adapterURL);};
function fixture(Session,devices=[device('a'),device('b')]){
 let record=null,failRemove=false,leaveViewer=false,failSet=false;const viewers=new Set(),calls=[];
 const hub={call:async(verb,path,payload={})=>{
  calls.push({verb,path,payload});const id=payload.devices?.[0];
  if(path==='/devices/list')return {deviceInfos:devices};
  if(path==='/lighting/viewer/state'){if(!viewers.has(id))throw Object.assign(Error('none'),{code:'INVALID_ARG'});return {};}
  if(verb==='GET'&&path.endsWith('/state'))return structuredClone(base);
  if(verb==='REMOVE'){if(failRemove)throw Error('release failed');if(!leaveViewer)viewers.delete(id);return {};}
  if(verb==='SET'&&path==='/lighting/viewer'){viewers.add(id);if(failSet)throw Error('response lost');return {};}
  return {};
 }};
 const session=new Session({hub,readRecord:()=>record,writeRecord:r=>{record=structuredClone(r);},clearRecord:()=>{record=null;}});
 return {session,hub,calls,viewers,get record(){return record;},set record(r){record=r;},set failRemove(v){failRemove=v;},set leaveViewer(v){leaveViewer=v;},set failSet(v){failSet=v;}};
}
test('inventory exposes only exact verified model and eligible transport with unique persistent identity',async()=>{
 const {describeDevices}=await load();
 const rows=describeDevices([device(),device('b',{deviceModel:'g915'}),device('c',{deviceModel:'g913_tkl'}),device('d',{displayConnectionType:'BLUETOOTH'}),device('e',{onboardMode:true}),device('f',{state:'INACTIVE'}),device('g',{deviceSignature:''})]);
 assert.equal(rows[0].key,'ghub:a');assert.equal(rows[0].selectable,true);assert.equal(rows[0].support,'verified');assert.equal(rows[0].layoutId,'g913-full');
 assert.equal(rows[1].support,'unverified');for(const row of rows.slice(1))assert.equal(row.selectable,false);
 const duplicates=describeDevices([device('a'),device('a',{id:'other'})]);assert.ok(duplicates.every(d=>!d.selectable));
 assert.equal(new Set(duplicates.map(d=>d.id)).size,2);
});
test('selection never falls back on absent, ambiguous or unsupported targets',async()=>{
 const {resolveSelectedDevice}=await load();const devices=[device('a'),device('b')];
 assert.equal(resolveSelectedDevice(devices,'ghub:b').id,'b');
 for(const key of [null,'ghub:missing'])assert.throws(()=>resolveSelectedDevice(devices,key));
 assert.throws(()=>resolveSelectedDevice([device('a'),device('a',{id:'z'})],'ghub:a'));
 assert.throws(()=>resolveSelectedDevice([device('a',{onboardMode:true})],'ghub:a'));
});
test('acquisition validates every known full-layout key and mandatory slots before writes',async()=>{
 const {validateG913Layout}=await load();assert.equal(validateG913Layout(device(),base),'g913-full');
 for(const [slot,key] of [['PERKEY_KEYBOARD','83'],['PERKEY_KEYBOARD','4'],['PERKEY_GKEY','5'],['PERKEY_BRANDING','1']]){
  const broken=structuredClone(base);delete broken.infoMap[slot].perKeyMap.colorCodeMap[key];assert.throws(()=>validateG913Layout(device(),broken));
 }
 assert.throws(()=>validateG913Layout(device('a',{deviceModel:'g913_tkl'}),base));
});
test('switching releases and verifies old viewer before acquiring new one; active identity follows successful send',async()=>{
 const {GHubKeyboardSession}=await load();const f=fixture(GHubKeyboardSession);const list=[device('a'),device('b')];
 await f.session.select(list,'ghub:a');assert.equal(f.session.activeKey,null);
 await f.session.send({devices:['a']});assert.equal(f.session.activeKey,'ghub:a');
 await f.session.select(list,'ghub:b');assert.equal(f.session.activeKey,null);await f.session.send({devices:['b']});assert.equal(f.session.activeKey,'ghub:b');
 const remove=f.calls.findIndex(c=>c.verb==='REMOVE');const acquireB=f.calls.findIndex(c=>c.path==='/lighting/b/state');assert.ok(remove>=0&&acquireB>remove);
 assert.deepEqual([...f.viewers],['b']);assert.equal(f.record.key,'ghub:b');
});
test('release errors and lingering viewers preserve recovery and block a new target',async()=>{
 const {GHubKeyboardSession}=await load();
 for(const failure of ['failRemove','leaveViewer']){
  const f=fixture(GHubKeyboardSession);await f.session.select([device('a')],'ghub:a');await f.session.send({devices:['a']});f[failure]=true;
  await assert.rejects(f.session.select([device('a'),device('b')],'ghub:b'));assert.equal(f.record.key,'ghub:a');assert.equal(f.record.owned,true);assert.equal(f.session.activeKey,'ghub:a');
  assert.ok(!f.calls.some(c=>c.path==='/lighting/b/state'));
 }
});
test('recovery targets recorded identity with changed runtime id, never first keyboard',async()=>{
 const {GHubKeyboardSession}=await load();const f=fixture(GHubKeyboardSession);f.record={version:2,owned:true,signature:'b',model:'g913'};f.viewers.add('new-b');
 await f.session.recover([device('a'),device('b',{id:'new-b'})]);assert.equal(f.record,null);
 assert.deepEqual(f.calls.filter(c=>c.verb==='REMOVE').map(c=>c.payload.devices),[['new-b']]);
});
test('offline or duplicate recovery identities block another selection and preserve records',async()=>{
 const {GHubKeyboardSession}=await load();
 for(const list of [[device('a')],[device('b'),device('b',{id:'new-b'})]]){
  const f=fixture(GHubKeyboardSession);f.record={version:3,owned:true,key:'ghub:b',signature:'b',model:'g913'};
  await assert.rejects(f.session.select(list,'ghub:a'));assert.ok(f.record);assert.equal(f.calls.filter(c=>c.verb!=='GET').length,0);
 }
});
test('uncertain send persists ownership before request and reconnect recovery prevents overlap',async()=>{
 const {GHubKeyboardSession}=await load();const f=fixture(GHubKeyboardSession);await f.session.select([device('a')],'ghub:a');f.failSet=true;
 await assert.rejects(f.session.send({devices:['a']}));assert.equal(f.record.owned,true);assert.equal(f.session.activeKey,null);
 f.session.connectionLost();assert.equal(f.session.activeKey,null);f.failSet=false;
 await f.session.select([device('a'),device('b')],'ghub:b');assert.equal(f.viewers.size,0);await f.session.send({devices:['b']});assert.deepEqual([...f.viewers],['b']);
});
test('deselecting or choosing an offline device releases the previous viewer without fallback',async()=>{
 const {GHubKeyboardSession}=await load();
 for(const selection of [null,'ghub:missing']){
  const f=fixture(GHubKeyboardSession);await f.session.select([device('a')],'ghub:a');await f.session.send({devices:['a']});
  await assert.rejects(f.session.select([device('a')],selection));assert.equal(f.session.activeKey,null);assert.equal(f.viewers.size,0);
 }
});
test('read-only discovery runs with lighting disabled, coalesces requests, and reports unavailable with no stale active target',async()=>{
 const {DeviceDiscovery}=await load();assert.equal(typeof DeviceDiscovery,'function');
 let now=100,reads=0,fail=false;const writes=[];
 const discovery=new DeviceDiscovery({now:()=>now,write:value=>writes.push(value),connect:async()=>({call:async(verb,path)=>{assert.equal(verb,'GET');assert.equal(path,'/devices/list');reads++;if(fail)throw Error('offline');return {deviceInfos:[device()]};}})});
 await discovery.refresh({lighting:false,selectedDeviceKey:'ghub:a'});assert.equal(reads,1);assert.equal(writes.at(-1).activeKey,null);
 now=101;await discovery.refresh({lighting:false,selectedDeviceKey:'ghub:a'});assert.equal(reads,1);
 await discovery.refresh({lighting:false,selectedDeviceKey:'ghub:a',deviceScanRequest:101});assert.equal(reads,2);
 now=116;await discovery.refresh({lighting:false,selectedDeviceKey:'ghub:a',deviceScanRequest:101});assert.equal(reads,3);
 fail=true;now=131;await assert.rejects(discovery.refresh({selectedDeviceKey:'ghub:a',deviceScanRequest:101},'ghub:a'));
 assert.equal(writes.at(-1).activeKey,null);assert.equal(writes.at(-1).selectedKey,'ghub:a');assert.equal(writes.at(-1).status,'unavailable');assert.deepEqual(writes.at(-1).devices,[]);
 now=132;await discovery.refresh({selectedDeviceKey:'ghub:a',deviceScanRequest:101});assert.equal(reads,4);
});
test('status command is strictly read-only even when a recovery record exists',async()=>{
 const {spawnSync}=await import('node:child_process');const os=await import('node:os');const path=await import('node:path');
 const directory=fs.mkdtempSync(path.join(os.tmpdir(),'pulse-adapter-status-'));
 const record={version:3,owned:true,key:'ghub:a',signature:'a',model:'g913'};
 fs.writeFileSync(path.join(directory,'config.json'),JSON.stringify({lighting:false,selectedDeviceKey:'ghub:a'}));
 fs.writeFileSync(path.join(directory,'keyboard-backup.json'),JSON.stringify(record));
 const prelude=`globalThis.WebSocket=class {static OPEN=1;constructor(){this.readyState=1;queueMicrotask(()=>this.onopen?.());}send(raw){const q=JSON.parse(raw);if(q.verb!=='GET'){console.error('UNEXPECTED DEVICE WRITE');throw Error('UNEXPECTED DEVICE WRITE');}let payload=q.path==='/devices/list'?{deviceInfos:[${JSON.stringify(device())}]}:{};queueMicrotask(()=>this.onmessage?.({data:JSON.stringify({msgId:q.msgId,result:{code:'SUCCESS'},payload})}));}close(){this.readyState=3;this.onclose?.();}};`;
 try{
  const result=spawnSync(process.execPath,['--import',`data:text/javascript,${encodeURIComponent(prelude)}`,fileURLToPath(new URL('../scripts/keyboard.mjs',import.meta.url)),'status',directory],{encoding:'utf8',timeout:5000});
  assert.equal(result.status,0,result.stderr);assert.equal(result.stderr,'');assert.deepEqual(JSON.parse(fs.readFileSync(path.join(directory,'keyboard-backup.json'))),record);
  assert.ok(!fs.existsSync(path.join(directory,'devices.json')),'read-only status must not overwrite the live worker inventory');assert.equal(JSON.parse(result.stdout).selectedKey,'ghub:a');
 }finally{fs.rmSync(directory,{recursive:true,force:true});}
});
test('run worker discovers while off and switches hardware plus leased previews with matching identity',async()=>{
 const {spawn}=await import('node:child_process');const os=await import('node:os');const path=await import('node:path');
 for(const {lighting,stale,blocked} of [{lighting:false},{lighting:true},{lighting:true,stale:true},{lighting:true,blocked:true}]){
  const directory=fs.mkdtempSync(path.join(os.tmpdir(),'pulse-adapter-run-'));
  const config={lighting,selectedDeviceKey:'ghub:a',lightSettings:{}};
  fs.writeFileSync(path.join(directory,'config.json'),JSON.stringify(config));
  fs.writeFileSync(path.join(directory,'preview-viewer.lease'),'');
  fs.writeFileSync(path.join(directory,'lighting-preview.json'),JSON.stringify({active:true,deviceKey:'ghub:previous-worker'}));
  fs.writeFileSync(path.join(directory,'snapshot.json'),JSON.stringify({generatedAt:stale?1:Date.now()/1000,quotaAt:Date.now()/1000,windows:[],tasks:[],events:[]}));
  if(blocked){fs.writeFileSync(path.join(directory,'keyboard.lock'),String(process.pid));fs.writeFileSync(path.join(directory,'keyboard-backup.json'),JSON.stringify({version:3,owned:true,key:'ghub:a',signature:'a',model:'g913'}));}
  const prelude=`import fs from 'node:fs';import dgram from 'node:dgram';import {EventEmitter} from 'node:events';
   dgram.createSocket=()=>Object.assign(new EventEmitter(),{bind(){},close(){}});
   const dir=${JSON.stringify(directory)},base=${JSON.stringify(base)},list=${JSON.stringify([device('a'),device('b')])},viewers=new Set(${blocked?'["a"]':'[]'});
   const rename=fs.renameSync;fs.renameSync=(from,to)=>{rename(from,to);if(to===dir+'/lighting-preview.json'||to===dir+'/devices.json'){const data=JSON.parse(fs.readFileSync(to));fs.appendFileSync(dir+'/publications.jsonl',JSON.stringify({type:to.endsWith('/devices.json')?'inventory':'preview',active:data.active,deviceKey:data.deviceKey,activeKey:data.activeKey})+'\\n');}};
   globalThis.WebSocket=class {static OPEN=1;constructor(){this.readyState=1;queueMicrotask(()=>this.onopen?.());}
    send(raw){const q=JSON.parse(raw),id=q.payload.devices?.[0];fs.appendFileSync(dir+'/calls.jsonl',JSON.stringify({verb:q.verb,path:q.path,id})+'\\n');
     let payload={},code='SUCCESS';if(q.path==='/devices/list')payload={deviceInfos:list};
     else if(q.path==='/lighting/viewer/state'){if(!viewers.has(id))code='INVALID_ARG';}
     else if(q.verb==='GET'&&q.path.endsWith('/power_saving'))payload={brightness:.5,inactivity:{seconds:60},sleep:{seconds:300}};
     else if(q.verb==='GET'&&q.path.endsWith('/state'))payload=base;
     else if(q.verb==='SET'&&q.path==='/lighting/viewer')viewers.add(id);
     else if(q.verb==='REMOVE')viewers.delete(id);
     queueMicrotask(()=>this.onmessage?.({data:JSON.stringify({msgId:q.msgId,result:{code},payload})}));}
    close(){this.readyState=3;this.onclose?.();}};
   setTimeout(()=>fs.writeFileSync(dir+'/config.json',JSON.stringify({...${JSON.stringify(config)},selectedDeviceKey:'ghub:b',deviceScanRequest:1})),650);
   setTimeout(()=>fs.writeFileSync(dir+'/config.json',JSON.stringify({...${JSON.stringify(config)},selectedDeviceKey:null,deviceScanRequest:2})),1900);
   setTimeout(()=>process.kill(process.pid,'SIGTERM'),3200);`;
  try{
   const child=spawn(process.execPath,['--import',`data:text/javascript,${encodeURIComponent(prelude)}`,fileURLToPath(new URL('../scripts/keyboard.mjs',import.meta.url)),'run',directory],{stdio:['ignore','pipe','pipe']});
   let stderr='';child.stderr.on('data',d=>stderr+=d);const exit=await new Promise((resolve,reject)=>{const timer=setTimeout(()=>{child.kill('SIGKILL');reject(Error('fake worker timeout'));},7000);child.on('error',reject);child.on('exit',code=>{clearTimeout(timer);resolve(code);});});
   assert.equal(exit,0,stderr);assert.equal(stderr,'');
   const calls=fs.readFileSync(path.join(directory,'calls.jsonl'),'utf8').trim().split('\n').map(JSON.parse),writes=calls.filter(c=>c.verb!=='GET');
   if(!lighting||stale||blocked){assert.deepEqual(writes,[]);assert.ok(!calls.some(c=>/^\/lighting\/[ab]\/state$/.test(c.path)),'off/stale worker must not repeatedly acquire lighting state');}
   else{
    assert.deepEqual(writes.filter(c=>c.path==='/lighting/viewer').map(c=>[c.verb,c.id]),[['SET','a'],['REMOVE','a'],['SET','b'],['REMOVE','b']]);
    assert.ok(!fs.existsSync(path.join(directory,'keyboard-backup.json')));
    const publications=fs.readFileSync(path.join(directory,'publications.jsonl'),'utf8').trim().split('\n').map(JSON.parse);
    const activePreviews=publications.filter(p=>p.type==='preview'&&p.active);
    assert.deepEqual(activePreviews.map(p=>p.deviceKey),['ghub:a','ghub:b']);
    const firstActive=publications.findIndex(p=>p.type==='inventory'&&p.activeKey);
    assert.ok(publications.slice(0,firstActive).some(p=>p.type==='preview'&&p.active===false),'a prior worker preview must clear before the first new active target');
    const bActive=publications.findIndex(p=>p.type==='inventory'&&p.activeKey==='ghub:b');
    const aPreview=publications.findIndex(p=>p.type==='preview'&&p.deviceKey==='ghub:a');
    assert.ok(publications.slice(aPreview+1,bActive).some(p=>p.type==='preview'&&p.active===false),'old preview must clear before B is claimed active');
    for(const [index,p] of publications.entries())if(p.type==='preview'&&p.active){
     const active=publications.slice(0,index).filter(e=>e.type==='inventory').at(-1)?.activeKey;
     assert.equal(p.deviceKey,active,'published preview must belong to the confirmed active device');
    }
   }
   if(blocked)assert.equal(JSON.parse(fs.readFileSync(path.join(directory,'keyboard-backup.json'))).owned,true);
   const inventory=JSON.parse(fs.readFileSync(path.join(directory,'devices.json')));assert.equal(inventory.devices.length,2);assert.equal(inventory.selectedKey,null);assert.equal(inventory.activeKey,null);
  }finally{fs.rmSync(directory,{recursive:true,force:true});}
 }
});
test('restore rejects present primitive and array recovery files without replacing bytes or writing hardware',async()=>{
 const {spawnSync}=await import('node:child_process');const os=await import('node:os');const path=await import('node:path');
 for(const value of [null,false,0,[],true,'record']){
  const directory=fs.mkdtempSync(path.join(os.tmpdir(),'pulse-adapter-record-')),original=JSON.stringify(value);
  fs.writeFileSync(path.join(directory,'keyboard-backup.json'),original);
  const prelude=`globalThis.WebSocket=class {static OPEN=1;constructor(){this.readyState=1;queueMicrotask(()=>this.onopen?.());}send(raw){const q=JSON.parse(raw);if(q.verb!=='GET'){console.error('UNEXPECTED WRITE');throw Error('UNEXPECTED WRITE');}queueMicrotask(()=>this.onmessage?.({data:JSON.stringify({msgId:q.msgId,result:{code:'SUCCESS'},payload:{deviceInfos:[${JSON.stringify(device())}]}})}));}close(){this.readyState=3;this.onclose?.();}};`;
  try{
   const result=spawnSync(process.execPath,['--import',`data:text/javascript,${encodeURIComponent(prelude)}`,fileURLToPath(new URL('../scripts/keyboard.mjs',import.meta.url)),'restore',directory],{encoding:'utf8',timeout:5000});
   assert.equal(result.status,1,'present '+original+' must not count as an absent record');assert.match(result.stderr,/恢复记录/);assert.doesNotMatch(result.stderr,/UNEXPECTED WRITE/);
   assert.equal(fs.readFileSync(path.join(directory,'keyboard-backup.json'),'utf8'),original);
  }finally{fs.rmSync(directory,{recursive:true,force:true});}
 }
});
test('preview input validates current selection and active identity and never replays A input on B',async()=>{
 const {spawn}=await import('node:child_process');const os=await import('node:os');const path=await import('node:path');
 const directory=fs.mkdtempSync(path.join(os.tmpdir(),'pulse-adapter-input-'));
 const config={lighting:true,selectedDeviceKey:'ghub:a',lightSettings:{ambientEnabled:true,ambientPreset:'echo',ambientInputEnabled:false}};
 fs.writeFileSync(path.join(directory,'config.json'),JSON.stringify(config));
 fs.writeFileSync(path.join(directory,'snapshot.json'),JSON.stringify({generatedAt:Date.now()/1000,quotaAt:Date.now()/1000,windows:[],tasks:[],events:[]}));
 const prelude=`import fs from 'node:fs';import dgram from 'node:dgram';import {EventEmitter} from 'node:events';
  const dir=${JSON.stringify(directory)},base=${JSON.stringify(base)},list=${JSON.stringify([device('a'),device('b')])},viewers=new Set(),start=Date.now();
  let socket;dgram.createSocket=()=>socket=Object.assign(new EventEmitter(),{bind(){},close(){}});
  const input=key=>socket.emit('message',Buffer.from(JSON.stringify({source:'preview',deviceKey:key,id:4})),{address:'127.0.0.1'});
  globalThis.WebSocket=class {static OPEN=1;constructor(){this.readyState=1;queueMicrotask(()=>this.onopen?.());}
   send(raw){const q=JSON.parse(raw),id=q.payload.devices?.[0];
    fs.appendFileSync(dir+'/calls.jsonl',JSON.stringify({at:Date.now()-start,verb:q.verb,path:q.path,id})+'\\n');
    let payload={},code='SUCCESS';if(q.path==='/devices/list')payload={deviceInfos:list};
    else if(q.path==='/lighting/viewer/state'){if(!viewers.has(id))code='INVALID_ARG';}
    else if(q.verb==='GET'&&q.path.endsWith('/power_saving'))payload={brightness:.5,inactivity:{seconds:60},sleep:{seconds:300}};
    else if(q.verb==='GET'&&q.path.endsWith('/state'))payload=base;
    else if(q.verb==='SET'&&q.path==='/lighting/viewer')viewers.add(id);
    else if(q.verb==='REMOVE')viewers.delete(id);
    queueMicrotask(()=>this.onmessage?.({data:JSON.stringify({msgId:q.msgId,result:{code},payload})}));}
   close(){this.readyState=3;this.onclose?.();}};
  setTimeout(()=>input('ghub:b'),120);
  setTimeout(()=>input(undefined),200);
  setTimeout(()=>input('ghub:a'),650);
  setTimeout(()=>{fs.writeFileSync(dir+'/config.json',JSON.stringify({...${JSON.stringify(config)},selectedDeviceKey:'ghub:b'}));input('ghub:a');},1100);
  setTimeout(()=>input('ghub:a'),1500);
  setTimeout(()=>process.kill(process.pid,'SIGTERM'),2200);`;
 try{
  const child=spawn(process.execPath,['--import',`data:text/javascript,${encodeURIComponent(prelude)}`,fileURLToPath(new URL('../scripts/keyboard.mjs',import.meta.url)),'run',directory],{stdio:['ignore','pipe','pipe']});
  let stderr='';child.stderr.on('data',d=>stderr+=d);const exit=await new Promise((resolve,reject)=>{const timer=setTimeout(()=>{child.kill('SIGKILL');reject(Error('input fake worker timeout'));},5000);child.on('error',reject);child.on('exit',code=>{clearTimeout(timer);resolve(code);});});
  assert.equal(exit,0,stderr);assert.equal(stderr,'');
  const calls=fs.readFileSync(path.join(directory,'calls.jsonl'),'utf8').trim().split('\n').map(JSON.parse),updates=calls.filter(c=>c.path==='/lighting/viewer/update'&&c.verb==='SET');
  assert.ok(!updates.some(c=>c.at<600),'mismatched or unbound preview input must be ignored');
  assert.ok(updates.some(c=>c.id==='a'&&c.at>=650),'matching A preview input must animate');
  assert.ok(!updates.some(c=>c.id==='b'),'A input must not be replayed after selecting B');
 }finally{fs.rmSync(directory,{recursive:true,force:true});}
});
