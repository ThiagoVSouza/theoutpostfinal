// Foliage cards for the current tree set: alpha-cut and double-sided, drawn as the models' viewer
// draws them (TheOutpostModels viewer/foliage-material.js).
//
// The visual-pass cards carry normals that describe the whole crown's volume rather than a leaf
// surface; their GLB materials say so with outpostFoliageNormalMode "volume". Godot, like three.js,
// reverses a double-sided surface's normal on its back face, which for those cards turns the far
// side of every card near black, so for them that reversal is undone. Cards without the mark
// keep the ordinary reversal: their normals are the card's own, and undoing it would light
// their back faces from the wrong side.
//
// Alpha-cut foliage loses its crowns with distance. Each mip level averages the cutout's alpha
// with the gaps around it, so in the small mips most of a spray falls under the cutoff and is
// thrown away: at about 740 m of height only 13% of the 50,000-tree forest still read as leaves,
// against 50% once coverage is held. Coverage is held by raising alpha with the mip level, but
// only past mip_coverage_start. Below it, which covers every species at the closest zoom (the
// pine's 1536 atlas is read around mip 4 to 5 there), the cutout is exactly the authored one; an
// earlier version that raised alpha from mip 0 fattened the pine's needles into solid shapes.
shader_type spatial;
render_mode cull_disabled, diffuse_burley;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform float alpha_cutoff = 0.5;
uniform float roughness = 0.9;
uniform bool volume_normals = false;
// The mip level from which alpha is raised, and by how much per level past it.
uniform float mip_coverage_start = 5.0;
uniform float mip_coverage_rate = 0.45;

void fragment() {
	vec4 color = texture(albedo_texture, UV) * albedo_color;
	// Vertex colours carry soft, direction-independent bough occlusion. They do not bake
	// the sun into the texture, so rotating an instance still lights its correct side.
	ALBEDO = color.rgb * COLOR.rgb;
	float level = textureQueryLod(albedo_texture, UV).x;
	ALPHA = color.a * (1.0 + mip_coverage_rate * max(level - mip_coverage_start, 0.0));
	ALPHA_SCISSOR_THRESHOLD = alpha_cutoff;
	ROUGHNESS = roughness;
	if (volume_normals && !FRONT_FACING) {
		NORMAL = -NORMAL;
	}
}
