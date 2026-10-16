extends Control
## Loads the game scene and reports the progress that is actually being made.
##
## Carried over from TheOutpostMap2's loading screen, and it keeps the same rule: nothing here
## runs on a timer. The bar only ever reports work that is finished.
##
## The expensive part of showing a scene is not reading it off disk, it is the first real draw:
## shader compilation and mesh upload. So the scene is added as a child behind this opaque
## overlay rather than swapped in with change_scene_to_file. It renders, compiles and warms while
## the bar is still up, and removing the overlay then reveals a scene that is already drawing,
## instead of moving the freeze to just after the bar reaches the end.
##
## The stages are the resource loader's own percentage (the scene and everything in PRELOAD,
## averaged), instantiating the scene, the scene's own build work if it reports any, and the
## warm-up frames that are genuinely drawn.
##
## A stage the main thread does in one call is a stage the bar cannot report. Before adding work
## to startup, check which thread it lands on: heavy work inside a node's _ready runs inside the
## add_child below, where _process does not get a turn.

const GAME_SCENE := "res://scenes/main.tscn"
const LoadingView := preload("res://scripts/ui/loading_screen_view.gd")

## Used by the visual review tool. Normal startup never waits for a preview or a timer.
@export var preview_mode := false

## Read on the loader thread alongside the game scene, and held until the scene has been built.
## Assets a scene loads by path from its own _ready would otherwise be read on the main thread
## inside add_child; requesting them here overlaps them with the scene load, and the scene's own
## load() becomes a cache hit. The forest creates its tree-base material at runtime.
const PRELOAD: Array[String] = ["res://shaders/tree_base.gdshader"]

## Shares of the bar for each stage, so the bar moves at roughly the rate work completes.
## Re-measure with `godot --path . -- --profile-startup` once the scene has real weight.
const LOAD_SHARE := 0.80
## Reached once the scene is instantiated and in the tree, before its first frame is drawn.
const INSTANTIATE_SHARE := 0.85
## Reached once the scene reports its own build work finished. A scene that has none — anything
## without a build_fraction() method — skips straight here.
const BUILD_SHARE := 0.95
## Frames the scene must actually draw before it is revealed, counted from the frame its build
## finished on. The first of them pays for shader compilation; the rest confirm it draws steadily.
const WARM_FRAMES := 5

## The bar eases towards the real value instead of snapping, so a stage that completes in one
## step still reads as movement. It only ever catches up to work already done.
const CATCH_UP_RATE := 5.0
const MINIMUM_RATE := 0.4

var loading := false
## Paths whose threaded request was accepted, and the resources they produced. The second list
## holds a reference so the cache cannot release an asset between the preload and the scene's
## own load() of it.
var preloading: Array[String] = []
var preloaded: Array[Resource] = []
var painted := false
var leaving := false
var failed := false
var pending_scene: PackedScene
var game: Node
var warm_from := 0
var target := 0.0
var shown := 0.0
var stage_text := ""
var layer: CanvasLayer
var overlay: ColorRect
var bar: ProgressBar
var stage_label: Label
var percent_label: Label
var view: Control
var profile := false
var started_usec := 0
var stage_usec := 0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# This Control stays in the tree as the game's parent after the overlay is gone. A Control
	# defaults to MOUSE_FILTER_STOP, and at full rect that would swallow mouse input before the
	# game's _unhandled_input sees it.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	profile = "--profile-startup" in OS.get_cmdline_user_args()
	started_usec = Time.get_ticks_usec()
	stage_usec = started_usec
	_build_ui()
	_set_progress(0.0, "Gathering resources")
	if preview_mode:
		set_process(false)
		return
	var error := ResourceLoader.load_threaded_request(GAME_SCENE)
	if error != OK:
		_fail("Could not start loading the game: " + error_string(error))
		return
	# A preload that cannot be started is not a failure: whoever needs the asset still load()s
	# it, and the only cost is that they pay for it on the main thread.
	for path in PRELOAD:
		if ResourceLoader.exists(path) and ResourceLoader.load_threaded_request(path) == OK:
			preloading.append(path)
	loading = true

func _process(delta: float) -> void:
	if overlay == null or failed or preview_mode: return
	# Never instantiate before this screen has been drawn once, or a warm start would do all of
	# it in the first frame and leave the boot colour up until it finished.
	if pending_scene != null: _instantiate_game()
	elif loading and painted: _poll_load()
	elif game != null and not leaving: _poll_build()
	if failed: return
	painted = true
	shown = move_toward(shown, target, maxf(MINIMUM_RATE, (target - shown) * CATCH_UP_RATE) * delta)
	bar.value = shown * 100.0
	percent_label.text = "%d%%" % floori(shown * 100.0)
	if game != null and not leaving and shown >= 1.0:
		leaving = true
		if profile:
			print("STARTUP_TOTAL_MS ", (Time.get_ticks_usec() - started_usec) / 1000.0)
		var fade := create_tween()
		fade.tween_property(overlay, "modulate:a", 0.0, 0.25)
		fade.tween_callback(_reveal)

func _poll_load() -> void:
	var parts := []
	var status := ResourceLoader.load_threaded_get_status(GAME_SCENE, parts)
	var progress := float(parts[0]) if not parts.is_empty() else 0.0
	var done := status != ResourceLoader.THREAD_LOAD_IN_PROGRESS
	# The preloads run on the same loader and finish in whatever order they finish, so they are
	# averaged in with the scene rather than counted after it.
	for path in preloading:
		var sub := []
		var sub_status := ResourceLoader.load_threaded_get_status(path, sub)
		progress += float(sub[0]) if not sub.is_empty() else 0.0
		if sub_status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			done = false
	progress /= float(preloading.size() + 1)
	if not done:
		_set_progress(progress * LOAD_SHARE, "Gathering resources")
		return
	loading = false
	if status != ResourceLoader.THREAD_LOAD_LOADED:
		_fail("The game resources could not be loaded.")
		return
	var scene := ResourceLoader.load_threaded_get(GAME_SCENE) as PackedScene
	if scene == null:
		_fail("The game scene is invalid.")
		return
	for path in preloading:
		var resource := ResourceLoader.load_threaded_get(path)
		if resource != null:
			preloaded.append(resource)
	_set_progress(LOAD_SHARE, "Shaping the world")
	# Let this status actually draw before synchronous scene construction begins next frame.
	pending_scene = scene

func _instantiate_game() -> void:
	game = pending_scene.instantiate()
	pending_scene = null
	if game == null:
		_fail("The game scene could not be created. Please try again.")
		return
	add_child(game)
	# Behind this screen, so it draws and compiles its shaders while the bar is still up.
	move_child(game, 0)
	warm_from = Engine.get_frames_drawn()
	_set_progress(INSTANTIATE_SHARE, "Shaping the world")

## The scene's own build work, then real frames it has drawn. Both are counts of finished work
## rather than elapsed time. A scene opts in to the build stage by exposing build_fraction(),
## returning 0..1, which reaches 1 only once everything it builds is in the tree.
func _poll_build() -> void:
	if game.has_method("build_fraction"):
		var fraction := clampf(float(game.build_fraction()), 0.0, 1.0)
		if fraction < 1.0:
			_set_progress(INSTANTIATE_SHARE + fraction * (BUILD_SHARE - INSTANTIATE_SHARE), "Shaping the world")
			# The warm-up counts from the end of the build, not from instantiation: frames drawn
			# before the scene is whole are not evidence that the whole scene draws.
			warm_from = Engine.get_frames_drawn()
			return
	var drawn := Engine.get_frames_drawn() - warm_from
	var amount := clampf(float(drawn) / WARM_FRAMES, 0.0, 1.0)
	_set_progress(BUILD_SHARE + amount * (1.0 - BUILD_SHARE),
		"Your outpost awaits" if drawn >= WARM_FRAMES else "Preparing the view")

func _set_progress(amount: float, text: String) -> void:
	# Progress only ever moves forward: a later stage reporting less is a reporting bug.
	target = clampf(amount, target, 1.0)
	if text == stage_text: return
	if profile:
		var now := Time.get_ticks_usec()
		print("STARTUP_STAGE ", stage_text, " | ms=", (now - stage_usec) / 1000.0)
		stage_usec = now
	stage_text = text
	stage_label.text = text

func _reveal() -> void:
	layer.queue_free()
	layer = null
	overlay = null
	# The scene has been built, so whatever still needs these holds its own reference by now.
	preloaded.clear()
	preloading.clear()
	set_process(false)

func _fail(text: String) -> void:
	loading = false
	failed = true
	pending_scene = null
	stage_label.text = text
	percent_label.text = ""
	view.show_error()
	set_process(false)

func _retry() -> void:
	var error := get_tree().reload_current_scene()
	if error != OK:
		_fail("Unable to restart loading. Please close and reopen the game.")

func _build_ui() -> void:
	# The game builds its own overlays on CanvasLayers, which would draw over a plain Control.
	# Putting this overlay on a higher layer keeps it in front until the game is revealed.
	layer = CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	overlay = ColorRect.new()
	overlay.color = Color("171610")
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(overlay)
	view = LoadingView.new()
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(view)
	bar = view.bar
	stage_label = view.stage_label
	percent_label = view.percent_label
	view.retry_button.pressed.connect(_retry)
	view.quit_button.pressed.connect(func(): get_tree().quit())
