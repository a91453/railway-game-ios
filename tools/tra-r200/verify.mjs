// Vehicle-specific tests on exported geometry, including actual mutations.
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {model,bounds} from '../train-models/native.mjs';
const root=resolve(process.argv[2]);const manifest=JSON.parse(readFileSync(resolve(root,'manifest.json')));
const near=model(readFileSync(resolve(root,manifest.models[0].native))).vertices;
const far=model(readFileSync(resolve(root,manifest.models[1].native))).vertices;
const tol=(x,y,t=.0001)=>Math.abs(x-y)<t;
// Orthographic X rays use barycentric coordinates in the YZ plane.
function firstHit(vs,end,y,z){
 let hit=null;
 for(let i=0;i<vs.length;i+=3){
  const t=vs.slice(i,i+3),p=t.map(v=>v.position),a=p[0],b=p[1],c=p[2];
  const det=(b[1]-a[1])*(c[2]-a[2])-(c[1]-a[1])*(b[2]-a[2]);if(Math.abs(det)<1e-10)continue;
  const u=((y-a[1])*(c[2]-a[2])-(c[1]-a[1])*(z-a[2]))/det;
  const v=((b[1]-a[1])*(z-a[2])-(y-a[1])*(b[2]-a[2]))/det;
  if(u<-.00001||v<-.00001||u+v>1.00001)continue;
  const x=a[0]+u*(b[0]-a[0])+v*(c[0]-a[0]);
  if(!hit||x*end>hit.x*end)hit={x,color:t[0].color};
 }
 return hit;
}
function highest(vs,x,y){
 let best=-Infinity;
 for(let i=0;i<vs.length;i+=3){const[a,b,c]=vs.slice(i,i+3).map(v=>v.position);const det=(b[0]-a[0])*(c[1]-a[1])-(c[0]-a[0])*(b[1]-a[1]);if(Math.abs(det)<1e-10)continue;const u=((x-a[0])*(c[1]-a[1])-(c[0]-a[0])*(y-a[1]))/det,v=((b[0]-a[0])*(y-a[1])-(x-a[0])*(b[1]-a[1]))/det;if(u>=0&&v>=0&&u+v<=1)best=Math.max(best,a[2]+u*(b[2]-a[2])+v*(c[2]-a[2]));}
 return best;
}
function tyreComponents(vs){
 const p=Array.from({length:vs.length/3},(_,i)=>i),keys=new Map();const f=i=>p[i]===i?i:(p[i]=f(p[i]));
 for(let i=0;i<vs.length;i++){const k=vs[i].position.map(x=>Math.round(x*1e5)).join(',');if(keys.has(k))p[f(Math.floor(i/3))]=f(keys.get(k));else keys.set(k,Math.floor(i/3));}
 const groups=new Map();for(let i=0;i<vs.length;i++){const k=f(Math.floor(i/3));if(!groups.has(k))groups.set(k,[]);groups.get(k).push(vs[i]);}
 return [...groups.values()].map(bounds).filter(b=>tol(b.maximum[0]-b.minimum[0],1)&&tol(b.maximum[2]-b.minimum[2],1)&&tol(b.maximum[1]-b.minimum[1],.2));
}
function check(vs){
 const tyres=tyreComponents(vs);assert.equal(tyres.length,12,'wrong wheel count / diameter');
 const seen=new Set();
 for(let i=0;i<vs.length;i+=3){const key=vs.slice(i,i+3).map(v=>v.position.map(n=>Math.round(n*1e5)).join(',')).sort().join('|');assert(!seen.has(key),'duplicate triangle / equipment');seen.add(key);}
 const b=bounds(vs);assert(tol(b.minimum[0],-10.005)&&tol(b.maximum[0],10.005),'coupler envelope');assert(tol(b.minimum[2],0)&&tol(b.maximum[2],4.08),'rail/roof envelope');
 for(const x of [2.55,4,5.45])assert(tol(highest(vs,x,.1),3.99,.003),'radiator fan hidden or displaced');
 for(const c of [-5.9,5.9])assert(vs.some(v=>tol(v.position[0],c+.35)&&tol(Math.abs(v.position[1]),.30)&&tol(v.position[2],1.21)),'bogie bolster support absent');
 for(const e of [-1,1])assert(vs.some(v=>tol(v.position[0]*e,9.39)&&tol(Math.abs(v.position[1]),.21)&&tol(v.position[2],1.26)),'coupler support absent');
 for(const e of [-1,1])for(const side of [-1,1]){
  for(const z of [.38,1.44])assert(vs.some(v=>Math.abs(v.position[0]*e-7.37)<.03&&Math.abs(v.position[1]*side-1.32)<.03&&tol(v.position[2],z)),'access step stile absent');
 }
 for(const x of [-3.05,2.45])for(const y of [-.86,.86])for(const z of [.4,1.16])assert(vs.some(v=>tol(v.position[0],x)&&tol(v.position[1],y)&&tol(v.position[2],z)),'fuel tank absent or displaced');
 for(const end of [-1,1]){
  const solid=firstHit(vs,end,.12,1.03),opening=firstHit(vs,end,-.14,1.03);
  assert(solid&&tol(solid.x*end,10.005,.002),'coupler casting missing');
  assert(!opening||opening.x*end<9.75,'coupler aperture blocked');
 }
 // Test every intended tyre contact from the final payload. Removing or
 // raising a wheel must fail rather than relying on the overall Z bound.
 for(const c of [-5.9,5.9])for(const dx of [-1.5,0,1.5])for(const side of [-1,1]){
  const contacts=vs.filter(v=>tol(v.position[0],c+dx)&&v.position[1]*side>.47&&v.position[1]*side<.69&&tol(v.position[2],0));assert(contacts.length,'missing wheel or lifted tyre');
 }
 for(const end of [-1,1]){
  for(const y of [-1.056,-.90,.90,1.056]){const h=firstHit(vs,end,y,2.09);assert(h&&h.color[0]>130&&h.x*end>9.46&&h.x*end<9.54,'lamp hidden or displaced');}
  for(const y of [-.72,-.38,.38,.72])for(const z of [3.03,3.22,3.40]){
   const h=firstHit(vs,end,y,z);assert(h&&h.color[2]>h.color[0]&&h.color[0]<90,'windshield occluded');
   assert(tol(h.x*end,9.45-(z-2.1)*.39+.042+Math.max(0,1-(y/1.426)**2)*.045,.012),'windshield surface intersection');
  }
  const glass=vs.filter(v=>v.position[0]*end>8.7&&v.position[2]>2.84&&v.position[2]<3.49&&Math.abs(v.position[1])<1.12);
  assert(glass.length,'cab glass absent');
  const front=glass.filter(v=>Math.abs(v.normal[0])>.5&&v.normal[0]*end>0&&v.color[2]>v.color[0]*1.4&&v.color[0]<80);
  assert(front.length,'front-facing glass');
  for(const v of front){const[x,y,z]=v.position;const gap=x*end-(9.45-Math.max(0,z-2.1)*.39+Math.max(0,1-(y/1.426)**2)*.045);assert(gap>.019&&gap<.06,'glass buried or floating');assert(Math.abs(y)<1.12,'glass outside frame');}
 }
 for(const side of [-1,1])for(const end of [-1,1]){
 for(const [x,z,d]of [[8.1,3.05,1.452],[8.4,3.3,1.452],[7.62,3.1,1.466]]){const h=sideHit(vs,side,x*end,z);assert(h&&h.color[2]>h.color[0]&&h.color[0]<90&&tol(h.x*side,d,.002),'side glass floating, buried or occluded');}
}
 for(const side of [-1,1])for(const x of [-3.4,3.2,4.5,5.8]){const h=sideHit(vs,side,x,2.30);assert(h&&tol(h.x*side,1.446,.003),'major side grille displaced or missing');}
 return b;
}
for(const vs of [near,far])check(vs);
function sideHit(vs,side,x,z){return firstHit(vs.map(v=>({...v,position:[v.position[1],v.position[0],v.position[2]]})),side,x,z);}

for(const side of [-1,1])for(const x of [-6.2,-1.5,0,1.5,6.5])for(const z of [1.50,2.50,3.70]){
 const a=sideHit(near,side,x,z),b=sideHit(far,side,x,z);assert(a&&b,'LOD side missing');
 const colour=c=>c[0]>120?'white':c[2]>c[0]+8?'navy':'equipment';assert.equal(colour(a.color),colour(b.color),'LOD paint boundary jump');
}
// An actual opaque interior cover protruding through the windshield is rejected.
const cover=[[-.7,2.9],[.7,2.9],[0,3.5]].map(([y,z])=>({position:[9.7,y,z],normal:[1,0,0],color:[235,237,234,255]}));
assert.throws(()=>check([...near,...cover]),/windshield/);
const reversed=near.map(v=>({...v,position:[-v.position[0],-v.position[1],v.position[2]],normal:[-v.normal[0],-v.normal[1],v.normal[2]]}));
assert.throws(()=>check(reversed),/fan|roof/);
assert.throws(()=>check([...near,...structuredClone(near.slice(0,3))]),/duplicate/);
const bad=(mutator,pattern)=>{const v=structuredClone(near);mutator(v);assert.throws(()=>check(v),pattern);};
bad(v=>{for(const a of v)if(tol(a.position[0],4.4)&&Math.abs(a.position[1])>.47&&Math.abs(a.position[1])<.69&&a.position[2]<.01)a.position[2]+=.1;},/wheel/);
bad(v=>{for(const a of v)if(a.position[0]>8.7&&a.position[2]>2.84&&a.position[2]<3.49&&a.color[2]>a.color[0])a.position[0]+=.2;},/glass|windshield/);
bad(v=>{for(const a of v)if(a.position[0]>8.7&&a.position[2]>2.84&&a.position[2]<3.49&&a.color[2]>a.color[0])a.position[0]-=.1;},/glass|windshield/);
bad(v=>{for(const a of v)if(a.position[0]>2&&a.position[0]<6.5&&a.position[2]>3.97)a.position[2]-=.1;},/fan|roof/);
bad(v=>{for(const a of v)if(Math.abs(a.position[0]-5.9)<.36&&Math.abs(a.position[1])<.31&&a.position[2]>1.06&&a.position[2]<1.22)a.position[2]-=.2;},/bolster/);
bad(v=>{for(const a of v)if(a.position[0]>9&&a.position[0]<9.4&&Math.abs(a.position[1])<.22&&a.position[2]>1.07&&a.position[2]<1.27)a.position[0]-=.2;},/coupler/);
bad(v=>{for(const a of v)if(Math.abs(a.position[0]-7.37)<.03&&a.position[1]>.28&&tol(a.position[2],.38))a.position[2]+=.1;},/stile/);
bad(v=>{for(const a of v)if(a.position[0]>7.9&&a.position[0]<8.7&&a.position[2]>2.92&&a.position[2]<3.49&&a.color[2]>a.color[0])a.position[1]+=.2;},/side glass/);
bad(v=>{for(const a of v)if(a.position[0]>8.8&&a.position[2]>2&&a.position[2]<2.17&&a.color[0]>130&&a.color[0]>a.color[2]+20)a.position[0]+=.2;},/lamp/);
bad(v=>{for(const a of v)if(a.position[0]>-3.06&&a.position[0]<2.46&&Math.abs(a.position[1])<.87&&a.position[2]>.39&&a.position[2]<1.17)a.position[2]+=.1;},/fuel/);
bad(v=>{for(const a of v)if(a.position[0]>2.7&&a.position[0]<6.3&&a.position[2]>1.9&&a.position[2]<3.4&&a.color[0]<130&&a.color[2]-a.color[0]<20)a.position[0]+=.5;},/grille/);
const bp=[[9.92,-.18,.995],[10.005,-.18,.995],[10.005,-.07,.995],[9.92,-.07,.995],[9.92,-.18,1.065],[10.005,-.18,1.065],[10.005,-.07,1.065],[9.92,-.07,1.065]];
const blocked=[...near];for(const q of [[0,3,2,1],[4,5,6,7],[0,1,5,4],[1,2,6,5],[2,3,7,6],[3,0,4,7]])for(const ix of [q[0],q[1],q[2],q[0],q[2],q[3]])blocked.push({position:bp[ix],normal:[1,0,0],color:[98,107,112,255]});
assert.throws(()=>check(blocked),/aperture/);
if(process.argv[3]){const old=JSON.parse(readFileSync(resolve(process.argv[3],'manifest.json')));const v=model(readFileSync(resolve(process.argv[3],old.models[0].native))).vertices;assert.throws(()=>check(v),/fan|windshield/);}
assert(near.length>far.length*2,'far detail budget');
assert.deepEqual(bounds(near),bounds(far),'LOD envelope jump');
writeFileSync(resolve(root,'r200-verification.json'),JSON.stringify({status:'VERIFIED',previous_revision_rejection:process.argv[3]?'VERIFIED':'UNVERIFIED',checks:['12 connected tyre components of expected diameter/width and 12 rail contacts at 6 axle stations','rail/coupler/roof bounds','both end front-facing glass surface gap and 24 first-hit rays','near/far bounds, side paint classification and detail ratio','visible radiator fan first-hit rays; hidden-fan mutation','duplicate triangle, protruding interior cover and reversed whole locomotive rejected','bogie bolster, step stiles and drawgear support witnesses; actual support displacement mutations','actual lifted tyre and floating/buried windshield mutations rejected','concave coupler aperture and closed blocking-box counterexample','optional genuine R1 rejection probe'],limits:['not exhaustive collision detection','side window and door glass rays are sampled, opposite side fittings and roof BOM need sources','24 first-hit windshield rays are sampled visibility, not all-view intersection proof']},null,2)+'\n');
console.log('VERIFIED R200-specific geometry probes');
