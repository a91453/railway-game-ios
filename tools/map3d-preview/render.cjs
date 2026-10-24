// usage: node render.cjs <dir with index.html, demo.*, Map3DSurfaces.png> <out prefix> view[,view...]
const { chromium } = require('playwright');
const fs = require('fs'), path = require('path'), http = require('http');
(async () => {
  const [dir, out, views] = process.argv.slice(2);
  const browser = await chromium.launch({ args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  const page = await browser.newPage({ viewport: { width: 1600, height: 900 } });
  page.on('console', m => console.log('console:', m.text()));
  page.on('pageerror', e => console.log('pageerror:', e.message));
  // A local server, not page.route: route.fulfill sends a file through
  // the DevTools pipe, which closes on one over 100 MB (a big scene's
  // vertices).
  const server = http.createServer((request, response) => {
    const file = path.join(dir, path.normalize(new URL(request.url, 'http://local').pathname));
    if (!file.startsWith(dir) || !fs.existsSync(file)) { response.writeHead(404); response.end(); return; }
    response.writeHead(200);
    fs.createReadStream(file).pipe(response);
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  await page.goto(`http://127.0.0.1:${server.address().port}/index.html`);
  for (const view of views.split(',')) {
    for (const [textured, shadows, tag] of [[true, false, 'textured'], [true, true, 'shadows']]) {
      const err = await page.evaluate(([v, t, s]) => window.render(v, t, s), [view, textured, shadows]);
      await page.locator('#c').screenshot({ path: `${out}-${view}-${tag}.png` });
      console.log(view, textured, 'gl error', err);
    }
  }
  await browser.close();
  server.close();
})();
