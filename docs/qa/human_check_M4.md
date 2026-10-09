# Clean-machine run: cp-13 (about 20 minutes, needs a GPU)

M4 made the release candidate: the exports, the icons, the checksums, the Steam templates, the store page facts. The machines have run everything they can (`docs/qa/release_checklist.md`, the M4.3 section): the export pipeline, the release verifier, the Linux smoke, and the save, settings, Daily and ending tests. What no container can do is be a stranger's computer. This script is that stranger. You are a player who just downloaded the zip: **no Godot, no repository, no editor**. Nothing here is pass or fail by feeling; each numbered item is a plain observation to confirm, and each has a line in `docs/qa/notes_cp-13.md`. Short answers; write `could not` where a thing never happened.

Do Parts 1 to 11 on **Windows** (the platform most players have). If you also have a Linux machine, do Part 12 there. The Parts are in the order you meet them. Times in `[ ]` are a guide: Parts 1 to 4 about 5 minutes, Parts 5 to 7 about 8, Parts 8 to 11 about 7.

---

## 0. Before you start

- Use a machine that has **never run NOCLIP** and has no Godot. If it has run it, say so in the notes and delete `%APPDATA%\NOCLIP\` first.
- A GPU with Vulkan 1.2 and 2 GB of video memory, keyboard and mouse, headphones. Close other programs.
- Copy `docs/qa/notes_cp-13.md` and keep it open beside the game.
- Have the `NOCLIP-1.0.0-SHA256SUMS.txt` that came with the zips. The hashes written in `docs/qa/release_checklist.md` come from one agent export and will differ from yours; the file beside your zip is the reference.

## 1. Get the build `[0:00]`

You need `NOCLIP-1.0.0-windows.zip` and `NOCLIP-1.0.0-SHA256SUMS.txt`. `build/` is not committed, so the checkpoint branch does not carry them. Either:

1. **They are handed to you.** The orchestrator exports from the branch named in `docs/checkpoints.md` under `cp-13-rc` (expected `checkpoint/cp-13-rc`), checks it with `tools/ci/verify_release.sh`, and sends the zips. Write who made them and the commit in the notes. Or
2. **You make them** on Linux or WSL, from a clone of the repository (needs `zip` and `sha256sum`):
   ```
   git fetch origin
   git checkout checkpoint/cp-13-rc
   tools/godot/fetch.sh --templates       # the pinned Godot 4.7.2 and its export templates
   tools/ci/export.sh                     # writes build/NOCLIP-1.0.0-windows.zip, -linux.zip and build/NOCLIP-1.0.0-SHA256SUMS.txt
   tools/ci/verify_release.sh             # must end with: OK (NOCLIP 1.0.0)
   ```
   Copy the Windows zip and the SHA256SUMS file to the test machine by the same route a player's download takes (a USB stick, a download).

1. Did the files arrive? Write the zip's size (expected about 57 MB) in the notes.

## 2. Verify the checksum `[1:00]`

In PowerShell, in the folder holding the zip:

```
certutil -hashfile NOCLIP-1.0.0-windows.zip SHA256
```
(or `(Get-FileHash NOCLIP-1.0.0-windows.zip -Algorithm SHA256).Hash`). Compare with the line for `NOCLIP-1.0.0-windows.zip` in `NOCLIP-1.0.0-SHA256SUMS.txt`; case does not matter.

2. Do they match, every character? Write the first 8 characters in the notes.

## 3. Unzip to a fresh folder `[2:00]`

Unzip into a new empty folder such as `C:\Games\NOCLIP-test` (Explorer: Extract All; or `Expand-Archive`). It should make one folder, `NOCLIP-1.0.0-windows`, and nothing else.

3. Does that folder hold exactly `NOCLIP.exe`, `NOCLIP.pck`, `README.txt`, `LICENSES.txt`, `SHA256SUMS.txt`? An extra or missing file is a defect.
4. Open `README.txt` in Notepad. Are the lines separate (not one long line)? Does it list the controls and the save folder `%APPDATA%\NOCLIP\`, and say the game was made by an AI?
5. In that folder run `certutil -hashfile NOCLIP.exe SHA256` and compare with the `NOCLIP.exe` line in the inner `SHA256SUMS.txt`. Match? (The README gives this command.)
6. Type `%APPDATA%` in the Explorer address bar. Is there **no** `NOCLIP` folder yet? If there is, the machine is not clean; say what is in it.

## 4. First launch `[4:00]`

Double-click `NOCLIP.exe`.

7. Did Windows show **SmartScreen** ("Windows protected your PC")? The exe is unsigned, so this is expected. Write exactly what it said and what you clicked (More info, Run anyway). Did **antivirus** say anything? Which product, and what?
8. Did a **console window** (a black box with text) appear at any moment, even for a second? None should. Check the taskbar as well.
9. Seconds from the double-click to something on screen, and to the title, by feel. The first launch may stutter while shaders compile; say if it did.
10. Is the game fullscreen without a border (the default)? Is the title readable, and does its bottom line read `v1.0.0 · MADE BY AN AI · SEED OF THE DAY <date>`?
11. Do the taskbar button and the title bar (if shown) carry the NOCLIP icon, not the Godot icon?

## 5. The first-run flow `[6:00]`

12. Open SETTINGS from the title and **write down the defaults** as found. Expected: WINDOW MODE Fullscreen, FIELD OF VIEW 90, BRIGHTNESS 1.0, PRESET Medium, MASTER 80, MUTE WHEN UNFOCUSED on, HINTS on. Anything else, say what.
13. Make two changes. CONTROLS tab: rebind **Flashlight** (default F) to `G` (select the row, press Enter, press G). Does the row now show G? AUDIO tab: set MASTER to 60. Back out to the title.
14. Open `%APPDATA%\NOCLIP\` in Explorer. Does it exist now, where the README says? List what is in it (expected: `settings.cfg`, perhaps `meta.json`, a `shader_cache` folder).
15. Press DESCEND. Do the first-run hints appear (the move line first, then the flashlight line)? Does the flashlight hint name **G**, the key you set, rather than F?

## 6. One Descent to depth 2 `[8:00]`

Play naturally; skill is not being tested. The point is the real game on a fresh machine. The target is depth 2 within three Descents (`00` §9); stop at depth 2 or after the third Descent, whichever comes first.

16. How many Descents did it take to reach depth 2, and how did each end (the cause the summary names)?
17. Any hitch, freeze, crash, or black or magenta screen other than the Substrate's designed checker? Where, how long?
18. Open Task Manager (Ctrl+Shift+Esc) once at depth 2. Write the NOCLIP process's memory in MB, and whether the CPU or GPU looks pegged.
19. Did sound work at once on your default output device? Any crackle or gap?

## 7. Quit and relaunch: persistence `[12:00]`

End the session through the game: Esc, QUIT TO TITLE, then QUIT from the title (or die, read the summary, go to the title, QUIT).

20. `%APPDATA%\NOCLIP\` should now hold `meta.json`. Is its modified time the end of your run? (Do not edit it.)
21. Launch `NOCLIP.exe` again. Does it reach the title with your run in the Archive (ARCHIVE, Statistics)? Is the settings screen unchanged?
22. SETTINGS: is Flashlight still `G` and MASTER still 60?
23. DESCEND again. Do the hints you already saw stay retired or repeat in order? (Write which; they retire at depth 3.) Does the flashlight hint, if shown, still name G?
24. Put the defaults back: CONTROLS, RESET TAB TO DEFAULTS; AUDIO, MASTER 80.

## 8. Another keyboard layout, if you can `[14:00]`

Key names in Settings come from the OS layout, not the keycap (`12` §5). If you have a French keyboard, or can add the layout (Windows Settings, Time & language, Language, add French (France), AZERTY; switch with Windows key + Space):

25. With AZERTY active, does the CONTROLS tab show Move as Z Q S D, not W A S D? In play, do the keys that move you match what the screen names?
26. Switch the layout back.

If you cannot, write `could not`.

## 9. The Daily lock `[15:00]`

Daily Descent unlocks at depth 3. To test it without playing three levels, use the save fixture. **Quit the game**, rename `%APPDATA%\NOCLIP\meta.json` to `meta.json.mine`, copy `docs/qa/fixtures/meta_m2_mid_save.json` (from the repository, not the zip) in as `meta.json`, and launch.

27. Does the title list DAILY DESCENT, and does its panel say "One attempt per day. Faller loadout. Every item is in the pool."?
28. Select it, move a few steps, press Esc, choose ABANDON DESCENT, confirm ABANDON. Back on the title, is DAILY DESCENT now **not selectable**, with the panel reading "Today's attempt is spent. A new seed arrives at midnight UTC." and a result line (SCORE and DEPTH)?
29. QUIT and relaunch. Still locked?
30. If your clock was within an hour of 00:00 UTC, say so: the lock lifts at midnight UTC, not local midnight.
31. Restore: delete `meta.json`, rename `meta.json.mine` back.

## 10. Alt-tab and window modes `[17:00]`

Press DESCEND and stand still in the first corridor, where the lights hum.

32. Press Alt+Tab to another window. Is the cursor visible and free at once? Does the game go **silent** (MUTE WHEN UNFOCUSED is on)? Does the game keep running underneath or pause? Write which.
33. Alt+Tab back. Is the mouse captured again at once, or only after a click? Does the view jump? Does the sound return?
34. Esc, SETTINGS, DISPLAY. Set WINDOW MODE to Windowed. Does a KEEP / REVERT prompt with a countdown appear? Press KEEP. Is it now a window you can move?
35. Set the largest resolution your monitor offers above 1080p (2560 x 1440 if you have it), then back to Fullscreen. Does the UI fit at each with nothing cut off, and does the cursor behave in each mode?
36. Alt+Tab while windowed, then while fullscreen. Any stuck cursor, black frame, or the game appearing on the wrong monitor?
37. QUIT TO TITLE, QUIT. Is the NOCLIP process gone from Task Manager?

## 11. Uninstall `[19:00]`

38. Delete `C:\Games\NOCLIP-test`. Does it delete cleanly, with no "file in use"?
39. Look at `%APPDATA%\NOCLIP\`. Your save and settings stay there on purpose; the README says "Delete the folder to start over". List what is left. Is anything else left that you can find outside it (`%APPDATA%\Godot`, `%LOCALAPPDATA%`, the Start menu, the desktop)? Nothing is expected.
40. Delete `%APPDATA%\NOCLIP\` as well. Done.

## 12. Linux, if you have a machine (about 15 minutes)

Use `NOCLIP-1.0.0-linux.zip`. Same observations, with these commands:

```
sha256sum NOCLIP-1.0.0-linux.zip                       # compare with NOCLIP-1.0.0-SHA256SUMS.txt
unzip NOCLIP-1.0.0-linux.zip -d ~/noclip-test
cd ~/noclip-test/NOCLIP-1.0.0-linux
sha256sum -c SHA256SUMS.txt                            # every line OK
ls -l NOCLIP.x86_64                                    # the x bit must be set (-rwxr-xr-x)
./NOCLIP.x86_64
```

- L1. Is the executable bit set right after `unzip`? (A file manager's extractor may drop it; say which tool you used.)
- L2. Does it start from a terminal and from a double-click? Does the terminal print any error?
- L3. Does `~/.local/share/NOCLIP/` (or `$XDG_DATA_HOME/NOCLIP/`) exist after the first launch?
- L4. Repeat items 12 to 15 (defaults, rebind, hints), 20 to 23 (persistence), 27 to 29 (Daily) and 32 to 36 (alt-tab, window modes). Say X11 or Wayland and the GPU driver; mouse capture on alt-tab may differ on Wayland.
- L5. Uninstall: `rm -r ~/noclip-test`, then `ls ~/.local/share/NOCLIP` and remove it.

---

## cp-12 decisions still pending human data

cp-13 also applies the cp-12 tuning decisions. The cp-12 play script (`docs/qa/human_check_M3.md`, notes in `docs/qa/notes_cp-12.md`) has not come back with data: `notes_cp-12.md` is still the empty template. **If you played it, bring those notes** (commit the file or paste it) along with `notes_cp-13.md`; the orchestrator makes these calls from them. If you did not, the Descents of Part 6 are a small sample for row 4 only, labelled as such; they do not replace the five runs.

| # | Pending decision | What the data must say | Where it is recorded |
|---|---|---|---|
| 1 | **Landing gain, 20 or 10** (R20, review S1, pre-agreed) | Over runs reaching depths 3 to 6: average Coherence on arrival of 90 or more (with fewer than 2 noclips a level) halves the gain to 10 (`05` §4, `06` §9; `tuning.gd` and `test_tuning.gd` together, CHANGELOG with the data). Below 70 it stays 20. Between 70 and 90 the orchestrator decides from the notes. | `notes_cp-12.md`, Descents table, "Coherence at each arrival" |
| 2 | The Substrate is hard but winnable at Null's 10/s drain; do players route around the core with the unrender view or walk through it | Depth reached, cause, Null core time | cp-12 Part T, "Null again" |
| 3 | Still's counter works for a human (lit in view and back away, or hide) at depths 2 and 5; the sims saw 3 evasions in 279 levels and no Still number was changed | Which counter worked every time, sometimes, never | cp-12 Part T, "Still evasion" |
| 4 | A new player reaches depth 2 within three attempts; early deaths take 5 to 10 minutes | Attempts and minutes per Descent (also item 16 here) | cp-12 Descents table |
| 5 | The Offices light dilemma reads as a choice | Yes or no, and why | cp-12 Part T, "The Offices light dilemma" |
| 6 | How much noclip a human spends; Coherence arriving at depth 6 (sims: 90 and more) | Walls and drops per level; arrival Coherence | cp-12 Part T, "Noclip budget" |
| 7 | The sawtooth by ear: a long Build while exploring should not sit at maximum dread | Whether dread felt flat at the top | cp-12 core stages and Part L |
| 8 | Re-arming the 0.8 wake after Build holds 0.95 for 60 s with no chase (`open_items.md`, S2 second step) | Only if row 7 says the top was flat | `docs/qa/open_items.md` |
| 9 | Left to the human by design: frame times (Part P), the unrender halo, the checker under AgX, bloom, every sound (Part L) | `build/perf/*.json` and the Part L answers | cp-12 notes |

Also: say in `notes_cp-12.md` which five runs are the tuning sample (M3 review N6).

## Reporting back

1. Fill in `docs/qa/notes_cp-13.md` in place; it has one block per Part with the item numbers above.
2. Hand it back by committing it on a branch and pushing, or by pasting it into the conversation. Add screenshots of any prompt (SmartScreen, antivirus) and of any defect.
3. For a defect: the item number, the step before it, one sentence. For a problem inside a level, the depth, the stratum and what you were doing; the title shows only the seed of the day.
4. Not covered by this script, by design: frame-time numbers (cp-12 Part P), audio by ear (Part L), the Steam install (`tools/steam/README.md`, M4.2 table), and the store page in Steamworks.
