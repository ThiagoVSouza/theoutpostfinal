extends Node3D
## The game scene: the board under a strategy camera. G toggles the grid.

@onready var board: Board = $Board

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_G:
		board.grid_visible = not board.grid_visible
