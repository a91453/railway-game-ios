// Actual M3DM vertices. Glass blending is inspection-only; native Metal is opaque.
export const directions={top:[0,0,1],bottom:[0,0,-1],left:[0,1,0],right:[0,-1,0],front:[1,0,0],back:[-1,0,0],isometric:[1,-1,.7]};
const dot=(a,b)=>a.reduce((s,v,i)=>s+v*b[i],0),cross=(a,b)=>[a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]],unit=a=>a.map(x=>x/Math.hypot(...a));
export class NativeRenderer {
 constructor(canvas){
  this.canvas=canvas;const gl=this.gl=canvas.getContext('webgl2',{alpha:true,antialias:true,preserveDrawingBuffer:true});if(!gl)throw Error('WebGL2 unavailable');
  const shader=(type,source)=>{const s=gl.createShader(type);gl.shaderSource(s,source);gl.compileShader(s);if(!gl.getShaderParameter(s,gl.COMPILE_STATUS))throw Error(gl.getShaderInfoLog(s));return s};
  const vs=shader(gl.VERTEX_SHADER,`#version 300 es
layout(location=0) in vec3 position;layout(location=1) in vec3 normal;layout(location=2) in vec3 color;layout(location=3) in float glass;
uniform vec3 centre,right,up,direction;uniform float radius,aspect,depth;out vec3 n,c;out float g;
void main(){vec3 p=position-centre;gl_Position=vec4(dot(p,right)/(radius*aspect),dot(p,up)/radius,-dot(p,direction)/depth,1);n=normal;c=color;g=glass;}`);
  const fs=shader(gl.FRAGMENT_SHADER,`#version 300 es
precision highp float;in vec3 n,c;in float g;uniform float night,opacity,mode;out vec4 outColor;
void main(){float sun=max(dot(normalize(n),normalize(vec3(.4,-.5,.8))),0.);vec3 base=mode>.5?vec3(.92):c;vec3 lit=base*mix(.80+.20*sun,.16+.08*sun,night);if(mode>1.5)lit=vec3(.08,.12,.2);outColor=vec4(lit,mix(1.,opacity,g));}`);
  const p=this.program=gl.createProgram();gl.attachShader(p,vs);gl.attachShader(p,fs);gl.linkProgram(p);if(!gl.getProgramParameter(p,gl.LINK_STATUS))throw Error(gl.getProgramInfoLog(p));gl.deleteShader(vs);gl.deleteShader(fs);
  this.buffer=gl.createBuffer();this.vao=gl.createVertexArray();gl.bindVertexArray(this.vao);gl.bindBuffer(gl.ARRAY_BUFFER,this.buffer);for(const [i,s,o] of [[0,3,0],[1,3,12],[2,3,24],[3,1,36]]){gl.enableVertexAttribArray(i);gl.vertexAttribPointer(i,s,gl.FLOAT,false,40,o)}this.u=Object.fromEntries(['centre','right','up','direction','radius','aspect','depth','night','opacity','mode'].map(n=>[n,gl.getUniformLocation(p,n)]));
 }
 load(buffer,{hideRoof=false}={}){
  const d=new DataView(buffer);if(d.getUint32(0,true)!==0x4d44334d||d.getUint16(4,true)!==1||d.getUint16(6,true)!==0)throw Error('Invalid M3DM');const count=d.getUint32(8,true),len=d.getUint32(12,true),start=16+Math.ceil(len/4)*4;if(count<1||count>15000||buffer.byteLength!==start+count*52)throw Error('Invalid size');
  const meta=JSON.parse(new TextDecoder().decode(new Uint8Array(buffer,16,len))),hidden=new Set();if(hideRoof)for(const s of meta.extras.solids||[])if(/roof|yoke|hanger|grip|spring|opener/.test(s.name))for(let i=s.start;i<s.start+s.count;i++)hidden.add(i);
  this.triangles=[];this.bounds={low:[Infinity,Infinity,Infinity],high:[-Infinity,-Infinity,-Infinity]};
  for(let i=0;i<count;i++){if(hidden.has(i))continue;const at=start+i*52,flag=d.getUint32(at,true);if(flag&~3)throw Error('Unsupported flags');const p=[0,1,2].map(j=>[0,4,8].map(k=>d.getFloat32(at+4+j*16+k,true))),n=unit(cross(p[1].map((x,k)=>x-p[0][k]),p[2].map((x,k)=>x-p[0][k]))),data=[];if(n.some(x=>!Number.isFinite(x)))throw Error('Degenerate');for(let j=0;j<3;j++){const color=d.getUint32(at+16+j*16,true);data.push(...p[j],...n,...[0,8,16].map(s=>((color>>>s)&255)/255),(flag&2)?1:0);p[j].forEach((x,k)=>{if(!Number.isFinite(x))throw Error('Nonfinite');this.bounds.low[k]=Math.min(this.bounds.low[k],x);this.bounds.high[k]=Math.max(this.bounds.high[k],x)})}this.triangles.push({data,glass:!!(flag&2),centre:p[0].map((x,k)=>(x+p[1][k]+p[2][k])/3)})}
  return this.triangles.length;
 }
 render(view='isometric',{width=512,height=512,zoom=1,vector,night=0,opacity=.20,mode=0,fixed=true}={}){
  const gl=this.gl,direction=unit(vector||directions[view]||directions.isometric),right=unit(cross(Math.abs(direction[2])>.99?[0,1,0]:[0,0,1],direction)),up=unit(cross(direction,right)),aspect=width/height;
  const centre=fixed?[0,0,-2.07]:this.bounds.low.map((x,k)=>(x+this.bounds.high[k])/2),extent=fixed?[1.25,1.20,2.45]:this.bounds.low.map((x,k)=>(this.bounds.high[k]-x)/2),project=a=>dot(a.map(Math.abs),extent),radius=Math.max(project(up),project(right)/aspect)*1.14/zoom,depth=10;
  const opaque=this.triangles.filter(t=>!t.glass||opacity===1),glass=this.triangles.filter(t=>t.glass&&opacity!==1).sort((a,b)=>dot(a.centre,direction)-dot(b.centre,direction));const data=new Float32Array([...opaque,...glass].flatMap(t=>t.data));
  this.canvas.width=width;this.canvas.height=height;gl.viewport(0,0,width,height);gl.depthMask(true);gl.clearColor(0,0,0,0);gl.clear(gl.COLOR_BUFFER_BIT|gl.DEPTH_BUFFER_BIT);gl.enable(gl.DEPTH_TEST);gl.enable(gl.CULL_FACE);gl.cullFace(gl.BACK);gl.useProgram(this.program);gl.bindVertexArray(this.vao);gl.bindBuffer(gl.ARRAY_BUFFER,this.buffer);gl.bufferData(gl.ARRAY_BUFFER,data,gl.DYNAMIC_DRAW);
  for(const [k,v] of Object.entries({centre,right,up,direction}))gl.uniform3fv(this.u[k],v);for(const [k,v] of Object.entries({radius,aspect,depth,night,opacity,mode}))gl.uniform1f(this.u[k],v);
  gl.disable(gl.BLEND);gl.drawArrays(gl.TRIANGLES,0,opaque.length*3);gl.enable(gl.BLEND);gl.blendFuncSeparate(gl.SRC_ALPHA,gl.ONE_MINUS_SRC_ALPHA,gl.ONE,gl.ONE_MINUS_SRC_ALPHA);gl.depthMask(false);gl.drawArrays(gl.TRIANGLES,opaque.length*3,glass.length*3);gl.depthMask(true);gl.finish();if(gl.getError()!==gl.NO_ERROR)throw Error('WebGL error');
 }
 png(){return this.canvas.toDataURL('image/png')}
}
