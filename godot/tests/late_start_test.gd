extends SceneTree
## Late start: tapping N seconds after GO must always start the user's boat.
## Run: godot --headless --path godot -s res://tests/late_start_test.gd

var _failures := 0


func _init() -> void:
	var main: SailGame = load("res://main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.hud._close_settings()

	for boats in [3, 5, 10]:
		for wait_s in [0.0, 0.5, 1.0, 1.5, 2.0, 3.0, 5.0, 8.0, 15.0]:
			main.boat_count = boats
			main.difficulty = 0
			main.reset_game()
			main.handle_tap()
			var steps := 0
			while main.state == SailGame.State.STARTING and steps < 600:
				main.sim_step()
				steps += 1
			for i in int(wait_s * 60.0):
				main.sim_step()
			var before: String = SailGame.State.keys()[main.state]
			main.handle_tap()
			var user: Boat
			for b in main.boats:
				if b.is_user:
					user = b
			var started: bool = main.state == SailGame.State.PLAYING and user.moving
			for i in 120:
				main.sim_step()
			var ok: bool = started and main.state == SailGame.State.PLAYING and not user.dsq
			print("boats=%2d wait=%4.1fs  before tap: %-8s  after tap: %-8s  playing=%s medal=%s -> %s" % [
				boats, wait_s, before, SailGame.State.keys()[main.state], started,
				main.hud._medal_rank.text if main.hud._medal.visible else "-", "ok" if ok else "FAIL"])
			if not ok:
				_failures += 1
	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)
