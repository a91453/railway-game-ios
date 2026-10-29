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
  for (const z of [2.90,3.12]) {
    assert(match(-6.73-offset,z).length, `short hood centre lamp at ${z} absent`);
  }
}
function checkGlass(shift=0) {
  // The native transform maps builder side ±1.211 to native lateral ±1.211.
  assert(vertices.some(v => Math.abs(v.position[0]+4.18)<0.51 &&
    Math.abs(Math.abs(v.position[1])-1.257-shift)<0.025 &&
    v.position[2]>2.6 && v.position[2]<3.1 && v.color[2]>v.color[0]),
  'cab glazing not exposed at side');
}
function checkDrawGear(shift=0) {
  for (const end of [-1,1]) assert(vertices.some(v =>
    Math.abs(v.position[0]-end*(6.96+shift))<0.16 &&
    Math.abs(v.position[1])<0.28 && v.position[2]>0.5 && v.position[2]<0.9),
    'end draw gear absent');
}
function checkShortEndV(shift=0) {
  // Occlusion bakes a darker copy of the original warm white into the pack.
  const white=v => v.color[2]>125 && v.color[0]-v.color[2]<35;
  for (const [lateral,height] of [[0,1.50],[0.94,2.10]]) {
    assert(vertices.some(v => v.position[0]<-6.67 && v.position[0]>-6.70 &&
      Math.abs(Math.abs(v.position[1])-lateral)<0.08 &&
      Math.abs(v.position[2]-height-shift)<0.07 && white(v)),
    'short-end white V misses shell-band junction');
  }
}
function checkFront(bandShift=0,railShift=0) {
  const pale=v => v.color[2]>120 && v.color[0]-v.color[2]<50;
  assert(vertices.some(v => v.position[0]>6.70 && v.position[0]<6.75 &&
    Math.abs(v.position[2]-1.24-bandShift)<0.02 && pale(v)),
  'long-end white band does not meet low front face');
  assert(vertices.some(v => v.position[0]>6.88 && v.position[0]<6.91 &&
    Math.abs(v.position[1])<0.05 && v.position[2]>1.19 &&
    v.color[1]>110 && v.color[2]<80),
  'yellow pilot V does not start at top centre');
  assert(vertices.some(v => v.position[0]>6.90 &&
    Math.abs(Math.abs(v.position[1])-1.32-railShift)<0.05 &&
    Math.abs(v.position[2]-1.92)<0.04 && pale(v)),
  'front handrail misses supported outside post');
}
checkWheelContact();checkLamps();checkGlass();checkDrawGear();checkShortEndV();checkFront();
assert.throws(() => checkWheelContact(0.10),/misses rail/);
assert.throws(() => checkLamps(0.20),/lamp/);
assert.throws(() => checkGlass(0.20),/glazing/);
assert.throws(() => checkDrawGear(0.40),/draw gear/);
assert.throws(() => checkShortEndV(0.25),/white V/);
assert.throws(() => checkFront(0.25),/white band/);
assert.throws(() => checkFront(0,0.25),/front handrail/);
console.log('VERIFIED R21 six wheel contacts, both-end lamp heights, exposed cab glass, two supported draw gears, short-end V, low long-end band, yellow pilot V and supported front rail; seven shifted counterexamples rejected');
