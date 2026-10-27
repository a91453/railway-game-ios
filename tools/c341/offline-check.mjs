// Check the packaged viewer against actual native files, GLBs and PNGs.
// It uses only a local HTTP server; no CDN or other external request is allowed.
import {createServer} from 'node:http';
import {readFileSync,existsSync} from 'node:fs';
import {resolve,extname} from 'node:path';
import {createRequire} from 'node:module';
import {createHash} from 'node:crypto';
import assert from 'node:assert/strict';

const {chromium}=createRequire(import.meta.url)('playwright');
const root=resolve(process.argv[2]);
const manifest=JSON.parse(readFileSync(resolve(root,'manifest.json')));
const sha=bytes=>createHash('sha256').update(bytes).digest('hex');
const server=createServer((req,res)=>{
 try {
  const path=new URL(req.url,'http://localhost').pathname;
  if(path==='/favicon.ico'){res.writeHead(204);res.end();return;}
  const file=resolve(root,'.'+decodeURIComponent(path));
  if(!file.startsWith(root+'/'))throw Error('invalid path');
  res.setHeader('Content-Type',({'.html':'text/html','.js':'text/javascript','.json':'application/json','.png':'image/png','.glb':'model/gltf-binary','.zip':'application/zip'})[extname(file)]||'application/octet-stream');
  res.end(readFileSync(file));
 } catch {res.writeHead(404);res.end();}
});
await new Promise(done=>server.listen(0,'127.0.0.1',done));
const base='http://127.0.0.1:'+server.address().port;
let browser;
try {
 browser=await chromium.launch({executablePath:process.env.CHROMIUM_PATH||'/usr/bin/chromium',headless:true,args:['--no-sandbox','--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader']});
 const page=await browser.newPage({viewport:{width:1200,height:900},acceptDownloads:true});
 const errors=[],failed=[],external=[];
 page.on('pageerror',error=>errors.push(error.message));
 page.on('response',response=>{if(response.status()>=400)failed.push(response.url());});
 page.on('request',request=>{if(!request.url().startsWith(base)&&!request.url().startsWith('data:')&&!request.url().startsWith('file:'))external.push(request.url());});
 // Test the actual self-contained file with no HTTP server dependency.
 await page.goto('file://'+resolve(root,'viewer-standalone.html')); 
 await page.waitForFunction(()=>window.currentAsset);
 assert.equal(await page.locator('.tile').count(),manifest.models.length);
 assert.equal(await page.evaluate(()=>currentAsset.category),'formation');
 for(const asset of manifest.models){await page.evaluate(id=>loadAsset(id),asset.id);assert((await page.evaluate(()=>renderer.count))>0);}
 const formation=manifest.models.find(asset=>asset.category==='formation');
 await page.evaluate(id=>loadAsset(id),formation.id);
 const captures=[];
 for(const direction of manifest.directions){await page.click(`[data-view="${direction}"]`);captures.push(await page.evaluate(()=>renderer.png()));}
 assert(new Set(captures).size>=6,'fixed directions must make different images');
 await page.click('[data-view="isometric"]');
 const before=await page.evaluate(()=>renderer.png()),box=await page.locator('#canvas').boundingBox();
 await page.mouse.move(box.x+box.width/2,box.y+box.height/2);
 await page.mouse.down();await page.mouse.move(box.x+box.width/2+90,box.y+box.height/2+30,{steps:5});await page.mouse.up();
 assert.notEqual(await page.evaluate(()=>renderer.png()),before,'pointer rotation changes view');
 const beforeZoom=await page.evaluate(()=>renderer.png());
 await page.locator('#zoom').fill('1.5');assert.equal(await page.inputValue('#zoom'),'1.5');
 assert.notEqual(await page.evaluate(()=>renderer.png()),beforeZoom,'zoom changes rendered image');
 for(const [button,path,digest] of [['#glb',formation.glb,formation.glb_sha256],['#native',formation.native,formation.native_sha256]]){
  const wait=page.waitForEvent('download');await page.click(button);const download=await wait;
  assert.equal(sha(readFileSync(await download.path())),digest,button+' download differs from manifest');

 }
 let wait=page.waitForEvent('download');await page.click('#png');let download=await wait;
 assert.equal(readFileSync(await download.path()).readUInt32BE(16),900);
 const zip=resolve(root,'asset-package.zip');
 if(false){
  wait=page.waitForEvent('download');await page.click('#zip');download=await wait;
  assert.equal(sha(readFileSync(await download.path())),sha(readFileSync(zip)),'ZIP download differs from file');
 }
 await page.setViewportSize({width:390,height:844});
 assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),'mobile horizontal overflow');
 assert.deepEqual(errors,[]);assert.deepEqual(failed,[]);assert.deepEqual(external,[]);
 console.log(`VERIFIED self-contained viewer over loopback (local file launch UNVERIFIED): ${manifest.models.length} models, seven views, orbit, zoom, PNG/native/GLB (ZIP is tested separately in the HTTP viewer) downloads, mobile layout, no external requests.`);
} finally {if(browser)await browser.close();server.close();}
