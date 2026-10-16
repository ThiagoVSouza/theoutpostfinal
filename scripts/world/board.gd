class_name Board
extends Node3D
## The 100 km board and the wood frame around it, built from WorldSpec.
##
## The surface is a single quad: everything on it, the ocean, the land and the grid included, is
## drawn by its shader from the world position, so the board costs the same at any size. The frame is four boxes
## sharing one material whose shader works out the mitred corners itself.
##
## The shaders and the sheen texture are set in the scene rather than preloaded here. This script
## is read on the loading screen's loader thread, and in Godot 4.7.1 a preload inside a script read
## there leaves one loader object per preloaded file behind, reported as leaked instances at exit.
## Resources the scene file references load as ordinary dependencies of the scene and do not.

@export var board_shader: Shader
@export var frame_shader: Shader
@export var sheen_map: Texture2D
@export var grass_map: Texture2D
@export var grass_macro_map: Texture2D

## The test land mass of grassland at the centre of the board: a circle of TEST_LAND_RADIUS metres
## whose edge is pushed in and out by sine waves of 2, 3, 4, 5, 7 and 11 bumps around it, with these
## amplitudes (fractions of the radius) and phases. About 2.2 km to 5 km across.
const TEST_LAND_CENTRE := Vector2.ZERO
const TEST_LAND_RADIUS := 1800.0
const TEST_LAND_AMPLITUDE: Array[float] = [0.12, 0.10, 0.07, 0.05, 0.035, 0.02]
const TEST_LAND_PHASE: Array[float] = [0.4, 2.1, 4.7, 1.3, 3.6, 5.5]
## Must match LAND_LOBES in board.gdshader.
const TEST_LAND_LOBES: Array[float] = [2.0, 3.0, 4.0, 5.0, 7.0, 11.0]

## How far inside the test land mass p is, in metres: positive on land. The same sum as
## land_inland() in board.gdshader, which draws the coast; the two must be kept in step, or trees
## will stand in the sea or stop short of the shore.
static func test_land_inland(p: Vector2) -> float:
	var offset := p - TEST_LAND_CENTRE
	var angle := atan2(offset.y, offset.x)
	var edge := 1.0
	for i in TEST_LAND_LOBES.size():
		edge += TEST_LAND_AMPLITUDE[i] * sin(TEST_LAND_LOBES[i] * angle + TEST_LAND_PHASE[i])
	return edge * TEST_LAND_RADIUS - offset.length()

var grid_visible := true:
	set(value):
		grid_visible = value
		if surface_material != null: surface_material.set_shader_parameter("grid_enabled", value)

var surface_material: ShaderMaterial
## The fades last written to the surface, so a settled view stops writing them every frame.
var _pushed := Vector2(-1.0, -1.0)
var _has_forest := false
var _forest_painted := false

func _ready() -> void:
	_build_surface()
	_build_frame()

## Paints a forest's canopy map into the grass, or with no texture stops painting one. Whether it
## shows is set separately, by the level of detail.
func set_forest_map(texture: Texture2D, origin: Vector2, size: float) -> void:
	surface_material.set_shader_parameter("forest_map", texture)
	surface_material.set_shader_parameter("forest_origin", origin)
	surface_material.set_shader_parameter("forest_size", size)
	_has_forest = texture != null
	_push_forest()

## The forest is painted from the Overview level out, where the tree meshes are hidden.
func set_forest_painted(painted: bool) -> void:
	if painted == _forest_painted: return
	_forest_painted = painted
	_push_forest()

func _push_forest() -> void:
	surface_material.set_shader_parameter("forest_paint", 1.0 if _has_forest and _forest_painted else 0.0)

## Hands the view's level-of-detail fades to the surface shader.
func apply_view(lod: ViewLod) -> void:
	var fades := Vector2(lod.sheen_fade, lod.grid_fade)
	if fades.is_equal_approx(_pushed): return
	_pushed = fades
	surface_material.set_shader_parameter("sheen_fade", fades.x)
	surface_material.set_shader_parameter("grid_fade", fades.y)

func _build_surface() -> void:
	surface_material = ShaderMaterial.new()
	surface_material.shader = board_shader
	surface_material.set_shader_parameter("grid_enabled", grid_visible)
	surface_material.set_shader_parameter("tile_size", WorldSpec.TILE)
	surface_material.set_shader_parameter("subtile_size", WorldSpec.SUBTILE)
	surface_material.set_shader_parameter("sheen_map", sheen_map)
	surface_material.set_shader_parameter("grass_map", grass_map)
	surface_material.set_shader_parameter("grass_macro_map", grass_macro_map)
	surface_material.set_shader_parameter("land_centre", TEST_LAND_CENTRE)
	surface_material.set_shader_parameter("land_radius", TEST_LAND_RADIUS)
	surface_material.set_shader_parameter("land_amplitude", PackedFloat32Array(TEST_LAND_AMPLITUDE))
	surface_material.set_shader_parameter("land_phase", PackedFloat32Array(TEST_LAND_PHASE))
	# The sea and grass are held to the colours they had before the scene took the models' viewer
	# lighting, which needs the tonemap's own settings to undo it (see board.gdshader).
	var environment := get_world_3d().environment
	if environment != null and environment.tonemap_mode == Environment.TONE_MAPPER_ACES:
		surface_material.set_shader_parameter("hold_colours", true)
		surface_material.set_shader_parameter("tonemap_exposure", environment.tonemap_exposure)
		surface_material.set_shader_parameter("tonemap_white", environment.tonemap_white)
	var plane := PlaneMesh.new()
	plane.size = Vector2(WorldSpec.BOARD_SIZE, WorldSpec.BOARD_SIZE)
	plane.material = surface_material
	var surface := MeshInstance3D.new()
	surface.name = "Surface"
	surface.mesh = plane
	surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(surface)

func _build_frame() -> void:
	var material := ShaderMaterial.new()
	material.shader = frame_shader
	material.set_shader_parameter("half_board", WorldSpec.HALF_BOARD)
	material.set_shader_parameter("frame_width", WorldSpec.FRAME_WIDTH)
	var width := WorldSpec.FRAME_WIDTH
	var height := WorldSpec.FRAME_HEIGHT + WorldSpec.FRAME_DEPTH
	var centre_y := (WorldSpec.FRAME_HEIGHT - WorldSpec.FRAME_DEPTH) * 0.5
	var offset := WorldSpec.HALF_BOARD + width * 0.5
	var outer := WorldSpec.BOARD_SIZE + width * 2.0
	# North and south run the full outer width; east and west fit between them. They overlap at
	# the corners, which the shader's mitre hides.
	var pieces := {
		"North": [Vector3(outer, height, width), Vector3(0.0, centre_y, -offset)],
		"South": [Vector3(outer, height, width), Vector3(0.0, centre_y, offset)],
		"West": [Vector3(width, height, WorldSpec.BOARD_SIZE), Vector3(-offset, centre_y, 0.0)],
		"East": [Vector3(width, height, WorldSpec.BOARD_SIZE), Vector3(offset, centre_y, 0.0)],
	}
	var frame := Node3D.new()
	frame.name = "Frame"
	add_child(frame)
	for piece_name: String in pieces:
		var box := BoxMesh.new()
		box.size = pieces[piece_name][0]
		box.material = material
		var piece := MeshInstance3D.new()
		piece.name = piece_name
		piece.mesh = box
		piece.position = pieces[piece_name][1]
		piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		frame.add_child(piece)
