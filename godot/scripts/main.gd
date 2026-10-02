class_name SailGame
extends Node2D
## Sail Tactics: a one-tap upwind sailing race against AI boats.
## World units are logical points; the viewport is 390x844 expanded to the
## device aspect ratio. Simulation runs at a fixed 60 ticks per second.

enum State { WAITING, STARTING, RACE_ON, PLAYING, FINISHED }

const TICK_MS := 1000.0 / 60.0
const FINISH_OFFSET := 100.0 # Finish line distance below the top inset
const RIPPLE_COUNT := 100
const CONFETTI_COUNT := 100
const GUST_SPAWN_CHANCE := 0.005
const MAX_WIND_DEVIATION := 30.0 * PI / 180.0
const DEFAULT_WIND_SHIFT_CHANCE := 0.005
const DEFAULT_MAX_SHIFT := 20.0 * PI / 180.0
const DEFAULT_RADIUS := 15.0
const DEFAULT_SPEED := 0.2

const COLOR_FINISH := Color("ff4444")
const COLOR_MEDAL_GOLD := Color("ffd700")
const COLOR_MEDAL_SILVER := Color("c0c0c0")
const COLOR_MEDAL_BRONZE := Color("cd7f32")

# Settings (configurable)
var boat_speed := DEFAULT_SPEED
var boat_count := 3
var difficulty := Difficulty.BEGINNER
var boat_radius := DEFAULT_RADIUS
var god_mode := false
var wind_shift_chance := DEFAULT_WIND_SHIFT_CHANCE
var max_shift := DEFAULT_MAX_SHIFT

# World
var width := 390.0
var height := 844.0
var top_inset := 0.0
var bottom_inset := 0.0
var finish_line_y := FINISH_OFFSET

# Game state
var state := State.WAITING
var boats: Array[Boat] = []
var gusts: Array[Gust] = []
var ripples: Array[Ripple] = []
var confetti: Array[Confetti] = []
var finished_count := 0
var wind_direction := 0.0 # 0 = from the top
var wind_target := 0.0
var sim_ms := 0.0
var start_timer := 3
var _countdown_active := false
var _countdown_acc := 0.0

var sfx: SoundManager
var hud: Hud
var _gust_texture: GradientTexture2D
var _font: Font
var _bold_font: Font


func _ready() -> void:
	_font = ThemeDB.fallback_font
	var bold := FontVariation.new()
	bold.base_font = _font
	bold.variation_embolden = 0.6
	_bold_font = bold

	sfx = SoundManager.new()
	add_child(sfx)

	hud = Hud.new()
	add_child(hud)
	hud.settings_requested.connect(_on_settings_requested)
	hud.settings_saved.connect(_apply_settings)

	_gust_texture = _make_gust_texture()
	get_viewport().size_changed.connect(_update_world_size)
	_update_world_size()
	reset_game()

	# The original opens the settings dialog on launch.
	_on_settings_requested(false)


func _update_world_size() -> void:
	var size := get_viewport_rect().size
	width = size.x
	height = size.y
	top_inset = 0.0
	bottom_inset = 0.0
	# Keep the HUD and boats clear of the notch / Dynamic Island / home bar.
	if OS.has_feature("mobile"):
		var win := Vector2(DisplayServer.window_get_size())
		var safe := Rect2(DisplayServer.get_display_safe_area())
		if win.x > 0.0 and safe.size.x > 0.0:
			var k := size.x / win.x
			top_inset = maxf(safe.position.y * k, 0.0)
			bottom_inset = maxf((win.y - safe.end.y) * k, 0.0)
	finish_line_y = top_inset + FINISH_OFFSET
	hud.set_insets(top_inset, bottom_inset)


func _make_gust_texture() -> GradientTexture2D:
	# Soft-edged radial blob, tinted per gust through the draw modulate.
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.6, 1.0])
	grad.colors = PackedColorArray([
		Color(0, 30.0 / 255.0, 80.0 / 255.0, 1.0),
		Color(0, 30.0 / 255.0, 80.0 / 255.0, 0.75),
		Color(0, 30.0 / 255.0, 80.0 / 255.0, 0.0),
	])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 128
	tex.height = 128
	return tex


# --- Game flow -------------------------------------------------------------

func reset_game() -> void:
	boats.clear()
	gusts.clear()

	if ripples.is_empty():
		for i in RIPPLE_COUNT:
			ripples.append(Ripple.new(width, height))
	if confetti.is_empty():
		for i in CONFETTI_COUNT:
			confetti.append(Confetti.new())
	for c in confetti:
		c.active = false

	var start_y := height - 80.0 - bottom_inset
	var user_index := boat_count / 2
	var margin := minf(width * 0.1, 50.0)
	var available := width - 2.0 * margin
	var step := available / (boat_count - 1) if boat_count > 1 else 0.0

	wind_direction = 0.0
	wind_target = 0.0
	finished_count = 0
	_countdown_active = false

	for i in boat_count:
		var bx := margin + i * step if boat_count > 1 else width / 2.0
		boats.append(Boat.new(self, bx, start_y, i == user_index))

	state = State.WAITING
	hud.set_instructions("Tap to Start Sequence")
	hud.hide_countdown()
	hud.hide_medal()
	hud.hide_black_flag()


func start_sequence() -> void:
	state = State.STARTING
	hud.set_instructions("")
	start_timer = 3
	hud.show_countdown(str(start_timer))
	sfx.play_start_beep(440)
	_countdown_active = true
	_countdown_acc = 0.0


func _countdown_tick() -> void:
	start_timer -= 1
	if start_timer > 0:
		hud.show_countdown(str(start_timer))
		sfx.play_start_beep(440 + (3 - start_timer) * 100) # Pitch up
	elif start_timer == 0:
		hud.show_countdown("GO!")
		hud.set_instructions("Tap to Start Sailing")
		sfx.play_start_gun()
		state = State.RACE_ON
		launch_ai()
	else:
		_countdown_active = false
		hud.hide_countdown()


func launch_ai() -> void:
	for b in boats:
		if not b.is_user:
			b.moving = true


func _begin_user_race() -> void:
	state = State.PLAYING
	hud.set_instructions("Tap to Tack")
	hud.hide_countdown()
	for b in boats:
		if b.is_user:
			b.moving = true


func end_game(rank: int) -> void:
	state = State.FINISHED
	hud.set_instructions("")

	var suffix := "th"
	if rank == 1:
		suffix = "st"
	elif rank == 2:
		suffix = "nd"
	elif rank == 3:
		suffix = "rd"

	var color := COLOR_MEDAL_BRONZE
	var msg := "Unlucky pal, stick to college work"
	if rank == 1:
		color = COLOR_MEDAL_GOLD
		msg = "Congrats! You beat %s!" % Difficulty.NAMES[difficulty]
		if difficulty == Difficulty.BEGINNER:
			msg += "\nWant a medal bro?"
		for c in confetti:
			c.explode(width, height)
	elif rank == 2:
		color = COLOR_MEDAL_SILVER
	hud.show_medal("%d%s" % [rank, suffix], msg, color)


func user_hit_wall() -> void:
	state = State.FINISHED
	hud.show_medal("DNF", "You hit a wall!", COLOR_FINISH)
	sfx.play_start_gun()


func dsq_boat(boat: Boat, reason := "Rule 10: Starboard has right of way.") -> void:
	if boat.dsq or boat.finished:
		return
	if boat.is_user:
		if god_mode:
			return
		state = State.FINISHED
		hud.show_medal("DSQ", reason, COLOR_FINISH)
		sfx.play_start_gun()
	else:
		boat.dsq = true
		boat.moving = false


func handle_tap() -> void:
	match state:
		State.WAITING:
			start_sequence()
		State.STARTING:
			if start_timer > 0:
				# Tapped during the countdown: black flag.
				_countdown_active = false
				hud.hide_countdown()
				state = State.FINISHED
				hud.show_black_flag()
				hud.set_instructions("Tap to Restart")
			else:
				_countdown_active = false
				_begin_user_race()
				launch_ai()
		State.RACE_ON:
			# Tapped after GO disappeared (late start).
			_begin_user_race()
		State.PLAYING:
			for b in boats:
				if b.is_user:
					b.tack_boat()
		State.FINISHED:
			reset_game()


func _unhandled_input(event: InputEvent) -> void:
	# Touch is emulated as mouse input, so this covers both.
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			handle_tap()
	elif event is InputEventKey:
		if event.pressed and not event.echo and event.keycode in [KEY_SPACE, KEY_ENTER]:
			handle_tap()


# --- Settings --------------------------------------------------------------

func _on_settings_requested(advanced: bool) -> void:
	hud.open_settings({
		"speed": boat_speed,
		"boats": boat_count,
		"difficulty": difficulty,
		"sound": sfx.enabled,
		"radius": boat_radius,
		"chaos": wind_shift_chance > 0.01,
		"god": god_mode,
	}, advanced)


func _apply_settings(cfg: Dictionary) -> void:
	boat_speed = cfg.speed
	boat_count = cfg.boats
	boat_radius = cfg.radius
	god_mode = cfg.god
	if cfg.chaos:
		wind_shift_chance = 0.05 # 10x normal
		max_shift = 90.0 * PI / 180.0
	else:
		wind_shift_chance = DEFAULT_WIND_SHIFT_CHANCE
		max_shift = DEFAULT_MAX_SHIFT
	difficulty = cfg.difficulty
	sfx.enabled = cfg.sound
	reset_game()


# --- Simulation ------------------------------------------------------------

func _physics_process(_delta: float) -> void:
	sim_step()


func sim_step() -> void:
	sim_ms += TICK_MS

	for r in ripples:
		r.update(wind_direction, width, height)

	if _countdown_active:
		_countdown_acc += 1.0 / 60.0
		if _countdown_acc >= 1.0:
			_countdown_acc -= 1.0
			_countdown_tick()

	_update_wind()
	_update_gusts()

	if state == State.PLAYING or state == State.RACE_ON:
		for b in boats:
			b.update()
		_check_collisions()

	for c in confetti:
		c.update()

	queue_redraw()


func _update_wind() -> void:
	if state == State.PLAYING or state == State.STARTING:
		if wind_direction != wind_target:
			var diff := wind_target - wind_direction
			if absf(diff) < 0.005:
				wind_direction = wind_target
			else:
				wind_direction += diff * 0.05 # Ease to target

		if randf() < wind_shift_chance:
			var shift := (randf() - 0.5) * 2.0 * max_shift
			var centering_bias := -wind_target * 0.5 # Pull back towards centre
			wind_target = clampf(wind_target + shift + centering_bias, -MAX_WIND_DEVIATION, MAX_WIND_DEVIATION)

	# Wind sound is louder while the user's boat is inside a gust.
	var wind_vol := SoundManager.WIND_BASE
	for b in boats:
		if b.is_user:
			for g in gusts:
				if g.active and g.contains(b.x, b.y):
					wind_vol = SoundManager.WIND_GUST
					break
			break
	sfx.set_wind_volume(wind_vol)


func _update_gusts() -> void:
	if state == State.FINISHED:
		return
	if state != State.WAITING and randf() < GUST_SPAWN_CHANCE:
		gusts.append(Gust.new(width, height))
	for i in range(gusts.size() - 1, -1, -1):
		if state != State.WAITING:
			gusts[i].update(height)
		if not gusts[i].active:
			gusts.remove_at(i)


# --- Collisions / rules ----------------------------------------------------

func _is_clear_astern(behind: Boat, ahead: Boat) -> bool:
	var d := Vector2(behind.x - ahead.x, behind.y - ahead.y)
	var fwd := Vector2(sin(ahead.heading), -cos(ahead.heading))
	return d.dot(fwd) < -ahead.radius


func _polygons_intersect(a: PackedVector2Array, b: PackedVector2Array) -> bool:
	for polygon in [a, b]:
		for j in polygon.size():
			var p1: Vector2 = polygon[j]
			var p2: Vector2 = polygon[(j + 1) % polygon.size()]
			var normal := Vector2(p2.y - p1.y, p1.x - p2.x)

			var min_a := INF
			var max_a := -INF
			for p in a:
				var proj := normal.dot(p)
				min_a = minf(min_a, proj)
				max_a = maxf(max_a, proj)
			var min_b := INF
			var max_b := -INF
			for p in b:
				var proj := normal.dot(p)
				min_b = minf(min_b, proj)
				max_b = maxf(max_b, proj)
			if max_a < min_b or max_b < min_a:
				return false
	return true


# Returns the boat at the head of a hail chain that reaches `target`, or null.
func _chain_upstream(start: Boat, target: Boat) -> Boat:
	var curr := start
	var guard := 0
	while curr.hailing_target != null and guard < 20:
		if curr.hailing_target == target:
			return start
		curr = curr.hailing_target
		guard += 1
		if curr == start:
			break
	return null


func _check_collisions() -> void:
	for i in boats.size():
		for j in range(i + 1, boats.size()):
			var b1 := boats[i]
			var b2 := boats[j]
			if b1.finished or b1.dsq or b2.finished or b2.dsq:
				continue
			# A user who hasn't tapped to start yet can't be hit (or disqualified).
			if (b1.is_user and not b1.moving) or (b2.is_user and not b2.moving):
				continue

			var dist := Vector2(b1.x - b2.x, b1.y - b2.y).length()
			# Broad phase, then exact polygon test.
			if dist >= (b1.radius + b2.radius) * 1.5:
				continue
			if not _polygons_intersect(b1.get_polygon(), b2.get_polygon()):
				continue

			# Rule 20: room to tack at an obstruction (highest priority).
			var upstream := _chain_upstream(b1, b2)
			if upstream == null:
				upstream = _chain_upstream(b2, b1)
			if upstream != null:
				# The end of the hail chain is liable.
				var chain_end := upstream
				var visited: Array[Boat] = []
				while chain_end.hailing_target != null:
					if visited.has(chain_end):
						break
					visited.append(chain_end)
					chain_end = chain_end.hailing_target
				dsq_boat(chain_end, "Failed to give room to tack! (Rule 20 Chain)")
				continue

			# Rule 13: while tacking.
			var b1_tacking := b1.is_tacking_rule()
			var b2_tacking := b2.is_tacking_rule()
			if b1_tacking or b2_tacking:
				if b1_tacking and b2_tacking:
					# Both tacking: the boat on the left is in the wrong.
					if b1.x < b2.x:
						dsq_boat(b1, "You were on the left while both tacking.")
					else:
						dsq_boat(b2, "You were on the left while both tacking.")
				elif b1_tacking:
					dsq_boat(b1, "You tacked too close! (Rule 13)")
				else:
					dsq_boat(b2, "You tacked too close! (Rule 13)")
			elif b1.tack != b2.tack:
				# Rule 10: opposite tacks, port gives way to starboard.
				if b1.tack == -1 and b2.tack == 1:
					dsq_boat(b2, "You were on Port! Starboard has right of way.")
				elif b1.tack == 1 and b2.tack == -1:
					dsq_boat(b1, "You were on Port! Starboard has right of way.")
			else:
				# Same tack.
				if _is_clear_astern(b1, b2):
					dsq_boat(b1, "You hit them from behind! (Clear Astern)")
				elif _is_clear_astern(b2, b1):
					dsq_boat(b2, "You hit them from behind! (Clear Astern)")
				else:
					# Overlapped: windward boat keeps clear (Rule 11).
					var c := cos(-wind_direction)
					var s := sin(-wind_direction)
					var x1 := b1.x * c - b1.y * s
					var x2 := b2.x * c - b2.y * s
					if b1.tack == -1:
						# Starboard tack: wind from the right, windward is max X.
						dsq_boat(b1 if x1 > x2 else b2, "You were Windward! (Rule 11)")
					else:
						# Port tack: wind from the left, windward is min X.
						dsq_boat(b1 if x1 < x2 else b2, "You were Windward! (Rule 11)")


# --- Drawing ---------------------------------------------------------------

func draw_text(pos: Vector2, text: String, size: int, color: Color, outline := false, align := HORIZONTAL_ALIGNMENT_CENTER) -> void:
	# `pos` is the baseline anchor; for centre alignment it is the centre.
	var box := 600.0
	var origin := pos
	match align:
		HORIZONTAL_ALIGNMENT_CENTER:
			origin.x -= box / 2.0
		HORIZONTAL_ALIGNMENT_RIGHT:
			origin.x -= box
	if outline:
		draw_string_outline(_bold_font, origin, text, align, box, size, maxi(2, size / 5), Color(0, 0, 0, 0.85))
	draw_string(_bold_font, origin, text, align, box, size, color)


func _draw() -> void:
	draw_set_transform_matrix(Transform2D.IDENTITY)

	for r in ripples:
		var d := Vector2(-sin(wind_direction) * -5.0, cos(wind_direction) * -5.0)
		var p := Vector2(r.x, r.y)
		draw_line(p + d, p - d, Color(1, 1, 1, clampf(r.life, 0.0, 1.0) * 0.2), 1.0)

	_draw_finish_line()
	_draw_wind_arrow()

	if state != State.FINISHED:
		for g in gusts:
			var a := clampf(g.base_opacity(), 0.0, 1.0)
			draw_texture_rect(_gust_texture, Rect2(g.x, g.y, g.width, g.height), false, Color(1, 1, 1, a))

	for b in boats:
		b.draw(self)
	draw_set_transform_matrix(Transform2D.IDENTITY)

	for c in confetti:
		if c.active:
			draw_set_transform_matrix(Transform2D(c.rotation, Vector2(c.x, c.y)))
			draw_rect(Rect2(-4, -4, 8, 8), c.color)
	draw_set_transform_matrix(Transform2D.IDENTITY)


func _draw_finish_line() -> void:
	draw_dashed_line(Vector2(0, finish_line_y), Vector2(width, finish_line_y), COLOR_FINISH, 4.0, 20.0)
	draw_text(Vector2(width - 20.0, finish_line_y - 10.0), "FINISH", 20, COLOR_FINISH, false, HORIZONTAL_ALIGNMENT_RIGHT)


func _draw_wind_arrow() -> void:
	var center := Vector2(width / 2.0, top_inset + 60.0)
	var arrow_len := 40.0
	# The arrow points downwind.
	draw_set_transform_matrix(Transform2D(wind_direction, center))
	draw_line(Vector2(0, -arrow_len / 2.0), Vector2(0, arrow_len / 2.0), Color.WHITE, 3.0, true)
	draw_colored_polygon(PackedVector2Array([
		Vector2(0, arrow_len / 2.0),
		Vector2(-10, arrow_len / 2.0 - 10.0),
		Vector2(10, arrow_len / 2.0 - 10.0),
	]), Color.WHITE)
	draw_set_transform_matrix(Transform2D.IDENTITY)
	draw_text(center + Vector2(0, -arrow_len / 2.0 - 15.0), "WIND", 12, Color.WHITE)
