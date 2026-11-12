# Sounds wanted for breaking things and loose physics

**Made in 2.0.0-dev.32** (ElevenLabs, through the budget ledger; spec in
`scripts/audio_spec.py`, the block after the range). Where each plays is
listed below; nobody has listened to them yet.

The last column was the stand-in before; breakables.cfg now names the made
cues (`cue`, `cue2`, and `chip` for a shot that does not break it).

| Cue | What it is | Stand-in before |
| --- | --- | --- |
| `break_crate` | A wooden crate or pallet stove in: a dry crack and boards clattering down | `impact_wood` + `scenery_scrap` |
| `break_barrel` | An oak barrel staved in, hoop ringing as it drops | `impact_wood` + `scenery_scrap` |
| `break_mash` | The mash barrel split: a wet slosh after the crack | `impact_wood` + `splat` |
| `break_jugs` | Clay moonshine jugs shattering, several at once | `tosser_glass` + `glass_break` |
| `break_jar` | A big specimen jar or the cow tube bursting, brine pouring out | `glass_break` / `window_smash` + `splat` |
| `break_cooler` | A plastic cooler cracking, lid clattering, cans rolling | `can_kick` + `scenery_cans` |
| `break_tin` | Tin mailboxes and cans shot off, rattling down | `scenery_cans` |
| `break_flamingo` | A plastic lawn flamingo knocked over: hollow plastic clack | `can_kick` |
| `break_stuffing` | A plush prize bear or hay bale bursting: a soft thump, straw and fluff | `scenery_prize` |
| `balloon_pop` | Balloons popping in a quick ragged run | `rocket_pop` |
| `alien_crate_break` | An alien cargo pod bursting: metal buckle and a wet squelch | `metal_down` + `splat` |
| `fuse_hiss` (made as `fuse_short`: `fuse_hiss` is the dynamite's own loop) | The short hiss before a shot barrel, tank or crate goes up (a tenth to a quarter of a second) | none (silent) |
| `sign_shot` | A painted wooden sign taking a round: a sharp wooden knock | `impact_wood` |
| `debris_settle` | Small bits (splinters, shards, tin) landing and settling | none (silent) |
| `body_thud` | A body hitting the ground or a wall after being knocked back | none (the death cry covers it) |
| `bowling_thud` | A bowling ball striking a wall and rolling on (code: `game_combat.gd _roll`) | `impact_wood` |
| `tnt_roll` | A stick of dynamite rolling on boards or deck plate (code: `game_combat.gd _roll`) | `tnt_bounce` on each knock |
| `break_window` | A window painted on a building shot out: a pane bursting and glass raining down the wall (breakables.cfg `[windows]` cue, `features/wall_breaks.gd`) | `window_smash` + `glass_break` |
| `break_fence` | A plank fence cell broken through: boards cracking and splintering, a rail dropping (breakables.cfg `[fence.stockyard]` cue) | `impact_wood` + `scenery_scrap` |
