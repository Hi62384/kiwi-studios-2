extends RefCounted
## Private authored masks and exact regional suitability previews. A release
## restores source fields before the worker commits one complete history action.
var canvas: Control
var biome_id:=""
var _stroke: Dictionary={}
var _preview_revision:=0
func target() -> Dictionary:
	if canvas==null or canvas.environment_session()==null: return {}
	var session: KiwiEnvironmentSession=canvas.environment_session(); var selected:=session.primary()
	if selected==null: return {}
	var terrain:=session.environment().terrain(selected.id)
	if terrain==null or terrain.biomes==null or terrain.biome_data.is_empty(): return {}
	for definition in terrain.biomes.definitions:
		if not definition.get("enabled",true) or definition.get("domain","surface")!="surface": continue
		if biome_id.is_empty() or str(definition.id)==biome_id: biome_id=str(definition.id); return {"id":selected.id,"terrain":terrain}
	return {}
func input(event: InputEvent) -> bool:
	if not canvas.environment_tool in ["Paint biome","Erase biome"]: return false
	if not _stroke.is_empty() and ((event is InputEventKey and event.pressed and (event.keycode==KEY_ESCAPE or event.ctrl_pressed and event.keycode in [KEY_Z,KEY_Y])) or (event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_RIGHT)): cancel(); return true
	if canvas._navigating or canvas._panning or canvas._orbiting: return false
	if event is InputEventMouseMotion:
		canvas._brush_hit=canvas.pick_terrain(event.position)
		if not _stroke.is_empty() and not canvas._brush_hit.is_empty() and canvas._brush_hit.id==_stroke.id: _dab(canvas._brush_hit.local,event.ctrl_pressed)
		canvas.overlay.queue_redraw(); return not _stroke.is_empty()
	if not event is InputEventMouseButton or event.button_index!=MOUSE_BUTTON_LEFT: return false
	if not event.pressed:
		if _stroke.is_empty(): return false
		var stroke:=_stroke; cancel()
		if bool(stroke.changed): canvas.biomes_replaced.emit(str(stroke.id),stroke.source)
		canvas.gesture_finished.emit(); return true
	var info:=target(); canvas._brush_hit=canvas.pick_terrain(event.position)
	if info.is_empty() or canvas._brush_hit.is_empty() or canvas._brush_hit.id!=info.id: return false
	canvas.grab_focus(); var terrain:=info.terrain as KiwiEnvironmentTerrain; var source:=terrain.biomes.duplicate(true) as KiwiTerrainBiomes; var mask: PackedFloat32Array=source.paint_masks.get(biome_id,PackedFloat32Array()); var n:=terrain.resolution
	if mask.size()==n*n: mask=mask.duplicate()
	elif mask.size()>0:
		var old_n:=roundi(sqrt(float(mask.size())))
		if old_n*old_n==mask.size(): var image:=Image.create_from_data(old_n,old_n,false,Image.FORMAT_RF,mask.to_byte_array()); image.resize(n,n,Image.INTERPOLATE_BILINEAR); mask=image.get_data().to_float32_array()
		else: mask=PackedFloat32Array(); mask.resize(n*n)
	else: mask.resize(n*n)
	source.paint_masks[biome_id]=mask; var original:=terrain.biome_data.duplicate(); var weights: Dictionary={}
	for id: String in terrain.biome_data.weights: weights[id]=(terrain.biome_data.weights[id] as PackedFloat32Array).duplicate()
	original.weights=weights; _stroke={"id":info.id,"terrain":terrain,"source":source,"original":original,"noises":source.noise_fields(terrain.seed),"last":Vector2(canvas._brush_hit.local.x,canvas._brush_hit.local.z),"changed":false,"revision":0}; canvas._painting=true; _dab(canvas._brush_hit.local,event.ctrl_pressed,true); return true
func _dab(point: Vector3,invert: bool,first: bool=false) -> void:
	var terrain:=_stroke.terrain as KiwiEnvironmentTerrain; var source:=_stroke.source as KiwiTerrainBiomes; var center:=Vector2(point.x,point.z); var last: Vector2=_stroke.last; var spacing:=maxf(.01,canvas.brush_radius*canvas.brush_spacing)
	if not first and center.distance_to(last)<spacing: return
	var count:=clampi(ceili(center.distance_to(last)/spacing),1,32); var changed:={}; var mask: PackedFloat32Array=source.paint_masks[biome_id]; var radius:=maxf(.01,float(canvas.brush_radius)); var erase: bool=(canvas.environment_tool=="Erase biome")!=invert
	for index in range(1,count+1):
		var p:=last.lerp(center,float(index)/count); var centers: Array[Vector2]=[p]
		if canvas.brush_symmetry_x and not centers.has(Vector2(-p.x,p.y)): centers.append(Vector2(-p.x,p.y))
		if canvas.brush_symmetry_z:
			for existing in centers.duplicate():
				if not centers.has(Vector2(existing.x,-existing.y)): centers.append(Vector2(existing.x,-existing.y))
		for at in centers:
			var grid: Vector2=(at/terrain.dimensions+Vector2.ONE*.5)*(terrain.resolution-1); var extent: Vector2=Vector2.ONE*radius/(terrain.dimensions/(terrain.resolution-1)); var low:=Vector2i((grid-extent).floor()).max(Vector2i.ZERO); var high:=Vector2i((grid+extent).ceil()).min(Vector2i.ONE*(terrain.resolution-1))
			for z in range(low.y,high.y+1):
				for x in range(low.x,high.x+1):
					var offset:=Vector2(terrain.position(x,z).x,terrain.position(x,z).z)-at; var distance:=maxf(absf(offset.x),absf(offset.y)) if canvas.brush_square else offset.length()
					if distance>radius: continue
					var sample:=x+z*terrain.resolution; var value:=clampf(mask[sample]+float(canvas.brush_strength)*pow(maxf(0.,1.-distance/radius),maxf(.01,float(canvas.brush_falloff)))*(-1. if erase else 1.),0.,1.)
					if is_equal_approx(value,mask[sample]): continue
					mask[sample]=value; changed[sample]=true
	source.paint_masks[biome_id]=mask; _stroke.last=center
	if changed.is_empty(): return
	_stroke.changed=true; _preview_revision+=1; source.refresh_samples(terrain,changed.keys(),_stroke.noises); terrain.biome_data["preview_revision"]=_preview_revision; canvas.request_sync()
func cancel() -> void:
	if _stroke.is_empty(): return
	(_stroke.terrain as KiwiEnvironmentTerrain).biome_data=_stroke.original; _stroke={}; canvas._painting=false; canvas.request_sync(); canvas.overlay.queue_redraw()
