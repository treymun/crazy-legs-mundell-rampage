"""Stamp the download slots from site.json. Does not create a GitHub release."""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from site_config import CONFIG_PATH, REPO, SiteError, load_config, render_download

MARKER = re.compile(r"<!-- DOWNLOAD:START -->.*?<!-- DOWNLOAD:END -->", re.S)
PAGES = {"index": CONFIG_PATH.parent / "index.html", "play": CONFIG_PATH.parent / "play.html"}


def stamp(cfg: dict) -> None:
    for page, path in PAGES.items():
        text = path.read_text(encoding="utf-8")
        block = "<!-- DOWNLOAD:START -->\n" + render_download(cfg, page) + "\n<!-- DOWNLOAD:END -->"
        updated, count = MARKER.subn(block, text, count=1)
        if count != 1:
            raise SiteError(f"{path.name} needs one DOWNLOAD marker")
        path.write_text(updated, encoding="utf-8")


def list_assets() -> list[dict]:
    assets: list[dict] = []
    page = 1
    while page <= 10:
        proc = subprocess.run(
            [
                "gh",
                "api",
                f"repos/treymun/crazy-legs-mundell-rampage/releases?per_page=100&page={page}",
            ],
            check=False,
            capture_output=True,
            text=True,
            timeout=40,
        )
        if proc.returncode != 0:
            raise SiteError(proc.stderr.strip()[:500] or "could not list releases")
        batch = json.loads(proc.stdout or "[]")
        if not isinstance(batch, list):
            raise SiteError("unexpected release list")
        for release in batch:
            if release.get("draft"):
                continue
            for asset in release.get("assets") or []:
                name = asset.get("name") or ""
                if not name.lower().endswith(".zip"):
                    continue
                if asset.get("state") not in (None, "", "uploaded"):
                    continue
                digest = asset.get("digest") or ""
                if digest.startswith("sha256:"):
                    digest = digest.split(":", 1)[1]
                assets.append(
                    {
                        "tag": release.get("tag_name"),
                        "name": name,
                        "size": asset.get("size"),
                        "url": asset.get("browser_download_url"),
                        "sha256": digest,
                        "page": release.get("html_url"),
                        "target": release.get("target_commitish"),
                        "prerelease": bool(release.get("prerelease")),
                    }
                )
        if len(batch) < 100:
            break
        page += 1
    return assets


def write_config(url: str | None, expected: int | None, asset: dict | None = None) -> dict:
    cfg = json.loads(CONFIG_PATH.read_text(encoding="utf-8"))
    download = {"url": url, "expectedBytes": expected}
    if asset and asset.get("sha256"):
        download["sha256"] = asset["sha256"]
    cfg["download"] = download
    if asset:
        cfg["releasePage"] = asset.get("page")
        cfg["releaseTarget"] = asset.get("target")
        cfg["prerelease"] = bool(asset.get("prerelease"))
    elif url is None:
        cfg["prerelease"] = False
        cfg["releasePage"] = None
        cfg["releaseTarget"] = None
    CONFIG_PATH.write_text(json.dumps(cfg, indent=2) + "\n", encoding="utf-8")
    return load_config()


def main() -> int:
    parser = argparse.ArgumentParser(description="Update the site download config from a real release asset.")
    parser.add_argument("--list", action="store_true", help="List published ZIP assets and exit")
    parser.add_argument("--asset", help="Exact published ZIP asset name to store in site.json")
    parser.add_argument("--clear", action="store_true", help="Clear the download URL")
    args = parser.parse_args()
    if args.clear and args.asset:
        raise SiteError("use either --clear or --asset")
    if args.list:
        assets = list_assets()
        if not assets:
            print("no published ZIP assets")
            return 0
        for asset in assets:
            print(f"{asset['tag']}\t{asset['size']}\t{asset['name']}\t{asset['url']}")
        return 0
    if args.clear:
        cfg = write_config(None, None)
    elif args.asset:
        matches = [asset for asset in list_assets() if asset["name"] == args.asset]
        if len(matches) != 1 or not matches[0]["url"] or not isinstance(matches[0]["size"], int):
            raise SiteError("need exactly one published ZIP with that asset name")
        cfg = write_config(matches[0]["url"], matches[0]["size"], matches[0])
    else:
        cfg = load_config()
    stamp(cfg)
    print(f"stamped download slots from {CONFIG_PATH.name}")
    print(f"repository {REPO}")
    print("url " + (cfg["download"]["url"] or "null"))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (SiteError, subprocess.TimeoutExpired, json.JSONDecodeError, OSError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        raise SystemExit(1)
