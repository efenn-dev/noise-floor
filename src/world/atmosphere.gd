class_name Atmosphere
extends RefCounted
## V1 (Sprint 4): the look of the sky and air through the day, and the graphics quality presets.
## Pure functions of the sun's height (GameClock.sun_elevation_deg) so tests can check them headless;
## main.gd applies the results to its Environment, sky material and sun every frame.
## The Compatibility renderer (cloud screenshots) ignores SSAO, SSIL, SDFGI and volumetric fog.

const QUALITIES := ["low", "medium", "high"]
const DEFAULT_QUALITY := "high"

## What each preset turns on. Low is for weak PCs: plain fog (no flashlight beam in the air), no ambient
## occlusion or bounce light. Medium adds ambient occlusion and the volumetric fog at a coarser grid.
## High adds screen-space bounce light (SSIL), soft sun shadows and a finer fog grid.
## No SDFGI: tried in V1, it shut out the sky's light indoors and left houses black at noon.
const PRESETS := {
	"low": {"ssao": false, "ssil": false, "volumetric": false, "shadow_atlas": 2048,
			"fog_volume": 64, "soft_shadows": false},
	"medium": {"ssao": true, "ssil": false, "volumetric": true, "shadow_atlas": 4096,
			"fog_volume": 64, "soft_shadows": false},
	"high": {"ssao": true, "ssil": true, "volumetric": true, "shadow_atlas": 4096,
			"fog_volume": 128, "soft_shadows": true},
}

# Sky colours: [top, horizon] at full day, at the golden hour (sun near the horizon) and at night.
const SKY_DAY := [Color(0.36, 0.45, 0.57), Color(0.67, 0.69, 0.70)]
const SKY_GOLDEN := [Color(0.27, 0.29, 0.42), Color(0.86, 0.55, 0.36)]
const SKY_NIGHT := [Color(0.012, 0.015, 0.026), Color(0.035, 0.04, 0.055)]
const SUN_DAY := Color(1.0, 0.96, 0.9)
const SUN_LOW := Color(1.0, 0.58, 0.32)


static func valid_quality(q: String) -> String:
	return q if q in QUALITIES else DEFAULT_QUALITY


static func preset(q: String) -> Dictionary:
	return PRESETS[valid_quality(q)]


## How bright the sky and ambient light are, 0 (deep night) to 1 (full day). Unlike daylight() it keeps
## some light through twilight, so dusk glows instead of going black the moment the sun touches the roofs.
static func sky_light(elevation_deg: float) -> float:
	return smoothstep(-10.0, 25.0, elevation_deg)


## How strong direct sunlight is: full from about 14 degrees up, fading out as the sun sets.
static func sun_strength(elevation_deg: float) -> float:
	return smoothstep(-1.0, 14.0, elevation_deg)


## 1 when the sun sits on the horizon (warm light and sky), 0 when it's high or well below.
static func warmth(elevation_deg: float) -> float:
	if elevation_deg < 0.0:
		return 1.0 - smoothstep(0.0, 9.0, -elevation_deg)
	return 1.0 - smoothstep(4.0, 22.0, elevation_deg)


## [top, horizon] sky colours for this sun height.
static func sky_colors(elevation_deg: float) -> Array:
	var w := warmth(elevation_deg)
	var day_or_golden: Array = [SKY_DAY[0].lerp(SKY_GOLDEN[0], w), SKY_DAY[1].lerp(SKY_GOLDEN[1], w)]
	var l := sky_light(elevation_deg)
	return [SKY_NIGHT[0].lerp(day_or_golden[0], l), SKY_NIGHT[1].lerp(day_or_golden[1], l)]


static func sun_color(elevation_deg: float) -> Color:
	return SUN_DAY.lerp(SUN_LOW, warmth(elevation_deg))


## Fog tint: the season's day fog, warmed at dusk and dawn.
static func fog_tint(elevation_deg: float, season_fog: Color) -> Color:
	return season_fog.lerp(Color(0.62, 0.48, 0.42), warmth(elevation_deg) * 0.6)


## Turns the preset's effects on or off on the environment and sets the engine-wide sizes.
static func apply_quality(env: Environment, sun: DirectionalLight3D, q: String) -> void:
	var p := preset(q)
	env.ssao_enabled = p["ssao"]
	env.ssil_enabled = p["ssil"]
	env.sdfgi_enabled = false
	env.volumetric_fog_enabled = p["volumetric"]
	if sun != null:
		sun.light_angular_distance = 0.6 if p["soft_shadows"] else 0.0
	RenderingServer.directional_shadow_atlas_set_size(p["shadow_atlas"], true)
	RenderingServer.environment_set_volumetric_fog_volume_size(p["fog_volume"], p["fog_volume"])


## The fixed parts of the look, set once: tone mapping, a slightly drained colour grade, the strengths
## of each effect (whether they're on is apply_quality's job).
static func setup_environment(env: Environment) -> void:
	env.tonemap_mode = Environment.TONE_MAPPER_AGX  # rolls bright lamps and the flashlight off softly
	env.tonemap_exposure = 1.05
	env.adjustment_enabled = true
	env.adjustment_saturation = 0.9  # a dead town: colours a little drained
	env.adjustment_contrast = 1.12
	env.ssao_intensity = 2.2
	env.ssao_radius = 1.2
	env.ssil_intensity = 0.8
	env.glow_intensity = 0.7
	env.glow_bloom = 0.03
	env.glow_hdr_threshold = 1.1  # only lamps, fire and the flashlight bloom
