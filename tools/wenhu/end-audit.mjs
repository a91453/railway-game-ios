// Actual final native rays and actual-vertex failures. No synthetic labelled fixture.
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {model} from '../train-models/native.mjs';
function hit(vertices,y,z){let best=-Infinity;
 for(let i=0;i<vertices.length;i+=3){
  const p=vertices.slice(i,i+3).map(v=>v.position),[a,b,c]=p;
  const det=(b[1]-a[1])*(c[2]-a[2])-(c[1]-a[1])*(b[2]-a[2]);if(Math.abs(det)<1e-10)continue;
  const u=((y-a[1])*(c[2]-a[2])-(c[1]-a[1])*(z-a[2]))/det;
  const v=((b[1]-a[1])*(z-a[2])-(y-a[1])*(b[2]-a[2]))/det;
  if(u>=-1e-6&&v>=-1e-6&&u+v<=1+1e-6){const x=a[0]+u*(b[0]-a[0])+v*(c[0]-a[0]);if(x<7)best=Math.max(best,x);}
 }return best;
}
function check(v){
 const head=[];for(const y of [-.05,.05])for(const z of [.84,.88]){const x=hit(v,y,z);assert(x<6.72&&x>6.3,'coupler opening filled or drawbar absent');head.push(x);}
 const flank=hit(v,.82,1.08),pocket=hit(v,0,1.08);
 assert(flank-pocket>.20,'lower nose lacks a real recessed drawgear pocket');
 return{coupler_lumen_first_hits_x_m:head,pocket_depth_relative_to_flank_m:flank-pocket};
}
const root=resolve(process.argv[2]),manifest=JSON.parse(readFileSync(root+'/manifest.json')),rows=[];
for(const m of manifest.models.filter(m=>m.native_kind!=='assembly')){
 const sign=m.id.includes('-b')?-1:1;
 const raw=model(readFileSync(resolve(root,m.native))).vertices;
 const v=raw.map(a=>({...a,position:[sign*a.position[0],sign*a.position[1],a.position[2]]}));
 const result=check(v);
 const filled=v.map(a=>{const [x,y,z]=a.position;return x>6.59&&Math.abs(y)<.14&&Math.abs(z-.86)<.08?{...a,position:[x,y*.02,.86+(z-.86)*.02]}:a;});
 assert.throws(()=>check(filled),/coupler opening/);
 const flattened=v.map(a=>{const [x,y,z]=a.position;return x>5.7&&x<6.5&&Math.abs(y)<.68&&z>1.01&&z<1.28?{...a,position:[x+.58*Math.max(0,Math.min(1,(.68-Math.abs(y))/.23))*Math.max(0,Math.min(1,(1.28-z)/.30)),y,z]}:a;});
 assert.throws(()=>check(flattened),/pocket/);
 rows.push({id:m.id,...result,actual_head_inner_vertices_collapsed_rejected:true,actual_nose_pocket_vertices_flattened_rejected:true});
}
writeFileSync(resolve(root,'end-verification.json'),JSON.stringify({status:'VERIFIED',models:rows,coverage:'Four axial coupler-lumen rays plus two lower-nose rays per role/LOD; actual native vertex faults. Photo-fit display thresholds, not complete collision, glass/gear certification or appearance acceptance.'},null,2)+'\n');
console.log('VERIFIED',rows.length,'role/LOD native end pockets and coupler openings; two real vertex failures per model');
