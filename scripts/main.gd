extends Node3D
## The game scene: the board under a strategy camera. G toggles the grid.
##
## Runs after its children each frame (process_priority), so the level of detail is decided from
## the zoom the camera has just settled on rather than the previous frame's.

@onready var board: Board = $Board
@onready var camera: StrategyCamera = $Camera
@onready var stats: StatsOverlay = $StatsOverlay

var lod := ViewLod.new()

func _ready() -> void:
	process_priority = 1
	stats.extra_rows = _view_rows
	lod.update(camera, 0.0)
	board.apply_view(lod)

func _process(delta: float) -> void:
	lod.update(camera, delta)
	board.apply_view(lod)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_G:
		board.grid_visible = not board.grid_visible

## The level of detail and the view's height, for the stats panel.
func _view_rows() -> Array:
	return [
		["LOD", "%d %s" % [lod.tier, ViewLod.NAMES[lod.tier]]],
		["Height", "%s m" % _grouped(roundi(ViewLod.height_metres(camera.zoom)))],
	]

static func _grouped(value: int) -> String:
	var digits := str(absi(value))
	var out := ""
	while digits.length() > 3:
		out = "," + digits.right(3) + out
		digits = digits.left(digits.length() - 3)
	return ("-" if value < 0 else "") + digits + out
