# audio_src — where the game's sound comes from

```
audio_src/
  cue_inventory.json   every cue the Godot runtime can play, traced from godot/src
  manifest.json        one record per cue: trigger, source, recipe, cost, measurements
  ledger.json          every paid ElevenLabs request and the running total
  voices.json          the designed voices used for spoken lines
  generated/           raw ElevenLabs output, exactly as delivered (sfx/, music/, tts/)
  supplied/            menu_theme.* — the main-menu song supplied by the author
  final/sfx/           finished cues, mono 16-bit 22050 Hz: what the game packs
  DIRECTION.md         creative targets, reference measurements, calibration notes
```

## Rebuilding without paying

Everything paid for is committed under `generated/`. A fresh clone rebuilds the
finished audio and the game's packs with no network access:

```
pip install numpy Pillow            # and ffmpeg on PATH
python scripts/audio_build.py       # generated/ -> final/sfx, godot/assets/music, manifest.json
python scripts/audio_build.py --check
python scripts/build_godot_data.py  # final/sfx + music -> godot/assets_gen/*.bin
```

`final/sfx` and `godot/assets/music/*.ogg` are committed too, so CI and anyone
without ffmpeg can skip the first two lines.

## Changing a sound

1. Edit its entry in `scripts/audio_spec.py` (prompt, length, family) or the
   family's finishing chain in `scripts/audio_build.py`.
2. A new recording: `python scripts/audio_produce.py --redo <cue>` (paid; the
   old take is kept beside it as `<cue>.take1.mp3`). A processing change needs
   no request.
3. `python scripts/audio_build.py`, then `python scripts/build_godot_data.py`.

## The budget

`scripts/audio_generator.py` is the only code that talks to ElevenLabs. It will
not send a request that could take the project past 80,000 credits in total,
across every session: `python scripts/audio_generator.py status` prints what
has been spent, and `status --reconcile` checks the ledger against the
account's own counter. Measured rates on the Creator plan (2026-11-10): about
11 credits per second of sound effect and 13.8 per second of music, taken from
the plan's credit balance; the plan cannot bill overage.
