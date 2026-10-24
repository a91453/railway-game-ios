import{readFileSync,writeFileSync}from'node:fs';import{resolve}from'node:path';import assert from'node:assert/strict';import{readNative}from'../station-kit/package.mjs';
const current=resolve(process.argv[2]),prior=resolve(process.argv[3]),frontOnly=process.argv.includes('--front-only');
function components(root,id){const ps=JSON.parse(readFileSync(resolve(root,'components.json')))[id],vs=readNative(readFileSync(resolve(root,'models',id+'.m3dmodel'))).vertices;return new Map(ps.map(p=>[p.name,{...p,v:vs.slice(p.start_triangle*3,(p.start_triangle+p.triangles)*3)}]));}
const records=[];
for(const id of ['steam-locomotive','steam-tender']){const before=components(prior,id),after=components(current,id);let stableTriangles=0;const revised=[],added=[],removed=[];
 for(const[name,a]of before){const b=after.get(name);if(!b){assert(!frontOnly,'Front-only revision removed '+name);assert(name.includes('-spoke-6')||name.includes('-spoke-7'),'Unexpected removed '+name);removed.push(name);continue;}
  if(!frontOnly&&(a.role==='wheel'||a.role==='spoke'&&!name.startsWith('driver-')||name==='rear-coupler')){revised.push(name);continue;}
  assert(JSON.stringify(b.v)===JSON.stringify(a.v),'Previously stable solid changed: '+name);stableTriangles+=a.triangles;
 }
 for(const[name,b]of after)if(!before.has(name)){assert((frontOnly?/^front-/:/^(axlebox-|spring-hanger-|coal-lump-|rear-cab-|front-)/).test(name),'Unexpected new component '+name);added.push(name);}
 records.push({id,unchanged_triangles:stableTriangles,revised,added,removed});
}
writeFileSync(resolve(current,frontOnly?'front-revision-verification.json':'revision-verification.json'),JSON.stringify({status:'VERIFIED',prior:'actual prior export supplied as argument',checks:['unchanged component vertices, normals, colors and order compared exactly','only documented wheel simplification, prior supports/entry/coupler and added front running-gear solids; all other existing solids unchanged'],models:records},null,2)+'\n');console.log('VERIFIED stable body, boiler, cab, windows, major equipment and pipe components against genuine initial native.');
