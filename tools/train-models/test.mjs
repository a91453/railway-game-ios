import {test} from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync, mkdirSync, writeFileSync, readFileSync, rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {execFileSync} from 'node:child_process';
import {unit, model, expanded, bounds} from './native.mjs';
import {assemble} from './assemble.mjs';
import {audit, topology} from './audit.mjs';

function tetra() {
  const points = [[0,0,0], [1,0,0], [0,1,0], [0,0,1]], faces = [[0,2,1], [0,1,3], [0,3,2], [1,2,3]];
  const b = Buffer.alloc(20 + 4*52); b.write('M3DM'); b.writeUInt16LE(1,4); b.writeUInt32LE(4,8); b.writeUInt32LE(2,12); b.write('{}',16);
  faces.forEach((face,i) => { b.writeUInt32LE(i % 2,20+i*52); face.forEach((p,j) => { const at=24+i*52+j*16; points[p].forEach((v,k)=>b.writeFloatLE(v,at+k*4)); b.writeUInt32LE(0xffddeeff,at+12); }); });
  return b;
}
function fixture(t) {
  const root = mkdtempSync(join(tmpdir(), 'train-kit-')); t.after(() => rmSync(root,{recursive:true,force:true})); mkdirSync(join(root,'models'));
  const bytes=tetra(); writeFileSync(join(root,'models/a.m3dmodel'),bytes);
  const manifest={models:[{id:'a',native:'models/a.m3dmodel',triangles:4,...bounds(unit(bytes).vertices)}],sets:[],lighting:{}};
  writeFileSync(join(root,'manifest.json'),JSON.stringify(manifest)); return root;
}
const spec = {assemblies:[{id:'pair',placements:[{unit:'a',translation:[10,0,0]}, {unit:'a',translation:[-10,0,0],rotation_degrees:180}]}]};
test('generic assembly preserves flags and colours, rotates tail, embeds only referenced units', t => {
  const root=fixture(t); assemble(root,spec);
  const bytes=readFileSync(join(root,'models/pair.m3dscene.json')), scene=JSON.parse(bytes), parsed=model(bytes);
  assert.deepEqual(Object.keys(scene.units),['a']); assert.equal(parsed.vertices.length,24);
  assert.deepEqual(bounds(parsed.vertices),{minimum:[-11,-1,0],maximum:[11,1,1]});
  assert(parsed.vertices.every(v=>v.color.join(',')==='255,238,221,255'));
  assert.equal(expanded(bytes).readUInt32LE(20),0); assert.equal(expanded(bytes).readUInt32LE(20+52),1);
  assert.deepEqual(readFileSync(join(root,'models/pair.triangles.bin')),expanded(bytes).subarray(20));
});
test('reject invalid native length, nonfinite, zero/oversized units and unsupported header', () => {
  assert.throws(()=>unit(tetra().subarray(0,40)));
  for(const [offset,value] of [[6,1],[8,15001],[8,0]]){const b=tetra();if(offset===6)b.writeUInt16LE(value,offset);else b.writeUInt32LE(value,offset);assert.throws(()=>unit(b));}
  const b=tetra(); b.writeFloatLE(NaN,24); assert.throws(()=>unit(b));
});
test('reject missing unit, unsupported rotation/scale, NaN, empty or duplicate assembly', t => {
  for(const change of [p=>p.unit='missing', p=>p.rotation_degrees=90,p=>p.scale_x=2,p=>p.translation=[NaN,0,0]]){
    const root=fixture(t), bad=structuredClone(spec); change(bad.assemblies[0].placements[0]); assert.throws(()=>assemble(root,bad));
  }
  const root=fixture(t); assert.throws(()=>assemble(root,{assemblies:[]}));
  assemble(root,spec); assert.throws(()=>assemble(root,spec));
  const bad=JSON.parse(readFileSync(join(root,'models/pair.m3dscene.json')));bad.units.unused=bad.units.a;
  assert.throws(()=>expanded(Buffer.from(JSON.stringify(bad))),/Unused/);
});
test('GLB packaging, closure, mutations and assembly payload all checked on final files', t => {
  const root=fixture(t);assemble(root,spec);
  execFileSync(process.execPath,[new URL('./package.mjs',import.meta.url).pathname,root]);
  assert.equal(audit(root).models.length,2);
  const glb=join(root,'models/a.glb'), damaged=readFileSync(glb); damaged[damaged.length-1]^=1;writeFileSync(glb,damaged);
  assert.throws(()=>audit(root),/GLB differs/);
  const vertices=unit(tetra()).vertices;assert.throws(()=>topology(vertices.slice(3)));
  assert.throws(()=>topology([vertices[1],vertices[0],vertices[2],...vertices.slice(3)]));
});
