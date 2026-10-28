// Produce a self-contained viewer; verify direct file launch separately.
import {readFileSync,writeFileSync} from 'node:fs';
import {resolve,dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
const root=resolve(process.argv[2]),source=dirname(fileURLToPath(import.meta.url));
const manifest=JSON.parse(readFileSync(resolve(root,'manifest.json')));
const uri=(path,type)=>'data:'+type+';base64,'+readFileSync(resolve(root,path)).toString('base64');
for(const m of manifest.models){
 m.native=uri(m.native,'application/octet-stream');m.glb=uri(m.glb,'model/gltf-binary');
 for(const [view,path] of Object.entries(m.views))m.views[view]=uri(path,'image/png');
}
const renderer=readFileSync(resolve(root,'renderer.js'),'utf8').replace('export const directions','const directions').replace('export class NativeRenderer','class NativeRenderer');
let html=readFileSync(resolve(source,'viewer.html'),'utf8');
html=html.replace("import {NativeRenderer} from './renderer.js';",renderer)
 .replace("response=await fetch('manifest.json')",'response=new Response('+JSON.stringify(JSON.stringify(manifest))+')')
 .replace(/<a id="zip"[^>]*>.*?<\/a>/,'')
 .replace("$('glb').href=asset.glb;$('native').href=asset.native;","$('glb').href=asset.glb;$('glb').download=asset.id+'.glb';$('native').href=asset.native;$('native').download=asset.id+(asset.native_kind==='assembly'?'.m3dscene.json':'.m3dmodel');");
writeFileSync(resolve(root,'viewer-standalone.html'),html);
console.log('Created self-contained offline viewer; native / GLB / PNG downloads embedded.');
