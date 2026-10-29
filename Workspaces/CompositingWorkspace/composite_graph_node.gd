class_name KiwiCompositeGraphNode
extends Resource
@export var id:=ActorData.new_id()
@export_enum("Image Source","Solid Color","Layer Source","Over","Merge","Mask","Blur","Chroma Key","Luma Key","Color Grade","Output","Alpha Extract","Depth Compare") var kind:="Image Source"
@export var position:=Vector2.ZERO
@export var settings: Dictionary={}
@export var exposed:=false

static func port_type(node_kind: String,port: String) -> StringName:
	match node_kind:
		"Image Source","Layer Source": return &"image" if port=="image" else &""
		"Solid Color": return &"image" if port=="image" else &""
		"Over","Merge": return &"image" if port in ["foreground","background","image"] else &""
		"Mask": return &"image" if port=="image" else (&"mask" if port=="mask" else &"")
		"Blur","Chroma Key","Luma Key": return &"image" if port in ["image","output"] else &""
		"Color Grade": return &"image" if port in ["image","output"] else &""
		"Output": return &"image" if port=="image" else &""
		"Alpha Extract": return &"image" if port=="image" else (&"mask" if port=="mask" else &"")
		"Depth Compare": return &"image" if port=="image" else (&"depth" if port=="depth" else (&"mask" if port=="mask" else &""))
	return &""

static func has_output(node_kind: String,port: String) -> bool:
	if node_kind=="Output": return false
	if node_kind=="Alpha Extract" or node_kind=="Mask": return port=="mask"
	if node_kind=="Depth Compare": return port in ["image","mask"]
	return port_type(node_kind,port)!=&"" and port in ["image","output"]

static func has_input(node_kind: String,port: String) -> bool:
	if node_kind in ["Image Source","Solid Color","Layer Source"]: return false
	if node_kind=="Alpha Extract": return port=="image"
	if node_kind=="Mask": return port in ["image","mask"]
	if node_kind=="Blur": return port=="image"
	if node_kind=="Depth Compare": return port in ["image","depth"]
	return port_type(node_kind,port)!=&"" and port not in ["output","mask"]
