import {readFileSync,writeFileSync} from 'node:fs';
import {resolve} from 'node:path';
const root=resolve(process.argv[2]),m=JSON.parse(readFileSync(resolve(root,'manifest.json')));
const uri=(p,type)=>'data:'+type+';base64,'+readFileSync(resolve(root,p)).toString('base64');
for(const a of m.models){a.native=uri(a.native,'application/octet-stream');a.glb=uri(a.glb,'model/gltf-binary');for(const k in a.views)a.views[k]=uri(a.views[k],'image/png');}
let renderer=readFileSync(resolve(root,'renderer.js'),'utf8').replace("import {assemblyNative} from './scene.js';",readFileSync(resolve(root,'scene.js'),'utf8').replace('export function','function')).replace('export const directions','const directions').replace('export class NativeRenderer','class NativeRenderer');
let html=readFileSync(resolve(root,'viewer.html'),'utf8').replace("import {NativeRenderer} from './renderer.js';",renderer).replace("response=await fetch('manifest.json')",'response=new Response('+JSON.stringify(JSON.stringify(m))+')').replace(/<a id="zip"[^>]*>.*?<\/a>/,'<span>完整ZIP另行下載</span>').replace("$('glb').href=asset.glb;$('native').href=asset.native;","$('glb').href=asset.glb;$('glb').download=asset.id+'.glb';$('native').href=asset.native;$('native').download=asset.id+(asset.native_kind==='assembly'?'.m3dscene.json':'.m3dmodel');");
writeFileSync(resolve(root,'viewer-standalone.html'),html);
