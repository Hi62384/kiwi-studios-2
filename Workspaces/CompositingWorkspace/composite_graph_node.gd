class_name KiwiCompositeGraphNode
extends Resource
## Legacy binary-resource schema only; production node logic is in C#.
@export var id:=ActorData.new_id()
@export_enum("Image Source","Solid Color","Layer Source","Over","Merge","Mask","Blur","Chroma Key","Luma Key","Color Grade","Output","Alpha Extract","Depth Compare") var kind:="Image Source"
@export var position:=Vector2.ZERO
@export var settings: Dictionary={}
@export var exposed:=false
