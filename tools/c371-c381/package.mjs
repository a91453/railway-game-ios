import {readFileSync,writeFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {createHash} from 'node:crypto';
import assert from 'node:assert/strict';
import {assemblyNative} from './scene.js';
import {readNative as readUnit,glbFromNative} from '../station-kit/package.mjs';
export {glbFromNative};
export function readNative(bytes){const b=assemblyNative(bytes.buffer.slice(bytes.byteOffset,bytes.byteOffset+bytes.byteLength));return readUnit(Buffer.from(b));}
if(process.argv[1]&&resolve(process.argv[1])===resolve(new URL(import.meta.url).pathname)){
 const root=resolve(process.argv[2]),manifest=JSON.parse(readFileSync(resolve(root,'manifest.json'))),sha=b=>createHash('sha256').update(b).digest('hex');
 const assemblyChecks=[];
 for(const m of manifest.models){const b=readFileSync(resolve(root,m.native)),glb=glbFromNative(readNative(b));if(m.native_kind==='assembly'){
 const expanded=Buffer.from(assemblyNative(b.buffer.slice(b.byteOffset,b.byteOffset+b.byteLength))),expected=readFileSync(resolve(root,m.assembly_expected));
 assert.deepEqual(expanded.subarray(20),expected,'assembly differs from Swift final formation');
 const scene=JSON.parse(b);scene.placements[2].translation[0]+=0.1;
 const fault=Buffer.from(assemblyNative(new TextEncoder().encode(JSON.stringify(scene)).buffer));
 assert.notDeepEqual(fault.subarray(20),expected,'misplaced-unit mutation was accepted');
 assemblyChecks.push({id:m.id,triangles:m.triangles,exact_swift_formation_payload:true,shifted_unit_fault_rejected:true});
 }m.glb='models/' +m.id+'.glb';writeFileSync(resolve(root,m.glb),glb);m.native_sha256=sha(b);m.glb_sha256=sha(glb);m.views=Object.fromEntries(manifest.directions.map(v=>[v,'views/'+m.id+'/'+v+'.png']));}
 writeFileSync(resolve(root,'assembly-verification.json'),JSON.stringify({status:'VERIFIED',assemblies:assemblyChecks,limits:'Only legal units are M3DM; complete formation is an assembly.'},null,2)+'\n');
 writeFileSync(resolve(root,'manifest.json'),JSON.stringify(manifest,null,2)+'\n');
}
