// Inspect real native vertices. Reuse this vehicle's wheel connected-solid
// method; cab intake/door and paint thresholds come from its source review.
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {createHash} from 'node:crypto';
import {model} from '../train-models/native.mjs';
function solids(v){
 const parent=v.map((_,i)=>i),seen=new Map();const find=i=>{while(parent[i]!==i){parent[i]=parent[parent[i]];i=parent[i]}return i};
 for(let i=0;i<v.length;i++){const k=v[i].position.map(x=>Math.round(x*1e5)).join(',');if(seen.has(k))parent[find(i)]=find(seen.get(k));else seen.set(k,i);parent[find(i)]=find(i-i%3)}
 const groups=new Map();for(let i=0;i<v.length;i++){const k=find(i);if(!groups.has(k))groups.set(k,[]);groups.get(k).push(i)}
 return [...groups.values()].map(g=>{const low=[0,1,2].map(a=>Math.min(...g.map(i=>v[i].position[a]))),high=[0,1,2].map(a=>Math.max(...g.map(i=>v[i].position[a])));return{low,high,size:high.map((x,a)=>x-low[a]),centre:high.map((x,a)=>(x+low[a])/2)}});
}
function cab(v){assert(!solids(v).some(c=>Math.abs(c.centre[0]-8.45)<.03&&c.size[0]>.55&&c.size[0]<.70&&c.low[2]<1.4&&c.high[2]>3.1),'false full-height cab side door');}
function orange(c){return c[0]>c[1]*1.1&&c[1]>c[2]*1.5&&c[0]>c[2]*1.9}
function doorPaint(v){const selected=[];for(const x of [-6.4,0,6.4])for(const sign of [-1,1]){let n=0;for(let i=0;i<v.length;i+=3){const tri=v.slice(i,i+3),p=[0,1,2].map(a=>tri.reduce((s,t)=>s+t.position[a],0)/3);if(Math.abs(p[0]-x)<.67&&p[1]*sign>1.454&&p[2]>1.68&&p[2]<1.76&&orange(tri[0].color)){n++;selected.push(i,i+1,i+2)}}assert(n>=4,'missing orange on actual door faces')}return new Set(selected)}
const root=resolve(process.argv[2]),m=JSON.parse(readFileSync(root+'/manifest.json')),rows=[];
const old=process.argv[3]&&resolve(process.argv[3]);const oldManifest=old&&JSON.parse(readFileSync(old+'/manifest.json'));
for(const r of m.models.filter(x=>x.native_kind!=='assembly')){
 const v=model(readFileSync(resolve(root,r.native))).vertices;if(r.id.includes('-emc'))cab(v);const painted=doorPaint(v),bad=v.map((p,i)=>painted.has(i)?{...p,color:[182,192,200,255]}:p);assert.throws(()=>doorPaint(bad),/missing orange/);
 let previous=null;if(old){const record=oldManifest.models.find(x=>x.id===r.id),bytes=readFileSync(resolve(old,record.native)),before=model(bytes).vertices;assert.throws(()=>doorPaint(before),/missing orange/);if(r.id.includes('-emc'))assert.throws(()=>cab(before),/false full-height/);previous={producer:'ccc21854a16f21cb2d4f188749efaf6affd81d39',native_sha256:createHash('sha256').update(bytes).digest('hex'),actual_before_rejected:true};}
 rows.push({id:r.id,door_orange_face_vertices:painted.size,actual_door_colour_mutation_rejected:true,no_false_cab_door:r.id.includes('-emc')?true:null,previous});
}
writeFileSync(root+'/door-verification.json',JSON.stringify({status:'VERIFIED',models:rows,limits:'Specified painted door faces and the known full-height false cab panel; not exhaustive visual classification or collision proof.'},null,2)+'\n');console.log('VERIFIED native door paint, corrected cab intake, actual colour faults and supplied predecessor');
