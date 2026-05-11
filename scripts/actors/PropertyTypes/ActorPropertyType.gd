class_name ActorPropertyType
extends Resource

signal value_changed


##OVERRIDE
func set_value(_val: Variant) -> void:
	value_changed.emit()



##OVERRIDE
func get_value() -> Variant:
	return


##OVERRIDE
##-1 for cannot be chosen from filesystem
##-2 for can choose actor from scene tree
func can_be_chosen_from_filesystem_filetype() -> FileOperations.FileType:
	return -1



func get_actor_property_names() -> Array[String]:
	return []



##OVERRIDE
func get_icon() -> Texture2D:
	return null



func get_duplicate() -> ActorPropertyType:
	return self.duplicate_deep()
