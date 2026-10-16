// Foliage cards for the current tree set: alpha-cut, double-sided, with volume normals.
//
// The cards' normals describe the whole crown's volume, not a leaf surface (their GLB materials
// say so: outpostFoliageNormalMode "volume"). Godot, like three.js, reverses a double-sided
// surface's normal on its back face, which here turns the far side of every card near black. The
// models' own viewer undoes that reversal (TheOutpostModels viewer/foliage-material.js) and so does
// this, so a crown is lit the way it was authored.
//
// Alpha-tested foliage thins out with distance: the mip chain averages the cutout towards grey,
// more of it falls under the cutoff, and a crown shrinks to its branches. The cutout's alpha is
// scaled up with the mip level so a crown keeps its coverage as it gets smaller on screen.
shader_type spatial;
render_mode cull_disabled, diffuse_burley;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform float alpha_cutoff = 0.5;
uniform float roughness = 0.9;
// How much the alpha is raised per mip level, to hold coverage at a distance.
uniform float mip_coverage = 0.25;

void fragment() {
	vec4 color = texture(albedo_texture, UV) * albedo_color;
	float level = textureQueryLod(albedo_texture, UV).x;
	ALBEDO = color.rgb;
	ALPHA = color.a * (1.0 + max(level, 0.0) * mip_coverage);
	ALPHA_SCISSOR_THRESHOLD = alpha_cutoff;
	ROUGHNESS = roughness;
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
}
