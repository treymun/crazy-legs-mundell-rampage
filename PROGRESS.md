# Handoff: audio, main-menu and settings overhaul

Branch `audio-menu-overhaul` (off `main` at v2.0.0-dev.9). The final commit SHA
is the tip of that branch: `git rev-parse origin/audio-menu-overhaul`.
Read this, `git log`, `audio_src/manifest.json` and
`python scripts/audio_generator.py status` before continuing.

## State

| Step | State |
| --- | --- |
| Billing verified; 80,000-credit ceiling enforced by `scripts/audio_generator.py` | done |
| Cue inventory (301 active cues + 3 new) | done: `audio_src/cue_inventory.json` |
| Reference measurements and creative targets | done: `audio_src/DIRECTION.md` |
| Effect sources (245 generated), 3 designed voices, 21 spoken lines | done |
| Twelve chapter tracks, tally tune, supplied menu theme mastered | done |
| Local finishing, manifest, validation (304/304 cues, 14/14 songs) | done |
| Godot: packer, Ogg title/tally, menu-theme resume, previews | done |
| Title screen and settings rebuilt | done |
| Lint, boot, assets, regression, campaign walkthrough | pass (local) |
| Screenshots and demo | done: `docs/media/` |
| **Listening pass by a human** | **NOT DONE: see "Known issues"** |

## Spend

* Ceiling 80,000 credits. **Spent 30,052** (ledger reconciled against the
  account on 2026-11-10). **Remaining allowance 49,948.**
* By kind: music 25,447; effects 4,559; voice design 1,548; speech 489;
  transcription 360; reconcile adjustment -2,351 (requests the API rejected or
  billed under the estimate).
* Account after the work: 34,775 used of 132,236 (about 97,460 left).
* No dollar billing is possible: the plan has overage off
  (`can_extend_character_limit` false).
* The account shows the subscription set to cancel at the end of the period.
  Not changed here; unused credits may lapse then.
* Ledger: `audio_src/ledger.json`. Never run two generation processes at once;
  the ledger lock is in-process only.

## Commands

```
# Rebuild everything from the checkout. No paid requests, no ffmpeg needed.
python scripts/build_godot_data.py          # needs numpy + Pillow
godot --headless --path godot --import

# Checks (point APPDATA at a scratch folder first to keep your profile clean)
cd godot && gdformat --check src tools && gdlint src tools && cd ..
godot --headless --path godot --quit-after 100
godot --headless --path godot --script res://tools/verify_assets.gd
godot --headless --path godot --script res://tools/check_fixes.gd
godot --headless --path godot --script res://tools/bot_campaign.gd

# Run
godot --path godot

# Screens and demo
godot --headless --path godot -- --smoke-frames=40 --smoke-screen=setup:3:9 --smoke-shot=out.png
godot --path godot --fixed-fps 30 --write-movie demo.avi -- --demo   # needs a saved campaign: run bot_campaign.gd first

# Audio production (only these spend credits: audio_produce.py)
python scripts/audio_generator.py status --reconcile --account
python scripts/audio_produce.py --redo <cue>   # one paid replacement take
python scripts/audio_build.py                  # local finishing; needs ffmpeg
python scripts/audio_build.py --check
```

## What changed

* **Audio pipeline.** `scripts/audio_spec.py` is the plan (every cue's prompt,
  family, length; the 12 tracks). `audio_produce.py` sends requests through the
  ledger in `audio_generator.py`. `audio_build.py` finishes sources into
  `audio_src/final/sfx/*.wav` (22,050 Hz mono PCM) and
  `godot/assets/music/*.ogg`, and writes `audio_src/manifest.json` with
  purpose, trigger, source, duration, cost, recipe and validation per cue.
* **Godot.** `godot/tools/pack_assets.py` packs the bank from the manifest and
  fails on anything missing. `sound.gd` keeps the menu theme's position across
  submenus and pause, and has interruptible setting previews. Title and tally
  music are Ogg tracks; the old stream bank is gone.
* **Front end.** `godot/src/menu.gd` holds the title and settings layout as
  rectangles in 320x200 space; drawing and hit tests share them. Settings have
  category tabs, an 8-row scrolling list, a help footer, per-page reset, an
  "applies next run" note, and a keep/revert trial for display changes.
  Controls has keyboard, gamepad and touch pages. Art comes from
  `scripts/build_menu_art.py`.
* **CI.** `.github/workflows/release.yml` now runs on every branch push; the
  Pages steps stay limited to main and tags.

## Decisions that are easy to get wrong

* **The Python game is untouched.** Its `assets/wav` and `assets/music` still
  feed the Python build. Godot takes sound from `audio_src/final/sfx` and
  `godot/assets/music`.
* **Cue names, save keys, bookmarks and settings keys are unchanged.** New cue
  names: `menu_back`, `room_cow_launcher`, `room_teat_gun` (the last two were
  requested by the runtime and silently missing before).
* **Levels**: each finished cue is matched to the loudness of the cue it
  replaces, so `REPORT_GAIN`, priorities and ducking still hold. Songs are
  mastered to about -15 LUFS with true peak under -0.8 dB.
* **Cue lengths**: timing-critical families keep the length gameplay was tuned
  to; reports, explosions, deaths and speech run to their natural end.
* **Spoken lines are cut to their caption** using a word-timed transcript
  (`audio_src/generated/stt/`). The build fails a line whose words differ.
  `talk_tow-radio_1` is recorded as a longer sentence (`say=` in the spec) and
  cut to "Ask the pig", because the voice kept misreading the short line.
* **Menu theme**: `audio_src/supplied/menu_theme.mp3` is
  `Crazy_Legs_Mundell_2026-11-09T172930.mp3`, which the author sent in chat on
  2026-11-10 (it replaced an earlier guess). It is mastered to -15 LUFS as
  `godot/assets/music/title.ogg` (140 s). To change it, swap the file and run
  `python scripts/audio_build.py --music`.
* **Menu music** plays on every menu, including pause, and keeps its place.
  (The Python original was silent while paused.)

## Verification

* `audio_build.py --check`: 304 cues, 14 songs, 0 problems, 0 missing. Checks
  cover format, clipping, DC, silence, late onset on timing-critical cues,
  loop seams, abrupt ends, and caption text for speech.
* `verify_assets.gd` decodes every packed cue and track: ASSETS OK.
* `check_fixes.gd` (includes front-end tests: focus, scrolling, hit targets,
  reset, stored keys): PARITY FIXES OK. `bot_campaign.gd`: CAMPAIGN
  WALKTHROUGH OK. gdformat and gdlint clean. All on a clean test profile.
* Demo recording (`docs/media/demo.mp4`, menus then play): mix peak -0.9 dB,
  no clipped samples.
* Layout captures at 1024x768, 1280x720 and 860x400 in `docs/media/layout_*`.
* Song measurements in `audio_src/music_measurements.json`. Band balance is
  measured. The tempo figures are a rough autocorrelation estimate and often
  land on half or 3/2 of the real pulse; do not treat them as measured BPM.

## Known issues

* **Nobody has listened to any of this.** Every quality judgment was made from
  measurements and transcripts. A person must audition the cues and songs in
  game before this is merged to `main`. Expect some cues to be the wrong
  character even though they pass the checks.
* `closing_time_shuffle` (118 s) and `quarry_score` (128 s) came back shorter
  than the 137 s the others run. Inside the 2 to 2.5 minute brief only for the
  second; regenerate the first if it matters (about 1,930 credits).
* Not tested on a real phone, a real gamepad, or in a browser; touch and pad
  paths were exercised by simulated input only. No local Windows/Web/Android
  export was rebuilt on this branch; CI does that.
* The repository grew by about 105 MB (sources 54 MB, finished cues 16 MB,
  songs 32 MB, demo 17 MB).

## Suggested follow-ups

1. Listening pass; list cues to redo; `audio_produce.py --redo` them.
2. Regenerate `closing_time_shuffle` to full length.
3. Bring the new audio to the Python build, or retire its audio.
4. Open a pull request to `main` once the listening pass is done.
