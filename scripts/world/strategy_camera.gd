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
## world-space positions small at close zoom, where float precision would show as jitter, and keeps
## the depth range tight: the sun's shadow map is stretched over that whole range (see main.gd), so
## every metre of empty air in front of the ground is shadow resolution thrown away.

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

var focus := Vector3.ZERO
var zoom := HOME_ZOOM
var yaw := HOME_YAW
var pitch := HOME_PITCH

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

## Where a screen point's ray meets the board plane.
func _ground_at(screen: Vector2) -> Vector3:
	var origin := project_ray_origin(screen)
	var direction := project_ray_normal(screen)
	if absf(direction.y) < 0.000001: return focus
	return origin + direction * (-origin.y / direction.y)

func _right() -> Vector3:
	return Vector3(cos(yaw), 0.0, -sin(yaw))

## Towards the camera along the ground, so W (negative) moves the view away from it.
func _forward() -> Vector3:
	return Vector3(sin(yaw), 0.0, cos(yaw))

func _apply() -> void:
	focus.x = clampf(focus.x, -PAN_LIMIT, PAN_LIMIT)
	focus.z = clampf(focus.z, -PAN_LIMIT, PAN_LIMIT)
	focus.y = 0.0
	# The near plane's lower edge sits zoom / 2 * cos(pitch) below the camera, which is
	# distance * sin(pitch) up; that edge has to stay above the frame's top, with some room.
	var clearance := WorldSpec.FRAME_HEIGHT * 1.25
	var distance := (clearance + zoom * 0.5 * cos(pitch)) / sin(pitch)
	position = focus + Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * distance
	size = zoom
	look_at(focus)
	# Deep enough for the ground at the top edge of the screen, zoom / 2 / tan(pitch) past the
	# focus, and for the frame's outer wall reaching below the board there.
	near = 1.0
	far = distance + zoom * 0.5 / tan(pitch) + WorldSpec.FRAME_DEPTH / sin(pitch) + 10.0
