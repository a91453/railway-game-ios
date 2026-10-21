import {readFileSync,writeFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {createHash} from 'node:crypto';

export function readNative(bytes) {
  if(bytes.toString('ascii',0,4)!=='M3DM'||bytes.readUInt16LE(4)!==1)throw Error('Invalid native model');
  const count=bytes.readUInt32LE(8),size=bytes.readUInt32LE(12),start=16+Math.ceil(size/4)*4;
  if(bytes.length!==start+count*52)throw Error('Invalid native model length');
  const vertices=[];
  for(let i=0;i<count;i++) {
    const p=start+i*52,flags=bytes.readUInt32LE(p);
    const corners=[];
    for(let j=0;j<3;j++) {const k=p+4+j*16;corners.push([bytes.readFloatLE(k),bytes.readFloatLE(k+4),bytes.readFloatLE(k+8),bytes.readUInt32LE(k+12)]);}
    const [a,b,c]=corners,u=b.map((v,k)=>v-a[k]),v=c.map((v,k)=>v-a[k]);
    const n=[u[1]*v[2]-u[2]*v[1],u[2]*v[0]-u[0]*v[2],u[0]*v[1]-u[1]*v[0]],length=Math.hypot(...n);
    if(!length)throw Error('Degenerate native triangle');
    for(const point of corners)vertices.push({position:point.slice(0,3),normal:n.map(x=>x/length),color:[0,8,16,24].map(s=>(point[3]>>>s)&255),glow:flags&1});
  }
  return {vertices,provenance:JSON.parse(bytes.toString('utf8',16,16+size))};
}

export function glbFromNative(model) {
  const count=model.vertices.length,positions=Buffer.alloc(count*12),normals=Buffer.alloc(count*12),colors=Buffer.alloc(count*4),glows=Buffer.alloc(count*4);
  const low=[Infinity,Infinity,Infinity],high=[-Infinity,-Infinity,-Infinity];
  model.vertices.forEach((v,i)=>{
    const p=[v.position[0],v.position[2],-v.position[1]],n=[v.normal[0],v.normal[2],-v.normal[1]];
    for(let c=0;c<3;c++){positions.writeFloatLE(p[c],i*12+c*4);normals.writeFloatLE(n[c],i*12+c*4);low[c]=Math.min(low[c],p[c]);high[c]=Math.max(high[c],p[c]);}
    v.color.forEach((x,c)=>colors[i*4+c]=x);glows.writeFloatLE(v.glow,i*4);
  });
  const chunks=[positions,normals,colors,glows];let offset=0;
  const views=chunks.map(b=>{const v={buffer:0,byteOffset:offset,byteLength:b.length,target:34962};offset+=b.length;return v;});
  const json={asset:{version:'2.0',generator:'Along the Line native scene kit',extras:model.provenance},scene:0,scenes:[{nodes:[0]}],nodes:[{mesh:0}],meshes:[{primitives:[{attributes:{POSITION:0,NORMAL:1,COLOR_0:2,_NATIVE_GLOW:3},material:0,mode:4}]}],materials:[{name:'native-matte',pbrMetallicRoughness:{baseColorFactor:[1,1,1,1],metallicFactor:0,roughnessFactor:1},doubleSided:false}],buffers:[{byteLength:offset}],bufferViews:views,accessors:[{bufferView:0,componentType:5126,count,type:'VEC3',min:low,max:high},{bufferView:1,componentType:5126,count,type:'VEC3'},{bufferView:2,componentType:5121,normalized:true,count,type:'VEC4'},{bufferView:3,componentType:5126,count,type:'SCALAR'}]};
  const j=Buffer.from(JSON.stringify(json)),jp=Buffer.concat([j,Buffer.alloc((4-j.length%4)%4,32)]),binary=Buffer.concat(chunks);
  const header=Buffer.alloc(12);header.writeUInt32LE(0x46546c67);header.writeUInt32LE(2,4);header.writeUInt32LE(28+jp.length+binary.length,8);
  function chunkHeader(size,type){const b=Buffer.alloc(8);b.writeUInt32LE(size);b.writeUInt32LE(type,4);return b;}
  return Buffer.concat([header,chunkHeader(jp.length,0x4e4f534a),jp,chunkHeader(binary.length,0x004e4942),binary]);
}

if(process.argv[1]&&resolve(process.argv[1])===resolve(new URL(import.meta.url).pathname)) {
  const root=resolve(process.argv[2]),manifest=JSON.parse(readFileSync(resolve(root,'manifest.json')));
  const original=JSON.parse(readFileSync(new URL('../../docs/art/generated-2026-10-21-scene-kit/manifest.json',import.meta.url)));
  const concepts=new Map(original.assets.flatMap(sheet=>sheet.frames.map(frame=>[frame.id,{file:'../'+sheet.file,width:sheet.width,height:sheet.height,frame}])));
  for(const record of manifest.models) {
    const native=readFileSync(resolve(root,record.native)),model=readNative(native),glb=glbFromNative(model),file='models/'+record.id+'.glb';
    writeFileSync(resolve(root,file),glb);record.glb=file;record.native_sha256=createHash('sha256').update(native).digest('hex');record.glb_sha256=createHash('sha256').update(glb).digest('hex');
    record.views=Object.fromEntries(manifest.directions.map(d=>[d,'views/'+record.id+'/'+d+'.png']));
    record.view_metrics={};
    record.source_image=concepts.get(record.id);
  }
  writeFileSync(resolve(root,'manifest.json'),JSON.stringify(manifest,null,2)+'\n');
  console.log('Packaged '+manifest.models.length+' native models as GLB; no textures or external buffers.');
}
