shader_type sky;
// Himmel im Spielzeug-Look: weicher Verlauf, Sonne mit Schein, flauschige Wolken (stehen still,
// damit das Umgebungslicht nur einmal berechnet werden muss).

uniform vec3 top_color : source_color = vec3(0.16, 0.42, 0.88);
uniform vec3 horizon_color : source_color = vec3(0.74, 0.87, 0.98);
uniform vec3 ground_color : source_color = vec3(0.5, 0.58, 0.55);
uniform vec3 cloud_color : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 cloud_shade : source_color = vec3(0.72, 0.8, 0.92);
uniform float cloud_cover : hint_range(0.0, 1.0) = 0.48;
uniform float cloud_scale = 1.1;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	float a = 0.5;
	float s = 0.0;
	for (int i = 0; i < 5; i++) {
		s += a * noise(p);
		p = p * 2.03 + vec2(17.0, 9.0);
		a *= 0.5;
	}
	return s;
}

void sky() {
	vec3 d = EYEDIR;
	vec3 col = mix(horizon_color, top_color, pow(clamp(d.y, 0.0, 1.0), 0.55));
	if (d.y < 0.0) {
		col = mix(horizon_color, ground_color, clamp(-d.y * 5.0, 0.0, 1.0));
	}
	if (LIGHT0_ENABLED) {
		float along = max(dot(d, LIGHT0_DIRECTION), 0.0);
		col += LIGHT0_COLOR * 0.22 * pow(along, 24.0);
		col += vec3(1.0, 0.96, 0.85) * smoothstep(0.9993, 0.9997, along) * 6.0;
	}
	if (d.y > 0.015) {
		vec2 uv = d.xz / (d.y + 0.18) * cloud_scale;
		float c = fbm(uv);
		float m = smoothstep(1.0 - cloud_cover, 1.0 - cloud_cover + 0.16, c);
		float inner = smoothstep(1.0 - cloud_cover + 0.08, 1.0 - cloud_cover + 0.4, c);
		m *= smoothstep(0.015, 0.16, d.y);
		col = mix(col, mix(cloud_color, cloud_shade, inner * 0.8), m * 0.92);
	}
	COLOR = col;
}
