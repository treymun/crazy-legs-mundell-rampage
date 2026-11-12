# Firing range: sound wanted

Made (audio pass, 2026-11-11): all twelve cues (the crowd bed as `amb_range`,
the range's ambience) and swapped in. The range keeps Hickston's score; a boss
in the corral now brings Hickston's boss loop.

Mundell's Proving Grounds (the FIRING RANGE off the title screen) runs on
existing cues for now. These are the ones it should get; the main session
makes them (one generation process at a time). Family is the first argument
of `add()` in `scripts/audio_spec.py`. When a cue lands, swap it in where the
"uses now" column says (`src/range_targets.gd`, `src/features/firing_range.gd`).

| Cue | Family | Prompt (one line) | Length | Uses now |
| --- | --- | --- | --- | --- |
| `range_gong` | impact | A steel gong target struck by a rifle bullet at 20 yards: bright metallic clang ringing out, outdoors. | 1.4 s | `ricochet` |
| `range_board_hit` | impact | A bullet punching through a plywood bullseye target on a wooden stand: dry crack and a wobble of the stand. | 0.5 s | `impact_wood` |
| `range_dummy_thwack` | melee | A crowbar thwacking a straw-stuffed feed-sack dummy: dull burlap thump with straw rustle. | 0.5 s | `impact_plaster` |
| `range_pin_scatter` | impact | Bowling pins scattering on a wooden lane, a full strike: hollow wooden clatter. | 1.2 s | `can_kick` per pin |
| `range_strike` | ui | A county-fair bell and a short brass "ta-da" for a bowling strike, cheerful and cheap. | 1.5 s | `yee_haw` |
| `range_gallery_ding` | ui | A tin shooting-gallery duck knocked flat: a high tin ping and a spring clack. | 0.4 s | `ricochet` |
| `range_gallery_buzzer` | ui | An old carnival game buzzer ending the round: a rattly electric buzz. | 1.0 s | `stamp_thud` |
| `range_lever` | station | A heavy iron release lever thrown on a fence-post switch box: clunk and ratchet. | 0.6 s | `menu_accept` (station cue) |
| `range_pen_gate` | door | A wooden livestock pen gate banging open on its chain. | 0.8 s | `gate` |
| `range_pa_hot` | voice | A drawling county PA announcer, slightly distorted: "The range is hot. Keep it pointed downrange, y'hear." | 3.5 s | none |
| `range_pa_medic` | voice | The same PA announcer, bored: "Medic to the firing line. Again." | 2.5 s | none (message only) |
| `range_crowd` | ambience | A thin county-fair crowd at dusk far off: murmur, a distant calliope, crickets, the odd whoop. Loopable. | 20 s loop | the range has no ambience of its own |

Music: the range uses Hickston's score (`music`, with its fight loop). If it
should have its own track: "A rowdy 1997 PC game redneck shooting-range tune:
twangy electric guitar riff over slapped upright bass and a steady train-beat
snare, a honky-tonk piano answering, banjo rolls on the turnarounds; upbeat,
loopable, about 2 minutes, instrumental." It would need a pack entry like the
chapters' (`tools/pack_assets.gd MUSIC_FILES`) and its fight loop in
`Sound.FIGHTS`.
