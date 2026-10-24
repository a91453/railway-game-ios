// Audits exported vertices. Component ranges identify solids, not expected sizes.
import{readFileSync,writeFileSync}from'node:fs';import{resolve}from'node:path';import assert from'node:assert/strict';import{readNative}from'../station-kit/package.mjs';
const sub=(a,b)=>a.map((x,i)=>x-b[i]),dot=(a,b)=>a.reduce((n,x,i)=>n+x*b[i],0),cross=(a,b)=>[a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]],key=p=>p.map(x=>Math.round(x*1e5)).join(',');
function ray(o,d,t){const e1=sub(t[1].position,t[0].position),e2=sub(t[2].position,t[0].position),h=cross(d,e2),det=dot(e1,h);if(Math.abs(det)<1e-10)return Infinity;const s=sub(o,t[0].position),u=dot(s,h)/det;if(u<-.00001||u>1.00001)return Infinity;const q=cross(s,e1),v=dot(d,q)/det;if(v<-.00001||u+v>1.00001)return Infinity;const distance=dot(e2,q)/det;return distance>.000001?distance:Infinity;}
export function audit(vs,components,id){
 const parts=components.map(p=>{const v=vs.slice(p.start_triangle*3,(p.start_triangle+p.triangles)*3);assert.equal(v.length,p.triangles*3,'component length');return{...p,v,ts:Array.from({length:v.length/3},(_,i)=>v.slice(i*3,i*3+3)),low:[0,1,2].map(i=>Math.min(...v.map(q=>q.position[i]))),high:[0,1,2].map(i=>Math.max(...v.map(q=>q.position[i])))};});
 let edgeCount=0,glassChecks=0,maxGlassDistance=0;
 for(const p of parts){const edges=new Map();let volume=0;
  for(const t of p.ts){volume+=dot(t[0].position,cross(t[1].position,t[2].position))/6;for(let i=0;i<3;i++){const a=key(t[i].position),b=key(t[(i+1)%3].position),k=[a,b].sort().join('|'),e=edges.get(k)||{count:0,orientation:0};e.count++;e.orientation+=a<b?1:-1;edges.set(k,e);}}
  assert([...edges.values()].every(e=>e.count===2&&e.orientation===0),p.name+' open/reversed/nonmanifold solid');assert(volume>1e-8,p.name+' inward volume');edgeCount+=edges.size;
  if(p.role==='glass'){
   const supports=parts.filter(q=>q.role==='body').flatMap(q=>q.ts);
   for(const t of p.ts){const o=[0,1,2].map(i=>t.reduce((n,v)=>n+v.position[i]/3,0)),n=t[0].normal;
    if(!(p.name.startsWith('front-cab')?n[0]>.9:Math.abs(n[1])>.9&&n[1]*o[1]>0))continue;
    const d=Math.min(...supports.map(q=>ray(o,n.map(v=>-v),q)));assert(d<.065,p.name+' lacks real cab-wall support');maxGlassDistance=Math.max(maxGlassDistance,d);glassChecks++;
   }
  }
 }
 const wheels=parts.filter(p=>p.role==='wheel'),large=wheels.filter(p=>p.high[2]-p.low[2]>1.7);
 assert.equal(large.length,id==='steam-locomotive'?6:0,'missing/extra large wheel');assert.equal(wheels.length,id==='steam-locomotive'?12:8,'actual wheel count');
 for(const p of wheels){assert(Math.abs(p.low[2])<1e-5,p.name+' floats/below rail');}
 let minBoardClearance=Infinity;
 if(id==='steam-locomotive')for(const p of large)for(const q of parts.filter(q=>q.name.startsWith('running-board'))){const d=q.low[2]-p.high[2];assert(d>.049,'running board cuts driver crown');minBoardClearance=Math.min(minBoardClearance,d);}
 let frontCasingRays=0,frontWheelGap=null;
 if(id==='steam-locomotive'){
  const all=parts.flatMap(p=>p.ts);
  // Reference-backed silhouette/support contract: the cylinder casing fills
  // the upper-front running-gear region on BOTH sides. The prior thin platform
  // fails these rays even though its solids are closed and connected.
  for(const side of [-1,1])for(const x of [4.2,4.65,5.1])for(const h of [1.18,1.52,1.78]){
   const distance=Math.min(...all.map(t=>ray([x,side*2,h],[0,-side,0],t)));
   assert(distance<.70,'front cylinder region too empty at '+[x,side,h]);frontCasingRays++;
  }
  const leading=wheels.filter(p=>p.high[0]>4),casings=parts.filter(p=>p.role==='front-casing');
  assert.equal(casings.length,2,'missing front cylinder casing');
  frontWheelGap=Math.min(...casings.map(p=>p.low[2]))-Math.max(...leading.map(p=>p.high[2]));
  assert(frontWheelGap>.03,'front cylinder casing cuts leading wheel crown');
  for(const p of parts.filter(p=>p.name.startsWith('front-truck-')))assert(Math.max(Math.abs(p.low[1]),Math.abs(p.high[1]))<.90,'front truck intersects wheel rims laterally');
 }
 if(id==='steam-tender'){assert.equal(parts.filter(p=>p.role==='glass'||p.name.includes('headlamp')).length,0,'tender must not carry a cab');const frame=parts.find(p=>p.name==='tender-frame');assert(frame.low[2]-Math.max(...wheels.map(p=>p.high[2]))>.049,'tender underframe intersects wheel crowns');}
 return{id,front_casing_ray_checks:frontCasingRays,front_casing_wheel_gap_m:frontWheelGap,components:parts.length,triangles:vs.length/3,closed_directed_edges:edgeCount,positive_volume_solids:true,glazing_rays:glassChecks,max_glass_wall_gap_m:maxGlassDistance,wheel_rims:wheels.length,large_driver_rims:large.length,running_board_clearance_m:Number.isFinite(minBoardClearance)?minBoardClearance:null};
}
if(process.argv[1]===new URL(import.meta.url).pathname){const root=resolve(process.argv[2]),components=JSON.parse(readFileSync(resolve(root,'components.json'))),manifest=JSON.parse(readFileSync(resolve(root,'manifest.json'))),models=[];
 for(const m of manifest.models.filter(m=>m.category==='section'))models.push(audit(readNative(readFileSync(resolve(root,m.native))).vertices,components[m.id],m.id));
 writeFileSync(resolve(root,'geometry-verification.json'),JSON.stringify({status:'VERIFIED',models},null,2)+'\n');console.log(JSON.stringify(models));}
