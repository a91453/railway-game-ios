import {createRequire} from 'node:module';
const {chromium}=createRequire(import.meta.url)('/opt/codex/runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
import {readFileSync,writeFileSync,mkdirSync} from 'node:fs';
import {resolve} from 'node:path';
import {createServer} from 'node:http';
const root=process.argv[2];
const manifest=JSON.parse(readFileSync(resolve(root,'manifest.json')));
const server=createServer((req,res)=>{res.setHeader('Content-Type','text/html; charset=utf-8');res.end(readFileSync(resolve(root,'viewer.html')))});await new Promise(r=>server.listen(0,'127.0.0.1',r));
const browser=await chromium.launch({executablePath:'/usr/bin/chromium',headless:true,args:['--no-sandbox','--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader']});
try{
 const page=await browser.newPage({viewport:{width:900,height:800}});await page.goto('http://127.0.0.1:'+server.address().port+'/');await page.waitForFunction(()=>window.renderModel);
 for(const m of manifest.models){m.views={};for(const night of [0]){const mode=night?'night':'day';m.views[mode]={};for(const d of manifest.directions){const url=await page.evaluate(([id,d,night])=>window.renderModel(id,d,night,d==="front"?[0.8660254,0,0.5]:null,{centre:[-84,137,5],extent:[28,32,11]}),[m.id,d,night]);const path=`views/${mode}/${m.id}/${d}.png`;mkdirSync(resolve(root,`views/${mode}/${m.id}`),{recursive:true});writeFileSync(resolve(root,path),Buffer.from(url.split(',')[1],'base64'));m.views[mode][d]=path;}}console.log(m.id,m.triangles)}
 writeFileSync(resolve(root,'manifest.json'),JSON.stringify(manifest,null,2)+'\n');
}finally{await browser.close();server.close()}
