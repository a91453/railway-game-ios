#!/usr/bin/env node
// Converts an MML draft into a score of 《沿線》 (decision 219, research
// note docs/research/RAILWAY_SOUND_2026-10-14.md §2.14).
//
//     node tools/audio/mml_to_score.mjs tools/audio/mml/chime-tourist.mml
//     node tools/audio/mml_to_score.mjs --check
//
// The draft is `name.mml` (Mabinogi's six-slot `MML@a,b,c,d,e,f;`, as MML
// Studio writes it) beside `name.json`, its arrangement: the role, the
// title, the motif, the fade at the end, and for each of the six slots the
// synth voice, gain and pan of its track (`null` for an empty slot). The
// score goes to `tools/audio/scores/name.score.json`.
//
// The MML is read by MML Studio's own core (`mml-core/core.js`, copied from
// a91453/mml-tools, MIT): there is one MML parser, not two. A note that
// does not fall on a whole tick (960 a beat) is refused, never rounded, as
// mml-tools' `writeMidi` refuses what its PPQ cannot hold. `--check`
// converts every draft and fails if a committed score differs.

import { readFileSync, writeFileSync, readdirSync } from 'node:fs';
import { basename, dirname, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';
import { validateMML, f } from './mml-core/core.js';

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = join(HERE, '..', '..');
export const TICKS_PER_BEAT = 960;
const VOICES = ['bell', 'pluck', 'pad', 'clack'];
const ROLES = ['chime', 'departure', 'stem'];

function fail(message) {
  throw new Error(message);
}

/// The whole number of ticks `beats` (a fraction string of core.js) is.
function ticks(beats, what) {
  const t = f(beats).mul(TICKS_PER_BEAT);
  if (t.d !== 1n) fail(`${what}: ${beats} beats is not a whole number of ticks (${TICKS_PER_BEAT} a beat)`);
  return Number(t.n);
}

/// MML's volume V1–V15 as a velocity 1–127. V0 is a silent note: refused.
function velocity(volume, what) {
  if (!(volume >= 1 && volume <= 15)) fail(`${what}: volume V${volume} is silent or out of range`);
  return Math.round((volume * 127) / 15);
}

export function convert(mmlPath) {
  const raw = readFileSync(mmlPath, 'utf8').trim();
  const arrangementPath = mmlPath.replace(/\.mml$/, '.json');
  const arrangement = JSON.parse(readFileSync(arrangementPath, 'utf8'));
  const name = basename(mmlPath, '.mml');
  if (!ROLES.includes(arrangement.role)) fail(`${name}: unknown role ${arrangement.role}`);
  const beatsPerBar = arrangement.beatsPerBar ?? 4;
  const result = validateMML(raw, { meterText: `0 ${beatsPerBar}/4`, title: arrangement.title });
  if (!result.ok) fail(`${name}: MML refused:\n${result.errors.map((e) => `  ${e.role ?? ''} ${e.position ?? ''} ${e.message}`).join('\n')}`);
  const song = result.song;
  if (song.tempo.length !== 1) fail(`${name}: a score has one tempo; the MML changes it`);
  const slots = arrangement.tracks;
  if (!Array.isArray(slots) || slots.length !== 6) fail(`${name}: the arrangement needs six slots`);
  const tracks = [];
  song.tracks.forEach((track, i) => {
    const slot = slots[i];
    if (track.empty) {
      if (slot !== null) fail(`${name}: slot ${i + 1} is empty in the MML but arranged`);
      return;
    }
    if (slot === null) fail(`${name}: slot ${i + 1} has notes but no voice`);
    if (!VOICES.includes(slot.voice)) fail(`${name}: slot ${i + 1}: unknown voice ${slot.voice}`);
    const notes = track.events.map((e, n) => {
      const what = `${name} slot ${i + 1} note ${n + 1}`;
      const start = ticks(e.start, what);
      return { pitch: e.pitch, start, length: ticks(e.end, what) - start, velocity: velocity(e.volume, what) };
    });
    tracks.push({ voice: slot.voice, gain: slot.gain ?? 100, pan: slot.pan ?? 0, notes });
  });
  const score = {
    format: 1,
    role: arrangement.role,
    title: arrangement.title,
    source: relative(ROOT, mmlPath).split('\\').join('/'),
    tempo: song.tempo[0].bpm,
    beatsPerBar,
    length: ticks(song.total, name),
    motif: arrangement.motif ?? 0,
    fadeOut: arrangement.fadeOut ?? 0,
    tracks,
  };
  return { name, text: formatScore(score) };
}

/// The score's canonical text: two-space indents, a note a line.
export function formatScore(score) {
  const lines = ['{'];
  const keys = Object.keys(score).filter((k) => k !== 'tracks');
  for (const k of keys) lines.push(`  ${JSON.stringify(k)}: ${JSON.stringify(score[k])},`);
  lines.push('  "tracks": [');
  score.tracks.forEach((track, t) => {
    lines.push('    {');
    for (const k of ['voice', 'gain', 'pan']) lines.push(`      ${JSON.stringify(k)}: ${JSON.stringify(track[k])},`);
    lines.push('      "notes": [');
    track.notes.forEach((note, n) => {
      const body = ['pitch', 'start', 'length', 'velocity'].map((k) => `${JSON.stringify(k)}: ${note[k]}`).join(', ');
      lines.push(`        {${body}}${n + 1 < track.notes.length ? ',' : ''}`);
    });
    lines.push('      ]');
    lines.push(`    }${t + 1 < score.tracks.length ? ',' : ''}`);
  });
  lines.push('  ]');
  lines.push('}');
  return lines.join('\n') + '\n';
}

function main(args) {
  const scores = join(HERE, 'scores');
  if (args.length === 1 && args[0] === '--check') {
    const drafts = readdirSync(join(HERE, 'mml')).filter((n) => n.endsWith('.mml')).sort();
    let stale = 0;
    for (const draft of drafts) {
      const { name, text } = convert(join(HERE, 'mml', draft));
      let committed = null;
      try {
        committed = readFileSync(join(scores, `${name}.score.json`), 'utf8');
      } catch {}
      if (committed !== text) {
        console.error(`${name}.score.json differs from its MML; run: node tools/audio/mml_to_score.mjs tools/audio/mml/${draft}`);
        stale += 1;
      } else {
        console.log(`${name}.score.json matches its MML`);
      }
    }
    process.exit(stale ? 1 : 0);
  }
  if (args.length === 0) {
    console.error('usage: node tools/audio/mml_to_score.mjs DRAFT.mml... | --check');
    process.exit(2);
  }
  for (const path of args) {
    const { name, text } = convert(path);
    writeFileSync(join(scores, `${name}.score.json`), text);
    console.log(`wrote tools/audio/scores/${name}.score.json`);
  }
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  try {
    main(process.argv.slice(2));
  } catch (e) {
    console.error(e.message);
    process.exit(1);
  }
}
