// R21-specific probes on the exported native vertices. Run after package.mjs.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {model} from './native.mjs';

const root = resolve(process.argv[2]);
const manifest = JSON.parse(readFileSync(resolve(root,'manifest.json')));
const near = manifest.models.find(m => m.id === 'g12-r21');
const far = manifest.models.find(m => m.id === 'g12-r21-far');
assert(near && far);
assert(far.triangles < near.triangles / 2, 'far needs less than half triangles');
const vertices = model(readFileSync(resolve(root,near.native))).vertices;
const match = (x,z,tol=0.025) => vertices.filter(v => Math.abs(v.position[0]-x)<tol && Math.abs(v.position[2]-z)<tol);
function checkWheelContact(shift=0) {
  for (const x of [-5.65,-4.45,-3.25,3.23,4.43,5.63]) {
    assert(vertices.some(v => Math.abs(v.position[0]-x)<0.025 && Math.abs(v.position[2]+shift)<0.006),
      `wheel at ${x} misses rail plane`);
  }
}
function checkLamps(offset=0) {
  for (const z of [2.96,3.18]) {
    assert(match(6.80+offset,z).length, `long hood centre lamp at ${z} absent`);
  }
}
function checkGlass(shift=0) {
  // The native transform maps builder side ±1.211 to native lateral ±1.211.
  assert(vertices.some(v => Math.abs(v.position[0]+4.18)<0.51 &&
    Math.abs(Math.abs(v.position[1])-1.223-shift)<0.025 &&
    v.position[2]>2.6 && v.position[2]<3.1 && v.color[2]>v.color[0]),
  'cab glazing not exposed at side');
}
function checkDrawGear(shift=0) {
  for (const end of [-1,1]) assert(vertices.some(v =>
    Math.abs(v.position[0]-end*(6.96+shift))<0.16 &&
    Math.abs(v.position[1])<0.28 && v.position[2]>0.5 && v.position[2]<0.9),
    'end draw gear absent');
}
checkWheelContact();checkLamps();checkGlass();checkDrawGear();
assert.throws(() => checkWheelContact(0.10),/misses rail/);
assert.throws(() => checkLamps(0.20),/lamp/);
assert.throws(() => checkGlass(0.20),/glazing/);
assert.throws(() => checkDrawGear(0.40),/draw gear/);
console.log('VERIFIED R21 six wheel contacts, long-end lamp heights, exposed cab glass, two supported draw gears; four shifted counterexamples rejected');
