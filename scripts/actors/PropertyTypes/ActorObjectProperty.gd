class_name ActorObjectProperty
extends ActorPropertyType


@export var object_name: String
@export var object_icon: Texture2D
@export var inherits_object: ActorObjectProperty 
@export var abstract: bool = false
@export var property_references: Array[PropertyReference]


func get_property_reference(display_name: String) -> ActorObjectProperty:
	for property_reference: PropertyReference in property_references:
		if property_reference.display_name == display_name:
			return property_reference.property
	return null



func get_property_value(display_name: String) -> Variant:
	return get_property_reference(display_name).get_value()



func set_property_value(display_name: String, property_value: Variant) -> void:
	get_property_reference(display_name).set_value(property_value)



func get_icon() -> Texture2D:
	return object_icon
