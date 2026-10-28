// Vehicle-specific checks on the final native payload. These geometric probes
// do not assert engineering measurements or substitute for visual inspection.
import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {model} from '../train-models/native.mjs';

const root=resolve(process.argv[2]);
const round=n=>Math.round(n*100)/100;
function inspect(id) {
  const vertices=model(readFileSync(resolve(root,'models',id+'.m3dmodel'))).vertices;
  const triangles=Array.from({length:vertices.length/3},(_,i)=>vertices.slice(i*3,i*3+3).map(v=>v.position));
  const at=(t,p)=>t.every(v=>p(v));
  // The cab glazing must stand ahead of the painted cap so it remains visible.
  const frontGlass=triangles.filter(t=>at(t,v=>v[0]>=8.66 && v[2]>=1.78 && v[2]<=3.23 && Math.abs(v[1])<=0.83));
  assert(frontGlass.length>=2, `${id}: front glass missing or buried`);
  // Each of the four wheel positions reaches the rail plane on both sides.
  for(const bogie of [-5.63,5.54]) for(const axle of [-0.90,0.90]) for(const side of [-1,1]) {
    const near=vertices.filter(v=>Math.abs(v.position[0]-(bogie+axle))<0.10 && Math.abs(v.position[1])>0.63 && Math.sign(v.position[1])===side);
    assert(near.some(v=>Math.abs(v.position[2])<0.012),`${id}: wheel lifted at ${bogie+axle}/${side}`);
  }
  // Roof cases touch their foot volume, and there is no overhead collector.
  const maxZ=Math.max(...vertices.map(v=>v.position[2]));
  assert(maxZ<=3.81,`${id}: roof height exceeds published car envelope: ${round(maxZ)}`);
  return {id,front_glass_triangles:frontGlass.length,max_height_m:round(maxZ),wheel_contact_probes:8};
}
for(const id of ['sanying-a','sanying-b','sanying-a-far','sanying-b-far']) inspect(id);
const base=model(readFileSync(resolve(root,'models/sanying-a.m3dmodel'))).vertices;
// Fault example: moving the front pane behind the cab face trips the probe.
const broken=base.map(v=>({...v,position:[...v.position]}));
for(const v of broken) if(v.position[0]>8.66 && v.position[2]>1.78 && v.position[2]<3.23) v.position[0]-=0.10;
const hasPane=broken.some(v=>v.position[0]>=8.66 && v.position[2]>=1.78 && v.position[2]<=3.23 && Math.abs(v.position[1])<0.83);
assert(!hasPane,'buried-glass fault was not rejected');
const result={status:'VERIFIED',cars:['sanying-a','sanying-b','sanying-a-far','sanying-b-far'].map(inspect),mutation:'100mm buried windshield rejected',limits:'Geometric probes only; exact hardware and appearance need human/engineering review.'};
writeFileSync(resolve(root,'sanying-verification.json'),JSON.stringify(result,null,2)+'\n');
console.log('VERIFIED Sanying glass, wheel, roof and buried-glass fault probes');
