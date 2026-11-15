shader_type spatial;
// Bausatz-Teile (Dächer, Aufbauten, Schilder) mit Toon-Licht. Die Farbe je Gebäude kommt als
// Instanz-Zusatzdaten (INSTANCE_CUSTOM), damit feste Farben (Glas, Metall) nicht mit eingefärbt werden.
// Vertex-Alpha: 1,0 = einfärben, 0,8 = feste Farbe, 0,5 = einfärben und leuchten.
render_mode diffuse_toon, specular_toon;

varying vec3 tint;

void vertex() {
	tint = INSTANCE_CUSTOM.rgb;
}

void fragment() {
	vec3 c = pow(COLOR.rgb, vec3(2.2));
	float a = COLOR.a;
	float glow = step(a, 0.65);
	float tinted = 1.0 - step(0.7, a) * step(a, 0.9);
	c *= mix(vec3(1.0), pow(tint, vec3(2.2)), tinted);
	ALBEDO = c;
	EMISSION = c * glow * 2.2;
	ROUGHNESS = mix(0.7, 0.3, glow);
	SPECULAR = mix(0.15, 0.5, glow);
}
