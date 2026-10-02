class_name Boat
extends RefCounted

const TACK_ANGLE_RAD := 40.0 * PI / 180.0
const TURN_SPEED := 0.05 # Radians per frame
const SHADOW_LENGTH_MULT := 6.0
const SHADOW_WIDTH_MULT := 3.0
const MAX_SHADOW_PENALTY := 0.2
const COLOR_USER := Color("ffcc00")
const COLOR_OPPONENT := Color("cccccc")
const COLOR_FLAG := Color("ff4444")
const COLOR_OUTLINE := Color("333333")

var game: SailGame
var x: float
var y: float
var is_user: bool
var tack := 1 # 1 or -1
var heading := 0.0
var target_heading := 0.0
var radius: float
var finished := false
var moving := false # Waiting for start
var trail: Array[Dictionary] = []
var luff_timer := 0.0
var dsq := false
var last_tack_time := -1000000.0
var hailing_target: Boat = null
var hailing_target_original_tack := 0
var hailed_by: Boat = null
var hail_timer := 0


func _init(g: SailGame, px: float, py: float, user := false) -> void:
	game = g
	x = px
	y = py
	is_user = user
	radius = g.boat_radius
	update_target_heading()
	heading = target_heading


# --- Rules / hailing -------------------------------------------------------

func find_tack_blocker() -> Boat:
	var intended_tack := tack * -1
	var look_left := intended_tack == -1

	# Rotate into wind space.
	var c := cos(-game.wind_direction)
	var s := sin(-game.wind_direction)
	var my_rx := x * c - y * s
	var my_ry := x * s + y * c

	var closest: Boat = null
	var min_dist := INF
	var range_x := radius * 2.5
	var range_y := radius * 2.0

	for other in game.boats:
		if other == self or other.finished or other.dsq:
			continue
		var other_rx := other.x * c - other.y * s
		var other_ry := other.x * s + other.y * c
		var dx := other_rx - my_rx
		var dy := absf(other_ry - my_ry)
		if dy > range_y:
			continue
		var is_blocked := false
		if look_left:
			if dx < 0.0 and dx > -range_x:
				is_blocked = true
		else:
			if dx > 0.0 and dx < range_x:
				is_blocked = true
		if is_blocked:
			var d := absf(dx)
			if d < min_dist:
				min_dist = d
				closest = other
	return closest


func initiate_hail(target: Boat) -> void:
	if target == null or hailing_target == target:
		return
	hailing_target = target
	hailing_target_original_tack = target.tack
	target.hailed_by = self
	target.hail_timer = 60


func update_hailing_logic() -> void:
	# 1. Am I hailing someone?
	if hailing_target != null:
		var target := hailing_target
		var still_blocking := find_tack_blocker()
		var should_clear := false
		if still_blocking != target:
			should_clear = true
			# If the target hasn't tacked yet and we're still close, keep the link.
			if target.tack == hailing_target_original_tack:
				var dist := Vector2(target.x - x, target.y - y).length()
				if dist < radius * 6.0:
					should_clear = false
		if should_clear:
			hailing_target = null
			target.hailed_by = null
			if not is_user:
				tack_boat(true)

	# 2. Am I being hailed?
	if hailed_by != null:
		var my_blocker := find_tack_blocker()
		if my_blocker != null:
			# Blocked too: chain the hail.
			initiate_hail(my_blocker)
		elif not is_user:
			# AI: tack immediately (Rule 20). The user waits for input.
			tack_boat(true)


func is_tacking_rule() -> bool:
	return game.sim_ms - last_tack_time < 1000.0


func get_polygon() -> PackedVector2Array:
	var pts := [
		Vector2(0, -radius),
		Vector2(radius * 0.7, radius),
		Vector2(-radius * 0.7, radius),
	]
	var c := cos(heading)
	var s := sin(heading)
	var out := PackedVector2Array()
	for p in pts:
		out.append(Vector2(x + p.x * c - p.y * s, y + p.x * s + p.y * c))
	return out


# --- Wind shadow -----------------------------------------------------------

func calculate_shadow_penalty(all_boats: Array[Boat]) -> float:
	var total := 0.0
	var shadow_len := radius * SHADOW_LENGTH_MULT
	var shadow_wid := radius * SHADOW_WIDTH_MULT
	var wind_flow_angle := game.wind_direction + PI
	var wv := Vector2(sin(wind_flow_angle), -cos(wind_flow_angle))

	for other in all_boats:
		if other == self or other.finished or other.dsq:
			continue

		# Shadow points between the wind flow and the other boat's stern.
		var stern_angle := other.heading + PI
		var sv := Vector2(sin(stern_angle), -cos(stern_angle))
		var shadow := wv + sv
		var mag := shadow.length()
		if mag > 0.001:
			shadow /= mag
		var shadow_angle := atan2(shadow.x, -shadow.y)

		# Rotate this boat into the other boat's shadow space.
		var rotation := shadow_angle - PI
		var cs := cos(-rotation)
		var sn := sin(-rotation)
		var dx := x - other.x
		var dy := y - other.y
		var rx := dx * cs - dy * sn
		var ry := dx * sn + dy * cs

		var y_offset := -other.radius
		var cent_y := (shadow_len / 2.0) + y_offset
		var rad_x := shadow_wid / 2.0
		var rad_y := shadow_len / 2.0
		var dist_eq := (rx * rx) / (rad_x * rad_x) + ((ry - cent_y) * (ry - cent_y)) / (rad_y * rad_y)
		if dist_eq <= 1.0:
			var ratio := clampf((ry - y_offset) / shadow_len, 0.0, 1.0)
			total += MAX_SHADOW_PENALTY * (1.0 - ratio)

	return minf(total, 0.4)


# --- Simulation ------------------------------------------------------------

func update_target_heading() -> void:
	target_heading = game.wind_direction + tack * TACK_ANGLE_RAD


func update() -> void:
	if finished or not moving or dsq:
		return

	var is_tacking := false

	update_target_heading()
	if heading != target_heading:
		is_tacking = true
		var diff := target_heading - heading
		if absf(diff) < TURN_SPEED:
			heading = target_heading
			is_tacking = false
		else:
			heading += signf(diff) * TURN_SPEED

	# Speed retention while tacking.
	var tack_multiplier := 0.7
	if not is_user:
		tack_multiplier = Difficulty.TACK_MULT[game.difficulty]
	var current_speed := game.boat_speed * (tack_multiplier if is_tacking else 1.0)

	# Gusts stack multiplicatively, capped at 1.3x.
	var speed_multiplier := 1.0
	for g in game.gusts:
		if g.contains(x, y):
			speed_multiplier *= g.strength
	speed_multiplier = minf(speed_multiplier, 1.3)

	speed_multiplier *= (1.0 - calculate_shadow_penalty(game.boats))
	current_speed *= speed_multiplier

	x += sin(heading) * current_speed
	y -= cos(heading) * current_speed

	_update_trail()
	luff_timer += 0.5

	if hail_timer > 0:
		hail_timer -= 1
	update_hailing_logic()

	# Wall collision (user and AI).
	var hit_wall := false
	for p in get_polygon():
		if p.x < 0.0 or p.x > game.width:
			hit_wall = true
			break
	if hit_wall:
		if is_user:
			if game.god_mode:
				if x < 0.0:
					x = 1.0
				if x > game.width:
					x = game.width - 1.0
			else:
				game.user_hit_wall()
				return
		else:
			game.dsq_boat(self, "Hit the wall")

	if is_user:
		# Auto-hail when approaching a wall and blocked.
		var margin := 50.0
		if (x < margin and tack == -1) or (x > game.width - margin and tack == 1):
			var blocker := find_tack_blocker()
			if blocker != null:
				initiate_hail(blocker)

	if not is_user:
		_update_ai()

	# Finish line: any vertex across it.
	var crossed := false
	for p in get_polygon():
		if p.y <= game.finish_line_y:
			crossed = true
			break
	if crossed:
		finished = true
		game.finished_count += 1
		if is_user:
			game.end_game(game.finished_count)


func _update_trail() -> void:
	var stern_x := x - sin(heading) * radius
	var stern_y := y + cos(heading) * radius

	var add_point := false
	if trail.is_empty():
		add_point = true
	else:
		var last := trail[trail.size() - 1]
		if Vector2(stern_x - last.x, stern_y - last.y).length() > 2.0:
			add_point = true
	if add_point:
		trail.append({"x": stern_x, "y": stern_y, "heading": heading, "life": 1.0})

	for i in range(trail.size() - 1, -1, -1):
		trail[i].life -= 0.008
		if trail[i].life <= 0.0:
			trail.remove_at(i)


func _update_ai() -> void:
	var margin := 50.0
	var critical_margin := 20.0
	var urgent_tack := false
	var is_critical := false
	var width := game.width

	# 1. Boundary avoidance.
	if x < margin and tack == -1:
		urgent_tack = true
	elif x > width - margin and tack == 1:
		urgent_tack = true
	if x < critical_margin and tack == -1:
		is_critical = true
	elif x > width - critical_margin and tack == 1:
		is_critical = true

	# 2. Collision avoidance: port yields to starboard.
	if not urgent_tack and tack == 1 and x >= margin:
		var avoidance_range := radius * 2.5
		for other in game.boats:
			if other == self or other.finished or other.dsq:
				continue
			if other.hailed_by == self:
				continue
			if other.tack == -1 and other.x > x:
				var dx := other.x - x
				var dy := absf(other.y - y)
				if dx < avoidance_range and dy < avoidance_range:
					urgent_tack = true
					if dx < radius * 1.5 and dy < radius * 1.5:
						is_critical = true
					break

	if urgent_tack:
		var blocker := find_tack_blocker()
		if blocker != null:
			if is_critical:
				# Desperate tack. If we hit them, they are DSQ (Rule 20).
				tack_boat(true)
			else:
				initiate_hail(blocker)
		else:
			tack_boat()
		return

	# 3. Strategic tacking.
	var wind_threshold := 5.0 * PI / 180.0
	var reaction_chance: float = Difficulty.REACTION_CHANCE[game.difficulty]
	if not Difficulty.USE_WIND_STRATEGY[game.difficulty]:
		# Random tacking, ignoring the wind.
		if randf() < reaction_chance:
			var future_tack := tack * -1
			if (x < margin and future_tack == -1) or (x > width - margin and future_tack == 1):
				pass # Unsafe
			elif find_tack_blocker() == null:
				tack_boat()
	else:
		var wind := game.wind_direction
		if wind < -wind_threshold and tack == -1:
			# Wind from left, heading left: tack to the right.
			if randf() < reaction_chance:
				if x > width - margin:
					pass # Unsafe
				elif find_tack_blocker() == null:
					tack_boat()
		elif wind > wind_threshold and tack == 1:
			# Wind from right, heading right: tack to the left.
			if randf() < reaction_chance:
				if x < margin:
					pass # Unsafe
				elif find_tack_blocker() == null:
					tack_boat()


func tack_boat(force := false) -> bool:
	if finished:
		return false
	# No double tacking mid-turn, unless forced (Rule 20).
	if not force and absf(heading - target_heading) > 0.01:
		return false

	tack *= -1
	last_tack_time = game.sim_ms
	update_target_heading()
	hailed_by = null # Clear liability on tack

	if is_user:
		game.sfx.play_tack()
	return true


# --- Drawing ---------------------------------------------------------------

func draw(ci: CanvasItem) -> void:
	_draw_wake(ci)

	var base := Transform2D(heading, Vector2(x, y))
	ci.draw_set_transform_matrix(base)

	# Hull
	var hull := PackedVector2Array([
		Vector2(0, -radius),
		Vector2(radius * 0.7, radius),
		Vector2(0, radius * 0.8),
		Vector2(-radius * 0.7, radius),
	])
	ci.draw_colored_polygon(hull, COLOR_USER if is_user else COLOR_OPPONENT)
	ci.draw_polyline(hull + PackedVector2Array([hull[0]]), COLOR_OUTLINE, 1.0, true)

	# Sail
	var angle_to_wind := absf(heading - game.wind_direction)
	var is_turning := absf(heading - target_heading) > 0.01
	var is_into_wind := angle_to_wind < 20.0 * PI / 180.0

	var boom_end_x := 0.0
	var boom_end_y := radius * 0.5
	if is_into_wind or is_turning:
		# Luffing: the boom tip flaps.
		boom_end_x = sin(luff_timer) * 5.0
	else:
		var side := 1.0 if (heading - game.wind_direction) > 0.0 else -1.0
		boom_end_x = side * radius * 0.8

	var sail := PackedVector2Array([
		Vector2(0, -radius * 0.5),
		Vector2(0, radius * 0.5),
		Vector2(boom_end_x, boom_end_y),
	])
	if absf(boom_end_x) > 0.5:
		ci.draw_colored_polygon(sail, Color.WHITE)
	ci.draw_polyline(sail + PackedVector2Array([sail[0]]), COLOR_OUTLINE, 1.0, true)

	# Disqualification flag
	if dsq:
		var flag_rot := -PI / 2.0 if heading > 0.0 else PI / 2.0
		ci.draw_set_transform_matrix(base * Transform2D(flag_rot, Vector2(0, radius * 0.8)))
		_draw_small_red_flag(ci)

	# Text stays upright in screen space.
	ci.draw_set_transform_matrix(Transform2D(0.0, Vector2(x, y)))
	if hailing_target != null:
		game.draw_text(Vector2(0, -radius * 1.5), "Room!", 14, Color.WHITE, true)

	ci.draw_set_transform_matrix(Transform2D.IDENTITY)
	if is_user and hailed_by != null:
		game.draw_text(Vector2(game.width / 2.0, game.height / 2.0 - 50.0), "TACK NOW!", 24, COLOR_FLAG, true)


func _draw_wake(ci: CanvasItem) -> void:
	if trail.size() < 2:
		return
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)
	var base_half_width := radius * 0.5
	for i in trail.size() - 1:
		var p1 := trail[i]
		var p2 := trail[i + 1]
		var w1: float = base_half_width + (1.0 - p1.life) * 5.0
		var w2: float = base_half_width + (1.0 - p2.life) * 5.0

		var perp1: float = p1.heading + PI / 2.0
		var perp2: float = p2.heading + PI / 2.0
		var d1 := Vector2(sin(perp1), -cos(perp1))
		var d2 := Vector2(sin(perp2), -cos(perp2))
		var a := Vector2(p1.x, p1.y)
		var b := Vector2(p2.x, p2.y)

		var col := Color(1, 1, 1, p1.life * 0.4)
		ci.draw_line(a - d1 * w1, b - d2 * w2, col, 2.0, true)
		ci.draw_line(a + d1 * w1, b + d2 * w2, col, 2.0, true)


func _draw_small_red_flag(ci: CanvasItem) -> void:
	ci.draw_line(Vector2(0, 0), Vector2(0, -20), Color.WHITE, 1.0, true)
	var flag := PackedVector2Array([Vector2(0, -20), Vector2(12, -15), Vector2(0, -10)])
	ci.draw_colored_polygon(flag, COLOR_FLAG)
	ci.draw_polyline(flag + PackedVector2Array([flag[0]]), Color.WHITE, 1.0, true)
