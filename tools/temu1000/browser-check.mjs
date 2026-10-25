import {createServer} from 'node:http';
import {readFileSync,writeFileSync} from 'node:fs';
import {resolve,extname} from 'node:path';
import {createRequire} from 'node:module';
import {createHash} from 'node:crypto';
import assert from 'node:assert/strict';
const {chromium}=createRequire(import.meta.url)('playwright');
const root=resolve(process.argv[2]),manifest=JSON.parse(readFileSync(resolve(root,'manifest.json')));
const server=createServer((req,res)=>{try{const name=new URL(req.url,'http://localhost').pathname;if(name==='/favicon.ico'){res.writeHead(204);res.end();return;}const p=resolve(root,'.'+decodeURIComponent(name));if(!p.startsWith(root+'/'))throw Error();res.setHeader('Content-Type',({'.html':'text/html','.js':'text/javascript','.json':'application/json','.png':'image/png'})[extname(p)]||'application/octet-stream');res.end(readFileSync(p));}catch{res.writeHead(404);res.end();}});
await new Promise(r=>server.listen(0,'127.0.0.1',r));const base='http://127.0.0.1:'+server.address().port;
let browser;
try {
 browser=await chromium.launch({executablePath:process.env.CHROMIUM_PATH||'/usr/bin/chromium',headless:true,args:['--no-sandbox','--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader']});
 const page=await browser.newPage({viewport:{width:1200,height:900},acceptDownloads:true}),errors=[],external=[],failed=[];
 page.on('pageerror',e=>errors.push(e.message));page.on('response',r=>{if(r.status()>=400)failed.push(r.url());});page.on('request',r=>{if(!r.url().startsWith(base)&&!r.url().startsWith('data:'))external.push(r.url());});
 await page.goto(base+'/index.html');await page.waitForFunction(()=>window.currentAsset);
 assert.equal(await page.locator('.tile').count(),6);assert.equal(await page.evaluate(()=>currentAsset.id),'temu1000-formation');
 for(const m of manifest.models){await page.evaluate(id=>loadAsset(id),m.id);assert((await page.evaluate(()=>renderer.count))>1000);}
 await page.evaluate(()=>loadAsset('temu1000-formation'));
 const captures=[];for(const v of manifest.directions){await page.click('[data-view="'+v+'"]');captures.push(await page.evaluate(()=>renderer.png()));}assert(new Set(captures).size>=6);
 await page.click('[data-view="isometric"]');const before=await page.evaluate(()=>renderer.png()),box=await page.locator('#canvas').boundingBox();
 await page.mouse.move(box.x+box.width/2,box.y+box.height/2);await page.mouse.down();await page.mouse.move(box.x+box.width/2+90,box.y+box.height/2+30,{steps:5});await page.mouse.up();assert.notEqual(await page.evaluate(()=>renderer.png()),before);
 await page.locator('#zoom').fill('1.5');assert.equal(await page.inputValue('#zoom'),'1.5');
 let pending=page.waitForEvent('download');await page.click('#glb');let d=await pending;assert.equal(createHash('sha256').update(readFileSync(await d.path())).digest('hex'),manifest.models[4].glb_sha256);
 pending=page.waitForEvent('download');await page.click('#native');d=await pending;assert.equal(createHash('sha256').update(readFileSync(await d.path())).digest('hex'),manifest.models[4].native_sha256);
 pending=page.waitForEvent('download');await page.click('#png');d=await pending;assert.equal(readFileSync(await d.path()).readUInt32BE(16),900);
 await page.setViewportSize({width:390,height:844});assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));
 assert.deepEqual(errors,[]);assert.deepEqual(failed,[]);assert.deepEqual(external,[]);
 const p=resolve(root,'verification.json'),result=JSON.parse(readFileSync(p));result.browser={status:'VERIFIED',models_loaded:6,checks:['all six models load','seven directions','pointer rotation','zoom','PNG/native/GLB downloads','390 px mobile width','no missing or external requests']};writeFileSync(p,JSON.stringify(result,null,2)+'\n');
 console.log('VERIFIED viewer loads, orbits, zooms and downloads all six models.');
} finally {if(browser)await browser.close();server.close();}
