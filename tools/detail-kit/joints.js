// Same native coordinate transform as Map3DDetailKit. Fixed vertices are copied
// byte-for-byte. Only positions of the moving body's vertices are transformed;
// NativeRenderer recomputes flat normals from the resulting triangles.
export function composePose(fixed,moving,joint,pose) {
 function layout(buffer){const d=new DataView(buffer);if(d.getUint32(0,true)!==0x4d44334d||d.getUint16(4,true)!==1)throw Error('Invalid native body');const start=16+Math.ceil(d.getUint32(12,true)/4)*4,count=d.getUint32(8,true);if(start+count*52!==buffer.byteLength)throw Error('Invalid native body size');return {d,start,count};}
 const a=layout(fixed),b=layout(moving),out=new ArrayBuffer(a.start+(a.count+b.count)*52),bytes=new Uint8Array(out),d=new DataView(out);
 bytes.set(new Uint8Array(fixed));bytes.set(new Uint8Array(moving,b.start),a.start+a.count*52);d.setUint32(8,a.count+b.count,true);
 const value=Number.isFinite(pose)?Math.max(joint.limit[0],Math.min(joint.limit[1],pose)):0,[ax,ay,az]=joint.axis,[px,py,pz]=joint.pivot,c=Math.cos(value),s=Math.sin(value);
 for(let i=0;i<b.count;i++)for(let j=0;j<3;j++){
  const p=a.start+(a.count+i)*52+4+j*16,x=d.getFloat32(p,true),y=d.getFloat32(p+4,true),z=d.getFloat32(p+8,true);
  let q;
  if(joint.kind==='translation')q=[x+ax*value,y+ay*value,z+az*value];
  else {const u=x-px,v=y-py,w=z-pz,k=(ax*u+ay*v+az*w)*(1-c);q=[px+u*c+(ay*w-az*v)*s+ax*k,py+v*c+(az*u-ax*w)*s+ay*k,pz+w*c+(ax*v-ay*u)*s+az*k];}
  q.forEach((v,k)=>d.setFloat32(p+k*4,v,true));
 }
 return out;
}
