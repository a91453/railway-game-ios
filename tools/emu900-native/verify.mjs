// Audit exported native triangle soup and exact assembly; no recipe tables are imported.
import {readFileSync,writeFileSync} from 'node:fs';
import {resolve} from 'node:path';
import assert from 'node:assert/strict';
import {assemblyNative} from './scene.js';
import {readNative,glbFromNative} from './package.mjs';
const root=resolve(process.argv[2]),manifest=JSON.parse(readFileSync(resolve(root,'manifest.json')));
function audit(vs){
 const edges=new Map(),key=v=>v.position.map(x=>Math.round(x*1e5)).join(','),parent=Array.from({length:vs.length/3},(_,i)=>i);
 const find=i=>parent[i]===i?i:parent[i]=find(parent[i]);
 for(let i=0;i<vs.length;i+=3){
  const tri=vs.slice(i,i+3);assert(tri.every(v=>[...v.position,...v.normal].every(Number.isFinite)),'non-finite native values');
  const [a,b,c]=tri.map(v=>v.position),u=b.map((x,k)=>x-a[k]),v=c.map((x,k)=>x-a[k]),n=[u[1]*v[2]-u[2]*v[1],u[2]*v[0]-u[0]*v[2],u[0]*v[1]-u[1]*v[0]],length=Math.hypot(...n);
  assert(length>1e-12,'degenerate native face');
  for(const vertex of tri)assert(vertex.normal.every((x,k)=>Math.abs(x-n[k]/length)<1e-6),'normal differs from actual triangle');
  const p=tri.map(key);for(let j=0;j<3;j++){
   const a=p[j],b=p[(j+1)%3];assert.notEqual(a,b,'collapsed quantized edge');
   const k=a<b?a+'|'+b:b+'|'+a,entry=edges.get(k)||{balance:0,faces:[]};entry.balance+=a<b?1:-1;entry.faces.push(i/3);edges.set(k,entry);
  }
 }
 for(const [key,e] of edges){assert.equal(e.balance,0,'open or inverted edge '+key);for(const t of e.faces)parent[find(t)]=find(e.faces[0]);}
 const volumes=new Map();
 for(let i=0;i<vs.length;i+=3){const [a,b,c]=vs.slice(i,i+3).map(v=>v.position),volume=(a[0]*(b[1]*c[2]-b[2]*c[1])+a[1]*(b[2]*c[0]-b[0]*c[2])+a[2]*(b[0]*c[1]-b[1]*c[0]))/6,k=find(i/3);volumes.set(k,(volumes.get(k)||0)+volume);}
 for(const volume of volumes.values())assert(volume>1e-10,'inward or zero-volume solid');
 return {balanced_edges:edges.size,positive_solid_components:volumes.size};
}
function assemblyContacts(scene){
 assert.equal(scene.placements.length,10,'ten cars');const rows=[];let previous;
 for(const p of scene.placements){
  assert.equal(p.rotation_degrees,0,'reverse baked into unit');
  const rec=manifest.models.find(m=>m.id===p.unit),bytes=Buffer.from(scene.units[p.unit],'base64');
  assert(bytes.equals(readFileSync(resolve(root,rec.native))),'stale assembly unit');
  const vs=readNative(bytes).vertices.map(v=>v.position).filter(v=>v[2]>=0.75-1e-5&&v[2]<=0.99+1e-5&&Math.abs(v[1])<=0.18);
  const lo=Math.min(...vs.map(v=>v[0])),hi=Math.max(...vs.map(v=>v[0]));
  if(previous){const gap=previous.lo+previous.x-hi-p.translation[0];assert(Math.abs(gap)<0.006,'coupler gap mismatch '+gap);rows.push({gap_m:gap});}
  previous={lo,x:p.translation[0]};
 }
 return rows;
}
const results=[],assemblies=[];
for(const m of manifest.models){
 const bytes=readFileSync(resolve(root,m.native)),model=readNative(bytes);assert(glbFromNative(model).equals(readFileSync(resolve(root,m.glb))),'native/GLB bytes differ '+m.id);assert.equal(model.vertices.length,m.triangles*3);
 const lo=[0,1,2].map(i=>model.vertices.reduce((n,v)=>Math.min(n,v.position[i]),Infinity)),hi=[0,1,2].map(i=>model.vertices.reduce((n,v)=>Math.max(n,v.position[i]),-Infinity));
 assert(lo.every((x,i)=>Math.abs(x-m.minimum[i])<1e-5)&&hi.every((x,i)=>Math.abs(x-m.maximum[i])<1e-5),'manifest bounds differ '+m.id);
 assert(lo[2]>-1e-5,'unit below rail datum');
 if(m.native_kind==='assembly'){
  const scene=JSON.parse(bytes),decoded=Buffer.from(assemblyNative(bytes.buffer.slice(bytes.byteOffset,bytes.byteOffset+bytes.byteLength)));
  assert(decoded.subarray(20).equals(readFileSync(resolve(root,m.id+'-expected.bin'))),'Swift/JS complete assembly differs');
  const contacts=assemblyContacts(scene),bad=structuredClone(scene);bad.placements[2].translation[0]+=1;
  assert.throws(()=>assemblyContacts(bad),/mismatch|gap|overlap/,'actual placement shift was not rejected');
  const missingTail=structuredClone(scene);missingTail.placements.pop();assert.throws(()=>assemblyContacts(missingTail),undefined,'missing EMU900 car rejected');
  const faulty=Buffer.from(JSON.stringify(bad)),rebuilt=Buffer.from(assemblyNative(faulty.buffer.slice(faulty.byteOffset,faulty.byteOffset+faulty.byteLength)));
  assert(!rebuilt.subarray(20).equals(decoded.subarray(20)),'assembly payload shift missed');
  assemblies.push({id:m.id,contacts,shifted_car_mutation_rejected:true});results.push({id:m.id,status:'exact-composition-of-audited-units'});
 }else if(m.category==='section'){
  assert(m.triangles<=15000,'native unit format limit');if(m.id.endsWith('-far'))assert(m.triangles<=7000,'independent static EMU900 far cap');
  results.push({id:m.id,...audit(model.vertices)});
  assert.throws(()=>audit(model.vertices.slice(3)),undefined,'deleted face not rejected');
  assert.throws(()=>audit([model.vertices[1],model.vertices[0],model.vertices[2],...model.vertices.slice(3)]),undefined,'reversed face not rejected');
 }else results.push({id:m.id,status:'preserved-comparison-no-new-EMU900-quality-claim'});
 console.log('geometry',m.id,m.triangles);
}
writeFileSync(resolve(root,'verification.json'),JSON.stringify({status:'VERIFIED',checks:['native/GLB exact geometry','actual finite positions and face normals','closed oriented edges','positive solid volumes','every EMU900 unit missing/reversed-face mutations rejected','exact Swift/JS assembly payload','actual coupler/gangway endpoint faces','shifted-car mutation rejected'],models:results,assemblies,limits:['static endpoint-plane alignment and sampled geometry; not complete collision or control validation','Metal/device performance/animation unverified','source dimensions and unseen equipment limitations remain in reference record']},null,2)+'\n');
