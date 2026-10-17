// The imported bark material, with a short pigment transition at ground level.
// Geometry, normals and the material above stain_height are unchanged.
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform vec3 uv1_scale = vec3(1.0);
uniform vec3 uv1_offset = vec3(0.0);
uniform float roughness = 0.95;
uniform float metallic = 0.0;
uniform float specular = 0.5;
uniform float stain_height = 0.35;
uniform float moss_amount = 0.3;

varying vec3 local_position;

void vertex() {
	local_position = VERTEX;
}

void fragment() {
	vec2 bark_uv = UV * uv1_scale.xy + uv1_offset.xy;
	vec3 bark = texture(albedo_texture, bark_uv).rgb * albedo_color.rgb;
	if (local_position.y < stain_height) {
		// Uneven height and pigment prevent a horizontal painted band. The pattern stays
		// on the trunk as its existing instance transform rotates and scales the tree.
		float flecks = 0.5 + 0.5 * sin(local_position.x * 17.0 + local_position.z * 13.0
			+ sin(local_position.z * 23.0 - local_position.y * 7.0));
		float height = stain_height * (0.72 + 0.28 * flecks);
		float stain = 1.0 - smoothstep(0.018, height, max(local_position.y, 0.0));
		vec3 pigment = mix(vec3(0.67, 0.62, 0.49), vec3(0.56, 0.67, 0.40),
			moss_amount * smoothstep(0.25, 0.75, flecks));
		bark *= mix(vec3(1.0), pigment, stain * 0.75);
	}
	ALBEDO = bark;
	ROUGHNESS = roughness;
	METALLIC = metallic;
	SPECULAR = specular;
}
