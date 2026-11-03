// Actual native cab surfaces and normal closed-cover observations.
// This checks a photo-fitted model envelope, not surveyed engineering dimensions.
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {createHash} from 'node:crypto';
import {model} from '../train-models/native.mjs';
const orange=c=>c[0]>c[1]*1.1&&c[1]>c[2]*1.5&&c[0]>c[2]*1.9;
const blue=c=>c[2]>c[0]*1.5&&c[2]>c[1]*1.15;
const pointKey=p=>p.map(x=>Math.round(x*1e5)).join(',');
function outline(v){
 const painted=v.filter(p=>p.position[0]>9&&Math.abs(p.position[1])<1.35&&p.position[2]<2.1&&orange(p.color));
 assert(painted.length,'missing nose colour');const low=Math.min(...painted.map(p=>p.position[2])),high=Math.max(...painted.map(p=>p.position[2]));
 assert(low<1.5&&high<=1.90&&high-low>.40,'thin or raised moustache instead of the lower bowl');
 const edges=new Map();
 for(let i=0;i<v.length;i+=3){const t=v.slice(i,i+3),label=orange(t[0].color)?'orange':blue(t[0].color)?'blue':'other';if(label==='other')continue;
  for(let j=0;j<3;j++){const a=t[j].position,b=t[(j+1)%3].position;if(Math.min(a[0],b[0])<9||Math.max(Math.abs(a[1]),Math.abs(b[1]))>1.35||Math.min(a[2],b[2])<1.2||Math.max(a[2],b[2])>1.9)continue;const k=[pointKey(a),pointKey(b)].sort().join('|');if(!edges.has(k))edges.set(k,{a,b,labels:new Set()});edges.get(k).labels.add(label);}}
 const boundary=[...edges.values()].filter(e=>e.labels.has('orange')&&e.labels.has('blue'));assert(boundary.length>=12,'nose arc lacks a continuous subdivided colour boundary');
 const stairs=boundary.filter(e=>Math.abs(e.a[2]-e.b[2])<.0025&&Math.abs(e.a[1]-e.b[1])>.04);assert.equal(stairs.length,0,'staircase colour edge');return{orange_low_z_m:low,orange_high_z_m:high,boundary_edges:boundary.length,wide_horizontal_steps:stairs.length};
}
function hit(v,o,d){let best=null;const sub=(a,b)=>a.map((x,i)=>x-b[i]),cross=(a,b)=>[a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]],dot=(a,b)=>a.reduce((s,x,i)=>s+x*b[i],0);
 for(let i=0;i<v.length;i+=3){const [a,b,c]=v.slice(i,i+3).map(x=>x.position),e=sub(b,a),f=sub(c,a),h=cross(d,f),det=dot(e,h);if(Math.abs(det)<1e-10)continue;const s=sub(o,a),u=dot(s,h)/det,q=cross(s,e),w=dot(d,q)/det,t=dot(f,q)/det;if(u>=-1e-6&&w>=-1e-6&&u+w<=1+1e-6&&t>1e-5&&(!best||t<best.distance))best={distance:t,color:v[i].color};}return best;}
function cover(v){const front=hit(v,[20.743/2+.12,0,.92],[-1,0,0]);assert(front&&blue(front.color)&&front.distance<.36,'normal nose cover exposes a square frontal jaw');const under=hit(v,[20.743/2-.36,0,.40],[0,0,1]);assert(under&&under.distance>.30&&under.distance<.50&&!blue(under.color),'underside drawgear cavity filled or absent');return{front_cover_distance_m:front.distance,under_cavity_entry_distance_m:under.distance};}
const root=resolve(process.argv[2]),manifest=JSON.parse(readFileSync(root+'/manifest.json')),rows=[];
for(const m of manifest.models.filter(m=>m.id.includes('-emc')||m.native_kind==='assembly')){
 const bytes=readFileSync(resolve(root,m.native)),raw=model(bytes).vertices,ends=m.native_kind==='assembly'?[1,-1]:[1];
 for(const end of ends){const centre=m.native_kind==='assembly'?end*71.2715:0,v=raw.map(p=>({...p,position:[end*(p.position[0]-centre),end*p.position[1],p.position[2]]}));const shape=outline(v),housing=cover(v);
  const flat=v.map(p=>p.position[0]>9&&p.position[2]<1.90&&orange(p.color)?{...p,position:[p.position[0],p.position[1],1.70+(p.position[2]-1.40)*.3]}:p);assert.throws(()=>outline(flat),/moustache/);
  const absent=[];for(let i=0;i<v.length;i+=3){const tri=v.slice(i,i+3);if(!(blue(tri[0].color)&&tri.every(p=>p.position[0]>9.4&&p.position[2]<1.13)))absent.push(...tri);}assert.throws(()=>cover(absent),/square frontal jaw/);
  rows.push({id:m.id,end,native_sha256:createHash('sha256').update(bytes).digest('hex'),...shape,...housing,actual_flattened_paint_vertices_rejected:true,actual_front_hood_triangles_removed_rejected:true});
 }
}
writeFileSync(resolve(root,'mouth-verification.json'),JSON.stringify({status:'VERIFIED',models:rows,limits:'Specified native paint boundary and two fixed static rays; photo-fitted thresholds, no complete visual acceptance, surface coverage or collision certification.'},null,2)+'\n');console.log('VERIFIED',rows.length,'actual cab ends, bowl boundaries, cover/cavity rays and real vertex faults');
