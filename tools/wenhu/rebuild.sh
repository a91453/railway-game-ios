#!/bin/sh
set -eu
ids='wenhu-val256-a,wenhu-val256-b,wenhu-val256-a-far,wenhu-val256-b-far,wenhu-apm256-a,wenhu-apm256-b,wenhu-apm256-a-far,wenhu-apm256-b-far'
tools/train-models/run.sh "$1" --ids "$ids" --assembly-spec tools/wenhu/assembly.json
node tools/train-models/package.mjs "$1"
node tools/train-models/audit.mjs "$1"
