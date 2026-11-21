class_name KiwiCompositingDocument
extends Resource
const LayerNative=preload("res://Workspaces/CompositingWorkspace/CompositeLayer.cs")
@export var version:=1
@export var document_id:=ActorData.new_id()
@export var title:="Untitled Composition"
@export var canvas_size:=Vector2i(1920,1080)
@export var pixel_aspect_ratio:=1.0
@export var frame_rate:=24.0
@export var duration:=10.0
@export_enum("Linear sRGB") var working_color_space:=0
@export var input_color_settings: Dictionary={}
@export var output_color_settings: Dictionary={"transform":"sRGB"}
@export var layers: Array[Resource]=[]
@export var graphs: Array[Resource]=[]
@export var active_graph_id:=""
@export var solo_layer_id:=""
@export var media_references: Array[String]=[]
@export var render_references: Array[Dictionary]=[]
@export var masks: Array[Resource]=[]
@export var animation: Array[Dictionary]=[]
@export var processing_settings: Dictionary={"precision":"float32","tile_size":256,"cache":true}
@export var render_settings: Dictionary={"transparent":true,"quality":"Preview"}
@export var cache_references: Dictionary={}
@export var workspace_state: Dictionary={}

# Legacy binary-resource schema and C# behavior bridge.
const DocumentNative=preload("res://Workspaces/CompositingWorkspace/CompositingDocument.cs")
func layer(id: String) -> Resource:
	return DocumentNative.new().layer_resource(self,id)
func validate() -> PackedStringArray:
	return DocumentNative.new().validate_resource(self)
func signature() -> int:
	return DocumentNative.new().signature_resource(self)
func add_layer(kind: int,name: String="Layer") -> Resource:
	return DocumentNative.new().add_layer_resource(self,kind,name)
func has_layer_track(layer_id: String,property: String) -> bool:
	return DocumentNative.new().has_layer_track_resource(self,layer_id,property)
func set_layer_key(layer_id: String,property: String,time: float,value: Variant) -> bool:
	return DocumentNative.new().set_layer_key_resource(self,layer_id,property,time,value)
func sample_layer_value(layer_id: String,property: String,time: float,base_value: Variant) -> Variant:
	return DocumentNative.new().sample_layer_value_resource(self,layer_id,property,time,base_value)
