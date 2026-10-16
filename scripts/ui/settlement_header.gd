extends Control
## Settlement identity, anchored to the top-left of the gameplay viewport.
## Source textures stay untouched; atlas regions omit their transparent canvas padding.
## Decorative controls ignore input so the camera still works beneath the header.

const BANNER := preload("res://assets/ui/settlement/banner.png")
const SHIELD := preload("res://assets/ui/settlement/shield.png")
const FONT := preload("res://assets/ui/fonts/Spectral-Regular.ttf")
const TITLE_FONT := preload("res://assets/ui/fonts/Spectral-Bold.ttf")
const BANNER_TINT := preload("res://shaders/banner_tint.gdshader")
const SHIELD_TINT := preload("res://shaders/shield_tint.gdshader")

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
var name_label: Label
var rank_label: Label

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner = _texture("Banner", BANNER, Rect2(51, 219, 2004, 305))
	var banner_tint := ShaderMaterial.new()
	banner_tint.shader = BANNER_TINT
	banner.material = banner_tint
	shield = _texture("Shield", SHIELD, Rect2(447, 91, 609, 840))
	var tint := ShaderMaterial.new()
	tint.shader = SHIELD_TINT
	shield.material = tint
	name_label = _label("SettlementName", settlement_name, TITLE_FONT, Color("efd8af"))
	rank_label = _label("SettlementRank", settlement_rank, FONT, Color("c9b58d"))
	get_viewport().size_changed.connect(_layout)
	_layout()

func _layout() -> void:
	var factor := clampf(get_viewport_rect().size.x / 800.0, 0.65, 1.0)
	size = Vector2(300, 82) * factor
	# The supplied strip fades at both ends. Start its faded left end offscreen, so actual
	# fabric and both gold rules reach x=0 behind the shield instead of leaving an empty gap.
	banner.position = Vector2(-74, 3) * factor
	banner.size = Vector2(374, 374.0 * 305.0 / 2004.0) * factor
	shield.position = Vector2(6, 0) * factor
	shield.size = Vector2(56, 56.0 * 840.0 / 609.0) * factor
	name_label.position = Vector2(78, 3) * factor
	name_label.size = Vector2(174, 30) * factor
	name_label.add_theme_font_size_override("font_size", roundi(20 * factor))
	rank_label.position = Vector2(78, 29) * factor
	rank_label.size = Vector2(174, 24) * factor
	rank_label.add_theme_font_size_override("font_size", roundi(15 * factor))

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
