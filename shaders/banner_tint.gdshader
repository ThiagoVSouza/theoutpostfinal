shader_type canvas_item;
render_mode unshaded;

// Give the dark cloth a warm brown hue while retaining its original texture and
// brightness. The brighter gold rules keep their source colours and alpha.
uniform vec4 fabric_colour : source_color = vec4(0.1882, 0.1569, 0.1137, 1.0);
varying vec4 vertex_colour;

void vertex() {
	vertex_colour = COLOR;
}

void fragment() {
	vec4 source = texture(TEXTURE, UV);
	vec3 weights = vec3(0.2126, 0.7152, 0.0722);
	float luminance = dot(source.rgb, weights);
	float fabric = 1.0 - smoothstep(0.18, 0.30, luminance);
	vec3 brown = fabric_colour.rgb * luminance / max(dot(fabric_colour.rgb, weights), 0.001);
	vec3 colour = mix(source.rgb, brown, fabric);
	COLOR = vec4(colour, source.a * fabric_colour.a) * vertex_colour;
}
