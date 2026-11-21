extends VBoxContainer
const Appearance=preload("res://scripts/actors/fog/fog_appearance.gd")
static func layer_actions(host: ActorInspector,actor: ActorData,object: ActorObjectData,property: ActorProperty,parent: VBoxContainer) -> void:
	_native().layer_actions(host,actor,object,property,parent)
func setup(host: ActorInspector,actor: ActorData) -> void:
	_native().setup(self,host,actor)
static func _native() -> Object:
	return Engine.get_singleton("KiwiNativeServices").service("fog_control")
