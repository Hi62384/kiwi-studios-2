class_name KiwiCompositingEvaluator
extends RefCounted
var _cache: Dictionary={}
var _cache_limit:=48
var last_error:=""
var nodes_evaluated:=0
var graph_cache_hits:=0
var _evaluation_stack: Dictionary={}
var _text_cache: Dictionary={}

func clear_cache() -> void: _cache.clear(); _text_cache.clear()

func evaluate(document: KiwiCompositingDocument,time: float,force: bool=false) -> KiwiCompositeBuffer:
	last_error=""; nodes_evaluated=0; graph_cache_hits=0
	if document==null: last_error="Composition is missing."; return null
	var identity:=document.resource_path if not document.resource_path.is_empty() else document.document_id
	if _evaluation_stack.has(identity): last_error="Linked composition cycle detected at '"+document.title+"'."; return null
	_evaluation_stack[identity]=true
	var result:=_evaluate_document(document,time,force)
	_evaluation_stack.erase(identity)
	return result

func _evaluate_document(document: KiwiCompositingDocument,time: float,force: bool=false) -> KiwiCompositeBuffer:
	if document==null: last_error="Composition is missing."; return null
	if document.working_color_space!=0: last_error="The selected working color space is not supported by the float preview backend."; return null
	var errors:=document.validate()
	if not errors.is_empty(): last_error="; ".join(errors); return null
	if not is_finite(time) or time<0. or time>document.duration: last_error="Requested frame lies outside the composition duration."; return null
	var key:=hash([document.signature(),snappedf(time*document.frame_rate,.00001),document.canvas_size,document.working_color_space])
	if not force and document.processing_settings.get("cache",true) and _cache.has(key): return (_cache[key] as KiwiCompositeBuffer).duplicate_buffer()
	var output:=_transparent(document,time); var seen:={}
	for item in document.layers:
		if item!=null and item.parent_id.is_empty(): output=_render_layer(document,item,output,time,seen)
	if not last_error.is_empty(): return null
	if output==null: last_error="Composition evaluation failed."; return null
	output.source_identity=str(key)
	if document.processing_settings.get("cache",true):
		_cache[key]=output.duplicate_buffer()
		while _cache.size()>_cache_limit: _cache.erase(_cache.keys()[0])
	return output

func evaluate_graph(document: KiwiCompositingDocument,graph: KiwiCompositeGraph,time: float,force: bool=false) -> KiwiCompositeBuffer:
	last_error=""
	if document==null or graph==null: last_error="Composition graph is missing."; return null
	var cache_key:=hash([document.signature(),graph.id,graph.nodes,graph.connections,graph.output_node,snappedf(time*document.frame_rate,.00001),document.canvas_size])
	if not force and document.processing_settings.get("cache",true) and _cache.has(cache_key):
		graph_cache_hits+=1; return (_cache[cache_key] as KiwiCompositeBuffer).duplicate_buffer()
	var errors:=graph.compile_errors()
	if not errors.is_empty(): last_error="; ".join(errors); return null
	if graph.output_node.is_empty(): last_error="The graph has no Output node."; return null
	var memo:={}; var result: Variant=_eval_node(document,graph,graph.output_node,time,memo,{})
	if result is KiwiCompositeBuffer:
		if document.processing_settings.get("cache",true):
			_cache[cache_key]=result.duplicate_buffer()
			while _cache.size()>_cache_limit: _cache.erase(_cache.keys()[0])
		return result
	last_error="Graph output did not produce an image."; return null

func evaluate_node_output(document: KiwiCompositingDocument,graph: KiwiCompositeGraph,node_id: String,time: float) -> KiwiCompositeBuffer:
	last_error=""; nodes_evaluated=0
	if document==null or graph==null or graph.node(node_id)==null: last_error="The selected graph node is missing."; return null
	var cache_key:=hash([document.signature(),graph.id,graph.nodes,graph.connections,node_id,snappedf(time*document.frame_rate,.00001)])
	if document.processing_settings.get("cache",true) and _cache.has(cache_key): graph_cache_hits+=1; return (_cache[cache_key] as KiwiCompositeBuffer).duplicate_buffer()
	var result: Variant=_eval_node(document,graph,node_id,time,{}, {})
	if result is KiwiCompositeBuffer:
		if document.processing_settings.get("cache",true): _cache[cache_key]=result.duplicate_buffer()
		return result
	if last_error.is_empty(): last_error="The selected node does not produce an image."
	return null

func _eval_node(document: KiwiCompositingDocument,graph: KiwiCompositeGraph,id: String,time: float,memo: Dictionary,visiting: Dictionary) -> Variant:
	if memo.has(id): return memo[id]
	if visiting.has(id): last_error="Graph cycle detected."; return null
	visiting[id]=true; var node:=graph.node(id)
	if node==null: last_error="Graph contains a missing node."; return null
	nodes_evaluated+=1; var result: Variant=null
	match node.kind:
		"Image Source": result=_source(document,str(node.settings.get("path","")),time)
		"Layer Source":
			var source_layer:=document.layer(str(node.settings.get("layer_id","")))
			if source_layer==null: last_error="Layer Source needs a valid layer reference."
			else:
				var source_copy:=source_layer.duplicate(true) as KiwiCompositeLayer; source_copy.processing_graph_id=""
				result=_layer_source(document,source_copy,time)
		"Solid Color": result=_solid(document,node.settings.get("color",Color.WHITE),time)
		"Over","Merge":
			var foreground: Variant=_input(document,graph,node,"foreground",time,memo,visiting); var background: Variant=_input(document,graph,node,"background",time,memo,visiting)
			if foreground is KiwiCompositeBuffer and background is KiwiCompositeBuffer:
				var merge_mode:=int(node.settings.get("mode",KiwiCompositeLayer.Blend.OVER)) if node.kind=="Merge" else KiwiCompositeLayer.Blend.OVER
				result=_blend(document,background,foreground,merge_mode,clampf(float(node.settings.get("opacity",1.)),0.,1.),null)
		"Color Grade":
			var source: Variant=_input(document,graph,node,"image",time,memo,visiting)
			if source is KiwiCompositeBuffer: result=_grade(source,node.settings)
		"Alpha Extract":
			var source: Variant=_input(document,graph,node,"image",time,memo,visiting)
			if source is KiwiCompositeBuffer: result=_alpha_extract(document,source,time)
		"Mask":
			var mask_source: Variant=_input(document,graph,node,"image",time,memo,visiting); var matte: Variant=_input(document,graph,node,"mask",time,memo,visiting)
			if mask_source is KiwiCompositeBuffer and matte is KiwiCompositeBuffer: result=_apply_matte(document,mask_source,matte,time)
		"Blur":
			var blur_source: Variant=_input(document,graph,node,"image",time,memo,visiting)
			if blur_source is KiwiCompositeBuffer: result=_blur(blur_source,int(node.settings.get("radius",2)))
		"Chroma Key":
			var key_source: Variant=_input(document,graph,node,"image",time,memo,visiting)
			if key_source is KiwiCompositeBuffer: result=_chroma_key(key_source,node.settings)
		"Luma Key":
			var luma_source: Variant=_input(document,graph,node,"image",time,memo,visiting)
			if luma_source is KiwiCompositeBuffer: result=_luma_key(luma_source,node.settings)
		"Depth Compare":
			last_error="Depth Compare requires a typed depth input and is not available in the CPU preview backend yet."
		"Output": result=_input(document,graph,node,"image",time,memo,visiting)
	if result==null and last_error.is_empty(): last_error="Node '%s' is missing a required input or source."%node.kind
	if result!=null: memo[id]=result
	visiting.erase(id); return result

func _input(document: KiwiCompositingDocument,graph: KiwiCompositeGraph,node: KiwiCompositeGraphNode,port: String,time: float,memo: Dictionary,visiting: Dictionary) -> Variant:
	for edge in graph.connections:
		if edge.to_node==node.id and edge.to_port==port: return _eval_node(document,graph,edge.from_node,time,memo,visiting)
	return null

func _render_layer(document: KiwiCompositingDocument,layer: KiwiCompositeLayer,backdrop: KiwiCompositeBuffer,time: float,seen: Dictionary) -> KiwiCompositeBuffer:
	if not layer.visible or seen.has(layer.id) or time<layer.start_time or (layer.end_time>=0. and time>=layer.end_time): return backdrop
	if not document.solo_layer_id.is_empty() and not _solo_contains(document,layer.id,document.solo_layer_id) and not (layer.kind==KiwiCompositeLayer.Kind.GROUP and _solo_contains(document,document.solo_layer_id,layer.id)): return backdrop
	seen[layer.id]=true
	layer=_animated_layer(document,layer,time)
	if layer.kind==KiwiCompositeLayer.Kind.ADJUSTMENT:
		var adjusted:=_grade(backdrop,layer.settings); return _mix_adjustment(backdrop,adjusted,layer.opacity,_mask(document,layer.mask_id,time),time)
	if layer.kind==KiwiCompositeLayer.Kind.GROUP:
		var group:=_transparent(document,time); var local_seen:=seen.duplicate()
		for child in document.layers:
			if child!=null and child.parent_id==layer.id: group=_render_layer(document,child,group,time,local_seen)
		var transformed_group:=_transform(document,group,layer,time)
		return _blend(document,backdrop,transformed_group,layer.blend_mode,layer.opacity,_mask(document,layer.mask_id,time))
	var source:=_layer_source(document,layer,time)
	if source==null: return backdrop
	var transformed:=_transform(document,source,layer,time)
	return _blend(document,backdrop,transformed,layer.blend_mode,layer.opacity,_mask(document,layer.mask_id,time))

func _animated_layer(document: KiwiCompositingDocument,source: KiwiCompositeLayer,time: float) -> KiwiCompositeLayer:
	var result:=source.duplicate(true) as KiwiCompositeLayer
	for property in ["position","rotation","scale","opacity"]:
		if document.has_layer_track(source.id,property): result.set(property,document.sample_layer_value(source.id,property,time,source.get(property)))
	return result

func _solo_contains(document: KiwiCompositingDocument,id: String,solo_id: String) -> bool:
	var current:=document.layer(id)
	while current!=null:
		if current.id==solo_id: return true
		current=document.layer(current.parent_id) if not current.parent_id.is_empty() else null
	return false

func _layer_source(document: KiwiCompositingDocument,layer: KiwiCompositeLayer,time: float) -> KiwiCompositeBuffer:
	if not layer.processing_graph_id.is_empty():
		var graph:=_graph_by_id(document,layer.processing_graph_id)
		if graph==null: last_error=layer.name+" references a missing processing graph."; return null
		return evaluate_graph(document,graph,time)
	if layer.kind==KiwiCompositeLayer.Kind.SOLID: return _solid(document,layer.color,time)
	if layer.kind==KiwiCompositeLayer.Kind.SHAPE: return _shape(document,layer,time)
	if layer.kind==KiwiCompositeLayer.Kind.TEXT: return _text(document,layer,time)
	if layer.kind==KiwiCompositeLayer.Kind.IMAGE:
		var image: Image=layer.source_image.get_image() if layer.source_image!=null else null
		if image==null and not layer.source_path.is_empty():
			image=Image.load_from_file(ProjectSettings.globalize_path(layer.source_path))
		if image==null or image.is_empty(): last_error="Image source is missing or unreadable: "+layer.source_path; return null
		var result:=KiwiCompositeBuffer.new(); result.image=_normalize_image(image,&"srgb",&"straight"); result.frame_time=time; result.source_identity=layer.source_path if not layer.source_path.is_empty() else layer.source_image.resource_path; result.color_space=&"linear_srgb"; result.alpha_association=&"straight"; return result
	if layer.kind==KiwiCompositeLayer.Kind.VIDEO:
		var source_time:=source_time_for_layer(layer,time); var texture:=ActorVideo.frame(layer.source_path,source_time,true)
		if texture==null: last_error="Waiting for the requested video frame: "+layer.source_path; return null
		var video_image:=texture.get_image()
		if video_image==null or video_image.is_empty(): last_error="The requested video frame could not be read."; return null
		var video_buffer:=KiwiCompositeBuffer.new(); video_buffer.image=_normalize_image(video_image,&"srgb",&"straight"); video_buffer.frame_time=time; video_buffer.source_identity=layer.source_path+"@"+str(source_time); video_buffer.color_space=&"linear_srgb"; video_buffer.alpha_association=&"straight"; return video_buffer
	if layer.kind in [KiwiCompositeLayer.Kind.CGI,KiwiCompositeLayer.Kind.VFX,KiwiCompositeLayer.Kind.MASK] and (layer.source_image!=null or not layer.source_path.is_empty()):
		var pass_image: Image=layer.source_image.get_image() if layer.source_image!=null else Image.load_from_file(ProjectSettings.globalize_path(layer.source_path))
		if pass_image==null or pass_image.is_empty(): last_error=layer.name+" render or mask source is missing."; return null
		var source_space: StringName=&"linear_srgb" if bool(layer.settings.get("scene_linear",false)) else &"srgb"; var alpha_mode: StringName=&"premultiplied" if bool(layer.settings.get("premultiplied",false)) else &"straight"
		var pass_buffer:=KiwiCompositeBuffer.new(); pass_buffer.image=_normalize_image(pass_image,source_space,alpha_mode); pass_buffer.frame_time=time; pass_buffer.source_identity=layer.source_path if not layer.source_path.is_empty() else layer.source_image.resource_path; pass_buffer.color_space=&"linear_srgb"; pass_buffer.alpha_association=&"straight"; return pass_buffer
	if layer.kind in [KiwiCompositeLayer.Kind.CGI,KiwiCompositeLayer.Kind.VFX]: last_error=layer.name+" needs a baked render-pass source. Live scene rendering is not yet available."; return null
	if layer.kind==KiwiCompositeLayer.Kind.LINKED_COMPOSITION:
		if layer.source_path.is_empty() or not ResourceLoader.exists(layer.source_path): last_error=layer.name+" references a missing composition resource."; return null
		var linked:=ResourceLoader.load(layer.source_path,"",ResourceLoader.CACHE_MODE_REUSE) as KiwiCompositingDocument
		if linked==null: last_error=layer.name+" could not load its linked composition."; return null
		var linked_time:=source_time_for_layer(layer,time)
		if linked_time>linked.duration: last_error=layer.name+" maps to a time outside its linked composition."; return null
		return evaluate(linked,linked_time)
	last_error=layer.name+" does not produce an image in the current preview backend."; return null

static func source_time_for_layer(layer: KiwiCompositeLayer,time: float) -> float:
	return layer.source_time_offset+maxf(0.,time-layer.start_time)*layer.playback_speed

func _source(document: KiwiCompositingDocument,path: String,time: float) -> KiwiCompositeBuffer:
	if path.is_empty(): last_error="Image Source node needs a file path."; return null
	var image:=Image.load_from_file(ProjectSettings.globalize_path(path))
	if image==null or image.is_empty(): last_error="Image Source node cannot read: "+path; return null
	var result:=KiwiCompositeBuffer.new(); result.image=_normalize_image(image,&"srgb",&"straight"); result.frame_time=time; result.source_identity=path; result.color_space=&"linear_srgb"; return result

func _graph_by_id(document: KiwiCompositingDocument,id: String) -> KiwiCompositeGraph:
	for graph in document.graphs:
		if graph!=null and graph.id==id: return graph
	return null

func _solid(document: KiwiCompositingDocument,color: Color,time: float) -> KiwiCompositeBuffer:
	var result:=KiwiCompositeBuffer.new(); result.image=Image.create(document.canvas_size.x,document.canvas_size.y,false,Image.FORMAT_RGBAF); var linear:=Color(color.r,color.g,color.b,color.a).srgb_to_linear(); result.image.fill(linear); result.frame_time=time; result.color_space=&"linear_srgb"; result.pixel_aspect_ratio=document.pixel_aspect_ratio; return result

func _shape(document: KiwiCompositingDocument,layer: KiwiCompositeLayer,time: float) -> KiwiCompositeBuffer:
	var size: Vector2i=layer.settings.get("size",Vector2i(256,256)); size.x=clampi(size.x,1,4096); size.y=clampi(size.y,1,4096)
	var image:=Image.create(size.x,size.y,false,Image.FORMAT_RGBA8); image.fill(Color.TRANSPARENT); var shape:=str(layer.settings.get("shape","rectangle")); var color:=layer.color
	for y in size.y:
		for x in size.x:
			var inside:=true
			if shape=="ellipse":
				var dx: float=(float(x)+.5)/size.x*2.-1.; var dy: float=(float(y)+.5)/size.y*2.-1.; inside=dx*dx+dy*dy<=1.
			elif shape=="triangle":
				inside=float(y)>=absf(float(x)-float(size.x)*.5)*float(size.y)/maxf(1.,float(size.x)*.5)
			elif shape=="polygon":
				var points: PackedVector2Array=layer.settings.get("points",PackedVector2Array()); inside=points.size()>=3 and Geometry2D.is_point_in_polygon(Vector2(x+.5,y+.5),points)
			if inside: image.set_pixel(x,y,color)
	var output:=KiwiCompositeBuffer.new(); output.image=_normalize_image(image,&"srgb",&"straight"); output.frame_time=time; output.pixel_aspect_ratio=document.pixel_aspect_ratio; output.source_identity="shape:"+layer.id; return output

func _text(document: KiwiCompositingDocument,layer: KiwiCompositeLayer,time: float) -> KiwiCompositeBuffer:
	var size: Vector2i=layer.settings.get("size",Vector2i(640,180)); size.x=clampi(size.x,1,4096); size.y=clampi(size.y,1,2048); var text_value:=str(layer.settings.get("text","Text")); var font_size:=clampi(int(layer.settings.get("font_size",72)),1,512); var font_path:=str(layer.settings.get("font_path","")); var cache_key:=hash([layer.id,text_value,font_size,font_path,layer.color,size])
	if _text_cache.has(cache_key):
		var cached:=KiwiCompositeBuffer.new(); cached.image=_text_cache[cache_key].duplicate(); cached.frame_time=time; cached.source_identity="text:"+layer.id+":"+text_value; return cached
	var image: Image
	if DisplayServer.get_name()=="headless": image=_bitmap_text(size,text_value,font_size,layer.color)
	else:
		var font: Font=ThemeDB.fallback_font
		if not font_path.is_empty() and ResourceLoader.exists(font_path):
			var loaded:=ResourceLoader.load(font_path) as Font
			if loaded!=null: font=loaded
		if font==null: last_error=layer.name+" cannot find a usable font."; return null
		var viewport:=SubViewport.new(); viewport.size=size; viewport.transparent_bg=true; viewport.gui_disable_input=true; viewport.render_target_update_mode=SubViewport.UPDATE_ONCE
		var tree:=Engine.get_main_loop() as SceneTree
		if tree==null: last_error="Text rendering needs an active scene tree."; return null
		tree.root.add_child(viewport); var label:=Label.new(); label.position=Vector2(2,2); label.size=Vector2(size); label.text=text_value; label.autowrap_mode=TextServer.AUTOWRAP_OFF; label.add_theme_font_override("font",font); label.add_theme_font_size_override("font_size",font_size); label.add_theme_color_override("font_color",layer.color); viewport.add_child(label)
		RenderingServer.force_draw(true,0.); image=viewport.get_texture().get_image(); viewport.free()
	if image==null or image.is_empty(): last_error=layer.name+" text could not be rasterized."; return null
	var normalized:=_normalize_image(image,&"srgb",&"straight"); _text_cache[cache_key]=normalized.duplicate()
	while _text_cache.size()>32: _text_cache.erase(_text_cache.keys()[0])
	var output:=KiwiCompositeBuffer.new(); output.image=normalized; output.frame_time=time; output.pixel_aspect_ratio=document.pixel_aspect_ratio; output.source_identity="text:"+layer.id+":"+text_value; return output

func _bitmap_text(size: Vector2i,text: String,font_size: int,color: Color) -> Image:
	var patterns: Dictionary={"A":["01110","10001","10001","11111","10001","10001","10001"],"B":["11110","10001","10001","11110","10001","10001","11110"],"C":["01111","10000","10000","10000","10000","10000","01111"],"D":["11110","10001","10001","10001","10001","10001","11110"],"E":["11111","10000","10000","11110","10000","10000","11111"],"F":["11111","10000","10000","11110","10000","10000","10000"],"G":["01111","10000","10000","10111","10001","10001","01111"],"H":["10001","10001","10001","11111","10001","10001","10001"],"I":["11111","00100","00100","00100","00100","00100","11111"],"J":["00111","00010","00010","00010","10010","10010","01100"],"K":["10001","10010","10100","11000","10100","10010","10001"],"L":["10000","10000","10000","10000","10000","10000","11111"],"M":["10001","11011","10101","10101","10001","10001","10001"],"N":["10001","11001","10101","10011","10001","10001","10001"],"O":["01110","10001","10001","10001","10001","10001","01110"],"P":["11110","10001","10001","11110","10000","10000","10000"],"Q":["01110","10001","10001","10001","10101","10010","01101"],"R":["11110","10001","10001","11110","10100","10010","10001"],"S":["01111","10000","10000","01110","00001","00001","11110"],"T":["11111","00100","00100","00100","00100","00100","00100"],"U":["10001","10001","10001","10001","10001","10001","01110"],"V":["10001","10001","10001","10001","10001","01010","00100"],"W":["10001","10001","10001","10101","10101","10101","01010"],"X":["10001","10001","01010","00100","01010","10001","10001"],"Y":["10001","10001","01010","00100","00100","00100","00100"],"Z":["11111","00001","00010","00100","01000","10000","11111"],"0":["01110","10001","10011","10101","11001","10001","01110"],"1":["00100","01100","00100","00100","00100","00100","01110"],"2":["01110","10001","00001","00010","00100","01000","11111"],"3":["11110","00001","00001","01110","00001","00001","11110"],"4":["00010","00110","01010","10010","11111","00010","00010"],"5":["11111","10000","10000","11110","00001","00001","11110"],"6":["01110","10000","10000","11110","10001","10001","01110"],"7":["11111","00001","00010","00100","01000","01000","01000"],"8":["01110","10001","10001","01110","10001","10001","01110"],"9":["01110","10001","10001","01111","00001","00001","01110"]," ":["00000","00000","00000","00000","00000","00000","00000"],"?":["11111","00001","00010","00100","00100","00000","00100"]}
	var image:=Image.create(size.x,size.y,false,Image.FORMAT_RGBA8); image.fill(Color.TRANSPARENT); var scale:=maxi(1,int(floor(float(font_size)/7.))); var pen_x:=2
	for character in text.substr(0,128).to_upper():
		var glyph: Array=patterns.get(character,patterns["?"])
		if pen_x+5*scale>size.x: break
		for row in 7:
			for column in 5:
				if glyph[row][column]!="1": continue
				for yy in range(row*scale+2,mini(size.y,(row+1)*scale+2)):
					for xx in range(pen_x+column*scale,mini(size.x,pen_x+(column+1)*scale)): image.set_pixel(xx,yy,color)
		pen_x+=6*scale
	return image

func _normalize_image(source: Image,source_space: StringName,alpha_mode: StringName) -> Image:
	var result:=source.duplicate(); result.convert(Image.FORMAT_RGBAF)
	for y in result.get_height():
		for x in result.get_width():
			var color: Color=result.get_pixel(x,y); var rgb:=Vector3(color.r,color.g,color.b)
			if source_space==&"srgb":
				var converted:=Color(color.r,color.g,color.b).srgb_to_linear(); rgb=Vector3(converted.r,converted.g,converted.b)
			if alpha_mode==&"premultiplied": rgb=rgb/color.a if color.a>0.000001 else Vector3.ZERO
			result.set_pixel(x,y,Color(rgb.x,rgb.y,rgb.z,color.a))
	return result

func _transparent(document: KiwiCompositingDocument,time: float) -> KiwiCompositeBuffer:
	var result:=_solid(document,Color.TRANSPARENT,time); result.source_identity="transparent"; return result

func _transform(document: KiwiCompositingDocument,source: KiwiCompositeBuffer,layer: KiwiCompositeLayer,time: float) -> KiwiCompositeBuffer:
	var input:=source.image.duplicate(); input.convert(Image.FORMAT_RGBAF)
	var output:=_transparent(document,time); var transform:=Transform2D(layer.rotation,layer.position); transform.x*=layer.scale.x; transform.y*=layer.scale.y; var inverse:=transform.affine_inverse(); var pivot:=Vector2(input.get_size())*layer.anchor
	for y in document.canvas_size.y:
		for x in document.canvas_size.x:
			var point:=inverse*Vector2(x+.5,y+.5)+pivot
			if point.x<0. or point.y<0. or point.x>=input.get_width() or point.y>=input.get_height(): continue
			var color: Color=input.get_pixel(clampi(int(point.x),0,input.get_width()-1),clampi(int(point.y),0,input.get_height()-1))
			if source.color_space==&"srgb": color=Color(color.r,color.g,color.b,color.a).srgb_to_linear()
			output.image.set_pixel(x,y,color)
	return output

func _mask(document: KiwiCompositingDocument,id: String,time: float) -> Image:
	if id.is_empty(): return null
	var layer:=document.layer(id)
	if layer==null: last_error="A layer references a missing mask."; return null
	var source:=_layer_source(document,layer,time)
	if source==null: return null
	var transformed:=_transform(document,source,layer,time)
	if not is_equal_approx(layer.opacity,1.):
		for y in transformed.image.get_height():
			for x in transformed.image.get_width():
				var color: Color=transformed.image.get_pixel(x,y); color.a*=layer.opacity; transformed.image.set_pixel(x,y,color)
	return transformed.image

func _blend(document: KiwiCompositingDocument,backdrop: KiwiCompositeBuffer,source: KiwiCompositeBuffer,mode: int,opacity: float,mask: Image) -> KiwiCompositeBuffer:
	if not backdrop.is_valid() or not source.is_valid(): last_error="A merge input image is invalid."; return null
	var out:=backdrop.duplicate_buffer(); out.image.convert(Image.FORMAT_RGBAF); var input:=source.image.duplicate(); input.convert(Image.FORMAT_RGBAF); var factor:=clampf(opacity,0.,1.)
	for y in document.canvas_size.y:
		for x in document.canvas_size.x:
			var foreground:=Color.TRANSPARENT
			if x<input.get_width() and y<input.get_height(): foreground=input.get_pixel(x,y)
			if source.color_space==&"srgb": foreground=foreground.srgb_to_linear()
			var background:=out.image.get_pixel(x,y); var coverage:=factor
			if mask!=null and not mask.is_empty() and x<mask.get_width() and y<mask.get_height(): coverage*=_mask_coverage(mask.get_pixel(x,y))
			foreground.a*=coverage
			out.image.set_pixel(x,y,_composite_pixel(background,foreground,mode))
	out.frame_time=source.frame_time; out.source_identity="merge:"+backdrop.source_identity+":"+source.source_identity; return out

func _composite_pixel(backdrop: Color,source: Color,mode: int) -> Color:
	var ab:=clampf(backdrop.a,0.,1.); var af:=clampf(source.a,0.,1.); var cb:=Vector3(backdrop.r,backdrop.g,backdrop.b); var cf:=Vector3(source.r,source.g,source.b)
	match mode:
		KiwiCompositeLayer.Blend.UNDER: return _composite_pixel(source,backdrop,KiwiCompositeLayer.Blend.OVER)
		KiwiCompositeLayer.Blend.IN:
			var alpha:=af*ab; return Color(cf.x*alpha,cf.y*alpha,cf.z*alpha,alpha) if alpha<=.000001 else Color(cf.x,cf.y,cf.z,alpha)
		KiwiCompositeLayer.Blend.OUT:
			var alpha:=af*(1.-ab); return Color(cf.x,cf.y,cf.z,alpha)
		KiwiCompositeLayer.Blend.ATOP:
			var alpha:=ab; var premul:=cf*af*ab+cb*ab*(1.-af); var rgb:=premul/alpha if alpha>.000001 else Vector3.ZERO; return Color(rgb.x,rgb.y,rgb.z,alpha)
		KiwiCompositeLayer.Blend.CROSSFADE:
			var alpha:=af+ab*(1.-af); var premul:=cf*af+cb*ab*(1.-af); var rgb:=premul/alpha if alpha>.000001 else Vector3.ZERO; return Color(rgb.x,rgb.y,rgb.z,alpha)
	var blend:=cf
	match mode:
		KiwiCompositeLayer.Blend.ADD: blend=cf+cb
		KiwiCompositeLayer.Blend.SUBTRACT: blend=cb-cf
		KiwiCompositeLayer.Blend.MULTIPLY: blend=cf*cb
		KiwiCompositeLayer.Blend.SCREEN: blend=Vector3.ONE-(Vector3.ONE-cf)*(Vector3.ONE-cb)
		KiwiCompositeLayer.Blend.DIFFERENCE: blend=(cf-cb).abs()
		KiwiCompositeLayer.Blend.MINIMUM: blend=cf.min(cb)
		KiwiCompositeLayer.Blend.MAXIMUM: blend=cf.max(cb)
	var alpha:=af+ab*(1.-af); var premultiplied: Vector3
	if mode==KiwiCompositeLayer.Blend.OVER: premultiplied=cf*af+cb*ab*(1.-af)
	else: premultiplied=cf*af*(1.-ab)+cb*ab*(1.-af)+blend*af*ab
	var rgb:=premultiplied/alpha if alpha>.000001 else Vector3.ZERO
	return Color(rgb.x,rgb.y,rgb.z,alpha)

func _mask_coverage(color: Color) -> float:
	return clampf(color.a*Vector3(color.r,color.g,color.b).dot(Vector3(.2126,.7152,.0722)),0.,1.)

func _mix_adjustment(original: KiwiCompositeBuffer,adjusted: KiwiCompositeBuffer,opacity: float,mask: Image,time: float) -> KiwiCompositeBuffer:
	var result:=original.duplicate_buffer(); var weight:=clampf(opacity,0.,1.)
	for y in result.image.get_height():
		for x in result.image.get_width():
			var factor:=weight
			if mask!=null and not mask.is_empty(): factor*=_mask_coverage(mask.get_pixel(x,y)) if x<mask.get_width() and y<mask.get_height() else 0.
			var a:=original.image.get_pixel(x,y); var b:=adjusted.image.get_pixel(x,y); result.image.set_pixel(x,y,a.lerp(b,factor))
	result.frame_time=time; result.source_identity="adjustment:"+original.source_identity; return result

func _grade(source: KiwiCompositeBuffer,settings: Dictionary) -> KiwiCompositeBuffer:
	var result:=source.duplicate_buffer(); result.image.convert(Image.FORMAT_RGBAF); var exposure:=float(settings.get("exposure",0.)); var brightness:=float(settings.get("brightness",0.)); var contrast:=float(settings.get("contrast",1.)); var saturation:=float(settings.get("saturation",1.)); var scale:=pow(2.,exposure)
	for y in result.image.get_height():
		for x in result.image.get_width():
			var c: Color=result.image.get_pixel(x,y); var rgb:=Vector3(c.r,c.g,c.b)*scale+Vector3.ONE*brightness; var temperature:=float(settings.get("temperature",0.)); var tint:=float(settings.get("tint",0.)); rgb+=Vector3(temperature*.1-tint*.03,tint*.05,-temperature*.1-tint*.03); rgb=(rgb-Vector3.ONE*.18)*contrast+Vector3.ONE*.18; var luminance:=rgb.dot(Vector3(.2126,.7152,.0722)); rgb=Vector3.ONE*luminance+(rgb-Vector3.ONE*luminance)*saturation
			var curves: Dictionary=settings.get("curves",{}); var master:Array=curves.get("master",[]); var red:Array=curves.get("red",[]); var green:Array=curves.get("green",[]); var blue:Array=curves.get("blue",[])
			if not master.is_empty(): rgb=Vector3(_curve_sample(master,rgb.x),_curve_sample(master,rgb.y),_curve_sample(master,rgb.z))
			if not red.is_empty(): rgb.x=_curve_sample(red,rgb.x)
			if not green.is_empty(): rgb.y=_curve_sample(green,rgb.y)
			if not blue.is_empty(): rgb.z=_curve_sample(blue,rgb.z)
			result.image.set_pixel(x,y,Color(rgb.x,rgb.y,rgb.z,c.a))
	return result

func _curve_sample(points: Array,value: float) -> float:
	if points.size()<2: return value
	var sorted:=points.duplicate(); sorted.sort_custom(func(a: Vector2,b: Vector2): return a.x<b.x)
	if value<=sorted[0].x: return sorted[0].y
	for index in range(1,sorted.size()):
		var left: Vector2=sorted[index-1]; var right: Vector2=sorted[index]
		if value<=right.x: return lerpf(left.y,right.y,inverse_lerp(left.x,right.x,value))
	return sorted[-1].y

func _chroma_key(source: KiwiCompositeBuffer,settings: Dictionary) -> KiwiCompositeBuffer:
	var result:=source.duplicate_buffer(); result.image.convert(Image.FORMAT_RGBAF); var key: Color=settings.get("key_color",Color.GREEN); var tolerance:=clampf(float(settings.get("tolerance",.2)),0.,2.); var softness:=maxf(.0001,float(settings.get("softness",.1))); var spill:=clampf(float(settings.get("spill",.5)),0.,1.)
	for y in result.image.get_height():
		for x in result.image.get_width():
			var pixel: Color=result.image.get_pixel(x,y); var distance:=Vector3(pixel.r-key.r,pixel.g-key.g,pixel.b-key.b).length(); var amount:=clampf((distance-tolerance)/softness,0.,1.); amount=amount*amount*(3.-2.*amount); pixel.a*=amount
			var dominant:=maxf(pixel.r,pixel.b); pixel.g=lerpf(pixel.g,minf(pixel.g,dominant),spill); result.image.set_pixel(x,y,pixel)
	result.source_identity="chroma:"+source.source_identity; return result

func _luma_key(source: KiwiCompositeBuffer,settings: Dictionary) -> KiwiCompositeBuffer:
	var result:=source.duplicate_buffer(); result.image.convert(Image.FORMAT_RGBAF)
	var low:=clampf(float(settings.get("low",.1)),0.,1.); var high:=clampf(float(settings.get("high",.9)),0.,1.)
	if high<low: var swap:=low; low=high; high=swap
	var softness:=maxf(.0001,float(settings.get("softness",.05))); var invert:=bool(settings.get("invert",false))
	for y in result.image.get_height():
		for x in result.image.get_width():
			var pixel: Color=result.image.get_pixel(x,y); var luma:=clampf(pixel.r*.2126+pixel.g*.7152+pixel.b*.0722,0.,1.)
			var lower:=smoothstep(low-softness,low+softness,luma); var upper:=smoothstep(high-softness,high+softness,luma); var matte:=clampf(lower*(1.-upper),0.,1.)
			if invert: matte=1.-matte
			pixel.a*=matte; result.image.set_pixel(x,y,pixel)
	result.source_identity="luma_key:"+source.source_identity; return result

func _alpha_extract(document: KiwiCompositingDocument,source: KiwiCompositeBuffer,time: float) -> KiwiCompositeBuffer:
	var result:=_transparent(document,time); var input:=source.image.duplicate(); input.convert(Image.FORMAT_RGBAF)
	for y in document.canvas_size.y:
		for x in document.canvas_size.x:
			var alpha: float=input.get_pixel(x,y).a if x<input.get_width() and y<input.get_height() else 0.; result.image.set_pixel(x,y,Color(alpha,alpha,alpha,1.))
	result.source_identity="alpha:"+source.source_identity; return result

func _apply_matte(document: KiwiCompositingDocument,source: KiwiCompositeBuffer,matte: KiwiCompositeBuffer,time: float) -> KiwiCompositeBuffer:
	var result:=source.duplicate_buffer(); result.image.convert(Image.FORMAT_RGBAF); var mask:=matte.image.duplicate(); mask.convert(Image.FORMAT_RGBAF)
	for y in result.image.get_height():
		for x in result.image.get_width():
			var color: Color=result.image.get_pixel(x,y); var matte_color: Color=mask.get_pixel(x,y) if x<mask.get_width() and y<mask.get_height() else Color.TRANSPARENT
			result.image.set_pixel(x,y,Color(color.r,color.g,color.b,color.a*matte_color.r*matte_color.a))
	result.frame_time=time; result.source_identity="matte:"+source.source_identity+":"+matte.source_identity; return result

func _blur(source: KiwiCompositeBuffer,radius: int) -> KiwiCompositeBuffer:
	var result:=source.duplicate_buffer(); var input: Image=source.image.duplicate(); input.convert(Image.FORMAT_RGBAF); radius=clampi(radius,0,32)
	if radius==0: result.image=input; return result
	var width: int=input.get_width(); var height: int=input.get_height(); var horizontal:=Image.create(width,height,false,Image.FORMAT_RGBAF)
	for y in height:
		var sum:=Color(0.,0.,0.,0.)
		for x in range(0,mini(width,radius+1)):
			var pixel: Color=input.get_pixel(x,y); sum+=Color(pixel.r*pixel.a,pixel.g*pixel.a,pixel.b*pixel.a,pixel.a)
		for x in width:
			var count:=mini(width-1,x+radius)-maxi(0,x-radius)+1; horizontal.set_pixel(x,y,sum/float(count))
			var remove: int=x-radius; var add: int=x+radius+1
			if remove>=0:
				var pixel: Color=input.get_pixel(remove,y); sum-=Color(pixel.r*pixel.a,pixel.g*pixel.a,pixel.b*pixel.a,pixel.a)
			if add<width:
				var pixel: Color=input.get_pixel(add,y); sum+=Color(pixel.r*pixel.a,pixel.g*pixel.a,pixel.b*pixel.a,pixel.a)
	result.image=Image.create(width,height,false,Image.FORMAT_RGBAF)
	for x in width:
		var sum:=Color(0.,0.,0.,0.)
		for y in range(0,mini(height,radius+1)): sum+=horizontal.get_pixel(x,y)
		for y in height:
			var count:=mini(height-1,y+radius)-maxi(0,y-radius)+1; var pixel: Color=sum/float(count)
			if pixel.a>.000001: pixel=Color(pixel.r/pixel.a,pixel.g/pixel.a,pixel.b/pixel.a,pixel.a)
			else: pixel=Color.TRANSPARENT
			result.image.set_pixel(x,y,pixel)
			var remove: int=y-radius; var add: int=y+radius+1
			if remove>=0: sum-=horizontal.get_pixel(x,remove)
			if add<height: sum+=horizontal.get_pixel(x,add)
	return result

func _copy_time(source: KiwiCompositeBuffer,time: float) -> KiwiCompositeBuffer:
	var result:=source.duplicate_buffer(); result.frame_time=time; return result
