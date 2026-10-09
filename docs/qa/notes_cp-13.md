# Notes: cp-13 clean-machine run

Fill this in while you follow `docs/qa/human_check_M4.md`. Item numbers match that file. Short answers; `could not` where a thing never happened.

## Setup
- Date, name:
- Where the zips came from (who exported, branch, commit):
- Machine: OS and version, CPU, GPU and driver, monitor and resolution:
- Never ran NOCLIP before, no Godot installed (yes / no):
- Linux machine too (distro, X11 or Wayland, GPU driver):
- cp-12 notes brought (yes / no / where):

## Part 1 to 3. Download, checksum, unzip
- 1. Zip size and name:
- 2. Zip hash first 8 characters; match (yes / no):
- 3. Folder contents exactly the five files (yes / no; extras or missing):
- 4. README.txt: lines, controls, save folder, AI line:
- 5. NOCLIP.exe hash matches the inner SHA256SUMS.txt:
- 6. `%APPDATA%\NOCLIP\` absent before first launch:

## Part 4. First launch
- 7. SmartScreen (exact text, what I clicked); antivirus (product, message):
- 8. Console window at any moment (yes / no):
- 9. Seconds to first frame, to title; stutter:
- 10. Fullscreen borderless; title readable; version line as expected:
- 11. Icon in the taskbar and window:

## Part 5. First-run flow
- 12. Defaults as found (window mode, FOV, brightness, preset, master, mute when unfocused, hints):
- 13. Rebound Flashlight to G (row shows G); MASTER 60:
- 14. `%APPDATA%\NOCLIP\` contents after first launch:
- 15. Hints appeared in order; flashlight hint names G:

## Part 6. One Descent to depth 2
| # | Seed or note | Deepest depth | How it ended (cause) | Minutes |
|---|---|---|---|---|
| 1 | | | | |
| 2 | | | | |
| 3 | | | | |
- 16. Descents to reach depth 2:
- 17. Hitch, freeze, crash, wrong colours (where, how long):
- 18. Task Manager at depth 2 (MB, CPU, GPU):
- 19. Sound at once; crackle:

## Part 7. Quit and relaunch
- 20. `meta.json` present, time matches the run end:
- 21. Archive shows the run; title and settings unchanged:
- 22. Flashlight still G, MASTER still 60:
- 23. Hints after relaunch (retired / repeated):
- 24. Defaults restored:

## Part 8. Other layout
- 25. AZERTY shows Z Q S D; play matches the screen:
- 26. Layout switched back:

## Part 9. Daily lock
- 27. DAILY DESCENT listed with its rules text:
- 28. After ABANDON: not selectable; spent text; result line:
- 29. Still locked after relaunch:
- 30. Clock near 00:00 UTC (yes / no):
- 31. Own save restored:

## Part 10. Alt-tab and window modes
- 32. Alt-tab out: cursor free; silent; game keeps running or pauses:
- 33. Alt-tab in: capture at once or after a click; view jump; sound back:
- 34. Windowed: KEEP / REVERT prompt; movable window:
- 35. Resolution above 1080p and back; UI fits; cursor:
- 36. Alt-tab windowed and fullscreen; stuck cursor, black frame, wrong monitor:
- 37. Process gone after QUIT:

## Part 11. Uninstall
- 38. Folder deleted cleanly:
- 39. What remains in `%APPDATA%\NOCLIP\`; anything elsewhere:
- 40. Folder deleted:

## Part 12. Linux
- L1. Executable bit after unzip (tool used):
- L2. Starts from terminal and double-click; terminal errors:
- L3. Save folder location:
- L4. Items 12 to 15, 20 to 23, 27 to 29, 32 to 36 (differences only):
- L5. Uninstall leftovers:

## cp-12 decisions: data brought
- Landing gain: runs reaching depths 3 to 6, arrival Coherence per run, average, noclips per level:
- Which five runs are the cp-12 tuning sample:
- Null / Still / Offices / noclip budget / sawtooth: see `notes_cp-12.md` (filled in yes / no):
- Part P `build/perf/*.json` handed back (yes / no):

## Defects (item number, step before, one sentence)
-
