// Decision 352: draws RailwayGameApp/Resources/Map3D/Map3DSigns.png from
// atlas.html and words.json in headless Chromium (the session's own;
// Playwright, Apache-2.0, only on the developer's machine).
//
//   node tools/map3d-signs/render.cjs <Noto Sans TC folder> <out.png>
//
// The font folder is @fontsource/noto-sans-tc 5.1.0's package (SIL Open
// Font License 1.1), unpacked: `npm pack @fontsource/noto-sans-tc@5.1.0`.
// Only its pictures of the words go into the atlas, not the font.
const { chromium } = require('playwright');
const fs = require('fs'), path = require('path');
(async () => {
  const [fonts, out] = process.argv.slice(2);
  const here = __dirname;
  const words = JSON.parse(fs.readFileSync(path.join(here, 'words.json'), 'utf8'));
  const browser = await chromium.launch();
  const page = await browser.newPage();
  page.on('pageerror', e => console.log('pageerror:', e.message));
  await page.route('http://local/**', route => {
    const name = new URL(route.request().url()).pathname;
    const file = name.startsWith('/font/') ? path.join(fonts, name.slice(6)) : path.join(here, name);
    route.fulfill({ path: file });
  });
  await page.goto('http://local/atlas.html');
  const url = await page.evaluate(w => window.drawAtlas(w), words);
  fs.writeFileSync(out, Buffer.from(url.split(',')[1], 'base64'));
  await browser.close();
  console.log('wrote', out);
})();
