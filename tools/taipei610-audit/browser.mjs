import {createServer} from 'node:http';
import {readFileSync,writeFileSync} from 'node:fs';
import {resolve,extname} from 'node:path';
import {createRequire} from 'node:module';
import assert from 'node:assert/strict';
const {chromium}=createRequire('/opt/codex/cua_node/lib/node_modules/')('playwright');
const root=resolve(process.argv[2]),manifest=JSON.parse(readFileSync(resolve(root,'manifest.json')));
const server=createServer((q,r)=>{try{const p=resolve(root,'.'+decodeURIComponent(q.url.split('?')[0]));if(!p.startsWith(root+'/'))throw Error();r.setHeader('Content-Type',({'.html':'text/html','.js':'text/javascript','.json':'application/json','.png':'image/png'})[extname(p)]||'application/octet-stream');r.end(readFileSync(p));}catch{r.statusCode=404;r.end();}});
await new Promise(ok=>server.listen(0,'127.0.0.1',ok));const base='http://127.0.0.1:'+server.address().port;
const browser=await chromium.launch({executablePath:'/usr/bin/chromium',args:['--no-sandbox','--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader']});
const page=await browser.newPage({acceptDownloads:true});const errors=[];page.on('pageerror',e=>errors.push(e.message));
const downloads=[];
async function download(selector,expected){const d=page.waitForEvent('download');await page.click(selector);const item=await d;const bytes=readFileSync(await item.path());if(expected)assert(bytes.equals(expected),selector+' bytes');else assert(bytes.subarray(1,4).toString()==='PNG','downloaded PNG');downloads.push({selector,bytes:bytes.length});}
for(const route of ['viewer.html','viewer-standalone.html']){
 await page.context().setOffline(false);await page.goto(base+'/'+route);await page.waitForFunction(()=>window.currentAsset?.id==='taipei610-a');
 if(route.includes('standalone')) await page.context().setOffline(true);
 for(const m of manifest.models){await page.evaluate(id=>window.loadAsset(id),m.id);for(const view of manifest.directions)await page.click('[data-view="'+view+'"]');
  await download('#native',readFileSync(resolve(root,m.native)));await download('#glb',readFileSync(resolve(root,m.glb)));
 }
 await download('#png');
 const before=await page.locator('canvas').evaluate(c=>c.toDataURL());await page.locator('#zoom').fill('1.45');await page.locator('#zoom').dispatchEvent('input');assert.notEqual(await page.locator('canvas').evaluate(c=>c.toDataURL()),before);
 const box=await page.locator('canvas').boundingBox();await page.mouse.move(box.x+200,box.y+200);await page.mouse.down();await page.mouse.move(box.x+330,box.y+240);await page.mouse.up();
 await page.setViewportSize({width:390,height:844});await page.screenshot({path:resolve(root,'viewer-mobile.png')});await page.setViewportSize({width:1400,height:900});
}
await page.context().setOffline(false);await page.goto(base+'/viewer.html');await page.waitForFunction(()=>window.currentAsset);await download('#zip',readFileSync(resolve(root,'asset-package.zip')));
assert.deepEqual(errors,[]);writeFileSync(resolve(root,'browser-verification.json'),JSON.stringify({platform:'Linux Chromium software WebGL2',models:manifest.models.length,routes:['HTTP folder','self-contained HTML with browser network offline'],file_url:'UNVERIFIED: Chromium enterprise policy ERR_BLOCKED_BY_ADMINISTRATOR',seven_direction_clicks_per_model:7,downloads,zoom_drag:true,page_errors:errors,limits:'browser interaction and downloaded bytes; not iOS/Metal or animation'},null,2));
await browser.close();server.close();console.log('VERIFIED folder/offline viewer/downloads');
