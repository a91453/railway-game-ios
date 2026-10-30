import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {model} from '../train-models/native.mjs';
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
// Check the photographed cab end in the delivered native triangles, not only
// the car-wide manifest. x is forward; y is left; z is height in metres.
const cab=model(readFileSync(resolve(root,near.native))).vertices;
function frontProbe(vertices) {
  const front=vertices.filter(v=>v.position[0]>9.70);
  const count=predicate=>front.filter(predicate).length;
  for(const side of [-1,1]) {
    if(count(v=>v.position[1]*side>0.45&&v.position[1]*side<1.26&&
         v.position[2]>2.14&&v.position[2]<3.26&&Math.max(...v.color.slice(0,3))<80)<100)
      throw Error('paired dark cab windows missing');
    if(count(v=>v.position[0]>9.78&&v.position[1]*side>0.75&&
         v.position[1]*side<1.0&&v.position[2]>2.94&&v.position[2]<3.16&&
         v.color[0]>100&&v.color[1]>100)<20)
      throw Error('paired high cab lamps missing');
  }
  if(count(v=>v.position[2]>3.17&&v.position[2]<3.5&&
       v.color[0]>100&&v.color[0]>v.color[1]*1.15)<20)
    throw Error('rounded orange brow missing');
  if(count(v=>v.position[0]>9.80&&Math.abs(v.position[1])<0.36&&
       v.position[2]>1.32&&v.position[2]<3.15&&v.color[0]>100&&
       v.color[0]>v.color[2]*1.4)<8)
    throw Error('central yellow gangway missing');
}
frontProbe(cab);
const brokenCab=mutator=>cab.map(v=>{const p={...v,position:[...v.position],color:[...v.color]};mutator(p);return p});
for(const [name,mutate] of [
  ['left black field lost',v=>{if(v.position[0]>9.70&&v.position[1]>0.45&&v.position[2]>2.14&&v.position[2]<3.26)v.color=[240,240,240,255]}],
  ['orange brow lost',v=>{if(v.position[0]>9.70&&v.position[2]>3.17)v.color=[20,20,20,255]}],
  ['right headlamp lost',v=>{if(v.position[0]>9.78&&v.position[1]<-0.75&&v.position[1]>-1&&v.position[2]>2.94&&v.position[2]<3.16)v.color=[20,20,20,255]}],
  ['gangway shifted',v=>{if(v.position[0]>9.80&&Math.abs(v.position[1])<0.36&&v.position[2]>1.32&&v.position[2]<3.15)v.position[1]+=0.60}]
]) {
  let rejected=false;try{frontProbe(brokenCab(mutate))}catch{rejected=true}
  if(!rejected) throw Error(`front fault example passed: ${name}`);
}
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
console.log('VERIFIED: 45DR1000 envelope, LOD and photographed cab; eight rejected faults');
