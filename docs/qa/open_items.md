# Open items (orchestrator)

Deferred work found during production. Each line names the task that should absorb it.

- M4.2 / credits: add "JetBrains Mono, Copyright 2020 The JetBrains Mono Project Authors, SIL OFL 1.1" (font bundled in M0.5).
- M1.6: the theme carries a `NoclipTokens` type and named text-role styles (see `game/src/ui/ui_tokens.gd` and the M0.5 commit); add them to 04 Interfaces when the HUD lands.
- M1.2 / lighting: fixture prefab paths `res://scenes/props/<stratum>/fixture_<kind>.tscn` are referenced by StratumData and do not exist yet.
- Placeholder values chosen in M0.4 (item use times, shadow bias, reverb predelay, loadout descriptions) are listed in that commit; revisit in M3.4.
- M2 / Static: inside Static the post grain goes to 0.6 and CA to 0.02 (02 §8); `CoherenceRenderer` has no feed for it yet. Proposed: `CoherenceRenderer.set_static(amount)`.
- Lighting task: the Halls fixture prefab (`scenes/props/halls/fixture_tube.tscn`) can reuse `data/materials/halls/fixture_emissive.tres`; the render bench hangs the omni 0.3 m below the tube so the ceiling reads lit.
