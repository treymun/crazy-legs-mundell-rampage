"""ElevenLabs client for the project's audio tooling.

    pip install -r requirements-dev.txt
    python scripts/audio_generator.py "rusty road gate creaking open" gate_creak.mp3 --seconds 2.5

The key is read from ELEVENLABS_API_KEY, which the ElevenLabs CLI keeps in the
git-ignored ``.env`` at the repository root. It is never written in code.

This is only the connection and one sound-effect call. The game's shipped cues
still come from ``sound_production.py``; nothing here runs during a build.
"""
from __future__ import annotations

import argparse
from pathlib import Path

from dotenv import load_dotenv
from elevenlabs.client import ElevenLabs

ROOT = Path(__file__).resolve().parent.parent


def client() -> ElevenLabs:
    """A client that takes its key from the environment (.env at the repo root)."""
    load_dotenv(ROOT / ".env")
    return ElevenLabs()


def sound_effect(prompt: str, target: Path, *, seconds: float | None = None,
                 loop: bool = False) -> Path:
    """Generate one effect from a text prompt and save it as MP3 (44.1 kHz)."""
    options = {"text": prompt, "output_format": "mp3_44100_128", "loop": loop}
    if seconds is not None:
        options["duration_seconds"] = seconds
    audio = client().text_to_sound_effects.convert(**options)
    target.parent.mkdir(parents=True, exist_ok=True)
    with target.open("wb") as handle:
        for chunk in audio:
            handle.write(chunk)
    return target


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate one sound effect with ElevenLabs.")
    parser.add_argument("prompt", help="what the effect should sound like")
    parser.add_argument("target", type=Path, help="MP3 file to write")
    parser.add_argument("--seconds", type=float, help="length, 0.5 to 30 (default: automatic)")
    parser.add_argument("--loop", action="store_true", help="make the effect loop cleanly")
    args = parser.parse_args()
    print(sound_effect(args.prompt, args.target, seconds=args.seconds, loop=args.loop))


if __name__ == "__main__":
    main()
