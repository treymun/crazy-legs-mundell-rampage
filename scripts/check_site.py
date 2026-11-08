"""Check the static site, the download config, and the ZIP verifier."""

from __future__ import annotations

import hashlib
import json
import re
import subprocess
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import unquote, urlparse
from zipfile import ZipFile

sys.path.insert(0, str(Path(__file__).resolve().parent))

from site_config import (  # noqa: E402
    CONFIG_PATH,
    REPO,
    ROOT,
    SiteError,
    fetch_zip_signature,
    format_mib,
    load_config,
    render_download,
)

PAGES = (
    "index.html",
    "county.html",
    "arsenal.html",
    "play.html",
    "media.html",
    "notes.html",
)
NAV = (
    "index.html",
    "county.html",
    "arsenal.html",
    "play.html",
    "media.html",
    "notes.html",
)
EXTERNAL = {
    REPO,
    "https://polyhaven.com/",
    "https://polyhaven.com/license",
}
TEXTURES = {
    "assets/textures/asphalt_02.webp": "bfadcc90fbf883590afe6746ccf1cb38a0ad0d84e50cfbff88b56ba900d8876b",
    "assets/textures/corrugated_iron.webp": "4a2ca69a490f51cef3e7a98a9b98c204c70e2fafce1887c3509852c7631924bd",
    "assets/textures/weathered_plank_siding.webp": "813835215304098bc670de3f6b04479dd662f9a4fb41b11564c656a2d7867d1f",
}
MARKER = re.compile(r"<!-- DOWNLOAD:START -->(.*?)<!-- DOWNLOAD:END -->", re.S)
FORBIDDEN = re.compile(
    r"\bjerry\b|C:\\Users|dosgamesarchive|steampowered|wikimedia\.org|freesound\.org|opengameart\.org|loc\.gov",
    re.I,
)


def collapse(text: str) -> str:
    return re.sub(r"\s+", " ", text).strip()


class Document(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.ids: list[str] = []
        self.hrefs: list[str] = []
        self.srcs: list[str] = []
        self.alts: list[tuple[str, str | None]] = []
        self.h1 = 0
        self.bad: list[str] = []
        self.skip = False
        self.main = False
        self.current = False

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        attr = {key: value for key, value in attrs}
        if tag == "video":
            if "autoplay" in attr:
                self.bad.append("autoplay")
            if "controls" not in attr:
                self.bad.append("video-without-controls")
        elif tag == "source" and attr.get("src"):
            self.hrefs.append(attr["src"])
        elif tag in {"script", "iframe", "audio", "form", "object", "embed", "base"}:
            if tag == "script" and attr.get("src") == "js/download.js":
                self.srcs.append(attr["src"])
            else:
                self.bad.append(tag)
        if tag == "h1":
            self.h1 += 1
        if tag == "img":
            self.alts.append((attr.get("src") or "", attr.get("alt")))
        if "id" in attr and attr["id"]:
            self.ids.append(attr["id"])
        if tag == "a":
            if attr.get("href"):
                self.hrefs.append(attr["href"])
            if attr.get("aria-current") == "page":
                self.current = True
        if tag == "link" and attr.get("href"):
            self.hrefs.append(attr["href"])
        for key in attr:
            if key.startswith("on") or key == "style":
                self.bad.append(key)
        if tag == "a" and attr.get("href") == "#content":
            self.skip = True
        if tag == "main" and attr.get("id") == "content":
            self.main = True


def fail(errors: list[str], message: str) -> None:
    errors.append(message)


def check_markers(cfg: dict, errors: list[str]) -> None:
    slots = {"index.html": "index", "play.html": "play"}
    for name, page in slots.items():
        text = (ROOT / name).read_text(encoding="utf-8")
        found = MARKER.findall(text)
        if len(found) != 1:
            fail(errors, f"{name} needs exactly one download marker")
            continue
        if collapse(found[0]) != collapse(render_download(cfg, page)):
            fail(errors, f"{name} download slot does not match site.json")


def local_target(page: str, href: str) -> tuple[str, str] | str | None:
    if href.startswith(("http://", "https://", "mailto:", "data:")):
        return None
    if href.startswith("//") or href.startswith("/"):
        return f"{page} uses a root or protocol link: {href}"
    path, _, fragment = href.partition("#")
    target = page if path == "" else (Path(page).parent / unquote(path)).as_posix()
    return target, fragment


def check_pages(cfg: dict, errors: list[str]) -> dict[str, Document]:
    docs: dict[str, Document] = {}
    url = cfg["download"]["url"]
    for name in PAGES:
        path = ROOT / name
        text = path.read_text(encoding="utf-8")
        if FORBIDDEN.search(text):
            fail(errors, f"{name} contains a blocked source string")
        parser = Document()
        parser.feed(text)
        docs[name] = parser
        if parser.h1 != 1:
            fail(errors, f"{name} should have one h1, found {parser.h1}")
        if not parser.skip or not parser.main:
            fail(errors, f"{name} needs a skip link and main#content")
        if 'lang="en"' not in text or "css/site.css" not in text:
            fail(errors, f"{name} is missing lang or the stylesheet")
        if "An independent, unofficial game project." not in text:
            fail(errors, f"{name} is missing the independence disclaimer")
        if len(parser.ids) != len(set(parser.ids)):
            fail(errors, f"{name} has a duplicate id")
        for bad in parser.bad:
            fail(errors, f"{name} has a disallowed tag or attribute: {bad}")
        for src, alt in parser.alts:
            if alt is None or alt.strip() == "":
                fail(errors, f"{name} image {src} needs alt text")
        expect_script = name in {"index.html", "play.html"}
        if expect_script and parser.srcs != ["js/download.js"]:
            fail(errors, f"{name} should load js/download.js once")
        if not expect_script and parser.srcs:
            fail(errors, f"{name} should not load a script")
        for href in parser.hrefs:
            if href.startswith("https://") or href.startswith("http://"):
                allowed = href in EXTERNAL or href == url or href == cfg.get("releasePage")
                if not allowed:
                    fail(errors, f"{name} links outside the allow list: {href}")
                if href.endswith((".zip", ".exe")) and href != url:
                    fail(errors, f"{name} has an unexpected file link: {href}")
            elif "releases/download" in href:
                fail(errors, f"{name} has a release link outside the config: {href}")
        if url is None and "releases/download" in text:
            fail(errors, f"{name} mentions a release download URL")
        missing = [item for item in NAV if item not in parser.hrefs]
        if missing:
            fail(errors, f"{name} navigation is missing {', '.join(missing)}")
        if f'href="{name}" aria-current="page"' not in text:
            fail(errors, f"{name} does not mark itself as the current page")
    if url is None:
        for name in ("index.html", "play.html"):
            if "Download coming soon" not in (ROOT / name).read_text(encoding="utf-8"):
                fail(errors, f"{name} should say Download coming soon")
    else:
        for name in PAGES:
            text = (ROOT / name).read_text(encoding="utf-8")
            if "coming soon" in text.lower() or "/releases/latest" in text:
                fail(errors, f"{name} still has a coming-soon line or a latest alias")
        for name in ("index.html", "play.html"):
            text = (ROOT / name).read_text(encoding="utf-8")
            found = MARKER.search(text)
            if (
                found is None
                or url not in found.group(1)
                or "Download the Windows x64 ZIP" not in found.group(1)
                or format_mib(cfg["download"]["expectedBytes"]) not in found.group(1)
                or cfg["releasePage"] not in found.group(1)
            ):
                fail(errors, f"{name} download slot does not show the configured release ZIP")
    play = (ROOT / "play.html").read_text(encoding="utf-8")
    if cfg["packageExe"] not in play:
        fail(errors, "play.html is missing the documented exe name")
    if f'href="{cfg["packageExe"]}"' in play or ".exe\"" in play:
        fail(errors, "play.html must not link the exe")
    for name in ("index.html", "play.html", "notes.html"):
        if cfg["notesVersion"] not in (ROOT / name).read_text(encoding="utf-8"):
            fail(errors, f"{name} is missing notes version {cfg['notesVersion']}")
    county = (ROOT / "county.html").read_text(encoding="utf-8")
    for place in ("Hickston", "Possum County Fair", "Blackwater Timber", "Stillwater Cut", "County Crossroads"):
        if place not in county or place not in (ROOT / "index.html").read_text(encoding="utf-8"):
            fail(errors, f"missing chapter name {place}")
    return docs


def check_links(docs: dict[str, Document], errors: list[str]) -> None:
    for name, doc in docs.items():
        for href in doc.hrefs:
            if href.startswith(("http://", "https://", "mailto:")):
                continue
            target = local_target(name, href)
            if target is None:
                continue
            if isinstance(target, str):
                fail(errors, target)
                continue
            path, fragment = target
            file_path = ROOT / path
            if not file_path.is_file():
                fail(errors, f"{name} links to missing {path}")
                continue
            if fragment:
                owner = docs.get(path)
                ids = owner.ids if owner else re.findall(r'id="([^"]+)"', file_path.read_text(encoding="utf-8"))
                if fragment not in ids:
                    fail(errors, f"{name} points at missing anchor {path}#{fragment}")


def check_css(errors: list[str]) -> None:
    css_path = ROOT / "css" / "site.css"
    text = css_path.read_text(encoding="utf-8")
    if FORBIDDEN.search(text):
        fail(errors, "css contains a blocked source string")
    for match in re.finditer(r"url\(\s*['\"]?([^'\")]+)", text):
        raw = match.group(1)
        if raw.startswith(("data:", "http://", "https://")):
            fail(errors, f"css uses an external url: {raw}")
            continue
        target = (css_path.parent / unquote(raw)).resolve()
        if not target.is_file() or ROOT not in target.parents:
            fail(errors, f"css missing asset {raw}")


def check_files(errors: list[str]) -> None:
    blocked_suffix = {".zip", ".exe", ".png", ".jpg", ".jpeg", ".mp3", ".wav", ".ogg"}
    for path in ROOT.rglob("*"):
        if not path.is_file() or ".git" in path.parts:
            continue
        if path.suffix.lower() in blocked_suffix:
            fail(errors, f"repo should not contain {path.relative_to(ROOT)}")
        if path.suffix.lower() in {".mp4", ".webm"} and "assets/gameplay" not in path.as_posix():
            fail(errors, f"video outside the gameplay folder: {path.relative_to(ROOT)}")
        if path.name in {"RELEASE_THIRD_PARTY_NOTICES.md", "ATTRIBUTION.md"}:
            fail(errors, f"do not publish {path.name}")
    for rel, digest in TEXTURES.items():
        file_path = ROOT / rel
        if not file_path.is_file():
            fail(errors, f"missing texture {rel}")
            continue
        found = hashlib.sha256(file_path.read_bytes()).hexdigest()
        if found != digest:
            fail(errors, f"texture hash changed for {rel}")
    js = (ROOT / "js" / "download.js").read_text(encoding="utf-8")
    if "releases\\/download\\/" not in js or "crazy-legs-mundell-rampage" not in js:
        fail(errors, "download.js is missing the release URL check")
    if "/releases/latest" in js or "/releases/latest" in (ROOT / "site.json").read_text(encoding="utf-8"):
        fail(errors, "download config uses the latest alias")
    readme = (ROOT / "README.md").read_text(encoding="utf-8")
    if FORBIDDEN.search(readme) or FORBIDDEN.search((ROOT / "site.json").read_text(encoding="utf-8")):
        fail(errors, "readme or site.json contains a blocked source string")


def list_release_zips() -> tuple[list[dict] | None, str | None]:
    releases: list[dict] = []
    page = 1
    while page <= 10:
        proc = subprocess.run(
            ["gh", "api", f"repos/treymun/crazy-legs-mundell-rampage/releases?per_page=100&page={page}"],
            check=False,
            capture_output=True,
            text=True,
            timeout=40,
        )
        if proc.returncode != 0:
            return None, (proc.stderr or proc.stdout or "gh failed").strip()[:400]
        try:
            batch = json.loads(proc.stdout or "[]")
        except json.JSONDecodeError:
            return None, "release list was not json"
        if not isinstance(batch, list):
            return None, "release list was not a list"
        releases.extend(batch)
        if len(batch) < 100:
            break
        page += 1
    assets = []
    for release in releases:
        if release.get("draft"):
            continue
        for asset in release.get("assets") or []:
            name = asset.get("name") or ""
            if name.lower().endswith(".zip") and asset.get("state") in (None, "", "uploaded"):
                digest = asset.get("digest") or ""
                if digest.startswith("sha256:"):
                    digest = digest.split(":", 1)[1]
                assets.append(
                    {
                        "tag": release.get("tag_name"),
                        "name": name,
                        "size": asset.get("size"),
                        "url": asset.get("browser_download_url"),
                        "digest": digest,
                        "prerelease": bool(release.get("prerelease")),
                        "target": release.get("target_commitish"),
                        "page": release.get("html_url"),
                    }
                )
    return assets, None


def check_release(cfg: dict, errors: list[str]) -> str:
    assets, problem = list_release_zips()
    url = cfg["download"]["url"]
    if problem:
        print(f"release_list=unknown ({problem})")
    elif not assets:
        print("release_list=empty")
    else:
        print(f"release_list={len(assets)}")
    if url is None:
        if assets:
            names = ", ".join(asset["name"] for asset in assets)
            fail(errors, f"a published ZIP exists but site.json has no url: {names}")
            return "release_asset_not_configured"
        print("download_ready=no")
        print("reason=no_release_asset")
        return "no_release_asset"
    if assets is not None:
        match = [asset for asset in assets if asset["url"] == url]
        if len(match) != 1:
            fail(errors, "configured download URL is not one published release ZIP")
        else:
            asset = match[0]
            if asset["size"] != cfg["download"]["expectedBytes"]:
                fail(errors, "configured byte size does not match the published asset")
            if asset.get("digest") != cfg["download"].get("sha256"):
                fail(errors, "configured sha256 does not match the published asset digest")
            if asset.get("prerelease") is not True:
                fail(errors, "published asset is not marked as a prerelease")
            if asset.get("page") != cfg.get("releasePage"):
                fail(errors, "release page does not match the published release")
            if asset.get("target") != cfg.get("releaseTarget"):
                fail(errors, "release tag target does not match site.json")
            if "/releases/latest" in asset.get("url", ""):
                fail(errors, "asset URL uses the latest alias")
    try:
        found = fetch_zip_signature(url)
    except Exception as exc:  # noqa: BLE001 — report the network result, do not pretend success
        fail(errors, f"anonymous ZIP check failed: {exc}")
        print("download_ready=no")
        print("reason=asset_not_publicly_reachable")
        return "asset_not_publicly_reachable"
    if found["bytes"] != cfg["download"]["expectedBytes"]:
        fail(errors, f"anonymous size {found['bytes']} != configured {cfg['download']['expectedBytes']}")
        print("download_ready=no")
        return "size_mismatch"
    print("download_ready=yes")
    print(f"download_bytes={found['bytes']}")
    return "verified"


class ZipHandler(BaseHTTPRequestHandler):
    def do_GET(self) -> None:  # noqa: N802
        path = self.path.split("?", 1)[0]
        body = self.server.zip_bytes  # type: ignore[attr-defined]
        if path != "/good.zip":
            payload = b"not-a-zip"
            self.send_response(200)
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
            return
        if self.headers.get("Range") == "bytes=0-3":
            chunk = body[:4]
            self.send_response(206)
            self.send_header("Content-Length", str(len(chunk)))
            self.send_header("Content-Range", f"bytes 0-3/{len(body)}")
            self.end_headers()
            self.wfile.write(chunk)
            return
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body[:4])

    def log_message(self, fmt: str, *args) -> None:
        return


def self_test_verifier() -> None:
    from io import BytesIO

    buffer = BytesIO()
    with ZipFile(buffer, "w") as archive:
        archive.writestr("readme.txt", "texture credit stays with the site\n")
    payload = buffer.getvalue()
    if not payload.startswith(b"PK\x03\x04"):
        raise SiteError("fixture zip did not start with a local file header")
    server = ThreadingHTTPServer(("127.0.0.1", 0), ZipHandler)
    server.zip_bytes = payload  # type: ignore[attr-defined]
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    port = server.server_address[1]
    try:
        good = fetch_zip_signature(f"http://127.0.0.1:{port}/good.zip", timeout=5)
        if good["bytes"] != len(payload) or good["signature"] != b"PK\x03\x04":
            raise SiteError("verifier missed the fixture zip size or signature")
        try:
            fetch_zip_signature(f"http://127.0.0.1:{port}/bad.bin", timeout=5)
        except SiteError:
            pass
        else:
            raise SiteError("verifier accepted a non-zip")
    finally:
        server.shutdown()
        server.server_close()


def main() -> int:
    errors: list[str] = []
    try:
        cfg = load_config()
    except (SiteError, OSError, json.JSONDecodeError) as exc:
        print(f"error: {exc}")
        return 1
    check_markers(cfg, errors)
    docs = check_pages(cfg, errors)
    check_links(docs, errors)
    check_css(errors)
    check_files(errors)
    try:
        self_test_verifier()
        print("zip_verifier=ok")
    except Exception as exc:  # noqa: BLE001
        fail(errors, f"zip verifier self-test failed: {exc}")
    check_release(cfg, errors)
    if errors:
        print(f"errors={len(errors)}")
        for message in errors:
            print(f"- {message}")
        return 1
    print("site_check=ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
