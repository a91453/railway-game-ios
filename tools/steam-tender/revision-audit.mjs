import{readFileSync,writeFileSync}from'node:fs';import{resolve}from'node:path';import assert from'node:assert/strict';import{readNative}from'../station-kit/package.mjs';
const current=resolve(process.argv[2]),prior=resolve(process.argv[3]);
function components(root,id){const ps=JSON.parse(readFileSync(resolve(root,'components.json')))[id],vs=readNative(readFileSync(resolve(root,'models',id+'.m3dmodel'))).vertices;return new Map(ps.map(p=>[p.name,{...p,v:vs.slice(p.start_triangle*3,(p.start_triangle+p.triangles)*3)}]));}
const records=[];
for(const id of ['steam-locomotive','steam-tender']){const before=components(prior,id),after=components(current,id);let stableTriangles=0;const revised=[],added=[],removed=[];
 for(const[name,a]of before){const b=after.get(name);if(!b){assert(name.includes('-spoke-6')||name.includes('-spoke-7'),'Unexpected removed '+name);removed.push(name);continue;}
  if(a.role==='wheel'||a.role==='spoke'&&!name.startsWith('driver-')||name==='rear-coupler'){revised.push(name);continue;}
  assert(JSON.stringify(b.v)===JSON.stringify(a.v),'Previously stable solid changed: '+name);stableTriangles+=a.triangles;
 }
 for(const[name,b]of after)if(!before.has(name)){assert(/^(axlebox-|spring-hanger-|coal-lump-|rear-cab-)/.test(name),'Unexpected new component '+name);added.push(name);}
 records.push({id,unchanged_triangles:stableTriangles,revised,added,removed});
}
writeFileSync(resolve(current,'revision-verification.json'),JSON.stringify({status:'VERIFIED',prior:'history/initial (genuine prototype)',checks:['unchanged component vertices, normals, colors and order compared exactly','only wheel rim tessellation / small-wheel spoke simplification, documented added supports/coal/entry and rear coupler changed'],models:records},null,2)+'\n');console.log('VERIFIED stable body, boiler, cab, windows, major equipment and pipe components against genuine initial native.');
