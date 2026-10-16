extends SceneTree
## Renders the real game and settlement header with runtime-only review camera/forest settings.
## godot --path . --script tools/settlement_header_review.gd -- --output=res://previews/settlement-header/1600x1000.png --size=1600x1000
## Also saves a top-left -detail.png region at original pixel resolution.
## Add --interaction to exercise native pointer events and capture flag feedback states.
## Add --menu to check the seven icon buttons and their native selection/input behavior.

var _failures := 0
var _flag_activations := 0
var _pointer_position := Vector2.ZERO
var _pointer_inside := false
var _menu_actions: Array[StringName] = []
const MENU_SECTIONS: Array[StringName] = [
	&"domain", &"population", &"finances", &"military", &"diplomacy", &"religion", &"knowledge"]

class PointerProbe extends Node:
	var left_presses := 0
	func _unhandled_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			left_presses += 1

func _initialize() -> void:
	call_deferred("_capture")

func _capture() -> void:
	var output := "res://previews/settlement-header/1600x1000.png"
	var dimensions := Vector2i(1600, 1000)
	var interaction := false
	var menu_review := false
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			output = argument.trim_prefix("--output=")
		elif argument.begins_with("--size="):
			var parts := argument.trim_prefix("--size=").split("x")
			if parts.size() == 2:
				dimensions = Vector2i(int(parts[0]), int(parts[1]))
		elif argument == "--interaction":
			interaction = true
		elif argument == "--menu":
			menu_review = true
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
	var header: Control
	var menu: Control
	_check(hud != null, "Main/GameUI CanvasLayer is missing.")
	if hud != null:
		_check(hud.layer == 10 and hud.layer < 100, "Header must use HUD layer 10 below loading overlay 100.")
		for child in hud.get_children():
			if child is Control and _has_property(child, "settlement_name"):
				header = child
				break
		_check(header != null, "Settlement header Control is missing.")
		if header != null:
			_check(str(header.get("settlement_name")) == "Black Raven", "Default settlement name differs from Black Raven.")
			_check(str(header.get("settlement_rank")) == "Outpost", "Default settlement rank differs from Outpost.")
			var flag_button := header.get("flag_button") as Button if _has_property(header, "flag_button") else null
			_check_pass_through(header, flag_button)
			var banner := header.get("banner") as TextureRect
			var shield := header.get("shield") as TextureRect
			_check(banner != null and shield != null, "Header banner or shield is missing.")
			if banner != null and shield != null:
				_check(banner.get_global_rect().position.x < 0.0, "Banner's faded edge is not moved offscreen.")
				_check(banner.get_global_rect().end.x > shield.get_global_rect().end.x, "Banner does not extend behind the full shield.")
				var shield_layer: Node = shield if shield.get_parent() == header else shield.get_parent()
				_check(shield_layer.get_index() > banner.get_index(), "Shield does not draw above banner.")
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
		if menu_review:
			for child in hud.get_children():
				if child is Control and child.has_signal("section_pressed") and _has_property(child, "buttons"):
					menu = child
					break
			_check(menu != null, "Seven-button settlement menu is missing.")
			if menu != null:
				_check_menu_layout(menu, dimensions)

	var image := viewport.get_texture().get_image()
	_check(image != null and not image.is_empty(), "Viewport returned no pixels.")
	var destination := ProjectSettings.globalize_path(output)
	var directory_error := DirAccess.make_dir_recursive_absolute(destination.get_base_dir())
	_check(directory_error == OK, "Could not create output directory: " + error_string(directory_error))
	var save_error := image.save_png(destination)
	_check(save_error == OK, "Could not save capture: " + error_string(save_error))
	var detail_destination := destination.get_basename() + "-detail.png"
	var detail := image.get_region(Rect2i(0, 0, mini(720, dimensions.x), mini(480, dimensions.y)))
	var detail_error := detail.save_png(detail_destination)
	_check(detail_error == OK, "Could not save detail capture: " + error_string(detail_error))
	print("HEADER_REVIEW_CAPTURE ", destination)
	print("HEADER_REVIEW_DETAIL ", detail_destination)
	print("HEADER_REVIEW_SIZE ", dimensions.x, "x", dimensions.y)
	if interaction and header != null:
		await _review_interaction(viewport, header, destination)
	if menu_review and menu != null:
		await _review_menu(viewport, menu, destination)
	print("HEADER_REVIEW_CHECKS ", "PASS" if _failures == 0 else "FAIL (%d)" % _failures)
	viewport.queue_free()
	await process_frame
	quit(0 if _failures == 0 else 1)

func _check_pass_through(node: Node, flag_button: Button) -> void:
	if node is Control:
		var expected := Control.MOUSE_FILTER_STOP if node == flag_button else Control.MOUSE_FILTER_IGNORE
		_check(node.mouse_filter == expected, str(node.get_path()) + " has the wrong mouse filter.")
	for child in node.get_children():
		_check_pass_through(child, flag_button)

func _review_interaction(viewport: SubViewport, header: Control, destination: String) -> void:
	var button := header.get("flag_button") as Button
	var shield := header.get("shield") as TextureRect
	_check(button != null and shield != null, "Interactive flag controls are missing.")
	if button == null or shield == null:
		return
	_check(button.button_mask == MOUSE_BUTTON_MASK_LEFT, "Flag must activate with the left mouse button only.")
	_check(header.has_signal("flag_pressed"), "Header is missing flag_pressed.")
	if not header.has_signal("flag_pressed"):
		return
	header.connect("flag_pressed", func(): _flag_activations += 1)
	var probe := PointerProbe.new()
	viewport.add_child(probe)
	var hit_rect := button.get_global_rect()
	var centre := hit_rect.get_center()
	var away := Vector2(hit_rect.end.x + 100.0, hit_rect.end.y + 80.0)
	_ensure_pointer_inside(viewport)
	_move_pointer(viewport, away)
	await _settle_feedback()
	_check_flag_state(button, shield, hit_rect, 1.0, 1.0, "rest")
	_save_state_detail(viewport, destination, "rest")

	_move_pointer(viewport, centre)
	await _settle_feedback()
	_check(button.is_hovered(), "Native button did not receive pointer hover.")
	_check_flag_state(button, shield, hit_rect, 1.08, 1.12, "hover")
	_save_state_detail(viewport, destination, "hover")

	_mouse_button(viewport, centre, true)
	await _settle_feedback()
	_check(_flag_activations == 0, "Flag activated before the mouse was released.")
	_check(probe.left_presses == 0, "Flag press leaked through to gameplay input.")
	_check_flag_state(button, shield, hit_rect, 0.94, 0.82, "pressed")
	_save_state_detail(viewport, destination, "pressed")

	_mouse_button(viewport, centre, false)
	await _settle_feedback()
	_check(_flag_activations == 1, "Valid flag click must emit exactly one activation.")
	_check_flag_state(button, shield, hit_rect, 1.08, 1.12, "released")
	_save_state_detail(viewport, destination, "released")

	# A press dragged outside must cancel without changing the fixed target rectangle.
	_mouse_button(viewport, centre, true)
	_move_pointer(viewport, away, MOUSE_BUTTON_MASK_LEFT)
	await _settle_feedback()
	_check_flag_state(button, shield, hit_rect, 1.0, 1.0, "dragged outside")
	_mouse_button(viewport, away, false)
	await _settle_feedback()
	_check(_flag_activations == 1, "Dragging outside activated the flag.")
	_check_flag_state(button, shield, hit_rect, 1.0, 1.0, "canceled")

	# Exercise pointer propagation through the real decorative controls into _unhandled_input.
	var banner: Control = header.get("banner")
	var points := [
		(header.get("name_label") as Control).get_global_rect().get_center(),
		(header.get("rank_label") as Control).get_global_rect().get_center(),
		Vector2(banner.get_global_rect().end.x - 10.0, banner.get_global_rect().get_center().y)]
	for point: Vector2 in points:
		var before := probe.left_presses
		_move_pointer(viewport, point)
		_mouse_button(viewport, point, true)
		_mouse_button(viewport, point, false)
		await process_frame
		_check(probe.left_presses == before + 1, "Decorative header content blocked gameplay input at " + str(point))
	_check(_flag_activations == 1, "Decorative header content triggered a flag action.")
	print("HEADER_REVIEW_INTERACTION activations=", _flag_activations, " passthrough=", probe.left_presses)
	probe.queue_free()

func _check_menu_layout(menu: Control, dimensions: Vector2i) -> void:
	var buttons: Array = menu.get("buttons")
	_check(buttons.size() == MENU_SECTIONS.size(), "Menu must contain exactly seven section buttons.")
	_check_menu_decorations(menu, buttons, false, menu)
	var bounds := Rect2(Vector2.ZERO, Vector2(dimensions))
	for index in buttons.size():
		var button: Button = buttons[index]
		var rect := button.get_global_rect()
		_check(bounds.encloses(rect), "Menu button extends beyond viewport: " + str(rect))
		_check(button.text.is_empty(), "Menu button has a visible text label.")
		_check(button.mouse_filter == Control.MOUSE_FILTER_STOP, "Menu button does not handle pointer input.")
		_check(button.button_mask == MOUSE_BUTTON_MASK_LEFT, "Menu button accepts an unintended mouse button.")
		if index < MENU_SECTIONS.size():
			_check(StringName(button.get_meta("section", &"")) == MENU_SECTIONS[index], "Menu section order is incorrect at index " + str(index))
		if index > 0:
			var previous: Button = buttons[index - 1]
			_check(previous.get_global_rect().end.y < rect.position.y, "Adjacent menu buttons overlap or have no pointer gap.")
		var medallion := button.get_node_or_null("Medallion") as TextureRect
		_check(medallion != null and medallion.texture != null, "Menu button has no medallion image.")
		print("MENU_REVIEW_BUTTON ", button.get_meta("section", &""), " ", rect)

func _check_menu_decorations(node: Node, buttons: Array, inside_button := false, menu_root: Control = null) -> void:
	var is_button := node is Button and node in buttons
	var in_button := inside_button or is_button
	var is_background := node is Panel and node.name == &"Background" and node.get_parent() == menu_root
	if node is Control:
		if not is_button:
			_check(node.mouse_filter == Control.MOUSE_FILTER_IGNORE, str(node.get_path()) + " blocks menu background input.")
		_check(not (node is Label and node.visible), "Menu contains a visible label.")
		if not in_button and not is_background:
			_check(not (node is Panel or node is PanelContainer or node is ColorRect or node is TextureRect), "Menu contains a sidebar background outside its icon buttons.")
	for child in node.get_children():
		_check_menu_decorations(child, buttons, in_button, menu_root)

func _review_menu(viewport: SubViewport, menu: Control, destination: String) -> void:
	var buttons: Array = menu.get("buttons")
	if buttons.size() != MENU_SECTIONS.size():
		return
	menu.connect("section_pressed", func(section: StringName): _menu_actions.append(section))
	var probe := PointerProbe.new()
	viewport.add_child(probe)
	var original_rects: Array[Rect2] = []
	for button: Button in buttons:
		original_rects.append(button.get_global_rect())
	var first: Button = buttons[0]
	var centre := first.get_global_rect().get_center()
	var away := Vector2(first.get_global_rect().end.x + 90.0, centre.y)
	_ensure_pointer_inside(viewport)
	_move_pointer(viewport, away)
	await _settle_feedback()
	_check(StringName(menu.get("selected_section")) == &"", "Menu starts with an unexpected selection.")
	_check_menu_feedback(first, original_rects[0], 1.0, 1.0, "rest")
	_save_state_detail(viewport, destination, "menu-rest")

	_move_pointer(viewport, centre)
	await _settle_feedback()
	_check(first.is_hovered(), "Menu button did not receive a native hover.")
	_check_menu_feedback(first, original_rects[0], 1.08, 1.12, "hover")
	_save_state_detail(viewport, destination, "menu-hover")
	_mouse_button(viewport, centre, true)
	await _settle_feedback()
	_check(_menu_actions.is_empty(), "Menu activated before mouse release.")
	_check_menu_feedback(first, original_rects[0], 0.94, 0.82, "pressed")
	_save_state_detail(viewport, destination, "menu-pressed")
	_mouse_button(viewport, centre, false)
	await _settle_feedback()
	_check(_menu_actions.size() == 1 and _menu_actions[0] == MENU_SECTIONS[0], "Valid menu click did not emit exactly one correct section.")
	_check_menu_feedback(first, original_rects[0], 1.08, 1.16, "selected hover")
	_move_pointer(viewport, away)
	await _settle_feedback()
	_check_menu_selection(menu, buttons, MENU_SECTIONS[0])
	_save_state_detail(viewport, destination, "menu-selected")

	# Activate each remaining native button and ensure selection transfers exclusively.
	for index in range(1, buttons.size()):
		var button: Button = buttons[index]
		var point := button.get_global_rect().get_center()
		_move_pointer(viewport, point)
		_mouse_button(viewport, point, true)
		_mouse_button(viewport, point, false)
		_move_pointer(viewport, away)
		await _settle_feedback()
		_check(_menu_actions.size() == index + 1 and _menu_actions[index] == MENU_SECTIONS[index], "Menu click emitted an incorrect section or duplicate action.")
		_check_menu_selection(menu, buttons, MENU_SECTIONS[index])
	_check(probe.left_presses == 0, "Menu button press leaked through to gameplay.")

	# Cancel a press on an unselected icon; the last selection must remain active.
	_move_pointer(viewport, centre)
	_mouse_button(viewport, centre, true)
	_move_pointer(viewport, away, MOUSE_BUTTON_MASK_LEFT)
	await _settle_feedback()
	_check_menu_feedback(first, original_rects[0], 1.0, 1.0, "dragged outside")
	_mouse_button(viewport, away, false)
	await _settle_feedback()
	_check(_menu_actions.size() == 7, "Canceled menu drag emitted an action.")
	_check_menu_selection(menu, buttons, MENU_SECTIONS.back())

	# Gaps and open space around the icons must reach ordinary gameplay input.
	var pass_points: Array[Vector2] = [
		Vector2(maxf(0.0, original_rects[0].position.x - 4.0), centre.y), away]
	for index in range(buttons.size() - 1):
		pass_points.append(Vector2(centre.x, (original_rects[index].end.y + original_rects[index + 1].position.y) * 0.5))
	for point in pass_points:
		var before := probe.left_presses
		_move_pointer(viewport, point)
		_mouse_button(viewport, point, true)
		_mouse_button(viewport, point, false)
		await process_frame
		_check(probe.left_presses == before + 1, "Menu background blocked gameplay input at " + str(point))
	_check(_menu_actions.size() == 7, "Menu gap or backdrop triggered an action.")
	for index in buttons.size():
		var button: Button = buttons[index]
		_check(button.get_global_rect().is_equal_approx(original_rects[index]), "Menu button hit rectangle moved during interaction.")
	print("MENU_REVIEW_INTERACTION activations=", _menu_actions.size(), " passthrough=", probe.left_presses, " selected=", menu.get("selected_section"))
	probe.queue_free()

func _check_menu_feedback(button: Button, original_rect: Rect2, expected_scale: float, brightness: float, state: String) -> void:
	var medallion := button.get_node("Medallion") as TextureRect
	_check(button.get_global_rect().is_equal_approx(original_rect), "Menu hit rectangle changed during " + state + ".")
	_check(medallion.scale.is_equal_approx(Vector2.ONE * expected_scale), "Unexpected menu scale during " + state + ": " + str(medallion.scale))
	_check(medallion.self_modulate.is_equal_approx(Color(brightness, brightness, brightness, 1.0)), "Unexpected menu brightness during " + state + ": " + str(medallion.self_modulate))

func _check_menu_selection(menu: Control, buttons: Array, selected: StringName) -> void:
	_check(StringName(menu.get("selected_section")) == selected, "Menu did not retain the requested section selection.")
	for button: Button in buttons:
		var active := StringName(button.get_meta("section")) == selected
		var medallion := button.get_node("Medallion") as TextureRect
		_check(medallion.scale.is_equal_approx(Vector2.ONE), "Idle menu icon remained scaled.")
		var brightness := 1.08 if active else 1.0
		_check(medallion.self_modulate.is_equal_approx(Color(brightness, brightness, brightness, 1.0)), "Menu selection highlight is not exclusive.")
		var rim := button.get_node_or_null("Medallion/SelectionRim") as Control
		if rim != null:
			_check(rim.visible == active, "Menu selection rim is not exclusive.")

func _ensure_pointer_inside(viewport: SubViewport) -> void:
	if not _pointer_inside:
		viewport.notify_mouse_entered()
		_pointer_inside = true

func _move_pointer(viewport: SubViewport, point: Vector2, buttons := 0) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	event.relative = point - _pointer_position
	event.button_mask = buttons
	_pointer_position = point
	viewport.push_input(event, true)

func _mouse_button(viewport: SubViewport, point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.pressed = pressed
	viewport.push_input(event, true)

func _settle_feedback() -> void:
	await create_timer(0.18).timeout
	await RenderingServer.frame_post_draw

func _check_flag_state(button: Button, shield: TextureRect, hit_rect: Rect2, expected_scale: float, brightness: float, state: String) -> void:
	_check(button.get_global_rect().is_equal_approx(hit_rect), "Flag hit rectangle changed during " + state + ".")
	_check(shield.scale.is_equal_approx(Vector2.ONE * expected_scale), "Unexpected flag scale during " + state + ": " + str(shield.scale))
	_check(shield.self_modulate.is_equal_approx(Color(brightness, brightness, brightness, 1.0)), "Unexpected flag brightness during " + state + ": " + str(shield.self_modulate))

func _save_state_detail(viewport: SubViewport, destination: String, state: String) -> void:
	var image := viewport.get_texture().get_image()
	var detail := image.get_region(Rect2i(0, 0, mini(720, image.get_width()), mini(480, image.get_height())))
	var path := destination.get_basename() + "-" + state + "-detail.png"
	_check(detail.save_png(path) == OK, "Could not save " + state + " detail.")
	print("HEADER_REVIEW_STATE ", state, " ", path)

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
