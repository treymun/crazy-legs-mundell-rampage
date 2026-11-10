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
from concurrent.futures import ThreadPoolExecutor
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
    gen.tts(name, entry.get("say", entry["text"]), voices[entry["voice"]]["id"], "eleven_multilingual_v2",
            {"stability": .6, "similarity_boost": .8, "style": .35, "use_speaker_boost": True},
            redo)


def transcribe(name: str, redo: bool = False) -> None:
    """Have the recording of a spoken line written back as words with times.

    The build uses it twice: to check the line says its caption, and to cut the
    cue at the last word instead of at whatever the voice model added after it.
    """
    source = gen.OUT / "tts" / f"{name}.mp3"
    if not source.is_file():
        return

    def call(client):
        with source.open("rb") as handle:
            reply = client.speech_to_text.convert(model_id="scribe_v1", file=handle,
                                                  language_code="en", timestamps_granularity="word")
        words = [{"text": w.text, "start": w.start, "end": w.end}
                 for w in reply.words if getattr(w, "type", "word") == "word"]
        return [json.dumps({"text": reply.text, "words": words}, indent=1).encode()]

    gen.run("stt", name, {"file": source.name, "bytes": source.stat().st_size}, 150, 12, "json",
            call, redo=redo)


DESIGNS = {
    # Original characters, described rather than cloned from anyone.
    "local": ("A middle-aged man from the rural American South with a thick, slow Arkansas drawl. "
              "Gravelly, nasal, a little slow on the uptake, comic and deadpan. Close, dry studio recording.",
              "Well I'll be. Somebody went and took the truck again. You ask me, it was that pig. "
              "That pig has had it in for me since the county fair, and I ain't forgot it neither."),
    "dispatch": ("An older woman, a tired small-town Southern police dispatcher with a dry smoker's rasp and "
                 "a flat Arkansas accent. Bored, clipped, deadpan. Close, dry studio recording.",
                 "County dispatch, all units. Look for the hog. I repeat, look for the hog. Check the blue "
                 "trunk, keep the key dry, and somebody please fix that roof before it rains again."),
    "barker": ("A fast-talking Southern carnival barker, a man in his fifties with a brassy, theatrical, "
               "wheedling voice and a strong country accent. Loud and showy. Close, dry studio recording."
               , "Step right up, step right up, clear the stage and save that rope! One thin dime, folks, one "
               "tenth of a dollar, to see the wonder of Possum County before the whole show leaves town!"),
}


def design(name: str) -> None:
    """Design one original voice (paid once) and keep its id in voices.json."""
    voices = json.loads(VOICES.read_text(encoding="utf-8")) if VOICES.is_file() else {}
    if name in voices:
        print(f"cached   voice {name}")
        return
    description, sample = DESIGNS[name]
    holder: dict = {}

    def call(client):
        reply = client.text_to_voice.design(voice_description=description, text=sample,
                                            model_id="eleven_ttv_v3")
        first = reply.previews[0]
        made = client.text_to_voice.create(voice_name=f"Crazy Legs - {name}",
                                           voice_description=description,
                                           generated_voice_id=first.generated_voice_id)
        holder["id"] = made.voice_id
        import base64
        return [base64.b64decode(first.audio_base_64)]

    path = gen.run("voice_design", name, {"description": description, "text": sample},
                   3000, len(sample) * 3, "mp3", call)
    if path and "id" in holder:
        voices[name] = {"id": holder["id"], "description": description,
                        "preview": path.relative_to(gen.ROOT).as_posix()}
        VOICES.write_text(json.dumps(voices, indent=1), encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--only", nargs="*", default=[])
    parser.add_argument("--family", nargs="*", default=[])
    parser.add_argument("--sfx", action="store_true")
    parser.add_argument("--voices", action="store_true")
    parser.add_argument("--transcribe", action="store_true", help="check the spoken lines")
    parser.add_argument("--design", nargs="*", help="design the named voices (default: all)")
    parser.add_argument("--music", nargs="*")
    parser.add_argument("--redo", nargs="*", default=[])
    parser.add_argument("--workers", type=int, default=4)
    args = parser.parse_args()
    if args.design is not None:
        for name in args.design or list(DESIGNS):
            design(name)
    if args.transcribe:
        with ThreadPoolExecutor(max_workers=args.workers) as pool:
            list(pool.map(lambda n: transcribe(n, n in args.redo),
                          [n for n, e in spec.CUES.items() if e["make"] == "voice"]))
    names = list(args.only) + list(args.redo)
    names += [n for n, f in spec.FAMILY.items() if f in args.family]
    if args.sfx:
        names += [n for n, e in spec.CUES.items() if e["make"] == "gen"]
    if args.voices:
        names += [n for n, e in spec.CUES.items() if e["make"] == "voice"]
    def one(name: str) -> None:
        if gen.summary(gen.load())["remaining"] < 500:
            return                               # the ceiling is close: stop asking
        entry = spec.CUES.get(name)
        if entry is None:                        # a song named with --redo
            return
        if entry["make"] == "gen":
            effect(name, name in args.redo)
        elif entry["make"] == "voice":
            line(name, name in args.redo)

    # Requests take 20-30 s each; a few in flight at once is the difference
    # between an hour and a quarter of one. Each holds its own reservation.
    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        list(pool.map(one, dict.fromkeys(names)))
        if args.music is not None:
            stems = args.music or [m[0] for m in spec.MUSIC] + [spec.VICTORY[0]]
            list(pool.map(lambda stem: song(stem, stem in args.redo), stems))
    print(json.dumps(gen.reconcile(), indent=1))


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    main()
