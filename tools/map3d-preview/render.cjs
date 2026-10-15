// usage: node render.cjs <dir with index.html, demo.*, Map3DSurfaces.png> <out prefix> view[,view...]
const { chromium } = require('playwright');
const fs = require('fs'), path = require('path');
(async () => {
  const [dir, out, views] = process.argv.slice(2);
  const browser = await chromium.launch({ args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  const page = await browser.newPage({ viewport: { width: 1600, height: 900 } });
  page.on('console', m => console.log('console:', m.text()));
  page.on('pageerror', e => console.log('pageerror:', e.message));
  await page.route('http://local/**', route => {
    const file = path.join(dir, new URL(route.request().url()).pathname);
    route.fulfill({ path: file });
  });
  await page.goto('http://local/index.html');
  for (const view of views.split(',')) {
    for (const [textured, shadows, tag] of [[true, false, 'textured'], [true, true, 'shadows']]) {
      const err = await page.evaluate(([v, t, s]) => window.render(v, t, s), [view, textured, shadows]);
      await page.locator('#c').screenshot({ path: `${out}-${view}-${tag}.png` });
      console.log(view, textured, 'gl error', err);
    }
  }
  await browser.close();
})();
