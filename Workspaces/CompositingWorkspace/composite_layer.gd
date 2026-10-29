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
@export var children: Array[KiwiCompositeLayer]=[]

func validate() -> PackedStringArray:
	var errors:=PackedStringArray()
	if id.is_empty() or name.strip_edges().is_empty(): errors.append("Every compositing layer needs an ID and name.")
	if not is_finite(opacity) or opacity<0. or opacity>1. or not is_finite(rotation) or not position.is_finite() or not scale.is_finite() or absf(scale.x)<.000001 or absf(scale.y)<.000001: errors.append("Layer opacity and transform values are invalid.")
	if not is_finite(start_time) or not is_finite(end_time) or not is_finite(source_time_offset) or not is_finite(playback_speed) or start_time<0. or (end_time>=0. and end_time<start_time) or source_time_offset<0. or playback_speed<=0.: errors.append("Layer timing values must be finite, clip ends cannot precede starts, and playback speed must be positive.")
	if kind==Kind.IMAGE and source_image==null and source_path.is_empty() and processing_graph_id.is_empty(): errors.append(name+" has no image source.")
	if kind==Kind.VIDEO and source_path.is_empty(): errors.append(name+" has no video footage source.")
	if kind==Kind.LINKED_COMPOSITION and source_path.is_empty(): errors.append(name+" has no linked composition resource.")
	if not processing_graph_id.is_empty() and not [Kind.IMAGE,Kind.SOLID,Kind.VIDEO,Kind.CGI,Kind.VFX,Kind.TEXT,Kind.SHAPE,Kind.MASK,Kind.LINKED_COMPOSITION].has(kind): errors.append(name+" cannot use a source processing graph.")
	if kind==Kind.SOLID and (not is_finite(color.r) or not is_finite(color.g) or not is_finite(color.b) or not is_finite(color.a)): errors.append(name+" has an invalid solid color.")
	return errors
