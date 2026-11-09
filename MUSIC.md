# Campaign soundtrack

Four chapter playlists, three original pieces each. Each playlist shuffles without repeating a song at the boundary between shuffles. The title theme, jukebox, victory music, and finale stings are separate.

| Chapter | Track | Opus stem | Length |
| --- | --- | --- | ---: |
| Hickston | County Road Shuffle | `music` | 149.79 s |
| Hickston | County Line at Sundown | `county_line` | 182.86 s |
| Hickston | Porchlight Stomp | `porchlight_stomp` | 145.82 s |
| Fair | The Wheel Turns Crooked | `fair_score` | 140.18 s |
| Fair | Tickets After Dark | `tickets_after_dark` | 188.24 s |
| Fair | Last Call at the Midway | `closing_time_shuffle` | 154.16 s |
| Blackwater | Rain on the Green Chain | `mill_score` | 172.58 s |
| Blackwater | Green Chain Blues | `green_chain` | 161.34 s |
| Blackwater | Across the Loading Apron | `apron_run` | 143.67 s |
| Stillwater | Limestone Stomp | `quarry_score` | 157.38 s |
| Stillwater | Copper and Steam | `copper_and_steam` | 163.30 s |
| Stillwater | Last Load from Stillwater | `last_load` | 149.61 s |

The arrangements use FreePats FSBS Clean Electric Guitar and ClueSurf Wavebase bass and percussion from the included sample plates. The iron percussion also uses a recorded reload sample by Brian MacIntosh. The [third-party notices](THIRD_PARTY_NOTICES.md) include license details.

Run `python audio.py` to regenerate the soundtrack, stings, dialogue and effects. Run `python soundtrack_production.py` to regenerate the twelve chapter arrangements separately. The original chapter motifs run through new breaks, contrasting chord progressions, leads, reprisals and codas. The title, jukebox and tally retain separate playback.

The chapter mixes stream through SDL_mixer as mono Ogg Opus, encoded at 24 kHz and a nominal 48 kbps with the libopus included with pygame-ce. A chapter bookmark stores its track, remaining shuffle bag and seek position. The 22,050 Hz 16-bit WAV masters generated alongside the streams measure approximately 0.72 full-scale peak and have matching first and last PCM frames. County Road Shuffle retains its stereo master. The distribution ships the Opus streams for chapter music and 16-bit WAVs for the other audio.

The listed lengths are the encoded file lengths. Chapter playback fades at the end of each coda and skips the remaining quiet mastering tail. The included `assets/music/playback_ends.json` records those points. Regenerate it from the WAV masters with `python soundtrack_production.py --ends-only`. Existing bookmarks in an outgoing quiet tail advance within the same chapter playlist.
