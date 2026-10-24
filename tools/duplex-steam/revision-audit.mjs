// Actual preserved initial model vs final. Never manufacture an earlier model.
import{readFileSync,writeFileSync}from'node:fs';import{resolve}from'node:path';import assert from'node:assert/strict';import{readNative}from'../station-kit/package.mjs';
const final=resolve(process.argv[2]),before=resolve(process.argv[3]);
function parts(root,id){const ranges=JSON.parse(readFileSync(resolve(root,'components.json')))[id],vs=readNative(readFileSync(resolve(root,'models/'+id+'.m3dmodel'))).vertices;return new Map(ranges.map(p=>[p.name,JSON.stringify(vs.slice(p.start_triangle*3,(p.start_triangle+p.triangles)*3))]));}
const records=[];
for(const id of ['duplex-locomotive','duplex-tender']){
 const a=parts(before,id),b=parts(final,id),changed=[],added=[],removed=[];let unchanged=0;
 for(const[name,vertices]of a){if(!b.has(name)){assert(id==='duplex-locomotive'&&/^(cylinder-|crosshead-|slide-guide-|step-)/.test(name),'unexpected removal '+name);removed.push(name);continue;}if(b.get(name)===vertices)unchanged++;else{assert(id==='duplex-locomotive'&&/^(cylinder-|crosshead-|slide-guide-|main-rod-|step-|cab-wall|cab-blue-lower-)/.test(name),'unscoped change '+name);changed.push(name);}}
 for(const name of b.keys())if(!a.has(name)){assert(id==='duplex-locomotive'&&/^(front-platform-(support|step-hanger-)|cylinder-|crosshead-|slide-guide-|step-)/.test(name),'unexpected addition '+name);added.push(name);}
 if(id==='duplex-tender'){assert.equal(changed.length,0);assert.equal(added.length,0);assert.equal(removed.length,0);}
 records.push({id,unchanged_solids:unchanged,changed_solids:changed,added_solids:added,removed_or_renamed_solids:removed});
}
writeFileSync(resolve(final,'revision-verification.json'),JSON.stringify({status:'VERIFIED',before:'genuine initial native export with preserved recipe',scope:'cylinder size/position and connected rods, front access steps and beam/step supports, cab palette; tender geometry and colours identical',models:records},null,2)+'\n');console.log(JSON.stringify(records));
