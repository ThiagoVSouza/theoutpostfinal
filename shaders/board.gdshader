// The board's surface: black for now, with the tile and subtile grid over it.
//
// The grid functions come from TheOutpostMap's map_grid.gdshaderinc. They are written out here
// rather than included: in Godot 4.7.1 a shader include read on the loading screen's loader thread
// leaves a loader object behind, reported as a leaked instance at exit. Once a second surface needs
// the grid it should become a shared include again, with that leak dealt with first.
shader_type spatial;
render_mode unshaded, cull_back;

uniform vec3 surface_color : source_color = vec3(0.0);
uniform vec3 grid_color : source_color = vec3(0.62, 0.60, 0.54);
uniform bool grid_enabled = true;
uniform float tile_size = 100.0;
uniform float subtile_size = 10.0;

varying vec3 world_position;

// One grid tier, a fixed width in pixels rather than in metres, so lines stay hairlines at every
// zoom instead of thickening into bands on the way in and aliasing into dashes on the way out.
//
// Each tier fades on its own cell size in pixels: fully drawn above sixteen pixels a cell, gone
// below five. TheOutpostMap fades between three and nine, but on a black board a tier at nine
// pixels a cell reads as a grey mesh rather than as lines. Zooming out hands the board from
// subtiles to tiles, and then to no grid at all once tiles are too small to read.
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
	vec3 color = surface_color;
	if (grid_enabled) {
		vec2 p = world_position.xz;
		// Metres per pixel along the worse screen axis; under a tilted camera the two differ.
		float footprint = max(length(dFdx(p)), length(dFdy(p)));
		color = mix(color, grid_color, map_grid(p, footprint));
	}
	ALBEDO = color;
}
