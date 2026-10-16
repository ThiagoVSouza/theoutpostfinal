extends Node3D
## The game scene: the board under a strategy camera. G toggles the grid, T steps the benchmark
## forest through none, 1,000, 10,000 and 50,000 trees, and L switches the sun's shadows.
##
## Runs after its children each frame (process_priority), so the level of detail is decided from
## the zoom the camera has just settled on rather than the previous frame's.
##
## The sun's shadow map is one orthogonal split stretched over the camera's depth range, so it
## covers exactly what is on screen. Godot's directional shadows reach from the camera out to
## directional_shadow_max_distance, and the camera's depth range changes with its zoom, so the
## distance follows camera.far every frame. A shadow texel is then roughly the larger of the view's
## width and its depth, over the shadow map's 4096 texels.

@onready var board: Board = $Board
@onready var camera: StrategyCamera = $Camera
@onready var forest: Forest = $Forest
@onready var sun: DirectionalLight3D = $Sun
@onready var stats: StatsOverlay = $StatsOverlay

var lod := ViewLod.new()

func _ready() -> void:
	process_priority = 1
	stats.extra_rows = _view_rows
	_update_view(0.0)

func _process(delta: float) -> void:
	_update_view(delta)

func _update_view(delta: float) -> void:
	lod.update(camera, delta)
	board.apply_view(lod)
	# Tree meshes at the Detail level only; from Distant out the forest is painted into the grass.
	var meshes := lod.tier == ViewLod.Tier.DETAIL
	forest.visible = meshes
	board.set_forest_painted(not meshes)
	if not is_equal_approx(sun.directional_shadow_max_distance, camera.far):
		sun.directional_shadow_max_distance = camera.far

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo): return
	match event.physical_keycode:
		KEY_G:
			board.grid_visible = not board.grid_visible
		KEY_T:
			forest.cycle()
			board.set_forest_map(forest.paint_texture, forest.paint_origin, forest.paint_size)
		KEY_L:
			sun.shadow_enabled = not sun.shadow_enabled

## The level of detail, the view's height and what the forest is drawing, for the stats panel.
func _view_rows() -> Array:
	var rid := get_viewport().get_viewport_rid()
	var draws := RenderingServer.viewport_get_render_info(rid,
		RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
	var primitives := RenderingServer.viewport_get_render_info(rid,
		RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME)
	var trees := "off"
	if forest.count > 0:
		trees = _grouped(forest.placed) + ("" if forest.visible else " painted")
	return [
		["LOD", "%d %s" % [lod.tier, ViewLod.NAMES[lod.tier]]],
		["Height", "%s m" % _grouped(roundi(ViewLod.height_metres(camera.zoom)))],
		["Trees", trees],
		["Shadows", "on" if sun.shadow_enabled else "off"],
		["Draws", _grouped(draws)],
		["Triangles", _grouped(primitives)],
	]

static func _grouped(value: int) -> String:
	var digits := str(absi(value))
	var out := ""
	while digits.length() > 3:
		out = "," + digits.right(3) + out
		digits = digits.left(digits.length() - 3)
	return ("-" if value < 0 else "") + digits + out
