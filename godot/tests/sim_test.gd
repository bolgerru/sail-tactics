extends SceneTree
## Headless smoke test: plays races at every difficulty, checks that nothing
## errors and that the state machine behaves.
## Run: godot --headless --path godot -s res://tests/sim_test.gd

var _failures := 0


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		print("FAIL: ", msg)


func _init() -> void:
	var main: SailGame = load("res://main.tscn").instantiate()
	root.add_child(main)
	await process_frame

	# Opening dialog blocks input; dismiss it by saving defaults.
	_check(main.hud.settings_open, "settings dialog opens on launch")
	main.hud.settings_saved.emit({"speed": 0.2, "boats": 3, "radius": 15.0, "chaos": false,
		"god": false, "difficulty": 0, "sound": false})
	main.hud._close_settings()

	# --- Black flag: tap during countdown ---
	_check(main.state == SailGame.State.WAITING, "starts waiting")
	main.handle_tap()
	_check(main.state == SailGame.State.STARTING, "tap starts countdown")
	main.handle_tap()
	_check(main.state == SailGame.State.FINISHED, "early tap = black flag")
	_check(main.hud._black_flag.visible, "black flag shown")
	main.handle_tap()
	_check(main.state == SailGame.State.WAITING, "tap restarts")
	_check(not main.hud._black_flag.visible, "black flag hidden on restart")

	# --- Full races at every difficulty ---
	for d in Difficulty.NAMES.size():
		main.difficulty = d
		for boats in [2, 3, 6, 10]:
			main.boat_count = boats
			main.reset_game()
			var outcome := _play_race(main)
			print("difficulty=%-8s boats=%2d -> %s (steps=%d, dsq=%d)" % [
				Difficulty.NAMES[d], boats, outcome.result, outcome.steps, outcome.dsq])
			_check(outcome.result != "timeout", "race ends (%s, %d boats)" % [Difficulty.NAMES[d], boats])

	# --- God mode + chaos mode survive a long race ---
	main.difficulty = 5
	main.boat_count = 5
	main.god_mode = true
	main.wind_shift_chance = 0.05
	main.max_shift = deg_to_rad(90.0)
	main.reset_game()
	var o := _play_race(main)
	print("god+chaos -> %s (steps=%d)" % [o.result, o.steps])
	_check(o.result != "timeout", "god/chaos race ends")

	print("---")
	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)


# Drives the user boat: starts the race on GO, then tacks at random intervals.
func _play_race(main: SailGame) -> Dictionary:
	main.handle_tap() # start sequence
	var steps := 0
	while main.state == SailGame.State.STARTING and steps < 600:
		main.sim_step()
		steps += 1
	# State is now RACE_ON ("GO!"); tap to launch the user's boat.
	main.handle_tap()
	var result := "timeout"
	while steps < 60 * 400:
		main.sim_step()
		steps += 1
		if randf() < 0.01:
			main.handle_tap()
		if main.state == SailGame.State.FINISHED:
			result = main.hud._medal_rank.text
			break
	var dsq := 0
	for b in main.boats:
		if b.dsq:
			dsq += 1
	return {"result": result, "steps": steps, "dsq": dsq}
