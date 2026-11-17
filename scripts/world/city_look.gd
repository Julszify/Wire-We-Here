class_name CityLook
extends RefCounted
## Gemeinsames Aussehen für Hauptszene und Stadt-Vorschau: Himmel mit Wolken, Sonnenlicht, Dunst,
## Leuchten heller Flächen und kräftigere Farben. Alles an einer Stelle, damit beide Szenen gleich aussehen.

const SKY_SHADER := "res://assets/shaders/sky_clouds.gdshader"


static func environment() -> Environment:
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var mat := ShaderMaterial.new()
	mat.shader = load(SKY_SHADER)
	sky.sky_material = mat
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	# Nur zum Teil vom Himmel: sonst werden alle Schatten kräftig blau
	e.ambient_light_sky_contribution = 0.3
	e.ambient_light_color = Color(0.86, 0.88, 0.94)
	e.ambient_light_energy = 0.8
	e.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = 1.05
	e.tonemap_white = 1.4
	# Weiche Schatten in Ecken und unter Kabeln
	e.ssao_enabled = true
	e.ssao_radius = 1.2
	e.ssao_intensity = 2.2
	# Helle Flächen (Lämpchen, wichtige Kabel, Himmel) strahlen leicht
	e.glow_enabled = true
	e.glow_intensity = 0.55
	e.glow_bloom = 0.06
	e.glow_hdr_threshold = 1.05
	e.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	# Dunst: ferne Viertel verblassen in die Himmelsfarbe
	e.fog_enabled = true
	e.fog_light_color = Color(0.74, 0.85, 0.96)
	e.fog_density = 0.00016
	e.fog_aerial_perspective = 0.7
	e.fog_sky_affect = 0.0
	e.adjustment_enabled = true
	e.adjustment_saturation = 1.1
	e.adjustment_contrast = 1.06
	return e


## Warme Nachmittagssonne mit weichen, weit reichenden Schatten
static func setup_sun(sun: DirectionalLight3D) -> void:
	sun.rotation = Vector3(deg_to_rad(-48), deg_to_rad(-38), 0)
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.light_energy = 1.35
	# Schatten je Grafikstufe (Settings): niedrig keine, mittel kürzer mit 2 Stufen, hoch 160 m mit 4 Stufen
	var shadow_m: float = Settings.shadow_distance()
	sun.shadow_enabled = shadow_m > 0.0
	sun.light_angular_distance = 0.8
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if shadow_m > 120.0 \
		else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = maxf(shadow_m, 1.0)
	sun.directional_shadow_blend_splits = true
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
