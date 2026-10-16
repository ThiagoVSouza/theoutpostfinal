class_name UITheme
extends RefCounted
## Shared palette and control styling for the loading screen and in-game overlays.

const BACKGROUND := Color("0e1c20")
const TITLE := Color("e4decb")
const MUTED := Color("93a6a0")
const BRIGHT := Color("d4d7c7")
const HIGHLIGHT := Color("fff1cf")
const BORDER := Color("3c4c4b")
const BORDER_ACTIVE := Color("9b946e")
const PANEL := Color(0.06, 0.095, 0.10, 0.94)
const TRACK := Color("1b3035")
const TRACK_BORDER := Color("2c4240")
const FILL := Color("8ba86b")
const WARNING := Color("d98b6a")

## The game logo, white on transparent, tinted to the title colour. Height is in pixels; the
## width follows the image's 3:1 aspect. It is 2172 px wide, so it is always drawn scaled down
## and needs mipmaps to stay clean; the .import file generates them.
const LOGO := preload("res://assets/ui/theoutpost_logo_white_transparent.png")
const LOGO_ASPECT := 2172.0 / 724.0

static func logo(height: float) -> TextureRect:
	var node := TextureRect.new()
	node.texture = LOGO
	node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	node.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	node.custom_minimum_size = Vector2(height * LOGO_ASPECT, height)
	node.modulate = TITLE
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node

static func label(text: String, size: int, color: Color, centred := false) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_size_override("font_size", size)
	node.add_theme_color_override("font_color", color)
	if centred: node.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return node

static func bar_style(color: Color, border := Color.TRANSPARENT) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(3)
	if border != Color.TRANSPARENT:
		style.border_color = border
		style.set_border_width_all(1)
	return style

static func panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL
	style.border_color = BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style
