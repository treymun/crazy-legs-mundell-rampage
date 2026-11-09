"""One-time overheard exchanges tied to each chapter's occupied places."""
from dataclasses import dataclass


@dataclass(frozen=True)
class Exchange:
    id: str
    x: float
    y: float
    stop_at: str
    lines: tuple


EXCHANGES = {
    "hickston": (
        Exchange("tow-radio", 57.7, 26.1, "", ("RADIO: WHO TOOK THE TRUCK?", "VOICE: ASK THE PIG.")),
        Exchange("registry-radio", 74.4, 12.3, "", ("RADIO: KEEP THE KEY DRY.", "VOICE: THEN FIX THE ROOF.")),
    ),
    "fair": (
        Exchange("freight-pa", 47.3, 30.5, "broadcast", ("PA: SAVE THAT ROPE.", "VOICE: FOR THE SHOW?")),
        Exchange("show-pa", 55.0, 8.6, "broadcast", ("PA: CLEAR THE STAGE.", "VOICE: TELL THE GOAT.")),
    ),
    "sawmill": (
        Exchange("sort-radio", 46.1, 23.0, "east", ("RADIO: HEAR THAT BELT?", "VOICE: SOUNDS LIKE TEETH.")),
        Exchange("kiln-radio", 61.5, 31.2, "east", ("RADIO: KILL THE DRIVE.", "VOICE: YOU FIRST.")),
    ),
    "quarry": (
        Exchange("pit-speaker", 57.8, 24.6, "bottling", ("HORN: TASTE THAT MUD?", "VOICE: NEEDS MORE SALT.")),
        Exchange("line-speaker", 72.0, 17.3, "bottling", ("HORN: CLOSE THE TAP.", "VOICE: WHICH RED ONE?")),
    ),
}
