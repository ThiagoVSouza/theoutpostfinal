extends SceneTree
## Renders the real game and settlement header with runtime-only review camera/forest settings.
## godot --path . --script tools/settlement_header_review.gd -- --output=res://previews/settlement-header/1600x1000.png --size=1600x1000
## Also saves a top-left -detail.png region at original pixel resolution.
## Add --interaction to exercise native pointer events and capture flag feedback states.
## Add --menu to check the seven icon buttons and their native selection/input behavior.
## Add --resources to check resource values, responsive layout, and pointer passthrough.

var _failures := 0
var _flag_activations := 0
var _pointer_position := Vector2.ZERO
var _pointer_inside := false
var _menu_actions: Array[StringName] = []
const MENU_SECTIONS: Array[StringName] = [
	&"domain", &"population", &"finances", &"military", &"diplomacy", &"religion", &"knowledge"]
const RESOURCE_KEYS: Array[StringName] = [&"gold", &"population", &"score"]

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
	var resources_review := false
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
		elif argument == "--resources":
			resources_review = true
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
	var resources: Control
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
		if resources_review:
			resources = hud.get_node_or_null("SettlementResources") as Control
			_check(resources != null, "Settlement resources Control is missing.")

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
	if resources_review and resources != null:
		await _review_resources(viewport, resources, header, game.get_node("StatsOverlay"), destination)
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
	_check_menu_feedback(first, original_rects[0], 1.12, 1.12, "hover")
	_save_state_detail(viewport, destination, "menu-hover")
	_mouse_button(viewport, centre, true)
	await _settle_feedback()
	_check(_menu_actions.is_empty(), "Menu activated before mouse release.")
	_check_menu_feedback(first, original_rects[0], 0.94, 0.82, "pressed")
	_save_state_detail(viewport, destination, "menu-pressed")
	_mouse_button(viewport, centre, false)
	await _settle_feedback()
	_check(_menu_actions.size() == 1 and _menu_actions[0] == MENU_SECTIONS[0], "Valid menu click did not emit exactly one correct section.")
	_check_menu_feedback(first, original_rects[0], 1.12, 1.16, "selected hover")
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

func _review_resources(viewport: SubViewport, resources: Control, header: Control, stats: Node, destination: String) -> void:
	_check_pass_through(resources, null)
	_check(resources.has_method("set_resource"), "Resource HUD is missing its runtime update API.")
	var icons: Array = resources.get("icons")
	var totals: Array = resources.get("total_labels")
	var increments: Array = resources.get("increment_labels")
	var cells: Array = resources.get("cells")
	_check(icons.size() == 3 and totals.size() == 3 and increments.size() == 3 and cells.size() == 3, "Resource HUD must contain three icon/value pairs.")
	if not resources.has_method("set_resource") or icons.size() != 3 or totals.size() != 3 or increments.size() != 3 or cells.size() != 3:
		return
	var parts: Array[Dictionary] = []
	for index in RESOURCE_KEYS.size():
		_check(StringName(cells[index].get_meta("resource", &"")) == RESOURCE_KEYS[index], "Resource order is incorrect at index " + str(index))
		parts.append({"id": RESOURCE_KEYS[index], "icon": icons[index], "total": totals[index], "yearly": increments[index]})
		_check(int(resources.get(str(RESOURCE_KEYS[index]) + "_total")) == 0, "Resource total does not default to zero.")
		_check(int(resources.get(str(RESOURCE_KEYS[index]) + "_yearly_increment")) == 0, "Resource yearly increment does not default to zero.")
	_check_resource_text(parts, ["0", "0", "0"], ["+0", "+0", "+0"], "default")
	_check_resource_layout(parts, header, stats, viewport.size, "default")
	_save_resource_state(viewport, parts, destination, "default", true)

	_set_resource_values(resources, [1250, 180, 420], [125, 12, 35])
	await _draw_review_frames()
	_check_resource_text(parts, ["1,250", "180", "420"], ["+125", "+12", "+35"], "sample")
	_check_resource_layout(parts, header, stats, viewport.size, "sample")
	_save_resource_state(viewport, parts, destination, "sample", true)
	await _review_resource_pointer(viewport, parts)

	_set_resource_values(resources, [5, 6, 7], [-125, 0, -35])
	await _draw_review_frames()
	_check_resource_text(parts, ["5", "6", "7"], ["-125", "+0", "-35"], "negative")
	_check_resource_layout(parts, header, stats, viewport.size, "negative")
	_save_resource_state(viewport, parts, destination, "negative")

	_set_resource_values(resources, [1234567890, 9876543210, 1234567890123], [9999999, -1234567, 0])
	await _draw_review_frames()
	_check_resource_layout(parts, header, stats, viewport.size, "large")
	for part in parts:
		var total: Label = part.total
		_check(not total.text.is_empty() and total.text != "0", "Large resource total was lost: " + str(part.id))
	_check((parts[0].yearly as Label).text.begins_with("+"), "Positive large yearly increment lost its sign.")
	var negative_text := (parts[1].yearly as Label).text.replace("−", "-")
	_check(negative_text.begins_with("-"), "Negative large yearly increment lost its sign.")
	_check((parts[2].yearly as Label).text == "+0", "Zero yearly increment lost its explicit plus sign.")
	_save_resource_state(viewport, parts, destination, "large")
	_set_resource_values(resources, [0, 0, 0], [0, 0, 0])
	await _draw_review_frames()
	_check_resource_text(parts, ["0", "0", "0"], ["+0", "+0", "+0"], "reset")

func _set_resource_values(resources: Control, totals: Array, increments: Array) -> void:
	for index in RESOURCE_KEYS.size():
		resources.call("set_resource", RESOURCE_KEYS[index], totals[index], increments[index])
		_check(int(resources.get(str(RESOURCE_KEYS[index]) + "_total")) == int(totals[index]), "Resource update lost the stored total.")
		_check(int(resources.get(str(RESOURCE_KEYS[index]) + "_yearly_increment")) == int(increments[index]), "Resource update lost the stored yearly increment.")

func _check_resource_text(parts: Array[Dictionary], totals: Array, increments: Array, state: String) -> void:
	for index in parts.size():
		var total: Label = parts[index].total
		var yearly: Label = parts[index].yearly
		_check(total.text == totals[index], "Incorrect resource total during " + state + ": " + total.text)
		_check(yearly.text.replace("−", "-") == increments[index], "Incorrect yearly increment during " + state + ": " + yearly.text)

func _check_resource_layout(parts: Array[Dictionary], header: Control, stats: Node, dimensions: Vector2i, state: String) -> void:
	var bounds := Rect2(Vector2.ZERO, Vector2(dimensions)).grow(0.5)
	var obstacles: Array[Rect2] = []
	if header != null:
		for property in ["banner", "shield", "name_label", "rank_label"]:
			var decoration := header.get(property) as Control
			if decoration != null:
				obstacles.append(decoration.get_global_rect())
	for child in stats.get_children():
		if child is Control and child.is_visible_in_tree():
			obstacles.append(child.get_global_rect())
	var previous_pair := Rect2()
	var total_y := 0.0
	var yearly_y := 0.0
	for index in parts.size():
		var part := parts[index]
		var icon: TextureRect = part.icon
		var total: Label = part.total
		var yearly: Label = part.yearly
		var icon_rect := icon.get_global_rect()
		var total_rect := total.get_global_rect()
		var yearly_rect := yearly.get_global_rect()
		var pair_rect := icon_rect.merge(total_rect).merge(yearly_rect)
		var context := str(part.id) + " during " + state
		_check(icon.texture != null, "Resource icon has no texture: " + context)
		_check(bounds.encloses(pair_rect), "Resource content extends outside viewport: " + context)
		_check(icon_rect.end.x <= minf(total_rect.position.x, yearly_rect.position.x) + 0.5, "Resource icon is not left of both values: " + context)
		_check(total_rect.end.y <= yearly_rect.position.y + 0.5, "Resource total and yearly value overlap: " + context + " total=" + str(total_rect) + " yearly=" + str(yearly_rect))
		_check(absf(total_rect.position.x - yearly_rect.position.x) <= 0.5, "Resource value columns are misaligned: " + context)
		_check(yearly.get_theme_font_size("font_size") < total.get_theme_font_size("font_size"), "Resource yearly value is not smaller than the total: " + context)
		for label: Label in [total, yearly]:
			var text_width := label.get_theme_font("font").get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("font_size")).x
			_check(text_width <= label.size.x + 0.5, "Resource value does not fit its label: " + context + " " + label.text)
			_check(not label.text.contains("…") and not label.text.contains("..."), "Resource value is ellipsized: " + context)
		for obstacle in obstacles:
			_check(not pair_rect.intersects(obstacle), "Resource overlaps the settlement header or developer stats: " + context)
		if index == 0:
			total_y = total_rect.position.y
			yearly_y = yearly_rect.position.y
		else:
			_check(previous_pair.end.x < pair_rect.position.x, "Resource groups overlap or have no horizontal gap: " + context)
			_check(absf(total_y - total_rect.position.y) <= 0.5 and absf(yearly_y - yearly_rect.position.y) <= 0.5, "Resource rows are misaligned: " + context)
		previous_pair = pair_rect
		print("RESOURCE_REVIEW_PAIR ", context, " ", pair_rect, " total=", total.text, " yearly=", yearly.text)

func _review_resource_pointer(viewport: SubViewport, parts: Array[Dictionary]) -> void:
	var probe := PointerProbe.new()
	viewport.add_child(probe)
	_ensure_pointer_inside(viewport)
	var flag_before := _flag_activations
	var menu_before := _menu_actions.size()
	for part in parts:
		for control: Control in [part.icon, part.total, part.yearly]:
			var point := control.get_global_rect().get_center()
			var before := probe.left_presses
			_move_pointer(viewport, point)
			_mouse_button(viewport, point, true)
			_mouse_button(viewport, point, false)
			await process_frame
			_check(probe.left_presses == before + 1, "Resource content blocked gameplay input at " + str(point))
	_check(_flag_activations == flag_before and _menu_actions.size() == menu_before, "Resource pointer passthrough activated another HUD control.")
	print("RESOURCE_REVIEW_INTERACTION passthrough=", probe.left_presses)
	probe.queue_free()

func _save_resource_state(viewport: SubViewport, parts: Array[Dictionary], destination: String, state: String, full_capture := false) -> void:
	var pixels := viewport.get_texture().get_image()
	var strip_height := 96
	for part in parts:
		for control: Control in [part.icon, part.total, part.yearly]:
			strip_height = maxi(strip_height, ceili(control.get_global_rect().end.y) + 16)
	var top := pixels.get_region(Rect2i(0, 0, pixels.get_width(), mini(strip_height, pixels.get_height())))
	var path := destination.get_basename() + "-resources-" + state + "-top.png"
	_check(top.save_png(path) == OK, "Could not save resource " + state + " top strip.")
	print("RESOURCE_REVIEW_TOP ", state, " ", path)
	if full_capture:
		var full_path := destination.get_basename() + "-resources-" + state + ".png"
		_check(pixels.save_png(full_path) == OK, "Could not save resource " + state + " full capture.")
		print("RESOURCE_REVIEW_CAPTURE ", state, " ", full_path)

func _draw_review_frames() -> void:
	for frame in 2:
		await process_frame
		await RenderingServer.frame_post_draw

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
