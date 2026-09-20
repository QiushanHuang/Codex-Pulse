import fs from 'node:fs';import {presets,palettes,profiles,zoneNames,keys,layoutBounds} from './ambient-engine.mjs';
fs.writeFileSync(process.argv[2],JSON.stringify({presets,palettes,profiles,zones:Object.entries(zoneNames).map(([id,name])=>({id,name})),keys:keys.map(k=>({...k,id:String(k.id)})),layoutBounds}));
