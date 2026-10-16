class_name AudioManager
extends Node
## The game's music and sound effects, played by cue name from assets/audio/audio.json. Autoloaded
## as Audio.
##
## Ported from TheOutpostGodot's core/audio/audio_manager.gd, keeping what this game uses: named
## cues, one music player that fades, a pool of effect voices, a window cut out of a longer effect,
## and buses per category. Screens never name a file: re-scoring the game is a change to the
## manifest.
##
## Every button gets the click and hover sounds without being wired by hand. Rather than walking
## each screen, this listens to the SceneTree for every node that enters it, so a button added by
## any screen at any time is covered, and one a screen forgets cannot exist. A disabled button stays
## silent: a control that answers the pointer while refusing to be pressed is a worse lie than
## silence.
##
## The streams are read by the loading screen, on its loader thread, with everything else
## (preload_paths), and taken into the cache before the loading screen lets go of them (warm). So
## nothing is read from disk once the game is showing, and the first press is never the one that
## pays for a load.

const MANIFEST := "res://assets/audio/audio.json"

## Manifest categories, which are also the bus names (default_bus_layout.tres).
const MUSIC := "music"
const SFX := "sfx"
const AMBIENCE := "ambience"
const CATEGORIES: Array[String] = [MUSIC, SFX, AMBIENCE]

## The track for the game itself.
const GAME_MUSIC := "game"
const CLICK := "ui_click"
const HOVER := "ui_hover"

## How many effects can overlap before the oldest is cut off, so two quick presses sound like two.
const SFX_VOICES := 8
## Seconds to fade between tracks, and to bring the first track in as the game appears.
const MUSIC_FADE := 0.6
const MUSIC_INTRO_FADE := 2.0
const SILENT_DB := -80.0

## Marks a button already given its sounds, so a button re-entering the tree is not connected twice.
const WIRED_FLAG := "_audio_wired"

## Off while a capture or test script runs the game (OUTPOST_TEST_RUN=1): nobody hears it, and a
## playback left open at exit is reported as a leaked instance.
var enabled: bool = OS.get_environment("OUTPOST_TEST_RUN") != "1"

var _cues: Dictionary = {}  # category -> { id -> {path, loop, volume_db, start, length, fade} }
var _streams: Dictionary = {}  # path, or path#window for a cut effect -> AudioStream
var _music: AudioStreamPlayer
var _voices: Array[AudioStreamPlayer] = []
var _next_voice := 0
var _music_cue := ""
var _fade: Tween

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_music = AudioStreamPlayer.new()
	_music.bus = bus_for(MUSIC)
	add_child(_music)
	for i in SFX_VOICES:
		var voice := AudioStreamPlayer.new()
		voice.bus = bus_for(SFX)
		add_child(voice)
		_voices.append(voice)
	load_manifest(MANIFEST)
	get_tree().node_added.connect(_on_node_added)
	# Closing the window goes through quit_cleanly, so the audio is released before the app ends.
	get_tree().auto_accept_quit = false

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		quit_cleanly()

## Ends the game with its audio released first. Stopping a player only asks the audio thread to
## drop its playback on its next mix; quitting in the same frame often beats it there, and the
## playback and its stream are then reported as leaked instances at exit. A tenth of a second is
## several mixes. Anything that quits the game should call this rather than SceneTree.quit().
func quit_cleanly() -> void:
	stop_music(false)
	for voice in _voices:
		voice.stop()
	await get_tree().create_timer(0.1, true, false, true).timeout
	get_tree().quit()

## Cut the music dead on the way out, for a quit that did not come through quit_cleanly: there is
## no next frame for a fade.
func _exit_tree() -> void:
	stop_music(false)

## Every file the manifest names, for the loading screen to read on its loader thread.
func preload_paths() -> Array[String]:
	var paths: Array[String] = []
	for category in _cues:
		for id in _cues[category]:
			var path: String = _cues[category][id]["path"]
			if not paths.has(path):
				paths.append(path)
	return paths

## Takes every cue's stream into the cache, and cuts the windowed effects, while the loading screen
## still holds what it read, so these are cache hits rather than reads.
func warm() -> void:
	for category in _cues:
		for id in _cues[category]:
			var cue: Dictionary = _cues[category][id]
			if category == SFX:
				_sfx_stream(cue)
			else:
				_stream(cue["path"], cue["loop"])

## Reads audio.json. Shape: {"version": 1, "<category>": {"<cue>": {"file", "loop", "volume"}}},
## file paths relative to the manifest, volume 0..1 linear. An effect may also give "start",
## "length" and "fade" in seconds, to sound only that window of its file (see cut).
func load_manifest(path: String) -> bool:
	if not FileAccess.file_exists(path):
		push_warning("No audio manifest at %s" % path)
		return false
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not manifest is Dictionary:
		push_warning("Audio manifest %s is not readable JSON" % path)
		return false
	for category in CATEGORIES:
		var entries: Dictionary = manifest.get(category, {})
		for id: String in entries:
			var entry: Dictionary = entries[id]
			var file := String(entry.get("file", ""))
			if file.is_empty():
				continue
			if not _cues.has(category):
				_cues[category] = {}
			_cues[category][id] = {
				"path": path.get_base_dir().path_join(file),
				"loop": bool(entry.get("loop", category == MUSIC)),
				"volume_db": linear_to_db(clampf(float(entry.get("volume", 1.0)), 0.0, 1.0)),
				"start": maxf(0.0, float(entry.get("start", 0.0))),
				"length": maxf(0.0, float(entry.get("length", 0.0))),
				"fade": maxf(0.0, float(entry.get("fade", 0.0))),
			}
	return true

## Starts a music cue, fading from whatever is playing. Asking for the cue already playing does
## nothing rather than restarting it.
func play_music(id: String, fade_in := MUSIC_FADE) -> void:
	if not enabled or (_music_cue == id and _music.playing):
		return
	var cue := _cue(MUSIC, id)
	if cue.is_empty():
		return
	var stream := _stream(cue["path"], cue["loop"])
	if stream == null:
		return
	_music_cue = id
	var target: float = cue["volume_db"]
	if _music.playing:
		_tween_music(SILENT_DB, MUSIC_FADE, func() -> void: _start_music(stream, target, fade_in))
		return
	_start_music(stream, target, fade_in)

func stop_music(fade := true) -> void:
	_music_cue = ""
	if _music == null or not _music.playing:
		return
	if not fade:
		if _fade != null and _fade.is_valid():
			_fade.kill()
		_music.stop()
		return
	_tween_music(SILENT_DB, MUSIC_FADE, _music.stop)

## Fires an effect on the next free voice, so overlapping effects stack instead of cutting off.
func play_sfx(id: String) -> void:
	if not enabled:
		return
	var cue := _cue(SFX, id)
	if cue.is_empty():
		return
	var stream := _sfx_stream(cue)
	if stream == null:
		return
	var voice := _free_voice()
	voice.stream = stream
	voice.volume_db = cue["volume_db"]
	voice.play()

func _on_node_added(node: Node) -> void:
	if node is BaseButton and not node.has_meta(WIRED_FLAG):
		node.set_meta(WIRED_FLAG, true)
		node.pressed.connect(_sound_for.bind(node, CLICK))
		node.mouse_entered.connect(_sound_for.bind(node, HOVER))

func _sound_for(button: BaseButton, cue: String) -> void:
	if not button.disabled:
		play_sfx(cue)

func _start_music(stream: AudioStream, target_db: float, fade_in: float) -> void:
	_music.stream = stream
	_music.volume_db = SILENT_DB
	_music.play()
	_tween_music(target_db, fade_in)

## One fade at a time: a new one replaces a running one, or the two fight over volume_db.
func _tween_music(to_db: float, seconds: float, on_done: Callable = Callable()) -> void:
	if _fade != null and _fade.is_valid():
		_fade.kill()
	_fade = create_tween()
	_fade.tween_property(_music, "volume_db", to_db, seconds)
	if on_done.is_valid():
		_fade.tween_callback(on_done)

func _free_voice() -> AudioStreamPlayer:
	for voice in _voices:
		if not voice.playing:
			return voice
	# All busy: reuse them in turn, so the effect cut off is the oldest.
	var voice := _voices[_next_voice]
	_next_voice = (_next_voice + 1) % _voices.size()
	return voice

func _cue(category: String, id: String) -> Dictionary:
	var entries: Dictionary = _cues.get(category, {})
	if not entries.has(id):
		push_warning("No %s cue '%s'" % [category, id])
		return {}
	return entries[id]

## The stream an effect sounds: its file, or the window of it the cue asks for, cut once and cached.
func _sfx_stream(cue: Dictionary) -> AudioStream:
	var path: String = cue["path"]
	if is_zero_approx(cue["start"]) and is_zero_approx(cue["length"]):
		return _stream(path, false)
	var key := "%s#%.4f,%.4f,%.4f" % [path, cue["start"], cue["length"], cue["fade"]]
	if not _streams.has(key):
		var whole := _stream(path, false)
		var window := cut(whole as AudioStreamWAV, cue["start"], cue["length"], cue["fade"]) if whole is AudioStreamWAV else null
		if window == null:
			# The whole file rather than silence: a window that cannot be taken is a tuning problem,
			# and a cue that has gone quiet is harder to recognise as one.
			push_warning("Could not cut a window from '%s' (it needs an uncompressed 16-bit WAV); playing it whole" % path)
		_streams[key] = window if window != null else whole
	return _streams[key]

## A copy of source holding length seconds from start, with fade seconds ramped in at each end. A
## window seldom starts or ends where the waveform crosses zero, and a step there is a click; the
## ramps are what make a slice sound like a sound. 16-bit PCM only, hence compress/mode=0 on the WAV.
static func cut(source: AudioStreamWAV, start: float, length: float, fade: float) -> AudioStreamWAV:
	if source == null or source.format != AudioStreamWAV.FORMAT_16_BITS:
		return null
	var channels := 2 if source.stereo else 1
	var frame_bytes := 2 * channels
	var frames := source.data.size() / frame_bytes
	var rate := float(source.mix_rate)
	var first := clampi(roundi(start * rate), 0, frames)
	var count := frames - first
	if length > 0.0:
		count = mini(count, roundi(length * rate))
	if count <= 0:
		return null
	var out := source.data.slice(first * frame_bytes, (first + count) * frame_bytes)
	var ramp := mini(roundi(fade * rate), count / 2)
	for i in ramp:
		var gain := float(i) / float(ramp)
		for c in channels:
			var head := (i * channels + c) * 2
			out.encode_s16(head, int(out.decode_s16(head) * gain))
			var tail := ((count - 1 - i) * channels + c) * 2
			out.encode_s16(tail, int(out.decode_s16(tail) * gain))
	var window := AudioStreamWAV.new()
	window.format = source.format
	window.mix_rate = source.mix_rate
	window.stereo = source.stereo
	window.loop_mode = AudioStreamWAV.LOOP_DISABLED
	window.data = out
	return window

## Loads and caches a stream; a failed load is cached as null so it is reported once.
func _stream(path: String, loop: bool) -> AudioStream:
	if not _streams.has(path):
		var loaded: AudioStream = load(path) as AudioStream if ResourceLoader.exists(path) else null
		if loaded == null:
			push_warning("Could not load audio '%s'" % path)
		elif loop and "loop" in loaded:
			loaded.set("loop", true)
		_streams[path] = loaded
	return _streams[path]

## A category's bus, or Master when the layout has none.
static func bus_for(category: String) -> String:
	var bus := "SFX" if category == SFX else category.capitalize()
	return bus if AudioServer.get_bus_index(bus) >= 0 else "Master"
