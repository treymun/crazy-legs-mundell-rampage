# Sounds the new looks want (not made yet)

The graphics-card view's weather, water and shimmer (palette.gdshader,
features/weather.gd, features/water.gd, effects.cfg) are silent apart from the
thunder that was already there. No sound was generated for them: these are
the sounds they would want, for the owner to decide on. Every one would be
original, in the Redneck Rampage spirit (close, dry, a little rough), and
none needs the ElevenLabs budget if it can be made in `assets.gd` MADE_CUES.

## Weather

| Cue | What | Where it would play |
| --- | --- | --- |
| `rain_loop` | A steady rain on dirt, tin and truck hoods, loopable (20 to 30 s), no thunder in it | Hickston and the mill all chapter (effects.cfg `rain`), the bayou during a shower; its volume follows `weather.rain` |
| `rain_roof` | The same rain heard from under a tin roof: a drumming, muffled | While the player stands where `open_sky` is false in a rainy chapter |
| `rain_gutter` | Water running off an eave into a puddle, a short loop | Optional, near buildings in the rain |

## Water

| Cue | What | Where it would play |
| --- | --- | --- |
| `wade_splash` | A heavier slosh as a body steps into water (the big ring) | `features/water.gd` when a body steps in (`ring(..., size * 1.6)`) |
| `drip_small` | Single drips into still water, three or four takes | A body standing in water (the drip rings), quiet |
| `airboat_wake` | The hiss and slap of the king's wake behind the engine | Under the airboat while it runs, beside its existing engine cues |
| `rain_on_water` | Rain hissing on open water, a loop | Mixed into `rain_loop` near [water] floors |

The wading footsteps themselves already exist (`step_water_0`, `step_water_1`).

## Heat

| Cue | What | Where it would play |
| --- | --- | --- |
| `fire_crackle` | A burn barrel's crackle and pop, a loop | At each burn barrel and grill (effects.cfg `burn_barrel`, `grill`) |
| `still_bubble` | A moonshine still's low bubble and tick of hot copper | At each still (`still`) |
| `generator_hum` | A small gas generator's putter, a loop | At each generator (`generator`) |
| `core_thrum` | A deep, slow alien thrum | Round the Mothership's core (effects.cfg `heat` on `[level.mothership]`) |
