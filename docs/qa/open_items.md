# Open items (orchestrator)

Deferred work found during production. Each line names the task that should absorb it.

- M1.6: the theme carries a `NoclipTokens` type and named text-role styles (see `game/src/ui/ui_tokens.gd` and the M0.5 commit); add them to 04 Interfaces when the HUD lands.
- M1.2 / lighting: fixture prefab paths `res://scenes/props/<stratum>/fixture_<kind>.tscn` are referenced by StratumData and do not exist yet.
- Placeholder values chosen in M0.4 (item use times, shadow bias, reverb predelay, loadout descriptions) are listed in that commit; revisit in M3.4.
- M1.4/M1.5: `g_noclip_commit` currently decays 1→0 over 300 ms; 06 §8 wants it held at 1.0 for the 250 ms pass, then decay. Add a hold.
- M1.11 / human cp-06: listen for tile step reading as ceramic (not a beep), the 60 ms silence in noclip commit, and natural sprint breath.
