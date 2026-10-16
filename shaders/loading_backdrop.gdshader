shader_type canvas_item;
render_mode unshaded;

// A quiet, static material. No animated noise or extra image dependencies at startup.
float grain(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 p = UV - vec2(0.5, 0.42);
	float vignette = smoothstep(0.12, 0.72, length(p * vec2(1.05, 1.0)));
	vec3 colour = mix(vec3(0.175, 0.145, 0.102), vec3(0.063, 0.060, 0.049), vignette);
	vec2 pixel = FRAGCOORD.xy;
	float fine = grain(floor(pixel)) - 0.5;
	float fibre = grain(vec2(floor(pixel.x / 3.0), floor(pixel.y / 94.0))) - 0.5;
	colour += fine * 0.018 + fibre * 0.005;
	// Keep inherited modulation so the whole screen fades into the rendered world together.
	COLOR = vec4(colour, 1.0) * COLOR;
}
