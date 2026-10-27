// One offline HTML page of rendered runs: node viewer.mjs OUT.html RUN [RUN ...]
// Each RUN is a directory export.swift and render.mjs made (its manifest.json
// "tag" names it: before, after, ...). The page embeds the PNGs and the
// manifest numbers, so it opens from a file with no network. With two runs a
// model is shown side by side (before | after) in every view and light.
import {readFileSync, writeFileSync, readdirSync, existsSync} from 'node:fs';
import {resolve} from 'node:path';
const [out, ...runs] = process.argv.slice(2);
if (!out || !runs.length) { console.error('usage: viewer.mjs OUT.html RUN [RUN ...]'); process.exit(2); }
const data = runs.map(dir => {
  const root = resolve(dir), manifest = JSON.parse(readFileSync(resolve(root, 'manifest.json'))), images = {};
  const pngRoot = resolve(root, 'png');
  for (const time of existsSync(pngRoot) ? readdirSync(pngRoot) : [])
    for (const file of readdirSync(resolve(pngRoot, time))) images[`${time}/${file.replace(/\.png$/, '')}`] = 'data:image/png;base64,' + readFileSync(resolve(pngRoot, time, file)).toString('base64');
  return {tag: manifest.tag, models: manifest.models.map(({id, triangles, hash, role, far, glowTriangles}) => ({id, triangles, hash, role, far, glowTriangles})), images};
});
const ids = [...new Set(data.flatMap(r => r.models.map(m => m.id)))].sort();
const html = `<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Train models</title>
<style>:root{color-scheme:light dark;--bg:#eceef6;--fg:#1d2230;--card:#fff}@media(prefers-color-scheme:dark){:root{--bg:#161a24;--fg:#e8eaf2;--card:#202636}}
body{margin:0;padding:16px;background:var(--bg);color:var(--fg);font:14px system-ui,sans-serif}select,button{font:inherit;padding:4px 8px}
.row{display:flex;flex-wrap:wrap;gap:8px;margin-bottom:12px}.cell{background:var(--card);border-radius:8px;padding:8px;flex:1 1 360px;min-width:0}
.cell h3{margin:0 0 6px;font-size:13px}.cell img{width:100%;height:auto;display:block}.meta{opacity:.7;font-size:12px}</style>
<div class="row"><select id="model"></select><select id="time"></select><button id="all">all views</button></div>
<div id="out"></div>
<script>const runs=${JSON.stringify(data)},ids=${JSON.stringify(ids)},views=['isometric','left','right','front','back','top','bottom'];
const $=id=>document.getElementById(id),times=[...new Set(runs.flatMap(r=>Object.keys(r.images).map(k=>k.split('/')[0])))];
$('model').innerHTML=ids.map(i=>'<option>'+i+'</option>').join('');$('time').innerHTML=times.map(t=>'<option>'+t+'</option>').join('');
function draw(){const id=$('model').value,t=$('time').value;let h='';
 for(const v of views){h+='<div class="row">';for(const r of runs){const m=r.models.find(m=>m.id===id),img=r.images[t+'/'+id+'-'+v];
  h+='<div class="cell"><h3>'+r.tag+' · '+v+'</h3>'+(img?'<img src="'+img+'">':'<span class="meta">no image</span>')+(m?'<div class="meta">'+m.triangles+' triangles · '+m.role+' · '+m.hash+(m.glowTriangles?' · '+m.glowTriangles+' glowing':'')+'</div>':'')+'</div>';}
  h+='</div>';}
 $('out').innerHTML=h;}
$('model').onchange=$('time').onchange=draw;draw();</script>`;
writeFileSync(resolve(out), html);
console.log(`wrote ${out}: ${ids.length} models, ${data.length} run(s)`);
