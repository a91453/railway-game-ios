// The shared station-kit renderer with a night uniform: at night the scene
// keeps a dim blue of its own colours and the triangles flagged as glowing
// show at full strength, so lamps and the pavement they light stand out.
import {readFileSync} from 'node:fs';
export function nightRenderer(){
 const source=readFileSync(new URL('../station-kit/renderer.js',import.meta.url),'utf8');
 const patched=source.replace('precision highp float;in vec3 n,c;in float g;','precision highp float;uniform float night;in vec3 n,c;in float g;')
  .replace('c*(0.8+0.2*sun)+vec3(g*0.025)','mix(c*(0.8+0.2*sun)+vec3(g*0.025),c*vec3(0.26,0.31,0.46)*(0.8+0.3*sun)+c*g*0.95,night)')
  .replace("'radius','aspect','depth'","'radius','aspect','depth','night'").replace('zoom=1,vector','zoom=1,vector,night=0')
  .replace('Object.entries({radius,aspect,depth})','Object.entries({radius,aspect,depth,night})');
 if(!patched.includes('uniform float night')||!patched.includes('g*0.95,night')||!patched.includes("'depth','night'")||!patched.includes('vector,night=0')||!patched.includes('depth,night})'))throw Error('renderer.js changed: the night patch no longer applies');
 return patched;
}
