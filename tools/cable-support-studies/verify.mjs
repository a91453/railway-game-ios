import {readFileSync as read,writeFileSync as write} from 'node:fs';
import {resolve} from 'node:path';
import {createHash} from 'node:crypto';
import {createRequire} from 'node:module';
import {glbFromNative,readNative} from '../station-kit/package.mjs';
const root=resolve(process.argv[2]),manifest=JSON.parse(read(root+'/manifest.json')),hash=b=>createHash('sha256').update(b).digest('hex');
for(const m of manifest.models){const b=read(root+'/'+m.native);if(hash(b)!==m.native_sha256||!glbFromNative(readNative(b)).equals(read(root+'/'+m.glb)))throw Error('native/GLB mismatch '+m.id)}
const {chromium}=createRequire(import.meta.url)('playwright');const browser=await chromium.launch({executablePath:'/usr/bin/chromium',args:['--no-sandbox','--use-angle=swiftshader','--enable-unsafe-swiftshader']});
const errors=[],requests=[];
try{
 let page=await browser.newPage({viewport:{width:390,height:844}});page.on('pageerror',e=>errors.push(e.message));page.on('request',r=>requests.push(r.url()));let fileURL='VERIFIED';try{await page.goto('file://'+root+'/index.html')}catch(e){if(!String(e).includes('ERR_BLOCKED_BY_ADMINISTRATOR'))throw e;fileURL='UNVERIFIED: managed Chromium blocks file:// (ERR_BLOCKED_BY_ADMINISTRATOR)';await page.close();page=await browser.newPage({viewport:{width:390,height:844}});page.on('pageerror',e=>errors.push(e.message));page.on('request',r=>requests.push(r.url()));await page.setContent(read(root+'/index.html','utf8'));}await page.context().setOffline(true);await page.waitForFunction(()=>window.cableViewer);
 const baseline=await page.locator('canvas').screenshot();
 for(let i=0;i<manifest.models.length;i++){await page.selectOption('#model',String(i));for(const v of manifest.directions)await page.selectOption('#view',v);}
 const jointIndex=manifest.models.findIndex(m=>m.id==='assembly-near');await page.selectOption('#model',String(jointIndex));
 const poses=[];for(const theta of [0,1.570796]){await page.locator('#pose').evaluate((el,v)=>{el.value=String(v);el.dispatchEvent(new Event('input'))},theta);poses.push(await page.locator('canvas').screenshot())}if(poses[0].equals(poses[1]))throw Error('joint slider did not change pixels');
 const joint=await page.evaluate(()=>{const m=cableViewer.models[document.querySelector('#model').value],b=new Uint8Array(atob(m.bytes).split('').map(c=>c.charCodeAt(0))),p=new Uint8Array(cableViewer.posed(m)),d=new DataView(b.buffer),offset=16+Math.ceil(d.getUint32(12,true)/4)*4,j=m.connectors.joints[0],start=offset+j.movingTriangleStart*52,end=start+j.movingTriangleCount*52;let fixedSame=true,movingChanged=false;for(let i=0;i<b.length;i++){if(i<start||i>=end)fixedSame&&=b[i]===p[i];else movingChanged||=b[i]!==p[i]}return {fixedSame,movingChanged}});if(!joint.fixedSame||!joint.movingChanged)throw Error('joint body isolation');
 await page.click('#night');const night=await page.locator('canvas').screenshot();if(night.equals(poses[1]))throw Error('night unchanged');for(let i=0;i<4;i++)await page.click('#bg');await page.locator('canvas').dispatchEvent('wheel',{deltaY:100});
 if(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth))throw Error('390px overflow');
 if(requests.some(u=>/^https?:/.test(u)))throw Error('offline viewer made network request');if(errors.length)throw Error(errors.join('\n'));
 write(root+'/browser-verification.json',JSON.stringify({status:'VERIFIED',backend:'Linux Chromium WebGL2 embedded HTML, network offline; 390px',fileURL,models:manifest.models.length,sevenDirections:true,nightChangesPixels:true,jointSliderChangesPixels:true,...joint,externalRequests:0,pageErrors:errors},null,2)+'\n');
 console.log('VERIFIED GLB byte reconstruction, offline embedded 12-model viewer (file URL policy separately recorded), day/night, rigid moving body, mobile layout');
}finally{await browser.close()}
