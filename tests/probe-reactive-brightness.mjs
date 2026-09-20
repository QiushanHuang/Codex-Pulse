import fs from 'node:fs';import dgram from 'node:dgram';import {GHub,chooseKeyboard}from '../scripts/keyboard.mjs';
const h=new GHub(),udp=dgram.createSocket('udp4'),p=process.env.HOME+'/Library/Application Support/CodexPulse/lighting-preview.json';
try{await h.connect();const d=chooseKeyboard((await h.call('GET','/devices/list')).deviceInfos);const rows=[];await new Promise((resolve,reject)=>udp.send(JSON.stringify({id:4,source:'preview'}),49315,'127.0.0.1',e=>e?reject(e):resolve()));const start=Date.now();
while(Date.now()-start<3200){const f=await h.call('GET',`/lighting/${d.id}/state`),preview=JSON.parse(fs.readFileSync(p));
const ids=preview.keys.filter(k=>+k>=4&&+k<=56),rgb=k=>f.infoMap.PERKEY_KEYBOARD.perKeyMap.colorCodeMap[k]?.rgba;
const expected=preview.frames.map(frame=>Math.max(...ids.map(k=>{const v=frame[preview.keys.indexOf(k)];return Math.max(v>>16,(v>>8)&255,v&255);})));const actual=Math.max(...ids.map(k=>{const v=rgb(k);return v?Math.max(v.red,v.green,v.blue)*255:0;}));
rows.push({ms:Date.now()-start,actual:Math.round(actual),planPeak:Math.max(...expected),packetAt:preview.startedAt});await new Promise(r=>setTimeout(r,45));}
fs.writeFileSync('build/reactive-brightness-probe.json',JSON.stringify(rows,null,2));console.log(rows.filter((_,i)=>i%5===0));}finally{udp.close();h.close();}
