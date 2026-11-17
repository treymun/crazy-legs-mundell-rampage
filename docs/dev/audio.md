# Audio

The sound is made in `audio_src/` by the Python tools in `scripts/` (see
`audio_src/README.md` and `audio_src/DIRECTION.md`) and played by `src/sound.gd`
(`Sound`, behind `GameSound`). Nobody on the agent side can listen: every
decision here comes from measurement and from the code.

## Making and finishing

- `scripts/audio_spec.py` says what every cue is: `G` a paid recording, `D` a
  cue derived from another's recording (`room` tail, `event` another hit of it,
  `pitch` retuned, `bleep` the CLEAN copy), `V` a spoken line. Options a cue
  may carry: `keep` (seconds), `level` (dB, its loudest 50 ms), `punch` (the
  designed layers under a gun, seeded), `split` (the level that splits a
  recording into its hits for `event`), `like` (master to another cue's
  loudness: every take of a set comes out as loud as the first).
- `scripts/audio_build.py` finishes them (free, deterministic): `--sfx` all
  the effects, `--sfx --only <cues>` just those (a `room_`/`bleep` cue needs
  its base in the list), `--check`. Then `tools/pack_assets.gd`. A cue
  named after a chapter's enemy (`<kind>_...`, `boss_<kind>_...`) goes in
  that chapter's `sfx_<chapter>.bin` and its browser pack; the browser and
  phone builds play the music re-encoded at Vorbis q3 (`pack_lite.gd`,
  [checks.md](checks.md#the-browser-packs)).
- `level_to` brings a cue to its level under a -0.8 dB ceiling: a gentle knee
  up to 6 dB over, past that a look-ahead limiter (`limit_peaks`, at most
  `LIMIT_DB` 6 dB off the spikes) and then a plain scale. Very short spiky cues
  (a splat, a click) still land under their family's level: their loudest
  50 ms is the spike itself, so limiting it lowers both.
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
  `metal_down`) is in the bank or `Assets.MADE_CUES`.

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
  before levelling) and land at -10.4. Its older radio talk is unchanged.
- **BLUE.** His barks, bays, growls, bite, boof, yelps and whines are
  `hound_*` effects (`audio_spec.py` "the hound"; takes dealt by
  `Sound.VARIANTS`), the whistle `hound_whistle`; Mundell's words to him are
  his own `hound_*` lines (mundell_lines.json; `MUNDELL_SAY` spells "sic 'em"
  for the voice). Made in content pass 8 (about 520 credits).
- **Turns.** `Sound.talking()` is any spoken line (`Sound.SPEECH`) still
  playing; `hush_speech()` stops the ones playing as effects. A hand keeps
  quiet while anyone talks; Mundell's line is shown, not said; a boss's
  line hushes the rest and plays on the voice channel; its mad line (1.1 s
  after the roar) and Maw's crew calls queue until nobody talks (dropped
  after a few seconds); Mundell's answer to a boss's entrance or fall waits
  for the boss to finish (`enemy_barks.gd _mundell_after`). All of it is
  sound and captions, off its own dice; play is unchanged.
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
