extends SceneTree
## Deterministic renderer for the real loading-screen controls, without loading the world.
## godot --path . --script tools/loading_screen_review.gd -- --output=C:/Dev/loading.png --size=1600x1000 --progress=0.42
## Add --error to capture and check the persistent failure state.
## Add --startup to load the real world, verify its reveal, and capture the resulting scene.
## Add --resize=640x480 to check the live layout after resizing from --size.

var _failures := 0

func _initialize() -> void:
	call_deferred("_capture")

func _capture() -> void:
	var output := "user://loading_screen_review.png"
	var dimensions := Vector2i(1600, 1000)
	var resize_dimensions := Vector2i.ZERO
	var progress := 0.42
	var show_error := false
	var startup := false
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			output = argument.trim_prefix("--output=")
		elif argument.begins_with("--size="):
			var parts := argument.trim_prefix("--size=").split("x")
			if parts.size() == 2:
				dimensions = Vector2i(int(parts[0]), int(parts[1]))
		elif argument.begins_with("--progress="):
			progress = clampf(float(argument.trim_prefix("--progress=")), 0.0, 1.0)
		elif argument.begins_with("--resize="):
			var parts := argument.trim_prefix("--resize=").split("x")
			if parts.size() == 2:
				resize_dimensions = Vector2i(int(parts[0]), int(parts[1]))
		elif argument == "--error":
			show_error = true
		elif argument == "--startup":
			startup = true
	if dimensions.x <= 0 or dimensions.y <= 0:
		push_error("Review dimensions must be positive.")
		quit(1)
		return

	var viewport := SubViewport.new()
	viewport.size = dimensions
	viewport.disable_3d = not startup
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var screen: Control = load("res://scripts/ui/loading_screen.gd").new()
	if not startup:
		screen.process_mode = Node.PROCESS_MODE_DISABLED
	var preview_supported := false
	for property in screen.get_property_list():
		if property.name == "preview_mode":
			preview_supported = true
			break
	if startup:
		viewport.add_child(screen)
		await _verify_startup(screen)
	elif preview_supported:
		screen.set("preview_mode", true)
		viewport.add_child(screen)
	else:
		# Baseline compatibility: build the real controls before the loader enters a tree.
		# Move only its CanvasLayer into the render viewport, so _ready never requests a scene.
		screen.call("_build_ui")
		var canvas: CanvasLayer = screen.get("layer")
		screen.remove_child(canvas)
		viewport.add_child(canvas)

	if not startup:
		_set_preview_state(screen, progress, show_error, preview_supported)

	# Containers settle through deferred sorts; frame_post_draw confirms real pixels exist.
	for frame in 4:
		await process_frame
		await RenderingServer.frame_post_draw
	if resize_dimensions.x > 0 and resize_dimensions.y > 0:
		dimensions = resize_dimensions
		viewport.size = dimensions
		for frame in 4:
			await process_frame
			await RenderingServer.frame_post_draw
	if not startup:
		var bounds := Rect2(Vector2.ZERO, Vector2(dimensions)).grow(1.0)
		var bar: ProgressBar = screen.get("bar")
		for control: Control in [bar, screen.get("percent_label"), screen.get("stage_label")]:
			_check(bounds.encloses(control.get_global_rect()), "%s lies outside %s: %s" % [control.get_class(), dimensions, control.get_global_rect()])
		_check(bar.size.x >= 100.0 and bar.size.y > 0.0, "Loading bar has no useful visible area.")
		if preview_supported:
			var loading_view: Control = screen.get("view")
			for property in ["logo", "heading", "tip", "actions"]:
				var control: Control = loading_view.get(property)
				if not control.is_visible_in_tree():
					continue
				var rect := control.get_global_rect()
				_check(bounds.encloses(rect), "%s lies outside %s: %s" % [property, dimensions, rect])
				_check(absf(rect.get_center().x - dimensions.x * 0.5) <= 1.0, "%s is not centered: %s" % [property, rect])
	var image := viewport.get_texture().get_image()
	_check(image != null and not image.is_empty(), "Viewport returned no pixels.")
	var destination := ProjectSettings.globalize_path(output)
	var directory_error := DirAccess.make_dir_recursive_absolute(destination.get_base_dir())
	_check(directory_error == OK, "Could not create output directory: " + error_string(directory_error))
	var save_error := image.save_png(destination)
	_check(save_error == OK, "Could not save capture: " + error_string(save_error))
	print("LOADING_REVIEW_CAPTURE ", destination)
	print("LOADING_REVIEW_SIZE ", dimensions.x, "x", dimensions.y)
	print("LOADING_REVIEW_CHECKS ", "PASS" if _failures == 0 else "FAIL (%d)" % _failures)
	if not preview_supported and not startup:
		screen.free()
	viewport.queue_free()
	await process_frame
	quit(0 if _failures == 0 else 1)

func _set_preview_state(screen: Control, progress: float, show_error: bool, preview_supported: bool) -> void:
	screen.call("_set_progress", progress, "Gathering resources")
	screen.set("shown", progress)
	var bar: ProgressBar = screen.get("bar")
	var percent: Label = screen.get("percent_label")
	var stage: Label = screen.get("stage_label")
	bar.value = progress * 100.0
	percent.text = "%d%%" % floori(progress * 100.0)
	if show_error:
		if preview_supported:
			screen.set("preview_mode", false)
		screen.call("_fail", "The game resources could not be loaded. Please restart the game.")
		# Exercise several updates; failure copy and the blank percentage must remain stable.
		for frame in 3:
			screen.call("_process", 1.0 / 60.0)
		_check(percent.text.is_empty(), "Failure percentage was restored by _process.")
		_check(stage.text.contains("could not be loaded"), "Failure explanation was replaced.")
	else:
		_check(is_equal_approx(bar.value, progress * 100.0), "Progress bar differs from requested progress.")
	_check(not bool(screen.get("loading")), "Preview unexpectedly requested a resource load.")
	_check(screen.get("game") == null, "Preview unexpectedly instantiated the game.")

func _verify_startup(screen: Control) -> void:
	var started := Time.get_ticks_msec()
	var deadline := started + 20000
	var previous_progress := 0.0
	while screen.get("overlay") != null and Time.get_ticks_msec() < deadline:
		await process_frame
		var actual_progress := float(screen.get("shown"))
		_check(actual_progress >= previous_progress, "Actual startup progress moved backward.")
		previous_progress = actual_progress
		if bool(screen.get("failed")):
			break
	_check(not bool(screen.get("failed")), "Actual startup reported a loading failure.")
	_check(screen.get("overlay") == null and screen.get("layer") == null, "Loading overlay was not removed within 20 seconds.")
	var game: Node = screen.get("game")
	_check(game != null and game.is_inside_tree(), "Game was not instantiated into the scene tree.")
	_check(not screen.is_processing(), "Loader continued processing after reveal.")
	_check(screen.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Loader intercepts mouse input after reveal.")
	print("LOADING_REVIEW_STARTUP_MS ", Time.get_ticks_msec() - started)

func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("LOADING_REVIEW: " + message)
