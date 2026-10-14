extends SceneTree
## Touch input: taps must keep working when a finger's release is lost, the
## iOS bug that left the app unresponsive in App Review on iPad.
## Run: godot --headless --path godot -s res://tests/touch_test.gd

var _failures := 0
var main: SailGame


func _check(cond: bool, msg: String) -> void:
	print("%s: %s" % ["ok" if cond else "FAIL", msg])
	if not cond:
		_failures += 1


func _frames(n := 3) -> void:
	for i in n:
		await process_frame


# Touches go in window coordinates, as the OS sends them.
func _touch(index: int, local: Vector2, pressed: bool) -> void:
	var t := InputEventScreenTouch.new()
	t.index = index
	t.position = root.get_final_transform() * local
	t.pressed = pressed
	Input.parse_input_event(t)
	await _frames()


func _tap(index: int, local: Vector2) -> void:
	await _touch(index, local, true)
	await _touch(index, local, false)


func _save_button() -> Button:
	for c in main.hud._vbox.get_children():
		if c is Button and c.text == "Save & Restart":
			return c
	return null


func _launch() -> void:
	if main != null:
		main.queue_free()
		await _frames()
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await _frames()


func _init() -> void:
	# Scale the window so the viewport/window coordinate conversion is exercised.
	root.content_scale_factor = 1.5
	await _frames()
	print("final transform: ", root.get_final_transform())

	# --- Normal taps ---
	await _launch()
	_check(main.hud.settings_open, "settings dialog opens on launch")
	await _tap(0, _save_button().get_global_rect().get_center())
	_check(not main.hud.settings_open, "tapping Save & Restart closes settings")
	_check(main.state == SailGame.State.WAITING, "waiting to start")
	await _tap(0, Vector2(100, 400))
	_check(main.state == SailGame.State.STARTING, "one tap starts the countdown (once, not twice)")

	# --- A finger whose release never arrives ---
	await _launch()
	await _touch(5, Vector2(50, 300), true) # Held forever
	await _tap(0, _save_button().get_global_rect().get_center())
	_check(not main.hud.settings_open, "with a lost release, Save & Restart still works")
	await _tap(1, Vector2(100, 400))
	_check(main.state == SailGame.State.STARTING, "with a lost release, a tap still starts the countdown")
	await _tap(2, Vector2(100, 400))
	_check(main.state == SailGame.State.FINISHED, "and the next tap still registers (black flag)")
	await _tap(0, Vector2(100, 400))
	_check(main.state == SailGame.State.WAITING, "and the next (restart)")

	# --- Two thumbs overlapping ---
	await _touch(0, Vector2(100, 400), true)
	_check(main.state == SailGame.State.STARTING, "first thumb starts the countdown")
	await _touch(1, Vector2(200, 400), true)
	_check(main.state == SailGame.State.FINISHED, "second thumb, before the first lifts, also registers")
	await _touch(0, Vector2(100, 400), false)
	await _touch(1, Vector2(200, 400), false)
	await _tap(0, Vector2(100, 400))
	_check(main.state == SailGame.State.WAITING, "taps work after overlapping thumbs")

	print("\n%s" % ("ALL PASSED" if _failures == 0 else "%d FAILED" % _failures))
	quit(1 if _failures > 0 else 0)
