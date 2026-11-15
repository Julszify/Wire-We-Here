shader_type spatial;
// Stadt-Blockout im Spielzeug-Look: ein Material für Straßen, Zäune und Gebäude.
// Die Vertex-Farbe ist die Grundfarbe, ihr Alpha-Wert sagt, was die Fläche ist:
//   1.0 = einfarbig (Zaun, Tribüne, Kran)
//   0.5 = Gebäude: Fensterraster, Sockel, Dachkante, Dach (UV = Bodenhöhe, Gebäudehöhe)
//   0.3 = Straße entlang x, 0.2 = Straße entlang z: gestrichelte Mittellinie (UV = Mittelachse quer, Breite)
//   0.1 = Hauptstraße als Band: Mittellinie und Randlinien (UV = Lage quer -1..1, Lage längs in Metern)

uniform float floor_height = 3.3;
uniform float window_width = 3.0;
uniform vec3 glass_dark : source_color = vec3(0.13, 0.22, 0.36);
uniform vec3 glass_light : source_color = vec3(0.5, 0.72, 0.92);
uniform vec3 line_color : source_color = vec3(0.92, 0.9, 0.82);

varying vec3 lpos;
varying vec3 lnormal;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(41.3, 289.1))) * 43758.5453);
}

void vertex() {
	lpos = VERTEX;
	lnormal = NORMAL;
}

void fragment() {
	vec3 base = pow(COLOR.rgb, vec3(2.2));
	float kind = COLOR.a;
	vec3 n = normalize(lnormal);
	vec3 col = base;
	float rough = 0.85;
	if (kind > 0.4 && kind < 0.6) {
		float h = lpos.y - UV.x;
		float top = UV.y;
		if (n.y > 0.5) {
			// Dach: dunkler, mit hellem Rand
			col = mix(base * 0.5, vec3(0.3, 0.32, 0.36), 0.45);
		} else if (abs(n.y) < 0.5) {
			float u = abs(n.x) > 0.5 ? lpos.z : lpos.x;
			vec2 cell = vec2(u / window_width, (h - 0.6) / floor_height);
			vec2 f = fract(cell);
			vec2 id = floor(cell);
			float ground = step(cell.y, 1.0);
			// Erdgeschoss: breite Schaufenster, darüber Fenster mit Brüstung
			vec2 lo = mix(vec2(0.18, 0.3), vec2(0.08, 0.12), ground);
			vec2 hi = mix(vec2(0.82, 0.82), vec2(0.92, 0.8), ground);
			float win = step(lo.x, f.x) * step(f.x, hi.x) * step(lo.y, f.y) * step(f.y, hi.y);
			win *= step(0.6, h) * step(h, top - 1.2);
			float r = hash(id + n.xz * 13.0 + floor(UV.y));
			vec3 glass = mix(glass_dark, glass_light, 0.15 + 0.5 * step(0.72, r) + 0.2 * r);
			col = mix(base, glass, win);
			rough = mix(0.85, 0.12, win);
			// Sockel dunkler, Dachkante heller, Geschossbänder ganz leicht
			col = mix(col, base * 0.55, step(h, 0.6));
			col = mix(col, min(base * 1.25, vec3(1.0)), step(top - 0.7, h));
			col *= mix(1.0, 0.93, step(f.y, 0.06) * (1.0 - win) * step(0.6, h));
		}
	} else if (kind > 0.15 && kind < 0.35 && n.y > 0.5) {
		float across = (kind > 0.25 ? lpos.z : lpos.x) - UV.x;
		float along = kind > 0.25 ? lpos.x : lpos.z;
		// Abstand zur nächsten Kreuzung (UV2 = Ursprung, Rasterabstand): dort keine Linie, kein Gehweg
		float to_cross = abs(mod(along - UV2.x + UV2.y * 0.5, UV2.y) - UV2.y * 0.5);
		float open = step(UV.y * 0.5, to_cross);
		float dash = step(fract(along / 7.0), 0.45) * step(UV.y * 0.5 + 2.0, to_cross);
		col = mix(col, line_color, step(abs(across), 0.1) * dash);
		// heller Randstreifen als Gehweg
		col = mix(col, base * 1.55 + 0.05, step(UV.y * 0.5 - 1.6, abs(across)) * open);
	} else if (kind < 0.15 && n.y > 0.5) {
		float dash = step(fract(UV.y / 9.0), 0.5);
		col = mix(col, line_color, step(abs(UV.x), 0.02) * dash);
		col = mix(col, line_color, step(0.9, abs(UV.x)) * step(abs(UV.x), 0.94));
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = 0.0;
}
