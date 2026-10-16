class_name StatsOverlay
extends CanvasLayer
## Frame stats in the top-right corner: FPS, GPU core clock and GPU render time, and below them
## whatever rows the scene supplies through extra_rows.
##
## GPU ms is the engine's own timing of this viewport, averaged over each refresh so the number
## is readable rather than flickering frame to frame. The clock comes from nvidia-smi through
## GpuClock, because Godot has no API for it. It is only shown when Godot is actually rendering
## on the NVIDIA GPU: on a hybrid laptop the game can land on the integrated GPU while nvidia-smi
## still reports the discrete one, and that clock would describe a GPU doing none of the work.

const REFRESH_SECONDS := 0.25
const ROW := "%-10s%12s"

## Returns an Array of [name, value] pairs, drawn under the frame stats. Unset, nothing is drawn.
var extra_rows: Callable
var gpu_clock := GpuClock.new()
var label: Label
var on_nvidia := false
var elapsed := 0.0
var gpu_total := 0.0
var samples := 0

func _ready() -> void:
	layer = 50
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	on_nvidia = "NVIDIA" in RenderingServer.get_video_adapter_vendor().to_upper()
	if on_nvidia: gpu_clock.start()
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UITheme.panel_style())
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.offset_left = -16
	panel.offset_right = -16
	panel.offset_top = 16
	add_child(panel)
	label = UITheme.label("", 14, UITheme.BRIGHT)
	label.add_theme_font_override("font", _monospace())
	panel.add_child(label)
	_refresh()

## Must stop the poll thread before leaving the tree, or Godot reports a leaked thread.
func _exit_tree() -> void:
	gpu_clock.stop()

func _process(delta: float) -> void:
	gpu_total += RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid())
	samples += 1
	elapsed += delta
	if elapsed >= REFRESH_SECONDS:
		_refresh()

func _refresh() -> void:
	var gpu_ms := gpu_total / samples if samples > 0 else 0.0
	var megahertz := gpu_clock.megahertz() if on_nvidia else -1
	var clock := "%d MHz" % megahertz if megahertz > 0 else "n/a"
	var lines: Array[String] = [
		ROW % ["FPS", str(roundi(Engine.get_frames_per_second()))],
		ROW % ["GPU clock", clock],
		ROW % ["GPU", "%.2f ms" % gpu_ms],
	]
	if extra_rows.is_valid():
		lines.append("")
		for row: Array in extra_rows.call():
			lines.append(ROW % [row[0], row[1]])
	label.text = "\n".join(lines)
	elapsed = 0.0
	gpu_total = 0.0
	samples = 0

## Fixed-width digits so the numbers do not jitter sideways as they change.
static func _monospace() -> SystemFont:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Consolas", "Cascadia Mono", "Menlo", "monospace"])
	return font
