// The line `pack` writes for a model in the city view's index.json (tools/meshy/meshy.mjs). What the line already
// holds besides the file and the way the model faces (a picture to colour it, `colour`; its baked shadows, `ao`
// and `aoChannel`; `fit`, set by hand for N700ST) is kept: packing a model again replaced the whole line and lost them.
export function indexEntry(previous, file, front) {
  return { ...(previous ?? {}), file, front };
}
