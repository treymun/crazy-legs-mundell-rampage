# crazy-legs-mundell-rampage

Promotional site for Crazy Legs Mundell Rampage. The game download is the public v1.4.3 prerelease ZIP. This repository's website is not that game version, and the site does not host a second copy of the ZIP.

## Download configuration

`site.json` is the only place the download address is authored. `scripts/apply_download.py` copies it into the Home and Play download slots. `js/download.js` reads the same file in the browser.

Current public asset, checked against the GitHub release:

- Tag: `v1.4.3` (prerelease, not a later full release)
- Tag target: `148d9557d57100f17320cc961ed3957a00ff9533` on `main`
- Release page: https://github.com/treymun/crazy-legs-mundell-rampage/releases/tag/v1.4.3
- ZIP: https://github.com/treymun/crazy-legs-mundell-rampage/releases/download/v1.4.3/Crazy_Legs_Mundell_Rampage_1.4.3.zip
- File name: `Crazy_Legs_Mundell_Rampage_1.4.3.zip`
- Size: 115,895,791 bytes (110.5 MiB)
- SHA-256: `13613b4a2eadf69df4eed0ac1978031255b4bc727f90cd639156d03de09dcc1e`

Do not point the button at GitHub's latest-release alias. That alias skips prereleases. Use the tagged asset URL above.

After a real future asset is published, update `site.json` from the release record and restamp:

```bash
python3 scripts/apply_download.py --asset ExactFileName.zip
python3 scripts/check_site.py
```

`--asset` reads the published asset with `gh`. It does not create a release or upload a file. The checker then reads the ZIP's first four bytes and its reported size without running the exe. It also compares the published digest, byte size, prerelease flag, release page, and tag target with `site.json`.

## What the pages say

- Home, County, Arsenal, Play, Media, and Notes are the site.
- Copy follows the reviewed 1.4.3 project notes. It is not a performance test.
- The public build is a Windows x64 development build. The site does not promise macOS, Linux, mobile, browser play, or a specific Windows version.
- Only weapons named in those notes are listed. The count is twelve.
- Media shows scripted 1.4.3 gameplay stills, plus the three Poly Haven CC0 material textures. Moving footage is not on the site. Do not add private portraits or unfinished source plates.
- Keep the game package's own credits and third-party notices inside the ZIP. Do not strip them.

## Gameplay media

`assets/gameplay/` holds stills from the published 1.4.3 source. A scratch harness saved the 320×200 canvas, and the stills are a 3× nearest-neighbor scale. They are not recordings of the Windows EXE and not a person playing. Moving footage is not on the site. Do not replace the stills with generated pictures. Headings use Hickston Pixel, built from the game's own hand-cut lettering.

## Textures

The three WebP files in `assets/textures/` are the supplied Poly Haven scans. Their SHA-256 values are pinned in `scripts/check_site.py`. Website credit: Poly Haven, CC0, https://polyhaven.com/license

## Check

```bash
python3 scripts/check_site.py
```

The check fails if a download link is not the configured release ZIP, if the page says the download is still coming soon, or if a link uses the latest-release alias.

## GitHub Pages

The workflow `.github/workflows/pages.yml` uses official GitHub actions pinned to commits. A pull request only runs the checker. Publishing runs only after a push to `main`.

This site is not live until someone merges the website pull request and turns Pages on:

1. Merge the website pull request into `main`.
2. In the repository settings, open Pages and set the source to GitHub Actions.
3. Do not add a custom domain in that workflow.

The project site, once those two steps are done, is served under `/crazy-legs-mundell-rampage/`. Pages are not enabled by the pull request itself. Do not treat a guessed `github.io` address as live until a request to it returns this site.

## Links

Keep links relative (`play.html`, `css/site.css`) so the project subpath works. Do not add analytics, accounts, payment, or third-party embeds.
