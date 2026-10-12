class_name KiwiTextureMaterial
extends Resource
## An instance is independent of its preset. Coverage belongs to the layer,
## while these parameters describe the material revealed by that coverage.
@export var material_id:="wood/oak"
@export var label:="Oak"
@export var parameters: Dictionary={}
@export var image: Texture2D
@export var texture_size:=64.0
@export var rotation:=0.0
@export var alignment:="layer"
@export var application:="continuous"
@export var spacing:=.8
@export var jitter:=.25
@export var random_rotation:=0.0
@export var random_scale:=0.0
@export var follow_direction:=false
@export var direction_smoothing:=.7
@export var mapping_origin:=Vector2.ZERO
@export var tint_strength:=0.0
@export var tiling:="repeat"
@export var blending:="replace"
@export var secondary: KiwiTextureMaterial
@export var mix_amount:=0.0
@export var mix_distribution:="noise"
@export var mix_mask: Texture2D
@export var relief:=0.0
@export var relief_softness:=.3
@export var light_direction:=45.0
@export var highlight:=1.0
@export var shadow:=1.0
@export var coverage: Texture2D
@export var source: Texture2D

func copy_material() -> KiwiTextureMaterial:
	var result:=KiwiTextureMaterial.new()
	for key in ["material_id","label","image","texture_size","rotation","alignment","application","spacing","jitter","random_rotation","random_scale","follow_direction","direction_smoothing","mapping_origin","tint_strength","tiling","blending","mix_amount","mix_distribution","mix_mask","relief","relief_softness","light_direction","highlight","shadow","coverage","source"]: result.set(key,get(key))
	result.parameters=parameters.duplicate(true)
	if secondary!=null: result.secondary=secondary.copy_material()
	return result
