import { useState } from "react";

const T = {
  navy:"#0B1929",ink:"#0F2740",surface:"#132D4A",card:"#1A3A5C",
  muted:"#7BA7C4",text:"#C9E0F0",white:"#F0F8FF",
  good:"#3DD68C",caution:"#F5A623",bad:"#E05555",
  rain:"#5BA3D4",tide:"#4ECDC4",moon:"#D4C47A",
  wind:"#A78BFA",astro:"#C084FC",
  srcOM:"#5BA3D4",srcOW:"#F5A623",srcWK:"#3DD68C",srcBOM:"#C084FC",
};

const SOURCES = {
  openMeteo:  {short:"OM", color:T.srcOM},
  openWeather:{short:"OW", color:T.srcOW},
  weatherKit: {short:"WK", color:T.srcWK},
  bom:        {short:"BOM",color:T.srcBOM},
};

const RINGS = [
  {key:"temp",    label:"Temp",  unit:"°", emoji:"🌡",colorGood:T.good, colorBad:T.bad,  disagreementThreshold:2,
   scoreFromValue:(v)=>{if(v>=22&&v<=28)return 1;if(v<22){if(v>=17)return(v-17)/5;if(v>=12)return(v-12)/5-1;return-1;}else{if(v<=33)return 1-(v-28)/5;if(v<=38)return-(v-33)/5;return-1;}},
   comfortLabel:(v)=>v>=22&&v<=28?"Ideal":v<17?"Cool":v<22?"Slightly cool":v<=33?"Warm":"Hot",
   format:(v)=>`${v}°`},
  {key:"rain",    label:"Rain",  unit:"%", emoji:"💧",colorGood:T.rain, colorBad:T.rain, disagreementThreshold:15,
   scoreFromValue:(v)=>v<=15?1:v<=35?1-(v-15)/20:v<=60?-(v-35)/25:-1,
   comfortLabel:(v)=>v<=15?"Unlikely":v<=35?"Possible":v<=60?"Likely":"Probable",
   format:(v)=>`${v}%`},
  {key:"wind",    label:"Wind",  unit:"",  emoji:"💨",colorGood:T.wind, colorBad:T.wind, disagreementThreshold:10,
   scoreFromValue:(v)=>v<=12?1:v<=25?1-(v-12)/13:v<=45?-(v-25)/20:-1,
   comfortLabel:(v)=>v<=12?"Calm":v<=25?"Breezy":v<=45?"Windy":"Strong",
   format:(v)=>`${v}`},
  {key:"uv",      label:"UV",    unit:"",  emoji:"☀️",colorGood:T.caution,colorBad:T.bad,disagreementThreshold:1,
   scoreFromValue:(v)=>v<=2?1:v<=5?1-(v-2)/3:v<=8?-(v-5)/4.5:v<=11?-0.6-(v-8)*0.13:-1,
   comfortLabel:(v)=>v<=2?"Low":v<=5?"Moderate":v<=7?"High":v<=10?"Very High":"Extreme",
   format:(v)=>`${v}`},
  {key:"humidity",label:"Humid", unit:"%", emoji:"💦",colorGood:T.tide, colorBad:T.bad,  disagreementThreshold:10,
   scoreFromValue:(v)=>{if(v>=40&&v<=65)return 1;if(v<40){if(v>=30)return(v-30)/10;if(v>=20)return(v-20)/10-1;return-1;}else{if(v<=75)return 1-(v-65)/10;if(v<=85)return-(v-75)/10;return-1;}},
   comfortLabel:(v)=>v>=40&&v<=65?"Comfortable":v<40?"Dry":v<=75?"Muggy":"Oppressive",
   format:(v)=>`${v}%`},
];

const DATA = {
  location:"Hope Island, QLD",date:"Thu 10 Jul",time:"1:47 PM",season:"winter",
  sources:{
    openMeteo:  {temp:17,rain:12,wind:14,uv:4,humidity:62},
    openWeather:{temp:19,rain:18,wind:20,uv:5,humidity:58},
    weatherKit: {temp:18,rain:10,wind:16,uv:4,humidity:60},
    bom:        {temp:17,rain:15,wind:13,uv:4,humidity:65},
  },
  minMax:{temp:[13,21],rain:[5,20],wind:[8,22],uv:[0,6],humidity:[50,70]},
  historical:{
    oneYear: {temp:19,label:"1 yr ago"},
    fiveYear:{temp:16,label:"5 yrs ago"},
    average: {temp:18,label:"30yr avg"},
  },
  tides:[
    {time:"6:14", hour:6.23, height:1.8,type:"High"},
    {time:"12:38",hour:12.63,height:0.3,type:"Low"},
    {time:"18:52",hour:18.87,height:1.6,type:"High"},
    {time:"23:41",hour:23.68,height:0.5,type:"Low"},
  ],
  nowHour:13.8,
  moon:{phase:"Waxing Gibbous",illumination:78,emoji:"🌔",nextFullDays:3},
  uv:4,uvPeak:6,uvPeakTime:"12:30–1:30 PM",
  sunProtection:{start:"8:14 AM",end:"4:47 PM"},
  calendarEvents:[
    {id:1,title:"Kids Soccer",  date:"Sat Jul 12",time:"9:00 AM",impact:"major",rain:65,wind:28,temp:21,warning:"65% rain, 28km/h winds expected."},
    {id:2,title:"BBQ Broadwater",date:"Sun Jul 13",time:"4:00 PM",impact:"minor",rain:20,wind:14,temp:26,warning:"Light shower possible."},
    {id:3,title:"Morning Paddle",date:"Mon Jul 14",time:"7:00 AM",impact:"clear",rain:5, wind:8, temp:19,warning:null},
  ],
  astronomical:[
    {date:"Jul 14",event:"Partial Lunar Eclipse",emoji:"🌑",rarity:"rare",  desc:"Visible from SE QLD, 9:40 PM AEST"},
    {date:"Aug 12",event:"Perseid Meteor Shower", emoji:"☄️",rarity:"annual",desc:"~30/hr visible from southern hemisphere"},
    {date:"Dec 4", event:"Total Solar Eclipse",   emoji:"🌑",rarity:"rare",  desc:"Path crosses western Australia"},
  ],
  news:[
    {headline:"Severe Thunderstorm Warning for SE Queensland",              source:"BOM Warning", time:"38m ago",impact:"high",excerpt:"Damaging winds and large hail possible for the Gold Coast and Scenic Rim this afternoon.",isWarning:true},
    {headline:"East coast low to bring heavy rain to SE Qld this weekend",  source:"BOM",        time:"1h ago", impact:"high",excerpt:"A deepening low pressure system forecast to bring 60–100mm of rainfall to coastal areas Friday–Sunday."},
    {headline:"Heatwave conditions easing across inland Queensland",        source:"ABC Weather",time:"4h ago", impact:"low", excerpt:"Temperatures will drop by up to 12°C as a cold front moves through."},
  ],
  hourly:[
    {hour:"Now",temp:17,rain:12,emoji:"⛅"},{hour:"3pm",temp:18,rain:10,emoji:"🌤"},
    {hour:"4pm",temp:18,rain:12,emoji:"⛅"},{hour:"5pm",temp:17,rain:18,emoji:"🌦"},
    {hour:"6pm",temp:16,rain:25,emoji:"🌦"},{hour:"7pm",temp:15,rain:15,emoji:"⛅"},
    {hour:"8pm",temp:14,rain:8, emoji:"🌤"},{hour:"9pm",temp:13,rain:5, emoji:"🌤"},
  ],
  daily:[
    {day:"Today",high:21,low:13,rain:15,emoji:"🌤",disagree:false},
    {day:"Fri",  high:22,low:14,rain:8, emoji:"☀️",disagree:false},
    {day:"Sat",  high:20,low:13,rain:65,emoji:"🌧",disagree:true},
    {day:"Sun",  high:23,low:15,rain:20,emoji:"🌦",disagree:false},
    {day:"Mon",  high:24,low:15,rain:5, emoji:"☀️",disagree:false},
    {day:"Tue",  high:22,low:14,rain:10,emoji:"🌤",disagree:false},
    {day:"Wed",  high:21,low:13,rain:30,emoji:"🌦",disagree:false},
  ],
  crowdVotes:{great:3,good:12,ok:8,bad:2,awful:0},
};

// ─── HELPERS ─────────────────────────────────────────────────────────────────
function lerp(h1,h2,t){
  const p=h=>[parseInt(h.slice(1,3),16),parseInt(h.slice(3,5),16),parseInt(h.slice(5,7),16)];
  const[r1,g1,b1]=p(h1),[r2,g2,b2]=p(h2);
  return `rgb(${Math.round(r1+(r2-r1)*t)},${Math.round(g1+(g2-g1)*t)},${Math.round(b1+(b2-b1)*t)})`;
}
function needleColor(ring,score){
  return score>=0?lerp(ring.colorGood,"#FFFFFF",score*0.15):lerp(ring.colorGood,T.bad,Math.abs(score)*0.85);
}
function trimmedMean(vals){
  if(vals.length<=2)return Math.round(vals.reduce((a,b)=>a+b)/vals.length);
  const s=[...vals].sort((a,b)=>a-b).slice(1,-1);
  return Math.round(s.reduce((a,b)=>a+b)/s.length);
}
function calcConsensus(src){
  const keys=Object.keys(src),out={};
  RINGS.forEach(r=>{out[r.key]=trimmedMean(keys.map(k=>src[k][r.key]));});
  return out;
}
function calcDisagreements(src){
  const keys=Object.keys(src),out={};
  RINGS.forEach(r=>{
    const vals=keys.map(k=>({source:k,value:src[k][r.key]}));
    const nums=vals.map(v=>v.value),spread=Math.max(...nums)-Math.min(...nums);
    out[r.key]={spread,values:vals,
      isMajor:spread>=r.disagreementThreshold*2,
      isMinor:spread>=r.disagreementThreshold&&spread<r.disagreementThreshold*2,
      hasFlag:spread>=r.disagreementThreshold};
  });
  return out;
}
function overallScore(c){return RINGS.reduce((s,r)=>s+r.scoreFromValue(c[r.key]??0),0)/RINGS.length;}
function overallLabel(s){return s>=0.7?"Great":s>=0.3?"Good":s>=0?"OK":s>=-0.5?"Rough":"Poor";}
function overallColor(s){return s>=0.4?T.good:s>=0?T.caution:T.bad;}
function scoreToAngle(s){return -s*90;}
function polarXY(deg,r,cx,cy){
  const rad=((deg-90)*Math.PI)/180;
  return{x:cx+r*Math.cos(rad),y:cy+r*Math.sin(rad)};
}
function comfortBarLeft(score,half){return score>=0?`calc(${half}px - ${Math.max(2,Math.abs(score)*half)}px)`:"50%";}
function comfortBarWidth(score,half){return Math.max(2,Math.abs(score)*half);}

function ratingText(consensus){
  const os=overallScore(consensus);
  const worst=RINGS.map(r=>({r,s:r.scoreFromValue(consensus[r.key])})).sort((a,b)=>a.s-b.s)[0];
  if(os>=0.75)return{text:"A perfect winter's day in Brisbane — comfortable and clear.",emoji:"😎"};
  if(os>=0.4){
    if(worst.r.key==="rain")return{text:`Decent but ${consensus.rain}% rain chance — keep an eye on the sky.`,emoji:"🌦"};
    if(worst.r.key==="uv")return{text:`Nice day but UV is ${worst.r.comfortLabel(consensus.uv)} — sun protection essential.`,emoji:"🧴"};
    if(worst.r.key==="temp"&&consensus.temp<17)return{text:`Cool day at ${consensus.temp}° — pack a layer.`,emoji:"🧥"};
    return{text:"Good conditions with a few things to watch.",emoji:"🙂"};
  }
  if(worst.r.key==="rain")return{text:`Rain likely (${consensus.rain}%) — plan around the showers.`,emoji:"🌧"};
  if(worst.r.key==="temp"&&consensus.temp>35)return{text:`Heatwave — ${consensus.temp}°. Limit outdoor activity midday.`,emoji:"🔥"};
  return{text:"Mixed conditions today. Check the detail tabs.",emoji:"😐"};
}

// ─── DIAL ─────────────────────────────────────────────────────────────────────
// The rings only ever occupy the TOP semicircle (-90..+90 from 12 o'clock).
// The ring box and the centre-readout band are two SEPARATE stacked blocks
// (not absolutely positioned on top of each other) so there is zero chance
// of the readout text overlapping anything that follows in the page.
const DCX=170,DCY=176,BASE_R=150,GAP=23;
const DIAL_RING_H=190;     // height of just the ring/svg box
const DIAL_READOUT_H=80;   // fixed-height block reserved for the centre text — snug, no dead air
const DIAL_W=340,DIAL_H=DIAL_RING_H+DIAL_READOUT_H;

function RingLayer({ring,idx,value,minMax,disagreement,sources,radius,isSelected}){
  const score=ring.scoreFromValue(value);
  const angle=scoreToAngle(score);
  const color=needleColor(ring,score);
  const lw=isSelected?12:9;

  function ap(a1,a2,r){
    const s=polarXY(a1,r,DCX,DCY),e=polarXY(a2,r,DCX,DCY);
    const la=Math.abs(a2-a1)>180?1:0,sw=a2>a1?1:0;
    return `M${s.x.toFixed(1)} ${s.y.toFixed(1)} A${r} ${r} 0 ${la} ${sw} ${e.x.toFixed(1)} ${e.y.toFixed(1)}`;
  }

  const tip=polarXY(angle,radius,DCX,DCY);
  // Icon badge sits directly ON the ring track at its base — 12 o'clock (angle 0)
  const iconPos=polarXY(0,radius,DCX,DCY);

  const mm=minMax?.[ring.key];
  const minAngle=mm?scoreToAngle(ring.scoreFromValue(mm[0])):null;
  const maxAngle=mm?scoreToAngle(ring.scoreFromValue(mm[1])):null;

  // Min tick points
  const minTick= minAngle!=null ?{
    i:polarXY(minAngle,radius-lw/2-2,DCX,DCY),
    o:polarXY(minAngle,radius+lw/2+2,DCX,DCY)
  }:null;
  const maxTick= maxAngle!=null ?{
    i:polarXY(maxAngle,radius-lw/2-2,DCX,DCY),
    o:polarXY(maxAngle,radius+lw/2+2,DCX,DCY)
  }:null;

  // Disagreement bracket
  let disagBracket=null;
  if(disagreement?.hasFlag){
    const sc=disagreement.values.map(v=>ring.scoreFromValue(v.value));
    const da1=scoreToAngle(Math.max(...sc)),da2=scoreToAngle(Math.min(...sc));
    disagBracket={d:ap(da1,da2,radius),color:disagreement.isMajor?T.bad:T.caution};
  }

  // Source dots
  const srcDots=Object.entries(sources).map(([k,sv])=>{
    const sa=scoreToAngle(ring.scoreFromValue(sv[ring.key]));
    const dot=polarXY(sa,radius,DCX,DCY);
    return{key:k,cx:dot.x,cy:dot.y,color:SOURCES[k]?.color||T.muted};
  });

  return (
    <g>
      <path d={ap(-90,90,radius)} stroke={T.surface} strokeWidth={lw} fill="none" strokeLinecap="round"/>
      <path d={ap(-90,0,radius)} stroke="#3DD68C0e" strokeWidth={lw} fill="none" strokeLinecap="round"/>
      {minAngle!=null&&maxAngle!=null&&(
        <path d={ap(Math.min(minAngle,maxAngle),Math.max(minAngle,maxAngle),radius)}
          stroke={T.muted} strokeWidth={lw+2} fill="none" strokeLinecap="round" opacity={0.09}/>
      )}
      {minTick&&<line x1={minTick.i.x} y1={minTick.i.y} x2={minTick.o.x} y2={minTick.o.y} stroke={T.muted} strokeWidth={1.5} opacity={0.55}/>}
      {maxTick&&<line x1={maxTick.i.x} y1={maxTick.i.y} x2={maxTick.o.x} y2={maxTick.o.y} stroke={T.muted} strokeWidth={1.5} opacity={0.55}/>}
      {disagBracket&&<path d={disagBracket.d} stroke={disagBracket.color} strokeWidth={2} fill="none" strokeDasharray="2,2" opacity={0.55}/>}
      {Math.abs(angle)>1&&(
        <path d={ap(0,angle,radius)} stroke={color} strokeWidth={lw} fill="none" strokeLinecap="round"/>
      )}
      {srcDots.map(sd=>(
        <circle key={sd.key} cx={sd.cx} cy={sd.cy} r={2.5} fill={sd.color} opacity={0.7}/>
      ))}
      <circle cx={tip.x} cy={tip.y} r={isSelected?8:6} fill={color} stroke={T.navy} strokeWidth={1.5}/>
      {disagreement?.hasFlag&&(
        <circle cx={tip.x} cy={tip.y} r={isSelected?11:9} fill="none"
          stroke={disagreement.isMajor?T.bad:T.caution} strokeWidth={1.5} opacity={0.5}/>
      )}
      {/* Icon badge — sits directly on the ring track at its base (top).
          A solid circle behind the emoji so it reads clearly against every ring colour. */}
      <circle cx={iconPos.x} cy={iconPos.y} r={isSelected?13:11}
        fill={T.navy} stroke={isSelected?color:T.surface} strokeWidth={isSelected?2:1.5}/>
      <text x={iconPos.x} y={iconPos.y+5} textAnchor="middle"
        fontSize={isSelected?"15":"13"}>{ring.emoji}</text>
    </g>
  );
}

function Dial({consensus,disagreements,minMax,sources,tapped,onTap}){
  const os=overallScore(consensus);
  const oc=overallColor(os),ol=overallLabel(os);
  const selRing=RINGS.find(r=>r.key===tapped);
  const selScore=selRing?selRing.scoreFromValue(consensus[tapped]):null;
  const selColor=selScore!=null?needleColor(selRing,selScore):oc;
  const selVal=tapped?consensus[tapped]:null;
  const selMM=tapped&&minMax?.[tapped]?minMax[tapped]:null;

  return(
    <div style={{display:"flex",flexDirection:"column",alignItems:"center",width:DIAL_W}}>
      {/* Ring box — fixed height, rings drawn inside via SVG */}
      <div style={{position:"relative",width:DIAL_W,height:DIAL_RING_H}}>
        <svg width={DIAL_W} height={DIAL_RING_H} viewBox={`0 0 ${DIAL_W} ${DIAL_RING_H}`}
          style={{position:"absolute",top:0,left:0,overflow:"visible"}}>
          {RINGS.map((ring,i)=>(
            <g key={ring.key}
              onClick={()=>onTap(tapped===ring.key?null:ring.key)}
              style={{cursor:"pointer"}}>
              <RingLayer
                ring={ring} idx={i}
                value={consensus[ring.key]??0}
                minMax={minMax}
                disagreement={disagreements?.[ring.key]}
                sources={sources}
                radius={BASE_R-i*GAP}
                isSelected={tapped===ring.key}
              />
            </g>
          ))}
          <line x1={DCX} y1={DCY-BASE_R-14} x2={DCX} y2={DCY+8}
            stroke={T.white} strokeWidth={1} strokeDasharray="3,4" opacity={0.2}/>
          <text x={DCX-BASE_R+4} y={DCY+4} textAnchor="end"
            fill={T.good} fontSize="9" opacity={0.55}
            fontFamily="-apple-system,sans-serif">◀ good</text>
          <text x={DCX+BASE_R-4} y={DCY+4} textAnchor="start"
            fill={T.bad} fontSize="9" opacity={0.55}
            fontFamily="-apple-system,sans-serif">not ▶</text>
        </svg>
      </div>
      {/* Centre readout — a NORMAL block that follows the ring box in document
          flow. Fixed height so its own content (big number, label, min/max range)
          never changes the layout, and it can never overlap the ring box above
          or push into content below by more than this fixed amount. */}
      <div style={{width:"100%",height:DIAL_READOUT_H,marginTop:-58,
        display:"flex",flexDirection:"column",alignItems:"center",
        justifyContent:"flex-start",textAlign:"center"}}>
        {selRing?(
          <div>
            <div style={{fontSize:24,marginBottom:1}}>{selRing.emoji}</div>
            <div style={{fontSize:36,fontWeight:200,color:selColor,lineHeight:1}}>
              {selRing.format(selVal)}
            </div>
            <div style={{fontSize:12,color:selColor,fontWeight:600,marginTop:2}}>
              {selRing.comfortLabel(selVal)}
            </div>
            {selMM&&(
              <div style={{fontSize:10,color:T.muted,marginTop:3}}>
                {selRing.format(selMM[0])}–{selRing.format(selMM[1])}
              </div>
            )}
          </div>
        ):(
          <div>
            <div style={{fontSize:10,color:T.muted,marginBottom:2,
              textTransform:"uppercase",letterSpacing:"0.07em"}}>comfort</div>
            <div style={{fontSize:40,fontWeight:200,color:oc,lineHeight:1}}>{ol}</div>
          </div>
        )}
      </div>
    </div>
  );
}

// ─── COMFORT BAR (no IIFE) ────────────────────────────────────────────────────
function ComfortBar({score,color,half}){
  const fill=Math.max(2,Math.abs(score)*half);
  const left=score>=0?`calc(${half}px - ${fill}px)`:"50%";
  return(
    <div style={{position:"absolute",top:0,height:"100%",borderRadius:2,
      left:left,width:fill,background:color}}/>
  );
}

// ─── TAB BAR ─────────────────────────────────────────────────────────────────
const TABS=[
  {id:"now",    emoji:"🌤",label:"Now"},
  {id:"scene",  emoji:"🏖",label:"Scene"},
  {id:"today",  emoji:"📋",label:"Today"},
  {id:"week",   emoji:"📅",label:"Week"},
  {id:"tides",  emoji:"🌊",label:"Tides"},
  {id:"plans",  emoji:"📆",label:"Plans"},
  {id:"uv",     emoji:"☀️",label:"UV"},
  {id:"sky",    emoji:"🔭",label:"Sky"},
  {id:"news",   emoji:"📰",label:"News"},
  {id:"sources",emoji:"📡",label:"Sources"},
];

function TabBar({active,onTab,flags}){
  return(
    <div style={{position:"fixed",bottom:0,left:"50%",transform:"translateX(-50%)",
      width:"100%",maxWidth:430,background:T.ink,
      borderTop:`1px solid ${T.surface}`,
      display:"flex",overflowX:"auto",
      padding:"8px 4px 20px",zIndex:100}}>
      {TABS.map(t=>(
        <button key={t.id} onClick={()=>onTab(t.id)}
          style={{flex:"0 0 auto",minWidth:42,display:"flex",flexDirection:"column",
            alignItems:"center",gap:2,background:"transparent",border:"none",
            cursor:"pointer",padding:"0 4px",position:"relative"}}>
          <span style={{fontSize:17}}>{t.emoji}</span>
          <span style={{fontSize:9,
            color:active===t.id?T.white:T.muted,
            fontWeight:active===t.id?700:400}}>{t.label}</span>
          {active===t.id&&(
            <div style={{width:3,height:3,borderRadius:"50%",
              background:T.tide,marginTop:1}}/>
          )}
          {flags?.[t.id]&&(
            <div style={{position:"absolute",top:0,right:6,
              width:5,height:5,borderRadius:"50%",background:T.caution}}/>
          )}
        </button>
      ))}
    </div>
  );
}

// ─── TIDE CURVE ───────────────────────────────────────────────────────────────
function TideCurve({tides,nowHour,height}){
  const h=height||120,W=320,PL=28,PR=8,PT=16,PB=28;
  const CW=W-PL-PR,CH=h-PT-PB;
  const pts=[
    {h:0,v:0.5},{h:3,v:0.8},{h:6.23,v:1.8},{h:9,v:1.2},
    {h:12.63,v:0.3},{h:15,v:0.8},{h:18.87,v:1.6},
    {h:21,v:1.1},{h:23.68,v:0.5},{h:24,v:0.5}
  ];
  const xs=hv=>PL+(hv/24)*CW;
  const ys=v=>PT+CH-((v-0)/2.1)*CH;
  const path=pts.map((p,i)=>`${i===0?"M":"L"} ${xs(p.h).toFixed(1)} ${ys(p.v).toFixed(1)}`).join(" ");
  const nx=xs(nowHour);
  const hourLabels=[0,6,12,18,24];
  const hl=v=>v===0?"12am":v===6?"6am":v===12?"12pm":v===18?"6pm":"12am";
  return(
    <svg width={W} height={h} viewBox={`0 0 ${W} ${h}`} style={{overflow:"visible"}}>
      <defs>
        <linearGradient id="tg" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stopColor={T.tide} stopOpacity="0.35"/>
          <stop offset="100%" stopColor={T.tide} stopOpacity="0.03"/>
        </linearGradient>
      </defs>
      {[0.5,1.0,1.5].map(v=>(
        <line key={v} x1={PL} x2={PL+CW} y1={ys(v)} y2={ys(v)}
          stroke={T.surface} strokeWidth={0.5}/>
      ))}
      {[0.5,1.0,1.5].map(v=>(
        <text key={v} x={PL-4} y={ys(v)+3} textAnchor="end"
          fill={T.muted} fontSize="8">{v}m</text>
      ))}
      <path d={`${path} L ${xs(24)} ${PT+CH} L ${PL} ${PT+CH} Z`}
        fill="url(#tg)"/>
      <path d={path} stroke={T.tide} strokeWidth={2} fill="none" strokeLinecap="round"/>
      <line x1={nx} x2={nx} y1={PT} y2={PT+CH}
        stroke={T.white} strokeWidth={1} strokeDasharray="3,3" opacity={0.4}/>
      <text x={nx} y={PT-3} textAnchor="middle" fill={T.white} fontSize="7" opacity={0.6}>NOW</text>
      {tides.map((t,i)=>{
        const tx=xs(t.hour),ty=ys(t.height);
        const labelY=t.type==="High"?ty-7:ty+13;
        return(
          <g key={i}>
            <circle cx={tx} cy={ty} r={3.5}
              fill={t.type==="High"?T.tide:T.muted}/>
            <text x={tx} y={labelY} textAnchor="middle"
              fill={T.muted} fontSize="7.5">{t.height}m</text>
          </g>
        );
      })}
      {hourLabels.map(v=>(
        <g key={v}>
          <line x1={xs(v)} x2={xs(v)} y1={PT+CH} y2={PT+CH+3}
            stroke={T.muted} strokeWidth={0.5}/>
          <text x={xs(v)} y={h-2} textAnchor="middle"
            fill={T.muted} fontSize="7.5">{hl(v)}</text>
        </g>
      ))}
    </svg>
  );
}

// ─── NOW TAB ─────────────────────────────────────────────────────────────────
function NowTab({consensus,disagreements,minMax,sources,historical}){
  const [tapped,setTapped]=useState(null);
  const os=overallScore(consensus);
  const rating=ratingText(consensus);
  const confPenalty=RINGS.reduce((p,r)=>{
    const d=disagreements[r.key];
    const w={temp:0.3,rain:0.3,wind:0.2,uv:0.1,humidity:0.1}[r.key]||0.1;
    if(d.isMajor)return p+w*0.9;
    if(d.isMinor)return p+w*0.4;
    return p;
  },0);
  const confScore=Math.max(0,1-confPenalty);
  const confColor=confScore>=0.8?T.good:confScore>=0.5?T.caution:T.bad;
  const flagCount=RINGS.filter(r=>disagreements[r.key]?.hasFlag).length;

  return(
    <div style={{paddingBottom:8}}>
      <div style={{padding:"14px 20px 0",display:"flex",alignItems:"center",gap:10}}>
        <span style={{fontSize:28}}>{rating.emoji}</span>
        <p style={{color:T.text,fontSize:14,lineHeight:1.4,margin:0,fontWeight:300}}>{rating.text}</p>
      </div>

      <div style={{display:"flex",flexDirection:"column",alignItems:"center",padding:"12px 0 4px"}}>
        <Dial consensus={consensus} disagreements={disagreements}
          minMax={minMax} sources={sources} tapped={tapped} onTap={setTapped}/>
        <div style={{display:"grid",gridTemplateColumns:"repeat(3, 1fr)",
          gap:8,marginTop:8,padding:"0 16px",width:"100%",
          maxWidth:400,boxSizing:"border-box"}}>
          {RINGS.map(r=>{
            const val=consensus[r.key];
            const score=r.scoreFromValue(val);
            const color=needleColor(r,score);
            const d=disagreements[r.key];
            const isTapped=tapped===r.key;
            return(
              <button key={r.key}
                onClick={()=>setTapped(isTapped?null:r.key)}
                style={{background:isTapped?`${color}22`:T.surface,
                  border:`1.5px solid ${isTapped?color+"70":"transparent"}`,
                  borderRadius:14,padding:"10px 6px",cursor:"pointer",
                  display:"flex",flexDirection:"column",alignItems:"center",
                  gap:3,minHeight:52}}>
                <div style={{display:"flex",alignItems:"center",gap:5}}>
                  <span style={{fontSize:17}}>{r.emoji}</span>
                  <span style={{color:color,fontSize:16,fontWeight:700}}>{r.format(val)}</span>
                </div>
                {d?.hasFlag&&(
                  <span style={{fontSize:9,color:d.isMajor?T.bad:T.caution,fontWeight:600}}>
                    {d.isMajor?"🚨":"⚠️"} varies
                  </span>
                )}
              </button>
            );
          })}
        </div>
      </div>

      <div style={{margin:"8px 16px",background:T.surface,borderRadius:10,
        padding:"8px 12px",display:"flex",alignItems:"center",gap:10}}>
        <div style={{flex:1,height:4,background:T.card,borderRadius:2,overflow:"hidden"}}>
          <div style={{height:4,background:confColor,
            width:`${confScore*100}%`,borderRadius:2}}/>
        </div>
        <span style={{fontSize:11,color:confColor,fontWeight:600,width:44}}>
          {Math.round(confScore*100)}% conf
        </span>
        {flagCount>0&&(
          <span style={{fontSize:11,color:T.caution}}>⚠️ {flagCount} vary</span>
        )}
      </div>

      <div style={{margin:"0 16px",background:T.card,borderRadius:12,padding:"10px 14px"}}>
        <div style={{color:T.muted,fontSize:10,textTransform:"uppercase",
          letterSpacing:"0.07em",marginBottom:8}}>📅 On this day</div>
        <div style={{display:"flex",gap:0}}>
          <div style={{textAlign:"center",flex:1}}>
            <div style={{color:T.white,fontSize:20,fontWeight:200}}>{consensus.temp}°</div>
            <div style={{color:T.muted,fontSize:9}}>today</div>
          </div>
          {[historical.oneYear,historical.fiveYear,historical.average].map((hh,i)=>{
            const diff=consensus.temp-hh.temp;
            const dc=diff>0?T.bad:diff<0?T.rain:T.muted;
            return(
              <div key={i} style={{flex:1,textAlign:"center",
                borderLeft:`1px solid ${T.surface}`}}>
                <div style={{color:T.text,fontSize:15,fontWeight:300}}>{hh.temp}°</div>
                <div style={{color:dc,fontSize:9,fontWeight:600}}>
                  {diff>0?"+":""}{diff}°
                </div>
                <div style={{color:T.muted,fontSize:8}}>{hh.label}</div>
              </div>
            );
          })}
        </div>
      </div>

      <div style={{marginTop:10,paddingLeft:16}}>
        <div style={{color:T.muted,fontSize:10,textTransform:"uppercase",
          letterSpacing:"0.07em",marginBottom:6}}>Hourly</div>
        <div style={{display:"flex",gap:4,overflowX:"auto",
          paddingRight:16,paddingBottom:4}}>
          {DATA.hourly.map((hh,i)=>(
            <div key={i} style={{minWidth:52,
              background:i===0?T.surface:"transparent",
              borderRadius:10,padding:"8px 6px",textAlign:"center"}}>
              <div style={{fontSize:10,color:T.muted}}>{hh.hour}</div>
              <div style={{fontSize:18,margin:"3px 0"}}>{hh.emoji}</div>
              <div style={{fontSize:13,color:T.white,fontWeight:500}}>{hh.temp}°</div>
              <div style={{fontSize:9,color:T.rain}}>{hh.rain}%</div>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}

// ─── TODAY TAB ───────────────────────────────────────────────────────────────
function TodayTab(){
  return(
    <div style={{padding:"16px 0 0"}}>
      <div style={{color:T.muted,fontSize:10,textTransform:"uppercase",
        letterSpacing:"0.07em",padding:"0 20px",marginBottom:10}}>Today's hourly breakdown</div>
      <div style={{background:T.card,borderRadius:16,margin:"0 16px",overflow:"hidden"}}>
        {DATA.hourly.map((hh,i)=>(
          <div key={i} style={{display:"flex",alignItems:"center",gap:12,
            padding:"12px 16px",
            borderBottom:i<DATA.hourly.length-1?`1px solid ${T.surface}`:"none",
            background:i===0?`${T.rain}08`:"transparent"}}>
            <div style={{width:38,color:i===0?T.white:T.muted,
              fontSize:13,fontWeight:i===0?600:400}}>{hh.hour}</div>
            <span style={{fontSize:20}}>{hh.emoji}</span>
            <div style={{flex:1,color:T.muted,fontSize:12}}>
              {hh.rain<=15?"Dry":hh.rain<=35?"Possible shower":"Rain likely"}
            </div>
            <div style={{display:"flex",alignItems:"center",gap:6}}>
              <div style={{width:32,height:5,background:T.surface,
                borderRadius:3,overflow:"hidden"}}>
                <div style={{height:5,background:T.rain,
                  width:`${hh.rain}%`,borderRadius:3}}/>
              </div>
              <span style={{color:T.rain,fontSize:11,width:28}}>{hh.rain}%</span>
            </div>
            <span style={{color:T.white,fontSize:15,fontWeight:500,
              width:34,textAlign:"right"}}>{hh.temp}°</span>
          </div>
        ))}
      </div>
    </div>
  );
}

// ─── WEEK TAB ────────────────────────────────────────────────────────────────
function WeekTab(){
  return(
    <div style={{padding:"16px 0 0"}}>
      <div style={{color:T.muted,fontSize:10,textTransform:"uppercase",
        letterSpacing:"0.07em",padding:"0 20px",marginBottom:10}}>7-day forecast</div>
      <div style={{background:T.card,borderRadius:16,margin:"0 16px",overflow:"hidden"}}>
        {DATA.daily.map((d,i)=>(
          <div key={i} style={{display:"flex",alignItems:"center",gap:12,
            padding:"13px 16px",
            borderBottom:i<DATA.daily.length-1?`1px solid ${T.surface}`:"none",
            background:i===0?`${T.rain}08`:"transparent"}}>
            <div style={{width:44,color:i===0?T.white:T.text,
              fontSize:14,fontWeight:i===0?600:400}}>{d.day}</div>
            <span style={{fontSize:22}}>{d.emoji}</span>
            <div style={{flex:1}}>
              {d.disagree&&(
                <span style={{fontSize:9,fontWeight:700,color:T.caution,
                  background:`${T.caution}20`,borderRadius:4,padding:"1px 5px"}}>
                  ⚠️ sources vary
                </span>
              )}
            </div>
            <span style={{color:T.rain,fontSize:11}}>💧{d.rain}%</span>
            <div style={{display:"flex",gap:6,width:60,justifyContent:"flex-end"}}>
              <span style={{color:T.white,fontSize:15,fontWeight:500}}>{d.high}°</span>
              <span style={{color:T.muted,fontSize:15}}>{d.low}°</span>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}

// ─── SCENE TAB ────────────────────────────────────────────────────────────────
// An illustrated alternate view: a beach house whose colours shift with time
// of day, water that rises and falls with the tide, and weather drawn as it
// happens. Built as proper layered illustration — soft gradients, glow,
// layered parallax waves, real house architecture — rather than flat shapes.

const SKY_KEYFRAMES=[
  {h:0,   top:"#040A16", mid:"#0A1830", bottom:"#122544", sun:null,  stars:1.0, glow:0},
  {h:4.5, top:"#0A1830", mid:"#16264A", bottom:"#2C3F63", sun:null,  stars:0.7, glow:0},
  {h:5.8, top:"#2B3A63", mid:"#8B5A6B", bottom:"#FFA366", sun:"rise",stars:0.15,glow:0.6},
  {h:7,   top:"#6FA8D0", mid:"#9AC8DE", bottom:"#FFD9A0", sun:"low", stars:0,   glow:0.35},
  {h:9.5, top:"#4A9AD4", mid:"#7EC3E8", bottom:"#D6EEF7", sun:"high",stars:0,   glow:0.15},
  {h:14.5,top:"#4A9AD4", mid:"#7EC3E8", bottom:"#D6EEF7", sun:"high",stars:0,   glow:0.15},
  {h:16.5,top:"#5B8DC7", mid:"#8FB4D8", bottom:"#FFDDA8", sun:"low", stars:0,   glow:0.3},
  {h:18,  top:"#4A4C8C", mid:"#B0587A", bottom:"#FF9159", sun:"set", stars:0.1, glow:0.7},
  {h:19.2,top:"#241E4C", mid:"#5C3A63", bottom:"#B45C5A", sun:null, stars:0.45,glow:0.25},
  {h:20.5,top:"#0F1730", mid:"#1B2748", bottom:"#2E3A5E", sun:null, stars:0.8, glow:0},
  {h:24,  top:"#040A16", mid:"#0A1830", bottom:"#122544", sun:null, stars:1.0, glow:0},
];

function lerpNum(a,b,t){return a+(b-a)*t;}
function hexLerp(h1,h2,t){
  const p=h=>[parseInt(h.slice(1,3),16),parseInt(h.slice(3,5),16),parseInt(h.slice(5,7),16)];
  const[r1,g1,b1]=p(h1),[r2,g2,b2]=p(h2);
  return `rgb(${Math.round(lerpNum(r1,r2,t))},${Math.round(lerpNum(g1,g2,t))},${Math.round(lerpNum(b1,b2,t))})`;
}
function skyAt(hour){
  const kf=SKY_KEYFRAMES;
  for(let i=0;i<kf.length-1;i++){
    if(hour>=kf[i].h&&hour<=kf[i+1].h){
      const t=(hour-kf[i].h)/(kf[i+1].h-kf[i].h);
      return{
        top:hexLerp(kf[i].top,kf[i+1].top,t),
        mid:hexLerp(kf[i].mid,kf[i+1].mid,t),
        bottom:hexLerp(kf[i].bottom,kf[i+1].bottom,t),
        sun:t<0.5?kf[i].sun:kf[i+1].sun,
        stars:lerpNum(kf[i].stars,kf[i+1].stars,t),
        glow:lerpNum(kf[i].glow,kf[i+1].glow,t),
      };
    }
  }
  return kf[kf.length-1];
}

// Deterministic star field — stable across renders, varied sizes for depth
const STARS=Array.from({length:45}).map((_,i)=>({
  x:(i*41+7)%330+5,
  y:(i*59+3)%140+8,
  r:0.5+((i*13)%10)/12,
  bright:0.4+((i*23)%10)/14,
}));

function SceneTab({consensus}){
  const hour=DATA.nowHour;
  const sky=skyAt(hour);
  const rain=consensus.rain;
  const wind=consensus.wind;

  const tideMin=Math.min(...DATA.tides.map(t=>t.height));
  const tideMax=Math.max(...DATA.tides.map(t=>t.height));
  const sorted=[...DATA.tides].sort((a,b)=>a.hour-b.hour);
  let tideNow=sorted[0].height;
  for(let i=0;i<sorted.length-1;i++){
    if(hour>=sorted[i].hour&&hour<=sorted[i+1].hour){
      const t=(hour-sorted[i].hour)/(sorted[i+1].hour-sorted[i].hour);
      const eased=(1-Math.cos(t*Math.PI))/2;
      tideNow=lerpNum(sorted[i].height,sorted[i+1].height,eased);
    }
  }
  const tideFrac=(tideNow-tideMin)/(tideMax-tideMin||1);

  const W=340,H=460;
  const waterBaseY=318;
  const waterRange=34;
  const waterY=waterBaseY-(tideFrac-0.5)*2*waterRange;

  const isNight=sky.sun===null;
  const isDawnDusk=sky.sun==="rise"||sky.sun==="set"||sky.sun==="low";
  const cloudCover=rain>15?Math.min(1,rain/65):0.12;
  const isRaining=rain>25;
  const rainHeavy=rain>55;
  const windy=wind>22;

  // Palette that responds to time of day rather than a single flat silhouette
  const houseWall   = isNight?"#151E30":isDawnDusk?"#3B2A38":"#EDE3D3";
  const houseWallSh  = isNight?"#0D1420":isDawnDusk?"#2A1D28":"#D8C9AE";
  const houseRoof   = isNight?"#0A0F1A":isDawnDusk?"#2E1E2A":"#9B4B3F";
  const houseRoofSh = isNight?"#050810":isDawnDusk?"#20141C":"#7A362D";
  const houseTrim   = isNight?"#0A0F1A":isDawnDusk?"#241620":"#FDFBF5";
  const windowLit   = isNight||sky.sun==="set"||sky.sun==="rise";
  const windowColor = windowLit?"#FFC96B":(isNight?"#1A2438":"#6FA8C9");
  const doorColor   = isNight?"#080C14":isDawnDusk?"#1C1220":"#7A4A2E";
  const sandTop     = isNight?"#2A2216":isDawnDusk?"#6B4A3E":"#E8CE9C";
  const sandLow     = isNight?"#1A1610":isDawnDusk?"#4A3128":"#D4AF77";

  const sunY=sky.sun==="rise"?276:sky.sun==="low"?150:sky.sun==="set"?276:66;
  const sunX=sky.sun==="rise"?54:sky.sun==="set"?286:170;
  const sunColor=sky.sun==="high"?"#FFEFB0":"#FFB876";
  const sunGlowR=sky.sun==="high"?70:95;

  return(
    <div style={{padding:0}}>
      <div style={{position:"relative",width:"100%",maxWidth:W,margin:"0 auto",
        height:H,overflow:"hidden",background:"#000"}}>
        <svg width="100%" height={H} viewBox={`0 0 ${W} ${H}`} style={{display:"block"}}>
          <defs>
            <linearGradient id="skyGrad" x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%"  stopColor={sky.top}/>
              <stop offset="55%" stopColor={sky.mid}/>
              <stop offset="100%" stopColor={sky.bottom}/>
            </linearGradient>
            <radialGradient id="sunGlow" cx="50%" cy="50%" r="50%">
              <stop offset="0%"  stopColor={sunColor} stopOpacity="0.9"/>
              <stop offset="45%" stopColor={sunColor} stopOpacity="0.35"/>
              <stop offset="100%" stopColor={sunColor} stopOpacity="0"/>
            </radialGradient>
            <linearGradient id="waterFar" x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%"  stopColor={isNight?"#0E2036":hexLerp(sky.bottom,"#0B3A55",0.55)} stopOpacity="0.95"/>
              <stop offset="100%" stopColor={isNight?"#0A1826":hexLerp(sky.bottom,"#08283D",0.7)} stopOpacity="1"/>
            </linearGradient>
            <linearGradient id="waterNear" x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%"  stopColor={isNight?"#122A42":hexLerp(sky.bottom,"#0D3C58",0.35)}/>
              <stop offset="100%" stopColor={isNight?"#081420":hexLerp(sky.bottom,"#052232",0.6)}/>
            </linearGradient>
            <linearGradient id="sandGrad" x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%"  stopColor={sandTop}/>
              <stop offset="100%" stopColor={sandLow}/>
            </linearGradient>
            <linearGradient id="roofGrad" x1="0" y1="0" x2="1" y2="1">
              <stop offset="0%"  stopColor={houseRoof}/>
              <stop offset="100%" stopColor={houseRoofSh}/>
            </linearGradient>
            <filter id="softBlur" x="-50%" y="-50%" width="200%" height="200%">
              <feGaussianBlur stdDeviation="1.2"/>
            </filter>
          </defs>

          {/* Sky */}
          <rect x="0" y="0" width={W} height={H} fill="url(#skyGrad)"/>

          {/* Stars, twinkling depth via varied size/opacity */}
          {sky.stars>0.05&&STARS.map((s,i)=>(
            <circle key={i} cx={s.x} cy={s.y} r={s.r}
              fill="#FFFFFF" opacity={sky.stars*s.bright}/>
          ))}

          {/* Sun/moon glow halo, then disc */}
          {sky.sun&&(
            <>
              <circle cx={sunX} cy={sunY} r={sunGlowR} fill="url(#sunGlow)"/>
              <circle cx={sunX} cy={sunY} r={sky.sun==="high"?24:30} fill={sunColor}/>
            </>
          )}
          {isNight&&(
            <>
              <circle cx={278} cy={54} r={22} fill="url(#sunGlow)" opacity={0.5}/>
              <circle cx={278} cy={54} r={16} fill="#EDEFF4"/>
              {/* moon craters for a touch of texture */}
              <circle cx={273} cy={49} r={2.6} fill="#D7DAE2" opacity={0.6}/>
              <circle cx={282} cy={58} r={1.8} fill="#D7DAE2" opacity={0.5}/>
              <circle cx={280} cy={48} r={1.3} fill="#D7DAE2" opacity={0.5}/>
            </>
          )}

          {/* Layered fluffy clouds — soft, multi-lobed, with a subtle shadow lobe */}
          {Array.from({length:Math.round(2+cloudCover*4)}).map((_,i)=>{
            const cx=36+i*74+(i%3)*14;
            const cy=42+((i*31)%36);
            const scale=0.75+((i*17)%6)/10;
            const op=0.5+cloudCover*0.45;
            return(
              <g key={i} opacity={op} transform={`translate(${cx},${cy}) scale(${scale})`}>
                <ellipse cx="2" cy="4" rx="30" ry="13" fill="#0A1830" opacity="0.18"/>
                <ellipse cx="0" cy="0" rx="28" ry="13" fill="#FFFFFF"/>
                <ellipse cx="20" cy="-5" rx="19" ry="11" fill="#FFFFFF"/>
                <ellipse cx="-18" cy="1" rx="17" ry="10" fill="#FFFFFF"/>
                <ellipse cx="6" cy="-9" rx="14" ry="9" fill="#FFFFFF"/>
              </g>
            );
          })}

          {/* Distant seagulls — small, only on calmer/clearer days, add life */}
          {!isRaining&&!isNight&&[  [60,90],[95,78],[250,100] ].map(([gx,gy],i)=>(
            <path key={i} d={`M${gx-7},${gy} Q${gx-3},${gy-5} ${gx},${gy} Q${gx+3},${gy-5} ${gx+7},${gy}`}
              stroke={isDawnDusk?"#3A2A38":"#3A3A44"} strokeWidth="1.4" fill="none"
              strokeLinecap="round" opacity="0.55"/>
          ))}

          {/* Rain — layered near/far for depth, slanted with wind */}
          {isRaining&&Array.from({length:rainHeavy?34:16}).map((_,i)=>{
            const rx=(i*23+11)%W;
            const ry=(i*37)%210+70;
            const len=rainHeavy?18:11;
            const slant=windy?11:4;
            const near=i%2===0;
            return(
              <line key={i} x1={rx} y1={ry} x2={rx-slant} y2={ry+len}
                stroke="#BFE0F5" strokeWidth={near?1.6:1}
                opacity={near?0.6:0.35} strokeLinecap="round"/>
            );
          })}

          {/* ── WATER — two bands for parallax depth, gentle wave crests ── */}
          <path d={`M0,${waterY} C${W*0.2},${waterY-4} ${W*0.35},${waterY+3} ${W*0.5},${waterY}
                    C${W*0.65},${waterY-3} ${W*0.8},${waterY+4} ${W},${waterY}
                    L${W},${waterY+40} L0,${waterY+40} Z`} fill="url(#waterFar)"/>
          <path d={`M0,${waterY+34} C${W*0.22},${waterY+30} ${W*0.4},${waterY+38} ${W*0.5},${waterY+34}
                    C${W*0.7},${waterY+29} ${W*0.85},${waterY+38} ${W},${waterY+34}
                    L${W},${H} L0,${H} Z`} fill="url(#waterNear)"/>
          {/* Wave crest highlight lines — subtle, catch the light */}
          {[0,1,2].map(i=>(
            <path key={i}
              d={`M0,${waterY+8+i*14} Q${W*0.25},${waterY+4+i*14} ${W*0.5},${waterY+8+i*14} T${W},${waterY+8+i*14}`}
              stroke={isNight?"#3A5A78":"#EAF6FB"} strokeWidth={1.1} fill="none"
              opacity={0.3-i*0.08}/>
          ))}
          {/* Small whitecap flecks when windy */}
          {windy&&Array.from({length:8}).map((_,i)=>(
            <ellipse key={i} cx={(i*41+20)%W} cy={waterY+10+((i*17)%50)}
              rx="4" ry="1.4" fill="#FFFFFF" opacity="0.35"/>
          ))}

          {/* Beach — soft crescent shoreline meeting the water */}
          <path d={`M0,${waterY+2} Q${W*0.5},${waterY-6} ${W},${waterY+2}
                    L${W},${H} L0,${H} Z`} fill="url(#sandGrad)"/>
          {/* Sand texture flecks */}
          {Array.from({length:14}).map((_,i)=>(
            <ellipse key={i} cx={(i*61+30)%W} cy={waterY+20+((i*23)%80)}
              rx="2.4" ry="1" fill={isNight?"#000":"#8A6A45"} opacity="0.15"
              transform={`rotate(${(i*37)%180} ${(i*61+30)%W} ${waterY+20+((i*23)%80)})`}/>
          ))}

          {/* ── PALM TREE — adds scale, life, and a wind indicator ── */}
          <g transform={`translate(48, ${waterY-64})`}>
            {/* trunk with a gentle lean, more lean when windy */}
            <path d={`M6,86 Q${windy?-6:-2},50 ${windy?2:4},0`}
              stroke={isNight?"#1A130E":isDawnDusk?"#2E1D16":"#5C4230"}
              strokeWidth="7" fill="none" strokeLinecap="round"/>
            {/* fronds — droop/sway direction shifts with wind */}
            {[-1,-0.5,0,0.6,1.1].map((dir,i)=>{
              const bend=windy?26:14;
              const baseX=windy?2:4, baseY=0;
              const tipX=baseX+dir*30+ (windy?dir*14:0);
              const tipY=baseY-14-Math.abs(dir)*6;
              const midX=baseX+dir*bend*0.6;
              const midY=baseY-10-Math.abs(dir)*10;
              return(
                <path key={i}
                  d={`M${baseX},${baseY} Q${midX},${midY} ${tipX},${tipY}`}
                  stroke={isNight?"#141C10":isDawnDusk?"#2A2418":"#3E6B3E"}
                  strokeWidth="5" fill="none" strokeLinecap="round" opacity="0.92"/>
              );
            })}
          </g>

          {/* ── BEACH HOUSE — proper proportions: pitched roof, trim, porch, steps ── */}
          <g transform={`translate(${W/2-62}, ${waterY-140})`}>
            {/* Soft ground shadow under the house */}
            <ellipse cx="62" cy="132" rx="76" ry="8" fill="#000" opacity="0.18"/>

            {/* Stilts (classic beach house on piers) */}
            <rect x="14" y="94" width="6" height="34" fill={houseWallSh}/>
            <rect x="104" y="94" width="6" height="34" fill={houseWallSh}/>
            <rect x="58" y="94" width="6" height="34" fill={houseWallSh}/>

            {/* Main body */}
            <rect x="4" y="46" width="120" height="52" fill={houseWall}/>
            {/* Body shading — right side in shadow for a touch of 3D */}
            <rect x="94" y="46" width="30" height="52" fill={houseWallSh} opacity="0.55"/>

            {/* Roof — pitched with overhang and a ridge highlight */}
            <path d="M-10,46 L64,6 L138,46 Z" fill="url(#roofGrad)"/>
            <path d="M64,6 L138,46 L128,46 Z" fill={houseRoofSh} opacity="0.5"/>
            {/* Roof trim line */}
            <path d="M-10,46 L64,6 L138,46" stroke={houseTrim} strokeWidth="2" fill="none" opacity="0.7"/>

            {/* Chimney */}
            <rect x="96" y="14" width="10" height="24" fill={houseWallSh}/>
            <rect x="94" y="12" width="14" height="5" fill={houseTrim} opacity="0.8"/>

            {/* Porch roof + posts */}
            <path d="M-8,74 L18,58 L18,74 Z" fill={houseRoofSh} opacity="0.85"/>
            <rect x="-6" y="74" width="4" height="24" fill={houseTrim} opacity="0.7"/>
            <rect x="12" y="74" width="4" height="24" fill={houseTrim} opacity="0.7"/>

            {/* Windows with mullions, warm glow at night/dusk */}
            <g>
              <rect x="20" y="58" width="20" height="20" rx="1" fill={windowColor}
                opacity={windowLit?0.95:0.85}/>
              <line x1="30" y1="58" x2="30" y2="78" stroke={houseTrim} strokeWidth="1.4" opacity="0.8"/>
              <line x1="20" y1="68" x2="40" y2="68" stroke={houseTrim} strokeWidth="1.4" opacity="0.8"/>
              <rect x="20" y="58" width="20" height="20" rx="1" fill="none"
                stroke={houseTrim} strokeWidth="1.6" opacity="0.9"/>
            </g>
            <g>
              <rect x="82" y="58" width="20" height="20" rx="1" fill={windowColor}
                opacity={windowLit?0.95:0.85}/>
              <line x1="92" y1="58" x2="92" y2="78" stroke={houseTrim} strokeWidth="1.4" opacity="0.8"/>
              <line x1="82" y1="68" x2="102" y2="68" stroke={houseTrim} strokeWidth="1.4" opacity="0.8"/>
              <rect x="82" y="58" width="20" height="20" rx="1" fill="none"
                stroke={houseTrim} strokeWidth="1.6" opacity="0.9"/>
            </g>
            {/* Window glow halo when lit */}
            {windowLit&&(
              <>
                <circle cx="30" cy="68" r="16" fill={windowColor} opacity="0.25" filter="url(#softBlur)"/>
                <circle cx="92" cy="68" r="16" fill={windowColor} opacity="0.25" filter="url(#softBlur)"/>
              </>
            )}

            {/* Door with a small window pane and handle */}
            <rect x="54" y="64" width="18" height="34" rx="1" fill={doorColor}/>
            <rect x="58" y="68" width="10" height="10" fill={windowColor} opacity={windowLit?0.7:0.4}/>
            <circle cx="68" cy="82" r="1.4" fill={houseTrim} opacity="0.9"/>

            {/* Steps down to the sand */}
            <rect x="50" y="98" width="26" height="5" fill={houseWallSh} opacity="0.8"/>
            <rect x="52" y="103" width="22" height="5" fill={houseWallSh} opacity="0.7"/>

            {/* Deck rail along the front */}
            {Array.from({length:9}).map((_,i)=>(
              <line key={i} x1={8+i*13} y1={98} x2={8+i*13} y2={108}
                stroke={houseTrim} strokeWidth="2" opacity="0.55"/>
            ))}
            <line x1="4" y1="98" x2="124" y2="98" stroke={houseTrim} strokeWidth="2" opacity="0.6"/>
          </g>

          {/* ── FOREGROUND DUNE GRASS — bends with real wind speed ── */}
          {Array.from({length:11}).map((_,i)=>{
            const gx=14+i*32;
            const bend=windy?22:7;
            const dir=i%2===0?1:-1;
            const h1=H-8,h2=H-38,h3=H-62;
            return(
              <path key={i}
                d={`M${gx},${h1} Q${gx+bend*dir*0.6},${h2} ${gx+bend*dir},${h3}`}
                stroke={isNight?"#0E1A10":isDawnDusk?"#2A2418":"#3F6B3F"}
                strokeWidth="2.6" fill="none" strokeLinecap="round" opacity="0.9"/>
            );
          })}

          {/* Gentle vignette for depth/focus */}
          <rect x="0" y="0" width={W} height={H} fill="#000"
            opacity="0.06" style={{mixBlendMode:"multiply"}}/>
        </svg>

        {/* Overlay: time + tide readout, glassy pill */}
        <div style={{position:"absolute",top:14,left:14,
          background:"rgba(8,16,28,0.5)",backdropFilter:"blur(6px)",
          border:"1px solid rgba(255,255,255,0.08)",
          borderRadius:12,padding:"7px 13px"}}>
          <div style={{color:"#fff",fontSize:14,fontWeight:600}}>
            {hour<12?`${Math.floor(hour)}:${String(Math.round((hour%1)*60)).padStart(2,"0")} AM`
              :`${Math.floor(hour)===12?12:Math.floor(hour)-12}:${String(Math.round((hour%1)*60)).padStart(2,"0")} PM`}
          </div>
          <div style={{color:"rgba(255,255,255,0.7)",fontSize:10,marginTop:1}}>
            {isNight?"Night":sky.sun==="rise"?"Sunrise":sky.sun==="set"?"Sunset":sky.sun==="low"?"Golden hour":"Daytime"}
          </div>
        </div>
        <div style={{position:"absolute",top:14,right:14,
          background:"rgba(8,16,28,0.5)",backdropFilter:"blur(6px)",
          border:"1px solid rgba(255,255,255,0.08)",
          borderRadius:12,padding:"7px 13px",textAlign:"right"}}>
          <div style={{color:"#fff",fontSize:14,fontWeight:600}}>{tideNow.toFixed(1)}m</div>
          <div style={{color:"rgba(255,255,255,0.7)",fontSize:10,marginTop:1}}>
            tide {tideFrac>0.6?"rising":tideFrac<0.4?"low":"turning"}
          </div>
        </div>
      </div>

      <div style={{padding:"14px 16px 0"}}>
        <div style={{color:T.muted,fontSize:10,textTransform:"uppercase",
          letterSpacing:"0.07em",marginBottom:10}}>🏖 What the scene shows</div>
        <div style={{display:"grid",gridTemplateColumns:"1fr 1fr",gap:8}}>
          {[
            {icon:"🌅",label:"Sky colour",   desc:"Time of day, live"},
            {icon:"🌊",label:"Water line",   desc:`${tideNow.toFixed(1)}m tide height`},
            {icon:"☁️",label:"Cloud cover",  desc:`${Math.round(cloudCover*100)}% from rain chance`},
            {icon:"🌧",label:"Rain",         desc:isRaining?`Falling · ${rain}% chance`:"Dry right now"},
            {icon:"🌴",label:"Palm sway",    desc:`${wind} km/h wind`},
            {icon:"✨",label:"Stars",        desc:isNight?"Visible now":"Daytime — hidden"},
          ].map(item=>(
            <div key={item.label} style={{background:T.card,borderRadius:12,
              padding:"10px 12px",display:"flex",alignItems:"center",gap:8}}>
              <span style={{fontSize:18}}>{item.icon}</span>
              <div>
                <div style={{color:T.text,fontSize:11,fontWeight:600}}>{item.label}</div>
                <div style={{color:T.muted,fontSize:10}}>{item.desc}</div>
              </div>
            </div>
          ))}
        </div>
        <div style={{color:T.muted,fontSize:10,lineHeight:1.6,marginTop:10,paddingBottom:16}}>
          Redraws continuously through the day. Sky blends smoothly between dawn, day,
          dusk and night keyframes. Water rises and falls with real tide predictions.
          Rain and cloud density map directly to forecast probability.
        </div>
      </div>
    </div>
  );
}

// ─── TIDES TAB ───────────────────────────────────────────────────────────────
function TidesTab(){
  return(
    <div style={{padding:"16px 16px 0"}}>
      <div style={{background:T.card,borderRadius:16,padding:16,marginBottom:10}}>
        <div style={{color:T.muted,fontSize:10,textTransform:"uppercase",
          letterSpacing:"0.07em",marginBottom:12}}>🌊 Today's tides · Mt Stapylton</div>
        <TideCurve tides={DATA.tides} nowHour={DATA.nowHour} height={110}/>
        <div style={{display:"flex",borderTop:`1px solid ${T.surface}`,
          paddingTop:12,marginTop:8}}>
          {DATA.tides.map((t,i)=>(
            <div key={i} style={{flex:1,textAlign:"center",
              borderLeft:i>0?`1px solid ${T.surface}`:"none"}}>
              <div style={{fontSize:9,fontWeight:700,
                color:t.type==="High"?T.tide:T.muted,
                textTransform:"uppercase"}}>{t.type}</div>
              <div style={{color:T.white,fontSize:18,
                fontWeight:200,margin:"2px 0"}}>{t.height}m</div>
              <div style={{color:T.muted,fontSize:11}}>{t.time}</div>
            </div>
          ))}
        </div>
      </div>
      <div style={{background:T.card,borderRadius:16,padding:16}}>
        <div style={{display:"flex",justifyContent:"space-between",alignItems:"center"}}>
          <div>
            <div style={{color:T.muted,fontSize:10,textTransform:"uppercase",
              letterSpacing:"0.07em",marginBottom:6}}>🌔 Moon</div>
            <div style={{color:T.moon,fontSize:18,fontWeight:500}}>
              {DATA.moon.emoji} {DATA.moon.phase}
            </div>
            <div style={{color:T.muted,fontSize:12,marginTop:2}}>
              Full moon in {DATA.moon.nextFullDays} days
            </div>
          </div>
          <div style={{textAlign:"right"}}>
            <div style={{color:T.moon,fontSize:40,fontWeight:200}}>
              {DATA.moon.illumination}%
            </div>
            <div style={{color:T.muted,fontSize:10}}>illuminated</div>
          </div>
        </div>
      </div>
    </div>
  );
}

// ─── PLANS TAB ───────────────────────────────────────────────────────────────
function PlansTab(){
  const IS={
    major:{bg:`${T.bad}12`,border:`${T.bad}40`,emoji:"🚨",color:T.bad},
    watch:{bg:`${T.caution}12`,border:`${T.caution}40`,emoji:"⚠️",color:T.caution},
    minor:{bg:`${T.good}08`,border:`${T.good}30`,emoji:"🌦",color:T.good},
    clear:{bg:T.card,border:"transparent",emoji:"✅",color:T.good},
  };
  return(
    <div style={{padding:"16px 16px 0"}}>
      <div style={{color:T.muted,fontSize:10,textTransform:"uppercase",
        letterSpacing:"0.07em",marginBottom:12}}>📆 Upcoming outdoor events</div>
      {DATA.calendarEvents.map(e=>{
        const s=IS[e.impact];
        const condEmoji=e.rain>50?"🌧":e.rain>20?"⛅":"☀️";
        return(
          <div key={e.id} style={{background:s.bg,border:`1px solid ${s.border}`,
            borderRadius:14,padding:"12px 14px",marginBottom:8}}>
            <div style={{display:"flex",justifyContent:"space-between",alignItems:"flex-start"}}>
              <div style={{flex:1}}>
                <div style={{display:"flex",alignItems:"center",gap:6,marginBottom:3}}>
                  <span style={{fontSize:14}}>{s.emoji}</span>
                  <span style={{color:T.white,fontSize:14,fontWeight:600}}>{e.title}</span>
                </div>
                <div style={{color:T.muted,fontSize:11}}>{e.date} · {e.time}</div>
                {e.warning&&(
                  <div style={{color:s.color,fontSize:11,marginTop:6,lineHeight:1.4}}>
                    {e.warning}
                  </div>
                )}
              </div>
              <div style={{textAlign:"right",marginLeft:10}}>
                <div style={{fontSize:20}}>{condEmoji}</div>
                <div style={{color:T.white,fontSize:13,fontWeight:600}}>{e.temp}°</div>
                <div style={{color:T.rain,fontSize:11}}>{e.rain}%💧</div>
              </div>
            </div>
          </div>
        );
      })}
      <div style={{background:T.card,borderRadius:12,padding:10,marginTop:2}}>
        <div style={{color:T.muted,fontSize:10,lineHeight:1.6}}>
          Reads your Apple Calendar · Flags events with outdoor keywords · Updates as forecast changes
        </div>
      </div>
    </div>
  );
}

// ─── UV TAB ──────────────────────────────────────────────────────────────────
const UV_LEVELS=[
  {max:2, label:"Low",       color:"#3DD68C"},
  {max:5, label:"Moderate",  color:"#F5A623"},
  {max:7, label:"High",      color:"#F87171"},
  {max:10,label:"Very High", color:"#E05555"},
  {max:20,label:"Extreme",   color:"#C084FC"},
];
function UVTab(){
  const [showKids,setShowKids]=useState(true);
  const uv=DATA.uv;
  const lvl=UV_LEVELS.find(l=>uv<=l.max)||UV_LEVELS[0];
  const pct=Math.min(1,uv/14);
  const CX=100,CY=100,R=78;

  function uvArc(a1,a2,r){
    function pt(deg){
      const rad=((deg-90)*Math.PI)/180;
      return{x:CX+r*Math.cos(rad),y:CY+r*Math.sin(rad)};
    }
    const s=pt(a1),e=pt(a2);
    const la=Math.abs(a2-a1)>180?1:0,sw=a2>a1?1:0;
    return `M${s.x.toFixed(1)} ${s.y.toFixed(1)} A${r} ${r} 0 ${la} ${sw} ${e.x.toFixed(1)} ${e.y.toFixed(1)}`;
  }

  const fillAngle=-210+240*pct;
  const kidsText=uv<=2?"Fine for outdoor play."
    :uv<=5?"SPF 50+ sunscreen 20 min before going out. Wide-brim hat and UV sunglasses."
    :uv<=7?"Rashie + SPF 50+ essential. Reapply after swimming. Hat and sunglasses required."
    :"Keep babies under 12 months out of direct sun. Full protection required for all children.";

  return(
    <div style={{padding:"12px 16px 0"}}>
      <div style={{display:"flex",flexDirection:"column",alignItems:"center",marginBottom:14}}>
        <div style={{position:"relative",width:200,height:200}}>
          <svg width={200} height={200} viewBox="0 0 200 200" style={{position:"absolute"}}>
            <defs>
              <linearGradient id="uvg" x1="0%" y1="100%" x2="100%" y2="0%">
                <stop offset="0%"   stopColor="#3DD68C"/>
                <stop offset="25%"  stopColor="#F5A623"/>
                <stop offset="50%"  stopColor="#F87171"/>
                <stop offset="75%"  stopColor="#E05555"/>
                <stop offset="100%" stopColor="#C084FC"/>
              </linearGradient>
            </defs>
            <path d={uvArc(-210,-210+240,R)} stroke="#132D4A" strokeWidth={12}
              fill="none" strokeLinecap="round"/>
            {pct>0.01&&(
              <path d={uvArc(-210,fillAngle,R)} stroke="url(#uvg)" strokeWidth={12}
                fill="none" strokeLinecap="round"/>
            )}
          </svg>
          <div style={{position:"absolute",top:"50%",left:"50%",
            transform:"translate(-50%,-52%)",textAlign:"center",pointerEvents:"none"}}>
            <div style={{fontSize:9,color:T.muted,textTransform:"uppercase",
              letterSpacing:"0.07em"}}>UV Index</div>
            <div style={{fontSize:52,fontWeight:200,color:lvl.color,lineHeight:1}}>{uv}</div>
            <div style={{fontSize:14,color:lvl.color,fontWeight:600}}>{lvl.label}</div>
            <div style={{fontSize:9,color:T.muted,marginTop:2}}>
              Peak {DATA.uvPeak} · {DATA.uvPeakTime}
            </div>
          </div>
        </div>
        <div style={{background:`${lvl.color}15`,border:`1px solid ${lvl.color}30`,
          borderRadius:12,padding:"8px 16px",textAlign:"center"}}>
          <div style={{color:T.muted,fontSize:9,textTransform:"uppercase"}}>Protection required</div>
          <div style={{color:lvl.color,fontSize:15,fontWeight:600,marginTop:1}}>
            {DATA.sunProtection.start} – {DATA.sunProtection.end}
          </div>
        </div>
      </div>
      <div style={{display:"flex",justifyContent:"space-around",background:T.card,
        borderRadius:14,padding:"12px 8px",marginBottom:10}}>
        {[["👕","Slip","Cover up"],["🧴","Slop","SPF 50+"],["🧢","Slap","Hat"],
          ["🌳","Seek","Shade"],["🕶","Slide","Sunnies"]].map(([e,l,d])=>(
          <div key={l} style={{textAlign:"center",opacity:uv>=3?1:0.4}}>
            <div style={{fontSize:22}}>{e}</div>
            <div style={{fontSize:10,color:lvl.color,fontWeight:700,marginTop:2}}>{l}</div>
            <div style={{fontSize:8,color:T.muted,marginTop:1}}>{d}</div>
          </div>
        ))}
      </div>
      <button onClick={()=>setShowKids(p=>!p)}
        style={{width:"100%",background:showKids?`${lvl.color}18`:T.surface,
          border:`1px solid ${showKids?lvl.color+"50":T.surface}`,
          borderRadius:12,padding:"10px 14px",cursor:"pointer",
          textAlign:"left",color:showKids?lvl.color:T.muted,
          fontSize:13,fontWeight:600,marginBottom:8}}>
        👶 {showKids?"Hide":"Show"} children & babies advice
      </button>
      {showKids&&(
        <div style={{background:T.card,borderRadius:12,padding:"10px 14px",
          borderLeft:`3px solid ${lvl.color}`,color:T.text,
          fontSize:12,lineHeight:1.6}}>
          {kidsText}
        </div>
      )}
    </div>
  );
}

// ─── SKY TAB ─────────────────────────────────────────────────────────────────
function SkyTab(){
  const rarityColor={rare:T.astro,annual:T.muted,notable:T.moon};
  return(
    <div style={{padding:"16px 16px 0"}}>
      <div style={{color:T.muted,fontSize:10,textTransform:"uppercase",
        letterSpacing:"0.07em",marginBottom:12}}>🔭 Astronomical events</div>
      {DATA.astronomical.map((e,i)=>(
        <div key={i} style={{background:T.card,borderRadius:14,
          padding:"12px 14px",marginBottom:8,
          borderLeft:`3px solid ${rarityColor[e.rarity]||T.muted}`}}>
          <div style={{display:"flex",gap:10,alignItems:"center"}}>
            <span style={{fontSize:26}}>{e.emoji}</span>
            <div style={{flex:1}}>
              <div style={{display:"flex",justifyContent:"space-between"}}>
                <span style={{color:T.white,fontSize:14,fontWeight:600}}>{e.event}</span>
                <span style={{color:T.muted,fontSize:11}}>{e.date}</span>
              </div>
              <div style={{color:T.muted,fontSize:11,marginTop:3,lineHeight:1.4}}>{e.desc}</div>
              {e.rarity==="rare"&&(
                <div style={{marginTop:5,display:"inline-block",
                  background:`${T.astro}20`,color:T.astro,
                  fontSize:9,fontWeight:700,borderRadius:4,
                  padding:"2px 6px",textTransform:"uppercase",
                  letterSpacing:"0.06em"}}>Rare · Push notification set</div>
              )}
            </div>
          </div>
        </div>
      ))}
    </div>
  );
}

// ─── NEWS TAB ────────────────────────────────────────────────────────────────
function NewsTab(){
  return(
    <div style={{padding:"16px 16px 0"}}>
      <div style={{color:T.muted,fontSize:10,textTransform:"uppercase",
        letterSpacing:"0.07em",marginBottom:12}}>📰 Local weather news · SE Queensland</div>
      {DATA.news.map((n,i)=>(
        <div key={i} style={{
          background:n.impact==="high"?`${T.bad}10`:T.card,
          border:`1px solid ${n.impact==="high"?T.bad+"30":"transparent"}`,
          borderRadius:14,padding:"12px 14px",marginBottom:8}}>
          <div style={{display:"flex",justifyContent:"space-between",marginBottom:4}}>
            <div style={{display:"flex",alignItems:"center",gap:6}}>
              {n.isWarning&&(
                <span style={{fontSize:9,fontWeight:700,color:"#000",
                  background:T.bad,borderRadius:4,padding:"1px 5px",
                  textTransform:"uppercase",letterSpacing:"0.05em"}}>⚠ Official</span>
              )}
              <span style={{fontSize:9,fontWeight:700,
                color:n.impact==="high"?T.bad:T.muted,
                textTransform:"uppercase",letterSpacing:"0.07em"}}>{n.source}</span>
            </div>
            <span style={{fontSize:9,color:T.muted}}>{n.time}</span>
          </div>
          <div style={{color:T.white,fontSize:13,fontWeight:600,
            lineHeight:1.4,marginBottom:5}}>{n.headline}</div>
          <div style={{color:T.muted,fontSize:11,lineHeight:1.5}}>{n.excerpt}</div>
        </div>
      ))}

      {/* Warning sources footnote */}
      <div style={{background:T.card,borderRadius:12,padding:"11px 14px",marginTop:4}}>
        <div style={{color:T.muted,fontSize:10,textTransform:"uppercase",
          letterSpacing:"0.07em",marginBottom:6}}>Official warning sources</div>
        <div style={{color:T.muted,fontSize:11,lineHeight:1.7}}>
          <strong style={{color:T.text}}>BOM Warnings Summary</strong> — free RSS feed per state,
          covers severe thunderstorm, cyclone, flood, fire weather and marine warnings.<br/>
          <strong style={{color:T.text}}>BOM Anonymous FTP</strong> — same warning products as
          machine-readable XML, updated the moment a warning is issued.<br/>
          <strong style={{color:T.text}}>BOM Space Weather API</strong> — free with registration,
          covers geomagnetic storms and aurora alerts for the Australian region.<br/>
          High-impact warnings from these feeds surface immediately at the top of this list
          and on the Now screen, ahead of general news coverage.
        </div>
      </div>
    </div>
  );
}

// ─── SOURCES TAB ─────────────────────────────────────────────────────────────
function SourcesTab({consensus,disagreements}){
  const [tapped,setTapped]=useState(null);
  const confPenalty=RINGS.reduce((p,r)=>{
    const d=disagreements[r.key];
    const w={temp:0.3,rain:0.3,wind:0.2,uv:0.1,humidity:0.1}[r.key]||0.1;
    if(d.isMajor)return p+w*0.9;
    if(d.isMinor)return p+w*0.4;
    return p;
  },0);
  const confScore=Math.max(0,1-confPenalty);
  const confColor=confScore>=0.8?T.good:confScore>=0.5?T.caution:T.bad;
  const crowdTotal=Object.values(DATA.crowdVotes).reduce((a,b)=>a+b,0);
  const crowdRows=[{k:"great",e:"😎"},{k:"good",e:"🙂"},{k:"ok",e:"😐"},{k:"bad",e:"😬"},{k:"awful",e:"🥵"}];

  return(
    <div style={{padding:"16px 16px 0"}}>
      <div style={{background:T.card,borderRadius:14,padding:"12px 14px",marginBottom:10}}>
        <div style={{display:"flex",justifyContent:"space-between",
          alignItems:"center",marginBottom:8}}>
          <div style={{color:T.muted,fontSize:10,textTransform:"uppercase",
            letterSpacing:"0.07em"}}>📡 Source confidence</div>
          <div style={{display:"flex",gap:4}}>
            {Object.entries(SOURCES).map(([k,s])=>(
              <div key={k} style={{display:"flex",alignItems:"center",gap:3,
                background:T.surface,borderRadius:5,padding:"2px 5px"}}>
                <div style={{width:5,height:5,borderRadius:"50%",background:s.color}}/>
                <span style={{fontSize:8,color:T.muted}}>{s.short}</span>
              </div>
            ))}
          </div>
        </div>
        <div style={{display:"flex",alignItems:"center",gap:8}}>
          <div style={{flex:1,height:6,background:T.surface,borderRadius:3,overflow:"hidden"}}>
            <div style={{height:6,background:confColor,
              width:`${confScore*100}%`,borderRadius:3}}/>
          </div>
          <span style={{color:confColor,fontSize:13,fontWeight:700}}>
            {Math.round(confScore*100)}%
          </span>
        </div>
      </div>

      {RINGS.map(ring=>{
        const val=consensus[ring.key];
        const d=disagreements[ring.key];
        const isOpen=tapped===ring.key;
        const score=ring.scoreFromValue(val);
        const color=needleColor(ring,score);
        const barHalf=44;
        const barFill=Math.max(2,Math.abs(score)*barHalf);
        const barLeft=score>=0?`calc(${barHalf}px - ${barFill}px)`:"50%";

        return(
          <div key={ring.key} style={{marginBottom:6}}>
            <button onClick={()=>setTapped(isOpen?null:ring.key)}
              style={{width:"100%",background:isOpen?T.surface:T.card,
                border:`1px solid ${isOpen?color+"50":"transparent"}`,
                borderRadius:12,padding:"10px 14px",cursor:"pointer",textAlign:"left"}}>
              <div style={{display:"flex",alignItems:"center",gap:10}}>
                <span style={{fontSize:18}}>{ring.emoji}</span>
                <div style={{flex:1}}>
                  <div style={{display:"flex",justifyContent:"space-between",
                    alignItems:"center"}}>
                    <span style={{color:T.text,fontSize:13}}>{ring.label}</span>
                    <div style={{display:"flex",alignItems:"center",gap:6}}>
                      {d?.hasFlag&&(
                        <span style={{fontSize:9,
                          color:d.isMajor?T.bad:T.caution,fontWeight:700}}>
                          {d.isMajor?"🚨":"⚠️"} {d.spread}{ring.unit}
                        </span>
                      )}
                      <span style={{color,fontSize:14,fontWeight:700}}>
                        {ring.format(val)}
                      </span>
                    </div>
                  </div>
                  <div style={{display:"flex",alignItems:"center",gap:5,marginTop:5}}>
                    <span style={{fontSize:7,color:T.good,opacity:0.7}}>good ◀</span>
                    <div style={{flex:1,height:4,background:T.navy,
                      borderRadius:2,position:"relative",overflow:"hidden"}}>
                      <div style={{position:"absolute",left:"50%",top:0,
                        width:1,height:4,background:T.white,opacity:0.3,
                        transform:"translateX(-50%)"}}/>
                      <div style={{position:"absolute",top:0,height:4,
                        borderRadius:2,left:barLeft,width:barFill,background:color}}/>
                    </div>
                    <span style={{fontSize:7,color:T.bad,opacity:0.7}}>▶ not</span>
                    <span style={{color,fontSize:10,fontWeight:600}}>
                      {ring.comfortLabel(val)}
                    </span>
                  </div>
                </div>
              </div>
              {isOpen&&(
                <div style={{marginTop:10,paddingTop:10,
                  borderTop:`1px solid ${T.surface}`}}>
                  {d?.values.map(({source,value:sv})=>{
                    const src=SOURCES[source];
                    const sc=ring.scoreFromValue(sv);
                    const nc=needleColor(ring,sc);
                    const diff=sv-val;
                    const sf=Math.max(2,Math.abs(sc)*barHalf);
                    const sl=sc>=0?`calc(${barHalf}px - ${sf}px)`:"50%";
                    return(
                      <div key={source} style={{display:"flex",alignItems:"center",
                        gap:8,marginBottom:6}}>
                        <div style={{display:"flex",alignItems:"center",
                          gap:4,width:44}}>
                          <div style={{width:7,height:7,borderRadius:"50%",
                            background:src?.color}}/>
                          <span style={{color:T.muted,fontSize:10}}>{src?.short}</span>
                        </div>
                        <div style={{flex:1,height:4,background:T.navy,
                          borderRadius:2,position:"relative",overflow:"hidden"}}>
                          <div style={{position:"absolute",left:"50%",top:0,
                            width:1,height:4,background:T.white,opacity:0.25,
                            transform:"translateX(-50%)"}}/>
                          <div style={{position:"absolute",top:0,height:4,
                            borderRadius:2,left:sl,width:sf,background:nc}}/>
                        </div>
                        <span style={{color:T.white,fontSize:12,fontWeight:600,
                          width:30,textAlign:"right"}}>{ring.format(sv)}</span>
                        {diff!==0&&(
                          <span style={{fontSize:10,width:26,
                            color:Math.abs(diff)>=ring.disagreementThreshold
                              ?T.caution:T.muted}}>
                            {diff>0?"+":""}{diff}
                          </span>
                        )}
                      </div>
                    );
                  })}
                  <div style={{borderTop:`1px solid ${T.surface}`,
                    paddingTop:6,marginTop:4,
                    display:"flex",justifyContent:"space-between"}}>
                    <span style={{color:T.muted,fontSize:10}}>Consensus (trimmed mean)</span>
                    <span style={{color:T.white,fontSize:12,fontWeight:700}}>
                      {ring.format(val)}
                    </span>
                  </div>
                </div>
              )}
            </button>
          </div>
        );
      })}

      <div style={{background:T.card,borderRadius:14,padding:"12px 14px",marginTop:4}}>
        <div style={{color:T.muted,fontSize:10,textTransform:"uppercase",
          letterSpacing:"0.07em",marginBottom:8}}>
          👥 People's weather · {crowdTotal} votes today
        </div>
        {crowdRows.map(({k,e})=>{
          const count=DATA.crowdVotes[k]||0;
          const pct=crowdTotal>0?count/crowdTotal*100:0;
          return(
            <div key={k} style={{display:"flex",alignItems:"center",gap:8,marginBottom:5}}>
              <span style={{fontSize:16,width:22}}>{e}</span>
              <div style={{flex:1,height:5,background:T.surface,
                borderRadius:3,overflow:"hidden"}}>
                <div style={{height:5,background:T.muted,
                  width:`${pct}%`,borderRadius:3}}/>
              </div>
              <span style={{color:T.text,fontSize:11,width:22,textAlign:"right"}}>
                {count}
              </span>
            </div>
          );
        })}
        <div style={{color:T.muted,fontSize:9,marginTop:8}}>
          How does it actually feel outside? Tap to vote ↑
        </div>
      </div>
    </div>
  );
}

// ─── ROOT ─────────────────────────────────────────────────────────────────────
export default function SkyWarden(){
  const [tab,setTab]=useState("now");
  const consensus=calcConsensus(DATA.sources);
  const disagreements=calcDisagreements(DATA.sources);
  const flags={plans:true,news:true};

  function renderTab(){
    if(tab==="now")     return <NowTab consensus={consensus} disagreements={disagreements} minMax={DATA.minMax} sources={DATA.sources} historical={DATA.historical}/>;
    if(tab==="scene")   return <SceneTab consensus={consensus}/>;
    if(tab==="today")   return <TodayTab/>;
    if(tab==="week")    return <WeekTab/>;
    if(tab==="tides")   return <TidesTab/>;
    if(tab==="plans")   return <PlansTab/>;
    if(tab==="uv")      return <UVTab/>;
    if(tab==="sky")     return <SkyTab/>;
    if(tab==="news")    return <NewsTab/>;
    if(tab==="sources") return <SourcesTab consensus={consensus} disagreements={disagreements}/>;
    return null;
  }

  return(
    <div style={{background:T.navy,minHeight:"100vh",
      fontFamily:"'SF Pro Display',-apple-system,sans-serif",
      display:"flex",justifyContent:"center"}}>
      <div style={{width:"100%",maxWidth:430,paddingBottom:88}}>
        <div style={{padding:"14px 20px 0",display:"flex",
          justifyContent:"space-between",alignItems:"baseline"}}>
          <div>
            <div style={{color:T.muted,fontSize:11}}>📍 {DATA.location}</div>
            <div style={{color:T.white,fontSize:22,fontWeight:200,
              marginTop:1,letterSpacing:-0.5}}>SkyWarden</div>
          </div>
          <div style={{textAlign:"right"}}>
            <div style={{color:T.muted,fontSize:11}}>{DATA.date}</div>
            <div style={{color:T.white,fontSize:14,fontWeight:300}}>{DATA.time}</div>
          </div>
        </div>
        <div style={{minHeight:"70vh"}}>{renderTab()}</div>
        <TabBar active={tab} onTab={setTab} flags={flags}/>
      </div>
    </div>
  );
}
