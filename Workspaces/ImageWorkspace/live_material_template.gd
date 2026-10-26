class_name KiwiLiveMaterialTemplate
extends Resource
## A document-local material instance. Regions refer to its stable ID, never its name.

@export var version: int = 1
@export var id: String = ""
@export var label: String = "Natural Material"
@export var material: KiwiTextureMaterial
@export var visible: bool = true


func copy_template() -> KiwiLiveMaterialTemplate:
	var result := KiwiLiveMaterialTemplate.new()
	result.version = version
	result.id = id
	result.label = label
	result.visible = visible
	if material != null: result.material = material.copy_material()
	return result
