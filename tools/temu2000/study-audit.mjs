// TEMU2000-specific geometric checks over the exported, final M3DM units.
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {model} from '../train-models/native.mjs';
const root=resolve(process.argv[2]), manifest=JSON.parse(readFileSync(resolve(root,'manifest.json')));
const units=manifest.models.filter(m=>!m.native_kind);
const read=m=>model(readFileSync(resolve(root,m.native))).vertices;
const triangles=v=>Array.from({length:v.length/3},(_,i)=>v.slice(i*3,i*3+3));
const near=(a,b,t=.015)=>Math.abs(a-b)<=t;
function wheels(v) {
  for(const x of [-8.25,-6.05,6.05,8.25]) for(const side of [-1,1]) {
    const tyre=v.filter(q=>near(q.position[0],x,.025)&&near(q.position[1],side*.74,.07)&&q.position[2]<.12);
    assert(tyre.length>=6,`axle ${x} ${side}: tyre contact samples missing`);
    assert(Math.abs(Math.min(...tyre.map(q=>q.position[2])))<.018,`axle ${x} ${side}: tyre raised or sunk`);
  }
}
function roofSupport(v, cab, roof) {
  const width=cab?.56:.75;
  for(const x of [-5.9,5.9]) {
    const contact=v.filter(q=>Math.abs(q.position[0]-x)<1.62&&near(Math.abs(q.position[1]),width,.006)&&near(q.position[2],roof-.005,.015));
    assert(contact.length>=8,`roof housing at ${x}: no contact with roof`);
  }
}
function projectedX(t,y,z){
  const [a,b,c]=t.map(q=>q.position),ay=a[1],az=a[2],by=b[1],bz=b[2],cy=c[1],cz=c[2];
  const d=(bz-cz)*(ay-cy)+(cy-by)*(az-cz);if(Math.abs(d)<1e-9)return null;
  const u=((bz-cz)*(y-cy)+(cy-by)*(z-cz))/d;
  const w=((cz-az)*(y-cy)+(ay-cy)*(z-cz))/d;
  if(u<.001||w<.001||u+w>.999)return null;
  return u*a[0]+w*b[0]+(1-u-w)*c[0];
}
function glassVisible(v,sign=1){
  const all=triangles(v), glass=t=>{let [r,g,b]=t[0].color;return r>=35&&r<90&&g>r+8&&b>g+4};
  const pane=all.filter(t=>glass(t)&&t.every(q=>sign*q.position[0]>8.8&&q.position[2]>1.9&&Math.abs(q.position[1])<1.15));
  assert(pane.length>=20,'front windscreen missing');
  let seen=0, sampled=0;
  for(const t of pane.filter((_,i)=>i%3===0).slice(0,90)) {
    const y=t.reduce((s,q)=>s+q.position[1],0)/3,z=t.reduce((s,q)=>s+q.position[2],0)/3;
    const own=projectedX(t,y,z);if(own===null)continue;
    let foremost=-Infinity;
    for(const other of all){const x=projectedX(other,y,z);if(x!==null&&sign*x>foremost)foremost=sign*x;}
    sampled++;if(sign*own>=foremost-.012)seen++;
  }
  assert(sampled>=10,'front glass rays missing');
  assert(seen/sampled>=.42,`windshield buried: ${seen}/${sampled} rays frontmost`);
  return {frontmost_rays:seen,sampled};
}
const results=[];
for(const m of units){
  const v=read(m),cab=/leading|trailing/.test(m.id),roof=cab?3.632:3.565;
  wheels(v);roofSupport(v,cab,roof);
  const row={id:m.id,tyre_contact:'8 wheel sides at Z=0',roof_contact:'two housings at the roof plane'};
  if(cab)row.windshield=glassVisible(v,m.id.includes('trailing')?-1:1);
  results.push(row);
}
const head=units.find(m=>m.id==='temu2000-leading'),v=read(head);
assert.throws(()=>wheels(v.map(q=>{
  const p=q.position;return Math.abs(p[0]+8.25)<.5&&Math.abs(p[1])>.65&&Math.abs(p[1])<.85&&p[2]<.87?{...q,position:[p[0],p[1],p[2]+.10]}:q;
})),/tyre/);
assert.throws(()=>roofSupport(v.map(q=>{
  const p=q.position;return Math.abs(p[0]-5.9)<1.11&&Math.abs(p[1])<=.57&&p[2]>3.62?{...q,position:[p[0],p[1],p[2]+.20]}:q;
}),true,3.632),/roof/);
assert.throws(()=>glassVisible(v.map(q=>{
  const p=q.position,[r,g,b]=q.color;return p[0]>8.8&&p[2]>1.9&&r>=35&&r<90&&g>r+8&&b>g+4?{...q,position:[p[0]-.35,p[1],p[2]]}:q;
})),/windshield/);
const report={status:'VERIFIED',models:results,faults:['one axle raised 100 mm','cab roof housing raised 200 mm','front glass buried 350 mm'],limits:['Photographic proportions and hidden equipment remain visual review, not engineering proof.']};
writeFileSync(resolve(root,'temu2000-study-audit.json'),JSON.stringify(report,null,2)+'\n');
console.log(`VERIFIED ${results.length} TEMU2000 units and 3 vehicle faults`);
