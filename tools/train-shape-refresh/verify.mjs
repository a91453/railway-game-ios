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
  const p=vs.slice(i,i+3).map(key);for(let j=0;j<3;j++){
   const a=p[j],b=p[(j+1)%3],k=a<b?a+'|'+b:b+'|'+a,entry=edges.get(k)||{balance:0,faces:[]};entry.balance+=a<b?1:-1;entry.faces.push(i/3);edges.set(k,entry);
  }
 }
 for(const [key,e] of edges){assert.equal(e.balance,0,'open or inverted edge '+key);for(const t of e.faces)parent[find(t)]=find(e.faces[0]);}
 const volumes=new Map();
 for(let i=0;i<vs.length;i+=3){const [a,b,c]=vs.slice(i,i+3).map(v=>v.position);const v=(a[0]*(b[1]*c[2]-b[2]*c[1])+a[1]*(b[2]*c[0]-b[0]*c[2])+a[2]*(b[0]*c[1]-b[1]*c[0]))/6,k=find(i/3);volumes.set(k,(volumes.get(k)||0)+v);}
 for(const v of volumes.values())assert(v>1e-10,'inward solid');
 return {balanced_edges:edges.size,positive_solid_components:volumes.size};
}
const results=[];
for(const m of manifest.models){
 const bytes=readFileSync(resolve(root,m.native)),model=readNative(bytes);assert.deepEqual(glbFromNative(model),readFileSync(resolve(root,m.glb)));assert.equal(model.vertices.length,m.triangles*3);
 if(m.native_kind==='assembly'){
  const decoded=Buffer.from(assemblyNative(bytes.buffer.slice(bytes.byteOffset,bytes.byteOffset+bytes.byteLength)));
  assert.deepEqual(decoded.subarray(20),readFileSync(resolve(root,m.assembly_expected)),'Swift/JS full assembly differs');
  const bad=JSON.parse(bytes);bad.placements[2].translation[0]+=1;
  const faulty=Buffer.from(JSON.stringify(bad));const rebuilt=Buffer.from(assemblyNative(faulty.buffer.slice(faulty.byteOffset,faulty.byteOffset+faulty.byteLength)));
  assert.notDeepEqual(rebuilt.subarray(20),decoded.subarray(20),'Assembly shift mutation missed');
 }
 assert(m.minimum[2]>-0.00001);console.log(m.id);results.push({id:m.id,...audit(model.vertices)});
}
// Defect checks operate on actual final triangle soup, not recipe constants.
const cab=readNative(readFileSync(resolve(root,manifest.models.find(m=>m.id==='refresh-700t-cab').native))).vertices;
let rejected=0;for(const broken of [cab.slice(3),[cab[1],cab[0],cab[2],...cab.slice(3)]]){try{audit(broken);}catch{rejected++;}}assert.equal(rejected,2);
writeFileSync(resolve(root,'verification.json'),JSON.stringify({status:'VERIFIED',checks:['native/GLB exact geometry','closed oriented edge balance','positive solid volumes','missing face rejected','reversed face rejected'],models:results,unverified:['Metal/device performance/animation','engineering dimensions except sourced E200 body width/length','complete equipment contact graph / all-surface collisions beyond sampled wheel clearance rays']},null,2));
console.log('VERIFIED geometry and two visible defect mutations');
