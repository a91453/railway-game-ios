import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {readNative,glbFromNative} from './package.mjs';

const fixture=readFileSync(new URL('../glb-to-m3dmodel/fixtures/static.m3dmodel',import.meta.url));
function gltf(bytes){const size=bytes.readUInt32LE(12);return{json:JSON.parse(bytes.toString('utf8',20,20+size)),binary:bytes.subarray(28+size)};}

test('GLB preserves native positions after the declared z-up to y-up rotation',()=>{
 const model=readNative(fixture),bytes=glbFromNative(model),{json,binary}=gltf(bytes);
 assert.equal(bytes.readUInt32LE(0),0x46546c67);assert.equal(bytes.readUInt32LE(4),2);assert.equal(bytes.readUInt32LE(8),bytes.length);
 assert.equal(json.accessors[0].count,model.vertices.length);
 const first=model.vertices[0];
 const position=[0,4,8].map(o=>binary.readFloatLE(o));
 assert.deepEqual(position,[first.position[0],first.position[2],-first.position[1]]);
 assert.equal(json.materials[0].pbrMetallicRoughness.roughnessFactor,1);
 assert.equal(json.materials[0].doubleSided,false);
});

test('vertex colors, glow markers and source provenance survive export without textures',()=>{
 const model=readNative(fixture),{json,binary}=gltf(glbFromNative(model));
 assert.deepEqual(json.asset.extras,model.provenance);
 const colorOffset=json.bufferViews[2].byteOffset,glowOffset=json.bufferViews[3].byteOffset;
 for(let i=0;i<model.vertices.length;i++){
  assert.deepEqual([...binary.subarray(colorOffset+i*4,colorOffset+i*4+4)],model.vertices[i].color);
  assert.equal(binary.readFloatLE(glowOffset+i*4),model.vertices[i].glow);
 }
 assert.equal(json.images,undefined);assert.equal(json.textures,undefined);assert.equal(json.buffers.length,1);assert.equal(json.buffers[0].uri,undefined);
});

test('all accessor ranges fit in the single embedded buffer and repeat export is identical',()=>{
 const model=readNative(fixture),a=glbFromNative(model),b=glbFromNative(model);assert.deepEqual(a,b);
 const {json,binary}=gltf(a);assert.equal(binary.length,json.buffers[0].byteLength);
 for(const v of json.bufferViews){assert.equal(v.byteOffset%4,0);assert(v.byteOffset+v.byteLength<=binary.length);}
});

test('truncated or foreign inputs are rejected before producing a model',()=>{
 assert.throws(()=>readNative(fixture.subarray(0,fixture.length-1)),/length/);
 const foreign=Buffer.from(fixture);foreign.write('XXXX');assert.throws(()=>readNative(foreign),/Invalid native/);
});
