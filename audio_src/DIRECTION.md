# Audio direction

Target: the feel of the 1997 backwoods shooter this game is a tribute to —
its bar-band soundtrack, its chunky foley and its comic voices — made from
original compositions, recordings and performances. Nothing from the reference
game is sampled, copied or imitated note for note; the references were used
only for the measurements below.

## What was measured, and what is an estimate

Measured on 2026-11-10 with ffmpeg (EBU R128) and numpy, from three recordings
of the reference game held outside the repository (a soundtrack rip, an effects
compilation and a voice-line compilation; all MP3 uploads, so absolute levels
describe those uploads, not the original masters):

| | Soundtrack (30 min) | Effects (13 min, 74 events) | Voices (15 min, 455 lines) |
| --- | --- | --- | --- |
| Loudness / range | -11.9 LUFS, LRA 10.3 | -12.7 LUFS, LRA 11.7 | -9.0 LUFS, LRA 8.9 |
| Crest factor | 15.8 dB | 16.5 dB | 13.6 dB |
| Energy below 120 Hz | -5.2 dB | -6.6 dB | -15.4 dB |
| 120-400 Hz | -5.4 dB | -6.1 dB | -6.5 dB |
| 400 Hz-1.5 kHz | -6.9 dB | -4.7 dB | -2.8 dB |
| 1.5-4 kHz | -7.9 dB | -8.4 dB | -7.1 dB |
| 4-11 kHz | -14.5 dB | -13.7 dB | -15.3 dB |
| Spectral centroid | 850 Hz | 950 Hz | 1120 Hz |
| Tempo (per 2.5 min) | 83-215 BPM, median about 144 | | |
| Event length (10/50/90 %) | | 0.4 / 5.8 / 27.6 s | 0.4 / 1.3 / 2.9 s |

(Band figures are each band's share of total energy, 22.05 kHz mono.)

The effects compilation runs sounds together and includes long ambiences, so
its event lengths and attack times describe the compilation, not single
effects. Per-category targets for attack, decay and density below are therefore
**creative estimates** informed by listening notes in the original brief, not
measurements:

| Family | Target (estimate) |
| --- | --- |
| Gun reports | Peak within 3 ms, body 80-250 ms, dry; a bright crack over a mid "bark"; little sub |
| Explosions | Peak within 10 ms, 1-1.5 s, crunchy, weight below 120 Hz |
| Reload / equip / dry fire | Under 300 ms, all above 150 Hz, crisp, one recognisable mechanical action each |
| Warnings (enemy wind-ups) | Rising shape, presence-forward (3 kHz), ends before the attack lands |
| Creatures and voices | Cartoonish, close, mid-forward like the reference voices |
| Footsteps | Short, dull, well under the guns |
| Ambience | Soft, full-bodied beds with no events; nothing piercing above 7 kHz |
| Interface | Tiny, tactile, string-and-wood rather than beeps |
| Music | Cowpunk / rockabilly / psychobilly bar band: twangy overdriven guitar, slap bass, live drums, small room; 110-185 BPM by chapter |

## Calibration (the first paid requests)

One chapter track, a revolver, a shotgun, a mechanical cue (shotgun hinge), an
ambience loop (yard) and the menu confirm were generated first and measured:

* **Track** ("County Road Shuffle"): right genre and structure (a quieter
  section at 60-80 s, a return), but 129 BPM against 148 asked and about 4 dB
  short of the reference between 400 Hz and 4 kHz. Response: the band prompt
  now asks for a bright, biting guitar tone and an urgent tempo, and mastering
  lifts 1 kHz and 3 kHz and trims 160 Hz.
* **Shotgun**: almost all energy below 120 Hz (centroid 190 Hz) — a thud with
  no crack. Regenerated with a prompt that names the crack and midrange bark;
  the report chain's presence lift went from 2 to 3.5 dB.
* **Yard ambience**: nothing but crickets at 4-8 kHz. Regenerated asking for
  wind and body; the ambience chain now rolls off above 6.8 kHz.
* **Revolver, hinge, menu confirm**: within the estimates as generated.

## What has not been done

No human listened to any of this during production: every decision above was
made from measurements (level, spectrum, onset, length, loop seam). The author
should audition `audio_src/final/sfx` and `godot/assets/music` in game and
note what to redo; `python scripts/audio_produce.py --redo <cue>` buys a
replacement take inside the same budget.
