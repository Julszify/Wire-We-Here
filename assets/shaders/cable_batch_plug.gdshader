shader_type spatial;
render_mode diffuse_toon, specular_toon;
// Stecker der ruhenden Kabel eines Blocks. UV.x = Nummer des Kabels im Block (ausblenden wie cable_batch).

uniform sampler2D hidden_tex : filter_nearest;

void vertex() {
	int idx = int(round(UV.x));
	if (texelFetch(hidden_tex, ivec2(idx, 0), 0).r > 0.5) {
		VERTEX = vec3(0.0);
	}
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.3;
	METALLIC = 0.1;
	CLEARCOAT = 0.4;
}
