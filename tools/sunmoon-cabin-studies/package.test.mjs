import test from 'node:test';import assert from 'node:assert/strict';import {glassGLB,readNative} from './package.mjs';
function fixture(flag){const meta=Buffer.from('{}  '),b=Buffer.alloc(72);b.write('M3DM');b.writeUInt16LE(1,4);b.writeUInt32LE(1,8);b.writeUInt32LE(2,12);meta.copy(b,16);b.writeUInt32LE(flag,20);[[0,0,0],[1,0,0],[0,1,0]].forEach((p,i)=>{p.forEach((x,k)=>b.writeFloatLE(x,24+i*16+k*4));b.writeUInt32LE(0xffaabbcc,36+i*16)});return b}
function json(b){return JSON.parse(b.toString('utf8',20,20+b.readUInt32LE(12)))}
test('glass flag2 produces separate BLEND primitive and stable output',()=>{const b=fixture(2),g=glassGLB(b),j=json(g);assert.deepEqual(glassGLB(b),g);assert.equal(j.meshes[0].primitives[0].material,1);assert.equal(j.materials[1].alphaMode,'BLEND');assert.equal(j.accessors.at(-1).count,3)});
test('plain geometry stays opaque',()=>{const j=json(glassGLB(fixture(0)));assert.equal(j.meshes[0].primitives[0].material,0);assert.equal(j.materials[0].alphaMode,undefined)});
test('truncation and bad magic rejected',()=>{const b=fixture(2);assert.throws(()=>readNative(b.subarray(0,71)));b.write('FAIL');assert.throws(()=>readNative(b))});
test('degenerate triangle rejected',()=>{const b=fixture(2);b.writeFloatLE(0,40);b.writeFloatLE(0,60);assert.throws(()=>readNative(b))});
test('emission creates its own emissive material',()=>{const j=json(glassGLB(fixture(1)));assert.equal(j.meshes[0].primitives[0].material,2);assert.deepEqual(j.materials[2].emissiveFactor,[1,.886,.65])});
test('unknown flags rejected',()=>assert.throws(()=>glassGLB(fixture(8))));
test('reserved header rejected',()=>{const b=fixture(0);b.writeUInt16LE(1,6);assert.throws(()=>glassGLB(b))});
test('combined emissive glass is explicitly unsupported',()=>assert.throws(()=>glassGLB(fixture(3))));
