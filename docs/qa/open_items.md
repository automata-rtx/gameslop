# Open items (orchestrator)

Deferred work found during production. Each line names the task that should absorb it.

- M1.6: the theme carries a `NoclipTokens` type and named text-role styles (see `game/src/ui/ui_tokens.gd` and the M0.5 commit); add them to 04 Interfaces when the HUD lands.
- M1.2 / lighting: fixture prefab paths `res://scenes/props/<stratum>/fixture_<kind>.tscn` are referenced by StratumData and do not exist yet.
- Placeholder values chosen in M0.4 (item use times, shadow bias, reverb predelay, loadout descriptions) are listed in that commit; revisit in M3.4.
- M1.4/M1.5: `g_noclip_commit` currently decays 1→0 over 300 ms; 06 §8 wants it held at 1.0 for the 250 ms pass, then decay. Add a hold.
- M1.11 / human cp-06: listen for tile step reading as ceramic (not a beep), the 60 ms silence in noclip commit, and natural sprint breath.
- M1.12/M3.1: camera parented to the body without physics interpolation may judder; consider enabling `physics/common/physics_interpolation` and mouse look in `_process`. Needs a human with a mouse.
- M1.5 follow-up: held flashlight should use the world shader with `held=1`; locker mask should use `locker_slats.gdshader`; dust particles.
- M2.4 (Echo): `Player.step_trail()` is not implemented.
- M2 / Static: inside Static the post grain goes to 0.6 and CA to 0.02 (02 §8); `CoherenceRenderer` has no feed for it yet. Proposed: `CoherenceRenderer.set_static(amount)`.
- Lighting task: the Halls fixture prefab (`scenes/props/halls/fixture_tube.tscn`) can reuse `data/materials/halls/fixture_emissive.tres`; the render bench hangs the omni 0.3 m below the tube so the ceiling reads lit.
- M1.10/M3.6: typed note text wraps with a leading space on the new line (note sheet, 1280x720 H3); UI scale for 720p arrives in M3.6; ui_dim text over bright fixtures has no backing.
