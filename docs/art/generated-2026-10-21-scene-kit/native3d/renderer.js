// Preview of actual native vertices. No Three.js, textures or external assets.
// Native/model coordinates: x front, y left, z up. WebGL is a preview backend,
// not evidence of the Metal renderer's performance on an iPhone.
export const directions={top:[0,0,1],bottom:[0,0,-1],left:[0,1,0],right:[0,-1,0],front:[1,0,0],back:[-1,0,0],isometric:[1,-1,0.8]};
const dot=(a,b)=>a.reduce((s,v,i)=>s+v*b[i],0);
const cross=(a,b)=>[a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]];
const unit=a=>{const n=Math.hypot(...a);return a.map(x=>x/n);};

export class NativeRenderer {
 constructor(canvas){
  this.canvas=canvas;const gl=canvas.getContext('webgl2',{alpha:true,antialias:true,preserveDrawingBuffer:true});
  if(!gl)throw Error('此瀏覽器無法開啟 WebGL 2。');this.gl=gl;
  const vertex=`#version 300 es
  layout(location=0) in vec3 position;layout(location=1) in vec3 normal;layout(location=2) in vec3 color;layout(location=3) in float glow;
  uniform vec3 centre,right,up,direction;uniform float radius,aspect,depth;
  out vec3 n,c;out float g;
  void main(){vec3 p=position-centre;gl_Position=vec4(dot(p,right)/(radius*aspect),dot(p,up)/radius,-dot(p,direction)/depth,1.0);n=normal;c=color;g=glow;}`;
  const fragment=`#version 300 es
  precision highp float;in vec3 n,c;in float g;out vec4 outColor;
  void main(){float sun=max(dot(normalize(n),normalize(vec3(0.4,-0.5,0.8))),0.0);outColor=vec4(c*(0.8+0.2*sun)+vec3(g*0.025),1.0);}`;
  const shader=(type,source)=>{const s=gl.createShader(type);gl.shaderSource(s,source);gl.compileShader(s);if(!gl.getShaderParameter(s,gl.COMPILE_STATUS))throw Error(gl.getShaderInfoLog(s));return s;};
  const p=gl.createProgram(),vs=shader(gl.VERTEX_SHADER,vertex),fs=shader(gl.FRAGMENT_SHADER,fragment);gl.attachShader(p,vs);gl.attachShader(p,fs);gl.linkProgram(p);gl.deleteShader(vs);gl.deleteShader(fs);if(!gl.getProgramParameter(p,gl.LINK_STATUS))throw Error(gl.getProgramInfoLog(p));this.program=p;
  this.buffer=gl.createBuffer();this.vao=gl.createVertexArray();gl.bindVertexArray(this.vao);gl.bindBuffer(gl.ARRAY_BUFFER,this.buffer);
  for(const [index,size,offset] of [[0,3,0],[1,3,12],[2,3,24],[3,1,36]]){gl.enableVertexAttribArray(index);gl.vertexAttribPointer(index,size,gl.FLOAT,false,40,offset);}
  this.uniforms=Object.fromEntries(['centre','right','up','direction','radius','aspect','depth'].map(n=>[n,gl.getUniformLocation(p,n)]));
 }
 load(buffer){
  const d=new DataView(buffer),magic=String.fromCharCode(...new Uint8Array(buffer,0,4));
  if(magic!=='M3DM'||d.getUint16(4,true)!==1||d.getUint16(6,true)!==0)throw Error('無效的原生模型。');
  const count=d.getUint32(8,true),length=d.getUint32(12,true),start=16+Math.ceil(length/4)*4;
  if(count<1||count>15000||start+count*52!==buffer.byteLength)throw Error('原生模型大小不符。');
  const data=new Float32Array(count*3*10),low=[Infinity,Infinity,Infinity],high=[-Infinity,-Infinity,-Infinity];
  for(let i=0;i<count;i++){
   const at=start+i*52,flags=d.getUint32(at,true);if(flags&~1)throw Error('不支援的三角形旗標。');const points=[];
   for(let j=0;j<3;j++){const k=at+4+j*16;points.push([d.getFloat32(k,true),d.getFloat32(k+4,true),d.getFloat32(k+8,true)]);}
   const u=points[1].map((x,k)=>x-points[0][k]),v=points[2].map((x,k)=>x-points[0][k]),normal=unit(cross(u,v));
   for(let j=0;j<3;j++){
    const k=(i*3+j)*10,color=d.getUint32(at+4+j*16+12,true);data.set(points[j],k);data.set(normal,k+3);data.set([color&255,(color>>>8)&255,(color>>>16)&255].map(x=>x/255),k+6);data[k+9]=flags&1;
    for(let c=0;c<3;c++){if(!Number.isFinite(points[j][c]))throw Error('無效的模型座標。');low[c]=Math.min(low[c],points[j][c]);high[c]=Math.max(high[c],points[j][c]);}
   }
  }
  this.count=count*3;this.bounds={low,high};this.centre=low.map((x,i)=>(x+high[i])/2);this.extent=low.map((x,i)=>(high[i]-x)/2);
  const gl=this.gl;gl.bindBuffer(gl.ARRAY_BUFFER,this.buffer);gl.bufferData(gl.ARRAY_BUFFER,data,gl.STATIC_DRAW);return count;
 }
 render(view='isometric',{width=768,height=540,zoom=1,vector}={}){
  if(!this.count)return;const gl=this.gl,direction=unit(vector||directions[view]||directions.isometric),reference=Math.abs(direction[2])>0.99?[0,1,0]:[0,0,1];
  const right=unit(cross(reference,direction)),up=unit(cross(direction,right)),aspect=width/height;
  const projected=axis=>this.extent.reduce((s,v,i)=>s+Math.abs(axis[i])*v,0);
  const radius=Math.max(projected(up),projected(right)/aspect,0.1)*1.14/zoom,depth=Math.max(...this.extent)*3+1;
  this.canvas.width=width;this.canvas.height=height;gl.viewport(0,0,width,height);gl.clearColor(0,0,0,0);gl.clear(gl.COLOR_BUFFER_BIT|gl.DEPTH_BUFFER_BIT);gl.enable(gl.DEPTH_TEST);gl.enable(gl.CULL_FACE);gl.cullFace(gl.BACK);gl.frontFace(gl.CCW);gl.useProgram(this.program);gl.bindVertexArray(this.vao);
  for(const [name,value] of Object.entries({centre:this.centre,right,up,direction}))gl.uniform3fv(this.uniforms[name],value);
  for(const [name,value] of Object.entries({radius,aspect,depth}))gl.uniform1f(this.uniforms[name],value);
  gl.drawArrays(gl.TRIANGLES,0,this.count);gl.finish();if(gl.getError()!==gl.NO_ERROR)throw Error('WebGL 繪圖失敗。');
 }
 png(){return this.canvas.toDataURL('image/png');}
}
