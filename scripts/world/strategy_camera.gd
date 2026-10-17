class_name StrategyCamera
extends Camera3D
## Orthographic strategy camera over the board, with the controls TheOutpostMap2 uses.
##
## WASD or the arrows pan, right-drag drags the board under the cursor, the wheel zooms towards
## the cursor, middle-drag or Q / E rotate, and R returns to the whole-board view.
##
## Zoom is the orthographic size: metres of board covered by the screen's height. The camera sits
## a distance from its focus that grows with the zoom, just far enough that the near plane's lower
## edge stays above the tallest thing on the board, the frame. Keeping it no farther than that keeps
## world-space positions small at close zoom, where float precision would show as jitter.
##
## The sun's shadow map is stretched over the depth from the near plane to shadow_reach (see
## main.gd), so every metre of empty air in front of the ground is shadow resolution thrown away. At
## 40 m of view the camera stands about 340 m from the ground to clear the frame, yet the frame is
## only on screen near the board's edge. So the near plane is pushed forward to just above
## TALLEST_PIECE, and drawn back to clear the frame only while the frame could be in view, and
## shadow_reach stops at the farthest ground on screen rather than at far, which also has to hold
## the frame's outer wall below the board. At the closest zoom that cuts the shadowed depth from
## about 760 m to about 120 m, for shadows six times finer.

## About 40 m of view, the closest TheOutpostMap2's settlement view goes.
const MIN_ZOOM := 40.0
## The whole board and its frame fill the screen's height at HOME_ZOOM: 102 km of board and frame,
## foreshortened by sin(pitch) to about 78 km, plus a margin.
const MAX_ZOOM := 110000.0
const HOME_ZOOM := 88000.0
const HOME_PITCH := deg_to_rad(50.0)
const HOME_YAW := 0.0
## Radians of yaw per pixel of middle-drag, and per second of Q / E.
const ROTATE_SPEED := 0.006
const KEY_ROTATE_SPEED := 0.5
## Fraction of the view panned per second with the keys.
const KEY_PAN_SPEED := 0.32
const WHEEL_STEP := 1.12
## The focus stays on the board.
const PAN_LIMIT := WorldSpec.HALF_BOARD
## How far the near plane's lower edge stays above the board at the camera's own position.
const CLEARANCE := WorldSpec.FRAME_HEIGHT * 1.25
## Metres above the board that the near plane leaves room for away from the frame: trees reach
## about 11.5 m, and this leaves headroom for buildings.
const TALLEST_PIECE := 60.0

var focus := Vector3.ZERO
var zoom := HOME_ZOOM
var yaw := HOME_YAW
var pitch := HOME_PITCH
## Depth from the camera to the farthest ground on screen, which the sun's shadows reach to.
var shadow_reach := 0.0

func _ready() -> void:
	projection = PROJECTION_ORTHOGONAL
	current = true
	_apply()

func _process(delta: float) -> void:
	var direction := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP): direction.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN): direction.y += 1.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT): direction.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT): direction.x += 1.0
	if Input.is_physical_key_pressed(KEY_Q): yaw -= delta * KEY_ROTATE_SPEED
	if Input.is_physical_key_pressed(KEY_E): yaw += delta * KEY_ROTATE_SPEED
	if direction != Vector2.ZERO:
		focus += (_right() * direction.x + _forward() * direction.y) * delta * zoom * KEY_PAN_SPEED
	_apply()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP: _zoom_at(event.position, zoom / WHEEL_STEP)
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN: _zoom_at(event.position, zoom * WHEEL_STEP)
	elif event is InputEventMouseMotion:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			# Drag the board rather than the camera: the ground follows the cursor. The tilt
			# foreshortens ground motion vertically by sin(pitch), so that is undone.
			var metres_per_pixel := zoom / get_viewport().get_visible_rect().size.y
			focus -= (_right() * event.relative.x + _forward() * event.relative.y / sin(pitch)) * metres_per_pixel
		elif Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
			yaw += event.relative.x * ROTATE_SPEED
	elif event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_R:
		focus = Vector3.ZERO
		zoom = HOME_ZOOM
		yaw = HOME_YAW
		pitch = HOME_PITCH

## Zooms keeping the board point under the cursor where it is.
func _zoom_at(screen: Vector2, size_to: float) -> void:
	var before := _ground_at(screen)
	zoom = clampf(size_to, MIN_ZOOM, MAX_ZOOM)
	_apply()
	focus += before - _ground_at(screen)
	_apply()

## The camera's distance from its focus at a zoom, which keeps the near plane's lower edge
## CLEARANCE above the board: that edge sits zoom / 2 * cos(pitch) below the camera, which is
## distance * sin(pitch) up.
static func distance_for(zoom_size: float, view_pitch: float) -> float:
	return (CLEARANCE + zoom_size * 0.5 * cos(view_pitch)) / sin(view_pitch)

## The nearest the near plane can be while still showing everything up to tallest metres above
## the board. The view's lower edge at depth t is CLEARANCE - t * sin(pitch) above the board, and
## anything below it is past the near plane anyway.
static func near_for(view_pitch: float, tallest: float) -> float:
	return maxf(1.0, (CLEARANCE - tallest) / sin(view_pitch))

## The depth of the ground at the top edge of the screen, zoom / 2 / tan(pitch) past the focus,
## with a little room.
static func shadow_reach_for(zoom_size: float, view_pitch: float) -> float:
	return distance_for(zoom_size, view_pitch) + zoom_size * 0.5 / tan(view_pitch) + 10.0

## Where a screen point's ray meets the board plane.
func _ground_at(screen: Vector2) -> Vector3:
	return _plane_at(screen, 0.0)

## Where a screen point's ray meets the horizontal plane height metres above the board.
func _plane_at(screen: Vector2, height: float) -> Vector3:
	var origin := project_ray_origin(screen)
	var direction := project_ray_normal(screen)
	if absf(direction.y) < 0.000001: return focus
	return origin + direction * ((height - origin.y) / direction.y)

## Whether the frame could be on screen: whether any screen corner, on the board or at the frame's
## top, lands beyond the board's edge. The view between those two planes lies inside the hull of
## those eight points, so if all are on the board the frame is not in view.
func _frame_in_view() -> bool:
	var screen := get_viewport().get_visible_rect().size
	for corner: Vector2 in [Vector2.ZERO, Vector2(screen.x, 0.0), Vector2(0.0, screen.y), screen]:
		for height: float in [0.0, WorldSpec.FRAME_HEIGHT]:
			var at := _plane_at(corner, height)
			if maxf(absf(at.x), absf(at.z)) > WorldSpec.HALF_BOARD: return true
	return false

func _right() -> Vector3:
	return Vector3(cos(yaw), 0.0, -sin(yaw))

## Towards the camera along the ground, so W (negative) moves the view away from it.
func _forward() -> Vector3:
	return Vector3(sin(yaw), 0.0, cos(yaw))

func _apply() -> void:
	focus.x = clampf(focus.x, -PAN_LIMIT, PAN_LIMIT)
	focus.z = clampf(focus.z, -PAN_LIMIT, PAN_LIMIT)
	focus.y = 0.0
	var distance := distance_for(zoom, pitch)
	position = focus + Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * distance
	size = zoom
	look_at(focus)
	# Deep enough for the ground at the top edge of the screen, zoom / 2 / tan(pitch) past the
	# focus, and for the frame's outer wall reaching below the board there.
	far = distance + zoom * 0.5 / tan(pitch) + WorldSpec.FRAME_DEPTH / sin(pitch) + 10.0
	near = near_for(pitch, WorldSpec.FRAME_HEIGHT if _frame_in_view() else TALLEST_PIECE)
	shadow_reach = shadow_reach_for(zoom, pitch)
