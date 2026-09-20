import fs from 'node:fs';

// Atomic replacement changes inode even if byte count and timestamp are identical.
export class JsonFileCache {
  constructor(file){this.file=file;this.stamp=null;this.value=null;}
  read(){
    const stat=fs.statSync(this.file,{bigint:true});
    const stamp=`${stat.ino}:${stat.size}:${stat.mtimeNs}:${stat.ctimeNs}`;
    if(stamp!==this.stamp){
      const value=JSON.parse(fs.readFileSync(this.file,'utf8'));
      this.value=value;this.stamp=stamp;
    }
    return this.value;
  }
}

// A single latest plan is retained. No queue grows when a window is closed.
export class PreviewPublisher {
  constructor({viewerAt,encode,write}){this.viewerAt=viewerAt;this.encode=encode;this.write=write;this.lastWrite=-Infinity;this.sent=null;this.current=null;}
  update(plan,at,metadata={}){this.current={plan,at,metadata};}
  invalidate(){this.sent=null;}
  clear(){this.current=null;this.sent=null;}
  publish(now){
    if(!this.current || this.sent===this.current || now-this.lastWrite<0.25)return;
    const lease=this.viewerAt();
    if(!Number.isFinite(lease)||lease>now+1||now-lease>3)return;
    const {plan,at,metadata}=this.current;
    this.write({...this.encode(plan,at),...metadata});
    this.sent=this.current;this.lastWrite=now;
  }
}

// UDP input wakes a sleeping worker immediately; no polling is needed for key latency.
export class WakeSignal {
  constructor(){this.pending=false;this.finish=null;}
  wake(){if(this.finish)this.finish();else this.pending=true;}
  wait(ms){
    if(this.pending){this.pending=false;return Promise.resolve();}
    return new Promise(resolve=>{
      const finish=()=>{clearTimeout(timer);this.finish=null;resolve();};
      const timer=setTimeout(finish,ms);this.finish=finish;
    });
  }
}
