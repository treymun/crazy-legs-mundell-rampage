# Gator Bayou (chapter five): sound and music to make

Made (audio pass, 2026-11-11): every cue below is in scripts/audio_spec.py and
the bank, and the music is three tracks (bayou_score, cypress_crawl,
crawdad_boil_hop), fight_bayou and the boss loop boss_bayou. The tables are
kept as the brief they were made from.

Nothing here has been generated: the chapter plays silently where these cues
are missing (`sound.play` skips them; the ambience falls back to the plain yard
and room beds until `amb_bayou*` exist). Names are exactly what the code and
data ask for. Families are the ones `scripts/audio_spec.py` `add()` uses; the
helper (G, LOOP, V) and its `style` follow the neighbouring cues of the same
family. Lengths are the generation length in seconds (keep in brackets where
it should be trimmed).

## Enemies

| Cue | Family | Prompt | Length |
| --- | --- | --- | --- |
| `noodler_holler` | alert | A big swamp man hollers, startled and mean, a wet bark of a shout rising out of the water. (vox) | 1.0 |
| `noodler_grunt` | warn | A heavy man grunts and winds up a swing, a big wet fish slapping against his waders. (creature) | .8 |
| `noodler_slap` | attack | A huge wet catfish slammed across somebody: meaty slap, splatter of swamp water. (impact) | .6 |
| `noodler_rise` | scene | A big man bursts up out of shallow swamp water: heavy splash, water pouring off him. (impact) | 1.0 |
| `chum_holler` | alert | A bait man yells "Chum's in!" and sloshes a bucket, slop hitting the water. (vox) | 1.2 |
| `chum_slosh` | warn | A plastic jug of fish chum sloshed back over a shoulder to throw: thick liquid glug. (impact) | .7 |
| `chum_throw` | attack | A full jug of chum lobbed: effortful toss, the jug tumbling with a gurgle. (impact) | .6 |
| `gator_hiss` | warn | An alligator's low warning hiss and throat rumble, close. (creature) | 1.0 |
| `gator_snap` | attack | An alligator's jaws snapping shut hard: heavy clack and a lunge splash. (creature) | .6 |

The gator is struck as a shell (`actor_shell_pain` / `_down` already exist);
the noodler and the chum tosser cry with the existing `hick` voice.

## The Swamp King (boss)

| Cue | Family | Prompt | Length |
| --- | --- | --- | --- |
| `king_holler` | alert | A big redneck swamp boss whoops over a roaring airboat engine, "Who's on my water?" (vox) | 1.6 |
| `king_rev` | warn | An airboat's aircraft engine revving hard, the big caged propeller winding up to a roar. (tool) | 1.2 |
| `king_charge` | attack | An airboat launching flat out across water: engine howl, prop roar, a hissing rooster tail of spray. (tool) | 1.4 |
| `king_ram` | attack | A steel airboat hull rams a wooden dock: heavy crunch, splintering planks, engine still screaming. (impact) | 1.0 |
| `king_beached` | attack | An airboat runs aground on a mud bank: grinding scrape, the engine choking and sputtering down. (impact) | 1.3 |
| `king_puntgun` | attack | A huge punt gun fires from a boat: enormous black-powder boom, a spray of shot ripping across water. (gun) | 1.4 (.9) |
| `swamp_king_rage` | alert | A fat swamp king bellows furiously over a redlining airboat engine. (vox) | 1.6 |
| `king_down` | death | A big man's dying howl as his airboat engine coughs and dies. (vox) | 1.8 |
| `swamp_king_death` | death | A swamp king's last wail as his airboat's fuel tank goes up with a whump and a splash. (vox) | 2.2 |
| `swamp_king_intro` | sting | Swampy dark Southern rock: a growling slide guitar riff, an airboat engine roar and pounding toms, boss arrival sting. | 2.5 (2.2) |
| `swamp_king_end` | sting | A huge victorious Southern rock final chord with a washboard rattle and a rolling drum fill. | 2.5 (2.2) |

`king` is listed in enemies.cfg `death_only_voices`, so only `king_down` is
needed for its voice (no pain cry).

## Places

| Cue | Family | Prompt | Length |
| --- | --- | --- | --- |
| `amb_bayou` | ambience | A swamp at dusk: bullfrogs, cicadas and crickets, still water lapping at pilings, a far heron call. LOOP | 14 (14.0) |
| `amb_bayou_shack` | ambience | Inside a tin-roofed stilt shack: a box fan rattling, water lapping under the floor, insects on the screens. LOOP | 12 (12.0) |
| `amb_bayou_after` | ambience | A swamp gone quiet after a fight: frogs starting up again, drifting smoke, water settling. LOOP | 12 (11.6) |
| `distant_bayou_airboat` | distant | An airboat engine idling out on open water far away. (far) | 2.5 |
| `distant_bayou_juke` | distant | A juke joint band thumping through thin walls across the water, muffled. (far) | 2.5 |
| `distant_bayou_gator` | distant | An alligator's deep bellow rolling across a swamp. (far) | 2.0 |
| `distant_bayou_frogs` | distant | A chorus of bullfrogs swelling far off in the cypress. (far) | 2.0 |
| `record_scratch` | scene | A needle dragged across a spinning record: a quick scratch to silence. (mech) | .6 |

## Overheard (voice, `talk_<id>_<n>`)

| Cue (spec name) | Voice | Line |
| --- | --- | --- |
| `talk_boil__cooks_0` | local | "Who dropped a boot in the boil?" |
| `talk_boil__cooks_1` | local | "That's seasonin'." |
| `talk_juke__band_0` | local | "We know two songs." |
| `talk_juke__band_1` | local | "Then play the other one." |
| `talk_dock__radio_0` | dispatch, fx radio | "King to dock. Fuel her up." |
| `talk_dock__radio_1` | local | "Tank's full, your majesty." |

## Music

Both go in `music_bayou.bin` (pack_assets.gd `MUSIC_FILES`). Once they are in
`godot/assets/music`, take `bayou_score` and `fight_bayou` off
`PENDING_MUSIC` in `godot/src/assets.gd` and add their cut-off points to
`playback_ends.json`, as for the other chapters.

| Track | Title | BPM | Prompt |
| --- | --- | --- | --- |
| `bayou_score` | Black Water Stomp | 112 | Swampy dark Southern rock at dusk: a greasy slide guitar riff over a loping kick and washboard, a growling bass, jug blows and a lonesome harmonica answering; humid, muddy and menacing, with a slow build like an airboat winding up out on the water. |
| `fight_bayou` | Airboat Brawl | 136 | Heavy swamp-rock brawl at 136 BPM: fuzzed slide guitar riff, stomping drums with washboard and tambourine, a droning jug bass, frantic fiddle and harmonica stabs over a roaring overdriven riff; loud, sweaty and dangerous, a seamless loop. |
