// The Khronos glTF-Validator (`gltf-validator`, Apache-2.0, pinned in
// package.json) on a GLB before it is converted
// (docs/research/GAME_AI_TOOLS_2026-10-15.md §6.3): a model that breaks the
// glTF spec is refused here, before its triangles are read. The game's own
// limits (the triangle budget, eight colours, the provenance) stay with the
// converter and Map3DModelFile.
import validator from 'gltf-validator';

export async function validateGlb(bytes, uri = 'model.glb') {
  const report = await validator.validateBytes(new Uint8Array(bytes), {
    uri,
    maxIssues: 100,
    // A GLB for the game carries everything in itself.
    externalResourceFunction: () => Promise.reject(new Error('external resources are not read')),
  });
  const { numErrors, numWarnings, numInfos, messages } = report.issues;
  if (numErrors > 0) {
    const errors = messages.filter(message => message.severity === 0).slice(0, 5)
      .map(message => `${message.code}${message.pointer ? ` at ${message.pointer}` : ''}`);
    throw new Error(`glTF-Validator: ${numErrors} error${numErrors === 1 ? '' : 's'} in ${uri}: ${errors.join(', ')}`);
  }
  return { warnings: numWarnings, infos: numInfos };
}
