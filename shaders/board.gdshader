// The board's surface: ocean, one test land mass of grassland, and the tile and subtile grid over
// both.
//
// The sea is TheOutpostMap2's grid_water.gdshader with everything about coasts taken out: its
// deep-water colour and its baked sheen. Map2 measures in units of 5.7735 m; every size here has
// been converted to metres.
//
// The land is drawn by this same shader rather than by a mesh of its own, so the board stays one
// quad, the grid crosses the coast without a join, and nothing is discarded (discards cost Map2 3.3
// ms of its 16 ms frame). The grass is Astra's highland-meadow ground made into a repeating tile by
// tools/make_grass_tile.gd. Its cost is in texture reads, not maths: Map2's investigation found the
// ground's textures cost about 1 ms all told and its noise and loops about 8.
//
// The test land mass is flat and its outline is a circle bent by a few sine waves around it, cheap
// enough to evaluate per pixel. A real map will come from authored data instead.
//
// The sea keeps one colour at every level of detail. Map2 faded its sheen to nothing and then
// blended to a brighter strategic-map ocean, so its sea changed colour twice on the way out: darker
// once the glitter had gone, then much lighter at the top. Here the glitter fades to its own
// average instead, which is what the eye sees of it from far away anyway, and that colour carries
// on to the top level.
//
// Lit, as in Map2, so the sea and grass take shadows. It costs about 0.25 ms a frame with the sea
// filling a 2560 x 1080 screen; unshaded halves that.
//
// The scene is lit and tonemapped like the models' viewer (ACES, a hemisphere sky, a sun and a rim
// light; see main.tscn), which is brighter and more contrasted than the lighting the sea and grass
// colours were chosen under. They are held to the colours they had: the colour each would have
// shown under the old lighting is worked out first, then turned into the albedo that, under the new
// lighting and through the ACES curve, shows that same colour. It holds where the Sun reaches;
// shadows on the ground follow the new lighting, as everything else on the board does. The canopy
// painted at the Distant level is not held, so it matches the trees it stands in for.
//
// The grid functions come from TheOutpostMap's map_grid.gdshaderinc. They are written out here
// rather than included: in Godot 4.7.1 a shader include read on the loading screen's loader thread
// leaves a loader object behind, reported as a leaked instance at exit. Once a second surface needs
// the grid it should become a shared include again, with that leak dealt with first.
shader_type spatial;
render_mode diffuse_burley, cull_back;

// R is the chop's glitter and G the broad swell bands it clusters along, both lit from the south
// east and baked by Map2's tools/build_water_sheen.gd. The sea's apparent light direction lives in
// this texture rather than in the scene's Sun; see Map2's docs/sun-and-sheen.md.
uniform sampler2D sheen_map : filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 sheen_tint : source_color = vec4(0.76, 0.87, 0.85, 1.0);
uniform float sheen_strength = 0.22;
// Metres covered by one edge of the sheen tile: Map2's 24 units.
uniform float sheen_world_size = 138.564;
// The average of glitter * (0.55 + 0.8 * band) over the sheen tile, measured from the imported
// texture: mean R 0.161 and mean G 0.486, independent because the two are sampled at unrelated
// positions. Re-measure it if the tile is ever rebaked.
uniform float sheen_mean = 0.151;
uniform vec4 deep_color : source_color = vec4(0.035, 0.20, 0.32, 1.0);

uniform sampler2D grass_map : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_macro_map : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
// Small tuft detail repeats over 30 m. The soft source keeps its original meadow-scale period,
// using the same two texture reads as before the visual pass.
uniform vec2 grass_tile_size = vec2(30.0, 27.5);
uniform vec2 grass_macro_tile_size = vec2(657.0, 602.25);
// Ratio of measured linear-light means (old / detail), so the added blades do not regrade the map.
uniform vec3 grass_detail_gain = vec3(1.111900, 1.146304, 1.123724);
// The tile's mean colour, printed by tools/make_grass_tile.gd. The large-scale variation is divided
// by it, so the grass averages to the same colour at every zoom.
uniform vec3 grass_mean : source_color = vec3(0.5058, 0.4979, 0.2848);
// How strongly a second, much larger copy of the tile varies the grass, breaking up the 90 m
// repeat. At 0 the repeat shows as a lattice from a kilometre up.
uniform float grass_variation = 0.6;
// Slightly stronger local pigment variation helps the meadow read at settlement scale without
// adding geometry, repeated procedural spots, or another texture lookup. The mean is preserved.
uniform float grass_detail_contrast = 1.08;

// Holding the sea and grass to their old colours (see the header). The lights are measured, not
// derived, by drawing a flat upward-facing albedo under each lighting with the tonemap off: under
// the old lighting it showed as albedo x old_light, under the viewer's as albedo x new_light. The
// tonemap's exposure and white come from the scene's Environment; hold_colours is off when the
// tonemap is not ACES, since the inverse below is ACES's.
uniform bool hold_colours = false;
uniform vec3 old_light = vec3(1.057, 1.042, 1.021);
uniform vec3 new_light = vec3(1.69575, 1.67591, 1.34783);
uniform float tonemap_exposure = 1.0;
uniform float tonemap_white = 1.0;

// Godot 4.7's ACES (servers/rendering/renderer_rd/shaders/effects/tonemap.glsl), run backwards:
// from the colour wanted on screen, in linear light, to the scene radiance that produces it.
const float ACES_A = 0.0245786;
const float ACES_B = 0.000090537;
const float ACES_C = 0.983729;
const float ACES_D = 0.432951;
const float ACES_E = 0.238081;
const float ACES_BIAS = 1.8;
const mat3 ACES_RGB_TO_RRT = mat3(
		vec3(0.59719, 0.35458, 0.04823) * ACES_BIAS,
		vec3(0.07600, 0.90834, 0.01566) * ACES_BIAS,
		vec3(0.02840, 0.13383, 0.83777) * ACES_BIAS);
const mat3 ACES_ODT_TO_RGB = mat3(
		vec3(1.60475, -0.53108, -0.07367),
		vec3(-0.10208, 1.10813, -0.00605),
		vec3(-0.00327, -0.07276, 1.07602));

float aces_fit(float x) {
	return (x * (x + ACES_A) - ACES_B) / (x * (ACES_C * x + ACES_D) + ACES_E);
}

vec3 aces_inverse(vec3 shown) {
	float white = aces_fit(tonemap_white * ACES_BIAS);
	vec3 fitted = clamp((shown * white) * inverse(ACES_ODT_TO_RGB), vec3(0.0), vec3(1.0 / ACES_C - 0.001));
	// fitted = (x (x + A) - B) / (x (C x + D) + E), solved for the positive root in x.
	vec3 a = fitted * ACES_C - 1.0;
	vec3 b = fitted * ACES_D - ACES_A;
	vec3 c = fitted * ACES_E + ACES_B;
	vec3 x = (-b - sqrt(b * b - 4.0 * a * c)) / (2.0 * a);
	return (x * inverse(ACES_RGB_TO_RRT)) / tonemap_exposure;
}

// The albedo that shows, under the current lighting, what old_albedo showed under the old one.
vec3 hold(vec3 old_albedo) {
	if (!hold_colours) return old_albedo;
	return max(aces_inverse(old_albedo * old_light), vec3(0.0)) / new_light;
}

// The forest painted into the grass from the Overview level out, where the tree meshes are hidden:
// a canopy map built by Forest from the trees' own positions, RGB their crowns' colour and alpha
// how much of the ground they cover. forest_paint is 1 while it shows and 0 otherwise.
uniform sampler2D forest_map : source_color, filter_linear_mipmap, repeat_disable;
uniform vec2 forest_origin = vec2(0.0);
uniform float forest_size = 1.0;
uniform float forest_paint = 0.0;

// The test land mass: a circle of land_radius metres around land_centre, its edge pushed in and
// out by sine waves of 2 to 11 bumps around it, each as a fraction of the radius.
uniform vec2 land_centre = vec2(0.0);
uniform float land_radius = 1800.0;
uniform float land_amplitude[6];
uniform float land_phase[6];
const float LAND_LOBES[6] = float[](2.0, 3.0, 4.0, 5.0, 7.0, 11.0);

// Driven by ViewLod: how much of the glitter's detail to draw, and how much of the grid belongs to
// the current level of detail.
uniform float sheen_fade = 1.0;
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

// Roughly how far inside the test land mass p is, in metres: positive on land, negative at sea.
// Measured along the radius rather than to the nearest point of the edge, which is exact enough to
// anti-alias the coast against.
float land_inland(vec2 p) {
	vec2 offset = p - land_centre;
	float angle = atan(offset.y, offset.x);
	float edge = 1.0;
	for (int i = 0; i < 6; i++) {
		edge += land_amplitude[i] * sin(LAND_LOBES[i] * angle + land_phase[i]);
	}
	return edge * land_radius - length(offset);
}

vec3 sea(vec2 p) {
	// Two copies of the sheen tile at mismatched scales and drift rates: the glitter in R rides
	// through the broad bands in G, and the periods never line up, so the tile does not read as a
	// grid. The second copy is turned as well as rescaled, or both copies' swell bands run parallel
	// and reinforce into diagonal corduroy across the whole sea. Once its detail has faded out, the
	// texture reads are skipped and only its average is left.
	float sheen = sheen_mean;
	if (sheen_fade > 0.0) {
		float glitter = texture(sheen_map, (p - GLITTER_DRIFT * TIME) / sheen_world_size).r;
		vec2 band_uv = (mat2(vec2(0.53, 0.85), vec2(-0.85, 0.53)) * (p + BAND_DRIFT * TIME))
			/ (sheen_world_size * 1.63);
		float band = texture(sheen_map, band_uv).g;
		sheen = mix(sheen_mean, glitter * (0.55 + 0.8 * band), sheen_fade);
	}
	// Added to the albedo rather than the emission, so shadows can still put the sparkle out.
	return deep_color.rgb + sheen_tint.rgb * sheen * sheen_strength;
}

vec3 grass(vec2 p) {
	vec3 near = texture(grass_map, p / grass_tile_size).rgb * grass_detail_gain;
	near = max(grass_mean + (near - grass_mean) * grass_detail_contrast, vec3(0.0));
	// The soft original tile gives broad patches without enlarging individual grass blades.
	vec2 far_uv = (mat2(vec2(0.80, 0.60), vec2(-0.60, 0.80)) * p) / grass_macro_tile_size;
	vec3 far = texture(grass_macro_map, far_uv).rgb;
	return near * mix(vec3(1.0), far / grass_mean, grass_variation);
}

// The painted canopy over the grass at p: RGB its colour, alpha how much of the ground it covers.
vec4 canopy(vec2 p) {
	vec2 uv = (p - forest_origin) / forest_size;
	if (any(lessThan(uv, vec2(0.0))) || any(greaterThan(uv, vec2(1.0)))) return vec4(0.0);
	return texture(forest_map, uv);
}

// The grid's colour, held like the ground it is drawn on. The same for every pixel, so it is worked
// out once a vertex rather than once a pixel.
varying vec3 held_grid_color;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	held_grid_color = hold(grid_color);
}

void fragment() {
	vec2 p = world_position.xz;
	float inland = land_inland(p);
	// About one pixel of blend across the coast, at any zoom.
	float reach = max(fwidth(inland), 0.001);
	float land = smoothstep(-reach * 0.5, reach * 0.5, inland);
	vec3 ground = vec3(0.0);
	if (land < 1.0) ground += sea(p) * (1.0 - land);
	if (land > 0.0) ground += grass(p) * land;
	vec3 color = hold(ground);
	if (forest_paint > 0.0 && land > 0.0) {
		vec4 crowns = canopy(p);
		color = mix(color, crowns.rgb, crowns.a * forest_paint * land);
	}
	if (grid_enabled && grid_fade > 0.0) {
		// Metres per pixel along the worse screen axis; under a tilted camera the two differ.
		float footprint = max(length(dFdx(p)), length(dFdy(p)));
		color = mix(color, held_grid_color, map_grid(p, footprint) * grid_fade);
	}
	ALBEDO = color;
	// Shaded flat. The sea's directional read comes from the sheen tile, not from the Sun; a real
	// wave normal would track the Sun and undo that. The test land mass is flat as well.
	NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	// No specular: measured on the flat board under the old lighting it added nothing, and under the
	// viewer's sun and rim it would add a sheen the held colours do not account for.
	ROUGHNESS = mix(0.42, 1.0, land);
	SPECULAR = 0.0;
}
