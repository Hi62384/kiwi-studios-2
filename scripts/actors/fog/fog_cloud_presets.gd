extends RefCounted
const TITLES:=["Fair-Weather Cumulus","Thick Cumulus","Stratus","Wispy High Clouds","Storm Clouds","Cartoon Clouds","Anime Clouds","Fantasy Clouds","Morning Mist","Ground Fog","Valley Mist","Forest Mist","Thick Cave Fog","Stylized Mist","Clear Atmospheric Haze","Distant Mountain Haze","Dusty Atmosphere","Humid Tropical Haze","Overcast Atmosphere","Stylized Atmospheric Perspective"]
const Field=preload("res://scripts/actors/fog/fog_field.gd")
const Appearance=preload("res://scripts/actors/fog/fog_appearance.gd")
static func configuration(index: int,original: Variant=null) -> Dictionary:
	return _native().configuration(index,original)

static func apply(model: RefCounted,actor: ActorData,index: int) -> void:
	_native().apply(model,actor,index)

static func _native() -> Object:
	return Engine.get_singleton("KiwiNativeServices").service("fog_cloud_presets")
