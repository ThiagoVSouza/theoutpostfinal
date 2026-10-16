class_name ViewLod
extends RefCounted
## The level of detail the view is at, decided from how big one 100 m tile is on screen.
##
## Taken from TheOutpostMap2's GridTileLodRuntime and grid_terrain_lod_config.gd, with the same
## four tiers, names and thresholds. The camera is orthographic, so apparent size depends only on
## the zoom, never on distance: one tier holds for the whole board at once.
##
## Tile pixels use Map2's metric, the tile's height on screen projected through the camera's up
## vector, so that a level here means the zoom range it means there. Each switch has a pair of
## thresholds, so a wheel step that lands on a boundary does not flicker between two tiers.
##
## The surface effects fade across their own ranges rather than switching with the tier, eased
## over time, because the wheel moves zoom in 12% steps and a fade driven by zoom alone would
## arrive in visible jumps.

enum Tier { DETAIL, DISTANT, OVERVIEW, STRATEGIC }
const NAMES := ["Detail", "Distant", "Overview", "Strategic"]
## Tile pixels at which each tier hands over to the next one out, and back in.
const EXIT_PIXELS := [48.0, 4.5, 1.5]
const ENTER_PIXELS := [60.0, 5.0, 1.6]

## The sea's glitter, from Map2: below about ten pixels a copy its fixed 138 m tile stops reading
## as glitter and reads as interference between two grids instead. It fades to its own average,
## so the sea keeps its colour. Map2's strategic-map blend is not taken: on an all-ocean board it
## only turned the sea a brighter blue at the top level.
const SHEEN_FADE_MIN_PIXELS := 70.0
const SHEEN_FADE_MAX_PIXELS := 115.0
## The grid belongs to the Detail and Distant tiers only. It is fully gone by the time the view
## crosses into Overview.
const GRID_NONE_PIXELS := 4.5
const GRID_FULL_PIXELS := 9.0
const FADE_SECONDS := 0.45

## Godot's default camera FOV, used to turn the orthographic zoom into a height.
const REFERENCE_FOV := 60.0

var tier := Tier.DETAIL
var tile_pixels := 0.0
var sheen_fade := 1.0
var grid_fade := 1.0
var _started := false

## Advances to the camera's current zoom. The first call snaps every fade to its target.
func update(camera: Camera3D, delta: float) -> void:
	var pixel_height := drawn_height(camera.get_viewport())
	var vertical := absf(camera.global_basis.y.dot(Vector3.UP))
	tile_pixels = WorldSpec.TILE * pixel_height / maxf(camera.size, 0.001) * vertical
	tier = desired_tier(tier, tile_pixels)
	var step := 1.0 if not _started else delta / FADE_SECONDS
	_started = true
	sheen_fade = move_toward(sheen_fade, smoothstep(SHEEN_FADE_MIN_PIXELS, SHEEN_FADE_MAX_PIXELS, tile_pixels), step)
	grid_fade = move_toward(grid_fade, smoothstep(GRID_NONE_PIXELS, GRID_FULL_PIXELS, tile_pixels), step)

## Pixels the 3D view is actually drawn at, vertically. Not the scaled UI height, and not
## get_texture().get_size() either: under the canvas_items stretch, in Godot 4.7.1, that reports
## 1167 for a frame drawn at 1080, the same 8% error TheOutpostMap2's LOD carries. The window's own
## size is what the frame is rendered at.
static func drawn_height(viewport: Viewport) -> float:
	if viewport is Window: return float((viewport as Window).size.y)
	if viewport is SubViewport: return float((viewport as SubViewport).size.y)
	return float(viewport.get_visible_rect().size.y)

static func desired_tier(current: int, pixels: float) -> int:
	var next := clampi(current, Tier.DETAIL, Tier.STRATEGIC)
	while next < Tier.STRATEGIC and pixels <= EXIT_PIXELS[next]:
		next += 1
	while next > Tier.DETAIL and pixels >= ENTER_PIXELS[next - 1]:
		next -= 1
	return next

## An orthographic camera has no meaningful altitude: zooming changes its size, not its height.
## This is the eye height a perspective camera at REFERENCE_FOV would need to frame the same
## ground, the figure Map2 reports as altitude.
static func height_metres(zoom: float) -> float:
	return (zoom * 0.5) / tan(deg_to_rad(REFERENCE_FOV * 0.5))
