// Intentionally visible defects must fail the exported-geometry checks.
import{readFileSync,writeFileSync}from'node:fs';import{resolve}from'node:path';import assert from'node:assert/strict';import{readNative}from'../station-kit/package.mjs';import{audit}from'./geometry-audit.mjs';
const root=resolve(process.argv[2]),parts=JSON.parse(readFileSync(resolve(root,'components.json')))['steam-locomotive'],base=readNative(readFileSync(resolve(root,'models/steam-locomotive.m3dmodel'))).vertices,records=[];
for(const kind of ['missing face','reversed face','detached closed glazing','board cuts drivers']){
 const vs=structuredClone(base),ps=structuredClone(parts);
 if(kind==='missing face'){vs.splice(0,3);ps[0].triangles--;for(let i=1;i<ps.length;i++)ps[i].start_triangle--;}
 if(kind==='reversed face')[vs[1],vs[2]]=[vs[2],vs[1]];
 if(kind==='detached closed glazing'){const p=ps.find(p=>p.name==='cab-glass--1.0');for(let i=p.start_triangle*3;i<(p.start_triangle+p.triangles)*3;i++)vs[i].position[1]+=.30;}
 if(kind==='board cuts drivers')for(const p of ps.filter(p=>p.name.startsWith('running-board')))for(let i=p.start_triangle*3;i<(p.start_triangle+p.triangles)*3;i++)vs[i].position[2]-=.20;
 let rejected=false;try{audit(vs,ps,'steam-locomotive');}catch(e){rejected=true;records.push({mutation:kind,result:'REJECTED',reason:e.message});}assert(rejected,kind+' escaped validation');
}
writeFileSync(resolve(root,'mutation-verification.json'),JSON.stringify({status:'VERIFIED',records},null,2)+'\n');console.log(JSON.stringify(records));
