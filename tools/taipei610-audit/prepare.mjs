// Package final common-tool native exports; no alternate model geometry.
import {readFileSync,writeFileSync,mkdirSync,copyFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {readNative,glbFromNative} from '../emu900-native/package.mjs';
const root=resolve(process.argv[2]),privateRoot=resolve(process.argv[3]);
const manifest=JSON.parse(readFileSync(resolve(root,'manifest.json')));
manifest.models=manifest.models.filter(m=>m.category!=='comparison');
for(const [id,path] of [
 ['accepted-e500-v3','e500-refresh-2026-10-25/revision-3/models/e500.m3dmodel'],
 ['accepted-emu3000-v5','emu3000-refresh-2026-10-25/revision-5/models/emu3000-ed.m3dmodel']]){
 const target='models/'+id+'.m3dmodel';copyFileSync(resolve(privateRoot,path),resolve(root,target));
 manifest.models.push({id,native:target,category:'comparison'});
}
// Actual captured base fallback. Never relabel this as an earlier 610 model.
const baseline=process.argv[4];
if(baseline){
 const rows=JSON.parse(readFileSync(resolve(baseline,'fingerprints.json'))),rec=rows.find(r=>r.id==='set-wenhu-head');
 const raw=readFileSync(resolve(baseline,rec.payload)),header=Buffer.alloc(20),body=Buffer.alloc(rec.triangles*52);
 header.write('M3DM');header.writeUInt16LE(1,4);header.writeUInt32LE(rec.triangles,8);header.writeUInt32LE(2,12);header.write('{}',16);
 for(let i=0;i<rec.triangles;i++){
  let glow=false;
  for(let j=0;j<3;j++){const source=(i*3+j)*32;raw.copy(body,i*52+4+j*16,source,source+16);glow ||= raw.readFloatLE(source+16)===-2;}
  body.writeUInt32LE(glow?1:0,i*52);
 }
 const native='models/before-operation-wenhu.m3dmodel';writeFileSync(resolve(root,native),Buffer.concat([header,body]));manifest.models.push({id:'before-operation-wenhu',native,category:'comparison',note:'Actual base set-wenhu-head shown by Y/BR shared mapping; NOT a previous independent 610'});
}
manifest.directions=['top','bottom','left','right','front','back','isometric'];
manifest.generator='Map3DTaipei610';manifest.title='台北捷運610 — 四輛展示';
for(const m of manifest.models){
 const model=readNative(readFileSync(resolve(root,m.native)));m.glb='models/'+m.id+'.glb';writeFileSync(resolve(root,m.glb),glbFromNative(model));
 m.name=m.id; m.triangles=model.vertices.length/3;
 for(const [key,fn,initial] of [['minimum',Math.min,Infinity],['maximum',Math.max,-Infinity]])m[key]=[0,1,2].map(i=>model.vertices.reduce((a,v)=>fn(a,v.position[i]),initial));
 m.views=Object.fromEntries(manifest.directions.map(d=>[d,'png/day/'+m.id+'-'+d+'.png']));
}
manifest.model_count=manifest.models.length;
writeFileSync(resolve(root,'manifest.json'),JSON.stringify(manifest,null,2));

let viewer=readFileSync(new URL('../emu900-native/viewer.html',import.meta.url),'utf8').replaceAll('EMU900','台北捷運610').replaceAll('十輛','四輛').replaceAll('六種','四種').replaceAll('emu900-ed','taipei610-a');
viewer=viewer.replace("new NativeRenderer($('canvas'))","new NativeRenderer($('canvas'),manifest.lighting)");
writeFileSync(resolve(root,'viewer.html'),viewer);
