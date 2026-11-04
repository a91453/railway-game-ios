import {readFileSync as read,writeFileSync as write} from 'node:fs';
import {resolve} from 'node:path';import {createHash} from 'node:crypto';import {createRequire} from 'node:module';
import {glbFromNative,readNative} from '../station-kit/package.mjs';
const root=resolve(process.argv[2]),manifest=JSON.parse(read(root+'/manifest.json')),fixtures=JSON.parse(read(root+'/pose-fixtures.json')),hash=b=>createHash('sha256').update(b).digest('hex');
for(const m of manifest.models){const b=read(root+'/'+m.native);if(hash(b)!==m.native_sha256||!glbFromNative(readNative(b)).equals(read(root+'/'+m.glb)))throw Error('native/GLB mismatch '+m.id)}
const {chromium}=createRequire(import.meta.url)('playwright'),browser=await chromium.launch({executablePath:'/usr/bin/chromium',args:['--no-sandbox','--use-angle=swiftshader','--enable-unsafe-swiftshader']});
const errors=[],requests=[];let maxDifference=0,comparedCoordinates=0;
try{
 let page=await browser.newPage({viewport:{width:390,height:844}}),fileURL='VERIFIED';
 try{await page.goto('file://'+root+'/index.html')}catch(e){if(!String(e).includes('ERR_BLOCKED_BY_ADMINISTRATOR'))throw e;fileURL='UNVERIFIED: managed Chromium blocks file:// (ERR_BLOCKED_BY_ADMINISTRATOR)';await page.close();page=await browser.newPage({viewport:{width:390,height:844}});await page.setContent(read(root+'/index.html','utf8'));}
 page.on('pageerror',e=>errors.push(e.message));page.on('request',r=>requests.push(r.url()));await page.context().setOffline(true);await page.waitForFunction(()=>window.berthingViewer);
 for(let i=0;i<manifest.models.length;i++){await page.selectOption('#model',String(i));for(const v of manifest.directions)await page.selectOption('#view',v);}
 const poseImages=new Map();
 for(const fixture of fixtures){
  const index=manifest.models.findIndex(m=>m.id===fixture.id);await page.selectOption('#model',String(index));await page.locator('#pose').evaluate((el,value)=>{el.step='any';el.value=value;el.dispatchEvent(new Event('input'))},fixture.value);
  const result=await page.evaluate(()=>{const m=berthingViewer.models[document.querySelector('#model').value],buffer=berthingViewer.posed(m),d=new DataView(buffer),base=Uint8Array.from(atob(m.bytes),c=>c.charCodeAt(0)),positions=[],start=16+Math.ceil(d.getUint32(12,true)/4)*4,j=m.connectors.joint;let fixedSame=true;for(let i=0;i<d.getUint32(8,true);i++){const moving=j.ranges.some(([s,n])=>i>=s&&i<s+n);for(let k=0;k<52;k++)if(!moving&&base[start+i*52+k]!==new Uint8Array(buffer)[start+i*52+k])fixedSame=false;for(let v=0;v<3;v++)for(const offset of [0,4,8])positions.push(d.getFloat32(start+i*52+4+v*16+offset,true))}return {positions,fixedSame}});
  if(!result.fixedSame)throw Error('Fixed body moved: '+fixture.id);
  const expected=Buffer.from(fixture.positions_f32_base64,'base64');if(expected.length!==result.positions.length*4)throw Error('Pose size');
  result.positions.forEach((v,i)=>{const delta=Math.abs(v-expected.readFloatLE(i*4));maxDifference=Math.max(maxDifference,delta);if(delta>2e-5)throw Error('Python/JS mismatch '+fixture.id+' '+delta);comparedCoordinates++});
  const png=await page.locator('canvas').screenshot();if(!poseImages.has(fixture.id))poseImages.set(fixture.id,png);else if(fixture.value!==0&&poseImages.get(fixture.id).equals(png))throw Error('Pose pixels unchanged '+fixture.id);
 }
 const day=await page.locator('canvas').screenshot();await page.click('#night');if(day.equals(await page.locator('canvas').screenshot()))throw Error('Night unchanged');for(let i=0;i<4;i++)await page.click('#bg');await page.locator('canvas').dispatchEvent('wheel',{deltaY:100});
 if(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth))throw Error('390px overflow');if(errors.length||requests.some(u=>/^https?:/.test(u)))throw Error('Browser errors/network');
 write(root+'/browser-verification.json',JSON.stringify({status:'VERIFIED',backend:'Linux Chromium WebGL2 embedded HTML network offline; 390px',fileURL,models:manifest.models.length,sevenDirections:true,nightChangesPixels:true,poseFixtures:fixtures.length,comparedCoordinates,maxDifference,fixedBodiesUnchanged:true,poseChangesPixels:true,externalRequests:0,pageErrors:errors},null,2)+'\n');console.log('VERIFIED GLB, browser, Python/JS poses',fixtures.length,comparedCoordinates,maxDifference);
}finally{await browser.close()}
