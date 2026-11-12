# Sounds the impacts and the gun's feel could use

**Made in 2.0.0-dev.32** (ElevenLabs, through the budget ledger; spec in
`scripts/audio_spec.py`, the block after the range). Where each plays is
listed below; nobody has listened to them yet.

Listed by the impacts and feel pass (ricochets and penetration, smoke, dust
and embers, marks that stay, the gun and view on springs). `src/materials.gd` CUES picks a strike's sound
by what was struck; steel's long whine plays one round in three
(`Sound.VARIANTS`). The last column was the stand-in before.

| Cue | When it plays | Before |
| --- | --- | --- |
| `ricochet_tin` | A round strikes sheet tin, a trailer or a garage door: a thin, bright ping | `ricochet` |
| `ricochet_whine` | A round glances off steel plate, the Mothership's hull or iron: the long whine | `ricochet` |
| `impact_brick` | A round strikes brick: a dry crack and a patter of grit | `impact_plaster` |
| `impact_glass` | A round cracks a window tile without breaking it out: a sharp tick and a tinkle | `impact_plaster` |
| `impact_brush` | A round tears through corn, hedge or reeds: a rustling thwip | `impact_dirt` |
| `impact_mesh` | A round strikes a wire fence: a twang | `ricochet` |
| `impact_rubber` | A round thumps into a tyre wall: a dull thud | `impact_dirt` |
| `pierce_plank` | A rifle round goes through a plank wall (penetration.gd `pierced`): a splintering crack on the far side | none |
| `glass_settle` | Glass chips landing after a pane goes (the glints in impacts.gd) | none |
| `ember_crackle` | A soft loop near a burn barrel, a still's firebox or a grill while embers lift off it (features/dust.gd) | none |
| `land_thump` | The player lands from a jump or a drop (the view's dip in features/feel.gd); the step cue plays today | `step_<surface>` |
| `blow_grunt` | A light blow that staggers the view without a death in it; `hurt` plays today | `hurt` |
