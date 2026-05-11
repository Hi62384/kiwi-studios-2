class_name Actor
extends Node3D

@export var object_property: ActorObjectProperty


var timeline_start_position: float = 0
var timeline_end_position: float = 3



func _ready() -> void:
	for property_reference: PropertyReference in object_property.property_references:
		property_reference.property = property_reference.property.get_du
		property_reference.property.value_changed.connect(func():
			property_changed(property_reference.display_name, property_reference.property.get_value())
			)



##OVERRIDE, AND CALL SUPER
##MANAGES TIMELINE VISIBILITY, AND KEYFRAMES
func timeline_seeker_position_changed(time) -> void:
	pass



func property_changed(property_name: String, value: Variant) -> void:
	pass
