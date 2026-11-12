# Sounds the quest props could use

Made (audio pass, 2026-11-11): `chain_rattle` (a locked exit or Crossroads
gate) and `lever_clunk` (the default station cue); keys and the patch lead
play the existing `key_pickup`.

Listed by the quest props pass (stations, exits, gates, keys and the patch
lead). None of these were generated: the main session decides whether to
spend ElevenLabs credits on them, or to make them in `assets.gd` MADE_CUES.

| Cue | When it plays | Why it would help |
| --- | --- | --- |
| `chain_rattle` | USE on an exit that is still locked (`EXIT LOCKED`), or on a locked Crossroads gate | The exit signal post's barrier arm and the gate barricade show a chain and padlock; today the press plays `empty` (a dry click), which sounds like a gun, not a lock |
| `lever_clunk` | A station's lever is thrown (the stations that use the default `menu_accept` cue) | The modelled control boxes, relay cabinet and brake show a big lever that is thrown and tagged; a heavy clunk would sell it. Stations with their own cue (`mill_isolate`, `scenery_scrap`, `scenery_pipe`) keep theirs |
| `pickup_key` | A key or the patch lead is picked up | They have no sound of their own; a jingle would mark the objective step |
