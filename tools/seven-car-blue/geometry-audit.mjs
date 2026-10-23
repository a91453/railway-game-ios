// Read actual exported triangles, independent of declarations in the recipe.
import {readFileSync,writeFileSync} from 'node:fs';
import {resolve} from 'node:path';
import assert from 'node:assert/strict';
import {readNative} from '../station-kit/package.mjs';
const root=resolve(process.argv[2]),manifest=JSON.parse(readFileSync(resolve(root,'manifest.json')));
const sub=(a,b)=>a.map((v,i)=>v-b[i]),dot=(a,b)=>a.reduce((n,v,i)=>n+v*b[i],0),cross=(a,b)=>[a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]];
const key=p=>p.map(v=>(Math.round(v*1e5)/1e5).toFixed(5)).join(',');
function hit(o,d,t){
 const e1=sub(t[1].position,t[0].position),e2=sub(t[2].position,t[0].position),h=cross(d,e2),det=dot(e1,h);
 if(Math.abs(det)<1e-9)return Infinity;
 const s=sub(o,t[0].position),u=dot(s,h)/det;if(u < -1e-5||u>1.00001)return Infinity;
 const q=cross(s,e1),v=dot(d,q)/det;if(v < -1e-5||u+v>1.00001)return Infinity;
 const dist=dot(e2,q)/det;return dist>0.00001?dist:Infinity;
}
// Infer the outermost central windscreen triangle's colour from the actual
// leading unit. It is lighter than the older train glass by design.
const lead=readNative(readFileSync(resolve(root,manifest.models[0].native))).vertices;
const candidates=[];
for(let i=0;i<lead.length;i+=3){const t=lead.slice(i,i+3),o=[0,1,2].map(j=>t.reduce((s,v)=>s+v.position[j]/3,0));
 if(Math.hypot(...cross(sub(t[1].position,t[0].position),sub(t[2].position,t[0].position)))>0.5&&t[0].normal[0]>.9&&o[2]>1.5&&o[2]<2.6&&Math.abs(o[1])<.8&&o[0]>3.2)candidates.push({t,lift:o[0]+(o[2]-.40)*.18});}
candidates.sort((a,b)=>b.lift-a.lift);assert(candidates.length,'Missing actual windscreen');
const baseGlass=candidates[0].t[0].color;
const glass=baseGlass.join(',');
const glassFamily=[1,.92,.80,.70,.86].map(f=>baseGlass.map((v,i)=>i===3?v:Math.round(v*f)).join(','));
const isGlass=t=>glassFamily.includes(t[0].color.join(','));
const records=[];
export function audit(model,vs){
 const ts=Array.from({length:vs.length/3},(_,i)=>vs.slice(i*3,i*3+3)),edges=new Map();
 for(const t of ts)for(let i=0;i<3;i++){
  const a=key(t[i].position),b=key(t[(i+1)%3].position);assert.notEqual(a,b,'collapsed edge');
  const k=[a,b].sort().join('|'),e=edges.get(k)||{count:0,winding:0};e.count++;e.winding+=a<b?1:-1;edges.set(k,e);
 }
 const open=[...edges].filter(([,e])=>e.count%2||e.winding!==0);
 assert.equal(open.length,0,model.id+' open / reversed edges '+JSON.stringify(open.slice(0,2)));
 // Visible glass faces must have an opaque support, not just their own backing.
 let glazing=0,maxSupport=0,maxShell=0;
 const opaque=ts.filter(t=>!isGlass(t));
 const shell=opaque.filter(t=>Math.max(...t[0].color.slice(0,3))>=110);
 for(const t of ts){
  if(!isGlass(t))continue;
  const o=[0,1,2].map(i=>t.reduce((s,v)=>s+v.position[i]/3,0)),n=t[0].normal;
  const outsideSide=Math.abs(o[1])>1.14&&n[1]*o[1]>0.9&&Math.abs(n[0])<0.6&&Math.abs(n[2])<0.5;
  const outsideCab=Math.abs(o[0])>3.3&&Math.abs(o[1])<1.05&&Math.abs(n[1])<0.05&&n[0]*o[0]>3;
  if(!outsideSide&&!outsideCab)continue;
  const distance=Math.min(...opaque.map(q=>hit(o,n.map(x=>-x),q)));
  assert(distance<0.065,model.id+' unsupported glazing '+JSON.stringify({o,n,distance}));
  const bodyDistance=Math.min(...shell.map(q=>hit(o,n.map(x=>-x),q)));
  assert(bodyDistance<0.065,model.id+' glazing/frame pair lacks shell support '+JSON.stringify({o,n,bodyDistance}));
  maxShell=Math.max(maxShell,bodyDistance);maxSupport=Math.max(maxSupport,distance);glazing++;
 }
 assert(glazing>0,'No glass checked');
 const wheels=vs.filter(v=>v.color.join(',')==='43,46,52,255');
 const wheelTop=Math.max(...wheels.map(v=>v.position[2]));
 const spanningBottoms=ts.filter(t=>t[0].normal[2]<-.9&&Math.max(...t.map(v=>v.position[0]))-Math.min(...t.map(v=>v.position[0]))>(model.maximum[0]-model.minimum[0])*0.5 && Math.max(...t.map(v=>v.position[1]))-Math.min(...t.map(v=>v.position[1]))>2);
 const frameBottom=Math.min(...spanningBottoms.flatMap(t=>t.map(v=>v.position[2])));
 assert(frameBottom-wheelTop>=.049,model.id+' wheel crown penetrates full-width underframe');
 // Check the visible defect found in the first render: the skirt must hide
 // upper wheel faces while leaving the bottom of each actual wheel exposed.
 const xs=[...new Set(wheels.map(v=>v.position[0]))].sort((a,b)=>a-b),groups=[];
 for(const x of xs){if(!groups.length||x-groups.at(-1).at(-1)>.14)groups.push([]);groups.at(-1).push(x);}
 let skirtChecks=0;
 for(const group of groups){const x=(group[0]+group.at(-1))/2;
  for(const side of [-1,1]){
   const d=[0,side,0],upper=[x,side*1.16,wheelTop*.84],lower=[x,side*1.16,wheelTop*.12];
   const upperHit=Math.min(...opaque.map(t=>hit(upper,d,t))),lowerHit=Math.min(...opaque.map(t=>hit(lower,d,t)));
   assert(upperHit<.20,model.id+' skirt exposes upper wheel face');
   assert(!Number.isFinite(lowerHit),model.id+' skirt hides rail-contact wheel edge');skirtChecks++;
  }
 }
 const partIndex=manifest.models.filter(m=>m.category==='section').findIndex(m=>m.id===model.id);
 const half=manifest.assemblies.blue.body_lengths_m[partIndex]/2;
 const skirts=vs.filter(v=>Math.abs(v.position[1])>1.2&&Math.abs(v.position[0])<half-.12);
 const skirtBottom=Math.min(...skirts.map(v=>v.position[2]));
 const joints=[];
 for(const side of [-1,1]){
  if((model.id.endsWith('leading')&&side===1)||(model.id.endsWith('trailing')&&side===-1))continue;
  const joint=vs.filter(v=>v.position[0]*side>half+.01),bottom=Math.min(...joint.map(v=>v.position[2])),top=Math.max(...joint.map(v=>v.position[2]));
  assert(bottom-skirtBottom<.05,model.id+' gangway leaves an open notch above skirt');
  const skirtEndRay=[side*(half-.04),0,skirtBottom+.17];
  assert(Math.min(...opaque.map(t=>hit(skirtEndRay,[0,1,0],t)))<1.5,model.id+' skirt stops short of its gangway');
  assert(top>3.20,model.id+' gangway ends below shoulder');joints.push({side,bottom,top});
 }
 return {id:model.id,triangles:ts.length,welded_edges:edges.size,open_or_reversed_edges:open.length,glazing_triangles:glazing,skirt_wheel_occlusion_checks:skirtChecks,gangway_extents:joints,wheel_underframe_clearance_m:frameBottom-wheelTop,max_opaque_support_distance_m:maxSupport,max_shell_support_distance_m:maxShell};
}
for(const m of manifest.models.filter(m=>m.category==='section'))records.push(audit(m,readNative(readFileSync(resolve(root,m.native))).vertices));
writeFileSync(resolve(root,'geometry-verification.json'),JSON.stringify({status:'VERIFIED',glass_rgba:glass,checks:['closed directed welded edges','opaque support ray for each outward main glazing face'],models:records},null,2)+'\n');
console.log(JSON.stringify(records));
