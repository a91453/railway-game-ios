// Renders a MIDI file on a SoundFont bank to raw stereo float32 at 48 kHz
// (interleaved), for tools/audio/sampled_music.py (decision 815, later note).
//
//     node render.mjs <bank.sf2> <song.mid> <out.f32> <seconds>
//
// SpessaSynth (spessasynth_core, Apache-2.0, npm, pinned in package.json)
// plays the file with its own effects off: the reverb and the master are
// sampled_music.py's, so they wrap round the loop.
import { readFile, writeFile } from 'node:fs/promises';
import { BasicMIDI, SoundBankLoader, SpessaSynthProcessor, SpessaSynthSequencer } from 'spessasynth_core';

const [bankPath, midiPath, outPath, seconds] = process.argv.slice(2);
const view = (bytes) => bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
const midi = BasicMIDI.fromArrayBuffer(view(await readFile(midiPath)));
const bank = SoundBankLoader.fromArrayBuffer(view(await readFile(bankPath)));
const rate = 48_000;
const synth = new SpessaSynthProcessor(rate, { eventsEnabled: false, effectsEnabled: false });
synth.soundBankManager.addSoundBank(bank, 'main');
await synth.ready;
synth.setSystemParameter?.('autoAllocateVoices', true);
const sequencer = new SpessaSynthSequencer(synth);
sequencer.loadNewSongList([midi]);
sequencer.loopCount = 0;
sequencer.play();
const frames = Math.round(rate * Number(seconds));
const left = new Float32Array(frames);
const right = new Float32Array(frames);
for (let done = 0; done < frames; ) {
  sequencer.processTick();
  const block = Math.min(128, frames - done);
  synth.process(left, right, done, block);
  done += block;
}
const out = new Float32Array(2 * frames);
for (let i = 0; i < frames; i++) {
  out[2 * i] = left[i];
  out[2 * i + 1] = right[i];
}
await writeFile(outPath, new Uint8Array(out.buffer));
