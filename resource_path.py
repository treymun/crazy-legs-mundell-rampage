"""Resolve bundled read-only resources and writable user data for every target.

One-file PyInstaller builds unpack into ``sys._MEIPASS``; Android bundles expose
their files under ``ANDROID_ARGUMENT``; running from source uses this folder.
Saves must never be written beside those resources, so they go to a per-user
directory instead.
"""
from __future__ import annotations

import os
import sys
from pathlib import Path

APP_NAME = "CrazyLegsMundellRampage"
IS_ANDROID = ("ANDROID_ARGUMENT" in os.environ
              or "P4A_BOOTSTRAP" in os.environ
              or "ANDROID_PRIVATE" in os.environ)
IS_WEB = sys.platform in ("emscripten", "wasi")


def _resource_root() -> Path:
    bundle = getattr(sys, "_MEIPASS", None)
    if bundle:
        return Path(bundle)
    if IS_ANDROID:
        # python-for-android copies the app tree into the APK's private dir.
        for key in ("ANDROID_APP_PATH", "ANDROID_ARGUMENT", "ANDROID_PRIVATE"):
            value = os.environ.get(key)
            if value:
                return Path(value)
    return Path(__file__).resolve().parent


def get_resource_path(relative_path: str) -> str:
    """Absolute path to a read-only bundled resource such as ``assets/art``."""
    return str(_resource_root() / relative_path)


def get_save_dir() -> str:
    """Writable per-user directory for saves, options and generated cache."""
    if IS_ANDROID:
        base = os.environ.get("ANDROID_PRIVATE") or os.environ.get("ANDROID_APP_PATH")
        if not base:
            base = os.environ.get("HOME") or "/data/data"
    elif IS_WEB:
        base = os.environ.get("HOME") or "/tmp"
    elif os.name == "nt":
        base = os.environ.get("APPDATA") or os.environ.get("LOCALAPPDATA") or str(Path.home())
    elif sys.platform == "darwin":
        base = str(Path.home() / "Library" / "Application Support")
    else:
        base = os.environ.get("XDG_DATA_HOME") or str(Path.home() / ".local" / "share")
    directory = Path(base) / APP_NAME
    directory.mkdir(parents=True, exist_ok=True)
    return str(directory)


def get_save_path(filename: str) -> str:
    """Absolute path inside the writable user directory (created on demand)."""
    directory = Path(get_save_dir())
    if not filename:
        return str(directory)
    target = directory / filename
    target.parent.mkdir(parents=True, exist_ok=True)
    return str(target)
