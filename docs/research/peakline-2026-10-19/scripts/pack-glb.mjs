// .gltf + .bin -> .glb with @gltf-transform/core 4.5.1 (scratch experiment)
import { createRequire } from 'node:module';
const require = createRequire(process.env.GLTF_MODULES + '/');
const { NodeIO } = require('@gltf-transform/core');
const { ALL_EXTENSIONS } = require('@gltf-transform/extensions');
const io = new NodeIO().registerExtensions(ALL_EXTENSIONS);
const doc = await io.read(process.argv[2]);
const root = doc.getRoot(), main = root.listBuffers()[0];
for (const a of root.listAccessors()) a.setBuffer(main);
for (const b of root.listBuffers().slice(1)) b.dispose();
main.setURI('');
await io.write(process.argv[3], doc);
