class_name Confetti
extends RefCounted

var x := 0.0
var y := 0.0
var vx := 0.0
var vy := 0.0
var gravity := 0.2
var friction := 0.98
var life := 0.0
var color := Color.WHITE
var rotation := 0.0
var rotation_speed := 0.0
var active := false


func explode(w: float, h: float) -> void:
	x = w / 2.0
	y = h / 2.0
	var angle := randf() * TAU
	var spd := randf() * 5.0 + 5.0
	vx = sin(angle) * spd
	vy = cos(angle) * spd
	life = randf() * 100.0 + 100.0
	color = Color.from_hsv(randf(), 1.0, 1.0)
	rotation = randf() * TAU
	rotation_speed = deg_to_rad((randf() - 0.5) * 10.0)
	active = true


func update() -> void:
	if not active:
		return
	x += vx
	y += vy
	vy += gravity
	vx *= friction
	vy *= friction
	rotation += rotation_speed
	life -= 1.0
	if life <= 0.0:
		active = false
