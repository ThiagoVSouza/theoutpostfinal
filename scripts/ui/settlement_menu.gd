extends Control
## Compact section navigation. Only the individual buttons receive mouse input;
## the gaps and the rest of the map remain available to the camera.

signal section_pressed(section: StringName)

const MEDALLIONS := preload("res://assets/ui/menu/medallions.png")
const SECTIONS: Array[StringName] = [
	&"domain", &"population", &"finances", &"military", &"diplomacy", &"religion", &"knowledge",
]
## Source regions are supplied with the medallion atlas; the original artwork is not tinted.
const ATLAS_REGIONS: Array[Rect2] = [
	Rect2(32, 42, 384, 384), Rect2(474, 42, 384, 384), Rect2(914, 42, 384, 384),
	Rect2(1356, 42, 384, 384), Rect2(31, 458, 384, 384), Rect2(472, 458, 384, 384),
	Rect2(915, 458, 384, 384),
]
const HIT_SIZE := 40.0
const ROW_PITCH := 44.0
const HOVER_SCALE := 1.08
const PRESSED_SCALE := 0.94
const HOVER_BRIGHTNESS := 1.12
const PRESSED_BRIGHTNESS := 0.82
const SELECTED_BRIGHTNESS := 1.08
const SELECTED_HOVER_BRIGHTNESS := 1.16

@export var selected_section: StringName = &"":
	set(value):
		if value != &"" and not SECTIONS.has(value):
			push_warning("Unknown settlement section: " + str(value))
			return
		if selected_section == value: return
		selected_section = value
		if is_node_ready():
			for index in buttons.size():
				_update_feedback(index)

var buttons: Array[Button] = []
var _background: Panel
var _medallions: Array[TextureRect] = []
var _selection_rims: Array[Panel] = []
var _tweens: Array[Tween] = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_background()
	_tweens.resize(SECTIONS.size())
	for index in SECTIONS.size():
		_build_button(index)
	get_viewport().size_changed.connect(_layout)
	_layout()

func _build_background() -> void:
	# A quiet brown panel and fine antique-gold edge, matching the reference HUD.
	# It is decorative: camera input still passes through the gaps between buttons.
	var style := StyleBoxFlat.new()
	style.bg_color = Color("30281d")
	style.border_color = Color("9b8151")
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.corner_detail = 4
	style.shadow_color = Color(0.025, 0.018, 0.01, 0.4)
	style.shadow_size = 3
	style.shadow_offset = Vector2(1, 1)
	_background = Panel.new()
	_background.name = "Background"
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_background.add_theme_stylebox_override("panel", style)
	add_child(_background)

func _build_button(index: int) -> void:
	var section := SECTIONS[index]
	var button := Button.new()
	button.name = str(section).capitalize() + "Button"
	button.flat = true
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.button_mask = MOUSE_BUTTON_MASK_LEFT
	button.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
	button.custom_minimum_size = Vector2.ONE * HIT_SIZE
	button.set_meta(&"section", section)
	var accessible_name := str(section).capitalize()
	button.set_meta(&"accessibility_name", accessible_name)
	# Set the native name where supported without adding visible text or tooltips.
	for property in button.get_property_list():
		if property.name == "accessibility_name":
			button.set("accessibility_name", accessible_name)
			break
	for state in ["normal", "hover", "pressed", "disabled", "hover_pressed"]:
		button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	button.add_theme_stylebox_override("focus", _ring_style(Color("c9b58d")))
	add_child(button)
	buttons.append(button)

	var atlas := AtlasTexture.new()
	atlas.atlas = MEDALLIONS
	atlas.region = ATLAS_REGIONS[index]
	atlas.filter_clip = true
	var medallion := TextureRect.new()
	medallion.name = "Medallion"
	medallion.texture = atlas
	medallion.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	medallion.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	medallion.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	medallion.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(medallion)
	_medallions.append(medallion)

	var rim := Panel.new()
	rim.name = "SelectionRim"
	rim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rim.add_theme_stylebox_override("panel", _ring_style(Color("f1d99d")))
	rim.hide()
	medallion.add_child(rim)
	_selection_rims.append(rim)

	# Native state has settled by the time these deferred callbacks run, including
	# dragging out of a held button and returning before release.
	button.mouse_entered.connect(_update_feedback.bind(index), CONNECT_DEFERRED)
	button.mouse_exited.connect(_update_feedback.bind(index), CONNECT_DEFERRED)
	button.button_down.connect(_update_feedback.bind(index), CONNECT_DEFERRED)
	button.button_up.connect(_update_feedback.bind(index), CONNECT_DEFERRED)
	button.focus_exited.connect(_update_feedback.bind(index), CONNECT_DEFERRED)
	button.visibility_changed.connect(_update_feedback.bind(index), CONNECT_DEFERRED)
	button.pressed.connect(_on_section_pressed.bind(index))

func _layout() -> void:
	var factor := clampf(get_viewport_rect().size.x / 800.0, 0.65, 1.0)
	# Follow the flag's centre and vertical offset, retaining useful button sizes
	# in narrow windows instead of reducing the targets below forty pixels.
	position = Vector2(34.0 * factor - HIT_SIZE * 0.5, 94.0 * factor)
	size = Vector2(HIT_SIZE, ROW_PITCH * (buttons.size() - 1) + HIT_SIZE)
	# Preserve the button positions while keeping the border inside narrow viewports.
	var horizontal_padding := clampf(position.x - 2.0, 0.0, 8.0)
	var vertical_padding := 8.0 * factor
	_background.position = Vector2(-horizontal_padding, -vertical_padding)
	_background.size = size + Vector2(horizontal_padding * 2.0, vertical_padding * 2.0)
	var art_size := maxf(36.0, 38.0 * factor)
	for index in buttons.size():
		var button := buttons[index]
		button.position = Vector2(0.0, index * ROW_PITCH)
		button.size = Vector2.ONE * HIT_SIZE
		var medallion := _medallions[index]
		medallion.position = Vector2.ONE * (HIT_SIZE - art_size) * 0.5
		medallion.size = Vector2.ONE * art_size
		medallion.pivot_offset = medallion.size * 0.5
		_selection_rims[index].position = Vector2.ONE * -1.0
		_selection_rims[index].size = medallion.size + Vector2.ONE * 2.0
		_update_feedback(index, false)

func _on_section_pressed(index: int) -> void:
	selected_section = SECTIONS[index]
	section_pressed.emit(selected_section)

func _update_feedback(index: int, animate := true) -> void:
	var selected := selected_section == SECTIONS[index]
	_selection_rims[index].visible = selected
	var target_scale := 1.0
	var brightness := SELECTED_BRIGHTNESS if selected else 1.0
	var duration := 0.12
	var draw_mode := buttons[index].get_draw_mode()
	if draw_mode in [BaseButton.DRAW_PRESSED, BaseButton.DRAW_HOVER_PRESSED]:
		target_scale = PRESSED_SCALE
		brightness = PRESSED_BRIGHTNESS
		duration = 0.07
	elif draw_mode == BaseButton.DRAW_HOVER:
		target_scale = HOVER_SCALE
		brightness = SELECTED_HOVER_BRIGHTNESS if selected else HOVER_BRIGHTNESS
	if _tweens[index] != null:
		_tweens[index].kill()
		_tweens[index] = null
	var medallion := _medallions[index]
	var target_modulate := Color(brightness, brightness, brightness, 1.0)
	if not animate:
		medallion.scale = Vector2.ONE * target_scale
		medallion.self_modulate = target_modulate
		return
	var tween := create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tweens[index] = tween
	tween.tween_property(medallion, "scale", Vector2.ONE * target_scale, duration)
	tween.tween_property(medallion, "self_modulate", target_modulate, duration)

static func _ring_style(colour: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color.TRANSPARENT
	style.border_color = colour
	style.set_border_width_all(1)
	style.set_corner_radius_all(20)
	style.corner_detail = 12
	return style
