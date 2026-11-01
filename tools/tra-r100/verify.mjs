// R100-specific checks against final exported native triangles. Shared topology,
// GLB, PNG and loader checks remain in tools/train-models, without weaker gates.
import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {createHash} from 'node:crypto';
import {model, bounds} from '../train-models/native.mjs';

const run = process.argv[2];
if (!run) throw Error('usage: node tools/tra-r100/verify.mjs OUT');
const root = resolve(run);
const manifest = JSON.parse(readFileSync(resolve(root, 'manifest.json')));
const records = new Map(manifest.models.map(m => [m.id, m]));
const tolerance = .003; // Export comparison tolerance, not engineering precision.
const close = (a,b,t=tolerance) => Math.abs(a-b) <= t;
const glass = v => v.color[2] >= 18 && v.color[2] <= 70 &&
  v.color[0]/v.color[2] > .58 && v.color[0]/v.color[2] < .67 &&
  v.color[1]/v.color[2] > .75 && v.color[1]/v.color[2] < .85;
const sub = (a,b) => a.map((v,i) => v-b[i]);
const add = (a,b) => a.map((v,i) => v+b[i]);
const mul = (a,n) => a.map(v => v*n);
const dot = (a,b) => a.reduce((n,v,i) => n+v*b[i],0);
const cross = (a,b) => [a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]];
const norm = v => mul(v,1/Math.hypot(...v));
const centroid = t => mul(t.map(v=>v.position).reduce(add,[0,0,0]),1/3);
const triangles = vs => Array.from({length:vs.length/3},(_,i)=>vs.slice(i*3,i*3+3));

// Möller–Trumbore rays are independent of the production builder. All returned
// distances are in native metres; back faces are intentionally included.
function rayDistance(origin,direction,t) {
  const [a,b,c] = t.map(v=>v.position),e1=sub(b,a),e2=sub(c,a);
  const h=cross(direction,e2),det=dot(e1,h);
  if(Math.abs(det)<1e-10)return null;
  const s=sub(origin,a),u=dot(s,h)/det;
  if(u < -1e-7 || u > 1+1e-7)return null;
  const q=cross(s,e1),v=dot(direction,q)/det;
  if(v < -1e-7 || u+v > 1+1e-7)return null;
  const d=dot(e2,q)/det;
  return d>=0 ? d : null;
}
function firstHit(ts,origin,direction,accept=()=>true) {
  let nearest=null;
  for(let i=0;i<ts.length;i++) {
    if(!accept(ts[i],i))continue;
    const d=rayDistance(origin,direction,ts[i]);
    if(d!==null && (!nearest || d<nearest.distance))nearest={distance:d,triangle:ts[i],index:i,position:add(origin,mul(direction,d))};
  }
  return nearest;
}
function orthographic(ts,axis,sign,a,b,accept=()=>true) {
  const other=[0,1,2].filter(n=>n!==axis),origin=[0,0,0],direction=[0,0,0];
  origin[axis]=sign*30;origin[other[0]]=a;origin[other[1]]=b;direction[axis]=-sign;
  return firstHit(ts,origin,direction,accept);
}

function components(vs) {
  const count=vs.length/3,parent=Array.from({length:count},(_,i)=>i),at=new Map();
  function find(i){return parent[i]===i?i:(parent[i]=find(parent[i]));}
  for(let i=0;i<vs.length;i++) {
    const key=vs[i].position.map(n=>Math.round(n*1e5)).join(',');
    if(at.has(key))parent[find(Math.floor(i/3))]=find(at.get(key));
    else at.set(key,Math.floor(i/3));
  }
  const groups=new Map();
  for(let i=0;i<vs.length;i++) {
    const key=find(Math.floor(i/3));if(!groups.has(key))groups.set(key,[]);groups.get(key).push(i);
  }
  return [...groups.values()].map(indices=>({indices,vertices:indices.map(i=>vs[i]),...bounds(indices.map(i=>vs[i]))}));
}
function checkDuplicates(vs) {
  const seen=new Set();
  for(const t of triangles(vs)) {
    const key=t.map(v=>v.position.map(n=>Math.round(n*1e5)).join(',')).sort().join('|');
    assert(!seen.has(key),'duplicate shell or equipment triangle');seen.add(key);
  }
}

const axleStations=[-4.55,4.55].flatMap(c=>[-1.35,0,1.35].map((dx,i)=>({x:c+dx,r:i===1?.43:.508})));
function checkRunning(vs) {
  const parts=components(vs);
  const wheels=parts.filter(p=>{
    const d=p.maximum.map((n,i)=>n-p.minimum[i]);
    return close(d[1],.18) && [1.016,.86].some(n=>close(d[0],n)&&close(d[2],n));
  });
  assert.equal(wheels.length,12,'wheel count / A1A-A1A axle count or tyre size');
  for(const {x,r} of axleStations)for(const side of [-1,1]) {
    const wheel=wheels.filter(p=>close((p.minimum[0]+p.maximum[0])/2,x)&&
      close((p.minimum[1]+p.maximum[1])/2,side*.6235));
    assert.equal(wheel.length,1,'missing wheel or bogie/axle displaced');
    const p=wheel[0];
    assert(close(p.minimum[2],0),'wheel lifted from or buried below rail');
    assert(close(p.maximum[2],2*r),'powered/idler wheel diameter or axle height');
    assert(close(p.minimum[0],x-r)&&close(p.maximum[0],x+r),'wheel diameter/axle displacement');
  }
  return wheels;
}

// Only cab glazing is classified; the blue hood paint is not glazing. The
// outward pane face must be exposed AND have a non-glass physical backing.
function checkGlass(vs) {
  const ts=triangles(vs),panes=[];
  // Only the two actual narrow diagonal windshield-wiper solids may mask a
  // few glass rays. A wide opaque cover never matches this component shape.
  const wipers=components(vs).filter(p=>p.minimum[0]>5.23&&p.maximum[0]<5.27&&p.maximum[0]-p.minimum[0]<.025&&p.maximum[1]-p.minimum[1]<.48&&p.maximum[1]-p.minimum[1]>.40&&p.minimum[2]>2.93&&p.maximum[2]<3.36);
  assert(wipers.length===0||wipers.length===2,'unexpected windshield wiper geometry');
  const wiperTriangles=new Set(wipers.flatMap(p=>p.indices.map(i=>Math.floor(i/3))));
  for(let i=0;i<ts.length;i++) {
    const t=ts[i],p=centroid(t),n=t[0].normal;
    if(!t.every(glass)||p[2]<2.8||p[2]>3.6||p[0]<2.8||p[0]>5.7)continue;
    const outward=(n[0]>.95 && p[0]>5.1)||(n[0]<-.95 && p[0]<3.3)||
      (Math.abs(n[1])>.95 && p[1]*n[1]>1.40);
    if(!outward)continue;
    const outer=firstHit(ts,add(p,mul(n,.0005)),n,(_,j)=>j!==i&&!wiperTriangles.has(j));
    assert(!outer||outer.distance>.25,`cab glass obscured / buried / interior cover protrudes at ${p} outward ${n}; hit ${outer?.distance} at ${outer?.position}`);
    const support=firstHit(ts,add(p,mul(n,-.0005)),mul(n,-1),t=>!t.every(glass));
    assert(support && support.distance<.025 && support.distance>=0,'cab glass floating: no physical backing within pane thickness plus 3mm');
    panes.push({index:i,centre:p,normal:n,support_gap:support.distance});
  }
  assert(panes.length>=12,'cab glazing missing or no outward visible pane surfaces');
  // These probes are away from the central nose and narrow wipers/frames.
  for(const y of [-.95,-.64,.64,.95])for(const z of [3.12,3.32]) {
    const hit=orthographic(ts,0,1,y,z,(_,i)=>!wiperTriangles.has(i));
    assert(hit&&hit.triangle.every(glass),'short-end cab windshield hidden or missing');
    assert(close(hit.position[0],5.246,.008),'short-end windshield floating / buried / end reversed');
  }
  for(const side of [-1,1])for(const [x,z,plane] of [[4.15,3.15,1.470],[4.7,3.15,1.456]]) {
    const hit=orthographic(ts,1,side,x,z);
    assert(hit&&hit.triangle.every(glass),'side cab window missing, buried or hidden');
    assert(close(hit.position[1]*side,plane,.003),'side cab window displaced / floating');
  }
  return panes;
}

function checkEnvelope(vs) {
  const b=bounds(vs);
  assert(close(b.minimum[0],-7.9)&&close(b.maximum[0],7.9),'R100 model coupling envelope');
  assert(close(b.minimum[2],0)&&close(b.maximum[2],3.92),'R100 rail/roof model envelope');
  return b;
}

function checkEquipment(vs) {
  const parts=components(vs),ts=triangles(vs),found=[];
  function requirePart(name,lo,hi,multiplicity=1) {
    const extent=hi.map((n,i)=>n-lo[i]);
    const sameShape=parts.filter(p=>extent.every((n,i)=>close(n,p.maximum[i]-p.minimum[i],.003)));
    assert.equal(sameShape.length,multiplicity,`${name} duplicate equipment or wrong dimensions`);
    const matches=parts.filter(p=>lo.every((n,i)=>close(n,p.minimum[i],.003))&&hi.every((n,i)=>close(n,p.maximum[i],.003)));
    assert.equal(matches.length,1,`${name} absent, duplicated or displaced`);
    const part=matches[0];found.push({name,minimum:part.minimum,maximum:part.maximum});return part;
  }
  const shells=parts.filter(p=>p.maximum[0]-p.minimum[0]>1.7&&p.maximum[2]-p.minimum[2]>.8&&p.minimum[2]>1.4);
  assert.equal(shells.length,3,'duplicate or missing main body shell');
  requirePart('long hood shell',[-7.12,-1.08,1.48],[3.18,1.08,3.53]);
  requirePart('cab shell',[3.18,-1.475,1.48],[5.22,1.475,3.80]);
  requirePart('short hood shell',[5.22,-1.08,1.48],[7.10,1.08,2.80]);
  const fuel=requirePart('fuel tank',[-2.50,-.88,.40],[1.35,.88,1.08]);
  const ac=requirePart('cab air conditioner',[3.445,-.45,3.80],[4.355,.45,3.92]);
  const exhaustBase=requirePart('exhaust base',[-.96,-.275,3.50],[-.34,.275,3.63]);
  const exhaust=requirePart('exhaust stack',[-.87,-.185,3.63],[-.43,.185,3.73]);
  const radiator=requirePart('long-end roof radiator',[-6.80,-.785,3.51],[-4.90,.785,3.545]);
  for(const c of [-4.55,4.55]) {
    requirePart('bogie main frame '+c,[c-1.81,-.74,.84],[c+1.81,.74,1.06],2);
    requirePart('bogie bolster '+c,[c-.39,-.59,1.06],[c+.39,.59,1.24],2);
  }
  // Cast separate components are tested at actual opposing surfaces. This
  // permits a seated/intersecting attachment but rejects an actual air gap.
  function seated(name,part,point,direction,maxDistance=.004) {
    const own=new Set(part.indices.map(i=>Math.floor(i/3)));
    const hit=firstHit(ts,point,direction,(_,i)=>!own.has(i));
    assert(hit&&hit.distance<=maxDistance,`${name} has no touching physical support`);
    return {name,gap:hit.distance};
  }
  const feet=[];
  for(const side of [-1,1])feet.push(requirePart('AC saddle '+side,[3.50,side*.34-.065,3.785],[4.30,side*.34+.065,3.80],2));
  const supports=[
    seated('exhaust stack',exhaust,[-.65,0,3.631],[0,0,-1]),
    seated('cab air conditioner',ac,[3.90,0,3.801],[0,0,-1]),
    seated('roof radiator',radiator,[-5.85,0,3.531],[0,0,-1]),
    seated('exhaust base',exhaustBase,[-.65,0,3.531],[0,0,-1]),
    // The actual tank top and the lower chassis bottom share Z=1.08.
    seated('fuel tank',fuel,[-.50,0,1.079],[0,0,1])
  ];
  for(let i=0;i<feet.length;i++) {
    const side=i===0?-1:1;
    supports.push(seated('AC saddle '+side,feet[i],[3.90,side*.34,3.78864],[0,0,-1]));
  }
  const lenses=parts.filter(p=>close(p.maximum[0]-p.minimum[0],.064)&&close(p.maximum[1]-p.minimum[1],.166)&&close(p.maximum[2]-p.minimum[2],.166));
  assert.equal(lenses.length,4,'stacked headlamp lenses missing or duplicated');
  for(const end of [-1,1])for(const z of end>0?[3.56,3.74]:[3.16,3.34]) {
    const expectedX=end>0?5.22:-7.12;
    const lens=lenses.find(p=>close((p.minimum[2]+p.maximum[2])/2,z)&&close((p.minimum[0]+p.maximum[0])/2,expectedX+end*.053));
    assert(lens,'headlamp location or long/short end configuration');
    supports.push(seated('headlamp lens',lens,[expectedX+end*.023,0,z],[-end,0,0]));
    const hit=orthographic(ts,0,end,0,z);
    assert(hit&&close(hit.position[0],expectedX+end*.085,.003),'headlamp hidden or front lens displaced');
  }
  // Fixed first-hit points verify visible principal louvres and steps, rather
  // than merely finding hidden vertices with the expected coordinates.
  for(const side of [-1,1]) {
    for(const x of [-6.10,-5.47]) {
      const hit=orthographic(ts,1,side,x,2.10);
      assert(hit&&close(hit.position[1]*side,1.098,.026),'long-end side radiator missing or displaced');
    }
    for(const end of [-1,1])for(const z of [.50,.83,1.16]) {
      const hit=orthographic(ts,1,side,end*6.99,z);
      assert(hit&&hit.position[1]*side>=1.40&&hit.position[1]*side<=1.46,'platform step missing or displaced');
    }
  }
  return {principal_components:found,supports};
}
function check(vs) {
  checkDuplicates(vs);const wheels=checkRunning(vs),envelope=checkEnvelope(vs),panes=checkGlass(vs),equipment=checkEquipment(vs);
  return {envelope,wheels: wheels.map(({minimum,maximum})=>({minimum,maximum})),glazing_samples:panes,equipment};
}

function paintClass(c) {
  const [r,g,b]=c;
  if(r>90&&g>90&&b>90&&Math.max(r,g,b)-Math.min(r,g,b)<45)return 'light';
  if(r>g*1.3&&r>b*1.7)return 'orange';
  if(b>r*1.5&&g>r*1.25)return 'blue';
  return 'equipment';
}
function checkLivery(vs,livery) {
  const ts=triangles(vs),body=livery==='orange'?'orange':'blue';
  for(const side of [-1,1]) {
    for(const [x,z] of [[-4.3,2.60],[-2.5,2.70],[2.9,2.70],[6.5,2.10]]) {
      const hit=orthographic(ts,1,side,x,z);
      assert(hit&&paintClass(hit.triangle[0].color)===body,`wrong representative body livery at ${side}/${x}/${z}: ${hit?.triangle[0].color}`);
    }
    for(const [x,z] of [[-4.3,1.90],[-2.5,2.40],[2.9,2.40],[6.5,2.40]]) {
      const hit=orthographic(ts,1,side,x,z);
      assert(hit&&paintClass(hit.triangle[0].color)==='light','R100 white waist sweep missing or misplaced');
    }
  }
  for(const [y,z] of [[0,1.80],[-.9,2.30],[.9,2.30]]) {
    const hit=orthographic(ts,0,1,y,z);
    assert(hit&&paintClass(hit.triangle[0].color)==='light','short-hood white flying-wing paint missing or misplaced');
  }
}
function checkLOD(a,b) {
  const ba=bounds(a),bb=bounds(b);
  for(const key of ['minimum','maximum'])for(let i=0;i<3;i++)assert(close(ba[key][i],bb[key][i]),'near/far maximum equipment envelope jump');
  assert(b.length<a.length/2,'R100 far unit must be less than half near triangles');
  const ta=triangles(a),tb=triangles(b);
  // Fixed, shared camera rays sample body regions and paint on both sides.
  for(const side of [-1,1])for(const x of [-5.4,-3.4,-1.4,-.1,2.9,4,6.6])for(const z of [1.6,2.0,2.4,2.5]) {
    const x1=orthographic(ta,1,side,x,z),x2=orthographic(tb,1,side,x,z);
    assert.equal(Boolean(x1),Boolean(x2),'near/far body silhouette missing');
    if(!x1)continue;
    assert(Math.abs(x1.position[1]-x2.position[1])<.08,'near/far body or major equipment position jump');
    assert.equal(paintClass(x1.triangle[0].color),paintClass(x2.triangle[0].color),`near/far livery boundary jump at ${side}/${x}/${z}: ${x1.triangle[0].color} -> ${x2.triangle[0].color}`);
  }
}

const failures=[];
function reject(name,vs,operation,validator=check,pattern) {
  const broken=structuredClone(vs);const result=operation(broken)||broken;
  let error;try{validator(result);}catch(e){error=e;}
  assert(error,`fault was accepted: ${name}`);
  if(pattern)assert.match(error.message,pattern,`unrelated rejection of ${name}`);
  failures.push({fault:name,result:'REJECTED',reason:error.message});
}
const outputs=[];
for(const id of ['tra-r100-r122-orange-locomotive','tra-r100-r123-breezy-blue-locomotive']) {
  const near=records.get(id),far=records.get(id+'-far');
  assert(near&&far,`missing required R100 near/far independent units: ${id}`);
  const nv=model(readFileSync(resolve(root,near.native))).vertices;
  const fv=model(readFileSync(resolve(root,far.native))).vertices;
  const nearResult=check(nv),farResult=check(fv);
  const livery=id.includes('orange')?'orange':'blue';checkLivery(nv,livery);checkLivery(fv,livery);checkLOD(nv,fv);
  const pane=nearResult.glazing_samples.find(p=>p.normal[0]>.95);
  assert(pane,'missing mutatable short-end windshield');
  // Mutate all glass of the cab face, not just metadata or one manifest bound.
  const frontGlass=v=>glass(v)&&v.position[0]>5.20&&v.position[0]<5.30&&v.position[2]>2.8;
  reject(id+': floating windshield',nv,v=>v.forEach(a=>{if(frontGlass(a))a.position[0]+=.20;}),check,/glass|windshield/);
  reject(id+': buried windshield',nv,v=>v.forEach(a=>{if(frontGlass(a))a.position[0]-=.15;}),check,/glass|windshield/);
  const longHood=components(nv).find(p=>close(p.minimum[0],-7.12)&&close(p.maximum[0],3.18)&&close(p.maximum[2],3.53));
  assert(longHood,'missing complete long hood shell for duplicate-shell fault');
  reject(id+': offset duplicate long hood shell',nv,v=>[...v,...longHood.indices.map(i=>{const a=structuredClone(nv[i]);a.position[1]+=.03;return a;})],check,/duplicate|shell/);
  const duplicate=nv.slice(0,3);
  reject(id+': duplicate shell/equipment',nv,v=>[...v,...structuredClone(duplicate)],check,/duplicate/);
  reject(id+': swapped long/short ends',nv,v=>v.forEach(a=>{
    a.position[0]*=-1;a.position[1]*=-1;a.normal[0]*=-1;a.normal[1]*=-1;
  }),check,/glass|glazing|windshield|window/);
  const wheel=components(nv).find(p=>close(p.maximum[1]-p.minimum[1],.18)&&close(p.maximum[0]-p.minimum[0],1.016));
  assert(wheel,'no actual connected wheel for rejection tests');
  reject(id+': lifted actual tyre',nv,v=>wheel.indices.forEach(i=>v[i].position[2]+=.10),check,/wheel|axle|tyre/);
  const removed=new Set(wheel.indices);
  reject(id+': missing actual tyre',nv,v=>v.filter((_,i)=>!removed.has(i)),check,/wheel|axle|tyre/);
  reject(id+': wrong axle station',nv,v=>wheel.indices.forEach(i=>v[i].position[0]+=.25),check,/wheel|axle|tyre/);
  reject(id+': buried actual tyre',nv,v=>wheel.indices.forEach(i=>v[i].position[2]-=.10),check,/wheel|axle|tyre/);
  // Opaque triangle protrudes into the windshield's visible area. This is final
  // geometry, not a fake manifest flag; generic topology audit is separate.
  const cover=[[-1.1,3.0],[1.1,3.0],[0,3.52]].map(([y,z])=>({position:[5.29,y,z],normal:[1,0,0],color:[220,220,215,255],glow:0}));
  reject(id+': interior cover through windshield',nv,v=>[...v,...cover],check,/glass|windshield/);
  function movePart(label,lo,hi,axis,delta,pattern) {
    const part=components(nv).find(p=>lo.every((n,i)=>close(n,p.minimum[i]))&&hi.every((n,i)=>close(n,p.maximum[i])));
    assert(part,'no actual component for '+label);
    reject(id+': '+label,nv,v=>part.indices.forEach(i=>v[i].position[axis]+=delta),check,pattern);
  }
  const actualLamp=components(nv).find(p=>close(p.maximum[0]-p.minimum[0],.064)&&close((p.minimum[2]+p.maximum[2])/2,3.74));
  assert(actualLamp,'no actual headlamp for floating-lens rejection');
  reject(id+': floating headlamp lens',nv,v=>actualLamp.indices.forEach(i=>v[i].position[0]+=.05),check,/lamp/);
  movePart('fuel tank displaced',[-2.50,-.88,.40],[1.35,.88,1.08],2,.12,/fuel/);
  movePart('exhaust stack floating',[-.87,-.185,3.63],[-.43,.185,3.73],2,.10,/exhaust/);
  movePart('roof radiator displaced',[-6.80,-.785,3.51],[-4.90,.785,3.545],0,.20,/radiator/);
  movePart('bogie frame displaced',[-6.36,-.74,.84],[-2.74,.74,1.06],0,.20,/bogie/);
  reject(id+': far floating windshield',fv,v=>v.forEach(a=>{if(frontGlass(a))a.position[0]+=.20;}),check,/glass|windshield/);
  reject(id+': far buried windshield',fv,v=>v.forEach(a=>{if(frontGlass(a))a.position[0]-=.15;}),check,/glass|windshield/);
  reject(id+': distant LOD wrong waist colour',fv,v=>v.forEach(a=>{
    if(a.position[0]>2.7&&a.position[0]<3.2&&paintClass(a.color)==='light')a.color=livery==='orange'?[231,110,50,255]:[36,62,89,255];
  }),v=>checkLOD(nv,v),/near\/far/);
  reject(id+': wrong representative livery',nv,v=>v.forEach(a=>{
    if(paintClass(a.color)===livery)a.color=livery==='orange'?[36,62,89,255]:[231,110,50,255];
  }),v=>checkLivery(v,livery),/livery/);
  reject(id+': missing white waist sweep',nv,v=>v.forEach(a=>{
    if(a.position[0]>2.7&&a.position[0]<3.2&&paintClass(a.color)==='light')a.color=livery==='orange'?[231,110,50,255]:[36,62,89,255];
  }),v=>checkLivery(v,livery),/waist/);
  reject(id+': distant LOD shifted body',fv,v=>v.forEach(a=>{if(a.position[2]>1.4)a.position[1]+=.16;}),v=>checkLOD(nv,v),/near\/far/);
  outputs.push({id,near:nearResult,far:farResult,native_sha256:createHash('sha256').update(readFileSync(resolve(root,near.native))).digest('hex'),far_native_sha256:createHash('sha256').update(readFileSync(resolve(root,far.native))).digest('hex')});
}

writeFileSync(resolve(root,'r100-verification.json'),JSON.stringify({
  status:'VERIFIED',models:outputs,rejected_faults:failures,
  checks:['final native connected wheel parts: A1A-A1A six axle stations, two wheel diameters, all twelve rail contacts',
    'outward cab glazing exposure, backing gap and fixed first-hit front/side samples independently for both LODs',
    'duplicate shell/equipment triangles; actual glass, wheel, interior-cover and reversed-end mutations',
    'principal fuel, roof radiator, exhaust, AC, bogie frame and bolster positions plus actual equipment support rays',
    'near/far maximum equipment envelope, sampled silhouette and livery boundaries'],
  limitations:['model envelope and inferred axle dimensions are the documented display simplification, not independently established real-world dimensions',
    'ray samples are not exhaustive all-view occlusion or global self-intersection proof',
    'this report does not establish user appearance acceptance, operating integration, device behavior or a reliable numbered full Breezy Blue formation',
    'shared topology/GLB/PNG/viewer and independent Swift assembly reports must also pass']
},null,2)+'\n');
console.log(`VERIFIED R100 native geometry; ${failures.length} actual faults rejected`);
