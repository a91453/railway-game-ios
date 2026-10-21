// usage: node diff.cjs <before.png> <after.png> <diff.png>
// The changed pixels between two preview pictures of the same view
// (GAME_AI_TOOLS §6.3): pixelmatch (pixelmatch.mjs, ISC, copied unchanged
// from pixelmatch 7.2.0; its licence beside it) run in the headless
// Chromium render.cjs uses, the PNGs decoded by its canvas. Writes the
// difference picture and prints how many pixels differ. Evidence for a
// review, not a gate.
const { chromium } = require('playwright');
const fs = require('fs'), path = require('path');
(async () => {
  const [before, after, out] = process.argv.slice(2);
  const files = { '/before.png': before, '/after.png': after, '/pixelmatch.mjs': path.join(__dirname, 'pixelmatch.mjs') };
  const browser = await chromium.launch();
  const page = await browser.newPage();
  page.on('pageerror', e => console.log('pageerror:', e.message));
  await page.route('http://local/**', route => {
    const name = new URL(route.request().url()).pathname;
    if (!files[name]) return route.fulfill({ status: 200, contentType: 'text/html', body: '<!doctype html><title>diff</title>' });
    route.fulfill({ path: path.resolve(files[name]), contentType: name.endsWith('.mjs') ? 'text/javascript' : 'image/png' });
  });
  await page.goto('http://local/');
  const result = await page.evaluate(async () => {
    const { default: pixelmatch } = await import('/pixelmatch.mjs');
    const pixels = async (url) => {
      const image = new Image();
      image.src = url;
      await image.decode();
      const canvas = new OffscreenCanvas(image.width, image.height);
      const context = canvas.getContext('2d');
      context.drawImage(image, 0, 0);
      return context.getImageData(0, 0, image.width, image.height);
    };
    const [a, b] = [await pixels('/before.png'), await pixels('/after.png')];
    if (a.width !== b.width || a.height !== b.height) return { error: `sizes differ: ${a.width}×${a.height}, ${b.width}×${b.height}` };
    const diff = new ImageData(a.width, a.height);
    const changed = pixelmatch(a.data, b.data, diff.data, a.width, a.height, { threshold: 0.1 });
    const canvas = new OffscreenCanvas(a.width, a.height);
    canvas.getContext('2d').putImageData(diff, 0, 0);
    const bytes = new Uint8Array(await (await canvas.convertToBlob({ type: 'image/png' })).arrayBuffer());
    let binary = '';
    for (let i = 0; i < bytes.length; i += 0x8000) binary += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
    return { changed, total: a.width * a.height, png: btoa(binary) };
  });
  await browser.close();
  if (result.error) { console.error(result.error); process.exit(1); }
  fs.writeFileSync(out, Buffer.from(result.png, 'base64'));
  console.log(`${result.changed} of ${result.total} pixels differ (${(100 * result.changed / result.total).toFixed(2)}%)`);
})();
