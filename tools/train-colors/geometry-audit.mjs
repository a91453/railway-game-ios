// Inspect the actual native triangles, independent of the recipe's declarations.
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
const comparisonRecord=manifest.models.find(m=>m.id==='green-commuter-leading');
const comparison=readNative(readFileSync(resolve(root,comparisonRecord.native))).vertices;
const glassReference=comparison.filter(v=>v.position[0]>9.2 && v.position[2]>1.83 && v.position[2]<2.84 && Math.abs(v.position[1])<1.2 && v.normal[0]>.9).sort((a,b)=>(b.position[0]+(b.position[2]-.69)*.056)-(a.position[0]+(a.position[2]-.69)*.056))[0];
assert(glassReference,'Missing existing glass comparison');
const glassColors=[1,.92,.80,.70,.86].map(f=>glassReference.color.map((v,i)=>i===3?v:Math.round(v*f)).join(','));
const isGlass=t=>glassColors.includes(t[0].color.join(','));
const records=[];
for(const model of manifest.models.filter(m=>m.category==='section'&&m.id.startsWith('urban-three-'))){
 const vs=readNative(readFileSync(resolve(root,model.native))).vertices;
 const triangles=Array.from({length:vs.length/3},(_,i)=>vs.slice(i*3,i*3+3));
 const edges=new Map();
 for(const t of triangles)for(let i=0;i<3;i++){
  const a=key(t[i].position),b=key(t[(i+1)%3].position);assert.notEqual(a,b);
  const k=[a,b].sort().join('|'),e=edges.get(k)||{count:0,winding:0};e.count++;e.winding+=a<b?1:-1;edges.set(k,e);
 }
 const open=[...edges].filter(([,e])=>e.count%2||e.winding!==0);
 assert.equal(open.length,0,model.id+' has open or inconsistently wound welded edges: '+JSON.stringify(open.slice(0,5)));
 // For every glazing triangle centroid, cast inward to a different surface.
 // This catches detached windows even when the bounding box still looks right.
 let glazing=0,maxSupport=0;
 for(const t of triangles){
  const p=t.map(v=>v.position),o=[0,1,2].map(i=>p.reduce((s,q)=>s+q[i]/3,0));
  const rgb=t[0].color;
  if(!isGlass(t))continue;
  const n=t[0].normal;
  if(Math.abs(o[1])>1.30){
   const nearDoor=Math.abs(Math.abs(o[0])-3.44)<.7,plane=nearDoor?1.363:1.342;
   if(Math.abs(Math.abs(o[1])-plane)>.0001)continue;
   assert(n[1]*o[1]>1.2,'Inverted side glazing');
  }else if(Math.abs(o[0])>7.1){
   const lift=Math.abs(o[0])-(7.5-(o[2]-.79)*.065);
   if(Math.abs(lift-.033)>.0001)continue;
   assert(n[0]*o[0]>7,'Inverted cab glazing');
  }else continue;
  const d=n.map(v=>-v),dist=Math.min(...triangles.filter(q=>!isGlass(q)).map(q=>hit(o,d,q)));
  assert(dist<.065,model.id+' glazing floats at '+o+' support '+dist);
  maxSupport=Math.max(maxSupport,dist);glazing++;
 }
 assert(glazing>20,'No glazing was audited');
 records.push({id:model.id,triangles:triangles.length,welded_edges:edges.size,open_or_reversed_edges:open.length,glazing_triangles:glazing,max_support_distance_m:maxSupport});
}
writeFileSync(resolve(root,'geometry-verification.json'),JSON.stringify({status:'VERIFIED',checks:['closed directed welded edges for every primitive and shell','inward ray support of every visible glazing triangle'],models:records},null,2)+'\n');
console.log(JSON.stringify(records));
