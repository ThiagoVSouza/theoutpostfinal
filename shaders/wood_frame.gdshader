// The board's wood frame: four mouldings meeting at mitred corners.
//
// The frame is four boxes sharing this one material, and the grain is decided from the world
// position rather than from each box's UVs. A point belongs to the east or west piece when it is
// farther from the centre on x than on z, otherwise to the north or south piece, so the pieces
// meet on the diagonals as a real mitre does, and the overlap of the boxes at the corners never
// shows.
//
// Grain runs along each piece. Its across coordinate continues from the top face down the walls,
// so a streak that reaches the edge carries on round it. Fine grain fades out once its period
// drops towards a pixel, which is what keeps the frame from shimmering at whole-board zoom.
shader_type spatial;
render_mode cull_back;

uniform float half_board = 50000.0;
uniform float frame_width = 2000.0;
uniform vec3 light_wood : source_color = vec3(0.56, 0.36, 0.20);
uniform vec3 dark_wood : source_color = vec3(0.27, 0.15, 0.07);
uniform vec3 seam_color : source_color = vec3(0.10, 0.05, 0.02);

varying vec3 world_position;

// Integer hash of a lattice point. A float hash (fract of a large product) loses most of its
// precision at these coordinates, and the compiler is free to round the same lattice point
// differently in neighbouring cells, which shows as hard seams across the grain.
float hash(vec2 p) {
	uvec2 q = uvec2(ivec2(p) + ivec2(65536)) * uvec2(1597334677u, 3812015801u);
	uint n = (q.x ^ q.y) * 1597334677u;
	return float(n >> 8u) * (1.0 / 16777216.0);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float total = 0.0;
	float amplitude = 0.5;
	for (int i = 0; i < 4; i++) {
		total += value_noise(p) * amplitude;
		p = p * 2.03 + vec2(17.0, 9.0);
		amplitude *= 0.5;
	}
	return total;
}

// A grain band pattern that fades to its mean once one period covers less than about two pixels.
float bands(float x, float pixel_width) {
	float fade = 1.0 - smoothstep(0.25, 0.5, pixel_width);
	return mix(0.5, 0.5 + 0.5 * sin(x * 6.2831853), fade);
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 p = world_position;
	bool along_z = abs(p.x) > abs(p.z);
	float piece = along_z ? (p.x > 0.0 ? 1.0 : 2.0) : (p.z > 0.0 ? 3.0 : 4.0);
	// Along the piece and across it, in frame widths. Across is 0 at the board edge and 1 at the
	// frame's outer edge on the top face, and keeps counting down the walls through y.
	float along = (along_z ? p.z : p.x) / frame_width + piece * 37.0;
	float across = ((along_z ? abs(p.x) : abs(p.z)) - half_board + p.y) / frame_width;

	// Broad figure: slow colour drift along the piece, and a warp that bends the grain lines.
	float figure = fbm(vec2(along * 0.35, across * 2.5));
	float warp = fbm(vec2(along * 0.9, across * 1.4) + 5.0);
	float grain_x = across * 26.0 + warp * 3.5 + figure * 2.0;
	float grain = bands(grain_x, fwidth(grain_x));
	float fibre_x = across * 140.0 + warp * 12.0 + value_noise(vec2(along * 6.0, across * 40.0)) * 2.0;
	float fibre = bands(fibre_x, fwidth(fibre_x));

	float tone = clamp(figure * 0.9 + grain * 0.35 + fibre * 0.12 - 0.15, 0.0, 1.0);
	vec3 color = mix(dark_wood, light_wood, tone);

	// The mitre: a thin dark joint on the corner diagonals, at least a pixel wide at any zoom.
	if (min(abs(p.x), abs(p.z)) > half_board) {
		float off_diagonal = abs(abs(p.x) - abs(p.z));
		float joint = max(6.0, fwidth(off_diagonal) * 1.2);
		color = mix(color, seam_color, 1.0 - smoothstep(joint * 0.5, joint, off_diagonal));
	}

	ALBEDO = color;
	ROUGHNESS = 0.55 - grain * 0.1;
	SPECULAR = 0.35;
}
