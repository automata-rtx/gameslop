# Visual targets judged by eye: T5 and T6

02 §2's T5 ("each stratum is identifiable from any single frame by palette and fixture type alone") and T6 ("each error is identifiable from a silhouette or signature at 15 m with the flashlight off") have no measurement. They are judged by eye from frames and recorded here. `tools/ci/tour_check.py` reads the table below and prints each row beside the measured T1, T3 and T4 (MANUAL for a recorded pass, FAIL for a recorded failure, OPEN where the row says `open` or no row exists). Keep one row per subject; replace a row when a newer judgement is made. The `result` column starts with `pass`, `fail` or `open`.

Frames are from the CPU renderer (`tools/ci/render.sh`, Forward+ on lavapipe) at 960x540. A real GPU at 1080p (bloom, TAA, a calibrated display) is cp-12's Part G, which also asks the human to name the stratum from one frame (T5).

How to reproduce:
- T5: `tools/ci/render.sh --path game --resolution 960x540 -- --tour build/tour`, then look at the six `build/tour/<stratum>/corridor_c100.png`.
- T6: `tools/ci/render.sh --path game --resolution 960x540 res://scenes/debug/error_arena.tscn -- --shots build/t6/<stratum> [--stratum garage|offices]` (Halls: `static_15m`; Garage: `still_15m`; Offices: `flicker_15m_a`, `flicker_15m_b`).

| target | subject | result | frame | note |
|---|---|---|---|---|
| T5 | halls | pass (2026-10-09, M3.8 tour seed 1; rechecked R20) | halls/corridor_c100 | yellow striped wallpaper, ceiling tiles, square panel fixtures |
| T5 | pools | pass (2026-10-09, M3.8 tour seed 1; rechecked R20) | pools/corridor_c100 | teal tile walls and floor, wet sheen, a line of small ceiling fixtures |
| T5 | garage | pass (2026-10-09, M3.8 tour seed 1; rechecked R20) | garage/corridor_c100 | sodium amber, low concrete deck, pillars with a painted band, box cars |
| T5 | offices | pass (2026-10-09, M3.8 tour seed 1; rechecked R20) | offices/corridor_c100 | white partitions, blue carpet, panel fixtures, a water cooler and a chair |
| T5 | server | pass (2026-10-09, M3.8 tour seed 1; rechecked R20) | server/corridor_c100 | blue haze, LED points on rack faces, a red emergency light |
| T5 | substrate | pass (2026-10-09, M3.8 tour seed 1; rechecked R20) | substrate/corridor_c100 | white grid lines on black, nothing else |
| T6 | static | pass, weak (2026-10-09, R20) | halls/static_15m | a grey, grain-filled veil fills the corridor's far end and greys the yellow walls behind it; no edge, as 02 §8 says. The refraction does not show in a still frame; its hum carries it first (02 §8 "audible before visible") |
| T6 | still | pass (2026-10-09, R20) | garage/still_15m | a dark capsule-topped column standing in the lane, a clear silhouette against the amber fog; the fog lifts its black to dark brown at 15 m |
| T6 | flicker | pass, as a pair (2026-10-09, R20) | offices/flicker_15m_a, _b | its signature is motion, so a single frame cannot show it: the group's far fixtures down the corridor at about 15 m are lit in `_a` and dark in `_b` 70 ms later while the near fixture holds, and the corridor's light falls with them. At 8 to 20 Hz on screen that is the stutter 02 §8 names; judge it moving on a GPU (Part G) |
| T6 | echo | open: by ear at cp-12 (sound-first, 02 §13 R20) | none | no body; its visual shimmer reaches only 4 m (`echo_4m_*`). At 15 m its signature is the late step, 3 dB under the player's: `docs/qa/listen_check.md` |
| T6 | null | pass, by sight and ear (2026-10-09, M3.8 tour seed 1, rechecked R20) | substrate/null_8m (tour) | no body; its signature is the world unrendering inside its 12 m radius (walls turn to see-through grid, the checker room shows through) and the grid tone (`listen_check.md`). At 15 m the player stands at the edge of that unrender |
