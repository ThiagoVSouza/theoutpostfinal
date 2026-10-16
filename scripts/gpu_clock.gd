class_name GpuClock
extends RefCounted
## Reads the GPU core clock in MHz, and the temperature, power draw and utilisation beside it.
##
## All four come from one nvidia-smi call, so the extra three are free. They exist because a
## frame time on a power-limited laptop GPU is meaningless without them: the same scene measures
## differently at 2900 MHz and at 1600 MHz, and an 80 W part under sustained load moves between
## the two. A comparison taken across a clock change is measuring the clock.
##
## Godot has no API for clock frequency, so this shells out to nvidia-smi. That makes it
## NVIDIA-only: on any other GPU the first call fails, the poll stops, and callers get -1 so
## they can leave the field out rather than show a permanently empty number.
##
## The call spawns a process and blocks for tens of milliseconds, so it runs on its own
## thread and the main thread only ever reads the last value behind a mutex.

## Default cadence. A benchmark sampling for a couple of seconds should lower it, or it gets
## one reading per case and cannot report a range.
const POLL_SECONDS := 1.0
const SLICE_MSEC := 50

var poll_seconds := POLL_SECONDS

var _thread: Thread
var _mutex := Mutex.new()
var _megahertz := -1
var _celsius := -1
var _watts := -1.0
var _utilisation := -1
var _running := false

func start() -> void:
	if _thread != null: return
	_set_running(true)
	_thread = Thread.new()
	_thread.start(_poll)

## Must be called before the owner leaves the tree, or Godot reports a leaked thread.
func stop() -> void:
	_set_running(false)
	if _thread != null and _thread.is_started(): _thread.wait_to_finish()
	_thread = null

## The last reading in MHz, or -1 when no clock is available.
func megahertz() -> int:
	_mutex.lock()
	var value := _megahertz
	_mutex.unlock()
	return value


## Degrees Celsius, watts and percent utilisation from the same reading, or -1 if unavailable.
func celsius() -> int:
	_mutex.lock()
	var value := _celsius
	_mutex.unlock()
	return value


func watts() -> float:
	_mutex.lock()
	var value := _watts
	_mutex.unlock()
	return value


func utilisation() -> int:
	_mutex.lock()
	var value := _utilisation
	_mutex.unlock()
	return value

func _set_running(value: bool) -> void:
	_mutex.lock()
	_running = value
	_mutex.unlock()

func _is_running() -> bool:
	_mutex.lock()
	var value := _running
	_mutex.unlock()
	return value

func _poll() -> void:
	while _is_running():
		var reading := _read()
		_mutex.lock()
		_megahertz = int(reading[0])
		_celsius = int(reading[1])
		_watts = float(reading[2])
		_utilisation = int(reading[3])
		_mutex.unlock()
		# No clock here, and that will not change while the app runs: stop spawning processes.
		if _megahertz < 0: return
		var waited := 0.0
		while _is_running() and waited < poll_seconds:
			OS.delay_msec(SLICE_MSEC)
			waited += SLICE_MSEC / 1000.0

## Returns [megahertz, celsius, watts, utilisation]; megahertz is -1 with no NVIDIA GPU.
func _read() -> Array:
	var output := []
	var code := OS.execute("nvidia-smi",
		["--query-gpu=clocks.current.graphics,temperature.gpu,power.draw,utilization.gpu",
		"--format=csv,noheader,nounits"], output)
	if code != 0 or output.is_empty(): return [-1, -1, -1.0, -1]
	# One line per GPU; the first is the one Godot is rendering on in the common case.
	# String.chr(10) rather than a newline escape: this file is generated through several
	# layers of quoting and the escape does not survive them.
	var text: String = str(output[0]).split(String.chr(10))[0].strip_edges()
	var fields := text.split(",")
	if fields.size() < 4: return [-1, -1, -1.0, -1]
	var clock := fields[0].strip_edges()
	if not clock.is_valid_int(): return [-1, -1, -1.0, -1]
	return [clock.to_int(), fields[1].strip_edges().to_int(),
		fields[2].strip_edges().to_float(), fields[3].strip_edges().to_int()]
