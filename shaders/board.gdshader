// The board's surface: open ocean everywhere for now, with the tile and subtile grid over it.
//
// The sea is TheOutpostMap2's grid_water.gdshader with everything about coasts taken out, since
// there is no land yet: its deep-water colour, its baked sheen, and its strategic-map ocean at
// far zoom. Map2 measures in units of 5.7735 m; every size here has been converted to metres.
//
// Unlit. The sea is flat and the camera orthographic, so the Sun gave it one constant brightness
// across the whole board, and measured from captures that brightness was within 2% of the albedo
// itself: lighting cost half the surface's GPU time and changed nothing on screen. What it gives up
// is shadows: once something stands on the water and casts one, the sea will need lighting back,
// or a shadow term of its own.
//
// The grid functions come from TheOutpostMap's map_grid.gdshaderinc. They are written out here
// rather than included: in Godot 4.7.1 a shader include read on the loading screen's loader thread
// leaves a loader object behind, reported as a leaked instance at exit. Once a second surface needs
// the grid it should become a shared include again, with that leak dealt with first.
shader_type spatial;
render_mode unshaded, cull_back;

// R is the chop's glitter and G the broad swell bands it clusters along, both lit from the south
// east and baked by Map2's tools/build_water_sheen.gd. The sea's apparent light direction lives in
// this texture rather than in the scene's Sun; see Map2's docs/sun-and-sheen.md. That is why the
// sea can be unlit and still read as lit.
uniform sampler2D sheen_map : filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 sheen_tint : source_color = vec4(0.76, 0.87, 0.85, 1.0);
uniform float sheen_strength = 0.22;
// Metres covered by one edge of the sheen tile: Map2's 24 units.
uniform float sheen_world_size = 138.564;
uniform vec4 deep_color : source_color = vec4(0.035, 0.20, 0.32, 1.0);
uniform vec4 strategic_ocean : source_color = vec4(0.114, 0.290, 0.408, 1.0);

// Driven by ViewLod: how much glitter to draw, how far the surface has turned into the strategic
// map, and how much of the grid belongs to the current level of detail.
uniform float sheen_fade = 1.0;
uniform float strategic_blend = 0.0;
uniform float grid_fade = 1.0;

uniform vec3 grid_color : source_color = vec3(0.62, 0.60, 0.54);
uniform bool grid_enabled = true;
uniform float tile_size = 100.0;
uniform float subtile_size = 10.0;

// Drift of the two sheen layers in metres per second: Map2's (-0.31, 0.14) and (0.44, 0.19) units.
const vec2 GLITTER_DRIFT = vec2(-1.790, 0.808);
const vec2 BAND_DRIFT = vec2(2.540, 1.097);

varying vec3 world_position;

// One grid tier, a fixed width in pixels rather than in metres, so lines stay hairlines at every
// zoom instead of thickening into bands on the way in and aliasing into dashes on the way out.
//
// Each tier fades on its own cell size in pixels: fully drawn above sixteen pixels a cell, gone
// below five. TheOutpostMap fades between three and nine, but a tier at nine pixels a cell reads
// as a mesh rather than as lines. Zooming out hands the board from subtiles to tiles, and grid_fade
// then takes the grid away altogether past the Distant level.
float grid_line(vec2 p, float spacing, float footprint) {
	float cell_pixels = spacing / max(footprint, 0.0001);
	float legible = smoothstep(5.0, 16.0, cell_pixels);
	if (legible <= 0.0) {
		return 0.0;
	}
	vec2 to_line = abs(fract(p / spacing + 0.5) - 0.5) * spacing;
	float distance_m = min(to_line.x, to_line.y);
	return legible * (1.0 - smoothstep(footprint * 0.18, footprint * 0.75, distance_m));
}

// Tiles are drawn stronger than subtiles so the 100 m cells still read inside the 10 m ones.
// TheOutpostMap also had a 10 km region tier for whole-map zoom; the board does not need one.
float map_grid(vec2 p, float footprint) {
	float grid = grid_line(p, tile_size, footprint) * 0.7;
	grid = max(grid, grid_line(p, subtile_size, footprint) * 0.4);
	return grid;
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_position.xz;
	vec3 water = deep_color.rgb;
	// Two copies of the sheen tile at mismatched scales and drift rates: the glitter in R rides
	// through the broad bands in G, and the periods never line up, so the tile does not read as a
	// grid. The second copy is turned as well as rescaled, or both copies' swell bands run parallel
	// and reinforce into diagonal corduroy across the whole sea. Skipped once it has faded out.
	if (sheen_fade > 0.0) {
		float glitter = texture(sheen_map, (p - GLITTER_DRIFT * TIME) / sheen_world_size).r;
		vec2 band_uv = (mat2(vec2(0.53, 0.85), vec2(-0.85, 0.53)) * (p + BAND_DRIFT * TIME))
			/ (sheen_world_size * 1.63);
		float band = texture(sheen_map, band_uv).g;
		water += sheen_tint.rgb * glitter * (0.55 + 0.8 * band) * sheen_strength * sheen_fade;
	}
	vec3 color = mix(water, strategic_ocean.rgb, strategic_blend);
	if (grid_enabled && grid_fade > 0.0) {
		// Metres per pixel along the worse screen axis; under a tilted camera the two differ.
		float footprint = max(length(dFdx(p)), length(dFdy(p)));
		color = mix(color, grid_color, map_grid(p, footprint) * grid_fade);
	}
	ALBEDO = color;
}
