import {DeviceDiscovery,GHubKeyboardSession,deviceKey} from './device-adapters.mjs';
import {JsonFileCache,PreviewPublisher,WakeSignal} from './runtime-efficiency.mjs';
export {JsonFileCache,PreviewPublisher,WakeSignal};
import dgram from 'node:dgram';
import {presets as ambientPresets,palettes as ambientPalettes,profiles as ambientProfiles,zoneNames,keys as ambientKeys,render as renderAmbient} from './ambient-engine.mjs';
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

export function colorsEqual(a,b){
  // Protobuf maps can change iteration order. Hardware reports 8-bit RGB.
  for(const [slot,info] of Object.entries(a.infoMap??{})){
    for(const [key,c] of Object.entries(info.perKeyMap?.colorCodeMap??{})){
      const d=b.infoMap?.[slot]?.perKeyMap?.colorCodeMap?.[key];
      if(!d || ['red','green','blue'].some(k=>!Number.isFinite(c.rgba?.[k])||!Number.isFinite(d.rgba?.[k])||
        Math.abs(Math.round(c.rgba[k]*255)-Math.round(d.rgba[k]*255))>1))return false;
    }
  }
  return true;
}

export function chooseKeyboard(devices) {
  return devices.find(d => d.deviceType === 'KEYBOARD' && /^g91[35](?:_|-|$)/i.test(d.deviceModel) && d.state === 'ACTIVE' && !d.onboardMode) ?? null;
}

function hardwareSlots(frame){
  const infoMap=structuredClone(frame.infoMap);
  for(const info of Object.values(infoMap))for(const [key,color]of Object.entries(info.perKeyMap?.colorCodeMap??{})){
    if(color.rgba){
      const hex='#'+['red','green','blue'].map(c=>Math.round(Math.min(1,Math.max(0,color.rgba[c]))*255).toString(16).padStart(2,'0')).join('').toUpperCase();
      info.perKeyMap.colorCodeMap[key]={hex,tag:color.tag??''};
    }
  }
  return {infoMap};
}

export function viewerPayload(deviceId,frame){
  const deviceSupport=['KEYBOARD_RGB_PER_KEY'];
  return {devices:[deviceId],effectPackage:{info:{deviceSupport,fixedInfo:{lightingSlots:hardwareSlots(frame)}}},
    effectMetadata:{deviceSupport,fixedMetadata:{}},actionType:'START',streaming:{enabled:true}};
}

export function animationPayload(deviceId,frames,speed=20,length=5){
  const deviceSupport=['KEYBOARD_RGB_PER_KEY'];
  const keyframeMap=Object.fromEntries(frames.map((frame,i)=>[String(i),{curveType:'LINEAR',length,lightingSlots:hardwareSlots(frame)}]));
  return {devices:[deviceId],effectPackage:{info:{deviceSupport,keyframeInfo:{keyframeMap,speed,direction:'CYCLE'}}},
    effectMetadata:{deviceSupport,keyframeMetadata:{index:0,speed,direction:'CYCLE',loops:0}},actionType:'START',streaming:{enabled:true}};
}

function rgba(r,g,b,scale=1) { return {rgba:{red:r*scale,green:g*scale,blue:b*scale,alpha:1},tag:''}; }

// Apple IOHIDUsageTables.h + the connected G913's actual per-key map.
export const QUOTA_KEYS=Array.from({length:10},(_,i)=>58+i);
export const NUMPAD_KEYS=Array.from({length:17},(_,i)=>83+i);
const PAD_ROW={98:0,99:0,88:.7,89:1,90:1,91:1,92:2,93:2,94:2,87:2.5,95:3,96:3,97:3,83:4,84:4,85:4,86:4};
const PRIORITY={reset:3,failed:2,interrupted:2,completed:1};
export const RUNNING_STYLES=['classic','wave','pulse','ripple','comet'];
export function runningStyleFor(count,options={}){return normalizeSettings(options)['mode'+Math.max(1,Math.min(4,count))];}
const STYLE_NAMES={classic:['经典外圈','经典双区','等距上行','斜线平移'],wave:['柔光环浪','上下交叠','错峰潮汐','四排柔浪'],pulse:['环形心跳','双区呼应','三拍律动','四拍轮动'],ripple:['中心涟漪','双心涟漪','斜向涟漪','水波横移'],comet:['流星拖尾','双星环绕','三道流光','四道星轨']};
export function previewPacket(plan,startedAt){
  const keys=ambientKeys.map(k=>String(k.id));
  const packed=c=>{const a=c?.rgba??{red:0,green:0,blue:0};return(Math.round(a.red*255)<<16)|(Math.round(a.green*255)<<8)|Math.round(a.blue*255);};
  return {version:1,active:true,startedAt,mode:plan.mode,style:plan.style,taskCount:plan.activeCount,
    frameSeconds:hardwareFrameSeconds(plan.length,plan.speed),keys,
    frames:plan.frames.map(f=>keys.map(k=>packed(k==='logo'?f.infoMap.PERKEY_BRANDING?.perKeyMap?.colorCodeMap?.['1']:k.startsWith('G')?f.infoMap.PERKEY_GKEY?.perKeyMap?.colorCodeMap?.[k.slice(1)]:f.infoMap.PERKEY_KEYBOARD?.perKeyMap?.colorCodeMap?.[k])))};
}
const PAD_POSITION={98:[.5,0],99:[2,0],88:[3,.5],89:[0,1],90:[1,1],91:[2,1],92:[0,2],93:[1,2],94:[2,2],87:[3,2.5],95:[0,3],96:[1,3],97:[2,3],83:[0,4],84:[1,4],85:[2,4],86:[3,4]};
const tau=2*Math.PI,wrap=x=>((x%1)+1)%1;
function rhythmEnergy(style,count,phase){
  const t=wrap(phase/64),output=new Map(),groups=runningGroups(count);
  const bell=(value,center,width)=>{const d=Math.min(wrap(value-center),wrap(center-value));return Math.exp(-d*d/(width*width));};
  if(style==='ripple'){
    const origins=count===1?[[1,2]]:count===2?[[0,1],[2,3]]:count===3?[[0,0],[1,1],[2,0]]:[[0,0],[2,0],[0,4],[2,4]];
    for(const id of NUMPAD_KEYS){const [x,y]=PAD_POSITION[id];let e=0;
      origins.forEach(([cx,cy],i)=>{const age=wrap(t-i/origins.length),radius=age*5.2;
        const ring=Math.exp(-Math.pow(Math.hypot(x-cx,y-cy)-radius,2)/.55)*Math.pow(Math.sin(Math.PI*age),.35);
        e=Math.max(e,ring);});output.set(id,e);
    }
  }else{
    groups.forEach((group,g)=>group.forEach((id,i)=>{
      const u=i/group.length;let e;
      if(style==='wave'){
        const advance=t+.085*Math.sin(tau*t+g*.9)-g*.21;
        const swell=.55+.45*(.5+.5*Math.sin(tau*t-g*.8));
        e=Math.pow(.5+.5*Math.cos(tau*(u-advance)),1.35)*swell;
      }else if(style==='pulse'){
        const beat=wrap(t-g*.19-u*.09);
        e=Math.min(1,bell(beat,.14,.08)+.64*bell(beat,.36,.11))*(.78+.22*Math.cos(Math.PI*(u-.5)));
      }else{
        const head=wrap(t+.07*Math.sin(tau*t)-g*.17),behind=wrap(head-u);
        e=Math.max(bell(u,head,.065),.58*Math.exp(-behind/.20),.22*bell(u,wrap(head+.5),.10));
      }
      output.set(id,Math.max(0,Math.min(1,e)));
    }));
    for(const id of NUMPAD_KEYS)if(!output.has(id))output.set(id,.10+.12*(.5+.5*Math.sin(tau*t+id*.37)));
  }
  return output;
}

export function runningGroups(count){
  if(count<=0)return [];
  if(count===1)return [[98,89,92,95,96,97,94,91,99]];
  if(count===2)return [[89,92,93,94,91,90],[95,83,84,85,97,96]];
  if(count>=4)return [[83,84,85],[95,96,97],[92,93,94],[89,90,91]];
  return [[89,92,95,83],[90,93,96,84],[91,94,97,85]];
}
export function runningHeads(count,phase){
  const progress=phase/64;
  if(count===3)return [0,1,2].map(offset=>progress*4+offset);
  if(count>=4)return [0,2/3,4/3,2].map(offset=>progress*3+offset);
  return runningGroups(count).map((group,i)=>(progress-i/2)*group.length);
}
export function normalizeSettings(value={}){
  const number=(key,fallback,min=0,max=1)=>Number.isFinite(value?.[key])?Math.max(min,Math.min(max,value[key])):fallback;
  const idleAfterSeconds=Math.round(number('idleAfterSeconds',60,30,1800));
  const sleepAfterSeconds=Math.max(idleAfterSeconds+30,Math.round(number('sleepAfterSeconds',300,60,7200)));
  const style=(key,fallback)=>RUNNING_STYLES.includes(value?.[key])?value[key]:fallback;
  const ambientPreset=ambientPresets.find(p=>p.id===(value?.ambientPreset??'g-ladder'));
  const ambientZones=Object.fromEntries(Object.keys(zoneNames).filter(k=>Number.isFinite(value?.ambientZones?.[k])).map(k=>[k,Math.max(0,Math.min(1,value.ambientZones[k]))]));
  return {ambientEnabled:value?.ambientEnabled===true&&Boolean(ambientPreset),ambientPreset:ambientPreset?.id??'g-ladder',
    ambientPalette:ambientPalettes[value?.ambientPalette]?value.ambientPalette:ambientPreset?.palette??'glacier',
    ambientProfile:ambientProfiles[value?.ambientProfile]?value.ambientProfile:ambientPreset?.profile??'balanced',
    ambientPeriod:number('ambientPeriod',ambientPreset?.period??12,1,24),ambientZones,
    ambientInputEnabled:value?.ambientInputEnabled===true,
    globalBrightness:number('globalBrightness',1),quotaBrightness:number('quotaBrightness',1),
    logoBrightness:number('logoBrightness',1),keypadBrightness:number('keypadBrightness',1),otherBrightness:number('otherBrightness',1),
    cycleSeconds:number('cycleSeconds',12,2,30),otherColorEnabled:value?.otherColorEnabled===true,
    otherColor:/^#[0-9a-f]{6}$/i.test(value?.otherColor)?value.otherColor.toUpperCase():'#FFC284',
    lowAlertEnabled:value?.lowAlertEnabled!==false,idleAfterSeconds,sleepAfterSeconds,idleBrightness:number('idleBrightness',.5),
    mode1:style('mode1','comet'),mode2:style('mode2','wave'),mode3:style('mode3','wave'),mode4:style('mode4','ripple')};
}
export function powerPolicy(options={}){
  const s=normalizeSettings(options);
  return {brightness:s.idleBrightness,inactivity:{seconds:s.idleAfterSeconds},sleep:{seconds:s.sleepAfterSeconds}};
}
export function policyMatches(actual,expected){
  const seconds=t=>(Number(t?.seconds)||0)+(Number(t?.minutes)||0)*60+(Number(t?.hours)||0)*3600+(Number(t?.milliseconds)||0)/1000;
  return Number.isFinite(actual?.brightness)&&Math.abs(actual.brightness-expected.brightness)<.005&&
    seconds(actual.inactivity)===expected.inactivity.seconds&&seconds(actual.sleep)===expected.sleep.seconds;
}
export class PowerPolicyController {
  constructor(hub,device){this.hub=hub;this.device=device;this.key=null;this.applied=null;}
  async apply(options){
    const desired=powerPolicy(options),key=JSON.stringify(desired);
    if(key===this.key)return this.applied;
    const path=`/lighting/${this.device.id}/power_saving`;
    let actual=await this.hub.call('GET',path);
    if(!policyMatches(actual,desired)){
      await this.hub.call('SET',path,desired);
      actual=await this.hub.call('GET',path);
      if(!policyMatches(actual,desired))throw Error('键盘省电设置读回与选择不一致');
      // Wake only on an explicit policy change, never on each monitoring tick.
      await this.hub.call('SET',`/lighting/${this.device.id}/mode/wake`,{});
    }
    this.key=key;this.applied=desired;return desired;
  }
}

function applyBrightness(frame,settings){
  const ambient=[1,3,5].map(start=>parseInt(settings.otherColor.slice(start,start+2),16)/255);
  for(const [slot,info]of Object.entries(frame.infoMap??{})){
    const colors=info.perKeyMap?.colorCodeMap??{};
    for(const [key,color]of Object.entries(colors)){
      const id=Number(key);
      const zone=slot==='PERKEY_BRANDING'&&id===1?'logo':slot==='PERKEY_KEYBOARD'&&QUOTA_KEYS.includes(id)?'quota':
        slot==='PERKEY_KEYBOARD'&&NUMPAD_KEYS.includes(id)?'keypad':'other';
      const multiplier=settings.globalBrightness*settings[zone+'Brightness'];
      const original=color.rgba??{red:0,green:0,blue:0,alpha:1};
      const rgb=zone==='other'&&settings.otherColorEnabled?ambient:[original.red,original.green,original.blue];
      const adjusted={...color,rgba:{red:rgb[0]*multiplier,green:rgb[1]*multiplier,blue:rgb[2]*multiplier,alpha:1}};
      delete adjusted.hex;colors[key]=adjusted;
    }
  }
  return frame;
}

export function lightingState(snapshot,now){
  const windows=(snapshot.windows??[]).filter(w=>w.bucket==='codex'&&Number.isFinite(w.remaining));
  const remaining=windows.length?Math.min(...windows.map(w=>w.remaining)):null;
  const dataFresh=now-(snapshot.generatedAt??now)<30;
  const fresh=Boolean(snapshot.quotaAt&&now-snapshot.quotaAt<180&&dataFresh&&!snapshot.quotaError&&remaining!==null);
  const activeCount=dataFresh&&!snapshot.taskError?(snapshot.tasks??[]).filter(t=>t.status==='active').length:0;
  const active=activeCount>0;
  const events=(snapshot.events??[]).filter(e=>now-e.at>=0&&now-e.at<8&&PRIORITY[e.kind]);
  const event=events.sort((a,b)=>PRIORITY[b.kind]-PRIORITY[a.kind]||b.at-a.at)[0];
  const age=event?now-event.at:0;
  const mode=event?.kind==='reset'?(age<2?'reset-flash':'reset-glow'):
    event?.kind==='completed'?(age<4.5?'complete-wave':'complete-settle'):
    event&&['failed','interrupted'].includes(event.kind)?'attention':active?'running':'idle';
  return {windows,remaining,fresh,active,activeCount,event,mode};
}

export function frameFor(base,snapshot,now,phase,options={}){
  const settings=normalizeSettings(options);
  const frame=structuredClone(base);frame.persistent=false;delete frame['@type'];
  const slots=frame.infoMap?.PERKEY_KEYBOARD?.perKeyMap?.colorCodeMap??{};
  const logo=frame.infoMap?.PERKEY_BRANDING?.perKeyMap?.colorCodeMap;
  if(snapshot.brightnessTest===true){
    for(const info of Object.values(frame.infoMap??{}))for(const key of Object.keys(info.perKeyMap?.colorCodeMap??{}))
      info.perKeyMap.colorCodeMap[key]=rgba(1,1,1);
    return frame;
  }
  const state=lightingState(snapshot,now),{remaining,fresh,mode}=state;
  const put=(id,color)=>{if(String(id) in slots)slots[String(id)]=color;};
  const pulse=(1-Math.cos(phase*Math.PI/8))/2;
  // Each key is 10%; a partial final segment is dimmed. All animation states leave this bar stable.
  QUOTA_KEYS.forEach((id,i)=>{
    const fill=Math.max(0,Math.min(1,(remaining??0)/10-i));
    put(id,!fresh?rgba(.16,.16,.16):fill>0?rgba(.1,1,.75,fill):rgba(.03,.035,.04));
  });
  if(logo?.['1'])logo['1']=!fresh?rgba(.16,.16,.16):remaining<=25?
    (settings.lowAlertEnabled?rgba(1,.015,.008):rgba(0,0,0)):rgba(.1,1,.8);
  NUMPAD_KEYS.forEach(id=>put(id,rgba(.1,.23,.32,.2)));
  if(mode==='reset-flash'){
    const flash=phase%2===0?rgba(.72,.4,1):rgba(.015,.01,.025);
    if(logo?.['1'])logo['1']=flash;NUMPAD_KEYS.forEach(id=>put(id,flash));
  }else if(mode==='reset-glow'){
    const glow=rgba(.65,.24,1,.25+.55*pulse);
    if(logo?.['1'])logo['1']=glow;NUMPAD_KEYS.forEach(id=>put(id,glow));
  }else if(mode==='running'){
    const style=runningStyleFor(state.activeCount,settings);
    if(style!=='classic'){
      for(const [id,energy]of rhythmEnergy(style,Math.min(4,state.activeCount),phase)){
        const e=Math.sqrt(Math.max(0,Math.min(1,energy)));
        put(id,rgba(.10+.34*e,.58+.42*e,1,.16+.84*e));
      }
    }else{
    const progress=((phase%64)+64)%64/64;
    // Center keys cannot belong to the outside orbit without a jump across the keypad.
    if(state.activeCount===1)[90,93].forEach((id,i)=>put(id,rgba(.12,.6,1,.12+.12*(1+Math.sin(progress*2*Math.PI+i*Math.PI))/2)));
    runningGroups(state.activeCount).forEach((group,groupIndex)=>{
      const rawHead=runningHeads(state.activeCount,phase)[groupIndex];
      const head=((rawHead%group.length)+group.length)%group.length;
      group.forEach((id,index)=>{
        let energy;
        if(state.activeCount>=3){
          const behind=(head-index+group.length)%group.length;
          const ahead=(index-head+group.length)%group.length;
          const distance=Math.min(behind,ahead);
          // Symmetric head preserves fractional position; a softer trailing component
          // joins neighboring keys without shifting the diagonal's apparent crest.
          energy=(Math.exp(-distance*distance/.38)+.22*Math.exp(-behind/1.1))/1.22;
        }else{
          const behind=(head-index+group.length)%group.length;
          const ahead=(index-head+group.length)%group.length;
          energy=Math.max(Math.exp(-behind*behind/1.5),.55*Math.exp(-ahead*ahead/.32));
        }
        // A slightly pale head, saturated blue trailing light, then a quiet background.
        put(id,rgba(.12+.25*energy,.45+.50*energy,1,.08+.92*energy));
      });
    });
    }
  }else if(mode==='complete-wave'){
    const row=(phase%16)/15*5;
    NUMPAD_KEYS.forEach(id=>put(id,rgba(.2,1,.5,.1+.9*Math.exp(-Math.pow(PAD_ROW[id]-row,2)/.5))));
  }else if(mode==='complete-settle'){
    NUMPAD_KEYS.forEach(id=>put(id,rgba(.1,1,.4,.25)));
    const confirm=rgba(.45,1,.7,.25+.75*Math.pow((1-Math.cos(phase*Math.PI/4))/2,2));
    put(87,confirm);put(88,confirm);
  }else if(mode==='attention'){
    NUMPAD_KEYS.forEach(id=>put(id,rgba(1,.27,.04,.12+.35*pulse)));
    put(88,rgba(1,.12,.03,.3+.7*pulse));
  }
  return applyBrightness(frame,settings);
}

export function renderPlan(base,snapshot,now,options={},previousKey=null){
  const settings=normalizeSettings(options);
  if(settings.ambientEnabled&&!snapshot.brightnessTest)return ambientPlan(base,snapshot,now,settings,previousKey);
  const state=lightingState(snapshot,now);
  let phases,length=1,speed=180;
  if(snapshot.brightnessTest===true){state.mode='brightness-test';phases=[0];}
  else if(state.mode==='reset-flash'){phases=[0,0,1,1];length=1;speed=100;}
  else if(state.mode==='running'){
    phases=Array.from({length:64},(_,i)=>i);length=5;
    // G HUB speed is a frame-interval multiplier in milliseconds, not frames/second.
    // Floor before the device's rendering tick quantization (verified by live RGB sampling).
    speed=Math.floor(settings.cycleSeconds*1000/(64*length));
  }else if(state.mode==='complete-wave'){phases=Array.from({length:16},(_,i)=>i);length=1;speed=80;}
  else if(state.mode!=='idle'){phases=Array.from({length:16},(_,i)=>i);}
  else phases=[0];
  const {idleAfterSeconds,idleBrightness,sleepAfterSeconds,...visualSettings}=settings;
  const key=JSON.stringify({remaining:state.remaining,fresh:state.fresh,mode:state.mode,activeCount:state.activeCount,event:state.event?.at??null,speed,settings:visualSettings});
  // G HUB already plays these frames; only materialize a changed effect.
  const frames=key===previousKey?[]:phases.map(phase=>frameFor(base,snapshot,now,phase,settings));
  return {frames,length,speed,key,mode:state.mode,activeCount:state.activeCount,style:runningStyleFor(state.activeCount,settings)};
}


function hardwareFrameSeconds(length,speed){return Math.max(.032,Math.ceil(length*speed/32)*.032);}
function ambientFunctionalPhase(state,at,settings){
 const age=state.event ? at-state.event.at:at;
 // The same device tick quantization drives cached cycles, streaming and the preview.
 const duration=64*hardwareFrameSeconds(5,Math.floor(settings.cycleSeconds*1000/(64*5)));
 return state.mode==='running' ? ((at%duration)/duration)*64:
   state.mode==='reset-flash' ? Math.floor(age/.2)%2:state.mode==='complete-wave' ? age/.08:age/.18;
}

function applyAmbientColors(frame,colors,settings){
 const gain=settings.globalBrightness*settings.otherBrightness;
 for(const k of ambientKeys){if(k.protected)continue;
   const slot=k.slot??'PERKEY_KEYBOARD',id=k.slotKey??String(k.id),map=frame.infoMap?.[slot]?.perKeyMap?.colorCodeMap;
   if(map&&id in map){const c=colors[k.id];map[id]=rgba(c[0]/255,c[1]/255,c[2]/255,gain);}
 }
}

export function ambientPlan(base,snapshot,now,settings,previousKey){
 const preset=ambientPresets.find(p=>p.id===settings.ambientPreset),state=lightingState(snapshot,now);
 const events=(snapshot.ambientEvents??[]).filter(e=>now-e.at>=0&&now-e.at<8).slice(-64);
 // Static backgrounds and resting reactive effects do not need a streaming clock.
 // Compose once with the existing full-cycle functional animation and let G HUB loop it.
 if(preset.category!=='loop' && events.length===0 && ['running','idle'].includes(state.mode)){
   let previous;try{previous=JSON.parse(previousKey);}catch{}
   const functionalSettings={...settings,ambientEnabled:false,otherColorEnabled:false};
   let functional=renderPlan(base,snapshot,now,functionalSettings,previous?.functionalKey);
   const {idleAfterSeconds,idleBrightness,sleepAfterSeconds,...visual}=settings;
   const key=JSON.stringify({ambient:visual,functionalKey:functional.key});
   if(key===previousKey)return {...functional,key,frames:[],pollMs:500};
   if(!functional.frames.length)functional=renderPlan(base,snapshot,now,functionalSettings);
   const colors=renderAmbient(preset,now,{palette:settings.ambientPalette,profile:settings.ambientProfile,period:settings.ambientPeriod,zones:settings.ambientZones,events:[]});
   if(state.mode==='running'){
     const dt=hardwareFrameSeconds(functional.length,functional.speed);
     functional.frames=functional.frames.map((_,i)=>frameFor(base,snapshot,now,ambientFunctionalPhase(state,now+i*dt,settings),functionalSettings));
   }
   for(const frame of functional.frames)applyAmbientColors(frame,colors,settings);
   return {...functional,key,pollMs:500};
 }
 const realtime=preset.category==='reactive' && (events.length>0 || Boolean(state.event));
 const moving=preset.category==='loop'||(preset.category==='reactive'&&events.length>0)||state.mode!=='idle';
 const {idleAfterSeconds,idleBrightness,sleepAfterSeconds,...visual}=settings;
 const key=JSON.stringify({ambient:visual,remaining:state.remaining,fresh:state.fresh,mode:state.mode,count:state.activeCount,event:state.event?.at,segment:moving?Math.floor(now/(realtime?.064:2)):0,inputs:preset.category==='reactive'?events:[]});
 const frames=[];
 if(key!==previousKey)for(let i=0;i<(moving?(realtime?2:64):1);i++){
   const at=now+i*.064,phase=ambientFunctionalPhase(state,at,settings);
   // Frame timing advances independently of quota/task state; the background never restarts on task events.
   const frame=frameFor(base,snapshot,now,phase,{...settings,ambientEnabled:false,otherColorEnabled:false});
   const colors=renderAmbient(preset,at,{palette:settings.ambientPalette,profile:settings.ambientProfile,period:settings.ambientPeriod,zones:settings.ambientZones,events});
   applyAmbientColors(frame,colors,settings);
   frames.push(frame);
 }
 return {frames,key,length:1,speed:64,pollMs:realtime?64:500,mode:state.mode,activeCount:state.activeCount,style:runningStyleFor(state.activeCount,settings)};
}

export function previewSnapshot(snapshot,preview,now){
  const duration=Number.isFinite(preview?.duration)?Math.max(2,Math.min(40,preview.duration)):8;
  if(!preview||!['running','completed','reset','low','brightness-test'].includes(preview.scene)||now-preview.startedAt<0||now-preview.startedAt>=duration)return snapshot;
  const copy=structuredClone(snapshot);copy.events=[];copy.tasks=[];copy.taskError=null;copy.generatedAt=now;
  if(preview.scene==='brightness-test')copy.brightnessTest=true;
  if(preview.scene==='running')copy.tasks=Array.from({length:Math.max(1,Math.min(4,Math.floor(preview.taskCount??1)))},()=>({status:'active'}));
  if(['reset','completed'].includes(preview.scene))copy.events=[{kind:preview.scene,at:preview.startedAt}];
  if(preview.scene==='low'){
    copy.quotaAt=now;copy.quotaError=null;copy.windows=[{bucket:'codex',remaining:15}];
  }
  return copy;
}

export class AlertPlayback {
  constructor(){this.seen=new Map();this.active=null;}
  events(snapshot,now){
    if(this.active&&now-this.active.at>=8)this.active=null;
    const id=e=>`${e.kind}:${e.at}:${e.message??''}`;
    const candidates=(snapshot.events??[]).filter(e=>PRIORITY[e.kind]&&now-e.at>=0&&now-e.at<10&&!this.seen.has(id(e)))
      .sort((a,b)=>PRIORITY[b.kind]-PRIORITY[a.kind]||b.at-a.at);
    for(const event of candidates)this.seen.set(id(event),now);
    const next=candidates[0];
    if(next&&(!this.active||PRIORITY[next.kind]>=PRIORITY[this.active.kind]))this.active={...next,sourceAt:next.at,at:now};
    for(const [key,at]of this.seen)if(now-at>60)this.seen.delete(key);
    return this.active?[this.active]:[];
  }
}

export class GHub {
  constructor() { this.ws=null; this.pending=new Map(); this.counter=0; }
  async connect() {
    const ws = new WebSocket('ws://127.0.0.1:9010','json'); this.ws=ws;
    await new Promise((resolve,reject)=>{
      const timeout=setTimeout(()=>{ws.close();reject(Error('G HUB 连接超时'));},4000);
      ws.onopen=()=>{clearTimeout(timeout);resolve();};
      ws.onerror=()=>{clearTimeout(timeout);reject(Error('G HUB 未运行'));};
    });
    ws.onmessage=event=>{
      let r; try{r=JSON.parse(event.data);}catch{return;}
      const p=this.pending.get(r.msgId); if(!p) return;
      this.pending.delete(r.msgId);clearTimeout(p.timer);
      if(r.result?.code==='SUCCESS')p.resolve(r.payload);
      else {const error=Error(`G HUB: ${r.result?.code??'协议错误'} · ${r.result?.what??''}`);error.code=r.result?.code;p.reject(error);}
    };
    ws.onclose=()=>{for(const p of this.pending.values()){clearTimeout(p.timer);p.reject(Error('G HUB 连接断开'));}this.pending.clear();};
    ws.onerror=()=>{};
  }
  async call(verb,endpoint,payload={}) {
    if(!this.ws || this.ws.readyState!==WebSocket.OPEN) throw Error('G HUB 未连接');
    const msgId=`codex-pulse-${++this.counter}`;
    return new Promise((resolve,reject)=>{
      const timer=setTimeout(()=>{this.pending.delete(msgId);reject(Error('G HUB 响应超时'));},4000);
      this.pending.set(msgId,{resolve,reject,timer});
      this.ws.send(JSON.stringify({verb,path:endpoint,msgId,payload}));
    });
  }
  close(){this.ws?.close();}
}

function atomic(file,value) {const tmp=`${file}.${process.pid}.tmp`;fs.writeFileSync(tmp,JSON.stringify(value),{mode:0o600});fs.renameSync(tmp,file);}

async function main() {
  const args=process.argv.slice(2),command=args[0]??'status',directory=args[1];
  if(!directory)throw Error('用法: node keyboard.mjs status|run|restore|test <数据目录>');
  fs.mkdirSync(directory,{recursive:true,mode:0o700});
  const backupFile=path.join(directory,'keyboard-backup.json'),statusFile=path.join(directory,'keyboard.json');
  const lockFile=path.join(directory,'keyboard.lock');
  const previewFile=path.join(directory,'lighting-preview.json');
  // A prior worker may have left an active preview on disk; invalidate it once.
  let published=fs.existsSync(previewFile),lastDemoRequest=null;
  let hub=null,device=null,base=null,locked=false,stopping=false,lastSent=null,power=null,appliedPower=null;
  const alerts=new AlertPlayback();
  const wake=new WakeSignal();
  const configReader=new JsonFileCache(path.join(directory,'config.json'));
  const snapshotReader=new JsonFileCache(path.join(directory,'snapshot.json'));
  const publisher=new PreviewPublisher({
    viewerAt:()=>{try{return fs.statSync(path.join(directory,'preview-viewer.lease')).mtimeMs/1000;}catch{return 0;}},
    encode:previewPacket,write:packet=>{atomic(previewFile,packet);published=true;}
  });
  const inputEvents=[];let inputSocket=null,inputEnabled=false,reactiveMode=false,inputCount=0,lastInputReport=0;
  if(command==='run'){
    inputSocket=dgram.createSocket('udp4');
    inputSocket.on('error',()=>{});
    inputSocket.on('message',(buffer,remote)=>{
      if(remote.address!=='127.0.0.1'||buffer.length>256||!reactiveMode)return;
      try{const e=JSON.parse(buffer.toString());
        if(e.source==='preview'){
          // Read the current selection for explicit preview clicks: a config
          // change may have arrived while a G HUB operation was awaiting a reply.
          const current=configReader.read();
          if(!current.lighting||!session.activeKey||e.deviceKey!==session.activeKey||e.deviceKey!==current.selectedDeviceKey)return;
        }else if(!inputEnabled)return;
        if(!ambientKeys.some(k=>!k.protected&&k.id===e.id))return;
        if(e.source==='physical')inputCount++;
        inputEvents.push({id:e.id,at:Date.now()/1000});if(inputEvents.length>64)inputEvents.shift();wake.wake();
      }catch{}
    });
    inputSocket.bind(49315,'127.0.0.1');
  }
  let lastReport='',lastReportAt=0;
  const report=(status,message)=>{
    if(status!=='connected'){if(status==='error')publisher.invalidate();else publisher.clear();if(published){atomic(previewFile,{active:false,message,startedAt:Date.now()/1000});published=false;}}
    const at=Date.now()/1000,key=status+message+JSON.stringify(appliedPower);
    if(key!==lastReport||at-lastReportAt>=10){atomic(statusFile,{at,status,message,powerPolicy:appliedPower});lastReport=key;lastReportAt=at;}
  };
  function lock(){
    if(locked)return;
    try{fs.writeFileSync(lockFile,String(process.pid),{flag:'wx',mode:0o600});locked=true;}
    catch(error){
      if(error.code!=='EEXIST')throw error;
      const old=Number(fs.readFileSync(lockFile,'utf8'));
      if(!Number.isInteger(old)||old<=0)throw Error('灯光锁文件异常，请检查 keyboard.lock');
      try{process.kill(old,0);}catch(e){if(e.code==='ESRCH'){fs.unlinkSync(lockFile);return lock();}throw e;}
      throw Error('另一个灯光脚本仍在运行；请先关闭灯光开关');
    }
  }
  function unlock(){if(locked){if(fs.existsSync(lockFile)&&fs.readFileSync(lockFile,'utf8')===String(process.pid))fs.unlinkSync(lockFile);locked=false;}}
  function recovery(){
    try{
      const record=JSON.parse(fs.readFileSync(backupFile,'utf8'));
      if(record===null||typeof record!=='object'||Array.isArray(record))throw Error('恢复记录必须是对象');
      return record;
    }
    catch(error){if(error.code==='ENOENT')return null;throw Error('键盘恢复记录损坏，已保留原文件');}
  }
  const session=new GHubKeyboardSession({hub:null,readRecord:recovery,
    writeRecord:record=>atomic(backupFile,record),clearRecord:()=>{if(fs.existsSync(backupFile))fs.unlinkSync(backupFile);}});
  async function ensureHub(){
    if(!hub||hub.ws?.readyState!==WebSocket.OPEN){
      hub?.close();session.connectionLost();hub=new GHub();await hub.connect();session.hub=hub;
      device=null;base=null;power=null;appliedPower=null;lastSent=null;
    }
    return hub;
  }
  let inventoryStamp='';
  const discovery=new DeviceDiscovery({connect:ensureHub,write:value=>{
    if(command==='status')return; // Diagnostics cannot overwrite a live worker's active target.
    const stamp=JSON.stringify(value);
    if(stamp!==inventoryStamp){atomic(path.join(directory,'devices.json'),value);inventoryStamp=stamp;}
  }});
  async function acquire(config){
    lock();await ensureHub();
    const changed=await session.select(discovery.devices,config.selectedDeviceKey);
    device=session.device;base=session.base;
    if(changed){
      // session.select releases the previous viewer internally. Clear its cached
      // preview before any frame can make the newly selected target active.
      inputEvents.length=0;
      report('connecting','目标键盘已选择，正在准备联动');
      power=new PowerPolicyController(hub,device);appliedPower=null;lastSent=null;
    }
    discovery.publish(session.activeKey);
  }
  async function send(frame,payloadOverride=null){
    const payload=streamPayload(device.id,frame,payloadOverride);
    const previous=session.activeKey;
    await session.send(payload,updateOwnedViewer);
    if(previous!==session.activeKey)discovery.publish(session.activeKey);
  }
  async function release(){
    // Resolve the saved identity against a fresh list before a destructive REMOVE.
    const devices=(await hub.call('GET','/devices/list')).deviceInfos??[];
    await session.release(devices);
    inputEvents.length=0;
    device=null;base=null;power=null;appliedPower=null;lastSent=null;
    discovery.publish(null);report('restored','已交回 G HUB，恢复原配置灯效');
  }
  async function disconnect(){
    if(session.device||recovery()){
      lock();await ensureHub();await release();
    }
    hub?.close();hub=null;session.connectionLost();unlock();
  }
  for(const sig of ['SIGTERM','SIGINT'])process.on(sig,()=>{stopping=true;wake.wake();});
  try{
    if(command==='status'){
      const config=configReader.read();await discovery.refresh(config);
      console.log(JSON.stringify({devices:discovery.devices.map(d=>({model:d.deviceModel,connection:d.displayConnectionType,state:d.state})),selectedKey:config.selectedDeviceKey??null}));return;
    }
    if(command==='restore'){
      lock();await ensureHub();await release();
      report('restored','G HUB 已接管灯光');console.log('G HUB 已接管灯光，无残留临时预览');return;
    }
    if(command==='test'){
      const config=configReader.read();await discovery.refresh(config);await acquire(config);
      const profile=(await hub.call('GET','/profile/active')).id;
      const beforeProfile=await hub.call('GET','/profile',{id:profile});
      const now=Date.now()/1000;
      const frame=frameFor(base,{quotaAt:now,windows:[{bucket:'codex',remaining:50}],tasks:[],events:[]},now,0);
      await send(frame);
      let matches=false;
      for(let i=0;i<10;i++){
        const readback=await hub.call('GET',`/lighting/${device.id}/state`);
        if(colorsEqual(frame,readback)){matches=true;break;}
        await new Promise(r=>setTimeout(r,100));
      }
      if(!matches)throw Error('状态灯光读回不匹配');
      // Exercise the update path too, not only initial viewer creation.
      const second=frameFor(base,{quotaAt:now,windows:[{bucket:'codex',remaining:25}],tasks:[],events:[]},now,1);
      await send(second);
      matches=false;
      for(let i=0;i<10;i++){
        const actual=await hub.call('GET',`/lighting/${device.id}/state`);
        if(colorsEqual(second,actual)){matches=true;break;}
        if(i===9){atomic(path.join(directory,'expected-frame.json'),second);atomic(path.join(directory,'actual-frame.json'),actual);}
        await new Promise(r=>setTimeout(r,100));
      }
      if(!matches)throw Error('动画更新读回不匹配');
      await release();
      const afterProfile=await hub.call('GET','/profile',{id:profile});
      const {isDeepStrictEqual}=await import('node:util');
      if(!isDeepStrictEqual(beforeProfile,afterProfile))throw Error('G HUB 保存的配置发生变化');
      console.log('PASS: 临时接管、颜色读回、动画更新、释放预览及原配置完整性均通过');return;
    }
    if(command!=='run')throw Error('未知命令');
    while(!stopping){
      let nextPoll=500;
      try{
        const config=configReader.read(),enabled=config.lighting;
        inputEnabled=config.lightSettings?.ambientInputEnabled===true;
        reactiveMode=enabled&&config.lightSettings?.ambientEnabled===true&&ambientPresets.find(p=>p.id===config.lightSettings?.ambientPreset)?.category==='reactive';
        const scanned=await discovery.refresh(config,session.activeKey);
        if(!hub||hub.ws?.readyState!==WebSocket.OPEN){
          if(session.activeKey){session.connectionLost();discovery.publish(null);}
          report('error','G HUB 暂不可用，等待下次发现');await wake.wait(1000);continue;
        }
        if(!enabled){
          if(session.device||recovery()){lock();await release();unlock();}
          report('off','灯光监控已关闭');await wake.wait(1000);continue;
        }
        const snapshot=snapshotReader.read();
        if(!Number.isFinite(snapshot.generatedAt)||Date.now()/1000-snapshot.generatedAt>30){
          if(session.device||recovery()){lock();await release();unlock();}
          report('stale','后台数据过期，已交回 G HUB');await wake.wait(1000);continue;
        }
        // Every scan revalidates the selected device. A changed/offline selection
        // can never keep sending frames to the previous or first-listed keyboard.
        if(!session.device||scanned||deviceKey(session.device)!==config.selectedDeviceKey)await acquire(config);
        try{appliedPower=await power.apply(config.lightSettings);}
        catch(error){report('error',`灯光省电设置未应用：${error.message}`);await new Promise(r=>setTimeout(r,3000));continue;}
        {
          const now=Date.now()/1000;
          if(now-lastInputReport>=1){atomic(path.join(directory,'input-worker.json'),{at:now,enabled:inputEnabled,reactiveMode,receivedCount:inputCount});lastInputReport=now;}
          while(inputEvents.length&&now-inputEvents[0].at>=8)inputEvents.shift();
          const live={...snapshot,ambientEvents:inputEvents.slice(),events:alerts.events(snapshot,now)};
          const displayed=live.events.some(e=>e.kind==='reset')?live:previewSnapshot(live,config.preview,now);
          const demoRequest=displayed!==live ? config.preview?.startedAt:null;
          if(demoRequest!==lastDemoRequest){
            lastSent=null;
            if(demoRequest!=null)await hub.call('SET',`/lighting/${device.id}/mode/wake`,{});
            lastDemoRequest=demoRequest;
          }
          const plan=renderPlan(base,displayed,now,config.lightSettings,lastSent);
          nextPoll=plan.pollMs??500;
          if(plan.key!==lastSent){
            const {frames,speed,length}=plan;
            if(plan.mode==='brightness-test')await hub.call('SET',`/lighting/${device.id}/mode/wake`,{});
            await send(frames[0],frames.length>1?animationPayload(device.id,frames,speed,length):null);lastSent=plan.key;
            publisher.update(plan,Date.now()/1000,{deviceKey:session.activeKey,demo:displayed!==live,requestAt:config.preview?.startedAt??null});
          }
          publisher.publish(now);
          const runLabel=`${plan.activeCount} 个任务 · ${STYLE_NAMES[plan.style][Math.max(0,Math.min(3,plan.activeCount-1))]}`;
          const labels={'brightness-test':'满亮白光自检','reset-flash':'重置同步快闪','reset-glow':'重置柔光收尾','complete-wave':'轮次结束扩散','complete-settle':'结束确认','running':runLabel,'idle':'等待任务','attention':'任务需要关注'};
          report('connected',`${device.displayName} · ${labels[plan.mode]}${displayed!==live?'（演示）':''}`);
        }
      }catch(error){
        try{await disconnect();}catch{hub?.close();hub=null;session.connectionLost();unlock();}
        discovery.publish(null);
        report('error',String(error.message));await wake.wait(1000);
      }
      await wake.wait(nextPoll);
    }
  }finally{
    inputSocket?.close();
    if(command==='status'){hub?.close();unlock();}
    else try{await disconnect();}catch{report('error','释放预览失败，请在 G HUB 关闭灯效预览；恢复记录已保留');hub?.close();session.connectionLost();discovery.publish(null);unlock();}
  }
}

if(process.argv[1] && path.resolve(process.argv[1])===fileURLToPath(import.meta.url)){
  main().catch(error=>{console.error(error.message);process.exitCode=1;});
}

export async function updateOwnedViewer(hub,deviceId,payload){
 await hub.call('SET','/lighting/viewer/update',{devices:[deviceId],actionType:'STOP'});
 await hub.call('SET','/lighting/viewer/update',payload);
}

export function streamPayload(deviceId,frame,animation=null){return animation??animationPayload(deviceId,[frame,frame],64,1);}
