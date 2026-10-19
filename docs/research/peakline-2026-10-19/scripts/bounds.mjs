import { readFileSync } from 'node:fs';
import { readGlb, accessor, scenePrimitives, applyMatrix } from '../../../../tools/glb-to-m3dmodel/glb.mjs';
const g = readGlb(readFileSync(process.argv[2]));
const min=[1e9,1e9,1e9],max=[-1e9,-1e9,-1e9]; let t=0;
for (const {primitive,matrix} of scenePrimitives(g)) { const pos=accessor(g,primitive.attributes.POSITION);
 for (const p of pos){const q=applyMatrix(matrix,p); q.forEach((v,i)=>{min[i]=Math.min(min[i],v);max[i]=Math.max(max[i],v);});}
 t+= (primitive.indices!==undefined? g.json.accessors[primitive.indices].count: pos.length)/3; }
console.log(JSON.stringify({min:min.map(v=>+v.toFixed(3)),max:max.map(v=>+v.toFixed(3)),triangles:t, materials:(g.json.materials||[]).map(m=>m.name+':'+JSON.stringify(m.pbrMetallicRoughness?.baseColorFactor?.map(x=>+x.toFixed(2))))}));
