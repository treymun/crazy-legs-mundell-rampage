[app]

title = Crazy Legs Mundell Rampage
package.name = crazylegsmundell
package.domain = com.hickston

source.dir = .
source.include_exts = py,png,jpg,jpeg,json,npy,ogg,wav,ico,txt,md
source.exclude_dirs = .venv,.build,build,dist,bot_shots,_backup,source_art,__pycache__,.github,.git,.pytest_cache,scripts,p4a-recipes
source.exclude_patterns = assets/music/*.opus,assets/wav/music.wav,assets/wav/county_line.wav,assets/wav/porchlight_stomp.wav,assets/wav/fair_score.wav,assets/wav/tickets_after_dark.wav,assets/wav/closing_time_shuffle.wav,assets/wav/mill_score.wav,assets/wav/green_chain.wav,assets/wav/apron_run.wav,assets/wav/quarry_score.wav,assets/wav/copper_and_steam.wav,assets/wav/last_load.wav

version = 2.0.0

requirements = python3,numpy,pygame-ce

orientation = landscape
fullscreen = 1

icon.filename = %(source.dir)s/assets/art/hickston_icon.png

android.api = 34
android.minapi = 24
android.archs = arm64-v8a
android.allow_backup = False
android.accept_sdk_license = True

p4a.branch = develop
p4a.local_recipes = p4a-recipes

[buildozer]
log_level = 2
warn_on_root = 1
