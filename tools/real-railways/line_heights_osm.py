#!/usr/bin/env python3
"""HEIGHT-STUDY: the running-track ways of Taiwan's railways, metros and light
rails (no service=siding|yard|spur|crossover) with their bridge, tunnel,
layer and level tags, and the station and stop nodes and platform ways with
theirs, from the osmtoday extract (ODbL), pickled for line_heights_summary.py.

    python3 -I line_heights_osm.py taiwan.pbf osm_heights.pkl

See docs/research/LINE_HEIGHTS_2026-11-05.md."""
import osmium, pickle, sys

KINDS = {'rail', 'subway', 'light_rail', 'narrow_gauge', 'monorail'}
KEEP = ('railway', 'service', 'bridge', 'tunnel', 'layer', 'level', 'location', 'covered',
        'embankment', 'cutting', 'name', 'name:en', 'ref', 'station', 'subway', 'light_rail',
        'public_transport', 'usage', 'operator', 'network')
ways, stations, platforms = [], [], []


class Handler(osmium.SimpleHandler):
    def node(self, n):
        if n.tags.get('railway') in ('station', 'halt', 'stop') or n.tags.get('public_transport') == 'station':
            if n.location.valid():
                stations.append((n.id, {k: n.tags.get(k) for k in KEEP if k in n.tags}, n.location.lon, n.location.lat))

    def way(self, w):
        railway = w.tags.get('railway')
        platform = railway == 'platform' or w.tags.get('public_transport') == 'platform'
        if railway not in KINDS and not platform:
            return
        if railway in KINDS and w.tags.get('service') in ('siding', 'yard', 'spur', 'crossover'):
            return
        try:
            points = [(nd.lon, nd.lat) for nd in w.nodes]
        except osmium.InvalidLocationError:
            return
        record = (w.id, {k: w.tags.get(k) for k in KEEP if k in w.tags}, points)
        (platforms if platform else ways).append(record)


Handler().apply_file(sys.argv[1], locations=True)
pickle.dump((ways, stations, platforms), open(sys.argv[2], 'wb'))
print(len(ways), len(stations), len(platforms))
