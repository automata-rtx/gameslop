# 13 — Save Data and Meta

**Depends on:** `00_OVERVIEW.md`, `05_run_structure_and_progression.md`, `12_settings_and_accessibility.md`
**Skills to read:** `godot-save-load-systems`, `godot-resource-data-patterns`

---

## 1. Files (all under `user://`)

| File | Format | Content | Written |
|---|---|---|---|
| `settings.cfg` | `ConfigFile` | Every setting (`12`) and bindings | On change, debounced |
| `meta.json` | JSON | Unlocks, statistics, notes found, codex counters, daily history, Polaroid images seen, best scores | At run end, at unlock, at note pickup, at level transition (atomic: write `meta.json.tmp`, then rename) |
| `run_telemetry/*.csv` | CSV | Debug builds only, per level (`10` §9) | Debug builds only |
| `screenshots/` | PNG | Screenshot tour output (`14` §9) | Tour mode only |

There is **no mid-run save** in v1.0. Quitting during a run abandons it (confirmation in the pause menu). The run's notes found and statistics are kept because they are written as they happen. (The run is not saved to prevent save-scumming; a mid-run "suspend" is a listed post-1.0 feature.)

## 2. `meta.json` schema (version 1)

```json
{
  "version": 1,
  "created_at": "2026-10-07T00:00:00Z",
  "first_descent_done": false,
  "unlocks": { "glowstick": true, "radio": false, "...": false },
  "notes_found": ["H1", "H3"],
  "codex": { "still": 2, "echo": 0, "flicker": 0, "null": 0, "static": 5 },
  "polaroids_seen": [0, 3],
  "stats": {
    "runs": 12, "wins": 1, "best_depth": 6, "best_score": 4880,
    "deaths_by": { "still": 4, "echo": 2, "flicker": 1, "static": 1, "null": 3, "substrate": 0 },
    "distance_walked_m": 15320.5, "walls_passed": 41, "floors_dropped": 7,
    "coherence_spent": 1180, "notes_total": 9, "evasions": 23, "time_played_s": 9120,
    "breakers_thrown": 10, "depth_reached_counts": { "3": 5, "4": 2 }, "items_used": { "polaroid": 9, "glowstick": 12 }
  },
  "daily": { "20261007": { "score": 2310, "depth": 3, "cause": "still" } },
  "last_run": { "cause": "still", "depth": 3, "stratum": "garage", "score": 2310, "seed": 123456789 },
  "endless_best_depth": 0,
  "cycle_unlocked": false
}
```

Rules: unknown keys are preserved on load; missing keys get defaults; `version` migrations are explicit functions. Values are validated (depth 1 to 999, scores ≥ 0). A corrupt file is renamed `meta.json.bad` and a fresh file is created; the title shows `ARCHIVE RESET` once.

## 3. What persists and when

| Event | Written |
|---|---|
| Note picked up | `notes_found`, `stats.notes_total`, unlock #14 check |
| Error `noticed_player` | `codex[id] += 1`, codex unlocks |
| Level transition | `stats` increments (distance, walls, drops, coherence spent), `best_depth` |
| Unlock earned | `unlocks[id] = true` |
| Run end | `stats.runs/wins/deaths_by/time_played`, `last_run`, `best_score`, `daily[...]` if daily, `endless_best_depth` |
| Ending | `cycle_unlocked`, `unlocks.endless` |

## 4. Daily seed

`run_seed = hash("NOCLIP:" + UTC date as "YYYYMMDD")` using Godot's `hash()` on the string (the same expression as `05` §8). One attempt per day: if `daily[today]` exists, the title's DAILY item shows the result and is not selectable. Local only; no network.

## 5. The Archive (meta presentation, `04` §7)

- Notes grid 6 × 6 by stratum and ID; unread found notes blink once on first Archive open.
- Errors: entries lock/unlock by `codex` counts (first notice: name and silhouette glyph; 3 notices: counter line as builder memo, `08`).
- Statistics: the `stats` block formatted; Polaroid images seen shown as small thumbnails.
- Unlocks: the 14 milestones with their condition and a `check`/`cross` glyph.

## 6. Threaded writes

`meta.json` writes are small (< 10 KB) and done on the main thread with the atomic rename; the save/load skill's threading guidance applies only if the file grows beyond 100 KB, which the schema cannot.

## 7. Verification

- Unit tests: round-trip serialisation, migration from a synthetic version 0, corrupt file recovery, atomic write (simulate a crash between tmp write and rename), daily hash stability across platforms (same string hash on Windows and Linux: Godot's `hash()` is deterministic).

## Interfaces

- `SaveManager` autoload: `load_meta() -> MetaState`, `save_meta()`, `reset_meta()`, `backup_corrupt(path)`.
- `MetaState` (in `GameState`): typed accessors for everything in §2 plus `is_unlocked(id)`, `earn(id)`, `note_found(id)`, `codex_notice(id)`, `record_run(result)`.

### Interface additions during production

- M2.10: the schema, validation and migrations live in `MetaSchema` (`game/src/core/meta_schema.gd`, pure): `migrate(d)` (version 0 is the synthetic layout with no `version` key and `unlocks` as a list of ids), `from_dict(d)`, `to_dict(meta)`, `default_stats()`. `stats.strata_reached` (array of stratum ids) is added to the v1 stats block: a stratum counts as reached when a run leaves it or ends in it, so tier 2 notes (01 §6) appear from the next visit. `stats.notes_total` counts note pickups (once per run per note). `stats.items_used` and `stats.breakers_thrown` follow `EventBus.item_used` and `breaker_thrown` and are written with the next persistence event.
- `MetaState` also has `depth_count(depth)`, `stratum_reached(id)`, `has_reached_stratum(id)`, `add_stat(key, amount)`, `item_used(kind)`, `has_daily(key)`, `daily_result(key)`, `notes_count_except(id)`, `to_dict()`, `from_dict(d)`; `record_run(result)` takes `cause, depth, stratum, score, seed, mode, won, seconds, daily_key` and never counts `depth_reached_counts` (`GameState.descend` does, once per run per depth).
- `SaveManager`: `save_meta(meta = GameState.meta) -> bool`, `reset_meta() -> MetaState` (also assigns `GameState.meta`), `meta_path()`, `tmp_path()`, `bad_path()`, `has_reset_notice()`, `consume_reset_notice() -> String` (returns `Strings.TITLE_ARCHIVE_RESET` once after a reset; the title shows it), `directory` (defaults to `user://`; under the headless test runner or any SceneTree script it is `user://tests`, wiped at start, so tests never touch the player's Archive), `crash_before_rename` (test hook). When `meta.json` is missing but `meta.json.tmp` parses, the tmp is used; a stale tmp next to a good `meta.json` is removed. If renaming onto an existing file fails, the old file is removed and the rename retried.
- `project.godot` uses a custom user folder (`application/config/use_custom_user_dir`, name `NOCLIP`): `%APPDATA%\NOCLIP` on Windows, `~/.local/share/NOCLIP` on Linux.
- M2.12 (additive, version stays 1): `notes_read` (found note ids the Archive has shown; ids not in `notes_found` are dropped), `hints_shown` (04 §9 hint ids, `Strings.HINT_IDS`; unknown ids dropped), `hints_retired` (bool). Missing keys default to empty / false. `MetaState.unread_notes()`, `mark_notes_read(ids) -> bool`.
