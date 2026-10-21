import {readFileSync,writeFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {createHash} from 'node:crypto';
import {readNative,glbFromNative} from '../station-kit/package.mjs';
const root=resolve(process.argv[2]),manifest=JSON.parse(readFileSync(resolve(root,'manifest.json'))),hash=b=>createHash('sha256').update(b).digest('hex');
for(const record of [...manifest.models,...manifest.components]) {
 const native=readFileSync(resolve(root,record.native)),model=readNative(native),glb=glbFromNative(model);
 record.glb='models/'+record.id+'.glb';writeFileSync(resolve(root,record.glb),glb);
 record.native_sha256=hash(native);record.glb_sha256=hash(glb);
 if(record.category!=='component')record.views=Object.fromEntries(manifest.directions.map(d=>[d,'views/'+record.id+'/'+d+'.png']));
}
writeFileSync(resolve(root,'manifest.json'),JSON.stringify(manifest,null,2)+'\n');
console.log('Packaged '+manifest.models.length+' models and '+manifest.components.length+' separate bodies.');
