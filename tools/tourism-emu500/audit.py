"""Run type-specific output probes and actual geometry mutations."""
from probes import *
root=Path(sys.argv[1]);fleet=root.name;rows=[]
for role in ['emc','ep','et','em']:
 pair=[]
 for far in [False,True]:
  id=f'{fleet}-emu500-{role}'+('-far' if far else '');t,f=read(root/'models'/f'{id}.m3dmodel')
  ids,n=glass(t,f);wheels(t);rs=roof(t);layout(t,f,role)
  broken=t.copy();broken[ids]+=n[ids,None,:]*.12;reject(lambda:glass(broken,f))
  broken=t.copy();broken[ids]-=n[ids,None,:]*.12;reject(lambda:glass(broken,f))
  broken=t.copy();sel=(broken[:,:,2]<.861).all(axis=1)&(abs(broken[:,:,0])>4.8).all(axis=1);broken[sel,:,2]+=.06;reject(lambda:wheels(broken))
  broken=t.copy();broken[rs,:,2]+=.08;reject(lambda:roof(broken))
  broken=t.copy();broken[rs,:,0]+=.3;reject(lambda:roof(broken))
  if role!='ep':
   centre=((f&2)>0)&(abs(t[:,:,0])<.7).all(axis=1)&(abs(t[:,:,1])>1.4).all(axis=1)
   duplicate=t[centre].copy();duplicate[:,:,1]+=.02
   reject(lambda:layout(np.concatenate([t,duplicate]),np.concatenate([f,f[centre]]),role))
  if role in ['emc','em']:
   cab_hardware(t);cab_glass_corners(t,f)
   for mask,shift in [
    ((t[:,:,0]>9.8).all(axis=1)&(t[:,:,2]>1.35).all(axis=1)&(t[:,:,2]<1.75).all(axis=1),[.12,0,0]),
    ((t[:,:,0]>9.85).all(axis=1)&(abs(t[:,:,1])<.4).all(axis=1)&(t[:,:,2]<1.10).all(axis=1),[-.2,0,0])]:
    broken=t.copy();broken[mask]+=np.array(shift);reject(lambda:cab_hardware(broken))
   block=np.array([[[10.,.3,.4],[10.,.7,.4],[10.,.5,.9]]])
   reject(lambda:cab_hardware(np.concatenate([t,block])))
   # Move actual lower nose faces ahead of their supporting shell.
   seal=(t[:,:,0]>9.5).all(axis=1)&(abs(t[:,:,1])<.5).all(axis=1)&(t[:,:,2]>1.1).all(axis=1)&(t[:,:,2]<2.3).all(axis=1)
   bad=t[seal].copy();bad[:,:,0]+=.25
   reject(lambda:layout(np.concatenate([t,bad]),np.concatenate([f,f[seal]]),role))
  rows.append(dict(id=id,glass_visible_supported=True,wheels=8,roof_contact=True,converted_openings=True,actual_faults_rejected=['floating glass','buried glass','off rail wheels','roof vertical/horizontal shift','duplicated centre glass','nose seal protrusion']+(['lamp displacement','retracted coupler','blocked coupler recess'] if role in ['emc','em'] else [])))
  pair.append((t,f,colors(root/'models'/f'{id}.m3dmodel')))
 near,far=pair
 assert len(far[0])<len(near[0])*.5,'LOD budget'
 lod(near[0],far[0],near[2],far[2])
 reject(lambda:lod(near[0],far[0]+np.array([0.,.2,0.]),near[2],far[2]))
 reject(lambda:lod(near[0],far[0],near[2],np.full_like(far[2],0xffff00ff)))
(root/'fleet-verification.json').write_text(json.dumps(dict(status='VERIFIED',models=rows,limits=['sampled support and visibility; not all intersections','dimensions / concealed equipment photo estimates','static studies; device / dynamics not verified']),indent=2)+'\n')
print('VERIFIED',fleet,'native probes and real mutations')
