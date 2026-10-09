# Performance check (cp-12, M3.5): Part P

The machine checks cover what a CPU can measure without a graphics card: script time per system, the physics step, nodes, lights, shadows, the build slices, the navigation bake and memory growth, all at the Garage's and the Server's worst-case peak (`docs/qa/perf.md`, enforced by `tools/ci/checkpoint.sh`). Draw calls and VRAM were read on a software renderer. None of that says how fast the game draws on a real graphics card. This part is for that. The cp-12 play script refers to it as **Part P**. It takes about 20 minutes.

**What you need:** the repository, the pinned Godot (`tools/godot/fetch.sh` prints `GODOT_BIN`), and the target machine or close to it: Windows or Linux, a GTX 1060-class graphics card (or say which card you have), a 1920 × 1080 monitor. Close other programs. Use a debug run (the editor binary below): the F3 overlay exists only in debug builds.

**How to use this list:** for each item run the command or do the thing, then copy the numbers asked for into the table at the end. Write `could not` and move on if something does not work.

**The F3 overlay** (press F3 in a level). The lines you will read:

| Line | Meaning |
|---|---|
| `FPS 60   FRAME 16.7 ms   PROCESS … ms   PHYS … ms` | frames per second; the frame time (1000 / FPS); the slowest process and physics step of the last second |
| `GPU … ms   RENDER CPU … ms   VRAM … MB   MEM … MB` | the graphics card's time for the last frame; the CPU's render time; video memory; game memory |
| `DRAW CALLS …   OBJECTS …   NODES …` | draw calls and objects in the last frame; nodes in the whole game |
| `LIGHTS OMNI … SPOT … POOL …/…` | lights drawn now; the pool's lights in use and its size |
| `ERRORS MS …` (on each error's line) | the errors' script time in the last physics step |
| `DIRECTOR PEAK …` | the Director's phase |

Budgets (14 §10, Medium at 1080p): frame 16.6 ms, of which render (the GPU line) ≤ 10 ms; draw calls ≤ 1,500; drawn lights ≤ 24; VRAM ≤ 1.5 GB; errors ≤ 1.0 ms; startup to title ≤ 4 s.

---

## The list

**P1. The Server bench on your card.** Run, from the repository:

```
$GODOT_BIN --path game --resolution 1920x1080 res://scenes/debug/perf_bench.tscn -- --stratum server --seconds 30 --fps 0 --out build/perf/gpu_server.json
```

A Server level appears, the hunters close in, the lights go out and come back every 8 seconds; you do nothing. It quits by itself after about 40 seconds. Send `build/perf/gpu_server.json` with the results, and copy from it, under `metrics`: `render_gpu` mean and p95, `render_cpu` mean, `frame` mean and p95, `draw_calls` max, `vram_mb` max, `script` mean, `errors_timing` mean.

**P2. The Garage bench.** The same with `--stratum garage` and `--out build/perf/gpu_garage.json`.

**P3. Server at peak, played.** Run:

```
$GODOT_BIN --path game -- --seed 1 --depth 5 --stratum server
```

Press F3. Walk the aisles with the flashlight on until a hunter chases you (you will see `DIRECTOR PEAK` on the overlay); keep it chasing. Read the overlay at four moments and write down FPS, FRAME, GPU, RENDER CPU, DRAW CALLS, VRAM and the LIGHTS line:
- (a) standing in a long aisle looking down its length;
- (b) in the brightest place you can find, as many lit fixtures in view as possible (the bench in P1 covers the breaker's power wave: this direct launch has no breaker);
- (c) with two hunters near (`still` and `echo` lines under 10 m);
- (d) while the lights around you stutter (Flicker), flashlight on.

**P4. Garage at peak, played.** The same with `--stratum garage`, at (a) the longest view across a deck, (b) the most lamps in view, (c) two hunters near, (d) on a ramp between decks looking down the deck.

**P5. Presets.** In P3's level, stand at moment (a), open the pause menu, set the quality preset to Low, then High, and read FPS and GPU for each. High is not a 60 fps promise on a 1060 (00 §9 names Medium); write what it does.

**P6. Hitches.** Play P3 for five minutes. Note every visible stutter and what was happening: the level appearing, a contact (the hit and the push), a door, Flicker's lunge flash. The machine saw two: the frame the level appears (40 to 80 ms on the agent's CPU) and the moment a contact sends every hunter away (10 to 16 ms). Say whether you saw them.

**P7. Startup to title.** Close everything. Start the exported build (`NOCLIP.exe` or `./NOCLIP.x86_64`) with a stopwatch; stop it when the title's corridor is moving and the menu answers. Do it twice; write both times.

**P8. Ten levels.** Start a Descent and drop through the floor (hold the noclip button aimed down) on every level until depth 10 or the Threshold. At depth 1 and at the last depth, read MEM on the overlay (in a debug run: `$GODOT_BIN --path game`, then DESCEND). The machine sees no growth beyond a few MB of caches; write both numbers.

---

## Results (fill in)

| Item | Reading |
|---|---|
| Card, CPU, OS, driver | |
| P1 Server bench: render_gpu mean / p95, render_cpu, frame mean / p95, draw calls max, VRAM max, script, errors | |
| P2 Garage bench: the same | |
| P3 (a) FPS, FRAME, GPU, RENDER CPU, DRAW CALLS, VRAM, LIGHTS | |
| P3 (b) | |
| P3 (c) | |
| P3 (d) | |
| P4 (a) | |
| P4 (b) | |
| P4 (c) | |
| P4 (d) | |
| P5 Low: FPS, GPU / High: FPS, GPU | |
| P6 hitches seen (when, what) | |
| P7 startup to title, two runs | |
| P8 MEM at depth 1 and at the last depth | |
