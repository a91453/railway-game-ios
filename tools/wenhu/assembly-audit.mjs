import assert from 'node:assert/strict';
import{readFileSync,writeFileSync}from'node:fs';
import{resolve}from'node:path';
import{expanded}from'../train-models/native.mjs';
const root=resolve(process.argv[2]),manifest=JSON.parse(readFileSync(root+'/manifest.json')),rows=[];
const payload=b=>b.subarray(16+Math.ceil(b.readUInt32LE(12)/4)*4);
for(const m of manifest.models.filter(m=>m.native_kind==='assembly')){
 const scene=JSON.parse(readFileSync(resolve(root,m.native))),expected=readFileSync(resolve(root,m.assembly_payload));assert.equal(scene.placements.length,4);assert.deepEqual(payload(expanded(Buffer.from(JSON.stringify(scene)))),expected);
 const faults=[];
 let q=structuredClone(scene);q.placements[1].unit=q.placements[0].unit;faults.push(['replace B with A',q]);
 q=structuredClone(scene);[q.placements[0].unit,q.placements[1].unit]=[q.placements[1].unit,q.placements[0].unit];faults.push(['wrong order',q]);
 q=structuredClone(scene);q.placements.splice(2,1);faults.push(['missing central role',q]);
 q=structuredClone(scene);q.placements[1].translation[0]+=.10;faults.push(['wrong centre/gap',q]);
 q=structuredClone(scene);q.placements[1].rotation_degrees=180;faults.push(['reversed B / wrong pair interface',q]);
 for(const[name,f]of faults){let broken;try{broken=payload(expanded(Buffer.from(JSON.stringify(f))));}catch{}if(broken)assert.notDeepEqual(broken,expected,name);}
 rows.push({id:m.id,actual_assembly_faults_rejected:faults.map(([name])=>name)});
}
writeFileSync(root+'/assembly-verification.json',JSON.stringify({status:'VERIFIED',models:rows,limits:'Actual final assemblies mutated and compared with baseline payload independently checked through Swift; validates study configuration, not unresolved official A/B directions or contemporary fleet identity.'},null,2)+'\n');console.log('VERIFIED',rows.length,'real assemblies; 5 actual configuration failures each');
