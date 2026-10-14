class_name TouchGuard
extends Node
## Keeps taps working if iOS loses a finger's release.
##
## Buttons and game taps all run on the mouse events Godot emulates from touch,
## and Godot emulates from one finger at a time. If that finger's release never
## arrives (iOS can drop it when a touch is cancelled, e.g. by a system gesture
## or taps during launch), every later touch is ignored and the app looks
## frozen. Godot sends the emulated press just before the touch itself, so a
## touch press with no emulated press means emulation is stuck: release it and
## replay the touch.

const MAX_TOUCHES := 32 # Touch slots in Godot's iOS view

var _saw_emulated_press := false
var _replayed := false # The last touch press was one we replayed


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.device == InputEvent.DEVICE_ID_EMULATION and event.pressed:
			_saw_emulated_press = true
	elif event is InputEventScreenTouch:
		if event.pressed:
			var stuck := not _saw_emulated_press and Input.is_emulating_mouse_from_touch()
			# A replay that still got no emulated press is not retried, so it can't loop.
			if stuck and not _replayed:
				_replay(event)
				_replayed = true
			else:
				_replayed = false
			_saw_emulated_press = false


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN or what == NOTIFICATION_APPLICATION_RESUMED:
		_release_all(Vector2.ZERO)


func _replay(touch: InputEventScreenTouch) -> void:
	# Events reach _input in viewport coordinates; Input wants window ones.
	var pos := get_viewport().get_final_transform() * touch.position
	_release_all(pos)
	var again := InputEventScreenTouch.new()
	again.index = touch.index
	again.position = pos
	again.pressed = true
	Input.parse_input_event(again)


func _release_all(pos: Vector2) -> void:
	# Whichever finger emulation is stuck on, its release frees it.
	for i in MAX_TOUCHES:
		var up := InputEventScreenTouch.new()
		up.index = i
		up.position = pos
		up.pressed = false
		up.canceled = true
		Input.parse_input_event(up)
