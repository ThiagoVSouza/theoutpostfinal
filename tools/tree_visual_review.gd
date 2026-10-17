extends SceneTree
## Deterministic production-material gallery. Run with the regular Vulkan renderer, not
## --headless (which cannot capture rendered pixels):
## godot --path . --script res://tools/tree_visual_review.gd -- --output=previews/trees.png
## Optional: --rotation=90 --dense=10000 --frames=120 --no-bases --bases-only
## Nearest gameplay zoom, three rotations of one species: --closeup=maple (or index 0..7)
## Flat-ground lighting calibration: --calibrate --ambient=0.65 --rim=0.16 --sun=1.08
## Calibration uses a known linear albedo, no specular, and the board's Burley diffuse model.

const SIZE := Vector2i(1600, 1000)
const SPECIES := ["Oak", "Maple", "Birch", "Pine", "Stone pine", "Spruce", "Cypress", "White willow"]
var _viewport: SubViewport
var _camera: Camera3D
var _forest: Node3D
var _world: Node3D
var _output := "previews/tree-visual-pass/gallery.png"
var _rotation := 0.0
var _dense := 0
var _frames := 90
var _calibrate := false
var _no_bases := false
var _bases_only := false
var _closeup := -1
var _light_overrides := {}

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): _output = arg.trim_prefix("--output=")
		elif arg.begins_with("--rotation="): _rotation = deg_to_rad(float(arg.trim_prefix("--rotation=")))
		elif arg.begins_with("--dense="): _dense = maxi(0, int(arg.trim_prefix("--dense=")))
		elif arg.begins_with("--frames="): _frames = maxi(30, int(arg.trim_prefix("--frames=")))
		elif arg == "--calibrate": _calibrate = true
		elif arg == "--no-bases": _no_bases = true
		elif arg == "--bases-only": _bases_only = true
		elif arg.begins_with("--closeup="):
			var requested := arg.trim_prefix("--closeup=").replace("-", " ").to_lower()
			if requested.is_valid_int(): _closeup = clampi(int(requested), 0, SPECIES.size() - 1)
			else:
				for kind in SPECIES.size():
					if SPECIES[kind].to_lower() == requested: _closeup = kind
		elif arg.begins_with("--ambient="): _light_overrides["ambient"] = float(arg.trim_prefix("--ambient="))
		elif arg.begins_with("--rim="): _light_overrides["rim"] = float(arg.trim_prefix("--rim="))
		elif arg.begins_with("--sun="): _light_overrides["sun"] = float(arg.trim_prefix("--sun="))
	_build.call_deferred()

func _build() -> void:
	_viewport = SubViewport.new()
	_viewport.size = SIZE
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)
	_world = load("res://scenes/main.tscn").instantiate()
	# Keep the production environment, lights, Board and Forest construction. The interactive
	# camera, LOD switching and gameplay overlays are replaced by a fixed review camera/labels.
	_world.set_script(null)
	for child_name in ["Camera", "StatsOverlay", "GameUI"]:
		var old := _world.get_node(child_name)
		_world.remove_child(old)
		old.free()
	_viewport.add_child(_world)
	_forest = _world.get_node("Forest")
	if _no_bases or _bases_only:
		# Runtime-only copies make the comparison use identical trees/materials/placement.
		for kind in _forest._meshes.size():
			var mesh: ArrayMesh = _forest._meshes[kind].duplicate()
			if _bases_only:
				for surface in mini(2, mesh.get_surface_count()): mesh.surface_remove(0)
			else:
				while mesh.get_surface_count() > 2: mesh.surface_remove(mesh.get_surface_count() - 1)
			_forest._meshes[kind] = mesh
	_world.get_node("Board").grid_visible = false
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 68.0
	_camera.near = 0.1
	_camera.far = 240.0
	_world.add_child(_camera)
	_camera.position = Vector3(0, 90, 80)
	_camera.look_at(Vector3.ZERO)
	_camera.current = true
	_world.get_node("Sun").directional_shadow_max_distance = _camera.far
	if _light_overrides.has("ambient"):
		_world.get_node("WorldEnvironment").environment.ambient_light_energy = _light_overrides.ambient
	if _light_overrides.has("rim"): _world.get_node("Rim").light_energy = _light_overrides.rim
	if _light_overrides.has("sun"): _world.get_node("Sun").light_energy = _light_overrides.sun
	if _calibrate:
		_build_calibration()
	elif _closeup >= 0:
		_build_closeup()
	elif _dense > 0:
		_build_dense()
	else:
		_build_gallery()
	await _capture()

func _build_closeup() -> void:
	# Match StrategyCamera's closest gameplay view, including its depth range/shadow coverage.
	var pitch := StrategyCamera.HOME_PITCH
	var zoom := StrategyCamera.MIN_ZOOM
	var distance := StrategyCamera.distance_for(zoom, pitch)
	_camera.size = zoom
	_camera.position = Vector3(0, sin(pitch), cos(pitch)) * distance
	_camera.look_at(Vector3.ZERO)
	_camera.near = StrategyCamera.near_for(pitch, StrategyCamera.TALLEST_PIECE)
	_camera.far = distance + zoom * 0.5 / tan(pitch) + WorldSpec.FRAME_DEPTH / sin(pitch) + 10.0
	_world.get_node("Sun").directional_shadow_max_distance = StrategyCamera.shadow_reach_for(zoom, pitch)
	var overlay := CanvasLayer.new()
	_viewport.add_child(overlay)
	_label(overlay, "%s  /  closest gameplay zoom: %.0f m" % [SPECIES[_closeup], zoom], Vector2(38, 30), 24)
	for i in 3:
		var at := Vector3((i - 1) * 19.0, 0, 0)
		var yaw := float(i) * TAU / 3.0
		_tree(_closeup, at, yaw)
		_label(overlay, "%d degrees" % roundi(rad_to_deg(yaw + _rotation)), _camera.unproject_position(at) + Vector2(-38, 35), 18)
	_label(overlay, "Production camera angle + depth range, materials, grass and lighting", Vector2(38, 940), 18)

func _build_calibration() -> void:
	_world.get_node("Board").hide()
	_forest.hide()
	var environment: Environment = _world.get_node("WorldEnvironment").environment
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.tonemap_exposure = 1.0
	environment.tonemap_white = 1.0
	var shader := Shader.new()
	# Sixteen known linear-albedo strips reduce the error from 8-bit screenshot quantization.
	# Hardcoded ALBEDO also avoids the sRGB interpretation of material color uniforms.
	shader.code = "shader_type spatial; render_mode diffuse_burley; void fragment() { ALBEDO = vec3((floor(SCREEN_UV.x * 16.0) + 1.0) * 0.025); ROUGHNESS = 1.0; SPECULAR = 0.0; }"
	var material := ShaderMaterial.new()
	material.shader = shader
	var plane := PlaneMesh.new()
	plane.size = Vector2(1000, 1000)
	plane.material = material
	var sample := MeshInstance3D.new()
	sample.mesh = plane
	_world.add_child(sample)

func _tree(kind: int, at: Vector3, yaw: float = 0.0, scale_factor: float = 1.0) -> void:
	var tree := MeshInstance3D.new()
	tree.mesh = _forest._meshes[kind]
	tree.position = at
	tree.rotation.y = yaw + _rotation
	tree.scale = Vector3.ONE * scale_factor
	_world.add_child(tree)

func _build_gallery() -> void:
	var overlay := CanvasLayer.new()
	_viewport.add_child(overlay)
	_label(overlay, "TREE VISUAL REVIEW  /  production materials + lighting", Vector2(38, 30), 24)
	_label(overlay, "Eight species at authored scale  |  rotation %d degrees" % roundi(rad_to_deg(_rotation)), Vector2(38, 64), 16)
	for i in SPECIES.size():
		var at := Vector3((i - 3.5) * 12.5, 0, -19)
		_tree(i, at)
		_label(overlay, SPECIES[i], _camera.unproject_position(at) + Vector2(-34, 15), 17)
	var positions := [Vector3(-27, 0, 14), Vector3(-21, 0, 19), Vector3(-14, 0, 12),
		Vector3(-11, 0, 24), Vector3(-4, 0, 18), Vector3(11, 0, 13),
		Vector3(17, 0, 18), Vector3(22, 0, 10), Vector3(28, 0, 22), Vector3(15, 0, 27)]
	var kinds := [0, 2, 5, 1, 3, 4, 7, 5, 6, 0]
	var scales := [1.1, 0.95, 1.0, 1.05, 1.2, 1.0, 0.92, 1.1, 1.0, 0.85]
	for i in positions.size():
		_tree(kinds[i], positions[i], float(i) * 1.37, scales[i])
	_label(overlay, "Mixed groups  /  fixed placement, scale and rotation", Vector2(38, 940), 18)

func _build_dense() -> void:
	# The production generator supplies placement, species stands and 500m chunk batching.
	# Initialization/map-paint time is excluded from the settled viewport timings.
	_forest.set_count(_dense)
	var extent := sqrt(float(_dense) * 50.0)
	_camera.size = extent * 1.05
	_camera.far = extent * 4.0
	_camera.position = Vector3(0, extent * 1.4, extent * 1.2)
	_camera.look_at(Vector3.ZERO)
	_world.get_node("Sun").directional_shadow_max_distance = _camera.far

func _label(parent: Node, value: String, at: Vector2, font_size: int) -> void:
	var label := Label.new()
	label.text = value
	label.position = at
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color(0.95, 0.96, 0.88))
	label.add_theme_color_override("font_shadow_color", Color(0.08, 0.10, 0.04, 0.9))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 2)
	parent.add_child(label)

func _capture() -> void:
	# Allow asynchronous pipeline creation and directional shadow updates to settle first.
	RenderingServer.viewport_set_measure_render_time(_viewport.get_viewport_rid(), true)
	for frame in 60:
		await process_frame
	var frame_times: Array[float] = []
	var cpu_ms := 0.0
	var gpu_ms := 0.0
	var previous := Time.get_ticks_usec()
	for frame in _frames:
		await process_frame
		var now := Time.get_ticks_usec()
		frame_times.append(float(now - previous) / 1000.0)
		previous = now
		cpu_ms += RenderingServer.viewport_get_measured_render_time_cpu(_viewport.get_viewport_rid())
		gpu_ms += RenderingServer.viewport_get_measured_render_time_gpu(_viewport.get_viewport_rid())
	await RenderingServer.frame_post_draw
	var path := _output if _output.is_absolute_path() else ProjectSettings.globalize_path("res://" + _output)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var captured := _viewport.get_texture().get_image()
	var result := captured.save_png(path)
	frame_times.sort()
	var metrics := {"image": path, "size": [SIZE.x, SIZE.y], "rotation_degrees": rad_to_deg(_rotation),
		"dense_instances": _dense, "no_bases": _no_bases, "bases_only": _bases_only, "closeup_species": _closeup,
		"warmup_frames": 60, "measured_frames": _frames, "save_error": result,
		"rendering_method": RenderingServer.get_current_rendering_method(),
		"frame_wall_median_ms": frame_times[frame_times.size() / 2],
		"frame_wall_p95_ms": frame_times[mini(frame_times.size() - 1, floori(frame_times.size() * 0.95))],
		"viewport_cpu_mean_ms": cpu_ms / _frames, "viewport_gpu_mean_ms": gpu_ms / _frames,
		"timing_scope": "Synthetic offscreen gallery; wall time includes host scheduling and is not a gameplay benchmark",
		"draw_calls": _viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),
		"primitives": _viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME)}
	if _calibrate:
		var weighted_sum := Color(0, 0, 0, 0)
		var albedo_squares := 0.0
		for strip in 16:
			var albedo := (strip + 1.0) * 0.025
			var sum := Color(0, 0, 0, 0)
			var centre_x := roundi((strip + 0.5) * SIZE.x / 16.0)
			for y in range(SIZE.y / 2 - 8, SIZE.y / 2 + 8):
				for x in range(centre_x - 8, centre_x + 8):
					sum += captured.get_pixel(x, y).srgb_to_linear()
			weighted_sum += sum / 256.0 * albedo
			albedo_squares += albedo * albedo
		var irradiance := weighted_sum / albedo_squares
		metrics["calibration_linear_albedo_range"] = [0.025, 0.4]
		metrics["calibration_fit"] = "Least squares through origin, 16 linear-albedo strips, 256 sRGB-decoded samples per strip"
		metrics["calibration_light_multiplier"] = [irradiance.r, irradiance.g, irradiance.b]
		metrics["light_overrides"] = _light_overrides
	var report := FileAccess.open(path.get_basename() + ".json", FileAccess.WRITE)
	if report: report.store_string(JSON.stringify(metrics, "\t") + "\n")
	print(JSON.stringify(metrics))
	quit(0 if result == OK else 1)
