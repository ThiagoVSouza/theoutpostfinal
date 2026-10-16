extends Control
## Loading-only art direction; the diagnostic HUD keeps its own compact theme.
## Layout is in viewport coordinates and recomputed on resize, including narrow windows.

const FONT := preload("res://assets/ui/fonts/Spectral-Regular.ttf")
const LOGO := preload("res://assets/ui/the_outpost_logo.png")
const BACKDROP := preload("res://shaders/loading_backdrop.gdshader")
const INK := Color("342b1c")
const PARCHMENT := Color("ebdab2")
const GOLD := Color("a58b50")
const MUTED := Color("b9ac8b")

var bar: ProgressBar
var stage_label: Label
var percent_label: Label
var heading: Label
var logo: TextureRect
var tip: PanelContainer
var tip_title: Label
var tip_text: Label
var actions: HBoxContainer
var retry_button: Button
var quit_button: Button
var _scale := 1.0
var _bar_rect := Rect2()
var _failed := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var background := ColorRect.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material := ShaderMaterial.new()
	material.shader = BACKDROP
	background.material = material
	add_child(background)
	# The decoration draws above the material but below the text.
	move_child(background, 0)
	background.show_behind_parent = true
	logo = TextureRect.new()
	logo.texture = LOGO
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	logo.modulate = Color("f2dfb3")
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(logo)
	heading = _label("Preparing your outpost", 30, PARCHMENT, true)
	bar = ProgressBar.new()
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_stylebox_override("background", _style(Color("151610"), Color("806d43"), 2))
	var fill := _style(Color("89945a"), Color("b2b77c"), 1)
	fill.expand_margin_left = -3
	fill.expand_margin_right = -3
	fill.expand_margin_top = -3
	fill.expand_margin_bottom = -3
	bar.add_theme_stylebox_override("fill", fill)
	add_child(bar)
	stage_label = _label("Gathering resources", 18, MUTED)
	stage_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	percent_label = _label("0%", 18, PARCHMENT)
	percent_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	# Tabular figures keep the percentage steady as the digits change.
	percent_label.add_theme_font_override("font", _tabular_font())
	tip = PanelContainer.new()
	tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var paper := StyleBoxFlat.new()
	paper.bg_color = Color("cdb98c")
	paper.border_color = Color("887041")
	paper.set_border_width_all(2)
	paper.set_corner_radius_all(2)
	paper.shadow_color = Color(0, 0, 0, 0.24)
	paper.shadow_size = 6
	paper.content_margin_left = 24
	paper.content_margin_right = 24
	paper.content_margin_top = 14
	paper.content_margin_bottom = 14
	tip.add_theme_stylebox_override("panel", paper)
	add_child(tip)
	tip.minimum_size_changed.connect(_fit_tip, CONNECT_DEFERRED)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	tip.add_child(column)
	tip_title = _label("EXPLORING THE WORLD", 13, Color("6b5731"), true, column)
	tip_text = _label("W A S D  to move   ·   Scroll to zoom   ·   Q / E  to rotate", 17, INK, true, column)
	tip_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	actions = HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 16)
	actions.hide()
	add_child(actions)
	retry_button = _button("Try again")
	quit_button = _button("Quit game")
	resized.connect(_layout)
	_layout()

func show_error() -> void:
	_failed = true
	heading.text = "Unable to load your outpost"
	stage_label.add_theme_color_override("font_color", Color("e5b48c"))
	percent_label.hide()
	bar.hide()
	tip.hide()
	actions.show()
	retry_button.grab_focus()
	_layout()

func _layout() -> void:
	if logo == null: return
	_scale = minf(1.0, minf(size.x / 1000.0, size.y / 740.0))
	var s := _scale
	var width := minf(600.0 * s, size.x - 80.0 * s)
	var left := (size.x - width) * 0.5
	var logo_width := minf(720.0 * s, size.x - 96.0 * s)
	var logo_height := logo_width * 291.0 / 1022.0
	var logo_top := size.y * 0.30 - logo_height * 0.35
	logo.position = Vector2((size.x - logo_width) * 0.5, logo_top)
	logo.size = Vector2(logo_width, logo_height)
	var heading_y := logo_top + logo_height + 59.0 * s
	heading.position = Vector2(24, heading_y)
	heading.size = Vector2(size.x - 48, 48.0 * s)
	heading.add_theme_font_size_override("font_size", maxi(20, roundi(30.0 * s)))
	_bar_rect = Rect2(left, heading_y + 77.0 * s, width, 18.0 * s)
	bar.position = _bar_rect.position
	bar.size = _bar_rect.size
	stage_label.position = Vector2(left, _bar_rect.end.y + 12.0 * s)
	stage_label.size = Vector2(width - (0.0 if _failed else 65.0 * s), 70.0 * s)
	stage_label.add_theme_font_size_override("font_size", maxi(14, roundi(18.0 * s)))
	percent_label.position = Vector2(left + width - 64.0 * s, stage_label.position.y)
	percent_label.size = Vector2(64.0 * s, 30.0 * s)
	percent_label.add_theme_font_size_override("font_size", maxi(14, roundi(18.0 * s)))
	tip_title.add_theme_font_size_override("font_size", maxi(11, roundi(13.0 * s)))
	tip_text.add_theme_font_size_override("font_size", maxi(13, roundi(17.0 * s)))
	# Font changes invalidate container minimum sizes on a deferred sort. Fit afterwards so a
	# small window cannot retain the previous, wider text minimum and push the panel off-centre.
	_fit_tip.call_deferred()
	actions.position = Vector2(left, stage_label.position.y + 84.0 * s)
	actions.size = Vector2(width, 44)
	queue_redraw()

func _fit_tip() -> void:
	var width := minf(650.0 * _scale, size.x - 80.0 * _scale)
	tip.size = Vector2(width, 88.0 * _scale)
	tip.position = Vector2((size.x - tip.size.x) * 0.5, size.y - 176.0 * _scale)

func _draw() -> void:
	var s := _scale
	var margin := 32.0 * s
	var frame := Rect2(Vector2.ONE * margin, size - Vector2.ONE * margin * 2.0)
	draw_rect(frame, Color(GOLD, 0.56), false, 1.0)
	draw_rect(frame.grow(-5.0 * s), Color(GOLD, 0.15), false, 1.0)
	for corner in [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)]:
		var origin: Vector2 = frame.position + frame.size * corner
		var direction: Vector2 = Vector2.ONE - corner * 2.0
		_corner(origin, direction, s)
	# Small lozenges break the frame at its midpoints, echoing the arrow in the wordmark.
	for y in [margin, size.y - margin]:
		draw_rect(Rect2(size.x * 0.5 - 24 * s, y - 3, 48 * s, 6), Color("191710"))
		_diamond(Vector2(size.x * 0.5, y), 5.0 * s, Color(GOLD, 0.8))
	if logo == null: return
	var y := logo.position.y + logo.size.y + 30.0 * s
	var centre := Vector2(size.x * 0.5, y)
	for side in [-1.0, 1.0]:
		draw_line(centre + Vector2(side * 16 * s, 0), centre + Vector2(side * 112 * s, 0), Color(GOLD, 0.55), 1, true)
		_diamond(centre + Vector2(side * 121 * s, 0), 2.4 * s, Color(GOLD, 0.6))
	_diamond(centre, 5 * s, GOLD)
	if not _failed:
		for x in [_bar_rect.position.x - 9.0 * s, _bar_rect.end.x + 9.0 * s]:
			_diamond(Vector2(x, _bar_rect.get_center().y), 3.0 * s, GOLD)

func _corner(origin: Vector2, direction: Vector2, s: float) -> void:
	var path := PackedVector2Array()
	for point in [Vector2(0, 54), Vector2(0, 0), Vector2(54, 0), Vector2(54, 9), Vector2(15, 9), Vector2(15, 35), Vector2(35, 35), Vector2(35, 19), Vector2(25, 19), Vector2(25, 25)]:
		path.append(origin + point * direction * s)
	draw_polyline(path, Color(GOLD, 0.83), 1.6 * s, true)
	_diamond(origin + Vector2(8, 8) * direction * s, 3.0 * s, GOLD)

func _diamond(centre: Vector2, radius: float, colour: Color) -> void:
	draw_polyline(PackedVector2Array([centre + Vector2(0, -radius), centre + Vector2(radius, 0), centre + Vector2(0, radius), centre + Vector2(-radius, 0), centre + Vector2(0, -radius)]), colour, 1.0, true)

func _label(text: String, font_size: int, colour: Color, centred := false, parent: Node = self) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", colour)
	if centred: label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(label)
	return label

func _button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(150, 44)
	button.add_theme_font_override("font", FONT)
	button.add_theme_font_size_override("font_size", 18)
	button.add_theme_color_override("font_color", PARCHMENT)
	button.add_theme_color_override("font_hover_color", Color("fff1ce"))
	button.add_theme_stylebox_override("normal", _style(Color("30291d"), GOLD, 1))
	button.add_theme_stylebox_override("hover", _style(Color("463b26"), PARCHMENT, 1))
	button.add_theme_stylebox_override("pressed", _style(Color("1c1a12"), GOLD, 1))
	button.add_theme_stylebox_override("focus", _style(Color.TRANSPARENT, PARCHMENT, 2))
	actions.add_child(button)
	return button

static func _style(colour: Color, border: Color, thickness: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = colour
	style.border_color = border
	style.set_border_width_all(thickness)
	style.set_corner_radius_all(3)
	return style

static func _tabular_font() -> FontVariation:
	var variation := FontVariation.new()
	variation.base_font = FONT
	variation.opentype_features = {"tnum": 1}
	return variation
