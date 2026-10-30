// Assembly identity and actual expanded payload mutations, beyond common shift.
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {expanded} from '../train-models/native.mjs';
const root=resolve(process.argv[2]),fleet=process.argv[3];
const rows=[];
for(const far of [false,true]){
 const suffix=far?'-far':'',file=resolve(root,`models/${fleet}-emu500-formation${suffix}.m3dscene.json`);
 const s=JSON.parse(readFileSync(file)),expected=['emc','ep','et','em'].map(x=>`${fleet}-emu500-${x}${suffix}`);
 function contract(scene){assert.deepEqual(scene.placements.map(x=>x.unit),expected);assert.deepEqual(scene.placements.map(x=>x.rotation_degrees),[0,0,0,180]);assert.deepEqual(scene.placements.map(x=>x.translation),[[30.495,0,0],[10.165,0,0],[-10.165,0,0],[-30.495,0,0]]);}
 contract(s);const original=expanded(Buffer.from(JSON.stringify(s)));
 for(const kind of ['order','direction','position']){
  const bad=structuredClone(s);
  if(kind==='order') [bad.placements[1].unit,bad.placements[2].unit]=[bad.placements[2].unit,bad.placements[1].unit];
  if(kind==='direction')bad.placements[0].rotation_degrees=180;
  if(kind==='position')bad.placements[2].translation[2]=.1;
  assert.throws(()=>contract(bad));assert.notDeepEqual(expanded(Buffer.from(JSON.stringify(bad))),original);
 }
 rows.push({far,wrong_order_rotation_position_payloads_rejected:true});
}
writeFileSync(resolve(root,'assembly-verification.json'),JSON.stringify({status:'VERIFIED',rows},null,2)+'\n');console.log('VERIFIED assembly mutations');
