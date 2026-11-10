#!/bin/sh
# Decision 675: makes the app's Kenney sounds (RailwayGameApp/Resources/AudioKenney/)
# from the two original packs. Usage: convert.sh <interface-sounds dir> <jingles dir>
# (the folders the two zips in SOURCE.md unpack to). Needs ffmpeg.
set -eu
is="$1/Audio"; jg="$2/OGG"; out="$(dirname "$0")/../../../RailwayGameApp/Resources/AudioKenney"
mkdir -p "$out"
conv() { ffmpeg -v error -y -i "$1" -ac 1 -ar 44100 -c:a pcm_s16le -fflags +bitexact -map_metadata -1 "$out/$2.wav"; }
conv "$is/click_003.ogg"          kenney-ui-tap
conv "$is/toggle_001.ogg"         kenney-ui-toggle
conv "$is/confirmation_001.ogg"   kenney-ui-confirm
conv "$is/back_002.ogg"           kenney-ui-cancel
conv "$is/maximize_009.ogg"       kenney-ui-open
conv "$jg/jingles_PIZZA/jingles_PIZZA02.ogg" kenney-jingle-goal
