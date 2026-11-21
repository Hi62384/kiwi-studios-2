class_name KiwiCompositeLayer
extends Resource
enum Kind { IMAGE, SOLID, VIDEO, CGI, VFX, TEXT, SHAPE, MASK, ADJUSTMENT, GROUP, LINKED_COMPOSITION }
enum Blend { OVER, UNDER, IN, OUT, ATOP, ADD, SUBTRACT, MULTIPLY, SCREEN, DIFFERENCE, MINIMUM, MAXIMUM, CROSSFADE }
@export var id:=ActorData.new_id()
@export var name:="Layer"
@export var kind:=Kind.IMAGE
@export var parent_id:=""
@export var visible:=true
@export var locked:=false
@export_range(0.,1.,.001) var opacity:=1.0
@export var blend_mode:=Blend.OVER
@export var position:=Vector2(640,360)
@export var rotation:=0.0
@export var scale:=Vector2.ONE
@export var anchor:=Vector2(.5,.5)
@export var source_path:=""
@export var source_image: Texture2D
@export var color:=Color.WHITE
@export var mask_id:=""
@export var processing_graph_id:=""
@export var start_time:=0.0
@export var end_time:=-1.0
@export var source_time_offset:=0.0
@export var playback_speed:=1.0
@export var effects: Array[Dictionary]=[]
@export var settings: Dictionary={}
@export var children: Array[Resource]=[]

# Legacy binary schema and numeric-enum bridge; production validation is C#.
const LayerNative=preload("res://Workspaces/CompositingWorkspace/CompositeLayer.cs")
func validate() -> PackedStringArray:
	return LayerNative.new().validate_resource(self)
