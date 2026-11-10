"""Send the paid requests the audio plan calls for, through the budget ledger.

    python scripts/audio_produce.py --only revolver shotgun amb_yard
    python scripts/audio_produce.py --family reload equip
    python scripts/audio_produce.py --sfx            # every generated effect
    python scripts/audio_produce.py --music [stem ...]
    python scripts/audio_produce.py --voices
    python scripts/audio_produce.py --redo revolver  # a paid replacement take

Anything that already has a file under audio_src/generated/ is skipped, so
this is safe to rerun after an interruption. Costs are reserved, booked and
reconciled by scripts/audio_generator.py; nothing is sent once the project
ceiling would be passed.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import audio_generator as gen  # noqa: E402
import audio_spec as spec  # noqa: E402

VOICES = gen.SRC / "voices.json"       # name -> ElevenLabs voice id (designed once)
MUSIC_SECONDS = 140


def effect(name: str, redo: bool) -> None:
    entry = spec.CUES[name]
    prompt = f"{entry['prompt']} {spec.STYLE[entry['style']]}"
    gen.sfx(name, prompt, entry["gen"], bool(entry.get("loop")), entry.get("influence", .45), redo)


def song(stem: str, redo: bool) -> None:
    if stem == spec.VICTORY[0]:
        gen.music(stem, spec.VICTORY[1], spec.VICTORY[2], redo)
        return
    for name, title, bpm, text in spec.MUSIC:
        if name == stem:
            gen.music(stem, f"{text} About {bpm} BPM. {spec.BAND}", MUSIC_SECONDS, redo)
            return
    raise SystemExit(f"No track named {stem}")


def line(name: str, redo: bool) -> None:
    entry = spec.CUES[name]
    voices = json.loads(VOICES.read_text(encoding="utf-8"))
    gen.tts(name, entry["text"], voices[entry["voice"]]["id"], "eleven_multilingual_v2",
            {"stability": .35, "similarity_boost": .8, "style": .55, "use_speaker_boost": True},
            redo)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--only", nargs="*", default=[])
    parser.add_argument("--family", nargs="*", default=[])
    parser.add_argument("--sfx", action="store_true")
    parser.add_argument("--voices", action="store_true")
    parser.add_argument("--music", nargs="*")
    parser.add_argument("--redo", nargs="*", default=[])
    args = parser.parse_args()
    names = list(args.only) + list(args.redo)
    names += [n for n, f in spec.FAMILY.items() if f in args.family]
    if args.sfx:
        names += [n for n, e in spec.CUES.items() if e["make"] == "gen"]
    if args.voices:
        names += [n for n, e in spec.CUES.items() if e["make"] == "voice"]
    for name in dict.fromkeys(names):
        entry = spec.CUES[name]
        if entry["make"] == "gen":
            effect(name, name in args.redo)
        elif entry["make"] == "voice":
            line(name, name in args.redo)
        if gen.summary(gen.load())["remaining"] < 500:
            print("Stopping: under 500 credits left.")
            break
    if args.music is not None:
        stems = args.music or [m[0] for m in spec.MUSIC] + [spec.VICTORY[0]]
        for stem in stems:
            song(stem, stem in args.redo)
    print(json.dumps(gen.reconcile(), indent=1))


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    main()
