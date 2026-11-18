// Kosmetik der Spielfigur (Tripo-Modell mit einer Textur): färbt Hoodie, Hose, Kopfhörer und Schuhe um.
// Die Teile werden an Farbton, Sättigung und Helligkeit der Textur erkannt, dazu an der Höhe am Körper
// (h: 0 = Füße, 1 = Scheitel, aus der Lage im Modell). Ziel-Farbe mit Alpha 0 = Teil bleibt wie es ist.
// Die Helligkeit der Textur bleibt erhalten (Falten, Schatten), nur Farbton und Sättigung wechseln.
shader_type spatial;
render_mode diffuse_toon, specular_toon;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform bool use_normal = false;
uniform float roughness = 0.7;
uniform float y_min = 0.0;
uniform float y_max = 1.0;
// sRGB-Werte (wie Color in GDScript), Alpha 0 = nicht umfärben
uniform vec4 hoodie_color = vec4(0.0);
uniform vec4 pants_color = vec4(0.0);
uniform vec4 headphones_color = vec4(0.0);
uniform vec4 shoes_color = vec4(0.0);

varying float h;

void vertex() {
	h = (VERTEX.y - y_min) / max(y_max - y_min, 0.0001);
}

vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

// Weiche Maske: 1 innerhalb [lo, hi], Rand `soft` breit
float band(float x, float lo, float hi, float soft) {
	return smoothstep(lo - soft, lo + soft, x) * (1.0 - smoothstep(hi - soft, hi + soft, x));
}

// Neue Farbe mit der Helligkeit der Vorlage (ref = typische Helligkeit des Teils)
vec3 recolor(vec3 src, vec4 target, float v, float ref, float mask) {
	vec3 to = target.rgb * clamp(v / ref, 0.25, 1.35);
	return mix(src, to, mask * target.a);
}

void fragment() {
	vec3 lin = texture(albedo_tex, UV).rgb;
	vec3 c = pow(lin, vec3(1.0 / 2.2));  // in sRGB vergleichen, wie die Farben im Bild aussehen
	vec3 hsv = rgb2hsv(c);
	float hue = hsv.x;
	float sat = hsv.y;
	float val = hsv.z;
	// Hoodie: kräftiges Blau am Oberkörper und an den Armen
	float m_hoodie = band(hue, 0.53, 0.67, 0.02) * smoothstep(0.3, 0.4, sat) * smoothstep(0.2, 0.3, val)
		* smoothstep(0.12, 0.2, h);
	// Schuhe: kräftiges Orange ganz unten
	float m_shoes = (band(hue, 0.0, 0.13, 0.015) + band(hue, 0.97, 1.0, 0.01)) * smoothstep(0.5, 0.6, sat)
		* smoothstep(0.45, 0.55, val) * (1.0 - smoothstep(0.12, 0.17, h));
	// Hose: dunkles Grau zwischen Schuhen und Hoodie
	float m_pants = (1.0 - smoothstep(0.18, 0.3, sat)) * band(val, 0.1, 0.55, 0.05) * band(h, 0.06, 0.4, 0.04);
	// Kopfhörer: helles, kühles Grau bis Silber am Kopf. Warme Töne (Haut, Haare) und Glanzpunkte bleiben,
	// sonst gibt es Sprenkel in Gesicht, Haaren und Augen
	float warm = (band(hue, 0.0, 0.17, 0.02) + band(hue, 0.92, 1.0, 0.02)) * smoothstep(0.04, 0.09, sat);
	float m_phones = (1.0 - smoothstep(0.16, 0.24, sat)) * band(val, 0.42, 0.86, 0.04) * smoothstep(0.66, 0.74, h)
		* (1.0 - warm);
	vec3 outc = c;
	outc = recolor(outc, hoodie_color, val, 0.82, m_hoodie);
	outc = recolor(outc, shoes_color, val, 0.95, m_shoes);
	outc = recolor(outc, pants_color, val, 0.38, m_pants);
	outc = recolor(outc, headphones_color, val, 0.75, m_phones);
	ALBEDO = pow(outc, vec3(2.2));
	ROUGHNESS = roughness;
	if (use_normal) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
	}
}
