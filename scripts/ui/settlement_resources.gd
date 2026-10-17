extends Control
## Read-only resource totals and their signed yearly changes.
## Decorative controls let camera input pass through the entire strip.

const ICON_SHEET := preload("res://assets/ui/resources/stat_icons.png")
const FONT := preload("res://assets/ui/fonts/Spectral-Regular.ttf")
const TOTAL_FONT := preload("res://assets/ui/fonts/Spectral-Bold.ttf")
const RESOURCES: Array[StringName] = [&"gold", &"population", &"score"]
const ICON_REGIONS: Array[Rect2] = [
	Rect2(56, 112, 616, 512), Rect2(740, 112, 692, 512), Rect2(1484, 112, 656, 512),
]
const STRIP_SIZE := Vector2(384, 32)
const MINIMUM_WIDTH := 264.0
const TOTAL_FONT_SIZE := 14
const MINIMUM_TOTAL_FONT_SIZE := 12
const INCREMENT_FONT_SIZE := 10
const HUD_GAP := 8.0
const POSITIVE_COLOUR := Color("c8cfaa")
const ZERO_COLOUR := Color("c9b58d")
const NEGATIVE_COLOUR := Color("d59483")
const NUMBER_SUFFIXES: Array[String] = ["", "K", "M", "B", "T", "Qa", "Qi"]

@export var gold_total: int = 0:
	set(value):
		gold_total = value
		_refresh_resource(0)
@export var gold_yearly_increment: int = 0:
	set(value):
		gold_yearly_increment = value
		_refresh_resource(0)
@export var population_total: int = 0:
	set(value):
		population_total = value
		_refresh_resource(1)
@export var population_yearly_increment: int = 0:
	set(value):
		population_yearly_increment = value
		_refresh_resource(1)
@export var score_total: int = 0:
	set(value):
		score_total = value
		_refresh_resource(2)
@export var score_yearly_increment: int = 0:
	set(value):
		score_yearly_increment = value
		_refresh_resource(2)

var panel: Panel
var cells: Array[Control] = []
var icons: Array[TextureRect] = []
var total_labels: Array[Label] = []
var increment_labels: Array[Label] = []
var _dividers: Array[ColorRect] = []
var _reserved_controls: Array[Control] = []
var _layout_requested := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_panel()
	for index in RESOURCES.size():
		_build_cell(index)
		_refresh_resource(index)
	_watch_neighbouring_hud()
	get_viewport().size_changed.connect(_queue_layout)
	_layout()

## A small integration point for the future economy, population, and score systems.
func set_resource(resource: StringName, total: int, yearly_increment: int) -> void:
	match resource:
		&"gold":
			gold_total = total
			gold_yearly_increment = yearly_increment
		&"population":
			population_total = total
			population_yearly_increment = yearly_increment
		&"score":
			score_total = total
			score_yearly_increment = yearly_increment
		_:
			push_warning("Unknown settlement resource: " + str(resource))

func _build_panel() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("30281d")
	style.border_color = Color("9b8151")
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.corner_detail = 4
	style.shadow_color = Color(0.025, 0.018, 0.01, 0.4)
	style.shadow_size = 3
	style.shadow_offset = Vector2(1, 1)
	panel = Panel.new()
	panel.name = "Background"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

func _build_cell(index: int) -> void:
	var cell := Control.new()
	cell.name = str(RESOURCES[index]).capitalize()
	cell.set_meta(&"resource", RESOURCES[index])
	cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cell)
	cells.append(cell)

	var atlas := AtlasTexture.new()
	atlas.atlas = ICON_SHEET
	atlas.region = ICON_REGIONS[index]
	atlas.filter_clip = true
	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.texture = atlas
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(icon)
	icons.append(icon)
	total_labels.append(_label(cell, "Total", TOTAL_FONT, Color("efd8af")))
	increment_labels.append(_label(cell, "YearlyIncrement", FONT, ZERO_COLOUR))

	if index > 0:
		var divider := ColorRect.new()
		divider.name = "Divider" + str(index)
		divider.color = Color(0.61, 0.51, 0.32, 0.35)
		divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(divider)
		_dividers.append(divider)

func _label(parent: Control, node_name: String, font: Font, colour: Color) -> Label:
	var label := Label.new()
	label.name = node_name
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.clip_text = true
	# Trim Spectral's extra line margins around digits without shrinking the glyphs.
	var compact_font := FontVariation.new()
	compact_font.base_font = font
	compact_font.spacing_top = -2
	compact_font.spacing_bottom = -3
	label.add_theme_font_override("font", compact_font)
	label.add_theme_color_override("font_color", colour)
	label.add_theme_color_override("font_shadow_color", Color(0.04, 0.04, 0.02, 0.85))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	parent.add_child(label)
	return label

func _refresh_resource(index: int) -> void:
	if index >= total_labels.size(): return
	var totals: Array[int] = [gold_total, population_total, score_total]
	var increments: Array[int] = [gold_yearly_increment, population_yearly_increment, score_yearly_increment]
	var total_label := total_labels[index]
	var full_total := _group_digits(totals[index])
	var preferred_font_size := roundi(TOTAL_FONT_SIZE * clampf(size.x / STRIP_SIZE.x, 0.9, 1.0))
	var font_size := preferred_font_size
	while font_size > MINIMUM_TOTAL_FONT_SIZE and TOTAL_FONT.get_string_size(full_total, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > total_label.size.x:
		font_size -= 1
	var display_total := _display_number(totals[index], TOTAL_FONT, font_size, total_label.size.x)
	if display_total != full_total:
		# Once abbreviated, restore the larger total size wherever it fits.
		font_size = preferred_font_size
		display_total = _display_number(totals[index], TOTAL_FONT, font_size, total_label.size.x)
		while font_size > MINIMUM_TOTAL_FONT_SIZE and TOTAL_FONT.get_string_size(display_total, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > total_label.size.x:
			font_size -= 1
			display_total = _display_number(totals[index], TOTAL_FONT, font_size, total_label.size.x)
	total_label.add_theme_font_size_override("font_size", font_size)
	total_label.text = display_total
	var increment := increments[index]
	increment_labels[index].text = _display_number(increment, FONT, INCREMENT_FONT_SIZE, increment_labels[index].size.x, true)
	var colour := POSITIVE_COLOUR if increment > 0 else ZERO_COLOUR
	if increment < 0: colour = NEGATIVE_COLOUR
	increment_labels[index].add_theme_color_override("font_color", colour)

static func _group_digits(value: int) -> String:
	# Work on the signed string so the minimum 64-bit integer is safe too.
	var digits := str(value).trim_prefix("-")
	var grouped := ""
	for index in digits.length():
		if index > 0 and (digits.length() - index) % 3 == 0:
			grouped += ","
		grouped += digits[index]
	return ("-" if value < 0 else "") + grouped

static func _display_number(value: int, font: Font, font_size: int, width: float, signed := false) -> String:
	var full_text := ("+" if signed and value >= 0 else "") + _group_digits(value)
	if font.get_string_size(full_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= width:
		return full_text
	# Compact only when needed; the exported integer always retains the exact value.
	var sign_text := "-" if value < 0 else ("+" if signed else "")
	var scaled := absf(float(value))
	var unit := 0
	while scaled >= 1000.0 and unit < NUMBER_SUFFIXES.size() - 1:
		scaled /= 1000.0
		unit += 1
	var compact := full_text
	for precision in [1, 0]:
		var rounded := snappedf(scaled, 0.1 if precision == 1 else 1.0)
		var suffix_index := unit
		if rounded >= 1000.0 and suffix_index < NUMBER_SUFFIXES.size() - 1:
			rounded /= 1000.0
			suffix_index += 1
		var amount := ("%.1f" % rounded).trim_suffix(".0") if precision == 1 else "%.0f" % rounded
		compact = sign_text + amount + NUMBER_SUFFIXES[suffix_index]
		if font.get_string_size(compact, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= width:
			return compact
	return compact

func _watch_neighbouring_hud() -> void:
	for path in ["../SettlementHeader", "../SettlementMenu/Background"]:
		var control := get_node_or_null(path) as Control
		if control != null: _reserved_controls.append(control)
	var stats := get_node_or_null("../../StatsOverlay")
	if stats != null:
		for child in stats.get_children():
			if child is Control: _reserved_controls.append(child)
	for control in _reserved_controls:
		control.item_rect_changed.connect(_queue_layout)
		control.visibility_changed.connect(_queue_layout)

func _queue_layout() -> void:
	if _layout_requested: return
	_layout_requested = true
	_layout.call_deferred()

func _layout() -> void:
	_layout_requested = false
	var viewport_size := get_viewport_rect().size
	var reserved: Array[Rect2] = []
	for control in _reserved_controls:
		if is_instance_valid(control) and control.is_visible_in_tree():
			reserved.append(control.get_global_rect().grow(HUD_GAP))
	var preferred_size := STRIP_SIZE
	var target := Rect2(Vector2((viewport_size.x - preferred_size.x) * 0.5, 3), preferred_size)
	var needs_fallback := target.position.x < HUD_GAP
	for rect in reserved:
		if target.intersects(rect): needs_fallback = true
	if needs_fallback:
		target = _find_free_band(viewport_size, reserved, preferred_size)
	position = target.position
	size = target.size
	panel.position = Vector2.ZERO
	panel.size = size
	var cell_width := size.x / RESOURCES.size()
	var factor := clampf(size.x / STRIP_SIZE.x, 0.8, 1.0)
	var icon_size := roundf(32.0 * factor)
	var padding := roundf(12.0 * factor)
	for index in cells.size():
		cells[index].position = Vector2(cell_width * index, 0)
		cells[index].size = Vector2(cell_width, size.y)
		icons[index].position = Vector2(padding, (size.y - icon_size) * 0.5)
		icons[index].size = Vector2.ONE * icon_size
		var text_x := padding + icon_size + roundf(8.0 * factor)
		var text_width := maxf(1.0, cell_width - text_x - padding)
		total_labels[index].position = Vector2(text_x, 4)
		total_labels[index].size = Vector2(text_width, 17)
		increment_labels[index].position = Vector2(text_x, 18)
		increment_labels[index].add_theme_font_size_override("font_size", INCREMENT_FONT_SIZE)
		increment_labels[index].size = Vector2(text_width, 11)
		_refresh_resource(index)
	for index in _dividers.size():
		_dividers[index].position = Vector2(roundf(cell_width * (index + 1)), 5)
		_dividers[index].size = Vector2(1, size.y - 10)

func _find_free_band(viewport_size: Vector2, reserved: Array[Rect2], preferred_size: Vector2) -> Rect2:
	# Keep the usual top-centre placement whenever it fits. Narrow windows use the
	# first free band below nearby HUD controls, including the changing stats panel.
	var bands: Array[float] = [3.0]
	for rect in reserved:
		bands.append(rect.end.y)
	bands.sort()
	var available_width := maxf(1.0, viewport_size.x - HUD_GAP * 2.0)
	var minimum_width := minf(MINIMUM_WIDTH, minf(preferred_size.x, available_width))
	for top in bands:
		if top + preferred_size.y > viewport_size.y: continue
		var intervals: Array[Vector2] = [Vector2(HUD_GAP, viewport_size.x - HUD_GAP)]
		for rect in reserved:
			if rect.end.y <= top or rect.position.y >= top + preferred_size.y: continue
			var remaining: Array[Vector2] = []
			for interval in intervals:
				if rect.end.x <= interval.x or rect.position.x >= interval.y:
					remaining.append(interval)
				else:
					if rect.position.x > interval.x: remaining.append(Vector2(interval.x, rect.position.x))
					if rect.end.x < interval.y: remaining.append(Vector2(rect.end.x, interval.y))
			intervals = remaining
		var best := Rect2()
		var best_distance := INF
		for interval in intervals:
			if interval.y - interval.x < minimum_width: continue
			var width := minf(preferred_size.x, interval.y - interval.x)
			var left := clampf((viewport_size.x - width) * 0.5, interval.x, interval.y - width)
			var distance := absf(left + width * 0.5 - viewport_size.x * 0.5)
			if distance < best_distance:
				best = Rect2(left, top, width, preferred_size.y)
				best_distance = distance
		if best_distance < INF: return best
	# Extremely small viewports may have no clear band; retain an in-bounds strip.
	var width := minf(preferred_size.x, available_width)
	return Rect2((viewport_size.x - width) * 0.5, maxf(0.0, viewport_size.y - preferred_size.y), width, preferred_size.y)
