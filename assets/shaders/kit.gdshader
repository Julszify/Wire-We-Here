shader_type spatial;
// Bausatz-Teile (Dächer, Aufbauten, Schilder) mit Toon-Licht. Die Farbe je Gebäude kommt als
// Instanz-Zusatzdaten (INSTANCE_CUSTOM), damit feste Farben (Glas, Metall) nicht mit eingefärbt werden.
// Vertex-Alpha: 1,0 = einfärben, 0,8 = feste Farbe, 0,5 = einfärben und leuchten.
// Dächer können eine Textur bekommen (use_roof_tex): Sie liegt in Weltkoordinaten auf den Dachflächen,
// Reihen laufen parallel zum First, und wird mit der Dachfarbe eingefärbt.
render_mode diffuse_toon, specular_toon;

uniform bool use_roof_tex = false;
uniform sampler2D roof_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
// Kantenlänge einer Kachel in Metern
uniform float roof_tile_m = 3.0;
// Ausgleich, damit die helle Textur die Dachfarbe nicht verdunkelt
uniform float roof_tex_gain = 1.3;

varying vec3 tint;
varying vec3 wpos;
varying vec3 wnorm;

void vertex() {
	tint = INSTANCE_CUSTOM.rgb;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	vec3 c = pow(COLOR.rgb, vec3(2.2));
	float a = COLOR.a;
	float glow = step(a, 0.65);
	float tinted = 1.0 - step(0.7, a) * step(a, 0.9);
	c *= mix(vec3(1.0), pow(tint, vec3(2.2)), tinted);
	if (use_roof_tex && a > 0.95) {
		vec3 n = normalize(wnorm);
		if (n.y > 0.2) {
			// Waagerechte Richtung entlang des Firsts, zweite Richtung die Dachschräge hinab
			vec3 t = abs(n.y) > 0.98 ? vec3(1.0, 0.0, 0.0) : normalize(cross(vec3(0.0, 1.0, 0.0), n));
			vec3 b = cross(n, t);
			vec2 uv = vec2(dot(wpos, t), dot(wpos, b)) / roof_tile_m;
			c *= texture(roof_tex, uv).rgb * roof_tex_gain;
		}
	}
	ALBEDO = c;
	EMISSION = c * glow * 2.2;
	ROUGHNESS = mix(0.7, 0.3, glow);
	SPECULAR = mix(0.15, 0.5, glow);
}
