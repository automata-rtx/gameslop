# Steam upload

What is here (`docs/design/16_release_and_steam.md` §3):

| File | What it is |
|---|---|
| `app_build.vdf.template` | The app build: names both depots, never sets a build live |
| `depot_build_windows.vdf.template`, `depot_build_linux.vdf.template` | One depot each, taking `build/windows/` and `build/linux/` |
| `upload.sh` | Fills the templates from environment variables, checks them, runs steamcmd |
| `check_vdf.py` | A small VDF parser; `upload.sh` runs it on every file it writes |
| `selftest.sh` | Proves the above without Steam (fake steamcmd); part of the test suite |

The templates hold five placeholders: `{APP_ID}`, `{DEPOT_WIN}`, `{DEPOT_LINUX}`, `{BUILD_DIR}`, `{DESCRIPTION}`. They stay as they are in the repository. `upload.sh` writes the filled copies to `build/steam/`, which is not committed. No account, password or id is stored anywhere in the repository.

## Steps (you, the human)

1. **Create the app.** In Steamworks (partner.steamgames.com) pay the app fee and create the app. Note the **app id**.
2. **Create the depots.** Steamworks > your app > SteamPipe > Depots: add one depot for Windows (operating system: Windows, 64-bit) and one for Linux (Linux, 64-bit). Note the two **depot ids**. They differ from each other and from the app id.
3. **Set the launch options.** SteamPipe > Installation > General Installation: Windows executable `NOCLIP.exe`, Linux executable `NOCLIP.x86_64`, with the matching operating system on each. Publish the changes.
4. **Make a build account.** Steamworks > Users and Permissions: a separate user with only the "Edit App Metadata" and "Publish App Changes To Steam" permissions. Do not use your main account. Turn Steam Guard on and log in once by hand (`steamcmd +login <account>`, enter the code) so steamcmd caches the login.
5. **Install steamcmd** (Linux: `sudo apt install steamcmd`, or Valve's tarball from developer.valvesoftware.com/wiki/SteamCMD; Windows: Valve's zip). Run it once so it updates itself.
6. **Export the builds.** `tools/ci/export.sh` writes `build/windows/` and `build/linux/`. Upload from the machine that exported, so the Linux binary keeps its executable bit.
7. **Set the variables** in your shell only (never in a file in the repository):
   ```
   export STEAM_APP_ID=<app id>
   export STEAM_DEPOT_WIN=<windows depot id>
   export STEAM_DEPOT_LINUX=<linux depot id>
   export STEAM_USER=<build account name>
   # export STEAM_PASSWORD=<password>   # optional; omit it to use the cached login
   # export STEAM_DESCRIPTION="release candidate 2"   # optional; default "NOCLIP <version>"
   ```
   A password in `STEAM_PASSWORD` is visible to other users on the same machine while steamcmd runs (command lines are). On a shared machine use the cached login and leave it unset.
8. **Check first.** `tools/steam/upload.sh --dry-run` fills and validates the three VDF files in `build/steam/` and stops. Read them.
9. **Upload.** `tools/steam/upload.sh`. It refuses to run if any id is unset, still a placeholder, not a positive integer, 480 (Valve's test app), or if two ids match. It prints the app and depot ids and the version, never the account or password (steamcmd output is filtered for both).
10. **Go live.** The upload never sets a build live. In Steamworks > SteamPipe > Builds, set the build live on a branch (start with a private test branch), then install it through the Steam client and check it on both platforms.
11. **Store page.** Paste the facts from `docs/release/store_page.md`, upload the screenshots listed there, and submit the page for review. Steam's review takes a few days; the build review is separate.

## Options

- `STEAM_BUILD_DIR` points at another folder holding `windows/` and `linux/` (default `build/`).
- `STEAMCMD` names the steamcmd binary if it is not on `PATH`.

## If something fails

- "no Windows build" or "no Linux build": run `tools/ci/export.sh` first.
- steamcmd asks for a Steam Guard code: log in by hand once (step 4), or set the code with `+set_steam_guard_code` yourself; the script does not take a code.
- A depot upload that produces no files: check `FileMapping` in the depot template and that `build/windows/` and `build/linux/` are not empty.

Nothing here has been run against Steam; the agents that wrote it cannot reach it. The first real upload is the test.
