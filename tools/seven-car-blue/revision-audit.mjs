// Compare actual closed glazing solids, including both door leaves, to the
// locally exported prototype. The lower skirt / chin / joint ribs may differ.
import {readFileSync,writeFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {createHash} from 'node:crypto';
import assert from 'node:assert/strict';
import {readNative} from '../station-kit/package.mjs';
const root=resolve(process.argv[2]),prior=resolve(process.argv[3]);
const manifest=JSON.parse(readFileSync(resolve(root,'manifest.json')));
const glass=JSON.parse(readFileSync(resolve(root,'geometry-verification.json'))).glass_rgba.split(',').map(Number);
const colors=[1,.92,.80,.70,.86].map(f=>glass.map((v,i)=>i===3?v:Math.round(v*f)).join(','));
function panes(bytes){const vs=readNative(bytes).vertices,out=[];for(let i=0;i<vs.length;i+=3)if(colors.includes(vs[i].color.join(',')))out.push(JSON.stringify(vs.slice(i,i+3).map(v=>[v.position,v.color])));return out.sort();}
const records=[];
for(const m of manifest.models.filter(m=>m.category==='section')){
 const before=readFileSync(resolve(prior,m.native)),after=readFileSync(resolve(root,m.native));
 assert.deepEqual(panes(after),panes(before),m.id+' glazing changed outside lower-body repair');
 assert.notDeepEqual(after,before,'No actual revision');
 records.push({id:m.id,unchanged_glazing_triangles:panes(after).length,prototype_native_sha256:createHash('sha256').update(before).digest('hex')});
}
writeFileSync(resolve(root,'revision-verification.json'),JSON.stringify({status:'VERIFIED',scope:'lower skirts, closed cab chin and separated gangway ribs; all closed window and door glazing unchanged',prototype:'uncommitted local prototype, recorded recipe and native SHA; not a claimed producer commit',models:records},null,2)+'\n');
console.log('VERIFIED unchanged glazing geometry across the actual lower-body revision.');
