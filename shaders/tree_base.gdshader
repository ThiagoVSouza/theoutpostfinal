// Two triangles per tree: broken soil, painted low greenery and stone facets, blended into meadow.
// One shared material, varied by the existing instance transform. No extra nodes or frame work.
// The ground/hold functions intentionally mirror board.gdshader: an include is avoided because
// this project's loader-thread shader-include issue is documented in that shader's header.
shader_type spatial;
render_mode diffuse_burley, cull_back;

uniform sampler2D grass_map : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_macro_map : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D ground_patch : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec2 grass_tile_size = vec2(30.0, 27.5);
uniform vec2 grass_macro_tile_size = vec2(657.0, 602.25);
uniform vec3 grass_detail_gain = vec3(1.111900, 1.146304, 1.123724);
uniform vec3 grass_mean : source_color = vec3(0.5058, 0.4979, 0.2848);
uniform float grass_variation = 0.6;
uniform float grass_detail_contrast = 1.08;
// The optional path matches newer Board shaders; legacy scenes keep the two-read meadow exactly.
uniform bool grass_blade_detail = false;
uniform float grass_cloud_contrast = 0.8;
uniform vec2 grass_blade_contrast = vec2(2.0, 1.3);
uniform vec2 grass_blades_fade = vec2(0.08, 0.4);
uniform float grass_far_contrast = 1.08;
uniform vec3 grass_grade = vec3(1.17, 1.17, 0.80);
uniform bool hold_colours = false;
uniform vec3 old_light = vec3(1.057, 1.042, 1.021);
uniform vec3 new_light = vec3(1.69575, 1.67591, 1.34783);
uniform float tonemap_exposure = 1.0;
uniform float tonemap_white = 1.0;

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

vec3 hold(vec3 albedo) {
	if (!hold_colours) return albedo;
	float white = aces_fit(tonemap_white * ACES_BIAS);
	vec3 fitted = clamp((albedo * old_light * white) * inverse(ACES_ODT_TO_RGB),
		vec3(0.0), vec3(1.0 / ACES_C - 0.001));
	vec3 a = fitted * ACES_C - 1.0;
	vec3 b = fitted * ACES_D - ACES_A;
	vec3 c = fitted * ACES_E + ACES_B;
	vec3 radiance = (-b - sqrt(b * b - 4.0 * a * c)) / (2.0 * a);
	return max((radiance * inverse(ACES_RGB_TO_RRT)) / tonemap_exposure, vec3(0.0)) / new_light;
}

vec3 grass(vec2 p) {
	vec2 uv = p / grass_tile_size;
	vec3 near = texture(grass_map, uv).rgb * grass_detail_gain;
	if (grass_blade_detail) {
		vec3 cloud = texture(grass_map, uv, 3.0).rgb * grass_detail_gain;
		vec3 detail = near - cloud;
		float sharpen = dot(detail, vec3(1.0)) < 0.0 ? grass_blade_contrast.x : grass_blade_contrast.y;
		float footprint = max(length(dFdx(p)), length(dFdy(p)));
		float far_fade = smoothstep(grass_blades_fade.x, grass_blades_fade.y, footprint);
		float blotches = mix(grass_cloud_contrast, grass_far_contrast, far_fade);
		float blades = mix(sharpen, grass_far_contrast, far_fade);
		near = max(grass_mean + (cloud - grass_mean) * blotches + detail * blades, vec3(0.0));
	} else {
		near = max(grass_mean + (near - grass_mean) * grass_detail_contrast, vec3(0.0));
	}
	vec2 far_uv = (mat2(vec2(0.80, 0.60), vec2(-0.60, 0.80)) * p) / grass_macro_tile_size;
	vec3 far = texture(grass_macro_map, far_uv).rgb;
	vec3 colour = near * mix(vec3(1.0), far / grass_mean, grass_variation);
	return grass_blade_detail ? colour * grass_grade : colour;
}

varying vec2 world_xz;
varying vec2 local_xz;
varying flat vec2 instance_offset;
varying flat vec2 root_radii;
varying flat vec2 root_centre;
varying flat float ground_family;

void vertex() {
	world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
	local_xz = VERTEX.xz;
	// Matches Forest.ROOT_RADIUS_SCALE (1 m); metadata is normalized for vertex colour packing.
	root_radii = max(COLOR.rg * 1.0, vec2(0.01));
	root_centre = UV2;
	ground_family = floor(COLOR.b * 3.0 + 0.5);
	// Computed at the four vertices, stable across camera movement and independent of instance IDs.
	instance_offset = fract(MODEL_MATRIX[3].xz * vec2(0.173, 0.319) + vec2(0.37, 0.61));
}

void fragment() {
	// TL airy broadleaf, TR earthier broadleaf, BL dry conifer, BR mossy willow.
	// The tree already rotates the patch; quarter-turns and mirroring add stable variation.
	vec2 cell = vec2(0.0);
	if (ground_family == 1.0) cell.x = step(0.28, instance_offset.y);
	if (ground_family >= 2.0) cell = vec2(ground_family - 2.0, 1.0);
	vec2 q = UV - 0.5;
	float turn = floor(instance_offset.x * 4.0);
	if (turn == 1.0) q = vec2(-q.y, q.x);
	if (turn == 2.0) q = -q;
	if (turn == 3.0) q = vec2(q.y, -q.x);
	q.x *= instance_offset.y < 0.5 ? -1.0 : 1.0;
	q *= vec2(1.0 + instance_offset.y * 0.08, 1.0 + instance_offset.x * 0.06);
	vec2 atlas_uv = (cell + clamp(q + 0.5, vec2(0.002), vec2(0.998))) * 0.5;
	vec4 patch = texture(ground_patch, atlas_uv);
	vec3 ground = grass(world_xz);
	vec3 soil = patch.rgb * (0.94 + instance_offset.x * 0.08);
	// Blend to the exact grass colour before lighting; alpha only discards the empty border.
	// Transparent holes keep grass between the painted islands, not just outside the outline.
	vec3 colour = mix(ground, soil, patch.a);
	vec2 root = (local_xz - root_centre) / root_radii;
	float angle = atan(root.y, root.x);
	float phase = instance_offset.y * 6.283185;
	float uneven = 0.014 * sin(angle * 5.0 + phase) + 0.009 * sin(angle * 9.0 - phase);
	float edge = (length(root) - 1.0) * min(root_radii.x, root_radii.y) - uneven;
	float aa = min(max(fwidth(edge), 0.008), 0.035);
	float seam = 1.0 - smoothstep(-0.018 - aa, 0.045 + aa, edge);
	// A contact accent only centimetres outside the measured wood, fading when subpixel.
	float footprint = max(length(dFdx(local_xz)), length(dFdy(local_xz)));
	seam *= 1.0 - smoothstep(0.08, 0.22, footprint);
	float contact_strength = 0.27 + 0.08 * sin(angle * 3.0 + phase);
	colour *= 1.0 - seam * contact_strength;
	ALBEDO = hold(colour);
	ALPHA = max(patch.a, seam);
	ALPHA_SCISSOR_THRESHOLD = 0.015;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
