// Fixed metre cab-detail comparison from the real before/after native payloads.
// node render-mouth.mjs AFTER BEFORE; raw crops remain local, one sheet ships.
import {createServer} from 'node:http';
import {readFileSync,writeFileSync,mkdirSync} from 'node:fs';
import {resolve,extname} from 'node:path';
import {createRequire} from 'node:module';
import {createHash} from 'node:crypto';
const roots={after:resolve(process.argv[2]),before:resolve(process.argv[3])};
const manifests=Object.fromEntries(Object.entries(roots).map(([k,p])=>[k,JSON.parse(readFileSync(resolve(p,'manifest.json')))]));
const root=roots.after;mkdirSync(resolve(root,'mouth'),{recursive:true});
const renderer=readFileSync(new URL('../train-models/renderer.js',import.meta.url),'utf8').replace('../emu900-native/scene.js','./scene.js');
const html='<canvas id="c"></canvas><script type="module">import{NativeRenderer}from"/renderer.js";window.make=l=>window.r=new NativeRenderer(document.querySelector("canvas"),l);window.ready=true;</script>';
const server=createServer((q,s)=>{try{const path=new URL(q.url,'http://x').pathname;if(path==='/'){s.setHeader('Content-Type','text/html');s.end(html);return;}if(path==='/renderer.js'){s.setHeader('Content-Type','text/javascript');s.end(renderer);return;}if(path==='/scene.js'){s.setHeader('Content-Type','text/javascript');s.end(readFileSync(new URL('../emu900-native/scene.js',import.meta.url)));return;}const [tag,...parts]=path.slice(1).split('/');if(!roots[tag])throw Error('unknown source');const p=resolve(roots[tag],parts.join('/'));if(!p.startsWith(roots[tag]+'/'))throw Error('outside run');s.setHeader('Content-Type',extname(p)==='.json'?'application/json':'application/octet-stream');s.end(readFileSync(p));}catch{s.writeHead(404);s.end();}});
await new Promise(r=>server.listen(0,'127.0.0.1',r));
const {chromium}=createRequire(process.env.NODE_GLOBAL||'/opt/node22/lib/node_modules/')('playwright');
const browser=await chromium.launch({executablePath:process.env.CHROMIUM_PATH||'/usr/bin/chromium',args:['--no-sandbox','--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader']});
const page=await browser.newPage();await page.goto('http://127.0.0.1:'+server.address().port);await page.waitForFunction(()=>window.ready);await page.evaluate(l=>window.make(l),manifests.after.lighting);
const inputs=[];
for(const tag of ['before','after'])for(const suffix of ['','-far']){
 const m=manifests[tag].models.find(m=>m.id.startsWith('tra-emu700-emc')&&m.id.endsWith('-far')===Boolean(suffix)),bytes=readFileSync(resolve(roots[tag],m.native));inputs.push({tag,id:m.id,native_sha256:createHash('sha256').update(bytes).digest('hex')});
 for(const state of ['color','clay','silhouette'])for(const view of ['front','isometric']){
  const png=await page.evaluate(async({url,state,view})=>{r.load(await(await fetch(url)).arrayBuffer(),state);r.centre=[9.7,0,2.2];r.extent=[1.4,1.6,1.65];r.render(view,{width:720,height:720,time:'day'});return r.png();},{url:'/'+tag+'/'+m.native,state,view});writeFileSync(resolve(root,'mouth',`${tag}${suffix}-${state}-${view}.png`),Buffer.from(png.split(',')[1],'base64'));
 }
}
await browser.close();server.close();
writeFileSync(resolve(root,'mouth-comparison.json'),JSON.stringify({before_producer:'553b3a2207bf87e6d02819d687b673860055a84a',before_acceptance:'USER REJECTED: cab mouth',camera:{centre:[9.7,0,2.2],extent:[1.4,1.6,1.65],width:720,height:720,scope:'Fixed cab-detail crop of the complete native car, not a separate replacement mesh; full car views are in the role sheets.'},lighting:manifests.after.lighting,inputs},null,2)+'\n');
console.log('Rendered fixed-metre rejected/current native cab comparisons');
