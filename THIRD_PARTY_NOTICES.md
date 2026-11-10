# Third-party notices

Redneck Rampage was created by Xatrix Entertainment and published by Interplay. This project includes a custom campaign, original sound, and adapted photographic materials. The character artwork incorporates photo-derived sprites and a generated wardrobe plate. Other generated plates provided source art for the viewmodels, barnyard sprites, Sheriff, and saucer. The current build uses an independently authored 256-color lookup. Earlier builds used color data from the 1997 demo. The current package excludes that source table.

- [1997 Redneck Rampage demo](https://www.dosgamesarchive.com/file/redneck-rampage/redneckd)
- [The Hickston Hog / original Redneck Rampage manual](https://store.steampowered.com/manual/565550/) and [RTCM's weapon reference page](https://rtcmsite.neocities.org/knowledge-base/build-games/redneck-rampage) served as references for equipment silhouettes and behavior. The new weapon frames were built for this project; those reference sprites and sounds are not bundled.
- [Poly Haven asset license](https://polyhaven.com/license). The wood siding, red brick, corrugated iron, asphalt, mud, forest floor, concrete, and linoleum scans are CC0 Poly Haven assets. Their asset names are recorded in the filenames under source_art/materials.
- [Old Amoco station, Hardy, Arkansas](https://www.loc.gov/pictures/resource/mrg.05491/). John Margolies, 1980. Library of Congress, Prints and Photographs Division, John Margolies Roadside America photograph archive. The photograph supplies the title backdrop and both roadside pump sprites.
- [Chevrolet C-10 pickup](https://commons.wikimedia.org/wiki/File:Chevrolet_C-10_pickup.jpg) by IFCAR, public domain. This is the historical truck source plate. The current parked trucks use two original generated profile plates in `source_art/county_truck_ochre.png` and `source_art/county_truck_blue.png`. Those plates are cropped, uniformly resized and digitized for the game.
- [Jerry Jones (24176024648).jpg](https://commons.wikimedia.org/wiki/File:Jerry_Jones_(24176024648).jpg), photograph by Keith Allison, [CC BY-SA 2.0](https://creativecommons.org/licenses/by-sa/2.0/). The source plate (`source_art/jerry_sideline.png`) crops and masks the photograph. The seven `assets/art/jerry_*.png` sprites composite painted clothing and props onto the cutout, alter the pose, and quantize the colors. That plate and all seven sprite derivatives are distributed under CC BY-SA 2.0. The boss is a fictional game depiction. The photograph credit does not imply endorsement.

The music uses original arrangements made in the game's offline sampler. [The campaign soundtrack manifest](MUSIC.md) names the 12 chapter pieces. Sound plates in `source_art/audio` have been trimmed and resampled. Game cues also use equalization, pitch changes, mixing, and other processing.

The 1.4.0 update uses the same source plates and scan licenses. The extended chapter arrangements, scripted radio phrases, prop and weapon effects, and county-wing enemy models were authored for this project. The later Tin Rooster, dispatch notices, clothing and machinery changes, and mix refinements reuse those same materials or original generated cels and sounds. The player derivatives come from the project owner's reference photos. The project owner authorized distributing the supplied game materials. The package excludes raw portrait photos, and third-party clearance has not been independently assessed.

- [FreePats FSBS Electric Guitar Clean](https://freepats.zenvoid.org/ElectricGuitar/clean-electric-guitar.html), bridge pickup samples, [CC0](https://creativecommons.org/publicdomain/zero/1.0/). [ClueSurf Wavebase](https://github.com/cluesurf/wavebase), public-domain bass and percussion.
- [Gunshot Sounds](https://opengameart.org/content/gunshot-sounds) by Vincent Sevedge (Tabasco), used under [CC BY 3.0](https://creativecommons.org/licenses/by/3.0/) as specified inside the download. This covers the shot source plates and derived pistol, rifle, shotgun, and explosion cues. [Gun Reload Sound Effects](https://opengameart.org/content/gun-reload-sound-effects) by Brian MacIntosh, CC0.
- [Footsteps on different surfaces](https://opengameart.org/content/footsteps-on-different-surfaces), edited by congusbongus. [Wood](https://freesound.org/people/swuing/sounds/38876/), [grass](https://freesound.org/people/swuing/sounds/38874/), and [concrete](https://freesound.org/people/swuing/sounds/38873/) by swuing, [water](https://freesound.org/people/EminYILDIRIM/sounds/608663/) by EminYILDIRIM, and [squeaky floor](https://freesound.org/people/ceberation/sounds/235524/) by ceberation are credited under [CC BY 3.0](https://creativecommons.org/licenses/by/3.0/) per the pack. [Gravel](https://freesound.org/people/Ali_6868/packs/21608/) by Ali_6868, CC0. Mud uses [Different Steps](https://opengameart.org/content/different-steps-on-wood-stone-leaves-gravel-and-mud) by TinyWorlds, CC0.
- [Yeehaw](https://freesound.org/people/chancellorbill/sounds/507024/) by chancellorbill, [Grunts of male death and pain](https://lpc.opengameart.org/content/grunts-male-death-and-pain) by thebardofblasphemy, and [Cricket Sounds](https://lpc.opengameart.org/content/cricket-sounds) by syncopika, all CC0.
- [Bottle cap](https://freesound.org/people/MLaudio/sounds/511356/) by MLaudio, [Crunch](https://freesound.org/people/qubodup/sounds/816237/) by qubodup, and [Gulp](https://freesound.org/people/DeVern/sounds/341651/) by DeVern, all CC0.

The Windows build bundles CPython, pygame-ce, SDL and related SDL libraries, NumPy, Pillow, and the PyInstaller bootloader. The source tree pins the Python dependencies in requirements.txt.

- [CPython](https://www.python.org/about/legal/)
- [pygame-ce source and licensing](https://github.com/pygame-community/pygame-ce/tree/2.5.8)
- [SDL 2 source and licensing](https://github.com/libsdl-org/SDL/tree/release-2.32.10)
- [NumPy source and licensing](https://github.com/numpy/numpy/tree/v2.3.5)
- [Pillow source and licensing](https://github.com/python-pillow/Pillow/tree/13.0.0)
- [PyInstaller license and bootloader exception](https://pyinstaller.org/en/stable/license.html)

The ZIP includes the license texts supplied with the installed Python, NumPy, Pillow, and PyInstaller distributions under third_party.

## Godot build audio

The Godot build's sound effects, spoken lines and chapter music were generated
with ElevenLabs (Sound Effects, Text to Speech with voices designed for this
game, and Eleven Music) from original prompts written for this project, under
the author's paid subscription, and then edited, levelled and mastered locally.
The prompts, the raw generations and the processing recipes are in
`audio_src/` and `scripts/audio_spec.py`. The main-menu theme was supplied by
the author. No audio from Redneck Rampage or any other game is included;
recordings of that game were used only to measure loudness, tempo and spectral
balance (`audio_src/DIRECTION.md`). The Python build keeps the sound described
above.
