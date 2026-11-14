"""Budgeted ElevenLabs generation for the game's audio.

    python scripts/audio_generator.py status
    python scripts/audio_generator.py sfx   <id> "<prompt>" --seconds 2.5 [--loop] [--influence .4]
    python scripts/audio_generator.py music <id> "<prompt>" --seconds 140
    python scripts/audio_generator.py tts   <id> "<text>" --voice <voice_id>
    python scripts/audio_generator.py batch audio_src/requests/<file>.json

Every paid request goes through one ledger, ``audio_src/ledger.json``:

* The project ceiling is CEILING credits, cumulative across sessions. Spent
  credits plus every pending reservation may never pass it.
* Before a request is sent its worst-case cost is reserved and written to
  disk. When the reply arrives the reservation becomes the expected cost at
  the rates measured on this account (the account's own counter lags a
  request by up to a minute, so it cannot price a single request).
* ``reconcile`` then compares everything the ledger says was spent with the
  real drop in the account's balance since the first request, and books the
  difference. Run it after every batch; ``batch`` does so itself.
* A request that errors or times out is booked at its full expected cost
  until reconcile proves otherwise, and is never silently retried.
* A request whose id already has an accepted file is not sent again.

The key is read from ELEVENLABS_API_KEY (the git-ignored .env at the repo
root); it is never written here. Raw generations land in
``audio_src/generated/<kind>/<id>.<ext>`` and are committed, so a fresh clone
rebuilds the game's audio without paying again.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import threading
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "audio_src"
LEDGER = SRC / "ledger.json"
OUT = SRC / "generated"

CEILING = 100_000  # raised from 80,000 by the owner, 2026-11-13
# Worst-case credits reserved before a request is sent. The rates are the
# ones measured on this account (see ledger "rates"); the margins cover drift.
# Measured 2026-11-10 on the Creator plan (usage endpoint): a 1 s effect cost
# 11 credits and 10 s of music cost 138. Reservations use the published 40/s
# for effects and a 1.5x margin for music; the expected cost uses the measured
# rate, and reconcile corrects the sum against the account.
SFX_RESERVE_PER_SECOND = 40
SFX_PER_SECOND = 11
SFX_AUTO_SECONDS = 30       # the longest an automatic-length effect can be
MUSIC_PER_SECOND = 13.8
TTS_PER_CHAR = 1
TIMEOUT = 420               # seconds; a song can take a few minutes


def _client():
    from dotenv import load_dotenv
    from elevenlabs.client import ElevenLabs
    load_dotenv(ROOT / ".env")
    key = os.environ.get("ELEVENLABS_API_KEY")
    if not key:
        raise SystemExit("ELEVENLABS_API_KEY is not set (expected in .env at the repo root).")
    return ElevenLabs(api_key=key, timeout=TIMEOUT)


def balance(client) -> int:
    """Credits used so far in this billing period (the account's own counter)."""
    return int(client.user.subscription.get().character_count)


def load() -> dict:
    if LEDGER.is_file():
        return json.loads(LEDGER.read_text(encoding="utf-8"))
    return {"ceiling": CEILING, "rates": {}, "entries": []}


def save(ledger: dict) -> None:
    SRC.mkdir(parents=True, exist_ok=True)
    temp = LEDGER.with_suffix(".tmp")
    temp.write_text(json.dumps(ledger, indent=1), encoding="utf-8", newline="\n")
    temp.replace(LEDGER)


def committed(ledger: dict) -> int:
    """Spent credits plus reservations still pending."""
    total = 0
    for entry in ledger["entries"]:
        total += entry["reserved"] if entry["status"] == "pending" else entry.get("actual", 0)
    return total


def summary(ledger: dict) -> dict:
    by_kind: dict[str, int] = {}
    for entry in ledger["entries"]:
        if entry["status"] != "pending":
            by_kind[entry["kind"]] = by_kind.get(entry["kind"], 0) + entry.get("actual", 0)
    spent = sum(by_kind.values())
    pending = committed(ledger) - spent
    return {"ceiling": CEILING, "spent": spent, "pending": pending,
            "remaining": CEILING - spent - pending, "by_kind": by_kind,
            "requests": len(ledger["entries"])}


def target(kind: str, name: str, ext: str) -> Path:
    return OUT / kind / f"{name}.{ext}"


_LOCK = threading.Lock()          # one writer to the ledger at a time


def run(kind: str, name: str, params: dict, reserve: int, expect: int, ext: str, call, *,
        redo=False) -> Path | None:
    """Reserve, send one request, book it. Returns the file, or None if refused.

    Safe to call from several threads: the ledger is re-read and rewritten
    under a lock at both ends, so parallel requests each hold their own
    reservation and none can slip past the ceiling.
    """
    path = target(kind, name, ext)
    if path.is_file() and not redo:
        print(f"cached   {kind}/{name}")
        return path
    client = _client()
    with _LOCK:
        ledger = load()
        if committed(ledger) + reserve > CEILING:
            print(f"REFUSED  {kind}/{name}: needs up to {reserve}, "
                  f"only {CEILING - committed(ledger)} left under the ceiling")
            return None
        if "anchor" not in ledger:
            ledger["anchor"] = {"balance": balance(client), "when": time.strftime("%Y-%m-%dT%H:%M:%S")}
        digest = hashlib.sha256(json.dumps(params, sort_keys=True).encode()).hexdigest()[:12]
        take = sum(1 for e in ledger["entries"] if e["kind"] == kind and e["name"] == name) + 1
        ident = f"{kind}/{name}#{take}"
        ledger["entries"].append({"id": ident, "kind": kind, "name": name, "params": params,
                                  "hash": digest, "reserved": reserve, "status": "pending",
                                  "started": time.strftime("%Y-%m-%dT%H:%M:%S")})
        save(ledger)
    error = ""
    data = b""
    try:
        data = b"".join(call(client))
    except Exception as problem:  # the request may still have been billed
        detail = getattr(problem, "body", None)
        code = getattr(problem, "status_code", "")
        error = f"{type(problem).__name__} {code}: {str(detail if detail is not None else problem)[:400]}"
    with _LOCK:
        ledger = load()
        entry = next(e for e in ledger["entries"] if e["id"] == ident)
        entry["actual"] = expect
        entry["basis"] = "expected"
        if error or not data:
            entry["status"] = "failed"
            entry["error"] = error or "empty response"
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            if path.is_file():                  # keep the earlier take for comparison
                path.replace(path.with_name(f"{path.stem}.take{take - 1}{path.suffix}"))
            path.write_bytes(data)
            entry["status"] = "settled"
            entry["file"] = path.relative_to(ROOT).as_posix()
            entry["bytes"] = len(data)
        save(ledger)
        state = summary(ledger)
    print(f"{entry['status']:8s} {ident}: {entry['actual']} credits "
          f"(reserved {reserve}); spent {state['spent']} / {CEILING}"
          + (f"  ERROR {error}" if error else ""), flush=True)
    return path if entry["status"] == "settled" else None


def sfx(name: str, prompt: str, seconds: float | None = None, loop: bool = False,
        influence: float | None = None, redo: bool = False) -> Path | None:
    params = {"text": prompt, "duration_seconds": seconds, "loop": loop,
              "prompt_influence": influence, "model_id": "eleven_text_to_sound_v2",
              "output_format": "mp3_44100_192"}
    length = SFX_AUTO_SECONDS if seconds is None else seconds
    reserve = int(length * SFX_RESERVE_PER_SECOND) + 5
    expect = int(round((8 if seconds is None else seconds) * SFX_PER_SECOND)) + 1

    def call(client):
        options = {k: v for k, v in params.items() if v is not None}
        return client.text_to_sound_effects.convert(**options)
    return run("sfx", name, params, reserve, expect, "mp3", call, redo=redo)


def music(name: str, prompt: str, seconds: float, redo: bool = False,
          model: str = "music_v1") -> Path | None:
    params = {"prompt": prompt, "music_length_ms": int(seconds * 1000), "model_id": model,
              "force_instrumental": True, "output_format": "mp3_44100_192"}
    reserve = int(seconds * MUSIC_PER_SECOND * 1.5) + 50
    expect = int(round(seconds * MUSIC_PER_SECOND))

    def call(client):
        return client.music.compose(**params)
    return run("music", name, params, reserve, expect, "mp3", call, redo=redo)


def tts(name: str, text: str, voice: str, model: str = "eleven_multilingual_v2",
        settings: dict | None = None, redo: bool = False) -> Path | None:
    params = {"text": text, "voice_id": voice, "model_id": model,
              "output_format": "mp3_44100_192", "voice_settings": settings}
    reserve = int(len(text) * TTS_PER_CHAR * 1.2) + 20
    expect = len(text) * TTS_PER_CHAR

    def call(client):
        options = {k: v for k, v in params.items() if v is not None}
        return client.text_to_speech.convert(**options)
    return run("tts", name, params, reserve, expect, "mp3", call, redo=redo)


def reconcile(wait: float = 50.0) -> dict:
    """Book the gap between the ledger and the account's real balance drop.

    Waits for the account counter to catch up, then adds one "reconcile"
    entry so that the ledger's total equals the credits the account actually
    lost since the first request. Anything else spent on the account in the
    meantime is counted against the project: the safe direction.
    """
    ledger = load()
    for entry in ledger["entries"]:
        if entry["status"] == "pending":          # crashed mid-request
            entry.update(status="failed", actual=entry["reserved"], basis="reserved",
                         error="interrupted before the reply was saved")
    if "anchor" not in ledger:
        save(ledger)
        return summary(ledger)
    client = _client()
    time.sleep(wait)
    seen = balance(client)
    while True:                                   # until two reads agree
        time.sleep(8)
        again = balance(client)
        if again == seen:
            break
        seen = again
    real = seen - ledger["anchor"]["balance"]
    ledger["entries"] = [e for e in ledger["entries"] if e["kind"] != "reconcile"]
    booked = sum(e.get("actual", 0) for e in ledger["entries"])
    if real != booked:
        ledger["entries"].append({"id": f"reconcile@{time.strftime('%Y-%m-%dT%H:%M:%S')}",
                                  "kind": "reconcile", "name": "", "reserved": 0,
                                  "status": "settled", "actual": real - booked,
                                  "basis": "account", "balance_after": seen})
    ledger["reconciled"] = {"when": time.strftime("%Y-%m-%dT%H:%M:%S"), "account_drop": real}
    save(ledger)
    return summary(ledger)


def batch(path: Path) -> None:
    for job in json.loads(path.read_text(encoding="utf-8")):
        kind = job.pop("kind")
        result = {"sfx": sfx, "music": music, "tts": tts}[kind](**job)
        if result is None and summary(load())["remaining"] < 200:
            print("Stopping: the allowance is nearly used.")
            break
    print(json.dumps(reconcile(), indent=1))


def main() -> None:
    parser = argparse.ArgumentParser(description="Budgeted ElevenLabs generation.")
    sub = parser.add_subparsers(dest="command", required=True)
    status = sub.add_parser("status")
    status.add_argument("--reconcile", action="store_true")
    status.add_argument("--account", action="store_true", help="also read the live balance")
    one = sub.add_parser("sfx")
    one.add_argument("name"); one.add_argument("prompt")
    one.add_argument("--seconds", type=float); one.add_argument("--loop", action="store_true")
    one.add_argument("--influence", type=float); one.add_argument("--redo", action="store_true")
    song = sub.add_parser("music")
    song.add_argument("name"); song.add_argument("prompt")
    song.add_argument("--seconds", type=float, required=True)
    song.add_argument("--model", default="music_v1"); song.add_argument("--redo", action="store_true")
    say = sub.add_parser("tts")
    say.add_argument("name"); say.add_argument("text"); say.add_argument("--voice", required=True)
    say.add_argument("--model", default="eleven_multilingual_v2"); say.add_argument("--redo", action="store_true")
    many = sub.add_parser("batch")
    many.add_argument("file", type=Path)
    args = parser.parse_args()
    if args.command == "status":
        state = reconcile() if args.reconcile else summary(load())
        if args.account:
            info = _client().user.subscription.get()
            state["account_used"] = info.character_count
            state["account_limit"] = info.character_limit
        print(json.dumps(state, indent=1))
    elif args.command == "sfx":
        sfx(args.name, args.prompt, args.seconds, args.loop, args.influence, args.redo)
    elif args.command == "music":
        music(args.name, args.prompt, args.seconds, args.redo, args.model)
    elif args.command == "tts":
        tts(args.name, args.text, args.voice, args.model, redo=args.redo)
    else:
        batch(args.file)


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    main()
