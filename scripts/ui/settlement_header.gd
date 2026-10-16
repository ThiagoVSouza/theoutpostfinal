extends Control
## Settlement identity, anchored to the top-left of the gameplay viewport.
## Source textures stay untouched; atlas regions omit their transparent canvas padding.
## Decorative controls ignore input so the camera still works beneath the header.

signal flag_pressed

const BANNER := preload("res://assets/ui/settlement/banner.png")
const SHIELD := preload("res://assets/ui/settlement/shield.png")
const FONT := preload("res://assets/ui/fonts/Spectral-Regular.ttf")
const TITLE_FONT := preload("res://assets/ui/fonts/Spectral-Bold.ttf")
const BANNER_TINT := preload("res://shaders/banner_tint.gdshader")
const SHIELD_TINT := preload("res://shaders/shield_tint.gdshader")
const FLAG_HOVER_SCALE := 1.08
const FLAG_PRESSED_SCALE := 0.94
const FLAG_HOVER_BRIGHTNESS := 1.12
const FLAG_PRESSED_BRIGHTNESS := 0.82

@export var settlement_name := "Black Raven":
	set(value):
		settlement_name = value
		if is_instance_valid(name_label): name_label.text = value

@export var settlement_rank := "Outpost":
	set(value):
		settlement_rank = value
		if is_instance_valid(rank_label): rank_label.text = value

var banner: TextureRect
var shield: TextureRect
var flag_button: Button
var name_label: Label
var rank_label: Label
var _flag_tween: Tween

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner = _texture("Banner", BANNER, Rect2(51, 219, 2004, 305))
	var banner_tint := ShaderMaterial.new()
	banner_tint.shader = BANNER_TINT
	banner.material = banner_tint
	flag_button = Button.new()
	flag_button.name = "FlagButton"
	flag_button.flat = true
	flag_button.focus_mode = Control.FOCUS_ALL
	flag_button.mouse_filter = Control.MOUSE_FILTER_STOP
	flag_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	flag_button.button_mask = MOUSE_BUTTON_MASK_LEFT
	flag_button.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
	# Empty regular styles leave only the artwork visible. Keep a quiet keyboard focus cue.
	for state in ["normal", "hover", "pressed", "disabled", "hover_pressed"]:
		flag_button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	var focus_style := StyleBoxFlat.new()
	focus_style.bg_color = Color.TRANSPARENT
	focus_style.border_color = Color("c9b58d")
	focus_style.set_border_width_all(1)
	flag_button.add_theme_stylebox_override("focus", focus_style)
	add_child(flag_button)
	shield = _texture("Shield", SHIELD, Rect2(447, 91, 609, 840))
	shield.reparent(flag_button)
	var tint := ShaderMaterial.new()
	tint.shader = SHIELD_TINT
	shield.material = tint
	name_label = _label("SettlementName", settlement_name, TITLE_FONT, Color("efd8af"))
	rank_label = _label("SettlementRank", settlement_rank, FONT, Color("c9b58d"))
	# Defer until BaseButton has settled its native hover/pressed state for this event.
	flag_button.mouse_entered.connect(_update_flag_feedback, CONNECT_DEFERRED)
	flag_button.mouse_exited.connect(_update_flag_feedback, CONNECT_DEFERRED)
	flag_button.button_down.connect(_update_flag_feedback, CONNECT_DEFERRED)
	flag_button.button_up.connect(_update_flag_feedback, CONNECT_DEFERRED)
	flag_button.pressed.connect(func() -> void: flag_pressed.emit())
	get_viewport().size_changed.connect(_layout)
	_layout()

func _layout() -> void:
	var factor := clampf(get_viewport_rect().size.x / 800.0, 0.65, 1.0)
	size = Vector2(300, 82) * factor
	# The supplied strip fades at both ends. Start its faded left end offscreen, so actual
	# fabric and both gold rules reach x=0 behind the shield instead of leaving an empty gap.
	banner.position = Vector2(-74, 3) * factor
	banner.size = Vector2(374, 374.0 * 305.0 / 2004.0) * factor
	# Keep the hit area still while the artwork grows down from its top centre.
	flag_button.position = Vector2(6, 0) * factor
	flag_button.size = Vector2(56, 56.0 * 840.0 / 609.0) * factor
	shield.position = Vector2.ZERO
	shield.size = flag_button.size
	shield.pivot_offset = Vector2(shield.size.x * 0.5, 0.0)
	name_label.position = Vector2(78, 3) * factor
	name_label.size = Vector2(174, 30) * factor
	name_label.add_theme_font_size_override("font_size", roundi(20 * factor))
	rank_label.position = Vector2(78, 29) * factor
	rank_label.size = Vector2(174, 24) * factor
	rank_label.add_theme_font_size_override("font_size", roundi(15 * factor))

func _update_flag_feedback() -> void:
	var target_scale := 1.0
	var brightness := 1.0
	var duration := 0.12
	var draw_mode := flag_button.get_draw_mode()
	if draw_mode in [BaseButton.DRAW_PRESSED, BaseButton.DRAW_HOVER_PRESSED]:
		target_scale = FLAG_PRESSED_SCALE
		brightness = FLAG_PRESSED_BRIGHTNESS
		duration = 0.07
	elif draw_mode == BaseButton.DRAW_HOVER:
		target_scale = FLAG_HOVER_SCALE
		brightness = FLAG_HOVER_BRIGHTNESS
	if _flag_tween != null:
		_flag_tween.kill()
	_flag_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_flag_tween.tween_property(shield, "scale", Vector2.ONE * target_scale, duration)
	_flag_tween.tween_property(shield, "self_modulate", Color(brightness, brightness, brightness, 1.0), duration)

func _texture(node_name: String, source: Texture2D, region: Rect2) -> TextureRect:
	var atlas := AtlasTexture.new()
	atlas.atlas = source
	atlas.region = region
	atlas.filter_clip = true
	var texture := TextureRect.new()
	texture.name = node_name
	texture.texture = atlas
	texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture.stretch_mode = TextureRect.STRETCH_SCALE
	texture.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(texture)
	return texture

func _label(node_name: String, text: String, font: Font, colour: Color) -> Label:
	var label := Label.new()
	label.name = node_name
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.add_theme_font_override("font", font)
	label.add_theme_color_override("font_color", colour)
	label.add_theme_color_override("font_shadow_color", Color(0.04, 0.04, 0.02, 0.85))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(label)
	return label
