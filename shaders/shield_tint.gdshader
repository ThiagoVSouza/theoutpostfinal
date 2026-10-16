shader_type canvas_item;
render_mode unshaded;

// Colour only the neutral white field of the supplied shield, preserving its gold edging,
// antialiasing and original alpha. A later heraldic emblem can sit above this blank field.
uniform vec4 field_colour : source_color = vec4(0.16, 0.22, 0.16, 1.0);
varying vec4 vertex_colour;

void vertex() {
	vertex_colour = COLOR;
}

void fragment() {
	vec4 source = texture(TEXTURE, UV);
	float low = min(source.r, min(source.g, source.b));
	float high = max(source.r, max(source.g, source.b));
	float white_field = smoothstep(0.72, 0.94, low) * (1.0 - smoothstep(0.06, 0.18, high - low));
	vec3 colour = mix(source.rgb, source.rgb * field_colour.rgb, white_field);
	COLOR = vec4(colour, source.a * field_colour.a) * vertex_colour;
}
