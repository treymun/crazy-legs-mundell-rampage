"""Shared download configuration for the static site."""

from __future__ import annotations

import json
import re
from pathlib import Path
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[1]
CONFIG_PATH = ROOT / "site.json"
REPO = "https://github.com/treymun/crazy-legs-mundell-rampage"
RELEASE_URL_RE = re.compile(
    r"^https://github\.com/treymun/crazy-legs-mundell-rampage/releases/download/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+\.zip$"
)
TAG_PAGE_RE = re.compile(
    r"^https://github\.com/treymun/crazy-legs-mundell-rampage/releases/tag/(?!latest$)[A-Za-z0-9._-]+$"
)
SHA_RE = re.compile(r"^[0-9a-f]{64}$")


class SiteError(Exception):
    pass


def load_config(path: Path = CONFIG_PATH) -> dict:
    with path.open(encoding="utf-8") as handle:
        data = json.load(handle)
    if data.get("repository") != REPO:
        raise SiteError("site.json repository must be the project repository")
    download = data.get("download") or {}
    url = download.get("url")
    expected = download.get("expectedBytes")
    if url is not None and not isinstance(url, str):
        raise SiteError("download.url must be a string or null")
    if url is not None and not RELEASE_URL_RE.fullmatch(url):
        raise SiteError("download.url must be a concrete GitHub release ZIP for this repository")
    if expected is not None and (not isinstance(expected, int) or expected <= 0):
        raise SiteError("download.expectedBytes must be a positive integer or null")
    if url and expected is None:
        raise SiteError("download.expectedBytes is required when download.url is set")
    if expected is not None and url is None:
        raise SiteError("download.expectedBytes must be null while download.url is null")
    if url and "/releases/latest" in url:
        raise SiteError("download.url must be a tagged asset, not the latest alias")
    page = data.get("releasePage")
    digest = download.get("sha256")
    if url:
        if not isinstance(page, str) or not TAG_PAGE_RE.fullmatch(page):
            raise SiteError("releasePage must be the concrete tag page for this repository")
        if "/releases/latest" in page:
            raise SiteError("releasePage must not use the latest alias")
        if not isinstance(digest, str) or not SHA_RE.fullmatch(digest):
            raise SiteError("download.sha256 must be 64 hex characters when a URL is set")
        if data.get("prerelease") is not True:
            raise SiteError("prerelease must be true for this development build")
    return data


def format_mib(size: int) -> str:
    return f"{size / (1024 * 1024):.1f} MiB"


def render_download(cfg: dict, page: str) -> str:
    download = cfg["download"]
    url = download.get("url")
    lines: list[str] = []
    if not url:
        lines.append('<p class="soon">Download coming soon</p>')
        lines.append("<p>No public Windows ZIP is published in this repository.</p>")
    else:
        name = url.rstrip("/").split("/")[-1].replace("_", "_<wbr>")
        size = download["expectedBytes"]
        detail = f"{name}. {format_mib(size)} ({size:,} bytes)."
        lines.append(f'<p class="cta"><a href="{url}">Download the Windows x64 ZIP</a></p>')
        lines.append('<details class="file-note"><summary>Release file</summary>')
        lines.append(f"<p>{detail}</p>")
        lines.append("<p>Windows x64 development build. Public v1.4.3 prerelease.</p>")
        lines.append(f'<p><a href="{cfg["releasePage"]}">View the v1.4.3 release</a></p>')
    if page == "index":
        lines.append('<p><a href="play.html#download">Read the download notes</a></p>')
    lines.append(f'<p><a href="{REPO}">View project on GitHub</a></p>')
    if url:
        lines.append("</details>")
    return "\n".join(lines)


def fetch_zip_signature(url: str, timeout: int = 30) -> dict:
    """Read the ZIP local-file signature and reported size. Do not run the file."""
    request = Request(
        url,
        headers={
            "User-Agent": "clmr-site-check",
            "Range": "bytes=0-3",
            "Accept": "application/octet-stream",
        },
    )
    with urlopen(request, timeout=timeout) as response:
        status = getattr(response, "status", 200)
        signature = response.read(4)
        headers = {key.lower(): value for key, value in response.headers.items()}
    if signature != b"PK\x03\x04":
        raise SiteError(f"download is not a ZIP file (signature {signature!r})")
    total = None
    content_range = headers.get("content-range", "")
    if "/" in content_range:
        total_text = content_range.rsplit("/", 1)[-1].strip()
        if total_text.isdigit():
            total = int(total_text)
    elif status == 200 and headers.get("content-length", "").isdigit():
        total = int(headers["content-length"])
    return {"status": status, "bytes": total, "signature": signature}
