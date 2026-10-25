// Local native assembly contract: legal M3DM units, translations in metres.
// The combined buffer exists only for preview/export; it is not a loadable
// single game M3DM file and does not raise the game's 15,000 triangle limit.
export function assemblyNative(buffer) {
 const first=new Uint8Array(buffer,0,1)[0];if(first!==123)return buffer;
 const scene=JSON.parse(new TextDecoder().decode(buffer));
 if(scene.format!=='M3DAssembly' || scene.version!==1)throw Error('Invalid native assembly');
 const units=new Map(Object.entries(scene.units).map(([id,b64])=>[id,Uint8Array.from(atob(b64),c=>c.charCodeAt(0))]));
 let count=0;for(const p of scene.placements){const b=units.get(p.unit);if(!b)throw Error('Missing unit');count+=new DataView(b.buffer).getUint32(8,true);}
 const out=new ArrayBuffer(20+count*52),d=new DataView(out);new Uint8Array(out).set([77,51,68,77,1,0,0,0]);d.setUint32(8,count,true);d.setUint32(12,2,true);new Uint8Array(out).set([123,125,0,0],16);
 let dest=20;
 for(const p of scene.placements){
  const b=units.get(p.unit),s=new DataView(b.buffer),n=s.getUint32(8,true),start=16+Math.ceil(s.getUint32(12,true)/4)*4;
  new Uint8Array(out,dest,n*52).set(b.subarray(start));
  for(let i=0;i<n;i++)for(let j=0;j<3;j++)for(let axis=0;axis<3;axis++){const at=dest+i*52+4+j*16+axis*4;d.setFloat32(at,Math.fround((axis===0?Math.fround(d.getFloat32(at,true)*Math.fround(p.scale_x??1)):d.getFloat32(at,true))+Math.fround(p.translation[axis])),true);}
  dest+=n*52;
 }
 return out;
}
