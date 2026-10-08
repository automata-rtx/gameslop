# NOCLIP — agent entry point

NOCLIP is a first-person horror roguelite built in Godot 4.7 (GDScript, Forward+). The whole game is designed in `docs/design/` and is being built by AI agents. The design is locked; build what it says.

## Read this first
1. `docs/design/00_OVERVIEW.md` (always).
2. Only the system documents your task names. Each ends with an "Interfaces" contract.
3. `docs/design/GLOSSARY.md` for canonical names. Use them in code, UI strings, and docs.
4. The Godot skill for your domain under `third_party/gd-agentic-skills/skills/<skill>/SKILL.md` (the document lists which). Skills are reference material; the design documents win on any conflict.

## Repository
- `game/` is the Godot project. `tools/` holds scripts. `docs/` holds the design, QA checklists, and release notes. `third_party/` is reference only and is never shipped.
- Layout, autoloads, the signal bus, conventions, layers, budgets, and testing: `docs/design/14_technical_architecture.md`.
- Milestones, tasks, roles, model recommendations, and the checkpoint protocol: `docs/design/15_production_plan.md` §1. Production never waits for the human; it stops only to mark green checkpoints: tag `cp-NN-<slug>` plus branch `checkpoint/cp-NN-<slug>` (the proxy may block tag pushes; the branch always goes up), with a note in `docs/checkpoints.md`.

## Commands
```
tools/godot/fetch.sh                          # downloads the pinned Godot into tools/godot/bin (sets GODOT_BIN)
$GODOT_BIN --headless --path game --import    # import after asset changes
tools/ci/test.sh                              # run the test suite headless (the merge gate; --filter <name> while iterating)
tools/ci/checkpoint.sh                        # full suite with 1,000 seeds and budgets enforced, validator, smoke, exports (before a tag)
python3 tools/audio/synth.py --out game/assets/audio   # regenerate all audio from recipes
$GODOT_BIN --path game -- --seed 1 --depth 1 --stratum halls   # launch straight into a level (needs a GPU)
tools/ci/render.sh --path game -- --tour build/tour   # screenshot tour on the CPU renderer
tools/ci/render.sh --path game res://scenes/debug/<bench>.tscn   # any scene, rendered
```
Agent containers have no GPU, but `tools/ci/render.sh <godot args>` runs the real Forward+ renderer on the CPU (Mesa lavapipe under Xvfb). Use it to capture screenshots (`get_viewport().get_texture().get_image().save_png(...)`) and look at them with your image-reading tool: composition, palette, shaders, UI layout. It is slow (expect a few fps at 1080p; render at 960x540 when you can) and says nothing about real frame times. Logic tests stay headless. Say in your report what you verified visually and what still needs a real GPU.

## Rules
- Numbers live in the design documents and are mirrored in `game/src/core/tuning.gd`. Change both or neither.
- Do not add autoloads or `EventBus` signals beyond `14_technical_architecture.md` §3 and §4 without a `docs/design/CHANGELOG.md` entry and the orchestrator's agreement.
- Each error has one rule, one counter, one tell, one cost (`08` §1). Do not add behaviours.
- No imported meshes or image textures (`02` T8). Primitives, procedural noise, hand-written SVG, synthesized audio.
- Never use the forbidden words in game text (`01` §2).
- No `randi()`/`randf()` in gameplay or generation; seeded `RandomNumberGenerator` only.
- Typed GDScript, `StringName` ids, `%UniqueName` node access, signals up and calls down.
- Every task ships tests or a bench scene update, and a 10-line report. Never merge with `tools/ci/test.sh` red.
- Do not commit `tools/godot/bin/`, `game/.godot/`, or `build/`.
- Do not include model names in commits, code, or game text. The credits say "an AI (Claude, Anthropic)" and nothing more specific.
