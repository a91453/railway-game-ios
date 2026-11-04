import {readNative,glbFromNative} from '../station-kit/package.mjs';
export {readNative};
export function glassGLB(bytes){
 if(bytes.length<16||bytes.readUInt16LE(6)!==0)throw Error('Invalid native header');
 const n=bytes.readUInt32LE(8),s=16+Math.ceil(bytes.readUInt32LE(12)/4)*4;if(n<1||n>15000||s+n*52!==bytes.length)throw Error('Invalid native size');
 for(let i=0;i<n;i++)if(bytes.readUInt32LE(s+i*52)&~2)throw Error('Only plain and glass triangles supported in this pack');
 const original=glbFromNative(readNative(bytes)),len=original.readUInt32LE(12),j=JSON.parse(original.toString('utf8',20,20+len)),bin=original.subarray(28+len),start=16+Math.ceil(bytes.readUInt32LE(12)/4)*4,groups=[[],[]];
 for(let i=0;i<bytes.readUInt32LE(8);i++)groups[(bytes.readUInt32LE(start+i*52)&2)?1:0].push(i*3,i*3+1,i*3+2);
 j.materials=[{name:'matte-vertex-colour',pbrMetallicRoughness:{metallicFactor:0,roughnessFactor:1},doubleSided:false},{name:'inspection-glass-native-flag2',pbrMetallicRoughness:{baseColorFactor:[1,1,1,.25],metallicFactor:0,roughnessFactor:.25},alphaMode:'BLEND',doubleSided:false}];j.asset.generator='Maokong native studies / indexed glass GLB';j.asset.extras.glassLimitation='GLB blending for inspection; current native Metal trainGlass remains opaque.';
 const attributes=j.meshes[0].primitives[0].attributes;j.meshes[0].primitives=[];let offset=bin.length;const chunks=[bin];
 for(let material=0;material<2;material++){const group=groups[material];if(!group.length)continue;const b=Buffer.alloc(group.length*4);group.forEach((n,i)=>b.writeUInt32LE(n,i*4));const view=j.bufferViews.length,index=j.accessors.length;j.bufferViews.push({buffer:0,byteOffset:offset,byteLength:b.length,target:34963});j.accessors.push({bufferView:view,componentType:5125,count:group.length,type:'SCALAR'});j.meshes[0].primitives.push({attributes,indices:index,material,mode:4});chunks.push(b);offset+=b.length}
 j.buffers[0].byteLength=offset;const text=Buffer.from(JSON.stringify(j)),json=Buffer.concat([text,Buffer.alloc((4-text.length%4)%4,32)]),binary=Buffer.concat(chunks),out=Buffer.alloc(28+json.length+binary.length);out.writeUInt32LE(0x46546c67);out.writeUInt32LE(2,4);out.writeUInt32LE(out.length,8);out.writeUInt32LE(json.length,12);out.writeUInt32LE(0x4e4f534a,16);json.copy(out,20);out.writeUInt32LE(binary.length,20+json.length);out.writeUInt32LE(0x004e4942,24+json.length);binary.copy(out,28+json.length);return out;
}
