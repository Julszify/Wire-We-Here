shader_type spatial;
// Stadt-Blockout im Spielzeug-Look: ein Material für Straßen, Zäune und Gebäude.
// Die Vertex-Farbe ist die Grundfarbe, ihr Alpha-Wert sagt, was die Fläche ist:
//   1.0 = einfarbig (Zaun, Tribüne, Kran)
//   0.5 = Gebäude: Fensterraster, Sockel, Dachkante, Dach (UV = Bodenhöhe, Gebäudehöhe; UV2.x = Fassadenstil:
//         0 Raster, 1 Büro, 2 Altstadt, 3 Läden, 4 Halle, 5 Rechenzentrum, 6 Hochhaus)
//   0.3 = Straße entlang x, 0.2 = Straße entlang z: gestrichelte Mittellinie (UV = Mittelachse quer, Breite)
//   0.1 = Hauptstraße als Band: Mittellinie und Randlinien (UV = Lage quer -1..1, Lage längs in Metern)
render_mode diffuse_toon, specular_toon;

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
		int style = int(UV2.x + 0.5);
		if (n.y > 0.5) {
			// Dach (meist von einem Bausatz-Dach verdeckt): dunkler
			col = mix(base * 0.5, vec3(0.3, 0.32, 0.36), 0.45);
		} else if (abs(n.y) < 0.5) {
			float u = abs(n.x) > 0.5 ? lpos.z : lpos.x;
			float bid = floor(UV.y * 7.0) + floor(UV.x * 3.0);
			// Stil-Werte: Geschosshöhe, Fensterbreite, Fensterrahmen (unten links / oben rechts im Feld)
			float fh = floor_height;
			float ww = window_width;
			vec2 lo = vec2(0.18, 0.3);
			vec2 hi = vec2(0.82, 0.82);
			if (style == 1) { fh = 3.6; ww = 2.4; lo = vec2(0.05, 0.22); hi = vec2(0.95, 0.86); }
			else if (style == 2) { fh = 3.2; ww = 2.6; lo = vec2(0.33, 0.26); hi = vec2(0.67, 0.82); }
			else if (style == 3) { fh = 3.4; ww = 2.8; lo = vec2(0.22, 0.3); hi = vec2(0.78, 0.8); }
			else if (style == 6) { fh = 3.8; ww = 1.6; lo = vec2(0.04, 0.1); hi = vec2(0.96, 0.92); }
			float ground_h = (style == 3 || style == 2) ? 4.2 : 0.6;
			vec2 cell = vec2(u / ww, (h - ground_h) / fh);
			vec2 f = fract(cell);
			vec2 id = floor(cell);
			float win = step(lo.x, f.x) * step(f.x, hi.x) * step(lo.y, f.y) * step(f.y, hi.y);
			win *= step(ground_h, h) * step(h, top - 1.0);
			if (style == 4 || style == 5) {
				win = 0.0;
			}
			float r = hash(id + n.xz * 13.0 + bid);
			vec3 glass = mix(glass_dark, glass_light, 0.15 + 0.5 * step(0.72, r) + 0.2 * r);
			if (style == 6 || style == 1) {
				glass = mix(vec3(0.32, 0.55, 0.78), vec3(0.62, 0.8, 0.95), 0.3 + 0.4 * r);
			}
			col = mix(base, glass, win);
			rough = mix(0.85, 0.08, win);
			if (style == 2) {
				// Altstadt: Fensterläden neben jedem Fenster, helles Gesims je Geschoss
				float shutter = (step(0.2, f.x) * step(f.x, 0.31) + step(0.69, f.x) * step(f.x, 0.8)) * step(lo.y, f.y) * step(f.y, hi.y);
				shutter *= step(ground_h, h) * step(h, top - 1.0);
				col = mix(col, vec3(0.18, 0.36, 0.26), shutter);
				col = mix(col, min(base * 1.3 + 0.08, vec3(1.0)), step(f.y, 0.07) * step(ground_h, h));
			}
			if (style == 2 || style == 3) {
				// Erdgeschoss: Schaufenster zwischen Pfeilern
				float gu = fract(u / 4.5);
				float shop = step(0.12, gu) * step(gu, 0.88) * step(0.35, h) * step(h, ground_h - 1.0);
				col = mix(col, mix(glass_dark, glass_light, 0.35), shop);
				rough = mix(rough, 0.08, shop);
				if (style == 3) {
					// bunter Schilderstreifen über dem Laden
					col = mix(col, base * 1.4 + vec3(0.1, 0.05, 0.15), step(ground_h - 0.9, h) * step(h, ground_h));
				}
			}
			if (style == 4) {
				// Halle: Fensterband oben, Rolltore unten
				float strip = step(top - 3.2, h) * step(h, top - 1.8) * step(0.08, fract(u / 2.0));
				col = mix(col, glass_light * 0.8, strip);
				float du = mod(u, 14.0);
				float gate = step(4.0, du) * step(du, 10.0) * step(h, 5.0);
				vec3 gate_col = vec3(0.55, 0.57, 0.6) * mix(0.85, 1.0, step(0.5, fract(h * 2.5)));
				col = mix(col, gate_col, gate);
			}
			if (style == 5) {
				// Rechenzentrum: senkrechte Lüftungsschlitze, helles Band oben
				float vent = step(0.75, fract(u / 1.5)) * step(1.5, h) * step(h, top - 2.0);
				col = mix(col, base * 0.55, vent);
				col = mix(col, vec3(0.3, 0.75, 0.95), step(top - 1.6, h) * step(h, top - 1.2));
			}
			if (style == 6) {
				// Hochhaus: Brüstungsbänder zwischen den Glasreihen
				col = mix(col, base * 0.85, (1.0 - win) * step(ground_h, h));
			}
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
