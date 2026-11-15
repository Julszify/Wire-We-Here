shader_type spatial;
// Umrisslinien als Nachbearbeitung (Spielzeug-Look): ein bildschirmfüllendes Rechteck vor der Kamera
// sucht Kanten in Tiefe und Normalen der undurchsichtigen Szene und zeichnet dort dunkle Linien.
// Tiefe: zweite Ableitung von 1/Tiefe (für ebene Flächen null, daher keine Linien auf Böden) und
// Silhouetten (Nachbar deutlich weiter vorn),
// Normalen: Knick zwischen Nachbarpixeln. In der Ferne blenden die Linien aus.
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled, cull_disabled, fog_disabled, shadows_disabled;

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform sampler2D normal_tex : hint_normal_roughness_texture, filter_nearest;
// Feste Werte statt Uniforms (Uniform-Standardwerte kamen beim per Code erzeugten Material nicht an)
const float thickness = 1.5;
const float depth_threshold = 0.035;
const float silhouette_threshold = 0.06;
const float normal_threshold = 0.45;
const float strength = 0.9;
const float fade_start = 40.0;
const float fade_end = 140.0;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

float view_depth(vec2 uv, mat4 inv_proj) {
	float d = texture(depth_tex, uv).r;
	vec4 v = inv_proj * vec4(uv * 2.0 - 1.0, d, 1.0);
	return -v.z / v.w;
}

vec3 view_normal(vec2 uv) {
	return normalize(texture(normal_tex, uv).xyz * 2.0 - 1.0);
}

void fragment() {
	vec2 px = thickness / VIEWPORT_SIZE;
	float d0 = view_depth(SCREEN_UV, INV_PROJECTION_MATRIX);
	float dl = view_depth(SCREEN_UV - vec2(px.x, 0.0), INV_PROJECTION_MATRIX);
	float dr = view_depth(SCREEN_UV + vec2(px.x, 0.0), INV_PROJECTION_MATRIX);
	float du = view_depth(SCREEN_UV - vec2(0.0, px.y), INV_PROJECTION_MATRIX);
	float dd = view_depth(SCREEN_UV + vec2(0.0, px.y), INV_PROJECTION_MATRIX);
	float w0 = 1.0 / d0;
	float lap = abs(1.0 / dl + 1.0 / dr - 2.0 * w0) + abs(1.0 / du + 1.0 / dd - 2.0 * w0);
	float depth_edge = step(depth_threshold, lap / w0);
	// Silhouette: ein Nachbar liegt deutlich weiter vorn (nur dann, damit die Linie außen am Objekt liegt)
	float front = min(min(dl, dr), min(du, dd));
	depth_edge = max(depth_edge, step(silhouette_threshold, (d0 - front) / d0));

	vec3 n0 = view_normal(SCREEN_UV);
	float nk = 0.0;
	nk = max(nk, 1.0 - dot(n0, view_normal(SCREEN_UV + vec2(px.x, 0.0))));
	nk = max(nk, 1.0 - dot(n0, view_normal(SCREEN_UV + vec2(0.0, px.y))));
	float normal_edge = step(normal_threshold, nk);

	float near_d = min(min(min(dl, dr), min(du, dd)), d0);
	float fade = clamp(1.0 - (near_d - fade_start) / (fade_end - fade_start), 0.0, 1.0);
	float a = max(depth_edge, normal_edge) * fade * strength;
	if (isnan(a) || isinf(a)) {
		a = 0.0;
	}
	ALBEDO = vec3(0.0);  // fast schwarz; eine Farbkonstante kam hier nicht an
	ALPHA = clamp(a, 0.0, 1.0);
}
