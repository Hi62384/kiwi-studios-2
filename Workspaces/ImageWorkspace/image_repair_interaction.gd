extends RefCounted
signal settings_changed
var canvas: Control
var engine:=preload("res://Workspaces/ImageWorkspace/image_repair_engine.gd").new()
var workspace: Control
var mode:="spot"
var main_mode:="repair"
var repair_source:="nearby"
var repair_method:="natural"
var texture_source:="procedural"
var material: KiwiTextureMaterial
var material_instances: Dictionary={}
var custom_materials: Dictionary={}
var mode_settings: Dictionary={}
var favorites:=PackedStringArray()
var recent:=PackedStringArray()
var _material_generation:=0
var _editable_texture:=false
var _coverage_base: Image
var _fill_bounds:=Rect2i()
var _fill_mask: Image
var config: Dictionary={"size":40.0,"hardness":.3,"strength":1.0,"opacity":1.0,"selection_only":true,"aligned":true,"sample_mode":"current","source_mode":"nearby","sample_shape":"rectangle","sample_size":64.0,"healing_blend":"texture","texture_preservation":1.0,"patch_size":16,"quality":1,"search_radius":3,"variation":.3,"scale":1.0,"rotation":0.0,"offset":Vector2.ZERO,"spacing":0.0,"density":1.0,"random_rotation":15.0,"random_scale":.15,"color_variation":.1,"seed":0,"layout":"tiled","behavior":"exact","new_layer":false,"clip_alpha":false}
var recipe:=KiwiImageTextureRecipe.new()
var active:=false
var ending:=false
var sampling:=false
var source_area:=Rect2i()
var source_point:=Vector2.ZERO
var sample_document_point:=Vector2.ZERO
var source_image: Image
var source_points:=PackedVector2Array()
var pattern_path:=""
var _owner: KiwiImageLayer
var _document: KiwiImageDocument
var _original: Image
var _editing: Image
var _points:=PackedVector2Array()
var _last:=Vector2.ZERO
var _anchor:=Vector2.ZERO
var _aligned_offset:=Vector2.ZERO
var _has_alignment:=false
var _area:=Rect2i()
var _latest:=0
var _completed:=0
var _changed:=false
var _pending:=false
var _sample_start:=Vector2.ZERO
var _generation_target:=""
var _generation_document: KiwiImageDocument
var _generation_sequence:=0
var _sample_down:=false
var _cached_procedural: Image
var _procedural_key:=0
var _selection: Image
var _pressures:=PackedFloat32Array()
var _layer_mask: Image
var selection_preview:=false
var _patch_drag:=false
var _patch_rect:=Rect2i()
var _repair_new_layer:=false
var _stroke_source_anchor:=Vector2.ZERO
var _selected_before: Array[String]=[]
var pick_source:=false
var _sample_region_dragged:=false

func initialize(studio: Control) -> void:
	workspace=studio; canvas=studio.canvas
	material=preload("res://Workspaces/ImageWorkspace/texture_material_library.gd").create("wood/oak")
	config.editable_texture=true
	canvas.add_child(engine); engine.preview.connect(_on_preview); engine.idle.connect(_on_idle)

func settings() -> Dictionary:
	return {"mode":mode,"main_mode":main_mode,"repair_source":repair_source,"repair_method":repair_method,"texture_source":texture_source,"material":material.copy_material() if material!=null else null,"instances":material_instances.duplicate(),"custom_materials":custom_materials.duplicate(),"mode_settings":mode_settings.duplicate(true),"favorites":favorites,"recent":recent,"config":config.duplicate(true),"recipe":recipe.copy_recipe(),"pattern_path":pattern_path,"source_point":source_point,"source_area":source_area}
func restore_settings(state: Dictionary) -> void:
	mode=state.get("mode","spot"); config.merge(state.get("config",{}),true)
	main_mode=state.get("main_mode","texture" if mode in ["procedural","pattern_fill"] else "repair")
	repair_source=state.get("repair_source","sample" if mode in ["clone","heal","pattern_heal"] else "nearby"); repair_method=state.get("repair_method","exact" if mode=="clone" else "natural")
	texture_source=state.get("texture_source","procedural")
	custom_materials=state.get("custom_materials",{}).duplicate(); mode_settings=state.get("mode_settings",{}).duplicate(true)
	if state.get("material") is KiwiTextureMaterial: material=state.material.copy_material()
	material_instances=state.get("instances",{}).duplicate(); favorites=state.get("favorites",PackedStringArray()); recent=state.get("recent",PackedStringArray())
	for id in material_instances:
		if material_instances[id] is KiwiTextureMaterial: material_instances[id]=material_instances[id].copy_material()
	if state.get("recipe") is KiwiImageTextureRecipe: recipe=state.recipe.copy_recipe()
	pattern_path=state.get("pattern_path",""); source_point=state.get("source_point",Vector2.ZERO); source_area=state.get("source_area",Rect2i())
	if FileAccess.file_exists(pattern_path):
		if pattern_path.get_extension() in ["tres","res"]:
			var resource:=ResourceLoader.load(pattern_path)
			if resource is KiwiImagePatternPreset and resource.texture!=null: source_image=resource.texture.get_image()
			elif resource is Texture2D: source_image=resource.get_image()
		else: source_image=Image.load_from_file(pattern_path)

func layer() -> KiwiImageLayer:
	if canvas.selected.is_empty(): return null
	return canvas.document.layer_for_id(canvas.selected[-1])
func to_pixel(document_point: Vector2,item: KiwiImageLayer) -> Vector2:
	return item.unproject_point(canvas.document.world_transform(item).affine_inverse()*document_point)/item.dimensions*Vector2(item.texture.get_size())
func to_screen(pixel: Vector2,item: KiwiImageLayer) -> Vector2:
	return canvas.origin()+canvas.document.world_transform(item)*item.project_point(pixel/Vector2(item.texture.get_size())*item.dimensions)*canvas.zoom

func sample_source(document_point: Vector2) -> void:
	var item:=layer()
	if item==null: return
	if config.sample_mode=="current":
		if item.texture==null: return
		source_image=item.texture.get_image().duplicate(); source_point=to_pixel(document_point,item)
	else:
		var document: KiwiImageDocument=workspace.document
		workspace.renderer.sync(document)
		if config.sample_mode=="group" and not item.parent_id.is_empty(): source_image=await workspace._render_layers([item.parent_id])
		else: source_image=await workspace.renderer.flattened()
		if workspace.document!=document: return
		source_point=document_point
	if source_image==null or not Rect2(Vector2.ZERO,Vector2(source_image.get_size())).has_point(source_point):
		source_image=null; source_area=Rect2i(); sampling=false; canvas.hint_changed.emit("Choose a source inside the image"); return
	sample_document_point=document_point; _has_alignment=false
	if mode in ["heal","clone","pattern_heal","pattern_fill","patch"]: config.source_mode="manual"
	var size:=maxi(2,int(config.sample_size)); source_area=Rect2i(Vector2i(source_point)-Vector2i.ONE*size/2,Vector2i.ONE*size).intersection(Rect2i(Vector2i.ZERO,source_image.get_size()))
	canvas.hint_changed.emit("Source sampled · Alt-drag to choose a texture region"); canvas.queue_redraw()
	sampling=_sample_down; _sample_region_dragged=false; _sample_start=source_point; source_points=PackedVector2Array([source_point]); settings_changed.emit()

func handle(event: InputEvent) -> bool:
	if event is InputEventMouseMotion:
		if canvas._drag=="pan": return false
		canvas._mouse=event.position
		if sampling and source_image!=null:
			var item:=layer(); var p: Vector2=canvas.to_document(event.position)
			if item!=null and config.sample_mode=="current": p=to_pixel(p,item)
			if _sample_start.distance_to(p)>=2: _sample_region_dragged=true
			if _patch_drag:
				var shifted:=Rect2i(_patch_rect.position+Vector2i((p-_sample_start).round()),_patch_rect.size)
				source_area=shifted.intersection(Rect2i(Vector2i.ZERO,source_image.get_size())); source_point=Rect2(source_area).get_center()
				canvas.queue_redraw(); refresh_selection_preview(); return true
			source_points.append(p)
			source_area=Rect2i(Vector2i(_sample_start.min(p)),Vector2i((_sample_start-p).abs().ceil())).intersection(Rect2i(Vector2i.ZERO,source_image.get_size()))
		elif active and not ending and not selection_preview:
			var point:=to_pixel(canvas.to_document(event.position),_owner)
			var distance:=point.distance_to(_last); var steps:=clampi(ceili(distance/maxf(1,float(config.size)*.2)),1,128)
			if main_mode=="texture" and material.application!="continuous":
				var spacing:=maxf(1,float(config.size)*material.spacing)
				if distance<spacing: canvas.queue_redraw(); return true
				steps=clampi(floori(distance/spacing),1,128)
			for i in range(1,steps+1):
				_points.append(_last.lerp(point,float(i)/steps)); _pressures.append(event.pressure if event.pen_inverted or event.pressure>0 else 1.0)
			_last=point; _pending=true
			if _editable_texture and material.alignment=="stroke" and material.follow_direction and _points.size()>1:
				var current: KiwiTextureMaterial=_owner.properties.texture_material
				var direction:=(_points[-1]-_points[-2]).angle()+deg_to_rad(material.rotation)
				current.rotation=rad_to_deg(lerp_angle(deg_to_rad(current.rotation),direction,1-material.direction_smoothing*.95))
		canvas.queue_redraw(); return true
	if not event is InputEventMouseButton: return false
	canvas._mouse=event.position
	if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
		if event.pressed and event.shift_pressed:
			config.size=clampf(float(config.size)*(1.1 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1/1.1),2,1024); settings_changed.emit(); return true
		return false
	if event.button_index==MOUSE_BUTTON_MIDDLE or Input.is_key_pressed(KEY_SPACE): return false
	if event.button_index==MOUSE_BUTTON_RIGHT and event.pressed: cancel(); sampling=false; return true
	if event.button_index!=MOUSE_BUTTON_LEFT: return false
	if not event.pressed:
		_sample_down=false
		if sampling:
			sampling=false
			_patch_drag=false
			if source_area.size.x<2 or source_area.size.y<2:
				var extent:=maxi(2,int(config.sample_size)); source_area=Rect2i(Vector2i(source_point)-Vector2i.ONE*extent/2,Vector2i.ONE*extent).intersection(Rect2i(Vector2i.ZERO,source_image.get_size()))
			elif _sample_region_dragged: source_point=Rect2(source_area).get_center()
			refresh_selection_preview(); settings_changed.emit(); return true
		if selection_preview: return true
		finish(); return true
	if selection_preview and active and not event.alt_pressed and not pick_source: return true
	var item:=layer()
	if item==null or not canvas.document.can_edit(item): canvas.hint_changed.emit("Select an unlocked raster layer"); return true
	if item.texture==null or item.kind not in ["image","paint","basic"]: canvas.hint_changed.emit("Rasterize this layer to repair individual pixels"); return true
	if item.warp!=null: canvas.hint_changed.emit("Bake the layer's warp before repairing its pixels"); return true
	if main_mode=="repair" and item.properties.get("texture_material") is KiwiTextureMaterial: canvas.hint_changed.emit("Bake this material layer before repairing pixels"); return true
	if main_mode=="repair" and (event.alt_pressed or pick_source):
		pick_source=false
		_sample_down=true
		if mode=="patch" and config.source_mode=="manual" and config.sample_mode=="current" and canvas.selection!=null:
			begin_patch_source(canvas.to_document(event.position),item); return true
		sample_source(canvas.to_document(event.position)); return true
	if main_mode=="texture":
		mode="pattern_fill"
		if source_image==null: refresh_material(); canvas.hint_changed.emit("Preparing material…"); return true
	else: mode="spot" if repair_source=="nearby" else ("clone" if repair_method=="exact" else "heal")
	if mode=="procedural":
		var key:=hash([recipe.kind,recipe.settings])
		if _cached_procedural==null or key!=_procedural_key:
			canvas.hint_changed.emit("Generate the procedural texture preview first"); generate(); return true
		source_image=_cached_procedural; source_area=Rect2i(Vector2i.ZERO,source_image.get_size())
	if mode in ["clone","heal","pattern_fill"] and source_image==null:
		canvas.hint_changed.emit("Alt-click to sample a source, or load a pattern"); return true
	begin(item,to_pixel(canvas.to_document(event.position),item)); return true

func begin(item: KiwiImageLayer,point: Vector2,fill: bool=false) -> void:
	if active or engine.busy(): return
	workspace._finish_pending(); canvas.gesture_started.emit()
	_selected_before.assign(canvas.selected)
	_owner=item; _document=canvas.document; _original=item.texture.get_image().duplicate(); _editing=_original.duplicate()
	_selection=canvas.selection.duplicate() if canvas.selection!=null and (config.selection_only or fill) else null
	_layer_mask=item.mask.get_image().duplicate() if item.mask!=null else null
	_repair_new_layer=bool(config.new_layer)
	_editable_texture=main_mode=="texture" and material.application=="continuous" and config.get("editable_texture",true)
	if _editable_texture:
		var existing: KiwiTextureMaterial=item.properties.get("texture_material")
		if existing==null or material.alignment=="stroke":
			var overlay:=item.copy_layer(); overlay.id=ActorData.new_id(); overlay.label=material.label+" material"; overlay.kind="basic"; overlay.effects.clear(); overlay.mask=null; overlay.warp=null
			overlay.properties.clear(); overlay.texture=item.texture; overlay.paint_base=item.texture; canvas.document.layers.append(overlay); canvas.selected.assign([overlay.id]); _owner=overlay
			existing=material.copy_material(); existing.source=item.texture; _owner.properties.texture_material=existing
			if material.alignment=="stroke":
				existing.mapping_origin=point/Vector2(_original.get_size())*item.dimensions
				var rng:=RandomNumberGenerator.new(); rng.seed=hash([point,material.parameters.get("seed",0)]); existing.rotation+=rng.randf_range(-1,1)*material.random_rotation
		_coverage_base=existing.coverage.get_image().duplicate() if existing.coverage!=null else Image.create(_original.get_width(),_original.get_height(),false,Image.FORMAT_RGBA8)
		_editing=_coverage_base.duplicate()
		existing.coverage=ImageTexture.create_from_image(_editing)
	if config.new_layer and not _editable_texture:
		var copy:=item.copy_layer(); copy.id=ActorData.new_id(); copy.label=NAMES_MODE_LABEL(mode)+" repair"
		copy.kind="basic"; copy.effects.clear(); copy.mask=null; copy.warp=null; copy.opacity=1
		copy.properties.erase("texture_recipe")
		_editing=Image.create(_original.get_width(),_original.get_height(),false,Image.FORMAT_RGBA8)
		copy.texture=ImageTexture.create_from_image(_editing); copy.paint_base=copy.texture
		canvas.document.layers.append(copy); canvas.selected.assign([copy.id]); _owner=copy
	_points=PackedVector2Array([point]); _last=point; _area=Rect2i(); _changed=false; active=true; ending=false; _pending=true
	_pressures=PackedFloat32Array([1.0])
	if not _editable_texture: _owner.texture=ImageTexture.create_from_image(_editing)
	_anchor=point
	if source_image==null or (mode in ["spot","pattern_heal","patch"] and config.source_mode=="nearby"):
		source_image=_original; source_area=Rect2i(Vector2i.ZERO,source_image.get_size()); source_point=point
	if config.aligned:
		if not _has_alignment: _aligned_offset=source_point-point; _has_alignment=true
		_stroke_source_anchor=point+_aligned_offset
	else: _stroke_source_anchor=source_point
	if fill: _pending=false; selection_preview=true; _queue(true)
	canvas._drag="repair"; canvas.hint_changed.emit(("Painting "+material.label if main_mode=="texture" else "Repair preview…")+" · Esc cancels")

func process() -> void:
	if not active or ending or not _pending or canvas._drag=="pan": return
	_queue(); _pending=false

func _queue(fill: bool=false,final: bool=false) -> void:
	var extent:=_original.get_size(); var radius:=float(config.size)*.5
	if main_mode=="texture" and material.application=="scatter": radius*=1+material.jitter*2
	var bounds:=Rect2(_points[0],Vector2.ZERO)
	for p in _points: bounds=bounds.expand(p)
	_area=Rect2i(Vector2i(bounds.position.floor()-Vector2.ONE*radius),Vector2i(bounds.size.ceil()+Vector2.ONE*radius*2)).intersection(Rect2i(Vector2i.ZERO,extent))
	if fill: _area=_fill_bounds.intersection(Rect2i(Vector2i.ZERO,extent)) if _fill_bounds.has_area() else Rect2i(Vector2i.ZERO,extent)
	if not _area.has_area(): return
	var settings:=config.duplicate(true)
	if main_mode=="texture": settings.rotation=material.rotation; settings.scale=material.texture_size/64.0; settings.sample_shape="rectangle"; settings.behavior="exact"
	if main_mode=="texture":
		settings.application=material.application; settings.jitter=material.jitter; settings.random_rotation=material.random_rotation; settings.random_scale=material.random_scale; settings.follow_direction=material.follow_direction
		settings.material_blending=material.blending
		settings.stamp_extent=material.texture_size
		if material.application!="continuous": settings.scale=material.texture_size/256.0
		elif not _editable_texture: settings.scale=1.; settings.rotation=0.; settings.material_blending="replace"
	settings.sample_points=source_points.duplicate()
	settings.pressures=_pressures.duplicate()
	settings.source_center=source_point
	settings.new_layer=_repair_new_layer
	if not final: settings.quality=0
	var job:={"kind":mode,"original":_original,"sample":source_image,"source_area":source_area,"source_anchor":_stroke_source_anchor,"destination_anchor":_anchor,"settings":settings,"area":_area,"points":_points.duplicate(),"fill":fill,"automatic":mode in ["spot","pattern_heal","patch"] and config.source_mode=="nearby","reference":_owner.copy_layer(),"frame":canvas.document.world_transform(_owner)}
	job.layer_mask=_layer_mask
	job.editable_texture=_editable_texture
	if _editable_texture: job.prior_coverage=_coverage_base
	if _selection!=null:
		job.selection=_selection; job.selection_inverse=canvas.selection_inverse
		if canvas.selection_inverse_warp.is_valid():
			job.selection_reference=canvas.document.pixel_selection_reference.copy_layer() if canvas.document.pixel_selection_reference!=null else null
			job.selection_world=canvas.document.pixel_selection_reference_world
	if fill and _fill_mask!=null: job.local_selection=_fill_mask
	if settings.sample_mode!="current": job.sample_basis=canvas.document.world_transform(_owner).scaled_local(_owner.dimensions/Vector2(_original.get_size()))
	_latest=engine.submit(job)

func finish() -> void:
	if not active: return
	var was_selection:=selection_preview
	selection_preview=false
	if mode in ["patch","pattern_heal"] or (mode in ["pattern_fill","procedural"] and config.behavior=="synthesis"): _queue(was_selection,true)
	elif _pending: _queue(); _pending=false
	if not _area.has_area(): cancel(); return
	ending=true; _on_idle()

func cancel() -> void:
	engine.cancel(); _generation_target=""
	_material_generation+=1
	selection_preview=false; sampling=false; _patch_drag=false; _sample_down=false; pick_source=false
	if not active: return
	active=false; ending=false; _pending=false; canvas._drag=""; canvas.gesture_cancelled.emit()
	canvas.selected.assign(_selected_before); canvas.selection_changed.emit(); canvas.queue_redraw()

func _on_preview(result: Dictionary) -> void:
	if result.kind=="generate":
		if result.sequence!=_generation_sequence: return
		_cached_procedural=result.image; _procedural_key=hash([recipe.kind,recipe.settings])
		source_image=_cached_procedural; source_area=Rect2i(Vector2i.ZERO,source_image.get_size()); source_point=Vector2.ZERO; pattern_path=""
		config.sample_mode="current"; config.sample_shape="rectangle"; source_points.clear()
		if not _generation_target.is_empty() and workspace.document==_generation_document:
			if _generation_target=="::new::":
				workspace._action(func():
					var target:=KiwiImageLayer.create("image",workspace.document.canvas_size); target.label=recipe.kind.capitalize()+" texture"
					target.texture=ImageTexture.create_from_image(result.image); target.paint_base=target.texture; target.properties.texture_recipe=recipe.copy_recipe()
					target.opacity=float(config.opacity); target.blend=int(config.get("blend",0)); target.clip_to_below=config.clip_alpha
					workspace.document.layers.append(target); canvas.selected.assign([target.id]))
			else:
				var target: KiwiImageLayer=workspace.document.layer_for_id(_generation_target)
				if target!=null: workspace._action(func(): target.texture=ImageTexture.create_from_image(result.image); target.properties.texture_recipe=recipe.copy_recipe())
		_generation_target=""; canvas.hint_changed.emit("Procedural texture ready"); settings_changed.emit(); return
	if not active or canvas.document!=_document or canvas.document.layer_for_id(_owner.id)!=_owner: return
	if _editable_texture:
		_editing.blit_rect(result.coverage,Rect2i(Vector2i.ZERO,result.coverage.get_size()),result.area.position)
		_owner.properties.texture_material.coverage=ImageTexture.create_from_image(_editing); _completed=result.sequence; _changed=true; canvas.gesture_changed.emit(); canvas.queue_redraw(); return
	_editing.blit_rect(result.image,Rect2i(Vector2i.ZERO,result.image.get_size()),result.area.position)
	(_owner.texture as ImageTexture).update(_editing); _completed=result.sequence; _changed=true; canvas.gesture_changed.emit(); canvas.queue_redraw()

func _on_idle() -> void:
	if not active or not ending or engine.busy() or _completed!=_latest: return
	active=false; ending=false; canvas._drag=""
	if _changed:
		if not _editable_texture: _owner.texture=ImageTexture.create_from_image(_editing)
		canvas.gesture_finished.emit()
	else: canvas.gesture_cancelled.emit()
	canvas.hint_changed.emit("Texture paint complete" if main_mode=="texture" else "Repair complete"); canvas.queue_redraw()

func fill_selection() -> void:
	if active and selection_preview: _queue(true); return
	var item:=layer()
	if item==null or item.texture==null or canvas.selection==null: canvas.hint_changed.emit("Select pixels on a raster layer first"); return
	if main_mode=="repair" and item.properties.get("texture_material") is KiwiTextureMaterial: canvas.hint_changed.emit("Bake this material layer before repairing pixels"); return
	var document: KiwiImageDocument=canvas.document
	var local_mask: Texture2D=await preload("res://Workspaces/ImageWorkspace/image_selection_fill.gd").capture_local_mask(workspace,item)
	if local_mask==null or canvas.document!=document or layer()!=item: return
	_fill_mask=local_mask.get_image()
	if _fill_mask.get_size()!=Vector2i(item.texture.get_size()): _fill_mask.resize(item.texture.get_width(),item.texture.get_height(),Image.INTERPOLATE_BILINEAR)
	_fill_bounds=_fill_mask.get_used_rect()
	if not _fill_bounds.has_area(): canvas.hint_changed.emit("Select pixels first"); return
	_fill_bounds=_fill_bounds.grow(4)
	mode="pattern_fill" if main_mode=="texture" else ("patch" if repair_source=="nearby" else ("clone" if repair_method=="exact" else "heal"))
	if main_mode=="texture" and source_image==null: await refresh_material()
	config.source_mode="nearby" if main_mode=="repair" and repair_source=="nearby" else "manual"
	if mode=="procedural":
		if _cached_procedural==null: generate(); return
		source_image=_cached_procedural; source_area=Rect2i(Vector2i.ZERO,source_image.get_size())
	if source_image==null and config.source_mode!="nearby": canvas.hint_changed.emit("Sample a source first"); return
	begin(item,Vector2(item.texture.get_size())*.5,true)

func refresh_selection_preview() -> void:
	if selection_preview and active:
		if _repair_new_layer!=bool(config.new_layer): cancel(); fill_selection()
		else: _queue(true)

func configure(key: String,value: Variant) -> void:
	config[key]=value; refresh_selection_preview()

func choose_material(id: String) -> void:
	if material!=null: material_instances[material.material_id]=material.copy_material()
	material=material_instances[id].copy_material() if material_instances.get(id) is KiwiTextureMaterial else preload("res://Workspaces/ImageWorkspace/texture_material_library.gd").create(id)
	recent.erase(id); recent.insert(0,id)
	if recent.size()>20: recent.resize(20)
	texture_source="procedural"; apply_material_settings(); refresh_material(); settings_changed.emit()

func switch_mode(next: String) -> void:
	if next==main_mode: return
	cancel(); mode_settings[main_mode]=config.duplicate(true); main_mode=next
	if mode_settings.has(next): config.merge(mode_settings[next],true)
	source_image=null; _has_alignment=false
	if main_mode=="texture": refresh_material()

func apply_material_settings(live: bool=false) -> void:
	var item:=layer()
	if item!=null and item.properties.get("texture_material") is KiwiTextureMaterial:
		var operation:=func():
			var old: KiwiTextureMaterial=item.properties.texture_material; var updated:=material.copy_material(); updated.coverage=old.coverage; updated.source=old.source; item.properties.texture_material=updated
		if live: workspace._begin(); operation.call(); workspace._preview()
		else: workspace._action(operation)

func refresh_material() -> void:
	if material==null: return
	source_image=null
	if config.get("editable_texture",true) and material.application=="continuous":
		source_image=Image.create(1,1,false,Image.FORMAT_RGBA8); source_image.fill(Color.WHITE); source_area=Rect2i(0,0,1,1); return
	_material_generation+=1; var generation:=_material_generation; var owner: KiwiImageDocument=workspace.document
	var preview_value:=material.copy_material(); preview_value.coverage=null; preview_value.blending="replace"; preview_value.rotation=0; preview_value.texture_size=64
	if material.application!="continuous": preview_value.texture_size=256
	var size:=Vector2i(256,256); var extent:=Vector2(size); var frame:=Transform2D.IDENTITY
	if material.application=="continuous" and layer()!=null:
		var item:=layer(); preview_value=material.copy_material(); preview_value.coverage=null; preview_value.source=item.texture
		size=item.texture.get_size(); extent=item.dimensions; frame=owner.world_transform(item)
	var result: Image=await preload("res://Workspaces/ImageWorkspace/texture_material_renderer.gd").preview(canvas,preview_value,size,extent,frame)
	if result==null or generation!=_material_generation or workspace.document!=owner: return
	source_image=result; source_area=Rect2i(Vector2i.ZERO,result.get_size()); source_point=Vector2.ZERO; config.source_mode="manual"; config.scale=1.0
	canvas.hint_changed.emit(material.label+" ready · Paint or Fill selection")

func begin_patch_source(at: Vector2,item: KiwiImageLayer) -> void:
	# Drag the repair's selection-shaped footprint onto clean source content.
	# The source snapshot is frozen, including while a repair preview is open.
	source_image=_original if active else item.texture.get_image().duplicate()
	var used: Rect2i=canvas.selection.get_used_rect()
	if not used.has_area(): return
	var bounds:=Rect2(); var first:=true
	for point in [Vector2(used.position),Vector2(used.end.x,used.position.y),Vector2(used.end),Vector2(used.position.x,used.end.y)]:
		var document_point: Vector2=canvas.selection_forward_warp.call(point) if canvas.selection_forward_warp.is_valid() else canvas.selection_transform*point
		var local:=to_pixel(document_point,item)
		if first: bounds=Rect2(local,Vector2.ZERO); first=false
		else: bounds=bounds.expand(local)
	_patch_rect=Rect2i(Vector2i(bounds.position.floor()),Vector2i(bounds.size.ceil()))
	source_area=_patch_rect.intersection(Rect2i(Vector2i.ZERO,source_image.get_size())); source_point=Rect2(source_area).get_center()
	config.sample_shape="rectangle"; source_points.clear(); sampling=true; _patch_drag=true; _sample_region_dragged=true; _sample_start=to_pixel(at,item)
	sample_document_point=at; canvas.hint_changed.emit("Drag the selection onto clean source texture · release to sample")

func generate(target_id: String="") -> void:
	_generation_target=target_id; _generation_document=workspace.document
	var extent: Vector2i=workspace.document.canvas_size if target_id=="::new::" else (Vector2i(layer().dimensions.ceil()) if layer()!=null and not target_id.is_empty() else Vector2i(256,256))
	var ratio:=minf(1,1024.0/maxi(extent.x,extent.y))
	_generation_sequence=engine.submit({"kind":"generate","recipe":recipe.copy_recipe(),"size":Vector2i((Vector2(extent)*ratio).round()).max(Vector2i.ONE),"target":target_id})
	canvas.hint_changed.emit("Generating texture…")

func draw() -> void:
	var item:=layer()
	if item!=null and item.texture!=null and canvas.get_global_rect().has_point(canvas.get_global_mouse_position()):
		var center:=to_pixel(canvas.to_document(canvas._mouse),item); var outline:=PackedVector2Array()
		for i in 49: outline.append(to_screen(center+Vector2(cos(TAU*i/48.0),sin(TAU*i/48.0))*float(config.size)*.5,item))
		canvas.draw_polyline(outline,Color.BLACK,3,true); canvas.draw_polyline(outline,Color("a2e9e0"),1,true)
	if source_image!=null and main_mode=="repair":
		var point: Vector2=canvas.origin()+sample_document_point*canvas.zoom
		if active and mode in ["clone","heal"] and config.sample_mode=="current": point=to_screen(_stroke_source_anchor+(_last-_anchor),_owner)
		canvas.draw_line(point-Vector2(9,0),point+Vector2(9,0),Color("ffc578"),2,true)
		canvas.draw_line(point-Vector2(0,9),point+Vector2(0,9),Color("ffc578"),2,true)
		if active: canvas.draw_line(point,canvas._mouse,Color(1,.75,.4,.4),1,true)
		if source_area.has_area():
			var rect:=Rect2(canvas.origin()+Vector2(source_area.position)*canvas.zoom,Vector2(source_area.size)*canvas.zoom)
			if config.sample_mode=="current" and item!=null and item.texture!=null:
				var corners:=PackedVector2Array()
				var source_outline:=PackedVector2Array()
				if config.sample_shape=="lasso" and source_points.size()>2:
					source_outline=source_points.duplicate(); source_outline.append(source_points[0])
				elif config.sample_shape=="circle":
					for i in 49: source_outline.append(Rect2(source_area).get_center()+Vector2(cos(TAU*i/48.0),sin(TAU*i/48.0))*Vector2(source_area.size)*.5)
				else: source_outline=PackedVector2Array([Vector2(source_area.position),Vector2(source_area.end.x,source_area.position.y),Vector2(source_area.end),Vector2(source_area.position.x,source_area.end.y),Vector2(source_area.position)])
				for p in source_outline: corners.append(to_screen(p,item))
				canvas.draw_polyline(corners,Color(1,.75,.4,.7),1,true)
			else: canvas.draw_rect(rect,Color(1,.75,.4,.7),false,1)

static func NAMES_MODE_LABEL(kind: String) -> String: return kind.replace("_"," ").capitalize()
