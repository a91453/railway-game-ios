import {createServer} from 'node:http';
import {readFileSync,writeFileSync,mkdirSync} from 'node:fs';
import {resolve,extname} from 'node:path';
import {createRequire} from 'node:module';
const {chromium}=createRequire('/opt/codex/cua_node/lib/node_modules/')('playwright');
const root=resolve(process.argv[2]);mkdirSync(resolve(root,'details'),{recursive:true});
const server=createServer((q,r)=>{try{r.setHeader('Content-Type',({'.html':'text/html','.js':'text/javascript','.json':'application/json'})[extname(q.url)]||'application/octet-stream');r.end(readFileSync(resolve(root,'.'+q.url)));}catch{r.statusCode=404;r.end();}});await new Promise(ok=>server.listen(0,'127.0.0.1',ok));
const browser=await chromium.launch({executablePath:'/usr/bin/chromium',args:['--no-sandbox','--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader']});
const page=await browser.newPage();await page.goto('http://127.0.0.1:'+server.address().port+'/viewer.html');await page.waitForFunction(()=>window.currentAsset?.id==='taipei610-a');
const tasks=[
 ['detail-crop-front','taipei610-a',[7.5,0,2.0],[1.7,1.7,2.0],'isometric'],
 ['detail-crop-doors','taipei610-a',[-.65,0,2.15],[3,1.6,1.5],'right'],
 ['detail-crop-collector-wheels','taipei610-a',[5.72,0,.7],[1.9,1.65,.9],'isometric'],
 ['detail-crop-roof','taipei610-a',[4.25,0,3.4],[2.5,1.7,.7],'isometric'],
 ...['taipei610-a','accepted-e500-v3','accepted-emu3000-v5','before-operation-wenhu'].map(id=>['same-metre-scale-'+id,id,null,[12,2,2.6],'isometric'])
];
for(const [name,id,centre,extent,view] of tasks){await page.evaluate(async ({id,centre,extent,view})=>{await loadAsset(id);if(centre)renderer.centre=centre;renderer.extent=extent;renderer.render(view,{width:1200,height:620});},{id,centre,extent,view});const png=await page.locator('canvas').evaluate(c=>c.toDataURL());writeFileSync(resolve(root,'details',name+'.png'),Buffer.from(png.split(',')[1],'base64'));}
await browser.close();server.close();
