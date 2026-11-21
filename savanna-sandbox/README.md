# Savanna Sandbox

English · [中文说明](README.zh.md)

A god game on a tabletop slab of African savanna, written by an AI in one sitting. Herds graze and drink, a lion pride hunts, two tribes forage, hunt, farm and build their way from a campfire to a walled stone kingdom, and they go to war across the river. You are the god: rain, lightning, wildfire, meteors, drought, storms, raising and lowering the land.

Made for the channels [**Build with AI**](https://www.youtube.com/@buildwithai2027) and [**独立营业中**](https://www.youtube.com/@独立营业中); more at [videodoz.com](https://videodoz.com).

Status: demo (2026-11-20). Not yet reviewed for release.

## What and why

The question behind the video: how good and how fast is a current AI model at making a whole game from nothing? This directory is the answer in the form of the game itself, plus a record of how it was made.

## How it was made

- Model: Claude Fable 5.2 (`claude-fable-5-2`) in Claude Code, working in one conversation with the channel owner.
- The human chose the idea (a god sandbox on an African savanna with animals, hunting, disasters and two warring tribes) and reviews the result. The model wrote every line of code and every model in the scene.
- Two generations of models. The first playable version had no art assets at all: every animal, person, tree and building was built in code from boxes, cylinders and cones (`js/models.js`, still used as the fallback and with `?assets=0`). The channel owner found that look too crude, so the model then generated 25 models with two other AIs: a reference picture per object from the OpenAI image API (`gpt-image-2`), turned into a textured 3D model by Tripo (`v2.5-20250123`, 30 credits each, about a minute each). `tools/make_assets.py` does both steps and records prompts, task ids, seconds and credits in `assets/manifest.json`; the GLB files are in `assets/models/`. Nothing was drawn or modelled by hand.
- Dependencies: three.js r187 and its GLTF loader, vendored in `vendor/three/`.
- The model checked its own work by opening the page in headless Chrome, taking screenshots and reading them (`tools/shot.py`, `tools/scenario.py`, `tools/probe.py`).
- First playable version: about 36 minutes of wall-clock time from an empty directory, about 3,100 lines of JavaScript.

## Verification

Nothing here is a benchmark; the claim is only "this is what came out, and this is how long it took". You can check it by playing the page and reading the code and the commit history.

## Design

- **World** (`js/terrain.js`, `js/flora.js`): a 96 x 96 heightmap slab with a river, a lake, a pond and three rock outcrops, sitting on a wooden tray. Grass, burn marks and water level are fields on the same grid; acacias, baobabs, berry bushes, rocks and grass tufts are instanced meshes.
- **Wildlife** (`js/animals.js`): zebra, wildebeest and gazelle herds graze, walk to water, breed and flee; elephants and giraffes roam; a lion pride rests at its rocks and hunts when hungry; vultures circle carcasses.
- **Tribes** (`js/tribes.js`): people forage berries, hunt in parties of three, farm, build and have children. A village moves through four eras (camp, village, town, kingdom), each with its own buildings. The war drum sends warriors to rally, march and fight.
- **God powers** (`js/env.js`): rain, lightning, meteor, raise land, lower land, summon a herd, drought, storm, war drum. Fire spreads through dry grass with the wind, burns trees and thatch, and is put out by rain.
- **Look** (`js/stage.js`, `js/post.js`): a day and night cycle, soft shadows, and one post-processing pass with depth-of-field for the miniature look, filmic tone mapping and a vignette.
- **Second round, after the owner's review** (same day): the map grew to 512 x 512 and fills the screen (only what is near the camera is drawn; distant land fades into haze); walls became real (everyone uses the gate); people fell trees and quarry stone, and buildings cost wood and stone; a big town sends settlers out to found a new one; hyena packs and crocodiles joined the lions, and predators eat people; new powers (plague, tornado, blessing); nature strikes on its own; synthesised sound (`js/audio.js`); a settings panel (day and night / always day / always night, volume, and switches for predators, natural disasters, new towns and haze).
- **Third round**: two more ages, the industrial city (brick townhouses, factories that burn wood, the wall comes down) and the metropolis (apartment blocks, glass towers, a landmark skyscraper). Progress has a price that the game shows: cities clear the land around them for good, hunters with guns range further and shoot anything, and the number of animals the land can carry falls with every town. In a 20-day test run the two peoples built 10 metropolises, the trees fell from 2,240 to under 200 and the wildlife was all but hunted out.
- **Deterministic**: the simulation runs in fixed 1/30 s steps from a seeded random number generator, so the same seed and the same inputs replay the same way.

## How to run

ES modules need http, so serve the directory:

```bash
cd savanna-sandbox
python3 -m http.server 8000
# open http://localhost:8000/
```

Query parameters: `lang=en|zh|es|pt|de|fr|ja|ko|it`, `seed=<n>`, `demo=1` (a 50-second scripted show reel), `ui=0` (hide the interface), `post=0` (no post-processing), `debug=models` (a line-up of every model).

Tools (need `pip install -r requirements.txt` and a local Chrome):

```bash
python3 tools/shot.py 5 20 --eval "G.setSpeed(16)"      # screenshots at 5 s and 20 s
python3 tools/scenario.py war                             # a scripted test with screenshots
python3 tools/capture.py out/demo.mp4 50 [--portrait]     # frame-exact recording of the show reel
```

## Output files

- `out/` (not committed): screenshots and recordings.
- `capture.py` also writes `<name>.events.json`, the simulation's event log (era changes, kills, fires, war) with timestamps, used to place sound effects in the video.

## Results

To be written after the review.
