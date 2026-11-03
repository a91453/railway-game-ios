// Actual native surface audit adapted from the asset checker at 36434179.
// Additional static validation; does not generate or change delivered models.
// node duplicate-check.mjs REVISION_DIR PUBLIC_PRODUCER_CHECKOUT
// Common native reader: public tools/train-models/native.mjs at geometry producer.
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import {createHash} from 'node:crypto';
const root=resolve(process.argv[2]),repo=resolve(process.argv[3]);
const {model}=await import(pathToFileURL(resolve(repo,'tools/train-models/native.mjs')));
function key(p){return p.map(x=>Math.round(x*1e5)).join(',')}
function inspect(v){const seen=new Set();for(let i=0;i<v.length;i+=3){const q=v.slice(i,i+3).map(x=>key(x.position)),k=q.map((_,j)=>[q[j],q[(j+1)%3],q[(j+2)%3]].join('|')).sort()[0];assert(!seen.has(k),'coincident same-winding duplicate surface');seen.add(k)}return seen.size}
function shell(v){const parent=v.map((_,i)=>i),seen=new Map(),find=i=>{while(parent[i]!==i){parent[i]=parent[parent[i]];i=parent[i]}return i};for(let i=0;i<v.length;i++){const k=key(v[i].position);if(seen.has(k))parent[find(i)]=find(seen.get(k));else seen.set(k,i);parent[find(i)]=find(i-i%3)}const groups=new Map();for(let i=0;i<v.length;i++){const k=find(i);if(!groups.has(k))groups.set(k,[]);groups.get(k).push(i)}const candidates=[...groups.values()].map(indices=>({indices,low:[0,1,2].map(a=>Math.min(...indices.map(i=>v[i].position[a]))),high:[0,1,2].map(a=>Math.max(...indices.map(i=>v[i].position[a])))})).filter(c=>c.high[0]-c.low[0]>17&&c.high[1]-c.low[1]>2.5&&c.high[2]-c.low[2]>2.5);assert(candidates.length>0,'actual metre-scale body shell required');return candidates[0]}

const manifest=JSON.parse(readFileSync(resolve(root,'manifest.json'))),rows=[];
for(const m of manifest.models){const bytes=readFileSync(resolve(root,m.native)),v=model(bytes).vertices,unique=inspect(v),body=shell(v),mutant=v.concat(body.indices.map(i=>structuredClone(v[i])));assert.throws(()=>inspect(mutant),/duplicate surface/);rows.push({id:m.id,input_native_sha256:createHash('sha256').update(bytes).digest('hex'),unique_oriented_triangles:unique,duplicated_actual_shell_triangles:body.indices.length/3,shell_bounds:{minimum:body.low,maximum:body.high},actual_duplicate_shell_rejected:true})}
writeFileSync(resolve(root,'duplicate-verification.json'),JSON.stringify({status:'VERIFIED',validator_sha256:createHash('sha256').update(readFileSync(new URL(import.meta.url))).digest('hex'),native_reader_sha256:createHash('sha256').update(readFileSync(resolve(repo,'tools/train-models/native.mjs'))).digest('hex'),geometry_producer:manifest.producer_commit??null,models:rows,precision_m:1e-5,limits:'Coincident same-winding triangle surfaces only. Opposite-winding shared contact caps are allowed. Does not certify general intersections, separated duplicate objects, Boolean union, dynamics or device rendering.'},null,2)+'\n');console.log('VERIFIED',rows.length,'final native items and actual connected body-shell duplication faults');
