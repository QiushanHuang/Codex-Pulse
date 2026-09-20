import {keys as layoutKeys} from './ambient-engine.mjs';

export const GHUB_PROVIDER=Object.freeze({id:'ghub',name:'Logitech G HUB',layoutId:'g913-full',capabilities:['per-key-rgb','quota-keys','numpad','logo','g-keys','temporary-viewer','idle-policy']});
const text=value=>typeof value==='string'?value.trim():'';
export const deviceKey=device=>text(device?.deviceSignature)?`ghub:${text(device.deviceSignature)}`:null;
const keyboards=devices=>(Array.isArray(devices)?devices:[]).filter(d=>d?.deviceType==='KEYBOARD');

export function describeDevices(devices){
 const all=keyboards(devices),counts=new Map(),ids=new Map();
 for(const device of all){const key=deviceKey(device);if(key)counts.set(key,(counts.get(key)??0)+1);const id=text(device.id);ids.set(id,(ids.get(id)??0)+1);}
 return all.map((device,index)=>{
  const model=text(device.deviceModel),key=deviceKey(device),connection=text(device.displayConnectionType),runtimeId=text(device.id);
  const exact=model.toLowerCase()==='g913';
  let support=exact?'verified':/^g915(?:$|[_-])/i.test(model)?'unverified':'unsupported';
  let reason=exact?'已验证 G913 完整布局；启用时检查实际键位。':support==='unverified'?'此型号尚未验证，请等待适配。':'此型号或布局尚不支持。';
  let selectable=exact;
  if(exact&&!['LIGHTSPEED','WIRED','USB'].includes(connection.toUpperCase())){selectable=false;reason='此连接方式尚未验证，请使用 LIGHTSPEED 或有线连接。';}
  if(device.state!=='ACTIVE'){selectable=false;reason='设备未连接或未激活。';}
  if(device.onboardMode){selectable=false;reason='请在 G HUB 关闭板载内存模式。';}
  if(!key||counts.get(key)!==1){selectable=false;reason=key?'设备标识重复，无法安全选择。':'设备未提供持久标识，无法安全选择。';}
  if(!runtimeId||ids.get(runtimeId)!==1){selectable=false;reason='设备运行标识缺失或重复，无法安全控制。';}
  return {id:`ghub:${runtimeId||'unknown'}:${index}`,key:key??'',name:text(device.displayName)||model||'未知键盘',model,provider:'ghub',connection,state:text(device.state)||'UNKNOWN',support,reason,selectable,layoutId:exact?'g913-full':null,capabilities:exact?[...GHUB_PROVIDER.capabilities]:[]};
 });
}

export function resolveSelectedDevice(devices,selectedKey){
 if(!text(selectedKey))throw Error('请选择要联动的键盘');
 const matches=keyboards(devices).filter(d=>deviceKey(d)===selectedKey);
 if(matches.length!==1)throw Error(matches.length?'设备标识重复，无法安全选择':'所选键盘暂未连接；不会切换到其他设备');
 const row=describeDevices(devices).find(d=>d.key===selectedKey);
 if(!row?.selectable)throw Error(row?.reason??'所选键盘不可用');
 return matches[0];
}

export function validateG913Layout(device,base){
 if(text(device?.deviceModel).toLowerCase()!=='g913')throw Error('此键盘型号或布局未验证');
 for(const key of layoutKeys){
  const id=String(key.id),slot=id==='logo'?'PERKEY_BRANDING':id.startsWith('G')?'PERKEY_GKEY':'PERKEY_KEYBOARD',address=id==='logo'?'1':id.startsWith('G')?id.slice(1):id;
  const color=base?.infoMap?.[slot]?.perKeyMap?.colorCodeMap?.[address];
  if(!color||!['red','green','blue'].every(c=>Number.isFinite(color.rgba?.[c])))throw Error(`键盘布局不完整或颜色数据无效：${slot}/${address}`);
 }
 return 'g913-full';
}

function recordedKey(record){
 if(!record)return null;
 if(![2,3].includes(record.version)||typeof record.owned!=='boolean')throw Error('键盘恢复记录无法识别，请检查后再开启联动');
 const key=text(record.signature)?`ghub:${record.signature}`:null;
 if(!key||(record.key&&record.key!==key))throw Error('键盘恢复标识无效，请检查恢复记录');
 return key;
}
function recoveryDevice(devices,key){
 const all=keyboards(devices),matches=all.filter(d=>deviceKey(d)===key);
 if(matches.length!==1||matches[0].state!=='ACTIVE'||!text(matches[0].id)||all.filter(d=>d.id===matches[0].id).length!==1)throw Error('原键盘尚未安全释放；请重新连接原设备并刷新');
 return matches[0];
}

// Owns a single transient viewer. Persistence precedes the first write because a
// successful device request can lose its response. Recovery must resolve identity
// again: G HUB runtime ids can change after reconnecting.
export class GHubKeyboardSession {
 constructor({hub,readRecord,writeRecord,clearRecord}){Object.assign(this,{hub,readRecord,writeRecord,clearRecord});this.device=null;this.base=null;this.owned=false;this.confirmed=false;}
 get activeKey(){return this.owned&&this.confirmed?deviceKey(this.device):null;}
 connectionLost(){this.confirmed=false;this.device=null;this.base=null;this.owned=false;}
 async viewerExists(device){
  try{await this.hub.call('GET','/lighting/viewer/state',{devices:[device.id]});return true;}
  catch(error){if(error.code==='INVALID_ARG')return false;throw error;}
 }
 async recover(devices){
  const record=this.readRecord();if(record==null)return;
  if(typeof record!=='object'||Array.isArray(record))throw Error('键盘恢复记录必须是对象');
  const key=recordedKey(record);
  if(record.owned){
   const target=recoveryDevice(devices,key);
   if(await this.viewerExists(target)){
    await this.hub.call('REMOVE','/lighting/viewer',{devices:[target.id]});
    if(await this.viewerExists(target))throw Error('灯效预览仍然存在；恢复记录已保留');
   }
  }
  this.clearRecord();this.owned=false;this.confirmed=false;this.device=null;this.base=null;
 }
 async release(devices){
  // Recover uses the durable record, not a possibly stale runtime id.
  await this.recover(devices);this.device=null;this.base=null;this.owned=false;this.confirmed=false;
 }
 async select(devices,key){
  if(this.device&&deviceKey(this.device)===key){
   let target;try{target=resolveSelectedDevice(devices,key);}catch(error){await this.release(devices);throw error;}
   if(this.device.id===target.id)return false;
  }
  await this.release(devices);
  const target=resolveSelectedDevice(devices,key);
  const base=await this.hub.call('GET',`/lighting/${target.id}/state`);
  validateG913Layout(target,base);
  if(await this.viewerExists(target))throw Error('G HUB 正在预览灯效；请结束预览后再开启状态灯');
  this.writeRecord({version:3,owned:false,key,model:target.deviceModel,signature:target.deviceSignature,state:base});
  this.device=target;this.base=base;this.owned=false;this.confirmed=false;return true;
 }
 async send(payload,update){
  if(!this.device)throw Error('尚未接管键盘');
  if(payload?.devices?.length!==1||payload.devices[0]!==this.device.id)throw Error('灯光目标与所选键盘不一致');
  if(this.owned){
   if(!this.confirmed)throw Error('上次灯光发送未确认，请先恢复原键盘');
   await update(this.hub,this.device.id,payload);
  }else{
   this.writeRecord({version:3,owned:true,key:deviceKey(this.device),model:this.device.deviceModel,signature:this.device.deviceSignature,state:this.base});
   this.owned=true;
   await this.hub.call('SET','/lighting/viewer',payload);
  }
  this.confirmed=true;
 }
}

// Requests and selection changes are coalesced with bounded periodic discovery.
// A connection error backs off without adding another resident process.
export class DeviceDiscovery {
 constructor({connect,write,now=()=>Date.now()/1000,interval=15}){Object.assign(this,{connect,write,now,interval});this.next=0;this.request=undefined;this.selection=undefined;this.devices=[];this.status='unavailable';this.message='等待设备发现';this.hub=null;}
 async refresh(config,activeKey=null,{force=false}={}){
  const now=this.now(),selectedKey=typeof config.selectedDeviceKey==='string'?config.selectedDeviceKey:null;
  const changed=this.request!==config.deviceScanRequest||this.selection!==selectedKey;
  this.request=config.deviceScanRequest;this.selection=selectedKey;
  if(!force&&!changed&&now<this.next)return false;
  this.next=now+this.interval;
  try{
   this.hub=await this.connect();
   const payload=await this.hub.call('GET','/devices/list');
   if(!Array.isArray(payload?.deviceInfos))throw Error('G HUB 返回的设备列表无效');
   this.devices=payload.deviceInfos;this.status='ready';this.message=this.devices.some(d=>d.deviceType==='KEYBOARD')?'设备列表已更新':'未发现键盘，请检查 G HUB 和设备连接';
  }catch(error){this.devices=[];this.status='unavailable';this.message=String(error.message);this.publish(null);throw error;}
  this.publish(activeKey);return true;
 }
 publish(activeKey){this.write({at:this.now(),status:this.status,message:this.message,devices:describeDevices(this.devices),selectedKey:this.selection??null,activeKey:activeKey??null});}
}
