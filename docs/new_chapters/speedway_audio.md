# Chapter 6, Buzzard Bend Speedway: sound and music to make

Made (audio pass, 2026-11-11): every cue below is in scripts/audio_spec.py and
the bank and swapped in where the table says; the music is three tracks
(music_speedway, pit_row_boogie, checkered_flag_rag), fight_speedway and the
boss loop boss_speedway. Kept as the brief.

Nothing here was generated: the speedway agent may not run ElevenLabs. Until
these exist the chapter uses existing cues where it can (listed under each
cue) and the game skips a missing cue silently, so every new cue below is
already called from the code or the level and only needs its file.

Families are the ones `scripts/audio_spec.py` `add()` already uses. Lengths are
`G(prompt, gen, keep)`'s generation length in seconds.

## Sound effects

| Cue | Family | Prompt | Length | Called from |
| --- | --- | --- | --- | --- |
| `derby_champ_warn` | warn | A big-block V8 in a battered derby car revving hard, lifters clattering, then the tyres starting to spin on dirt. | 1.2 | enemies.cfg windup of the boss (each RAMMING LANE and SPARE TYRES windup; `millhand_rev` plays with it now) |
| `derby_champ_crash` | impact | An armoured demolition-derby car slams into a concrete wall at speed: heavy crunch of steel, glass and a radiator bursting. | 1.4 | `src/derby_champ.gd` `_crash` (a charge ending in a wall; `scenery_scrap` plays with it now) |
| `derby_champ_rage` | alert | A redneck derby champion bellowing from inside his car over a screaming engine and a horn blast. | 1.6 | `enemies.gd _enrage` (half health) |
| `derby_champ_death` | death | A derby car's engine dies in a tearing explosion: fuel tank whoomp, steel crumpling, a man's last holler. | 2.2 | `enemies.gd _boss_falls` (the car's blast plays the `explosion` cue already) |
| `derby_champ_pain` | death | A man inside a steel car grunting as bullets ping off the armour plate. | 0.8 | none yet: the boss has no `voice` in enemies.cfg, so the steel `actor_tool_*` cues play; once these two exist add `voice="derby_champ"` to [derby_champ] |
| `derby_champ_down` | death | Same man, a short dying groan as the engine coughs out. | 1.0 | as above |
| `flagman_flare` | attack | A flare pistol fired: hollow pop and a fizzing whoosh of a burning flare. | 0.8 | the flagman fires `rocket_pop` now (`src/speedway_hands.gd`); rename there if made |
| `tire_roll` | attack | A heavy racing tyre bowled hard along packed dirt: rubbery thump and a rumbling roll. | 1.2 | the tyre roller uses `bowling_hit` as its release cue now (enemies.cfg signature) |
| `wrench_throw` | attack | A heavy steel lug wrench thrown end over end: whoosh and a ringing clang where it lands. | 0.9 | the pit mechanic uses `tosser_throw` now (enemies.cfg signature) |
| `huffer_hiss` | warn | A wild man huffing nitrous from a hose: a long gas hiss and a giggle. | 1.0 | the nitro huffer's windup uses `fuse_hiss` now (enemies.cfg) |
| `lap_car_pass` | distant | A dirt-track stock car blasting past close: V8 roar dopplering by, gravel spraying the wall. | 2.0 | `src/features/race_laps.gd` plays `distant_derby_engine` now |
| `lap_car_hit` | impact | A man struck by a speeding race car: bang of a fender and a body thrown onto dirt. | 1.0 | `race_laps.gd` plays `scenery_scrap` now |

## Stings

| Cue | Family | Prompt | Length |
| --- | --- | --- | --- |
| `derby_champ_intro` | sting | A gritty Southern rock riff over a revving V8 and a starter's horn: the derby champ rolls out. | 2.5 |
| `derby_champ_end` | sting | A huge victorious Southern rock chord with an engine coughing to silence and a crowd whoop. | 2.5 |

## Voice lines (exchanges, captioned in the game already)

Cue names are `talk_<id>_0` and `talk_<id>_1`, family `voice`.

| Id | Line 0 | Line 1 |
| --- | --- | --- |
| `pit-radio` | RADIO: FUEL'S 110 PROOF, BOYS. | CREW: THEN DON'T LIGHT A SMOKE. |
| `booth-pa` | PA: LAP FORTY-SEVEN, BOGGS LEADS. | PA: AS USUAL. WHAT A SHOCK. |
| `camp-fire` | CAMPER: SEE THAT SAUCER OVER TURN TWO? | OTHER: THAT'S A FLOODLIGHT, EARL. |

## Music

The level's score is `music_speedway` and its fight loop `fight_speedway`
(the hooks the brief asked for). Neither exists yet, so the chapter plays
silent music until they do. In the style of the chapter tracks in
`scripts/audio_spec.py`:

| Stem | Title | BPM | Prompt |
| --- | --- | --- | --- |
| `music_speedway` | Buzzard Bend Feature Race | 126 | Greasy Southern rock and honky-tonk at a dirt-track race night: driving overdriven Telecaster riff, chugging bass, snare on two and four with a ride cymbal like a revving engine, a wailing harmonica answering, a pedal steel swell over the bridge. Loose, loud, beer-soaked and fast. |
| `fight_speedway` | Demolition Derby Brawl | 138 | Heavy redneck rock brawl at 138 BPM: crunching fuzz guitar riff, pounding floor toms and crash cymbals like cars colliding, slide guitar screaming over the top, honky-tonk piano hammering, a quick banjo roll on the turnarounds. Dangerous, sweaty and relentless; a seamless loop. |

They are already wired like the bayou's: `src/sound.gd` SCORES
`"music_speedway": ["music_speedway"]` and FIGHTS
`"music_speedway": "fight_speedway"`, `tools/pack_assets.gd` MUSIC_FILES
`"music_speedway": ["music_speedway", "fight_speedway"]`, and
`tools/make_packs.gd` PACKS `"music_speedway": ["music_speedway.bin",
"art_speedway.bin"]`. Until the tracks exist, both are on
`godot/src/assets.gd PENDING_MUSIC` (the chapter's file is written empty and
verify_assets skips them). When both files are in `godot/assets/music` (each
in `playback_ends.json`), take them off that list (add more stems to SCORES if a
three-track playlist is made).
