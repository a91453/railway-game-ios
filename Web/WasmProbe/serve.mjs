import http from 'node:http';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const shim = '/node_modules/@bjorn3/browser_wasi_shim/dist/';
const allowed = new Set(['/index.html', '/worker.mjs', '/.artifacts/probe.wasm']);
export async function startServer(port = 8787) {
  const server = http.createServer(async (request, response) => {
    try {
      let name = new URL(request.url, 'http://localhost').pathname;
      if (name === '/') name = '/index.html';
      if (!allowed.has(name) && !(name.startsWith(shim) && /^[a-z_]+\.js$/.test(name.slice(shim.length)))) {
        response.writeHead(404).end();
        return;
      }
      const bytes = await readFile(path.join(here, name));
      const type = name.endsWith('.wasm') ? 'application/wasm' : name.endsWith('.html') ? 'text/html; charset=utf-8' : 'text/javascript; charset=utf-8';
      response.writeHead(200, { 'Content-Type': type, 'Cache-Control': 'no-store' }).end(bytes);
    } catch {
      response.writeHead(404).end();
    }
  });
  await new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(port, '127.0.0.1', resolve);
  });
  return server;
}
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const server = await startServer(Number(process.env.PORT || 8787));
  console.log(`Probe: http://127.0.0.1:${server.address().port}`);
}
