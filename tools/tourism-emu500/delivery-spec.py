"""Type-specific records for the shared deliver.py; no alternate exporter.

python3 tools/tourism-emu500/delivery-spec.py RUN PRODUCER
Reads the committed public source/status records; RUN already contains curated PNGs.
"""
import json
from pathlib import Path
import sys

repo = Path(__file__).resolve().parents[2]
root = Path(sys.argv[1]).resolve()
producer = sys.argv[2]
previous = 'f036e7f79279586f5831c7cb9bf9d8cce3444558'
rebuild = '''tools/tourism-emu500/build.sh /absolute/run
tools/train-models/run.sh /absolute/run/baseline --ids emu500-emc,emu500-ep,emu500-et,emu500-em,emu500-formation
for fleet in haifeng shanlan; do
  node tools/train-models/render.mjs /absolute/run/$fleet --time both
done
node tools/tourism-emu500/review.mjs /absolute/run
python3 tools/tourism-emu500/curate.py /absolute/run /absolute/overview.png
python3 tools/tourism-emu500/delivery-spec.py /absolute/run ''' + producer

for fleet in ['haifeng', 'shanlan']:
    run = root/fleet
    record = json.loads((repo/'docs/art/tourism-emu500/sources.json').read_text())
    record.update(fleet=fleet, producer_commit=producer,
                  previous_delivered_producer=previous, previous_accepted_producer=None,
                  vehicle='EMU573' if fleet == 'haifeng' else 'EMU583',
                  conversion_base='EMU500 07bd8f0d near / 40528d8a far',
                  simplifications='Photo-estimated hidden equipment / kitchen openings; dark simplified cabin; simplified coupler, major hoses only; no operational / dynamic validation')
    status = json.loads((repo/f'docs/art/tourism-emu500/{fleet}-status.json').read_text())
    pngs = [str(p.relative_to(run)) for p in sorted((run/'selected').glob('*.png'))]
    assert len(pngs) == 20
    spec = dict(repo=str(repo), producer=producer,
                previous_producer=previous+' (unaccepted first delivery)',
                rebuild=rebuild, sources='sources.json', status='status.json',
                license_files=[], pngs=pngs)
    for name, value in [('sources', record), ('status', status), ('delivery', spec)]:
        (run/(name+'.json')).write_text(json.dumps(value, ensure_ascii=False, indent=2)+'\n')
