class_name SeasonLook
extends RefCounted
## M16: how each season looks, all through tints on the existing materials (no new textures): the ground,
## the street trees' leaves (A1's tree model: "Leaves" and "Leaves Dark"), the house and factory roofs, and the
## daytime fog colour. main.gd applies it when the season changes; the rules are in GameClock and data/seasons.json.

const LOOKS := {
	"summer": {"ground": Color(0.66, 0.66, 0.52), "fog": Color(0.68, 0.66, 0.62), "roof": Color(0.42, 0.36, 0.34),
		"leaves": {}},
	"autumn": {"ground": Color(0.66, 0.58, 0.44), "fog": Color(0.64, 0.62, 0.6), "roof": Color(0.42, 0.36, 0.34),
		"leaves": {"Leaves": Color(0.62, 0.33, 0.07), "Leaves Dark": Color(0.45, 0.2, 0.05)}},
	"winter": {"ground": Color(1.45, 1.6, 2.4), "fog": Color(0.66, 0.72, 0.82), "roof": Color(1.6, 1.65, 1.8),
		"leaves": {"Leaves": Color(0.4, 0.4, 0.41), "Leaves Dark": Color(0.3, 0.3, 0.31)}},
	"spring": {"ground": Color(0.56, 0.68, 0.5), "fog": Color(0.62, 0.66, 0.7), "roof": Color(0.42, 0.36, 0.34),
		"leaves": {"Leaves": Color(0.2, 0.48, 0.1), "Leaves Dark": Color(0.12, 0.34, 0.07)}},
}


static func look(season: String) -> Dictionary:
	return LOOKS.get(season, LOOKS["summer"])


static func ground_material(season: String) -> StandardMaterial3D:
	return Surfaces.material("ground", 6.0, look(season)["ground"])


static func roof_material(season: String) -> StandardMaterial3D:
	return Surfaces.material("asphalt", 3.0, look(season)["roof"])


## The fog's colour at full daylight (night stays the same dark blue).
static func fog_day(season: String) -> Color:
	return look(season)["fog"]


## Leaf material name -> colour for the trees; {} = the model's own green (summer).
static func leaves(season: String) -> Dictionary:
	return look(season)["leaves"]
