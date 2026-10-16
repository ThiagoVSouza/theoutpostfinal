extends SceneTree
## Renders the real game and settlement header with runtime-only review camera/forest settings.
## godot --path . --script tools/settlement_header_review.gd -- --output=res://previews/settlement-header/1600x1000.png --size=1600x1000
## Also saves a top-left -detail.png region at original pixel resolution.

var _failures := 0

func _initialize() -> void:
	call_deferred("_capture")

func _capture() -> void:
	var output := "res://previews/settlement-header/1600x1000.png"
	var dimensions := Vector2i(1600, 1000)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			output = argument.trim_prefix("--output=")
		elif argument.begins_with("--size="):
			var parts := argument.trim_prefix("--size=").split("x")
			if parts.size() == 2:
				dimensions = Vector2i(int(parts[0]), int(parts[1]))
	if dimensions.x <= 0 or dimensions.y <= 0:
		push_error("Review dimensions must be positive.")
		quit(1)
		return

	var viewport := SubViewport.new()
	viewport.size = dimensions
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var game: Node3D = load("res://scenes/main.tscn").instantiate()
	viewport.add_child(game)
	var board: Board = game.get_node("Board")
	var camera: StrategyCamera = game.get_node("Camera")
	var forest: Forest = game.get_node("Forest")
	# Only this review instance is changed; production scene defaults remain untouched.
	board.grid_visible = false
	camera.focus = Vector3(Board.TEST_LAND_CENTRE.x, 0.0, Board.TEST_LAND_CENTRE.y)
	camera.zoom = 90.0
	camera.set_process(false)
	camera.call("_apply")
	forest.set_count(1000)
	board.set_forest_map(forest.paint_texture, forest.paint_origin, forest.paint_size)

	for frame in 8:
		await process_frame
		await RenderingServer.frame_post_draw
	var hud := game.get_node_or_null("GameUI") as CanvasLayer
	_check(hud != null, "Main/GameUI CanvasLayer is missing.")
	if hud != null:
		_check(hud.layer == 10 and hud.layer < 100, "Header must use HUD layer 10 below loading overlay 100.")
		var header: Control
		for child in hud.get_children():
			if child is Control and _has_property(child, "settlement_name"):
				header = child
				break
		_check(header != null, "Settlement header Control is missing.")
		if header != null:
			_check(str(header.get("settlement_name")) == "Black Raven", "Default settlement name differs from Black Raven.")
			_check(str(header.get("settlement_rank")) == "Outpost", "Default settlement rank differs from Outpost.")
			_check_pass_through(header)
			var banner := header.get("banner") as TextureRect
			var shield := header.get("shield") as TextureRect
			_check(banner != null and shield != null, "Header banner or shield is missing.")
			if banner != null and shield != null:
				_check(banner.get_global_rect().position.x < 0.0, "Banner's faded edge is not moved offscreen.")
				_check(banner.get_global_rect().end.x > shield.get_global_rect().end.x, "Banner does not extend behind the full shield.")
				_check(shield.get_index() > banner.get_index(), "Shield does not draw above banner.")
			var bounds := Rect2(Vector2.ZERO, Vector2(dimensions)).grow(1.0)
			for property in ["name_label", "rank_label"]:
				var label := header.get(property) as Label
				_check(label != null, "Header is missing " + property + ".")
				if label != null:
					var expected := "Black Raven" if property == "name_label" else "Outpost"
					_check(label.text == expected, property + " displays unexpected text: " + label.text)
					_check(bounds.encloses(label.get_global_rect()), property + " extends outside the viewport.")
					var text_width := label.get_theme_font("font").get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("font_size")).x
					_check(text_width <= label.size.x, property + " is too narrow to show the complete text.")
					print("HEADER_REVIEW_LABEL ", property, " ", label.get_global_rect())

	var image := viewport.get_texture().get_image()
	_check(image != null and not image.is_empty(), "Viewport returned no pixels.")
	var destination := ProjectSettings.globalize_path(output)
	var directory_error := DirAccess.make_dir_recursive_absolute(destination.get_base_dir())
	_check(directory_error == OK, "Could not create output directory: " + error_string(directory_error))
	var save_error := image.save_png(destination)
	_check(save_error == OK, "Could not save capture: " + error_string(save_error))
	var detail_destination := destination.get_basename() + "-detail.png"
	var detail := image.get_region(Rect2i(0, 0, mini(720, dimensions.x), mini(260, dimensions.y)))
	var detail_error := detail.save_png(detail_destination)
	_check(detail_error == OK, "Could not save detail capture: " + error_string(detail_error))
	print("HEADER_REVIEW_CAPTURE ", destination)
	print("HEADER_REVIEW_DETAIL ", detail_destination)
	print("HEADER_REVIEW_SIZE ", dimensions.x, "x", dimensions.y)
	print("HEADER_REVIEW_CHECKS ", "PASS" if _failures == 0 else "FAIL (%d)" % _failures)
	viewport.queue_free()
	await process_frame
	quit(0 if _failures == 0 else 1)

func _check_pass_through(node: Node) -> void:
	if node is Control:
		_check(node.mouse_filter == Control.MOUSE_FILTER_IGNORE, str(node.get_path()) + " intercepts mouse input.")
	for child in node.get_children():
		_check_pass_through(child)

func _has_property(object: Object, property_name: String) -> bool:
	for property in object.get_property_list():
		if property.name == property_name:
			return true
	return false

func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("HEADER_REVIEW: " + message)
