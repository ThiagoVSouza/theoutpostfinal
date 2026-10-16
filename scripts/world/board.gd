class_name Board
extends Node3D
## The 100 km board and the wood frame around it, built from WorldSpec.
##
## The surface is a single quad: everything on it, the ocean and the grid included, is drawn by its
## shader from the world position, so the board costs the same at any size. The frame is four boxes
## sharing one material whose shader works out the mitred corners itself.
##
## The shaders and the sheen texture are set in the scene rather than preloaded here. This script
## is read on the loading screen's loader thread, and in Godot 4.7.1 a preload inside a script read
## there leaves one loader object per preloaded file behind, reported as leaked instances at exit.
## Resources the scene file references load as ordinary dependencies of the scene and do not.

@export var board_shader: Shader
@export var frame_shader: Shader
@export var sheen_map: Texture2D

var grid_visible := true:
	set(value):
		grid_visible = value
		if surface_material != null: surface_material.set_shader_parameter("grid_enabled", value)

var surface_material: ShaderMaterial
## The fades last written to the surface, so a settled view stops writing them every frame.
var _pushed := Vector3(-1.0, -1.0, -1.0)

func _ready() -> void:
	_build_surface()
	_build_frame()

## Hands the view's level-of-detail fades to the surface shader.
func apply_view(lod: ViewLod) -> void:
	var fades := Vector3(lod.sheen_fade, lod.strategic_blend, lod.grid_fade)
	if fades.is_equal_approx(_pushed): return
	_pushed = fades
	surface_material.set_shader_parameter("sheen_fade", fades.x)
	surface_material.set_shader_parameter("strategic_blend", fades.y)
	surface_material.set_shader_parameter("grid_fade", fades.z)

func _build_surface() -> void:
	surface_material = ShaderMaterial.new()
	surface_material.shader = board_shader
	surface_material.set_shader_parameter("grid_enabled", grid_visible)
	surface_material.set_shader_parameter("tile_size", WorldSpec.TILE)
	surface_material.set_shader_parameter("subtile_size", WorldSpec.SUBTILE)
	surface_material.set_shader_parameter("sheen_map", sheen_map)
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
