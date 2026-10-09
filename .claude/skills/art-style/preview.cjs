// Renders SVGs at the sizes the app shows them, on the app's light and dark
// panels and on the map's light and dark ground, into one PNG to look at and
// to send the owner. Each row ends with two checks at the second size: blurred
// (does the silhouette alone read at a glance?) and in greys (does anything
// rely on hue alone?). Uses the Chromium that the cloud environment has
// (Playwright); nothing is downloaded.
//
//   NODE_PATH="$(npm root -g)" node .claude/skills/art-style/preview.cjs \
//     --out /path/in/scratchpad/sheet.png [--sizes 120,64,44,28] \
//     [--template] [--head] [--no-checks] a.svg b.svg ...
//
// --template  one-colour template glyphs: drawn in the text colour of each
//             panel (#262C57 light, #ECEEF6 dark), as the app tints them.
// --head      character art: below 60 points, the head alone, scaled 1.45
//             from (44%, 30%), as StationMasterAvatar does.
// --no-checks leave out the blurred and grey checks.
// Each file gets a row, labelled with its file name.
const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');

const args = process.argv.slice(2);
let out = null, sizes = [120, 64, 44, 28], template = false, head = false, checks = true;
const files = [];
for (let i = 0; i < args.length; i++) {
  const a = args[i];
  if (a === '--out') out = args[++i];
  else if (a === '--sizes') sizes = args[++i].split(',').map(Number);
  else if (a === '--template') template = true;
  else if (a === '--head') head = true;
  else if (a === '--no-checks') checks = false;
  else files.push(a);
}
if (!out || files.length === 0) {
  console.error('usage: preview.cjs --out sheet.png [--sizes 120,64,44,28] [--template] [--head] file.svg ...');
  process.exit(2);
}

// Theme.panel and Palette.land in each appearance, with the ink drawn on them.
const panels = [
  { name: 'panel, light', background: '#FFFFFF', ink: '#262C57' },
  { name: 'panel, dark', background: '#30376A', ink: '#ECEEF6' },
  { name: 'map, light', background: '#ECEEF6', ink: '#262C57' },
  { name: 'map, dark', background: '#262C57', ink: '#ECEEF6' },
];

function cell(svg, size, ink, filter = '') {
  if (template) {
    const tinted = svg
      .replace(/fill="#0{3}(0{3})?"/gi, 'fill="currentColor"')
      .replace(/<svg([^>]*?)\swidth="[^"]*"\sheight="[^"]*"/, '<svg$1')
      .replace('<svg', `<svg width="${size}" height="${size}"`);
    return `<div style="color:${ink};width:${size}px;height:${size}px;filter:${filter || 'none'}">${tinted}</div>`;
  }
  const uri = 'data:image/svg+xml;base64,' + Buffer.from(svg).toString('base64');
  const crop = head && size < 60 ? 'transform:scale(1.45);transform-origin:44% 30%;' : '';
  return `<div style="width:${size}px;height:${size}px;border-radius:50%;overflow:hidden;flex:none;filter:${filter || 'none'}">` +
    `<img src="${uri}" width="${size}" height="${size}" style="display:block;${crop}"></div>`;
}

const rows = files.map((file) => {
  const svg = fs.readFileSync(file, 'utf8');
  const test = sizes[Math.min(1, sizes.length - 1)];
  const label = (text) => `<div style="font-size:10px;opacity:.7">${text}</div>`;
  const sets = panels.map((p) =>
    `<div style="display:flex;gap:14px;align-items:flex-end;padding:10px 12px;border-radius:14px;background:${p.background};color:${p.ink}">` +
    sizes.map((s) => `<div style="text-align:center">${cell(svg, s, p.ink)}${label(s)}</div>`).join('') +
    (checks
      ? `<div style="text-align:center">${cell(svg, test, p.ink, `blur(${Math.max(1, test / 40)}px)`)}${label('blur')}</div>` +
        `<div style="text-align:center">${cell(svg, test, p.ink, 'grayscale(1)')}${label('grey')}</div>`
      : '') +
    `${label(p.name)}</div>`).join('');
  return `<div style="display:flex;gap:12px;align-items:center;margin-bottom:10px">` +
    `<div style="width:200px;font-size:13px;font-weight:600;overflow-wrap:anywhere">${path.basename(file)}</div>` +
    `<div style="display:grid;grid-template-columns:auto auto;gap:8px">${sets}</div></div>`;
});

const html = '<!doctype html><html><head><meta charset="utf-8"></head>' +
  '<body style="margin:0;padding:14px;background:#ECEEF6;color:#262C57;font-family:-apple-system,sans-serif">' +
  rows.join('') + '</body></html>';

(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 400, height: 200 }, deviceScaleFactor: 2 });
  await page.setContent(html);
  const size = await page.evaluate(() => ({ width: document.body.scrollWidth, height: document.body.scrollHeight }));
  await page.setViewportSize({ width: Math.ceil(size.width), height: Math.ceil(size.height) });
  await page.screenshot({ path: out, fullPage: true });
  await browser.close();
  console.log(out);
})();
