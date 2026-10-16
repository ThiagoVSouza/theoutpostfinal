// Two triangles per tree: painted bare earth, pebbles and fallen leaves, feathered into meadow.
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
	vec3 near = texture(grass_map, p / grass_tile_size).rgb * grass_detail_gain;
	near = max(grass_mean + (near - grass_mean) * grass_detail_contrast, vec3(0.0));
	vec2 far_uv = (mat2(vec2(0.80, 0.60), vec2(-0.60, 0.80)) * p) / grass_macro_tile_size;
	vec3 far = texture(grass_macro_map, far_uv).rgb;
	return near * mix(vec3(1.0), far / grass_mean, grass_variation);
}

varying vec2 world_xz;
varying flat vec2 instance_offset;

void vertex() {
	world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
	// Computed at the four vertices, stable across camera movement and independent of instance IDs.
	instance_offset = fract(MODEL_MATRIX[3].xz * vec2(0.173, 0.319) + vec2(0.37, 0.61));
}

void fragment() {
	// The instance already rotates with its tree. Mirror and compress the artwork slightly
	// to break up repetition while keeping the worn centre beneath the trunk.
	vec2 q = UV - 0.5;
	q *= mix(vec2(-1.0), vec2(1.0), step(vec2(0.5), instance_offset));
	q *= vec2(1.0 + instance_offset.y * 0.12, 1.0 + instance_offset.x * 0.09);
	vec4 patch = texture(ground_patch, q + 0.5);
	vec3 ground = grass(world_xz);
	vec3 soil = patch.rgb * (0.76 + instance_offset.x * 0.10);
	// Blend to the exact grass colour before lighting; alpha only discards the empty border.
	// This keeps a soft edge in the opaque pass without transparent sorting or a hard ring.
	vec3 colour = mix(ground, soil, patch.a);
	ALBEDO = hold(colour);
	ALPHA = patch.a;
	ALPHA_SCISSOR_THRESHOLD = 0.015;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
