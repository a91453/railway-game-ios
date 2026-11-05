#!/usr/bin/env python3
"""Original, deterministic airport studies; metres, x forward/y left/z up."""
import argparse
import importlib.util
import json
import math
from pathlib import Path

HERE = Path(__file__).resolve()
FERRY = HERE.parents[1] / 'ferry-studies' / 'produce.py'
spec = importlib.util.spec_from_file_location('native_mesh', FERRY)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

SPECS = {
    'commuter19': (16.56, 16.97, 4.86, 1.20, 4.2, 'high', 'prop'),
    'regional70': (27.17, 27.05, 7.65, 1.45, 5.0, 'high-t', 'prop'),
    'narrowjet': (44.51, 35.80, 11.76, 1.98, 7.4, 'low', 'jet'),
    'widejet': (66.80, 64.75, 17.05, 2.98, 10.0, 'low', 'jet'),
}
PALETTES = [('white', 'blue'), ('white', 'green'), ('white', 'red')]
PARTS = ('runway', 'taxiway', 'apron', 'papi', 'windsock', 'fence',
         'tug', 'baggage', 'stairs', 'fuel')
NAMES = {'commuter19':'十九座雙螺旋槳', 'regional70':'七十座雙渦輪螺旋槳',
         'narrowjet':'窄體噴射客機', 'widejet':'廣體噴射客機',
         'city':'城市航廈', 'island':'離島航廈', 'city-scene':'城市機位組景',
         'island-scene':'離島機位組景'}

def prism(mesh, name, outline, z0, z1, color):
    n = len(outline)
    v = [(x,y,z) for z in (z0,z1) for x,y in outline]
    mesh.solid(name, v, [list(range(n-1,-1,-1)), list(range(n,2*n))] +
               [[i,(i+1)%n,(i+1)%n+n,i+n] for i in range(n)], color)

def tube(mesh, name, x0, x1, y, r, h, color, segments=12):
    # Axial rings produce a sealed, positive-volume body with a distinguishable nose.
    n=segments
    rings=[(x0, r*.58), (x0+(x1-x0)*.14,r), (x1-(x1-x0)*.10,r), (x1,r*.43)]
    v=[(x,y+rad*math.cos(2*math.pi*i/n),h+rad*math.sin(2*math.pi*i/n))
       for x,rad in rings for i in range(n)]
    faces=[list(range(n-1,-1,-1)),list(range(3*n,4*n))]
    for ring in range(3):
        faces += [[ring*n+i,ring*n+(i+1)%n,(ring+1)*n+(i+1)%n,(ring+1)*n+i]
                  for i in range(n)]
    mesh.solid(name,v,faces,color)

def aircraft(mesh, kind, far, paint=0):
    L,W,H,r,wing_x,wing,engine=SPECS[kind]
    white,belt=PALETTES[paint]
    floor=.88 if kind=='commuter19' else (1.05 if kind=='regional70' else (1.30 if kind=='narrowjet' else 1.65))
    belly=floor+r
    door_z={'commuter19':1.8,'regional70':3.2,'narrowjet':4.3,'widejet':5.9}[kind]
    tube(mesh,'closed-fuselage',-L*.49,L*.51,0,r,belly,white,10 if far else 18)
    # Swept, tapered wings: one closed slab each side, visible in silhouette at far LOD.
    high=wing.startswith('high')
    wz=belly+(r*.72 if high else -r*.37)
    for side in (-1,1):
        poly=[(wing_x-3.2,side*r*.75),(wing_x+3.0,side*r*.75),
              (wing_x-1.0,side*(W/2)),(wing_x-3.0,side*(W/2))]
        if side<0:poly.reverse()
        prism(mesh,'left-wing' if side>0 else 'right-wing',poly,wz,wz+.20,belt)
        mesh.box('wingtip-strobe',wing_x-2.1,side*(W/2-.13),wz+.08,.20,.22,.10,'white',1)
        mesh.box('nav-red' if side>0 else 'nav-green',wing_x-2.4,side*(W/2-.16),wz+.12,.20,.22,.10,'red' if side>0 else 'green',1)
    # Tailplane remains elevated on the T-tail variant at both LODs.
    tailz=H-.28 if wing=='high-t' else belly+r*.65
    prism(mesh,'vertical-tail',[(-L*.48,-.13),(-L*.27,-.13),(-L*.36,.13),(-L*.48,.13)],belly, H-.08,belt)
    for side in (-1,1):
        poly=[(-L*.44,0),(-L*.34,0),(-L*.40,side*W*.17),(-L*.47,side*W*.17)]
        if side<0:poly.reverse()
        prism(mesh,'tailplane',poly,tailz,tailz+.13,belt)
    mesh.box('tail-white',-L*.46,0,H-.1,.18,.18,.08,'white',1)
    mesh.box('anti-collision',0,0,belly+r+.02,.24,.24,.15,'red',1)
    mesh.box('beacon-belly',0,0,belly-r-.04,.22,.22,.13,'red',1)
    count=max(4,int(L/2.2)) if not far else 2
    for side in (-1,1):
        for i in range(count):
            x=-L*.27+(i+.5)*(L*.66/count)
            mesh.box('cabin-window',x,side*(r*.995),belly+.23*r,.36,.035,.30,'glass',1)
    if not far:
        mesh.box('door',L*.35,r+.02,door_z-.65,.78,.05,1.3,'steel')
    # Fixed gear for the short field aircraft; metadata describes retraction for others.
    for x,y in [(L*.18,0),(-L*.10,W*.11),(-L*.10,-W*.11)]:
        mesh.box('gear-strut',x,y,0,.14,.13,floor,'steel')
        mesh.box('tyre',x,y,0,.39,.30,.22,'dark')
    for side in (-1,1):
        ex=wing_x-1.2;ey=side*(r+W*.12)
        if engine=='prop':
            tube(mesh,'engine-nacelle',ex-.95,ex+1.15,ey,r*.28,wz-.05,'steel',8 if far else 12)
            mesh.box('prop-hub',ex+1.18,ey,wz-.05,.16,.20,.20,'dark')
            mesh.box('prop-blade',ex+1.23,ey,wz-1.00,.06,.13,2.0,'dark')
            if not far:mesh.box('prop-blade',ex+1.24,ey-.82,wz-.05,.06,1.64,.13,'dark')
        else:
            tube(mesh,'underwing-engine',ex-1.6,ex+1.5,ey,r*.31,max(wz-r*.75,.55+r*.31),'steel',8 if far else 12)
    return {'length_m':L,'wingspan_m':W,'height_m':H,
            'door':{'position':[L*.35,r,door_z],'heading':[0,1,0]},
            'joints':([{'part':f'propeller-{side}','kind':'rotation','pivot':[wing_x-1.2+1.23,side*(r+W*.12),wz-.05],
                         'axis':[1,0,0],'unit':'radians','limit':[0,2*math.pi]} for side in (-1,1)] if engine=='prop' else [])+
                     [{'part':'landing-gear','kind':'rotation','pivot':[-L*.10,0,floor], 'axis':[0,1,0],'limit':[0,1.2],
                       'fixed':kind=='commuter19'},
                      {'part':'door','kind':'rotation','pivot':[L*.35,r,door_z], 'axis':[0,0,1],'limit':[0,1.57]}],
            'night_flags':['nav-red','nav-green','tail-white','anti-collision',
                           'wingtip-strobe','cabin-window']}

def part(mesh, kind, far):
    if kind=='runway':
        mesh.box('sealed-pavement',0,0,0,60,30,.08,'dark')
        for x in (-28,28):
            for y in (-9,-3,3,9):mesh.box('threshold',x,y,.085,2.4,1.3,.018,'white')
        for x in range(-24,25,8):mesh.box('centreline',x,0,.09,3,.28,.015,'white')
        if not far:
            for y in (-13,13):
                for x in (-16,16):mesh.box('touchdown',x,y,.09,7,.36,.015,'white')
            for x in range(-28,29,7):
                for y in (-14.7,14.7):mesh.box('edge-light',x,y,.09,.18,.18,.16,'white',1)
        return {'thresholds':[{'position':[x,0,0],'heading':[1 if x<0 else -1,0,0],
                                'length_m':60} for x in (-30,30)],
                'taxiway':[{'position':[0,15,0],'heading':[0,1,0]}]}
    if kind=='taxiway':
        mesh.box('sealed-pavement',0,0,0,30,12,.08,'steel')
        mesh.box('yellow-centreline',0,0,.09,30,.18,.015,'warm')
        if not far:
            for y in (-5.9,5.9):
                for x in (-13,0,13):mesh.box('blue-edge-light',x,y,.09,.17,.17,.15,'blue',1)
        return {'ends':[{'position':[x,0,0],'heading':[1,0,0]} for x in (-15,15)]}
    if kind=='apron':
        mesh.box('sealed-apron',0,0,0,80,80,.08,'deck')
        for y in (-24,0,24):
            mesh.box('stand-centreline',0,y,.09,24,.18,.015,'warm')
            mesh.box('nose-stop',9,y,.09,.24,3,.015,'warm')
        return {'stands':[{'id':f'S{i+1}','nose_stop':[9,y,0],
                           'heading':[1,0,0],'max_wingspan_m':w,'class':c}
                          for i,(y,w,c) in enumerate(zip((-24,0,24),(17,36,65),('A','C','D')))]}
    if kind=='papi':
        for i in range(4):mesh.box('PAPI-lamp',0,i*.7,0,.26,.26,.34,'red' if i<2 else 'white',1)
    elif kind=='windsock':
        mesh.box('mast',0,0,0,.10,.10,5,'steel');mesh.box('sock',.8,0,4.6,1.6,.42,.42,'red')
    elif kind=='fence':
        for x in (-4,0,4):mesh.box('post',x,0,0,.10,.10,2.5,'steel')
        for z in (.55,1.30,2.05):mesh.box('horizontal-rail',0,0,z,8,.055,.055,'steel')
        if not far:
            for x in range(-7,8):mesh.box('vertical-wire',x*.5,0,.3,.035,.04,2.1,'steel')
    else:
        dims={'tug':(2.7,1.5),'baggage':(4.5,1.5),
              'stairs':(5,2),'fuel':(6.8,2.3)}
        L,W=dims[kind]
        mesh.box('chassis',0,0,.38,L,W,.35,'steel')
        for x in (-L*.33,L*.33):
            for y in (-W*.4,W*.4):mesh.box('wheel',x,y,0,.38,.20,.45,'dark')
        if kind=='tug':
            mesh.box('low-cab',-.65,0,.73,1.05,W*.9,.75,'white')
            mesh.box('windshield',-.11,0,1.02,.04,W*.72,.32,'glass',1)
            mesh.box('drawbar',L*.55,0,.45,.62,.15,.13,'dark')
        elif kind=='baggage':
            mesh.box('tractor-cab',-1.55,0,.73,.95,W*.8,.85,'white')
            for x in (-.3,1.25):
                mesh.box('open-cart',x,0,.73,1.30,W*.84,.22,'blue')
                if not far:
                    for y in (-.42,.42):mesh.box('bag',x,y,.95,.65,.38,.40,'red')
        elif kind=='stairs':
            mesh.box('driver-cab',-1.65,0,.73,.95,W*.8,1.05,'white')
            steps=4 if far else 8
            for i in range(steps):
                mesh.box('stair-tread',-.9+i*2.9/steps,0,.75+(i+1)*2.30/steps,2.9/steps+.02,W*.66,.12,'steel')
            mesh.box('upper-landing',2.0,0,3.05,.75,W*.72,.15,'blue')
        else:
            mesh.box('fuel-cab',2.35,0,.73,1.25,W*.85,1.28,'white')
            tube(mesh,'sealed-fuel-tank',-3.1,1.35,0,.84,1.68,'white',8 if far else 12)
            if not far:mesh.box('hose-box',-.3,W*.48,.88,1.05,.18,.62,'blue')
    return {'mount':'ground-z0'}

def airport(mesh,kind,far):
    city=kind=='city'
    L,W=(90,42) if city else (25,13)
    H=11 if city else 4.5
    mesh.box('main-building',0,0,0,L,W,H,'white')
    mesh.box('roof',0,0,H,L+2,W+2,.25,'blue')
    mesh.box('glazed-front',L*.5+.04,0,.55,.08,W*.84,H*.55,'glass',1)
    mesh.box('entrance-canopy',L*.5+2.3,0,H*.60,5.0,W*.68,.19,'blue')
    for y in (-W*.31,0,W*.31):
        mesh.box('front-mullion',L*.5+.11,y,.55,.08,.15,H*.55,'white')
    if not city:
        mesh.box('walk-boarding-door',L*.5+.14,-W*.26,.55,.10,1.55,2.25,'dark')
        mesh.box('island-platform',L*.5+4,0,0,8,W*.86,.08,'deck')
    if city:
        mesh.box('upper-glazing',L*.5+.08,0,H*.66,.09,W*.78,H*.18,'glass',1)
        mesh.box('roof-plant',-L*.21,-W*.17,H+.25,9,5,1.55,'steel')
        mesh.box('tower-base',-L*.6,-W*.65,0,7,7,26,'steel')
        mesh.box('tower-cab',-L*.6,-W*.65,26,10,10,3,'glass',1)
        mesh.box('tower-roof',-L*.6,-W*.65,29,10.5,10.5,.22,'blue')
        mesh.box('hangar',-L*.8,W*1.5,0,36,30,12,'steel')
        mesh.box('hangar-doors',-L*.8,W*1.5-15.05,0,30,.09,9,'blue')
        for y in (-17,-5,5,20):
            base=2.0 if y<0 else 3.1
            mesh.box('jetbridge',L*.5+9,y,base,18,2.4,2.5,'white')
            mesh.box('bridge-legs',L*.5+16,y,0,.3,.3,base,'steel')
    return {'jetbridges':[{'id':f'J{i+1}','pivot':[L*.5,y,3.25 if y<0 else 4.35],
                           'joint':{'kind':'translation','axis':[1,0,0],'limit_m':[0,7]},
                           'end':[L*.5+18,y,3.25 if y<0 else 4.35]} for i,y in enumerate((-17,-5,5,20))] if city else [],
            'boarding':'jetbridge' if city else 'walk'}

def assembly(mesh,kind,far):
    city=kind=='city-scene'
    apron=mod.Mesh();part(apron,'apron',far)
    apron_start=len(mesh.t)
    apron_offset=(72 if city else 35,0,0)
    mesh.t += [([mod.add(v,apron_offset) for v in tri],c,g) for tri,c,g in apron.t]
    mesh.solids += [dict(s,name='apron-'+s['name'],start=s['start']+apron_start) for s in apron.solids]
    airport(mesh,'city' if city else 'island',far)
    parking=[]
    kinds=['regional70','narrowjet'] if city else ['commuter19']
    for i,plane in enumerate(kinds):
        a=mod.Mesh();aircraft(a,plane,far,i)
        offset=((72.5 if i==0 else 78.6) if city else 35,
                (-15.55 if i==0 else 21.98) if city else 0,0)
        mesh.t += [([(offset[0]-v[0],offset[1]-v[1],v[2]) for v in tri],c,g) for tri,c,g in a.t]
        mesh.solids += [dict(s,name='plane-'+s['name'],start=s['start']+len(mesh.t)-len(a.t)) for s in a.solids]
        parking.append({'id':f'A{i+1}','nose_stop':[offset[0]-SPECS[plane][0]*.51,offset[1],0],
                        'heading':[-1,0,0], 'max_wingspan_m':SPECS[plane][1],
                        'class':('B' if i==0 else 'C') if city else 'A'})
    for i,k in enumerate(('tug','baggage','stairs','fuel') if city else ('baggage','stairs')):
        a=mod.Mesh();part(a,k,far);off=(61+i*7,(-39 if city else -13),0)
        start=len(mesh.t);mesh.t += [([mod.add(v,off) for v in tri],c,g) for tri,c,g in a.t]
        mesh.solids += [dict(s,name=k+'-'+s['name'],start=s['start']+start) for s in a.solids]
    return {'stands':parking,'scene_only':True}

def main():
    ap=argparse.ArgumentParser();ap.add_argument('output',type=Path);args=ap.parse_args()
    root=args.output.resolve();assert HERE.parents[2] not in root.parents
    root.mkdir(parents=True,exist_ok=True)
    models=[]
    for kind in list(SPECS)+['city','island']+list(PARTS)+['city-scene','island-scene']:
        for far in (False,True):
            m=mod.Mesh()
            meta=aircraft(m,kind,far) if kind in SPECS else (airport(m,kind,far) if kind in ('city','island') else (assembly(m,kind,far) if kind.endswith('-scene') else part(m,kind,far)))
            name=NAMES.get(kind,kind);id=kind+('-lod' if far else '-near')
            models.append(mod.write_model(root,id,name+('・遠景' if far else '・近景'),m,meta))
    (root/'manifest.json').write_text(json.dumps({'schema_version':1,'directions':['top','bottom','left','right','front','back','isometric'], 'models':models},ensure_ascii=False,indent=2)+'\n')
    print(len(models),'models',max(m['triangles'] for m in models),'max triangles')

if __name__=='__main__':main()
