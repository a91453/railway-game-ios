#!/usr/bin/env python3
"""TRACKCOUNT-STUDY: the rail ways (sidings, crossovers and yards too), platforms
and switches of northern Taiwan from the osmtoday extract (ODbL), pickled for
urban_track_sections.py. See tools/real-railways/README.md."""
import osmium, pickle, sys
W,S,E,N = 121.15, 24.85, 121.70, 25.22
KINDS={'subway','light_rail','rail','narrow_gauge','monorail','construction','disused','abandoned'}
ways=[]; plats=[]; nodes=[]
class H(osmium.SimpleHandler):
    def node(self, n):
        r=n.tags.get('railway')
        if r in ('switch','buffer_stop','railway_crossing','stop','station','halt') and n.location.valid():
            lo,la=n.location.lon,n.location.lat
            if W<lo<E and S<la<N: nodes.append((n.id,r,dict(n.tags),lo,la))
    def way(self, w):
        r=w.tags.get('railway'); pt=w.tags.get('public_transport')
        if r in KINDS or r=='platform' or pt=='platform':
            try: pts=[(nd.lon,nd.lat) for nd in w.nodes]
            except osmium.InvalidLocationError: return
            if not pts or not any(W<x<E and S<y<N for x,y in pts): return
            ids=[nd.ref for nd in w.nodes]
            rec=(w.id,dict(w.tags),pts,ids)
            if r in KINDS: ways.append(rec)
            else: plats.append(rec)
H().apply_file(sys.argv[1], locations=True)
pickle.dump((ways,plats,nodes),open(sys.argv[2],'wb'))
print(len(ways),len(plats),len(nodes))
