shader_type spatial;
render_mode diffuse_toon, specular_toon;
// Ruhende Kabel eines Blocks (CableBatch): jeder Vertex liegt auf der Mittellinie, die Röhre entsteht hier.
// NORMAL = Richtung der Bahn, UV.x = Winkel auf dem Umfang (0..1), UV.y = Radius,
// COLOR.rgb = Farbe (linear), COLOR.a = Nummer des Kabels im Block / 255.
// hidden_tex: ein Pixel je Kabel, > 0,5 = ausgeblendet (gegriffen oder fertig).

uniform sampler2D hidden_tex : filter_nearest;

void vertex() {
	int idx = int(round(COLOR.a * 255.0));
	if (texelFetch(hidden_tex, ivec2(idx, 0), 0).r > 0.5) {
		VERTEX = vec3(0.0);
		NORMAL = vec3(0.0, 1.0, 0.0);
	} else {
		vec3 t = normalize(NORMAL);
		vec3 h = abs(t.y) < 0.9 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
		vec3 n = normalize(cross(h, t));
		vec3 b = cross(t, n);
		float a = UV.x * TAU;
		vec3 d = n * cos(a) + b * sin(a);
		VERTEX += d * UV.y;
		NORMAL = d;
	}
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.35;
	METALLIC = 0.05;
	CLEARCOAT = 0.4;
}
