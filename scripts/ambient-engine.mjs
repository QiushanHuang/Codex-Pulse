// Design sandbox only. No G HUB, filesystem, or global input access.
export const palettes={
 amber:{name:'琥珀暖白',colors:['#FFC284','#FFF0D6','#C56D35']},
 glacier:{name:'冰川蓝',colors:['#2257CE','#57DFFF','#D2F8FF']},
 sakura:{name:'樱花奶油',colors:['#F58DB5','#FFE4D8','#BB8FF0']},
 forest:{name:'苔绿薄荷',colors:['#23785A','#80DFA6','#D8E5AD']},
 neon:{name:'霓虹紫青',colors:['#713BF2','#F25CCC','#45DCEB']},
 sunset:{name:'落日余晖',colors:['#FF7957','#F9C05B','#934CD6']},
 ocean:{name:'深海青蓝',colors:['#113D87','#158DA8','#73EDD7']},
 mono:{name:'月光银白',colors:['#C2CFEA','#F0F4FF','#7184AD']},
 rainbow:{name:'低饱和彩虹',colors:['#EB7790','#F6BF74','#90D7A1','#73C7E8','#B99BEF','#EB7790']},
 ember:{name:'炉火红橙',colors:['#B32938','#EE7636','#FFCF6A']}
};
export const zoneNames={gkeys:'G1–G5 宏键区',letters:'字母区',numbers:'数字行',modifiers:'修饰键',space:'空格',nav:'导航区',arrows:'方向键',extras:'Esc / F11–F12'};
export const profiles={balanced:{name:'均衡',values:{gkeys:.65,letters:.65,numbers:.5,modifiers:.45,space:.35,nav:.45,arrows:.65,extras:.35}},
 focus:{name:'书写聚焦',values:{gkeys:.35,letters:.7,numbers:.32,modifiers:.28,space:.22,nav:.2,arrows:.3,extras:.15}},
 night:{name:'深夜低亮',values:{gkeys:.12,letters:.22,numbers:.12,modifiers:.10,space:.08,nav:.08,arrows:.16,extras:.06}},
 gaming:{name:'操作突出',values:{gkeys:.85,letters:.48,numbers:.4,modifiers:.7,space:.6,nav:.25,arrows:.85,extras:.25}},
 rim:{name:'外围强调',values:{gkeys:.8,letters:.28,numbers:.65,modifiers:.7,space:.6,nav:.65,arrows:.8,extras:.6}}};
export const categories={static:'静态配色',loop:'循环动画',zones:'分区构图',reactive:'按键交互'};
const rows=[
 ['warm','暖白书桌','static','solid','amber','focus','柔暖单色，字母区更亮'],
 ['moon','月光银白','static','solid','mono','balanced','冷白单色，均衡照明'],
 ['sakura','樱花奶油','static','gradient','sakura','balanced','粉色到奶油色的横向渐变'],
 ['forest','苔绿薄荷','static','gradient','forest','focus','森林绿向薄荷色过渡'],
 ['ice','冰川纵深','static','vertical','glacier','balanced','从上到下的蓝白渐变'],
 ['dusk','暮色双岸','static','split','sunset','balanced','左右两岸暖色与紫色'],
 ['ink','墨蓝夜读','static','solid','ocean','night','低亮深蓝，适合暗环境'],
 ['pastel','粉彩光谱','static','gradient','rainbow','balanced','柔和彩虹静态铺陈'],
 ['breath','琥珀呼吸','loop','breath','amber','focus','整区缓慢起伏，保留底光'],
 ['tide','海洋潮汐','loop','wave','ocean','balanced','横向双色波，宽而柔和'],
 ['aurora','极光帷幕','loop','aurora','neon','balanced','双色斜向流动，亮度叠加慢潮'],
 ['comet','落日流星','loop','comet','sunset','balanced','亮头前进，长尾衰减'],
 ['rain','翡翠细雨','loop','rain','forest','night','各列错相向下落光'],
 ['orbit','月心涟漪','loop','ripple','mono','balanced','中心连续向外扩展的光环'],
 ['stars','紫夜星点','loop','stars','neon','night','各键错相缓慢闪烁'],
 ['spectrum','粉彩漫游','loop','spectrum','rainbow','balanced','柔和彩带缓慢横移'],
 ['writer','书写岛屿','zones','zones','amber','focus','字母暖白，辅助键深琥珀'],
 ['wasd','WASD 导航','zones','wasd','neon','gaming','WASD 与方向键突出，周围低亮'],
 ['hands','左右分庭','zones','split','glacier','balanced','左右手双色，中央自然分界'],
 ['rows','三层梯田','zones','rows','sakura','balanced','按键排分配不同颜色'],
 ['rim','边框灯带','zones','rim','neon','rim','外围彩光，中央安静'],
 ['navigation','导航灯塔','zones','navigation','ocean','focus','导航与方向键成为亮色锚点'],
 ['modifiers','快捷键地图','zones','modifiers','forest','gaming','修饰键与空格作为独立色块'],
 ['night','深夜航线','zones','zones','mono','night','低亮字母，方向键略亮'],
 ['echo','青蓝回声','reactive','echo','glacier','balanced','当前键亮起后缓慢淡出'],
 ['splash','池塘涟漪','reactive','splash','ocean','balanced','从按下的位置向四周扩散'],
 ['cross','光线十字','reactive','cross','neon','balanced','横纵两束光沿按键扩散'],
 ['heat','余温热图','reactive','heat','ember','night','连续敲击逐渐升温，停止后降温'],
 ['rowecho','同排回响','reactive','rowecho','sakura','balanced','按键所在整排柔和亮起'],
 ['zoneecho','分区共鸣','reactive','zoneecho','forest','balanced','按下一个键，所在区域响应'],
 ['trail','星尘足迹','reactive','trail','neon','night','近期按过的键留下异色长余辉'],
 ['bloom','书写绽放','reactive','bloom','amber','focus','每次输入使整区短暂柔和提亮'],

 ['g-jewels','五色航标','zones','g-jewels','rainbow','balanced','G1–G5 五级配色，与主键区对应行呼应'],
 ['g-anchor','琥珀侧灯','zones','g-anchor','amber','focus','左侧暖色锚点，主键区柔和暖白'],
 ['g-duet','紫青双翼','zones','g-duet','neon','gaming','G 区紫色、方向键青色，主键区低亮融合'],
 ['g-steps','月光阶梯','zones','g-steps','mono','night','G1 到 G5 亮度递增，对应主键行同步分层'],
 ['g-ladder','五阶流光','loop','g-ladder','glacier','balanced','G1–G5 依次向下点亮，光带同步横穿对应行'],
 ['g-relay','左岸接力','loop','g-relay','sunset','balanced','光沿 G 区下行，再向主键区右侧传递'],
 ['g-beacon','侧心涟漪','loop','g-beacon','ocean','balanced','以 G3 为中心，光环穿过 G 区与主键区'],
 ['g-tide','双岸潮汐','loop','g-tide','glacier','balanced','G 区上行、主键区下行，形成对向潮汐'],
 ['g-braid','丝带交织','loop','g-braid','sakura','rim','G 区五个相位与主键区斜向彩带连成一体'],
 ['g-rain','雨幕接棒','loop','g-rain','forest','night','雨光从左侧 G 列依次传向右侧各列'],
 ['g-breathe','双区呼吸','loop','g-breathe','amber','focus','G 区先起伏，主键区延迟半拍呼应'],
 ['g-orbit','环岸巡游','loop','g-orbit','neon','rim','G 列与主键外围组成闭合流光路径'],
 ['g-lane','行间应答','reactive','g-lane','glacier','balanced','点 G 键亮起对应主键行，主键输入回亮对应 G 键'],
 ['g-fan','侧岸扩散','reactive','g-fan','ocean','balanced','G 键与主键区之间传播柔和光束'],
 ['g-echo','五阶回声','reactive','g-echo','neon','balanced','输入点亮对应 G 键并沿 G 列扩散，G 键向主区回响'],
 ['g-chord','双区和弦','reactive','g-chord','sakura','focus','G 区与主键区同步柔亮，输入位置决定重音']
];
export const presets=rows.map(([id,name,category,effect,palette,profile,description])=>({id,name,category,effect,palette,profile,description,gkeyFocus:id.startsWith('g-'),period:category==='loop'?12:2.4}));
export const keys=[];
function key(id,label,x,y,w=1,zone='letters',code='',h=1){keys.push({id,label,x,y,w,h,zone,code,protected:zone==='protected'});}
for(let i=1;i<=5;i++){key('G'+i,'G'+i,-1.5,i+.3,1,'gkeys');Object.assign(keys.at(-1),{slot:'PERKEY_GKEY',slotKey:String(i)});}
key(41,'Esc',0,0,1,'extras','Escape');
for(let i=0;i<12;i++)key(58+i,'F'+(i+1),2+i+(i>=4?.25:0)+(i>=8?.25:0),0,1,i<10?'protected':'extras','F'+(i+1));
function row(labels,ids,y,offset,widths,zone,codes){let x=offset;labels.forEach((label,i)=>{const w=widths[i]??1;key(ids[i],label,x,y,w,typeof zone==='function'?zone(ids[i]):zone,codes?.[i]??'');x+=w;});}
row(['`','1','2','3','4','5','6','7','8','9','0','−','=','⌫'],[53,30,31,32,33,34,35,36,37,38,39,45,46,42],1.3,0,{13:2},'numbers',['Backquote',...Array.from({length:9},(_,i)=>'Digit'+(i+1)),'Digit0','Minus','Equal','Backspace']);
row(['Tab',...'QWERTYUIOP','[',']','\\'],[43,20,26,8,21,23,28,24,12,18,19,47,48,49],2.3,0,{0:1.5,13:1.5},id=>id===43?'modifiers':'letters',['Tab',...'QWERTYUIOP'.split('').map(c=>'Key'+c),'BracketLeft','BracketRight','Backslash']);
row(['Caps',...'ASDFGHJKL',';',"'",'Enter'],[57,4,22,7,9,10,11,13,14,15,51,52,40],3.3,0,{0:1.75,12:2.25},id=>[57,40].includes(id)?'modifiers':'letters',['CapsLock',...'ASDFGHJKL'.split('').map(c=>'Key'+c),'Semicolon','Quote','Enter']);
row(['Shift',...'ZXCVBNM',',','.','/','Shift'],[225,29,27,6,25,5,17,16,54,55,56,229],4.3,0,{0:2.25,11:2.75},id=>id>=224?'modifiers':'letters',['ShiftLeft',...'ZXCVBNM'.split('').map(c=>'Key'+c),'Comma','Period','Slash','ShiftRight']);
row(['Ctrl','Win','Alt','Space','Alt','Win','Menu','Ctrl'],[224,227,226,44,230,231,101,228],5.3,0,{0:1.25,1:1.25,2:1.25,3:6.25,4:1.25,5:1.25,6:1.25,7:1.25},id=>id===44?'space':'modifiers',['ControlLeft','MetaLeft','AltLeft','Space','AltRight','MetaRight','ContextMenu','ControlRight']);
row(['Prt','Scr','Pause'],[70,71,72],0,15.5,{},'nav');row(['Ins','Home','PgUp'],[73,74,75],1.3,15.5,{},'nav');row(['Del','End','PgDn'],[76,77,78],2.3,15.5,{},'nav');
key(82,'↑',16.5,4.3,1,'arrows','ArrowUp');row(['←','↓','→'],[80,81,79],5.3,15.5,{},'arrows',['ArrowLeft','ArrowDown','ArrowRight']);
row(['Num','/','*','−'],[83,84,85,86],1.3,19,{},'protected');row(['7','8','9'],[95,96,97],2.3,19,{},'protected');key(87,'+',22,2.3,1,'protected','',2);
row(['4','5','6'],[92,93,94],3.3,19,{},'protected');row(['1','2','3'],[89,90,91],4.3,19,{},'protected');key(88,'Enter',22,4.3,1,'protected','',2);key(98,'0',19,5.3,2,'protected');key(99,'.',21,5.3,1,'protected');key('logo','G',19,0,1,'protected');
export const layoutBounds={left:-1.7,width:24.8,height:6.5};
const clamp=(v,min=0,max=1)=>Math.min(max,Math.max(min,v)),tau=Math.PI*2,wrap=x=>((x%1)+1)%1;
const hex=s=>[1,3,5].map(i=>parseInt(s.slice(i,i+2),16));
const mix=(a,b,t)=>a.map((c,i)=>c*(1-t)+b[i]*t);
function gradient(colors,u){const v=clamp(u)*(colors.length-1),i=Math.floor(v);return mix(colors[i],colors[Math.min(i+1,colors.length-1)],v-i);}
export function render(p,time,options={}){
 const pal=palettes[options.palette??p.palette]??palettes.amber,colors=pal.colors.map(hex);
 const gains={...(profiles[options.profile??p.profile]??profiles.balanced).values,...options.zones};
 const brightness=clamp(Number.isFinite(options.brightness)?options.brightness:1);
 const t=time/Math.max(.5,options.period??p.period),output={};
 const events=(options.events??[]).slice(-64).filter(e=>time-e.at>=0&&time-e.at<8).map(e=>({...e,key:keys.find(k=>k.id===e.id)})).filter(e=>e.key&&!e.key.protected);
 for(const k of keys){if(k.protected)continue;let u=(k.x+k.w/2)/18.5,v=k.y/5.3,color=colors[0],energy=1;
 const isG=k.zone==='gkeys',lane=clamp((k.y-1.3)/4),spread=(k.x+1.5)/20;
 switch(p.effect){
 case 'g-jewels':color=gradient(colors,lane);energy=isG?1:.65;break;
 case 'g-anchor':color=colors[isG?0:1];energy=isG?1:.6;break;
 case 'g-duet':color=colors[isG?0:k.zone==='arrows'?2:1];energy=isG||k.zone==='arrows'?1:.35;break;
 case 'g-steps':color=gradient(colors,lane);energy=.2+.8*lane;break;
 case 'g-ladder':energy=.08+.92*Math.pow(.5+.5*Math.cos(tau*(t-lane*.8-spread*.22)),8);color=gradient(colors,lane);break;
 case 'g-relay':{const position=isG?lane*.3:.3+spread*.7;energy=.08+.92*Math.exp(-wrap(t-position)/.12);color=gradient(colors,position);break;}
 case 'g-beacon':{const d=Math.hypot((k.x+1.5)/20,(k.y-3.3)/10);energy=.08+.92*Math.pow(.5+.5*Math.cos(tau*(d-t)),8);color=gradient(colors,clamp(d));break;}
 case 'g-tide':energy=.15+.85*(.5+.5*Math.sin(tau*(t+(isG?lane:-lane)*.8)));color=gradient(colors,isG?lane:1-lane);break;
 case 'g-braid':color=gradient(colors,.5+.5*Math.sin(tau*(lane*.6+spread-t)));energy=.3+.7*(.5+.5*Math.cos(tau*(lane-spread+t)));break;
 case 'g-rain':energy=.08+.92*Math.exp(-wrap(t-lane*.7-spread*.6)/.12);color=gradient(colors,energy);break;
 case 'g-breathe':energy=.15+.85*(.5-.5*Math.cos(tau*(t-(isG?0:.25))));color=colors[isG?0:1];break;
 case 'g-orbit':{const x=k.x+1.5,y=k.y-1.3,onRim=isG||k.y<=1.3||k.y>=5.3||k.x>=13;
 const position=isG?(36+(4-clamp(y,0,4)))/40:k.y<=1.3?x/40:k.x>=13?(16+clamp(y,0,4))/40:(20+16-x)/40;
 energy=onRim?.08+.92*Math.exp(-wrap(t-position)/.10):.12;color=gradient(colors,wrap(position));break;}
 case 'gradient':color=gradient(colors,u);break;
 case 'vertical':color=gradient(colors,v);break;
 case 'split':color=colors[k.x<7.5?0:colors.length-1];break;
 case 'zones':color=colors[k.zone==='letters'?1:k.zone==='arrows'?2:0];break;
 case 'wasd':color=colors[['W','A','S','D'].includes(k.label)||k.zone==='arrows'?2:0];energy=['W','A','S','D'].includes(k.label)?1:.5;break;
 case 'rows':color=colors[Math.floor(k.y)%colors.length];break;
 case 'rim':color=colors[k.zone==='letters'?0:2];energy=k.zone==='letters'?.32:1;break;
 case 'navigation':color=colors[['nav','arrows'].includes(k.zone)?2:0];break;
 case 'modifiers':color=colors[k.zone==='modifiers'?2:k.zone==='space'?1:0];break;
 case 'breath':energy=.16+.84*(.5-.5*Math.cos(tau*t));break;
 case 'wave':color=gradient(colors,.5+.5*Math.sin(tau*(u-t)));energy=.3+.7*(.5+.5*Math.sin(tau*(u-t)));break;
 case 'aurora':color=gradient(colors,.5+.5*Math.sin(tau*(u+.35*v-t)));energy=.3+.7*(.5+.5*Math.cos(tau*(t+v)));break;
 case 'comet':energy=.07+.93*Math.exp(-wrap(t-u)/.14);color=gradient(colors,clamp(energy));break;
 case 'rain':energy=.08+.92*Math.exp(-wrap(t*2-v+k.x*.381)/.12);color=gradient(colors,energy);break;
 case 'ripple':energy=.08+.92*Math.pow(.5+.5*Math.cos(tau*(Math.hypot(u-.45,(v-.5)*.4)*2-t)),5);color=gradient(colors,energy);break;
 case 'stars':energy=.08+.92*Math.pow(.5+.5*Math.sin(tau*(t+k.x*.713+k.y*.39)),12);color=gradient(colors,wrap(k.x*.13+k.y*.31));break;
 case 'spectrum':color=gradient(colors,wrap(u-t));break;
 default:break;
 }
 if(p.category==='reactive'){
 let glow=0,hue=1;energy=.13;
 for(const e of events){const age=time-e.at,life=p.effect==='heat'||p.effect==='trail'?8:Math.max(.4,options.period??p.period);if(age>=life)continue;
 const dx=k.x+k.w/2-e.key.x-e.key.w/2,dy=k.y-e.key.y,d=Math.hypot(dx,dy),fade=Math.pow(1-age/life,1.6);let g=0;
 switch(p.effect){
 case 'g-lane':g=(Math.abs(dy)<.3&&(isG||e.key.zone==='gkeys'))?fade:0;break;
 case 'g-fan':g=(isG||e.key.zone==='gkeys')?Math.exp(-Math.pow(d-age*10,2)/12)*fade:0;break;
 case 'g-echo':g=(isG||e.key.zone==='gkeys')?Math.exp(-Math.abs(dy)*.65)*fade:0;break;
 case 'g-chord':g=fade*(isG||Math.abs(dy)<.3?1:.5);break;
 case 'echo':g=k.id===e.id?fade:0;break;
 case 'splash':g=Math.exp(-Math.pow(d-age*5,2)/.8)*fade;break;
 case 'cross':g=(Math.abs(dx)<.6||Math.abs(dy)<.2)?Math.exp(-Math.pow(d-age*7,2)/2)*fade:0;break;
 case 'heat':g=Math.exp(-d*d/1.5)*fade*.5;break;
 case 'rowecho':g=Math.abs(dy)<.2?fade:0;break;
 case 'zoneecho':g=k.zone===e.key.zone?fade:0;break;
 case 'trail':g=k.id===e.id?fade:0;break;
 case 'bloom':g=fade*.75;break;
 }
 glow=p.effect==='heat'?clamp(glow+g):Math.max(glow,g);if(g>0)hue=wrap(e.key.x*.137+e.key.y*.31);
 }
 color=p.effect==='heat'?gradient(colors,glow):mix(colors[0],p.effect==='trail'?gradient(colors,hue):colors[colors.length-1],glow);energy+=.87*glow;
 }
 const gain=brightness*clamp(gains[k.zone]??1)*energy;
 output[k.id]=color.map(c=>Math.round(clamp(c*gain,0,255)));
 }
 return output;
}
