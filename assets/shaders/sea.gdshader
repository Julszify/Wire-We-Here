shader_type spatial;
// Meer im Spielzeug-Look: zwei wandernde Wellenmuster als Normalen, heller am Ufer (flaches Wasser).
render_mode blend_mix, depth_draw_opaque, cull_back;

uniform vec3 deep_color : source_color = vec3(0.06, 0.3, 0.55);
uniform vec3 shallow_color : source_color = vec3(0.2, 0.62, 0.72);
uniform sampler2D waves : hint_normal, repeat_enable, filter_linear_mipmap;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform float wave_scale = 0.02;
uniform float wave_speed = 0.012;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = wpos.xz * wave_scale;
	vec3 n1 = texture(waves, uv + vec2(TIME * wave_speed, TIME * wave_speed * 0.6)).rgb;
	vec3 n2 = texture(waves, uv * 1.7 - vec2(TIME * wave_speed * 0.8, -TIME * wave_speed * 0.5)).rgb;
	NORMAL_MAP = normalize(n1 + n2 - 1.0) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 0.6;
	// Wassertiefe unter dem Pixel: flach = heller und durchsichtiger
	float d = texture(depth_tex, SCREEN_UV).r;
	vec4 upos = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, d, 1.0);
	float depth = clamp((VERTEX.z - upos.z / upos.w) / 6.0, 0.0, 1.0);
	ALBEDO = mix(shallow_color, deep_color, depth);
	ALPHA = mix(0.55, 0.93, depth);
	ROUGHNESS = 0.08;
	METALLIC = 0.0;
	SPECULAR = 0.6;
}
