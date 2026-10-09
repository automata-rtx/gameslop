# Release checklist

Copy of `docs/design/16_release_and_steam.md` §4, ticked per build.

| Check | Windows | Linux | Notes |
|---|---|---|---|
| Clean-machine launch | | | |
| First-run flow (title → depth 2 within 3 attempts) | | | |
| Settings persist; AZERTY key names | | | |
| Alt-tab mouse capture; mute when unfocused | | | |
| 10 levels, memory flat | | | |
| Tour matches visual targets | | | |
| Feedback Contract complete | | | |
| Death by each error and the win write meta.json | | | |
| Ending, credits, Endless | | | |
| Daily locks after one attempt | | | |
| Forbidden words grep clean | | | Automated by tests/unit/test_text_gate.gd; re-read the store page text by hand |

## Store and Steam (M4.2)

Ticked by the agent where a machine can do it; the rows marked "human" need Steamworks or a screen.

| Check | Status | Notes |
|---|---|---|
| Steam templates carry the five placeholders (`{APP_ID}`, `{DEPOT_WIN}`, `{DEPOT_LINUX}`, `{BUILD_DIR}`, `{DESCRIPTION}`); no real id or credential committed | done | `tests/unit/test_store_and_steam.gd` |
| VDF syntax valid for the templates and for the filled files | done | `tools/steam/check_vdf.py`; `upload.sh` checks every file it writes |
| `upload.sh` refuses unset, placeholder, zero, 480 and duplicate ids; never prints the account or password | done | `tools/steam/selftest.sh` with a fake steamcmd, run by the test suite |
| `upload.sh --dry-run` on the real exported builds | human | After `tools/ci/export.sh`; ids from Steamworks |
| Real upload to a private branch; install through the Steam client; launch on Windows and Linux | human | `tools/steam/README.md` steps 1 to 10; first contact with Steam, nothing here has been run against it |
| Linux binary keeps its executable bit after the Steam install | human | Check in the installed folder |
| `docs/release/store_page.md` sections in the order of 16 §5; short description verbatim and at most 300 characters | done | `tests/unit/test_store_and_steam.gd` |
| Store page text passes the text gate (forbidden words, punctuation, model names); the gate's planted page fires | done | `tests/unit/test_text_gate.gd`; "liminal" allowed on this page only |
| Store page figures match the game (6 strata, 5 errors, 36 notes, 14 unlocks, 4 loadouts) | done | Notes, loadouts, errors and strata counted from `DataRegistry`; the 14 unlocks are 16 §5 and 05 wording, not counted by a test |
| Store page re-read by hand once more | human | Last check before paste |
| Eight screenshots captured at 1920 x 1080 from the listed frames and looked at | human | `docs/release/store_page.md` §13; frame 8 is Coherence 10, not 15 (tour steps) |
| Capsule art made from the title background, NOCLIP only | human | No capture helper yet |
| Store page, AI disclosure, content survey, price entered in Steamworks | human | The suggested price is USD 2.99 |
