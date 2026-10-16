class_name Forest
extends Node3D
## A benchmark forest on the test land mass: none, 1,000, 10,000 or 50,000 trees, cycled with T.
##
## The trees are the current low-poly set from TheOutpostModels, about 200 triangles each, one
## per species. They stand at one dense spacing whatever the count, so a larger count is a larger
## forest rather than a thicker one, centred on the land mass. Species grow in stands, each stand
## mostly one species with a share of others mixed in, rather than an even salt-and-pepper mix.
##
## Every tree of one species in one 500 m chunk is a single MultiMesh, so a chunk off screen is
## culled whole and the whole forest is a few hundred draw calls at most.
##
## From the Distant level of detail out the meshes are hidden and the forest is painted into the
## grass instead, from a canopy map this builds from the same tree positions: each crown's
## footprint, coloured by its species' average foliage colour. Distant starts where a 100 m tile
## covers 48 pixels, so a crown is 2 to 5 pixels across there.

## What T steps through.
const COUNTS: Array[int] = [0, 1000, 10000, 50000]
## Ground per tree, so 50,000 trees cover about 2.5 km^2. Crowns are 2 to 9.6 m across, so at
## this spacing (about 7 m) neighbouring crowns overlap: a closed forest, not an orchard.
const AREA_PER_TREE := 50.0
## Trees keep this far inside the coast.
const COAST_MARGIN := 15.0
const CHUNK_SIZE := 500.0
## Species stands are cells of roughly this size.
const STAND_SIZE := 140.0
## Share of the trees in a stand that are some other species.
const STAND_MIX := 0.25
const SCALE_MIN := 0.85
const SCALE_MAX := 1.2
const SEED := 20261016
## Texels across the canopy map. It covers just the forest, so its texels shrink with it: about
## 1.8 m for 50,000 trees, near a pixel's width where the Distant level begins (about 1.4 m).
const PAINT_TEXELS := 1024
## Crowns shade their own insides, so seen from above a forest is darker than its leaves' colour.
const CANOPY_SHADE := 0.8

## One imported tree scene per species, and the shader the foliage cards are drawn with. Set in
## the scene rather than preloaded, for the reason in board.gd.
@export var species: Array[PackedScene]
@export var foliage_shader: Shader

var count := 0
## How many trees actually stand, which can fall short of count if the land runs out.
var placed := 0
var paint_texture: ImageTexture
var paint_origin := Vector2.ZERO
var paint_size := 1.0

## Per species: the tree as one mesh (wood and foliage surfaces), its crown radius, and the colour
## its crown paints into the grass.
var _meshes: Array[ArrayMesh] = []
var _crown_radius: PackedFloat32Array = []
var _crown_colour: Array[Color] = []
## One material for every root patch; the patch is a third surface in the same species MultiMesh.
## Its ground settings are copied once from Board so the feathered edge follows the meadow grade.
var _base_material: ShaderMaterial

func _ready() -> void:
	_base_material = _make_base_material()
	for scene in species:
		_add_species(scene)

## The next count in COUNTS.
func cycle() -> void:
	set_count(COUNTS[(COUNTS.find(count) + 1) % COUNTS.size()])

func set_count(trees: int) -> void:
	count = trees
	for child in get_children():
		child.queue_free()
	placed = 0
	paint_texture = null
	if trees <= 0 or _meshes.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED + trees
	var spots := _spots(trees, rng)
	placed = spots.size()
	var stands := FastNoiseLite.new()
	stands.noise_type = FastNoiseLite.TYPE_CELLULAR
	stands.cellular_return_type = FastNoiseLite.RETURN_CELL_VALUE
	stands.frequency = 1.0 / STAND_SIZE
	stands.seed = SEED
	var kinds := PackedInt32Array()
	var scales := PackedFloat32Array()
	kinds.resize(placed)
	scales.resize(placed)
	## (chunk x, chunk z, species) -> MultiMesh transform rows. A plain Array, appended in place:
	## a packed array taken out of a dictionary is copied on its next write, which would copy the
	## whole bucket for every tree.
	var buckets := {}
	for i in placed:
		var p := spots[i]
		var kind := clampi(int((stands.get_noise_2dv(p) * 0.5 + 0.5) * _meshes.size()), 0, _meshes.size() - 1)
		if rng.randf() < STAND_MIX:
			kind = rng.randi_range(0, _meshes.size() - 1)
		var scale := rng.randf_range(SCALE_MIN, SCALE_MAX)
		kinds[i] = kind
		scales[i] = scale
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * scale)
		var key := Vector3i(floori(p.x / CHUNK_SIZE), floori(p.y / CHUNK_SIZE), kind)
		if not buckets.has(key):
			buckets[key] = []
		var rows: Array = buckets[key]
		rows.append_array([basis.x.x, basis.y.x, basis.z.x, p.x,
			basis.x.y, basis.y.y, basis.z.y, 0.0,
			basis.x.z, basis.y.z, basis.z.z, p.y])
	for key: Vector3i in buckets:
		var rows := PackedFloat32Array(buckets[key])
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = _meshes[key.z]
		multimesh.instance_count = rows.size() / 12
		multimesh.buffer = rows
		var node := MultiMeshInstance3D.new()
		node.name = "Chunk_%d_%d_%d" % [key.x, key.y, key.z]
		node.multimesh = multimesh
		add_child(node)
	_paint(spots, kinds, scales)

## Where the trees stand: a jittered grid at AREA_PER_TREE, on land, nearest the land mass's
## centre first, so the forest is a roughly round patch whose size follows the count.
func _spots(trees: int, rng: RandomNumberGenerator) -> PackedVector2Array:
	var spacing := sqrt(AREA_PER_TREE)
	var reach := sqrt(trees * AREA_PER_TREE / PI) * 1.25 + spacing * 2.0
	var steps := ceili(reach / spacing)
	var candidates := PackedVector2Array()
	var distances := PackedFloat32Array()
	for gz in range(-steps, steps + 1):
		for gx in range(-steps, steps + 1):
			var p := Board.TEST_LAND_CENTRE + Vector2(gx, gz) * spacing \
				+ Vector2(rng.randf() - 0.5, rng.randf() - 0.5) * spacing * 0.8
			var distance := p.distance_to(Board.TEST_LAND_CENTRE)
			if distance > reach or Board.test_land_inland(p) < COAST_MARGIN:
				continue
			candidates.append(p)
			distances.append(distance)
	if candidates.size() <= trees:
		return candidates
	# The trees-th nearest distance, found by sorting a copy natively rather than sorting the
	# points themselves through a GDScript comparison.
	var sorted := distances.duplicate()
	sorted.sort()
	var limit := sorted[trees - 1]
	var spots := PackedVector2Array()
	for i in candidates.size():
		if distances[i] <= limit and spots.size() < trees:
			spots.append(candidates[i])
	return spots

## The canopy map for the Distant level and out: RGB the crowns' colour, alpha their coverage.
func _paint(spots: PackedVector2Array, kinds: PackedInt32Array, scales: PackedFloat32Array) -> void:
	var widest := 0.0
	for radius in _crown_radius:
		widest = maxf(widest, radius * SCALE_MAX)
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for p in spots:
		low = low.min(p)
		high = high.max(p)
	paint_size = maxf(high.x - low.x, high.y - low.y) + widest * 2.0 + 8.0
	paint_origin = (low + high) * 0.5 - Vector2.ONE * paint_size * 0.5
	var texel := paint_size / PAINT_TEXELS
	var cover := PackedFloat32Array()
	var colour := PackedFloat32Array()
	cover.resize(PAINT_TEXELS * PAINT_TEXELS)
	colour.resize(PAINT_TEXELS * PAINT_TEXELS * 3)
	var mean := Color(0, 0, 0)
	for i in spots.size():
		var crown: Color = _crown_colour[kinds[i]]
		mean += crown
		var radius := _crown_radius[kinds[i]] * scales[i]
		var centre := (spots[i] - paint_origin) / texel
		if radius < texel:
			# A crown smaller than a texel adds its share of that texel's area.
			var index := clampi(int(centre.y), 0, PAINT_TEXELS - 1) * PAINT_TEXELS + clampi(int(centre.x), 0, PAINT_TEXELS - 1)
			_cover(cover, colour, index, PI * radius * radius / (texel * texel), crown)
			continue
		var reach := radius / texel
		for y in range(maxi(0, floori(centre.y - reach)), mini(PAINT_TEXELS, ceili(centre.y + reach))):
			for x in range(maxi(0, floori(centre.x - reach)), mini(PAINT_TEXELS, ceili(centre.x + reach))):
				if Vector2(x + 0.5, y + 0.5).distance_squared_to(centre) <= reach * reach:
					_cover(cover, colour, y * PAINT_TEXELS + x, 1.0, crown)
	mean /= maxf(spots.size(), 1)
	var bytes := PackedByteArray()
	bytes.resize(PAINT_TEXELS * PAINT_TEXELS * 4)
	for index in cover.size():
		var amount := cover[index]
		# Empty texels take the forest's mean colour rather than black, so the mip chain does not
		# darken the forest's edge as it averages them in.
		var linear := mean if amount <= 0.0 else Color(colour[index * 3], colour[index * 3 + 1], colour[index * 3 + 2]) / amount
		var srgb := linear.linear_to_srgb()
		bytes[index * 4] = clampi(roundi(srgb.r * 255.0), 0, 255)
		bytes[index * 4 + 1] = clampi(roundi(srgb.g * 255.0), 0, 255)
		bytes[index * 4 + 2] = clampi(roundi(srgb.b * 255.0), 0, 255)
		bytes[index * 4 + 3] = clampi(roundi(minf(amount, 1.0) * 255.0), 0, 255)
	var image := Image.create_from_data(PAINT_TEXELS, PAINT_TEXELS, false, Image.FORMAT_RGBA8, bytes)
	image.generate_mipmaps()
	paint_texture = ImageTexture.create_from_image(image)

static func _cover(cover: PackedFloat32Array, colour: PackedFloat32Array, index: int, amount: float, crown: Color) -> void:
	cover[index] += amount
	colour[index * 3] += crown.r * amount
	colour[index * 3 + 1] += crown.g * amount
	colour[index * 3 + 2] += crown.b * amount

## Folds one imported tree into one mesh, puts its foliage on the foliage shader, measures its
## crown, and appends a two-triangle soil/litter patch. The patch uses the existing batch transform.
func _add_species(scene: PackedScene) -> void:
	var tree := scene.instantiate()
	var mesh := ArrayMesh.new()
	var radius := 0.0
	var crown := Color(0.1, 0.2, 0.08)
	for node in tree.find_children("*", "MeshInstance3D", true, false):
		var part := node as MeshInstance3D
		# The models' parts all sit at the tree's origin; their transforms are not baked in.
		for surface in part.mesh.get_surface_count():
			var material := part.get_active_material(surface)
			if material is BaseMaterial3D and (material as BaseMaterial3D).transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR:
				var leaves := material as BaseMaterial3D
				var foliage := ShaderMaterial.new()
				foliage.shader = foliage_shader
				foliage.set_shader_parameter("albedo_texture", leaves.albedo_texture)
				foliage.set_shader_parameter("albedo_color", leaves.albedo_color)
				foliage.set_shader_parameter("alpha_cutoff", leaves.alpha_scissor_threshold)
				foliage.set_shader_parameter("roughness", leaves.roughness)
				# The GLB material's extras, which Godot keeps as metadata, say whether the cards'
				# normals describe the crown's volume (see foliage.gdshader).
				var extras: Variant = leaves.get_meta("extras", {})
				foliage.set_shader_parameter("volume_normals",
					extras is Dictionary and extras.get("outpostFoliageNormalMode", "") == "volume")
				material = foliage
				var size := part.mesh.get_aabb().size
				radius = maxf(size.x, size.z) * 0.5
				crown = _mean_foliage(leaves) * _mean_vertex_colour(part.mesh.surface_get_arrays(surface)) * CANOPY_SHADE
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, part.mesh.surface_get_arrays(surface))
			mesh.surface_set_material(mesh.get_surface_count() - 1, material)
	tree.free()
	_add_base_surface(mesh, clampf(radius * 0.48, 0.85, 2.3))
	_meshes.append(mesh)
	_crown_radius.append(radius)
	_crown_colour.append(crown)

func _make_base_material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/tree_base.gdshader") as Shader
	var board := get_parent().get_node_or_null("Board") as Board
	if board != null and board.surface_material != null:
		for parameter in ["grass_map", "grass_macro_map", "grass_tile_size", "grass_macro_tile_size", "grass_mean", "grass_variation",
				"grass_detail_gain", "grass_detail_contrast", "hold_colours", "old_light", "new_light",
				"tonemap_exposure", "tonemap_white"]:
			var value: Variant = board.surface_material.get_shader_parameter(parameter)
			if value != null:
				material.set_shader_parameter(parameter, value)
	else:
		# Also usable by a standalone tree gallery. No per-frame dependency on the board is needed.
		material.set_shader_parameter("grass_map", load("res://assets/textures/grass_meadow_detail.png"))
		material.set_shader_parameter("grass_macro_map", load("res://assets/textures/grass_meadow.png"))
	return material

static func _base_arrays(radius: float) -> Array:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	# A small lift avoids depth fighting with the board; the irregular outline lives in the shader.
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3(-radius, 0.018, -radius), Vector3(radius, 0.018, -radius),
		Vector3(radius, 0.018, radius), Vector3(-radius, 0.018, radius)])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([
		Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	return arrays

func _add_base_surface(mesh: ArrayMesh, radius: float) -> void:
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _base_arrays(radius))
	mesh.surface_set_material(mesh.get_surface_count() - 1, _base_material)

## Vertex colour carries the crown's baked interior shading. Include it in the distant canopy
## average as well as the live foliage shader, weighted by triangle area so small bough cards do
## not count as much as large ones. This is measured once when a species loads.
static func _mean_vertex_colour(arrays: Array) -> Color:
	var colours: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
	if colours.is_empty():
		return Color.WHITE
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	var element_count := indices.size() if not indices.is_empty() else vertices.size()
	var total := Color(0, 0, 0, 0)
	var weight := 0.0
	for triangle in range(0, element_count - 2, 3):
		var a := indices[triangle] if not indices.is_empty() else triangle
		var b := indices[triangle + 1] if not indices.is_empty() else triangle + 1
		var c := indices[triangle + 2] if not indices.is_empty() else triangle + 2
		var area := (vertices[b] - vertices[a]).cross(vertices[c] - vertices[a]).length()
		total += (colours[a] + colours[b] + colours[c]) * (area / 3.0)
		weight += area
	return Color(total.r / weight, total.g / weight, total.b / weight) if weight > 0.0 else Color.WHITE

## The foliage texture's average colour where it is leaf rather than cutout, in linear light.
static func _mean_foliage(leaves: BaseMaterial3D) -> Color:
	var tint := leaves.albedo_color.srgb_to_linear()
	if leaves.albedo_texture == null:
		return tint
	var image := leaves.albedo_texture.get_image()
	if image == null:
		return tint
	if image.is_compressed() and image.decompress() != OK:
		push_warning("Could not read %s back to average it; painting its forest a default green." % leaves.albedo_texture.resource_path)
		return Color(0.04, 0.08, 0.025)
	image.clear_mipmaps()
	image.convert(Image.FORMAT_RGBA8)
	image.resize(128, 128, Image.INTERPOLATE_BILINEAR)
	var total := Color(0, 0, 0)
	var weight := 0.0
	for y in image.get_height():
		for x in image.get_width():
			var c := image.get_pixel(x, y)
			if c.a < 0.5:
				continue
			var linear := c.srgb_to_linear()
			total += Color(linear.r, linear.g, linear.b) * c.a
			weight += c.a
	if weight <= 0.0:
		return tint
	return Color(total.r / weight * tint.r, total.g / weight * tint.g, total.b / weight * tint.b)
