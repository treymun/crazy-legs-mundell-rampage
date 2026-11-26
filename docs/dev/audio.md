# Audio

The sound is made in `audio_src/` by the Python tools in `scripts/` (see
`audio_src/README.md` and `audio_src/DIRECTION.md`) and played by `src/sound.gd`
(`Sound`, behind `GameSound`). Nobody on the agent side can listen: every
decision here comes from measurement and from the code.

## Making and finishing

- `scripts/audio_spec.py` says what every cue is: `G` a paid recording, `D` a
  cue derived from another's recording (`room` tail, `event` another hit of it,
  `pitch` retuned, `bleep` the CLEAN copy, `scuff` a step smeared into a
  boot's slide: `slide_scuff`, pass 15), `V` a spoken line. Options a cue
  may carry: `keep` (seconds), `level` (dB, its loudest 50 ms), `punch` (the
  designed layers under a gun, seeded), `split` (the level that splits a
  recording into its hits for `event`), `like` (master to another cue's
  loudness: every take of a set comes out as loud as the first).
- `scripts/audio_build.py` finishes them (free, deterministic): `--sfx` all
  the effects, `--sfx --only <cues>` just those (a `room_`/`bleep` cue needs
  its base in the list), `--check`. Then `tools/pack_assets.gd`. A cue
  named after a chapter's enemy (`<kind>_...`, `boss_<kind>_...`) goes in
  that chapter's `sfx_<chapter>.bin` and its browser pack (so does a
  chapter's own ambience, `Assets.CHAPTER_AMBIENCE`); the browser and
  phone builds play the music re-encoded at Vorbis q3 and every spoken line
  (the manifest's "voice" family) at mono Vorbis q1 (`pack_lite.gd`,
  [checks.md](checks.md#the-browser-packs)): listen to a line there with
  `--lite-assets` on a desktop.
- `level_to` brings a cue to its level under a -0.8 dB ceiling: a gentle knee
  up to 6 dB over, past that a look-ahead limiter (`limit_peaks`, at most
  `LIMIT_DB` 6 dB off the spikes) and then a plain scale. Very short spiky cues
  (a splat, a click) still land under their family's level: their loudest
  50 ms is the spike itself, so limiting it lowers both.
- Since pass 9: a cue still more than 3 dB under its level after that gets a
  second pass of the limiter (`DEEP_FROM`, families in `DEEP`: voices,
  creatures, breakage; a tool's click, a step and a gun keep their edge); a
  silence of more than 0.3 s at a cue's end is cut (`trim_tail`); a cue left
  off centre by its fades (over 2 % of its RMS) has it taken off under a
  bell; loops join at equal power (`seamless`, corrected for how alike the
  two passages are: the old equal-gain fade dipped 3 dB mid-join over a bed
  of noise, a pulse each time round); the tool loops cross over 0.3 s. A
  spoken line keeps everything up to its caption's last word (and 0.14 s on);
  every spoken line finishes at the voices' level, the oldest exchanges
  included. A CLEAN copy's duck call saturates at the line's peak instead of
  setting the whole line's level.
- `scripts/audio_qa.py` measures it all; see "Audio QA" below.
- `audio_build.py --layers` (pass 15, `scripts/audio_layers.py`, free) makes
  each chapter's fight loop's two layers (`audio_spec.LAYERS`,
  `LAYER_SHAPE`) from the finished loop on disk: `pulse_<chapter>` its drums
  and `peak_<chapter>` its riff ([the four levels](#the-fight-music-in-four-levels-pass-15)).
  A full `audio_build.py` (or `--music`) makes them again after the loops.
- Paid requests go only through `scripts/audio_generator.py` (ledger, ceiling;
  CLAUDE.md). It loads the key from `.env` at the repo root of the checkout it
  runs from.

## Playing

- **Takes and dice.** `Sound.VARIANTS` deals a cue's takes in turn (guns,
  steps: each foot keeps its own pair, hurt, ricochets). Every effect played
  through `play()` also gets its own pitch (within `PITCH_SPREAD`, 3.5 %) and
  level (`LEVEL_SPREAD`, 8 %) from Sound's own dice, never `game.rng`;
  warnings (timed to the attack), speech and menu sounds keep theirs
  (`STEADY_PREFIXES`).
- **Placing.** `game_world.gd` `sound_position` (volume, pan) and
  `sound_cutoff` (the voice bus's low-pass) ask `Game.hearing` (`hearing.gd`):
  distance counts the height between ear (`Player.eye`) and source past
  `HEIGHT_FREE`; on a level with geometry the sight test runs at their heights,
  so a deck between is a floor (`THROUGH_FLOOR_*`: .32, 800 Hz), a wall is
  `THROUGH_WALL_*` (.43, 1300 Hz, as before), and when the straight line is
  blocked but the listener's flow field says the way round is short (a
  doorway, a stairwell) it is `ROUND_*` (.72, 3600 Hz). A source's floor is the
  body's standing exactly at its x, y (most placed sounds are a body's), else
  the listener's own floor. Grid levels keep the flat sight test. One answer
  per place per tick is kept, so the pair of calls costs one test: about
  36 us a place headless against 22 before (`tools/sound_check.gd`).
- **Rooms.** `set_room` plays the ambience bed (`amb_<level ambience>`, or
  room / yard / an area's), `set_space` the world bus's reverb (`SPACES`);
  indoors a gun also plays its `room_` tail (`report`, `sound_at`).
- **Levels.** Every voice's level goes through `Sound.set_level` (read back
  with `level_of`): it reaches the mixer only when it moves `LEVEL_STEP` or
  to silence, and with no window (the checks, the lobby server) never for a
  playing voice; headless the bus effects (panners, filters, reverb,
  limiter) are added switched off (`_add_effect`). Each change of a playing
  voice's level makes Godot's mixer a record it frees a frame later, and that
  clean-up grows with the square of how many: a check that ticks minutes of
  play inside one frame (net_check, tactical_check, check_fixes) used to
  print OK and then keep a core busy for minutes on the next frame instead
  of quitting (40,000 changes cost 4 s a frame, the full net_check's never
  ended). Since 3.3.0 they quit at once.
- **Checks.** `tools/sound_check.gd` (in `check_fixes`): hearing open, round,
  through a wall and through a floor on Hickston; it costs little and changes
  nothing in play; every take VARIANTS deals and every cue the game names at
  run time (barks, boss lines, enemy cries, guns, floors, materials,
  `metal_down`) is in the bank or `Assets.MADE_CUES` (pass 15 added
  `head_ding`, a tin sign struck for a head hit: a click and three bright
  inharmonic plate modes ringing down, .38 s, played at .5 by
  `features/hit_reads.gd`).

## Doppler (pass 14)

What passes fast bends its pitch: up as it comes, down as it goes. `src/doppler.gd`
(`Doppler`, `sound.doppler`) holds the movers and the voices tied to them;
`src/mover_sounds.gd` (`MoverSounds`, the front end's `movers`) feeds it
each frame during the draw (main.gd `_mover_sounds`, between
`net_draw_begin` and `net_draw_end`), so every place is where it is drawn:
between ticks in single player (SoloBlend), online the others blended and
our own player predicted. Every number is `data/tuning/doppler.cfg`.

- **The sum.** pitch = base x (c - v_listener . n) / (c - v_source . n), n
  the way from the source to the listener, each speed times its family's
  `scale`. `base` is what Sound started the cue at (`PITCH_SPREAD`'s dice
  times an engine's `play_at_rate`), so the two multiply; a mover and a
  listener standing still give exactly the base. The listener's speed is
  its own drawn one, so riding in the car its own engine barely moves (0.01
  semitone at top speed, `doppler_check`) while a car going the other way
  passes at both speeds.
- **The numbers.** c (`sound_speed`) is 150 cells a second. Real sound is
  about 40 times a fast car; at 150 the stock car (top 13) comes in 1.57
  semitones up and goes away 1.44 down, a minor third in all, the size of a
  real car going by at about 100 km/h: heard, never a cartoon. At it: the airboat
  +1.0/-0.95, the mower +0.63/-0.61 (`scale` 1.5), the ripsaw's blade
  +1.8/-1.65, a crossbow bolt +1.3/-1.2, a bottle rocket +1.15/-1.07, the
  cow +1.0/-0.97, a bowling ball +0.88/-0.83, a carried thing thrown about
  +1.1/-1.05, a saucer +0.55/-0.53 (`scale` 3: they hover at 1.6 cells a
  second). Clamped at 3 semitones either way (`most_up`, `most_down`: only
  something past 30 cells a second reaches it); eased over 0.05 s (`ease`)
  and never faster than 30 semitones a second (`slew`): the steepest frame
  of a car passing 2 cells off moves 0.17 semitone at 60 frames a second.
- **Speeds** come from the drawn places frame to frame, followed over 0.06 s
  (`track`); a jump past 2 cells in one frame (`snap`) or faster than 45
  cells a second (`fastest`), a respawn, a seat taken, a new level, forgets
  the speed there instead of reading one from it: no spike (`doppler_check`).
- **What bends.** Only voices tied to a mover, and only cues of 0.45 s or
  more (`shortest`): a bottle rocket's 0.3 s whistle, a click, a shot keep
  their pitch. Tied: each ride's engine notes and tyre squeal
  (`vehicles.gd`, `Doppler.RIDE`, through `game.sound_from`), the speedway's
  race cars and the Moonshine Run's cruisers with their siren
  (`race_laps.gd`, `Doppler.LAP`), the swamp king's rev, charge and wake
  (`bayou_brains.gd`, `soundscape.gd`) and Bumper Boggs's rev into a charge
  (`derby_champ.gd`; both `Doppler.FOE`, `MoverSounds.FOES`), and the flight
  loops. A parked vehicle makes no sound, so it has nothing to bend.
  The pitch is the voice's own, so the same note heard through a wall or a
  floor (Hearing's muffle on its bus) bends by the same factor.
- **Flight loops.** The nearest three shots or carried things in the air
  within 14 cells each carry a loop on a bed of their own (`Sound.BED_FLY`
  and the two after it), placed as any sound is (`sound_position`,
  `sound_cutoff`, looked at again every 0.033 s; the pitch every frame), up
  over 0.06 s and down over 0.1 s where it burst or landed: `fly_rocket`
  (bottle rockets, flares), `fly_whoosh` (bolts, the blade, the cow, the
  dynamite, kegs, cocktails, jars, pots, cans, wrenches, footballs, bottles,
  a carried thing thrown; each at its own pitch, as loud as it is fast: none
  at 2 cells a second, all at 8), `fly_bowl` (a bowling ball's roll, a
  rolled tyre). The nearest saucer or probe within 11 cells hums
  (`saucer_hum`, `Sound.BED_HUM`). doppler.cfg `[fly]` names each shot's
  loop, level, pitch, family and whether it is a whoosh.
- **Off** (`on=false`) or a family's `scale=0` (`on=false` in its
  `[family.*]`): exactly the old pitch. Nothing here touches play: no dice,
  no tick, no snapshot (`doppler_check` plays the same run both ways to the
  same state, rng and snapshot). With the game held still under its own
  camera (PHOTO MODE, an opener, the KILL CAM), at the tally and out of play
  the loops are let go.
- **Made** 2026-11-24 (pass 14): the four loops, family `near`, style `fly`
  (`audio_spec.py`). `fly_bowl` took three takes: the first two were one
  ball going by (20 dB from end to middle), the third, asked as a steady
  bed, keeps its first steady 1.6 s (within about 8 dB; one soft knock a
  turn). 183 credits booked, 177 after the reconciles (79,184 to 79,361).
  73 KB in the first download (sfx.bin; 74.4 of 75 MB). Not listened to.

## Voice chat (online, pass 13)

The players' own voices online are not cues: `src/net/voice_chat.gd` plays
each talker through an `AudioStreamGenerator` on a bus of its own
(`voice_out_N`: a panner and a low-pass like a placed sound's), sent to
Master, outside the world's reverb, ducking nothing. Where it is heard from
uses the same `Hearing` as the game's sounds (through a wall .43 and 1300
Hz, a floor .32 and 800 Hz, round a corner .72 and 3600 Hz) and the same
pan as `sound_position` (STEREO WIDTH), with its own falloff (full within 3
cells, gone at 18: `data/tuning/voice.cfg`). The sound is 8 kHz IMA-ADPCM,
telephone band (VOICE QUALITY's CB 8K), or with CLEAR 16K (pass 14) a
second band of 4 to 6.5 kHz on top, played at 16 kHz. The mic is read from the muted `voice_mic` bus. The rest is
in [multiplayer.md](multiplayer.md#voice-chat-pass-13). Not heard by anyone
on the agent side.

## The fight music in four levels (pass 15)

Pass 15's audit found a chapter's fight loop playing 80 to 97 % of every
chapter: `fight_music.gd` was on/off, any hand on the player swelled the
loop in, it held 7 s, and a fight came every 8 to 12 s. Now there are four
levels (`features/fight_music.gd` decides, `src/score_layers.gd` plays):

- **CALM**: the chapter's track. **BUILD** (a hand on the player, or an
  alerted one within `NEAR` that sees or hunts him; held `BUILD_HOLD` 5 s):
  the track gives way (ScorePlayer's crossfade, in over 1 s, out over 3 s) to
  the fight loop's own drums alone. **FIGHT** (`CROWD` 4 hands on him, or one
  that hurt him within `HURT_HOT` 3 s, or the director's intensity
  `FIGHT_HEAT` .65 or more with a hand on him; held `HOLD` 10 s while a hand
  about is still awake and after him, `QUIET_HOLD` 5 s once none is, and
  dropped within `BREATHER_DROP` 1 s when the director calls a breather and
  nobody is on him): the whole loop. **PEAK** (a director's peak with a hand on him,
  or this machine's player on a RAMPAGE; held `PEAK_HOLD` 3 s): the loop with
  its riff laid over it. A hit landed only keeps the BUILD; the Crossroads
  is CALM. `fighting` (what `flow_report` counts as "fight loop %") is FIGHT
  or PEAK. The numbers are in `data/tuning/fight_music.cfg` (the balance
  step moved them there: with the director's bigger crowds two hands on him
  were most of the fighting and the whole loop played 59 to 67 % of the
  Moonshine Run, the Mothership and the bayou; `CROWD` 2 -> 4, `HOLD` 12 ->
  10, `HURT_HOT` 4 -> 3, `FIGHT_HEAT` .5 -> .65 took it under 60 %, see
  gameplay.md "Difficulty and pacing as numbers").
- **The layers** are free, made from each loop by `scripts/audio_layers.py`
  (`audio_build.py --layers`): the loop as a ring is split into its drums and
  its tune by median filtering its spectrogram (along time for what holds a
  note, along frequency for the hits; soft masks from the mono mix, so both
  sides part alike), the drums low-passed at 2 kHz with a little low shelf
  and held under -1.9 dB by a limiter run over the ring (`pulse_`, -18 LUFS,
  Vorbis q1), the tune high-passed at 650 Hz, lifted 2.5 dB at 2.8 kHz and
  driven a little (`peak_`, as loud as makes the loop and it together 2 LU
  over the loop, Vorbis q2). Every filter runs over the ring padded with
  itself, so nothing new happens at the join. Each decodes to exactly the
  loop's sample count (`audio_qa` and `music_check` hold it), and the fight
  player plays the three as one `AudioStreamSynchronized` (`stream_of`, the
  one call in sound.gd's `fight_step`): each layer's gain moves under the one
  stream (`step`, every tick: the loop in over .6 s and out over 2.5, the
  drums in over 1 and out over 1.2, the riff in over .5 and out over 2), so
  BUILD to FIGHT to PEAK never shifts a beat. While the fight player is
  silent the gains jump to the level asked for. A chapter whose layers are
  not in the packs (`layered`) plays its loop alone and keeps BUILD on the
  track. 7.3 MB in all, in each chapter's `music_<chapter>.bin`.
- **Measured** (nobody here can listen): the drums layer's strongest pitch
  class holds .12 to .15 of a frame's pitch energy against the loop's .15 to
  .21 (less tune in it) and its onsets follow the loop's at .68 to .91
  correlation; the riff layer's strongest pitch class is .18 to .30. Every
  join's step is under audio_qa's 4x limit (.01 to .37 of the loop's
  99.9th-percentile step); the drums layers peak at -3.2 to -1.6 dBTP, the
  loops with their riff 1.3 to 1.9 LU over the loops alone (their peaks
  -0.8 to -2.9 dBFS before the master limiter).
- `tools/music_check.gd` holds it; flow_report's music table shows each
  level's share ([gameplay.md](gameplay.md#rampage-pass-15) has the pass 15
  numbers).

**Listening, for the owner.** Play Hickston from the CROSSROADS gate with
MUSIC up and CHATTER on: walking in (no hand about) the chapter's song; as
the first coot spots you the song should give way, over about a second, to a
drums-only groove in the fight loop's tempo; take a hit or let two come and
the whole fight loop (banjo, fiddle, guitar) should join on the beat, with
no stumble; at a director peak (a station done, a new district: a crowd
comes with a holler) or on a RAMPAGE the riff should come up on top, a
little louder and brighter; after the peak's last kill (the breather) the
whole loop should drop back to the drums within a second or two and then to
the song. Listen at each change for a skipped beat, a doubled drum, a click
when the loop wraps (every 46 to 60 s) and for the drums alone sounding thin
or too loud against the song. `--lite-assets` hears the browser build's
copies.

## Voices

Every spoken line is a `V` cue: an ElevenLabs line in one of the designed
voices (`audio_src/voices.json`, all original characters; `eleven_multilingual_v2`,
stability .6, similarity .8, style .35, the same for every line so a voice
always sounds like itself).

- **Who says what.** Mundell (`mundell_lines.json` and his cuss lines,
  `barks.gd`); the bosses (`features/boss_voices.gd`: two entrances, four
  taunts, a mad line at half health, two worried lines, a last word; Maw's
  wake and crew calls, `mothership.gd`); the hands (`features/enemy_barks.gd`:
  eleven squad moments in five voices: hick for Hickston and the fair, local
  for the mill, quarry, fish camp and pits, deputy, coot, grey); each
  chapter's tough guy when he first sees you (`variants_feature.gd`
  `TOUGH_SAYS`, cue `bark_<kind>`); the radio talk (`talk_*`, dispatch); the
  announcer (`ann_*`, the 5v5 and the fair PA, `game.gd FAIR_PA`).
- **Making a line.** Write the caption in the game's table and the spec
  (`audio_spec.py`), then `audio_produce.py --only <cues>` (paid) and
  `audio_produce.py --transcribe` (paid, about a credit a line). The
  python running these needs `requirements.txt`'s elevenlabs and
  python-dotenv (the repo `.venv` may only have numpy; the system Python
  has them). `audio_build.py --sfx --only <cues> <cuss cues>_clean` cuts
  each line at its caption's words from the transcript, and refuses a line
  whose transcript does not say the caption. Where the transcript only
  spells the county's words or a name its own way, the line gets `heard`
  (`VOICE_HEARD`, `BOSS_HEARD`, `BARK_HEARD`, `CUSS_HEARD`, `MUNDELL_HEARD`);
  where it says something else, the line is made again (`--redo`, the old
  take kept as `.take<k>`; transcribe it again with
  `audio_produce.transcribe(name, True)`), or reworded.
- **Level.** Lines finish at -3 dB (loudest 50 ms) under the -0.8 dB
  ceiling. The local voice's plosives hit the ceiling first and left its
  shouts 2.5 dB under the others (speech RMS -13.0 against about -10.5):
  its barks, cuss lines and tough guys take `squash` 4 (their spikes limited
  before levelling) and land at -10.4. The older radio talk, kept at its
  placeholders' -9 dB until pass 9, now finishes at -3 dB like the rest.
- **BLUE.** His barks, bays, growls, bite, boof, yelps and whines are
  `hound_*` effects (`audio_spec.py` "the hound"; takes dealt by
  `Sound.VARIANTS`), the whistle `hound_whistle`; Mundell's words to him are
  his own `hound_*` lines (mundell_lines.json; `MUNDELL_SAY` spells "sic 'em"
  for the voice). Made in content pass 8 (about 520 credits).
  Pass 10 (2026-11-17): 23 more recordings (more takes of his bark, bay,
  yelp, boof and bite; a low warning growl, yips, a howl, panting, sniffing,
  a shake-off, a whimper, a sulky whine and huff), each later take mastered
  `like` the first of its set; `Sound.SHUFFLED` deals his sets at random
  instead of in turn, never the take just played (`hound_check`). Eleven
  more of Mundell's lines about him (`hound_down`, `hound_praise`,
  `hound_shot`, `hound_hush`, `hound_greet`, `hound_shine`): seven said
  their words (four with a word before them, "And", "Uh", "Yeah", which the
  cut leaves off), two only spelled them their own way ("That a boy",
  "hollering": MUNDELL_HEARD), "Hush, Blue" came back "Ha ha, Blue" and was
  reworded "Hush up, Blue", and "Blue! Outta my sights!" was heard as "Blow"
  and then "Blah, oh" and was reworded "Git outta my sights, Blue!" (heard
  "Get out of"). `hound_bite_alt` was made again (its first take a lone
  spike 11 dB under the family). The ledger went from 78,068 to 78,582: 849
  booked at its expected rates (effects 403, lines 278, transcripts 168),
  335 given back at the reconciles. Not listened to.
- **Turns.** `Sound.talking()` is any spoken line (`Sound.SPEECH`) still
  playing; `hush_speech()` stops the ones playing as effects. A hand keeps
  quiet while anyone talks; Mundell's line is shown, not said; a boss's
  line hushes the rest and plays on the voice channel; its mad line (1.1 s
  after the roar) and Maw's crew calls queue until nobody talks (dropped
  after a few seconds); Mundell's answer to a boss's entrance or fall waits
  for the boss to finish (`enemy_barks.gd _mundell_after`). All of it is
  sound and captions, off its own dice; play is unchanged.
- **Heard again (pass 10).** Until then none of the hands' squad barks, the
  bots' chatter, Mundell's word at a chapter's start, the bosses' entrance,
  worried and last lines, their taunts or Mundell's answers to them were
  ever played: `enemy_barks.gd` and `boss_voices.gd` looked for their
  signals on the game, which has had none since GameEvents. They listen on
  `game.events` now. With the hands talking again two lines came over them
  and now wait or cut in: the fall-back shout keeps quiet while anyone talks
  (`game_world.gd`), and a tough guy's piece cuts in as a boss's does
  (`variants_feature.gd`, `hush_speech`). Measured by `tools/bark_check.gd`
  (the balance bot at NORMAL, 4 minutes or to the chapter's end, god mode):
  the hands' lines a minute went from 0 to 6.0 (Hickston), 6.0 (the mill),
  5.2 (the quarry) and 6.0 (the bayou); Mundell's said aloud from 37, 31, 29
  and 26 to 23, 25, 20 and 22 (more of his are shown while a hand talks);
  never the same hand's line twice running, never one over another. Not
  listened to.
- **End stings.** A boss's end sting (`<kind>_end`, `shakedown_end`) used to
  be cut off the moment the boss loop handed back: `set_score` stopped any
  sting. It now stops one only for a score outside play's (the menus, the
  tally, `victory`); the boss ending holds the score under the sting
  ([bosses.md](bosses.md#the-boss-ending-pass-10)).
- **Checks.** `tools/voice_check.gd` (check_all, quick): every spoken line
  mastered from its transcript, its CLEAN copy, loading from the bank at
  0.3 to 6 s, every caption the game shows the words the line was made
  from, every recording, transcript and kept take booked and the ledger
  matching the account's drop at its last reconcile. `chatter_check` holds
  the turns. `county_dispatch_6` is a byte copy of a booked take of
  `county_dispatch_4` (voice_check `COPIED`).

### The pass 7 voice pass (2026-11-16)

172 new cues (150 lines and 22 CLEAN copies): the bosses 43 (5 each and
Maw's 3), the hands 66 (11 for each old voice, 22 for the new local one),
the local cuss lines 22, the tough guys 7, the fair PA 3, Mundell 9. 150
first takes; 119 matched their captions as made, 17 more only spelled the
county's words or a name their own way (`heard`), 12 said something else and
were made again (the swamp king's "cher" heard as "Sheriff" was reworded to
"boy"). Of those, 9 came back right, one only spelled "plumb" as "plum", and
two missed again and were reworded ("Hidey-hole!" heard as "Tidy hole", "I
need a hand" as "a hint"): 164 recordings for 150 lines. Measured against the 347
older lines: median 1.81 s (older 1.65), speech rate 11.4 letters a second
(10.9), every peak at -0.8 dB. The ledger booked 68,459 before and 68,447
after its reconcile: the account's own counter rose 2,642 credits from the
reconcile of 2026-11-13 to the end of this pass, for this pass and 184
earlier requests booked at their expected cost but never reconciled. Not
listened to: the owner should hear the local voice's barks (a slower, lower
voice than the hicks', and the longest barks at about 2 s) and the grey's
new lines in game.

### The Moonshine Run (content pass 8)

A designed voice for the Revenue Man ("revenue_man": a big, cold, clipped
federal lawman, nobody real) and his ten lines; the tough guy Hoss in the
deputy's voice; the dispatch's line for the Crossroads board (`county_dispatch_8`,
its place in `GameState.HUB_DISPATCH_CUES`); three radio exchanges. Effects: the
Revenue Man's warn, rage, pain, down, death, entrance and end stings, Little
Bethel's bell, a cruiser siren and the ridge's night bed (`amb_ridge`, the
level's ambience). Music: `moonshine_score`, `fight_moonshine`,
`boss_moonshine` (`music_moonshine.bin`). Not listened to.

### Pass 8: Mundell on finishers and hazards (2026-11-16)

Ten lines in his voice (barks.gd and mundell_lines.json `finisher`,
`hazard`; cues `mundell_finisher_0..4`, `mundell_hazard_0..4`), spoken over
his kill line after a finisher or a hazard kill. Seven matched as made; "ya
varmint" came back "you varmints" and "watch yer step" came back with ", son"
(both captions reworded to the take, `heard` in MUNDELL_HEARD); "He had that
comin'" was heard as "comments" and was reworded to "He was askin' fer that"
(one more take). About 400 credits (264 voice, 132 transcripts). Not
listened to.

### The chapter openers' storyteller (content pass 8)

A designed voice, "narrator": a weathered old Ozark storyteller on a porch
at dusk, slow, deep and dusty, an original character. Two lines a chapter
(`narr_<chapter>_0`, `_1`, words in `data/tuning/openers.json`, read by
`audio_spec.py` and the game; `src/opener.gd`), dry, at the voices' level.
Made 2026-11-17: 16 first takes, all said their words; three only spelled
them their own way ("Hixton" twice, "47": `NARRATOR_HEARD`). Lines last 2.4
to 4.5 s. Each opener's music is a `sting` cue `sting_open_<chapter>` (8 s,
the chapter's band and instruments, building to a last chord); the boss
teaser reuses each boss's growl (`<kind>_rage`), entrance sting and a line
of its own. About 2,280 credits at the ledger's expected rates (voice design
537, lines 833, stings 712, transcripts 192). Not listened to.

### The openers' sound (pass 10)

The owner: the openers were "silent half the time". Measured on v3.7.0 (each
opener rendered offline from its schedule at the default levels): 1.9 to
3.65 s of dead air an opener (momentary loudness under -45 LUFS; longest 3.15
s, the fair), and 5.4 to 8.0 s with no music at all (the 8 s sting gone by 7
s, nothing till the boss's sting); the storyteller sat only 2 to 7 LU over
the sting under his first line.

- **The bed** (`src/opener_mix.gd`, numbers in openers.json `mix`): the
  chapter's own song (the first of its score's tracks, or its `song`) from
  its top, played by the score player as the chapter's score
  (`Sound.opener_bed`, `ScorePlayer.cue_song`), so it is thematically the
  chapter's and hands off with no gap and no second song: at the end its
  hold is simply 1 and it goes on into play. Its hold (`set_opener_hold`, a
  share of MUSIC VOLUME, multiplied into `_apply_music` with the other holds)
  follows `mix.bed`: .6 at the start, a swell to 1 as the card lands, .85
  between, 1.2 into the boss's reveal, a dip to .35 under the boss's own sting
  (played at `sting_gain` .6 in an opener), .7 at the landing, 1 at the end.
  The songs' quiet intros make it an underscore under the narrator, the band
  coming in about the reveal. The pass 8 `sting_open_<chapter>` plays only
  when the song is not there (a browser pack still coming).
- **Ducking**: pass 9's music duck (`_music_duck`, `_radio_levels`): under an
  opener the music, and the boss's sting, go down to `VOICE_DUCK` .5 while
  the voice channel speaks (down at `DUCK_DOWN` 6 a second, about a tenth of
  a second, back at `DUCK_UP` 2.5, Dub's old rate); the room's ambience sits
  at `OPENER_AMB` .5 of its level (and the rain at half) until the opener
  ends, then eases up over 1.3 s.
- **Ambience and spots**: under each shot its `amb` (else the level's own,
  else the yard); the level's rain where it rains; each of the level's
  distant cues once as the flight passes nearest it, placed from the camera;
  a shot's `spots` (Hickston's far truck and a cow, the speedway's crowd and
  a passing car, the beam's hum and the core on the Mothership, a far
  cruiser's siren at the Revenue Man's checkpoint...); a whoosh at each cut
  and at the landing (`opener_whoosh`, `_alt`), a low swell into the reveal
  (`opener_reveal`, its boom on the moment), and each card landing with its
  own hit (`opener_<chapter>_hit`, timed by its `hit_lead`). Skipped, the
  opener's own effects stop, the duck lets go and the bed rises to play's
  level over 0.4 s.
- **Packs**: `opener_<chapter>_...` cues go with the chapter's pack
  (`Assets.chapter_of`); Hickston's (its hit, the truck), the whooshes and the
  reveal are in the first download (about 0.3 MB of effects; the bed is a song
  already there).
- **Made** 2026-11-17: 12 effects (two whooshes, the reveal, eight hits, the
  truck), each first take kept; 269 credits booked at expected rates (the
  account's counter, shared with another track generating at the same time,
  booked 502 more at reconcile). The Mothership's hit is levelled to -8.5 dB
  (it sat 5.6 dB over the impacts); the quarry's tin hit keeps a 2.2 dBTP
  between-sample peak (`qa_allow`).
- **Measured after** (same rendering): no dead air in any opener, music under
  every moment of every one (Hickston's song opens with 0.55 s near
  silence, under the ambience), each storyteller line 9 to 21 LU over
  everything under it and each boss line 10 to 17 LU. Not listened to: the
  owner should hear whether the bed's swells feel right, whether the hits
  suit the cards, and the hand-off as play starts.

## The county radio (content pass 8)

KPSM, fourteen-ninety AM, the Possum: Dub Tillery, a gravel-voiced
late-night jock (voice `dj`, designed for it, an original character), talks
between the cowpunk songs, and the county's police scanner (the `dispatch`
voice) calls in Mundell's trouble. `src/radio_station.gd` (`RadioStation`,
one per machine, kept by Sound as `sound.station` so it remembers the night
across chapters and retries) decides what is said and when, with its own
dice; `features/radio.gd` (a looks feature) tells it the news and where the
sets are, and captions it; the words are `data/tuning/radio_lines.json`.

- **Between songs.** When a chapter's song ends, ScorePlayer asks the station
  once (`take_break`); a break holds the next song until it is over: a beat,
  an ID, the talk (news first: a boss's fall, a blast, a wreck, a rampage, a
  rough night of deaths, drunk, a secret; else the weather, an ad for a county
  business or a county bit, sometimes an ad as well), the way back to the
  band. With no news Dub lets about a third of the gaps go. A fight ends a
  break early; a boss fight (`fight_music.boss_fight`) starts none. Lines are
  dealt from a shuffled bag per group, never the one just said across a new
  deal: 5 IDs x 5 ways back x 7 ads and so on. News is stale after 10
  minutes, a topic told waits 7 before it is news again; three deaths in 15
  minutes make a rough night.
- **The scanner.** Shots fired in a fight, a blast, a car burnt out, a
  rampage, a deputy down: the key-up (`scan_squelch`), sometimes "all units",
  the call, the units sent to the chapter's place (`place_<chapter>`), a word
  on the suspect, the key-down. One call of a kind in 45 s, any two 16 s
  apart; a call waits up to 8 s for nobody to be talking. Faint everywhere
  (`SCAN_FAINT`, through a 3.2 kHz muffle), louder in a vehicle and by a set.
- **Sets.** The nearest within 9 cells: a jukebox (one with a switch only
  while playing), a radio on a desk (a level's `*radio*` exchange or
  picture), the Crossroads' dispatch board, a ready vehicle's radio. Near
  one, Dub leans to its side and the scanner comes from it, by
  `sound_position` and `sound_cutoff`. Taking a vehicle tunes its set in
  (`radio_tune`) and now and then Dub says one for the road over the music.
- **Turns.** Dub and the scanner are on two voices of their own, outside the
  world's reverb and outside `talking()` (the hands do not wait for the
  radio). Anyone talking ducks both to `RADIO_DUCK`; a boss's line
  (`hush_speech`) and pausing (`pause_world`) hush them; Dub talking over
  the music (not in a break) brings it down to `MUSIC_UNDER_DJ`.
- **RADIO** (SOUND page): DJ + MUSIC (0), MUSIC ONLY (no talk, no scanner),
  OFF (the sets are hushed too: jukeboxes, the vehicles' radios). Per
  machine, never in a lobby's settings; off in the 5v5 rounds. Its levels
  follow VOICE VOLUME. Captions (VOICE CAPTIONS) say "KPSM: ..." for Dub and
  "SCANNER: ..." when a set or a vehicle is near, only when no other caption
  is up.
- **Crude lines.** Dub's `cuss_dj_<topic>_0` (four) are told now and then
  under CUSSIN', their CLEAN copies under CLEAN (#@!% in the caption), never
  with CHATTER OFF.
- **Made** (2026-11-16): 54 lines of Dub's, 4 crude (and 4 CLEAN copies), 26
  scanner pieces, the set's click and the squelch. 86 first takes: 78
  matched, 4 only spelled the county's words or numbers their own way
  (`RADIO_HEARD`), 2 said the caption a little otherwise and were captioned
  as said (`RADIO_SAID`), 2 lost their last word twice ("band", "units")
  and were reworded. The `am` speaker box (150 to 5,200 Hz, a little drive
  and hiss) is warmer than the two-way `radio` the scanner uses. Lines last
  0.9 to 6.0 s; Dub's loudest 50 ms sit at -5.1 dB (median), as loud as
  Mundell's and the bosses'. The ledger booked 6,492 credits at expected
  rates; the account's own counter fell 2,437. Not listened to.
- `tools/radio_check.gd` (check_all, quick) holds it.

### Pass 12: Mundell with the new player's tips (2026-11-18)

Five lines in his voice, said once each with a tip (`tip_hound`,
`tip_carry`, `tip_ride`, `tip_bench`, `tip_locked` in barks.gd and
mundell_lines.json; cues `mundell_tip_*_0`). Three matched as made; "If it
ain't nailed down, chuck it" came back with a "huh?" after it and "Duct tape
fixes everything" with a "Yeah," before it (both cut off at the caption's
words by audio_build); "Locked tight. Figures." was heard "Lock tight,
figures" (`heard`). 70 credits (79,114 to 79,184). Not listened to.

### Pass 15: Mundell's RAMPAGE hollers (2026-11-25)

Six lines in his voice as a RAMPAGE begins (`rampage` in barks.gd and
mundell_lines.json; cues `mundell_rampage_0..5`, forced past the kill line):
"Look out, the Legs is loose!", "Y'all done woke up the Legs!", "Meaner than
a wet bobcat!", "Fixin' to paint the barn red!", "Git outta the road, I'm
comin' through!", "Hide the hogs and the moonshine!". Five matched as made;
the first, written "Whoo-wee! The Legs is loose!", came back heard "Go away,
the legs is loose" and was reworded and made again (its first take kept as
`.take1`). 2.1 to 3.1 s each. 98 credits after the reconcile (79,361 to
79,459). The meter-full sting is a made cue (`assets.gd` `rampage_sting`: a
barn door's slam and an overdriven twang chord raked up three steps). Not
listened to.

### Pass 15: Mundell turned around (2026-11-25)

Four lines in his voice, said once a stuck spell (`src/hound_lead.gd`;
barks.gd and mundell_lines.json `lost`, `lost_pin`; cues `mundell_lost_0`,
`_1`, `mundell_lost_pin_0`, `_1`): with BLUE showing the way "Blue knows
the way." and "Foller the hound, dummy.", with HOUND DOG off and the pin
pulsing "Turned around again. Mind the arrow." and "I know these parts.
Mostly." Three matched as made ("Yeah," before the first, cut off at the
caption's words); "Foller" was heard "Follow" (`MUNDELL_HEARD`). 154
credits booked at the expected rates (106 for the takes, 48 for the
transcripts); the account's own counter dropped 51 past the RAMPAGE hollers
above (79,459 to 79,510), and the reconcile of the merged ledger gives the
rest back: both tracks together 149 (79,361 to 79,510). Not listened to.

## The county events' sounds (content pass 8)

The county events ([gameplay.md](gameplay.md#county-events-content-pass-8),
`features/event_looks.gd`): `tornado_siren` (family `distant`, a hand-cranked
civil defence siren far off), `tornado_roar` and `hog_stampede` (`near`
loops on their own bed, `Sound.BED_EVENT`, the fifth: the roar by how near and
strong the twister is, muffled under a roof; the hooves at the herd's
middle), `hog_squeal` (`alert`), `raid_siren`, `power_down`, `power_up` and
`breaker_throw` (`scene`), `torch_click` (`equip`); prompts in
`audio_spec.py` (style `event`). Nine of Mundell's lines (`event_*` in
mundell_lines.json), four scanner calls (`scan_twister`, `scan_hogs`,
`scan_raid`, `scan_outage`), two of Dub's bulletins over the music
(`dj_bulletin_twister`, `dj_bulletin_outage`, `RadioStation.bulletin`) and
four of his words at a break (`dj_twister`, `dj_hogs`, `dj_raid`,
`dj_outage`; news topics in `PRIORITY` after a boss's fall). Made
2026-11-16: 9 effects and 19 lines; 13 lines matched as made, 3 only spelled
a word their own way (`heard`: "Sooie" written "Zoe", "lawnmower", "cow's"),
3 said something else ("Feds. Figures." came back as a jingle, "Power's out"
as "Failures out", "at a still" with an "uh") and were reworded and made
again (one of those then heard "man" for "men"). About 1,330 credits at the
ledger's expected rates. Not listened to.

## Blasts and wrecks (destruction pass 11)

`fuel_whoomp` (family `boom`: a fuel fireball rolling up, layered under a
fuel, drum, propane, gas can, still or wreck blast's own cue by
blast_looks.cfg `layer`), `blast_debris` (`impact`: what a big blast threw
raining down, `debris_after` later), `wreck_crash` (`boom`: a vehicle blown
apart by its tank) and `wreck_pop` (`impact`: a burning wreck's pops).
Prompts in `audio_spec.py`; made 2026-11-18, one take each, about 85
credits at the ledger's expected rates. Not listened to.

## Audio QA (pass 9)

`scripts/audio_qa.py` (free, numpy; ffmpeg for the songs) measures every
finished cue in `audio_src/final/sfx` and every song in `godot/assets/music`:
EBU R128 loudness (K-weighted and gated; a cue under 0.4 s gets the level of
the whole of it), true peak (4x), the loudest 50 ms; each cue against the
median of its group (its family, or a spoken line's voice and speaker box: 5
dB, 4 LU for voices); clipping, DC, a click at either end, silence before
or after, a long cue stopped mid-sound under a short fade, a spoken line
shorter than its caption's words (from its transcript), a loop's join (the
step across it against the steps inside, its last 100 ms against its first
against the biggest change inside), two takes of a VARIANTS set that are one
recording; every cue the game names in a literal made, every cue named
somewhere in the game's code or data. `--check` fails on any finding not in
`audio_src/qa_allow.json` (cue -> start of the finding -> why) and on an
allowance no longer needed; `--json <file>` writes every number. It runs in
check_all's `lint` and in CI's lint job. `tools/audio_qa_check.gd`
(check_all, quick) holds the wiring headless: every literal cue made, clean
ends and loop joins, every CLEAN copy within 2 dB of its cussing take, the
music's holds stacking, no bark said twice running.

What pass 9 found and did (2026-11-17, measured, not heard):

- **Silent moments.** `honk` (a vehicle run's start), `impact_stone` (the
  Revenue Man's axe in the rock, the ship's boulders) and `step_water` (the
  swamp king's wave) were named and never made. `honk` is a new recording
  (booked 12 credits), `impact_stone` `impact_brick` a minor third down, the wave
  plays `wade_splash`. `church_bell` and `cruiser_siren`, made for the
  Moonshine Run, were never played: the church's bell station rang the fair's
  bell (now `church_bell`, moonshine_plan.gd), and a cruiser coming round
  fresh now wails its siren (race_laps.gd; the pass timer is unchanged).
- **The music's holds.** game.gd sets the music's level every tick (a blast,
  a caption up); that set it outright, so a jukebox or a truck's radio and
  Dub talking over a song held the music down for one tick only. Sound now
  keeps play's hold as a share (`_game_music`) and every hold multiplies
  (`_apply_music`); the menus drop play's.
- **Barks.** With two or three lines a moment the hands said the same line
  twice running a third to half the time; `enemy_barks._fresh` deals the next
  one instead (no extra dice).
- **Levels.** 114 cues sat 6 to 17 dB under their mastering level (spiky
  cues the 6 dB limiter could not lift). After the second pass the spread
  (10th to 90th percentile) of the voices fell: Mundell 3.4 to 2.5 LU, the
  hicks 5.0 to 3.5, the coot 4.3 to 2.6, the local voice 5.0 to 2.8, the grey
  5.2 to 3.4, every spoken line 4.9 to 3.6; breakage (`scene`) 10.1 to 7.1
  dB, impacts 8.2 to 6.3. The 21
  oldest exchanges (`talk_*` of 3.0.0 and `county_dispatch_*`) kept their
  placeholders' -9 dB and sat 3 LU (median) under the rest, the SOUND page's
  voice sample (`talk_tow-radio_1`) among them; now at the voices' level.
  CLEAN copies: up to 8 LU (median 1.2) under their cussing takes, now within
  1.4 dB.
- **Defects.** 74 spoken lines were cut before their last word (their soft
  last consonant fell under the build's hit floor; `bark_grey_cover_0` lost
  0.7 s): all whole now. 13 lines' last takes had never been transcribed
  (their transcripts were the takes before, so the cut and the check used the
  wrong words): transcribed (booked 156; the account fell 24 for the pass
  in all), all say their captions;
  `bark_grey_cover_0` loses its `heard`, `bark_grey_surprised_0` keeps its
  "Eep!" (`lead`, BARK_LEAD). `fuse_hiss` pulsed 3.3 dB at its 1.4 s join,
  now under 1.1; 29 cues held 0.45 to 1.4 s of silence at the end; six were
  off centre.
- **Music.** All 38 songs -15.0 +- 0.3 LUFS (tickets_after_dark and victory
  -14.7), true peak -0.8 dBTP or under, fight and boss loops join cleanly;
  unchanged. In game a spoken line (about -10 LUFS at VOICE .8, -3 dB) sits
  about 9 LU over the music (-15 LUFS at MUSIC .5, -7 dB) before any duck.
- **Accepted** (qa_allow.json): 21 cues whose true peak is 1.5 to 3.4 dBTP
  (hard edges between samples; played at .82 or less into the master
  limiter); clicks, crackles and splats under their family (the spike is the
  loudness); levels kept from the cues the mix was balanced on (the wood
  steps, the dry clicks of the belt-fed and the BAR, `amb_room`).

## The 3.0.0 remaster pass (measured, not heard)

- Loudness of all 993 effects (loudest 50 ms, peak; EBU R128 for cues of 1 s
  and more) and 35 songs (R128) measured with the build's own functions. The
  music was already even: every song -15.0 +- 0.3 LUFS, true peak -0.8 dB or
  under; nothing redone. Effects that sat 5 dB or more off their family's
  median went from 68 to 43: the limiter above; the twelve `room_` tails of
  the later guns, which had no older cue and took -10 dB (2 to 6 dB under
  their own shot where the first thirty sit 7 to 13 under), now -16 like the
  rest; the CLEAN cuss copies, which peaked at -0.3 dB, under the ceiling.
  The rest are short spiky cues (above) or levels kept from the cues the mix
  was balanced on (`assets/wav`).
- New takes, made from the guns' own recordings (retuned, new `punch` seed):
  shotgun, tommy, grease gun, patrol bar (two each), County .45, riot pump,
  .357, hogleg, hunter, marksman (one each). Steps: each step recording holds
  four footfalls and the game used two; now all four. Grass and water split
  at -20 / -16 dB (`STEP_SPLIT`): before, their `_0` and `_1` were one step.
- `metal_down` was played in seven places (metal gibs, tin guards, Jerry's
  scoreboard, propane tanks and fuel drums) and never made: now made from
  `scenery_scrap` a fourth lower.
- The speedway had no bed and fell back on the yard's crickets; it now uses
  the range maps' far-off crowd (`amb_range`).
- **Wanted from a paid pass** (none was made in 3.0.0: the key was not
  reachable from the remaster's checkout): other recordings of the busiest
  single-take cues (the enemies' three guns, `impact_wood`/`dirt`/`plaster`/
  `brick`, `body_thud`, `gib_splat`, the `actor_*` cries, `pickup`, `door`,
  `gate`, `explosion`), a real `metal_down`, and `amb_speedway`. The runtime
  pitch and level dice already vary them.
