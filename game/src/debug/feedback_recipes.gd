class_name FeedbackRecipes
extends FeedbackRecipesWorld
## The recipe set the bench calls by row id (see FeedbackRows). The recipes live in the
## three classes above this one: base helpers, the player's own actions, and the world.


## 11 §3 Threshold crossed (R17): the run's own crossing (Run._cross_threshold) on the bench's
## run, which stays on screen (no ending scene): the white cut layer's alpha (I), the single
## low tone (S), the HUD gone (R). It ends the Descent, so it runs last; after the dissolve
## row a fresh Descent record stands in, so end_run has a run to close.
func threshold(b: FeedbackBench) -> void:
	b.run.threshold_scene = ""
	if not GameState.is_run_active():
		GameState.start_run(Tuning.MODE_DESCENT, FeedbackBench.LOADOUT, FeedbackBench.RUN_SEED)
	b.run.hud.visible = true
	probe(b, &"I", "white", func() -> float:
		var rect := b.run.get_node_or_null(^"WhiteCut/WhiteRect") as ColorRect
		return rect.color.a if rect != null else 0.0)
	await b.arm()
	b.anchor()
	b.run._cross_threshold()
	await b.ticks(20)
	# No ending scene follows here: the next ending must not take this cut up.
	Ending.cut_at_ms = -1
