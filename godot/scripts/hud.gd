class_name Hud
extends CanvasLayer
## All on-screen UI: countdown, medal, black flag, instructions and settings.

signal settings_requested(advanced: bool)
signal settings_saved(cfg: Dictionary)

## Hold the settings button for a second to open the advanced menu
## (custom values, chaos mode, god mode). Set to false to ship without it.
const ENABLE_ADVANCED_MENU := true
const LONG_PRESS_SECONDS := 1.0
const DEFAULT_RADIUS := 15.0

var settings_open := false

var _top_inset := 0.0
var _bottom_inset := 0.0
var _bold: Font

var _root: Control
var _instructions: Label
var _countdown: Label
var _settings_btn: Button
var _press_timer: Timer
var _long_press := false

var _medal: PanelContainer
var _medal_style: StyleBoxFlat
var _medal_rank: Label
var _medal_msg: Label
var _black_flag: PanelContainer

var _blocker: ColorRect
var _scroll: ScrollContainer
var _vbox: VBoxContainer
var _opt_speed: HSlider
var _opt_boats: HSlider
var _boats_label: Label
var _opt_diff: OptionButton
var _opt_sound: CheckBox
var _advanced: PanelContainer
var _custom_speed: SpinBox
var _custom_boats: SpinBox
var _custom_radius: SpinBox
var _chaos: CheckBox
var _god: CheckBox


func _ready() -> void:
	var bold := FontVariation.new()
	bold.base_font = ThemeDB.fallback_font
	bold.variation_embolden = 0.6
	_bold = bold

	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_build_instructions()
	_build_countdown()
	_build_black_flag()
	_build_medal()
	_build_settings_button()
	_build_settings()


func set_insets(top: float, bottom: float) -> void:
	_top_inset = top
	_bottom_inset = bottom
	if _settings_btn == null:
		return
	_settings_btn.offset_top = 20.0 + top
	_settings_btn.offset_bottom = 20.0 + top + 44.0
	_instructions.offset_bottom = -(20.0 + bottom)
	_instructions.offset_top = -(20.0 + bottom) - 30.0


# --- Public API ------------------------------------------------------------

func set_instructions(text: String) -> void:
	_instructions.text = text


func show_countdown(text: String) -> void:
	_countdown.text = text
	_countdown.visible = true


func hide_countdown() -> void:
	_countdown.visible = false


func show_medal(rank: String, msg: String, color: Color) -> void:
	_medal_rank.text = rank
	_medal_msg.text = msg
	_medal_style.bg_color = color
	_medal.visible = true


func hide_medal() -> void:
	_medal.visible = false


func show_black_flag() -> void:
	_black_flag.visible = true


func hide_black_flag() -> void:
	_black_flag.visible = false


func open_settings(cfg: Dictionary, advanced: bool) -> void:
	_opt_speed.value = cfg.speed
	_opt_boats.value = cfg.boats
	_opt_diff.select(cfg.difficulty)
	_opt_sound.button_pressed = cfg.sound
	_boats_label.text = "Number of Boats: %d" % int(_opt_boats.value)

	_advanced.visible = advanced and ENABLE_ADVANCED_MENU
	if _advanced.visible:
		_custom_speed.value = cfg.speed
		_custom_boats.value = cfg.boats
		_custom_radius.value = cfg.radius
		_chaos.button_pressed = cfg.chaos
		_god.button_pressed = cfg.god

	_blocker.visible = true
	settings_open = true
	_size_settings.call_deferred()


# --- Builders --------------------------------------------------------------

func _label(text: String, size: int, align := HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _outline(l: Label, size: int) -> void:
	l.add_theme_font_override("font", _bold)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	l.add_theme_constant_override("outline_size", size)


func _box(bg: Color, radius: int, border := Color.WHITE, border_w := 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.border_color = border
	s.set_border_width_all(border_w)
	return s


func _build_instructions() -> void:
	_instructions = _label("Tap to Start", 19)
	_outline(_instructions, 4)
	_instructions.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_instructions.offset_top = -50.0
	_instructions.offset_bottom = -20.0
	_root.add_child(_instructions)


func _build_countdown() -> void:
	_countdown = _label("", 128)
	_outline(_countdown, 10)
	_countdown.set_anchors_preset(Control.PRESET_FULL_RECT)
	_countdown.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_countdown.visible = false
	_root.add_child(_countdown)


func _build_black_flag() -> void:
	_black_flag = PanelContainer.new()
	_black_flag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var s := _box(Color(0, 0, 0, 0.9), 10, Color.WHITE, 3)
	s.set_content_margin_all(20)
	s.content_margin_left = 40
	s.content_margin_right = 40
	_black_flag.add_theme_stylebox_override("panel", s)
	var l := _label("BLACK FLAG!", 26)
	l.add_theme_font_override("font", _bold)
	_black_flag.add_child(l)
	_black_flag.visible = false
	_center(_black_flag)


func _build_medal() -> void:
	_medal = PanelContainer.new()
	_medal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_medal.custom_minimum_size = Vector2(230, 230)
	_medal_style = _box(COLOR_GOLD, 115, Color.WHITE, 5)
	_medal_style.shadow_color = Color(0, 0, 0, 0.3)
	_medal_style.shadow_size = 8
	_medal_style.set_content_margin_all(24)
	_medal.add_theme_stylebox_override("panel", _medal_style)

	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_medal.add_child(v)

	_medal_rank = _label("1st", 48)
	_outline(_medal_rank, 3)
	v.add_child(_medal_rank)

	_medal_msg = _label("", 15)
	_medal_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_medal_msg.add_theme_font_override("font", _bold)
	_medal_msg.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.5))
	_medal_msg.add_theme_constant_override("outline_size", 3)
	_medal_msg.custom_minimum_size.x = 170
	v.add_child(_medal_msg)

	var again := _label("Tap to Restart", 13)
	again.custom_minimum_size.y = 24
	v.add_child(again)

	_medal.visible = false
	_center(_medal)


const COLOR_GOLD := Color("ffd700")


func _center(c: Control) -> void:
	# Full-screen centring wrapper that never eats input.
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(cc)
	cc.add_child(c)
	# Visibility follows the wrapped control.
	c.visibility_changed.connect(func(): cc.visible = c.visible)
	cc.visible = c.visible


func _build_settings_button() -> void:
	_settings_btn = Button.new()
	_settings_btn.text = "Settings"
	_settings_btn.add_theme_font_size_override("font_size", 16)
	_settings_btn.add_theme_stylebox_override("normal", _box(Color(0, 0, 0, 0.3), 5, Color.WHITE, 1))
	_settings_btn.add_theme_stylebox_override("hover", _box(Color(0, 0, 0, 0.4), 5, Color.WHITE, 1))
	_settings_btn.add_theme_stylebox_override("pressed", _box(Color(0, 0, 0, 0.55), 5, Color.WHITE, 1))
	_settings_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_settings_btn.focus_mode = Control.FOCUS_NONE
	_settings_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_settings_btn.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_settings_btn.offset_right = -20.0
	_settings_btn.offset_left = -130.0
	_settings_btn.offset_top = 20.0
	_settings_btn.offset_bottom = 64.0
	_root.add_child(_settings_btn)

	_press_timer = Timer.new()
	_press_timer.one_shot = true
	_press_timer.wait_time = LONG_PRESS_SECONDS
	_press_timer.timeout.connect(_on_long_press)
	add_child(_press_timer)

	_settings_btn.button_down.connect(_on_settings_down)
	_settings_btn.button_up.connect(_on_settings_up)


func _on_settings_down() -> void:
	_long_press = false
	if ENABLE_ADVANCED_MENU:
		_press_timer.start()


func _on_long_press() -> void:
	_long_press = true
	settings_requested.emit(true)


func _on_settings_up() -> void:
	_press_timer.stop()
	if not _long_press and not settings_open:
		settings_requested.emit(false)
	_long_press = false


func _build_settings() -> void:
	_blocker = ColorRect.new()
	_blocker.color = Color(0, 0, 0, 0.35)
	_blocker.set_anchors_preset(Control.PRESET_FULL_RECT)
	_blocker.mouse_filter = Control.MOUSE_FILTER_STOP # Taps must not reach the game
	_blocker.visible = false
	_root.add_child(_blocker)

	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_blocker.add_child(cc)

	var panel := PanelContainer.new()
	var ps := _box(Color(0, 0, 0, 0.85), 10)
	ps.set_content_margin_all(20)
	panel.add_theme_stylebox_override("panel", ps)
	cc.add_child(panel)

	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(_scroll)

	_vbox = VBoxContainer.new()
	_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_vbox.add_theme_constant_override("separation", 8)
	_scroll.add_child(_vbox)

	var title := _label("Settings", 24)
	title.add_theme_font_override("font", _bold)
	_vbox.add_child(title)

	_vbox.add_child(_label("Wind Speed", 16))
	_opt_speed = _slider(0.1, 0.4, 0.01)
	_vbox.add_child(_opt_speed)

	_boats_label = _label("Number of Boats: 3", 16)
	_vbox.add_child(_boats_label)
	_opt_boats = _slider(2, 10, 1)
	_opt_boats.value_changed.connect(func(v: float): _boats_label.text = "Number of Boats: %d" % int(v))
	_vbox.add_child(_opt_boats)

	_build_advanced()

	_vbox.add_child(_label("Difficulty", 16))
	_opt_diff = OptionButton.new()
	_opt_diff.custom_minimum_size.y = 44
	_opt_diff.add_theme_font_size_override("font_size", 16)
	for l in Difficulty.LABELS:
		_opt_diff.add_item(l)
	_opt_diff.get_popup().add_theme_font_size_override("font_size", 18)
	_vbox.add_child(_opt_diff)

	_opt_sound = CheckBox.new()
	_opt_sound.text = "Sound"
	_opt_sound.button_pressed = true
	_opt_sound.custom_minimum_size.y = 44
	_opt_sound.add_theme_font_size_override("font_size", 16)
	_vbox.add_child(_opt_sound)

	var save := Button.new()
	save.text = "Save & Restart"
	save.custom_minimum_size.y = 48
	save.add_theme_font_size_override("font_size", 18)
	save.pressed.connect(_on_save)
	_vbox.add_child(save)

	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.custom_minimum_size.y = 44
	cancel.add_theme_font_size_override("font_size", 16)
	cancel.pressed.connect(_close_settings)
	_vbox.add_child(cancel)


func _slider(lo: float, hi: float, step: float) -> HSlider:
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.custom_minimum_size.y = 32
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return s


func _spin(lo: float, hi: float, step: float) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.custom_minimum_size.y = 40
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return s


func _build_advanced() -> void:
	_advanced = PanelContainer.new()
	var s := _box(Color(0, 0, 0, 0), 0, Color.YELLOW, 1)
	s.set_content_margin_all(10)
	_advanced.add_theme_stylebox_override("panel", s)
	_advanced.visible = false

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	_advanced.add_child(v)

	var h := _label("Advanced Override", 18)
	h.add_theme_color_override("font_color", Color.YELLOW)
	v.add_child(h)

	v.add_child(_label("Custom Speed", 15))
	_custom_speed = _spin(0.01, 2.0, 0.01)
	v.add_child(_custom_speed)
	v.add_child(_label("Custom Boat Count", 15))
	_custom_boats = _spin(1, 30, 1)
	v.add_child(_custom_boats)
	v.add_child(_label("Boat Radius", 15))
	_custom_radius = _spin(4, 60, 1)
	v.add_child(_custom_radius)

	_chaos = CheckBox.new()
	_chaos.text = "Chaos Mode"
	_chaos.custom_minimum_size.y = 40
	v.add_child(_chaos)
	_god = CheckBox.new()
	_god.text = "God Mode (Invincible)"
	_god.custom_minimum_size.y = 40
	v.add_child(_god)

	_vbox.add_child(_advanced)


func _size_settings() -> void:
	# Cap the dialog to the screen; it scrolls when the advanced menu is open.
	var vp := get_viewport().get_visible_rect().size
	var content := _vbox.get_combined_minimum_size()
	var max_h := vp.y - 2.0 * (_top_inset + 24.0) - 40.0
	_scroll.custom_minimum_size = Vector2(minf(300.0, vp.x - 80.0), minf(content.y, max_h))


func _close_settings() -> void:
	_blocker.visible = false
	settings_open = false


func _on_save() -> void:
	var adv := _advanced.visible
	var cfg := {
		"speed": _custom_speed.value if adv else _opt_speed.value,
		"boats": int(_custom_boats.value if adv else _opt_boats.value),
		"radius": _custom_radius.value if adv else DEFAULT_RADIUS,
		"chaos": _chaos.button_pressed if adv else false,
		"god": _god.button_pressed if adv else false,
		"difficulty": _opt_diff.selected,
		"sound": _opt_sound.button_pressed,
	}
	_close_settings()
	settings_saved.emit(cfg)
