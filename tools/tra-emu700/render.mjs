// Same metre framing for every role/LOD, separate fixed full-train scale.
import{createServer}from'node:http';import{readFileSync,writeFileSync,mkdirSync}from'node:fs';import{resolve,extname}from'node:path';import{createRequire}from'node:module';
const root=resolve(process.argv[2]),manifest=JSON.parse(readFileSync(root+'/manifest.json'));
writeFileSync(root+'/renderer.js',readFileSync(new URL('../train-models/renderer.js',import.meta.url),'utf8').replace('../emu900-native/scene.js','./scene.js'));
writeFileSync(root+'/scene.js',readFileSync(new URL('../emu900-native/scene.js',import.meta.url)));
writeFileSync(root+'/_r.html','<canvas id="c"></canvas><script type="module">import{NativeRenderer}from"./renderer.js";window.make=l=>window.r=new NativeRenderer(document.querySelector("canvas"),l);window.ready=true;</script>');
const server=createServer((q,s)=>{try{const p=resolve(root,'.'+new URL(q.url,'http://x').pathname);s.setHeader('Content-Type',({'.html':'text/html','.js':'text/javascript'})[extname(p)]||'application/octet-stream');s.end(readFileSync(p));}catch{s.writeHead(404);s.end();}});await new Promise(r=>server.listen(0,'127.0.0.1',r));
const {chromium}=createRequire(process.env.NODE_GLOBAL||'/opt/node22/lib/node_modules/')('playwright');
const browser=await chromium.launch({executablePath:process.env.CHROMIUM_PATH||'/usr/bin/chromium',args:['--no-sandbox','--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader']});const page=await browser.newPage();await page.goto('http://127.0.0.1:'+server.address().port+'/_r.html');await page.waitForFunction(()=>window.ready);await page.evaluate(l=>window.make(l),manifest.lighting);
for(const state of ['day','night','day-clay','day-silhouette']){
 mkdirSync(root+'/png/'+state,{recursive:true});
 for(const m of manifest.models){for(const view of ['front','back','left','right','top','bottom','isometric']){
 const png=await page.evaluate(async({native,view,state,formation})=>{const material=state.includes('clay')?'clay':state.includes('silhouette')?'silhouette':'color';r.load(await(await fetch(native)).arrayBuffer(),material);r.centre=[0,0,2.5];r.extent=[formation?81.643:10.4,1.52,2.5];r.render(view,{width:view==='front'||view==='back'?600:1400,height:420,time:state==='night'?'night':'day'});return r.png();},{native:m.native,view,state,formation:m.id.includes('formation')});writeFileSync(root+'/png/'+state+'/'+m.id+'-'+view+'.png',Buffer.from(png.split(',')[1],'base64'));
 }}
}
await browser.close();server.close();
