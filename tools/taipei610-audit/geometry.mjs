import {readFileSync,writeFileSync} from 'node:fs';
import {resolve} from 'node:path';
import assert from 'node:assert/strict';
import {readNative,glbFromNative} from '../emu900-native/package.mjs';
import {assemblyNative} from '../emu900-native/scene.js';
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

const results=[];
for(const role of ['a','c','d','b']){const near=manifest.models.find(m=>m.id==='taipei610-'+role),far=manifest.models.find(m=>m.id==='taipei610-'+role+'-far');assert(far.triangles<near.triangles*.5,'far budget');}

for(const m of manifest.models){
 const bytes=readFileSync(resolve(root,m.native)),model=readNative(bytes);
 assert(glbFromNative(model).equals(readFileSync(resolve(root,m.glb))),'GLB mismatch');
 if(m.category==='comparison')continue;
 if(m.native_kind==='assembly'){
  const combined=Buffer.from(assemblyNative(bytes.buffer.slice(bytes.byteOffset,bytes.byteOffset+bytes.byteLength)));
  const expected=readFileSync(resolve(root,m.id+'-expected.bin'));
  const p=16+Math.ceil(expected.readUInt32LE(12)/4)*4;
  assert(combined.subarray(20).equals(expected.subarray(p)),'Swift/JS assembly mismatch');
  const scene=JSON.parse(bytes);assert.deepEqual(scene.placements.map(p=>p.unit.split('-')[1]),['a','c','d','b']);
  for(const p of scene.placements)assert(Buffer.from(scene.units[p.unit],'base64').equals(readFileSync(resolve(root,manifest.models.find(m=>m.id===p.unit).native))),'stale unit');
  const gaps=[];
  for(let i=1;i<scene.placements.length;i++){const a=scene.placements[i-1],b=scene.placements[i],ma=manifest.models.find(m=>m.id===a.unit),mb=manifest.models.find(m=>m.id===b.unit);const gap=ma.minimum[0]+a.translation[0]-mb.maximum[0]-b.translation[0];assert(gap>=-.0001&&gap<=.031,'gangway gap/overlap');gaps.push(gap);}
  const shifted=structuredClone(scene);shifted.placements[2].translation[0]+=1;
  const data=Buffer.from(JSON.stringify(shifted));
  assert(!Buffer.from(assemblyNative(data.buffer.slice(data.byteOffset,data.byteOffset+data.byteLength))).equals(combined),'shift mutation');
  results.push({id:m.id,exact_assembly:true,gangway_gaps_m:gaps,shift_mutation_rejected:true});continue;
 }
 assert(m.triangles<=15000);const result=audit(model.vertices);
 assert.throws(()=>audit(model.vertices.slice(3)),undefined,'deleted-face mutation');
 assert.throws(()=>audit([model.vertices[1],model.vertices[0],model.vertices[2],...model.vertices.slice(3)]),undefined,'reverse-face mutation');
 results.push({id:m.id,...result,deleted_reversed_mutations_rejected:true});
}
writeFileSync(resolve(root,'geometry-verification.json'),JSON.stringify({platform:'Linux Node independent native reader',results},null,2));
console.log('Native geometry/GLB/assembly verified',results.length);
