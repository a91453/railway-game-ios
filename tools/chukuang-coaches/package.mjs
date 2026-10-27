import {readFileSync,writeFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {createHash} from 'node:crypto';
import {assemblyNative} from './scene.js';
import {readNative as readUnit,glbFromNative} from '../station-kit/package.mjs';
export {glbFromNative};
export function readNative(bytes){const b=assemblyNative(bytes.buffer.slice(bytes.byteOffset,bytes.byteOffset+bytes.byteLength));return readUnit(Buffer.from(b));}
if(process.argv[1]&&resolve(process.argv[1])===resolve(new URL(import.meta.url).pathname)){
 const root=resolve(process.argv[2]),manifest=JSON.parse(readFileSync(resolve(root,'manifest.json'))),sha=b=>createHash('sha256').update(b).digest('hex');
 for(const m of manifest.models){const b=readFileSync(resolve(root,m.native)),parsed=readNative(b),glb=glbFromNative(parsed);m.triangles=parsed.vertices.length/3;m.minimum=[0,1,2].map(i=>parsed.vertices.reduce((a,v)=>Math.min(a,v.position[i]),Infinity));m.maximum=[0,1,2].map(i=>parsed.vertices.reduce((a,v)=>Math.max(a,v.position[i]),-Infinity));m.glb='models/'+m.id+'.glb';writeFileSync(resolve(root,m.glb),glb);m.native_sha256=sha(b);m.glb_sha256=sha(glb);m.views=Object.fromEntries(manifest.directions.map(v=>[v,'views/'+m.id+'/'+v+'.png']));}
 writeFileSync(resolve(root,'manifest.json'),JSON.stringify(manifest,null,2)+'\n');
}
