import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
const root=process.argv[2];
if(!root) throw Error('usage: node tools/45dr1000/verify.mjs OUT');
const manifest=JSON.parse(readFileSync(resolve(root,'manifest.json')));
const byID=new Map(manifest.models.map(m=>[m.id,m]));
const near=byID.get('45dr1000-drc1025'),far=byID.get('45dr1000-drc1025-far');
function verify(a,b) {
  if(!a||!b) throw Error('missing study unit');
  if(a.triangles>20000||b.triangles>=a.triangles/2) throw Error('near/far triangle budget');
  for(const m of [a,b]) {
    const size=m.maximum.map((v,i)=>v-m.minimum[i]);
    if(size[0]<19.65||size[0]>19.9) throw Error('45DR1000 length including couplers');
    if(size[1]<2.68||size[1]>2.85) throw Error('45DR1000 narrow branch-line width');
    if(size[2]<3.86||size[2]>3.94) throw Error('45DR1000 rooftop envelope or wheel/rail clearance');
    if(m.minimum[2]<-0.001||m.minimum[2]>0.05) throw Error('wheel/rail clearance');
    if(m.glassTriangles<70) throw Error('two cab windows and side glazing missing');
  }
  if(Math.abs(a.maximum[0]-b.maximum[0])>0.03||Math.abs(a.maximum[2]-b.maximum[2])>0.03) throw Error('near/far envelope mismatch');
}
verify(near,far);
for(const [name,change] of [
  ['wide as DR3100',m=>m.maximum[1]+=0.20],
  ['floating wheel',m=>m.minimum[2]+=0.11],
  ['missing glazing',m=>m.glassTriangles=0],
  ['far too dense',m=>m.triangles=near.triangles]
]) {
  const broken={...far,maximum:[...far.maximum],minimum:[...far.minimum]};change(broken);
  let rejected=false;try{verify(near,broken)}catch{rejected=true}
  if(!rejected) throw Error(`fault example passed: ${name}`);
}
console.log('VERIFIED: 45DR1000 envelope, glazing, LOD and four rejected faults');
