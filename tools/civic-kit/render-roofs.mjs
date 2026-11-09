// Decision 669: one directory per model, at most three states, seven views.
import {readFileSync,writeFileSync,mkdirSync,rmSync} from 'node:fs';
import {resolve,dirname} from 'node:path';
import {createRequire} from 'node:module';
import {createHash} from 'node:crypto';
import assert from 'node:assert/strict';
import {readNative,glbFromNative} from '../station-kit/package.mjs';
const {chromium}=createRequire(import.meta.url)('playwright');
const root=resolve(process.argv[2]),manifest=JSON.parse(readFileSync(resolve(root,'manifest.json')));
const renderer=readFileSync(new URL('../station-kit/renderer.js',import.meta.url),'utf8').replaceAll('export ','');
const sha=b=>createHash('sha256').update(b).digest('hex');
const groups=Map.groupBy(manifest.models,m=>m.base_id);
const browser=await chromium.launch({executablePath:process.env.CHROMIUM_PATH||'/usr/bin/chromium',headless:true,args:['--no-sandbox','--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader']});
try {
const page=await browser.newPage({viewport:{width:1440,height:900}}),errors=[];
page.on('pageerror',e=>errors.push(e.message));
await page.route('**/*',route=>route.abort());
for(const [id,records] of groups) {
 const dir=resolve(root,id);mkdirSync(dir,{recursive:true});
 const payload=[];
 const lod=records.filter(m=>m.state!=='fallback');
 const low=[0,1,2].map(i=>Math.min(...lod.map(m=>m.minimum[i]))),high=[0,1,2].map(i=>Math.max(...lod.map(m=>m.maximum[i])));
 const camera={centre:low.map((v,i)=>(v+high[i])/2),extent:low.map((v,i)=>(high[i]-v)/2)};
 for(const m of records) {
  const native=readFileSync(resolve(root,m.native)),glb=readFileSync(resolve(root,m.glb));
  assert.deepEqual(glb,glbFromNative(readNative(native)));
  assert.equal(sha(native),m.native_sha256);assert.equal(sha(glb),m.glb_sha256);
  m.native=`${id}/${m.state}.m3dmodel`;m.glb=`${id}/${m.state}.glb`;
  writeFileSync(resolve(root,m.native),native);writeFileSync(resolve(root,m.glb),glb);
  m.views=Object.fromEntries(manifest.directions.map(d=>[d,`${id}/${m.state}/${d}.png`]));
  payload.push({state:m.state,native:native.toString('base64'),glb:glb.toString('base64')});
 }
 const html=`<!doctype html><meta charset="utf-8"><title>${records[0].name}</title><style>body{font:16px system-ui;background:#eceef6;color:#262c57}canvas{width:min(90vw,800px)}button{margin:4px}</style><h1>${records[0].name}</h1><p>近景／原版遠景／原版回退；拖曳旋轉，滑鼠滾輪縮放。Illustrative kit, not a surveyed landmark.</p><div id="states"></div><div id="views"></div><canvas id="canvas" width="800" height="650"></canvas><p><button id="native">下載原生</button><button id="glb">下載 GLB</button></p><script>${renderer}\nconst payload=${JSON.stringify(payload)};window.renderer=new NativeRenderer(document.getElementById('canvas'));let current=payload[0],view='isometric',angle=-0.6,elevation=0.65,zoom=1,custom=false;const bytes=b=>Uint8Array.from(atob(b),c=>c.charCodeAt(0));window.loadState=s=>{current=payload.find(p=>p.state===s);renderer.load(bytes(current.native).buffer);if(s!=='fallback'){renderer.centre=${JSON.stringify(camera.centre)};renderer.extent=${JSON.stringify(camera.extent)};}draw();};function draw(){renderer.render(view,{width:800,height:650,zoom,vector:custom?[Math.cos(angle)*Math.cos(elevation),Math.sin(angle)*Math.cos(elevation),Math.sin(elevation)]:undefined});}for(const p of payload){const b=document.createElement('button');b.textContent=p.state;b.onclick=()=>loadState(p.state);document.getElementById('states').append(b);}for(const d of Object.keys(directions)){const b=document.createElement('button');b.textContent=d;b.onclick=()=>{custom=false;view=d;draw();};document.getElementById('views').append(b);}const canvas=document.getElementById('canvas');let last;canvas.onpointerdown=e=>{last=[e.clientX,e.clientY];canvas.setPointerCapture(e.pointerId);};canvas.onpointerup=()=>last=null;canvas.onpointermove=e=>{if(!last)return;angle-=(e.clientX-last[0])*0.01;elevation=Math.max(-1.4,Math.min(1.4,elevation+(e.clientY-last[1])*0.01));last=[e.clientX,e.clientY];custom=true;draw();};canvas.onwheel=e=>{e.preventDefault();zoom=Math.max(0.5,Math.min(3,zoom-e.deltaY*0.001));draw();};for(const type of ['native','glb'])document.getElementById(type).onclick=()=>{const a=document.createElement('a');a.href=URL.createObjectURL(new Blob([bytes(current[type])]));a.download='${id}-'+current.state+(type==='glb'?'.glb':'.m3dmodel');a.click();};loadState('near');</script>`;
 writeFileSync(resolve(dir,'viewer.html'),html);
 await page.goto('about:blank');
 await page.setContent(html);
 await page.waitForFunction(()=>window.renderer&&window.loadState);
 for(const m of records) {
  const images=await page.evaluate(({state,views})=>{loadState(state);const result={};for(const v of views){renderer.render(v,{width:384,height:384});const gl=renderer.gl,p=new Uint8Array(384*384*4);gl.readPixels(0,0,384,384,gl.RGBA,gl.UNSIGNED_BYTE,p);let count=0,l=384,t=384,r=0,b=0;for(let y=0;y<384;y++)for(let x=0;x<384;x++)if(p[(y*384+x)*4+3]>16){count++;l=Math.min(l,x);t=Math.min(t,y);r=Math.max(r,x);b=Math.max(b,y);}if(count<20||l<2||t<2||r>381||b>381)throw Error('Empty or clipped '+state+' '+v);result[v]={url:renderer.png(),opaque_pixels:count,bounds:[l,t,r,b]};}return result;},{state:m.state,views:manifest.directions});
  m.png_sha256={};m.view_metrics={};
  for(const [v,data] of Object.entries(images)){const file=resolve(root,m.views[v]);mkdirSync(dirname(file),{recursive:true});const b=Buffer.from(data.url.split(',')[1],'base64');assert(b.length<=2*1024*1024);assert.equal(b[25],6);writeFileSync(file,b);m.png_sha256[v]=sha(b);m.view_metrics[v]={opaque_pixels:data.opaque_pixels,bounds:data.bounds};}
 }
 // Exercise the self-contained viewer's state switching, rotation and zoom.
 await page.getByRole('button',{name:'far',exact:true}).click();
 await page.getByRole('button',{name:'near',exact:true}).click();
 await page.mouse.move(400,400);await page.mouse.down();await page.mouse.move(480,440);await page.mouse.up();await page.mouse.wheel(0,80);
 for(const type of ['native','glb']) {
  const pending=page.waitForEvent('download');
  await page.getByRole('button',{name:type==='native'?'下載原生':'下載 GLB',exact:true}).click();
  const downloaded=await pending;
  assert.equal(sha(readFileSync(await downloaded.path())),records.find(m=>m.state==='near')[type+'_sha256']);
 }
}
assert.deepEqual(errors,[]);
const rows=[];
for(const [id,records] of groups){
 const img=m=>`data:image/png;base64,${readFileSync(resolve(root,m.views.isometric)).toString('base64')}`;
 rows.push(`<h2>${records[0].name} · ${id}</h2><div class="row">`+records.map(m=>`<article><img src="${img(m)}"><p>${m.state} · ${m.triangles} triangles</p></article>`).join('')+
 `<article class="switch"><div>${records.filter(m=>m.state!=='fallback').map(m=>`<img src="${img(m)}">`).join('')}</div><p>遠近切換 · near / far<br>同一角度、同一公尺相機</p></article></div>`);
}
await page.setContent('<meta charset="utf-8"><style>body{background:#eceef6;color:#262c57;font:16px system-ui;margin:20px}h2{margin:10px}.row{display:flex}article{background:white;border-radius:8px;margin:4px;text-align:center}img{width:280px;height:230px;object-fit:contain}.switch img{width:240px}.switch div{display:flex}</style><h1>中式屋頂與老房子 · 決策 669 · revision 2</h1>'+rows.join(''));
await page.evaluate(()=>Promise.all([...document.images].map(i=>i.decode())));
await page.screenshot({path:resolve(root,'overview.png'),fullPage:true});
rmSync(resolve(root,'models'),{recursive:true});
rmSync(resolve(root,'views'),{recursive:true,force:true});
manifest.recipe_sha256=Object.fromEntries(['Map3DScooters.swift','Map3DChineseRoof.swift','Map3DCivicKit.swift','Map3DCivicKitCulture.swift','Map3DCivicKitGeometry.swift','Map3DResidentialKit.swift','Map3DResidentialKitGeometry.swift','Map3DStationKitGeometry.swift','Map3DRealFacade.swift','Map3DBuildings.swift'].map(name=>[name,sha(readFileSync(new URL('../../Sources/GamePresentation/'+name,import.meta.url)))]));
writeFileSync(resolve(root,'manifest.json'),JSON.stringify(manifest,null,2)+'\n');
writeFileSync(resolve(root,'verification.json'),JSON.stringify({status:'VERIFIED',models:groups.size,states:3,pngs:manifest.models.length*7,fixed_near_far_camera:true,checks:['native loader vertex roundtrip','GLB full byte re-encode','self-contained viewer markup loaded in Chromium with network blocked','state switch / drag / wheel / downloaded native and GLB SHA','seven nonempty unclipped PNG RGBA views <= 2MB'],unverified:['iOS / Android runtime','game planning visual acceptance','file URL navigation (Chrome administrator policy blocks file://)']},null,2)+'\n');
console.log('VERIFIED roofs: '+groups.size+' models, '+manifest.models.length*7+' PNGs, offline viewers and GLB byte comparison.');
} finally {await browser.close();}
