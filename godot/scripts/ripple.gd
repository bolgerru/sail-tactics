class_name Ripple
extends RefCounted

var x := 0.0
var y := 0.0
var life := 0.0
var speed := 0.0


func _init(w: float, h: float) -> void:
	reset(w, h)
	life = randf()


func reset(w: float, h: float) -> void:
	x = randf() * w
	y = randf() * h
	life = randf()
	speed = randf() * 0.5 + 0.5


func update(wind_direction: float, w: float, h: float) -> void:
	# Ripples drift downwind (wind direction 0 = from the top, blowing down).
	x -= sin(wind_direction) * speed * 2.0
	y += cos(wind_direction) * speed * 2.0
	life -= 0.005
	if life <= 0.0 or x < -50.0 or x > w + 50.0 or y < -50.0 or y > h + 50.0:
		reset(w, h)
