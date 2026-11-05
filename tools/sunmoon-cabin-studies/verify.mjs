import {readFileSync as read,writeFileSync as write} from 'node:fs';
import {resolve} from 'node:path';
import {createHash} from 'node:crypto';
import {readNative,glassGLB} from './package.mjs';
const root=resolve(process.argv[2]),manifest=JSON.parse(read(root+'/manifest.json')),hash=b=>createHash('sha256').update(b).digest('hex');
let triangles=0,glassTriangles=0,emissiveTriangles=0;
for(const m of manifest.models){
 const bytes=read(root+'/'+m.native),model=readNative(bytes),glb=read(root+'/'+m.glb);
 if(model.vertices.length!==m.triangles*3||hash(bytes)!==m.native_sha256||hash(glb)!==m.glb_sha256||!glassGLB(bytes).equals(glb))throw Error('Round-trip or SHA mismatch '+m.id);
 const jlen=glb.readUInt32LE(12),j=JSON.parse(glb.toString('utf8',20,20+jlen)),bin=glb.subarray(28+jlen),start=16+Math.ceil(bytes.readUInt32LE(12)/4)*4,seen=new Set();
 for(const primitive of j.meshes[0].primitives){const a=j.accessors[primitive.indices],bv=j.bufferViews[a.bufferView];if(a.componentType!==5125||primitive.mode!==4)throw Error('indices');for(let i=0;i<a.count;i++){const index=bin.readUInt32LE(bv.byteOffset+i*4),flag=bytes.readUInt32LE(start+Math.floor(index/3)*52);if(seen.has(index)||primitive.material!==((flag&2)?1:(flag&1)?2:0))throw Error('material/duplicate');seen.add(index)}if(primitive.material===1)glassTriangles+=a.count/3;if(primitive.material===2)emissiveTriangles+=a.count/3;}
 if(seen.size!==model.vertices.length)throw Error('missing GLB vertices');
 for(let i=0;i<model.vertices.length;i++){const v=model.vertices[i],p=[v.position[0],v.position[2],-v.position[1]],normal=[v.normal[0],v.normal[2],-v.normal[1]];for(let c=0;c<3;c++){if(bin.readFloatLE(i*12+c*4)!==p[c])throw Error('GLB position');if(Math.abs(bin.readFloatLE(j.bufferViews[1].byteOffset+i*12+c*4)-normal[c])>1e-6)throw Error('GLB normal')}for(let c=0;c<4;c++)if(bin[j.bufferViews[2].byteOffset+i*4+c]!==v.color[c])throw Error('GLB colour');}
 triangles+=m.triangles;
}
const report={status:'VERIFIED',models:manifest.models.length,triangles,glassTriangles,emissiveTriangles,checks:['M3DM / indexed GLB exact reconstruction','all positions, normals, colours, index coverage','native flag2 assigned only to GLB glass material','SHA256'],limits:['Native glass is opaque in current Metal; GLB blending is inspection only.']};write(root+'/geometry-verification.json',JSON.stringify(report,null,2)+'\n');console.log(report);
