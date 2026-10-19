import { readFileSync } from 'node:fs';
import { readGlb, accessor, scenePrimitives, applyMatrix } from '../../../../tools/glb-to-m3dmodel/glb.mjs';
const g = readGlb(readFileSync(process.argv[2])); const acc={};
for (const {primitive,matrix} of scenePrimitives(g)) { const m=g.json.materials[primitive.material]?.name; const pos=accessor(g,primitive.attributes.POSITION);
 for (const p of pos){const q=applyMatrix(matrix,p); (acc[m]??=[0,0])[0]+=q[2]; acc[m][1]++;} }
for (const [k,[s,n]] of Object.entries(acc)) console.log(k, (s/n).toFixed(2), n);
