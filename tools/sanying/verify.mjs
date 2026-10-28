// Vehicle-specific checks on final native payloads. These geometric probes
// do not claim engineering accuracy or replace human appearance review.
import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {model} from '../train-models/native.mjs';

const root=resolve(process.argv[2]);
function frontPane(vertices,minCount=20) {
  let count=0, outer=-Infinity;
  for(let i=0;i<vertices.length;i+=3) {
    const t=vertices.slice(i,i+3), p=[0,1,2].map(axis=>t.reduce((s,v)=>s+v.position[axis],0)/3);
    const dark=t.every(v=>Math.max(...v.color.slice(0,3))<130);
    if(p[0]>7.75 && p[2]>2.1 && p[2]<2.9 && Math.abs(p[1])<0.7 && t[0].normal[0]>0.4 && dark) {
      count++;outer=Math.max(outer,p[0]);
    }
  }
  assert(count>=minCount && outer>8.05,'front glass missing, buried or facing inward');
  return {triangles:count,outer_x_m:outer};
}
function inspect(id) {
  const vertices=model(readFileSync(resolve(root,'models',id+'.m3dmodel'))).vertices;
  const pane=frontPane(vertices,id.endsWith('-far')?8:20);
  for(const bogie of [-5.72,5.72]) for(const axle of [-0.90,0.90]) for(const side of [-1,1]) {
    const near=vertices.filter(v=>Math.abs(v.position[0]-(bogie+axle))<0.10 && Math.abs(v.position[1])>0.63 && Math.sign(v.position[1])===side);
    assert(near.some(v=>Math.abs(v.position[2])<0.012),`${id}: wheel lifted at ${bogie+axle}/${side}`);
  }
  for(const x of [-4.25,4.25]) {
    const equipment=vertices.filter(v=>Math.abs(v.position[0]-x)<1.8 && Math.abs(v.position[1])<0.9);
    assert(equipment.some(v=>Math.abs(v.position[2]-3.60)<0.012),`${id}: roof equipment lacks base contact`);
    assert(equipment.some(v=>v.position[2]>3.75),`${id}: roof equipment missing`);
  }
  const maxZ=Math.max(...vertices.map(v=>v.position[2]));
  assert(maxZ<=3.81,`${id}: roof exceeds published height envelope`);
  return {id,front_glass_triangles:pane.triangles,max_height_m:maxZ,wheel_contact_probes:8,roof_contact_probes:2};
}
const ids=['sanying-a','sanying-b','sanying-a-far','sanying-b-far'];
const cars=ids.map(inspect);
const base=model(readFileSync(resolve(root,'models/sanying-a.m3dmodel'))).vertices;
const broken=base.map(v=>({...v,position:[...v.position]}));
for(let i=0;i<broken.length;i+=3) {
  const t=broken.slice(i,i+3),p=[0,1,2].map(axis=>t.reduce((s,v)=>s+v.position[axis],0)/3);
  if(p[0]>7.75 && p[2]>2.1 && p[2]<2.9 && Math.abs(p[1])<0.7 && t[0].normal[0]>0.4 && t.every(v=>Math.max(...v.color.slice(0,3))<130))
    for(const v of t) v.position[0]-=0.5;
}
assert.throws(()=>frontPane(broken),/glass/,'buried-glass mutation was not rejected');
writeFileSync(resolve(root,'sanying-verification.json'),JSON.stringify({status:'VERIFIED',cars,mutation:'500mm buried windshield rejected',limits:'Geometric probes only; exact hardware and appearance require human/engineering review.'},null,2)+'\n');
console.log('VERIFIED Sanying glass, wheel, roof and buried-glass fault probes');
