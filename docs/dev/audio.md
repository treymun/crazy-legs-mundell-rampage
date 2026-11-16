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
  its base in the list), `--check`. Then `tools/pack_assets.gd`.
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
