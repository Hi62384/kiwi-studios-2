class_name PropertyReference
extends Resource


@export var display_name: String

@export var property: ActorPropertyType

@export_group("Visibility")

##if null, is always visible
@export var property_reference_visible: PropertyReference

@export var property_reference_condition: CuteCondition
