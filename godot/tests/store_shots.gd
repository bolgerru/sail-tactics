extends SceneTree
## Renders App Store screenshots (1320x2868, iPhone 6.9") offscreen from the real game.
## Run: godot --path godot -s res://tests/store_shots.gd -- <out_dir>

const SIZE := Vector2i(1320, 2868)
var out_dir := "res://build/store"
var vp: SubViewport


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	var img := vp.get_texture().get_image()
	img.convert(Image.FORMAT_RGB8) # App Store screenshots must have no alpha
	img.save_png("%s/%s.png" % [out_dir, name])
	print("saved ", name, " ", img.get_size())


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	seed(11)

	vp = SubViewport.new()
	vp.size = SIZE
	vp.size_2d_override = Vector2i(390, 847)
	vp.size_2d_override_stretch = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.msaa_2d = Viewport.MSAA_4X
	root.add_child(vp)

	var main: SailGame = load("res://main.tscn").instantiate()
	vp.add_child(main)
	await process_frame
	main.hud._close_settings()
	main.top_inset = 59.0 # Dynamic Island
	main.bottom_inset = 34.0
	main.finish_line_y = main.top_inset + SailGame.FINISH_OFFSET
	main.hud.set_insets(main.top_inset, main.bottom_inset)

	main.boat_count = 5
	main.difficulty = 3
	main.reset_game()
	await _shot("1_ready")

	main.handle_tap()
	for i in 70:
		main.sim_step()
	await _shot("2_countdown")

	# Race: let the countdown finish, then tack on a rhythm.
	for i in 200:
		main.sim_step()
	main.handle_tap()
	var t := 0
	while t < 2600 and main.state == SailGame.State.PLAYING:
		main.sim_step()
		t += 1
		if t % 330 == 0:
			main.handle_tap()
	await _shot("3_racing")

	main.hud.hide_medal()
	main.end_game(1)
	for i in 50:
		main.sim_step()
	await _shot("4_win")

	main.reset_game()
	main.hud.open_settings({"speed": 0.2, "boats": 5, "difficulty": 3, "sound": true,
		"radius": 15.0, "chaos": false, "god": false}, false)
	await _shot("5_settings")
	quit()
