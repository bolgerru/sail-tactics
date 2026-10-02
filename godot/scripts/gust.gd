class_name Gust
extends RefCounted

const MOVE_SPEED := 0.3

var x := 0.0
var y := 0.0
var width := 0.0
var height := 0.0
var strength := 1.0
var active := true


func _init(screen_w: float, screen_h: float) -> void:
	width = randf() * (screen_w * 0.15) + screen_w * 0.25
	height = randf() * (screen_h * 0.2) + screen_h * 0.2
	x = randf() * (screen_w - width)
	y = -height
	strength = randf() * 0.2 + 1.1


func update(screen_h: float) -> void:
	y += MOVE_SPEED
	if y > screen_h:
		active = false


func contains(px: float, py: float) -> bool:
	return px >= x and px <= x + width and py >= y and py <= y + height


# Peak opacity of the darker water patch, scaled by gust strength.
func base_opacity() -> float:
	return 0.2 + (strength - 1.2) * 0.75
