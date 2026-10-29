class_name KiwiCompositingDocument
extends Resource
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
@export var layers: Array[KiwiCompositeLayer]=[]
@export var graphs: Array[KiwiCompositeGraph]=[]
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

func layer(id: String) -> KiwiCompositeLayer:
	for item in layers:
		if item!=null and item.id==id: return item
	return null

func validate() -> PackedStringArray:
	var errors:=PackedStringArray(); var ids:={}
	if version!=1: errors.append("Unsupported compositing document version.")
	if document_id.is_empty() or title.strip_edges().is_empty(): errors.append("A composition needs a document ID and title.")
	if canvas_size.x<1 or canvas_size.y<1 or canvas_size.x>16384 or canvas_size.y>16384 or not is_finite(pixel_aspect_ratio) or pixel_aspect_ratio<=0.: errors.append("Canvas size and pixel aspect ratio are invalid.")
	if not is_finite(frame_rate) or frame_rate<=0. or frame_rate>240. or not is_finite(duration) or duration<=0.: errors.append("Composition frame rate and duration are invalid.")
	for item in layers:
		if item==null: errors.append("A compositing layer is missing."); continue
		if ids.has(item.id): errors.append("Layer IDs must be unique.")
		ids[item.id]=true; errors.append_array(item.validate())
	for item in layers:
		if item!=null and not item.parent_id.is_empty() and not ids.has(item.parent_id): errors.append(item.name+" has a missing parent.")
	var visited:={}; var visiting:={}
	for item in layers:
		if item!=null and _parent_cycle(item.id,visited,visiting): errors.append("Layer parenting cannot contain cycles."); break
	for graph in graphs:
		if graph==null: errors.append("A compositing graph is missing.")
		else: errors.append_array(graph.validate())
	return errors

func _parent_cycle(id: String,visited: Dictionary,visiting: Dictionary) -> bool:
	if visiting.has(id): return true
	if visited.has(id): return false
	visiting[id]=true; var item:=layer(id)
	if item!=null and not item.parent_id.is_empty() and _parent_cycle(item.parent_id,visited,visiting): return true
	visiting.erase(id); visited[id]=true; return false

func signature() -> int:
	var layer_data:=[]
	for item in layers: layer_data.append([item.id,item.name,item.kind,item.parent_id,item.visible,item.opacity,item.blend_mode,item.position,item.rotation,item.scale,item.anchor,item.source_path,item.source_image,item.color,item.mask_id,item.processing_graph_id,item.start_time,item.end_time,item.source_time_offset,item.playback_speed,item.effects,item.settings,item.children])
	var graph_data:=[]
	for graph in graphs: graph_data.append([graph.id,graph.name,graph.nodes,graph.connections,graph.output_node])
	return hash([version,document_id,title,canvas_size,pixel_aspect_ratio,frame_rate,duration,working_color_space,input_color_settings,output_color_settings,layer_data,graph_data,active_graph_id,solo_layer_id,media_references,render_references,masks,animation,processing_settings,render_settings])

func add_layer(kind: int,name: String="Layer") -> KiwiCompositeLayer:
	var item:=KiwiCompositeLayer.new(); item.kind=kind; item.name=name; item.position=Vector2(canvas_size)*.5; layers.append(item); return item

func has_layer_track(layer_id: String,property: String) -> bool:
	return _layer_track_index(layer_id,property)>=0

func set_layer_key(layer_id: String,property: String,time: float,value: Variant) -> bool:
	if layer(layer_id)==null or property not in ["position","rotation","scale","opacity"] or not is_finite(time): return false
	time=clampf(time,0.,duration)
	var index:=_layer_track_index(layer_id,property)
	if index<0: animation.append({"layer_id":layer_id,"property":property,"keys":[]}); index=animation.size()-1
	var track: Dictionary=animation[index]; var keys: Array=track.get("keys",[]); var replaced:=false
	for key_index in keys.size():
		var key: Dictionary=keys[key_index]
		if is_equal_approx(float(key.get("time",-1.)),time): keys[key_index]={"time":time,"value":value}; replaced=true; break
	if not replaced: keys.append({"time":time,"value":value})
	keys.sort_custom(func(a: Dictionary,b: Dictionary): return float(a.get("time",0.))<float(b.get("time",0.)))
	track["keys"]=keys; animation[index]=track; return true

func sample_layer_value(layer_id: String,property: String,time: float,base_value: Variant) -> Variant:
	var index:=_layer_track_index(layer_id,property)
	if index<0: return base_value
	var keys: Array=animation[index].get("keys",[])
	if keys.is_empty(): return base_value
	if time<=float(keys[0].get("time",0.)): return keys[0].get("value",base_value)
	for key_index in range(1,keys.size()):
		var left: Dictionary=keys[key_index-1]; var right: Dictionary=keys[key_index]; var left_time:=float(left.get("time",0.)); var right_time:=float(right.get("time",left_time))
		if time<=right_time:
			var amount:=inverse_lerp(left_time,right_time,time); var a: Variant=left.get("value",base_value); var b: Variant=right.get("value",base_value)
			if a is Vector2 and b is Vector2: return a.lerp(b,amount)
			if a is Vector3 and b is Vector3: return a.lerp(b,amount)
			if a is Color and b is Color: return a.lerp(b,amount)
			if a is float or a is int: return lerpf(float(a),float(b),amount)
			return a if amount<.5 else b
	return keys[-1].get("value",base_value)

func _layer_track_index(layer_id: String,property: String) -> int:
	for index in animation.size():
		var track: Dictionary=animation[index]
		if str(track.get("layer_id",""))==layer_id and str(track.get("property",""))==property: return index
	return -1
