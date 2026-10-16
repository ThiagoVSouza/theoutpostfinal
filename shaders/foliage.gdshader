// Foliage cards for the current tree set: alpha-cut and double-sided, drawn as the models' viewer
// draws them (TheOutpostModels viewer/foliage-material.js).
//
// Most species' cards carry normals that describe the whole crown's volume rather than a leaf
// surface; their GLB materials say so with outpostFoliageNormalMode "volume". Godot, like three.js,
// reverses a double-sided surface's normal on its back face, which for those cards turns the far
// side of every card near black, so for them that reversal is undone. Cards without the mark (the
// pine's) keep the ordinary reversal: their normals are the card's own, and undoing it would light
// their back faces from the wrong side.
shader_type spatial;
render_mode cull_disabled, diffuse_burley;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform float alpha_cutoff = 0.5;
uniform float roughness = 0.9;
uniform bool volume_normals = false;

void fragment() {
	vec4 color = texture(albedo_texture, UV) * albedo_color;
	ALBEDO = color.rgb;
	ALPHA = color.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cutoff;
	ROUGHNESS = roughness;
	if (volume_normals && !FRONT_FACING) {
		NORMAL = -NORMAL;
	}
}
