class_name KiwiPhysicsInspector
extends RefCounted
var inspector: Control
var actor: ActorData
var model: RefCounted
var panel: VBoxContainer
var settings: Dictionary
static func build(host: Control, data: ActorData, parent: VBoxContainer) -> void:
	var editor := KiwiPhysicsInspector.new(); editor.inspector=host; editor.actor=data; editor.model=host.model; editor.panel=parent; editor.settings=KiwiPhysicsSettings.sample(data,data.animation_time if not is_nan(data.animation_time) else 0.0); editor._build()
func _change(key: String, value: Variant, rebuild: bool=false) -> void:
	if key=="mode" and int(value)==3 and _editor()!=null:
		_editor().physics.freeze(model,actor); inspector._queue_rebuild_selected(); return
	KiwiPhysicsSettings.edit(model,actor,key,value)
	if rebuild: inspector._queue_rebuild_selected()
func _heading(text: String) -> void: inspector._add_label(panel,text)
func _property(key: String, title: String, parent: VBoxContainer, keyed: bool=true) -> HBoxContainer:
	var row:=HBoxContainer.new(); parent.add_child(row)
	var label:=Label.new(); label.text={"activation":"Activation (s)","influence":"Influence","gravity":"Gravity","damping":"Damping"}.get(key,title); label.tooltip_text=title; label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS; label.size_flags_horizontal=Control.SIZE_EXPAND_FILL; row.add_child(label)
	if keyed:
		var property:=ActorProperty.create(StringName("physics_"+key),title,settings.get(key),true); property.options.group="Physics"
		inspector._add_keyframe_button(row,actor,property,PackedStringArray(["physics",key]),settings.get(key))
	return row
func _check(key: String, title: String, parent: VBoxContainer, rebuild: bool=false) -> void:
	var row:=_property(key,title,parent)
	var input:=CheckButton.new(); input.name="Physics_"+key; input.button_pressed=bool(settings[key]); row.add_child(input)
	input.toggled.connect(func(value: bool): _change(key,value,rebuild))
	inspector._updaters.append(func(): input.set_pressed_no_signal(bool(KiwiPhysicsSettings.sample(actor,actor.animation_time if not is_nan(actor.animation_time) else 0.0)[key])))
func _choice(key: String, title: String, choices: Array, parent: VBoxContainer) -> void:
	_property(key,title,parent,false)
	var input:=OptionButton.new(); input.name="Physics_"+key; input.fit_to_longest_item=false; parent.add_child(input)
	for text: String in choices: input.add_item(text)
	if key=="mode" and (actor.type_id in [&"fluid",&"powder"] or int(settings.type)==9):
		for index in [0,2]: input.set_item_disabled(index,true)
		input.get_popup().set_item_tooltip(0,"Use Freeze to hold the grain state, or turn off Simulate grains for source preview." if actor.type_id==&"powder" else "Use Freeze to hold the reconstructed liquid surface.")
		input.get_popup().set_item_tooltip(2,"Spring-guided motion is not a granular control mode." if actor.type_id==&"powder" else "Spring-guided motion is not a liquid control mode.")
	if key=="mode" and settings.bake.get("frames",[]).is_empty() and not settings.bake.get("cache") is KiwiPhysicsBakeCache:
		input.set_item_disabled(4,true); input.get_popup().set_item_tooltip(4,"Use Bake… to create baked physics first.")
	input.select(clampi(int(settings[key]),0,choices.size()-1)); input.item_selected.connect(func(value: int): _change(key,value,true))
func _number(key: String, title: String, parent: VBoxContainer, low: float=0.0, high: float=1000.0, step: float=.01, keyed: bool=true) -> void:
	_property(key,title,parent,keyed)
	var input:=DragNumber.new(); input.name="Physics_"+key; input.min_value=low; input.max_value=high; input.step=step; input.size_flags_horizontal=Control.SIZE_EXPAND_FILL; input.set_value_no_signal(float(settings[key])); parent.add_child(input)
	_bind_number(input,key)
func _bind_number(input: DragNumber, key: String, axis: int=-1) -> void:
	var gesture:={"before":{},"tracks":[],"active":false}
	var convert:=func(value: float) -> Variant:
		if axis<0: return int(value) if input.step>=1.0 else value
		var next: Vector3=KiwiPhysicsSettings.sample(actor,actor.animation_time if not is_nan(actor.animation_time) else 0.0)[key]; next[axis]=value; return next
	input.interaction_started.connect(func(): gesture.before=KiwiPhysicsSettings.authored(actor); gesture.tracks=model.animation_snapshot(actor); gesture.active=true)
	input.preview_changed.connect(func(value: float):
		var normalized: Variant=convert.call(value)
		if actor.animation_track(PackedStringArray(["physics",key]))!=null: model.preview_animation_value(actor,PackedStringArray(["physics",key]),normalized)
		else:
			var next:=KiwiPhysicsSettings.authored(actor); next[key]=normalized; actor.values[&"physics"]=next; model.changed.emit())
	input.drag_committed.connect(func(value: float):
		if gesture.active:
			actor.values[&"physics"]=gesture.before.duplicate(true); actor.animation_previews.clear(); model.restore_animation(actor,gesture.tracks); gesture.active=false
		_change(key,convert.call(value)))
	input.drag_cancelled.connect(func():
		if gesture.active: gesture.active=false; actor.animation_previews.clear(); actor.values[&"physics"]=gesture.before.duplicate(true); model.restore_animation(actor,gesture.tracks))
	input.value_changed.connect(func(value: float): _change(key,convert.call(value)))
	input.interaction_ended.connect(func():
		if gesture.active and is_equal_approx(input.value,input._origin):
			gesture.active=false; actor.animation_previews.clear(); actor.values[&"physics"]=gesture.before.duplicate(true); model.restore_animation(actor,gesture.tracks))
	inspector._updaters.append(func():
		if gesture.active: return
		var value: Variant=KiwiPhysicsSettings.sample(actor,actor.animation_time if not is_nan(actor.animation_time) else 0.0)[key]
		input.set_value_no_signal(float(value) if axis<0 else value[axis]))
func _vector(key: String, title: String, parent: VBoxContainer) -> void:
	_property(key,title,parent)
	for axis in 3:
		var row:=HBoxContainer.new(); parent.add_child(row); var label:=Label.new(); label.text=["X","Y","Z"][axis]; row.add_child(label)
		var input:=DragNumber.new(); input.name="Physics_%s_%d"%[key,axis]; input.allow_greater=true; input.allow_lesser=true; input.step=.01; input.size_flags_horizontal=Control.SIZE_EXPAND_FILL; input.set_value_no_signal(settings[key][axis]); row.add_child(input)
		_bind_number(input,key,axis)
func _target(key: String, bone_key: String, title: String, parent: VBoxContainer) -> void:
	_property(key,title,parent,false)
	var choose:=OptionButton.new(); choose.name="Physics_"+key; choose.fit_to_longest_item=false; parent.add_child(choose); choose.add_item("World / animated actor"); choose.set_item_metadata(0,"")
	for candidate: ActorData in model.actors:
		if candidate!=actor and KiwiPhysicsSettings.compatible(candidate): choose.add_item(candidate.display_name); choose.set_item_metadata(choose.item_count-1,candidate.id)
	var selected:=-1
	for index in choose.item_count:
		if str(choose.get_item_metadata(index))==str(settings[key]): selected=index
	if selected<0: choose.add_item("⚠ Missing actor"); choose.set_item_metadata(choose.item_count-1,str(settings[key])); selected=choose.item_count-1
	choose.select(selected); choose.item_selected.connect(func(index: int): _change(key,str(choose.get_item_metadata(index)),true))
	var target: ActorData=model.actor_for_id(str(settings[key]))
	if target!=null and not (target.values.get(&"rig_bones",[]) as Array).is_empty():
		var bones:=OptionButton.new(); bones.name="Physics_"+bone_key; bones.fit_to_longest_item=false; bones.add_item("Actor origin"); bones.set_item_metadata(0,""); parent.add_child(bones)
		for bone: Dictionary in target.values[&"rig_bones"]: bones.add_item(str(bone.name)); bones.set_item_metadata(bones.item_count-1,str(bone.name))
		var found:=false
		for index in bones.item_count:
			if str(bones.get_item_metadata(index))==str(settings[bone_key]): bones.select(index); found=true
		if not found: bones.add_item("⚠ Missing: "+str(settings[bone_key])); bones.set_item_metadata(bones.item_count-1,str(settings[bone_key])); bones.select(bones.item_count-1)
		bones.item_selected.connect(func(index: int): _change(bone_key,str(bones.get_item_metadata(index)),true))
func _fold(title: String) -> VBoxContainer:
	var categories: Dictionary=inspector.ui_state._actor_state(actor.id).get("categories",{})
	if not categories.has("Physics:"+title): inspector.ui_state.set_category_expanded(actor.id,"Physics:"+title,false)
	return inspector._stateful_category(title,actor.id,panel,"Physics")
func _build() -> void:
	if int(settings.type)==9:
		_heading("Fog · timeline-controlled transport")
		_check("enabled","Simulation enabled",panel)
		_number("activation","Activation (source seconds)",panel,0,86400)
		_number("end","Stop at source seconds (-1 = no stop)",panel,-1,86400)
		_number("steps","Fixed steps / scene second",panel,30,120,1,false)
		_choice("mode","Control",KiwiPhysicsSettings.MODES,panel)
		_events(); _actions(); return
	if actor.type_id==&"powder":
		_heading("Powder · timeline-controlled granular contacts")
		_number("gravity","Gravity (m/s²)",panel,0,1000); _vector("gravity_direction","Gravity direction",panel)
		_vector("wind","Wind velocity (m/s)",panel)
		var collision:=_fold("Collision")
		_check("collision","Collisions enabled",collision); _number("layer","Collision layer bits",collision,1,2147483647,1,false); _number("mask","Collision mask bits",collision,0,2147483647,1,false)
		_target("attachment","attachment_bone","Source attachment",panel); _vector("pivot","Source offset",panel)
		_check("inherit_velocity","Inherit source velocity",panel)
		_number("activation","Activation (source seconds)",panel,0,86400)
		_number("end","Stop at source seconds (-1 = no stop)",panel,-1,86400)
		_number("steps","Fixed steps / scene second",panel,30,240,1,false)
		_choice("mode","Control",KiwiPhysicsSettings.MODES,panel)
		_events(); _actions(); return
	_check("enabled","Physics",panel,true)
	if not settings.enabled: return
	if KiwiGrowthPhysics.data(actor)!=null: _heading("Surface growth · guide simulation")
	elif actor.type_id!=&"fluid": _choice("type","Physics type",KiwiPhysicsSettings.TYPES,panel)
	else: _heading("Fluid · density-constrained liquid")
	_choice("mode","Control",KiwiPhysicsSettings.MODES,panel)
	_number("activation","Activation (source seconds)",panel,0,86400)
	if actor.type_id!=&"fluid": _number("influence","Physics influence",panel,0,1)
	var kind:=int(settings.type)
	if kind in [0,2]: _choice("body_mode","Motion",["Dynamic","Static collider","Animated collider"],panel)
	if int(settings.body_mode)==0 or kind not in [0,2]:
		_number("gravity","Gravity strength",panel,0,1000)
		if kind!=6: _number("mass","Mass",panel,.001,10000)
		_number("damping","Damping",panel,0,100)
	if kind in [2,3] or int(settings.mode)==2:
		_number("stiffness","Spring stiffness",panel,0,1000)
	if kind in [2,3]:
		_check("ragdoll","Articulated ragdoll (off = jiggle)",panel,true)
		_number("limit","Joint angle limit (degrees)",panel,0,180)
	if kind==2:
		_target("attachment","attachment_bone","Attachment",panel)
		_vector("pivot","Attachment offset",panel)
		_number("position_limit","Maximum travel",panel,0,1000)
		if settings.ragdoll:
			_choice("constraint","Joint",["Fixed","Hinge","Slider","Distance","Spring"],panel)
			_number("distance","Joint distance",panel,0,1000)
			if int(settings.constraint) in [1,2]: _vector("axis","Joint axis (attachment space)",panel)
			_vector("body_pivot","Pivot on this actor",panel)
	if kind==3: _bones()
	if kind==3: _heading("Bone-tip sphere contacts. Unchecked bones keep their normal animation.")
	if kind in [1,4,5]:
		_number("stretch","Stretch resistance",panel,0,1)
		if kind!=5: _number("bend","Bend resistance",panel,0,1)
		if kind==1: _number("recovery","Shape recovery",panel,0,100)
		if kind!=5: _choice("pin_region","Pin region",["None","Upper edge","Lower edge","Left edge"],panel)
		_target("attachment","attachment_bone","Pin / start attachment",panel)
	if kind==5:
		_number("rope_length","Rope length",panel,.01,1000)
		_number("rope_radius","Visible rope radius",panel,.002,10)
		_check("rope_start","Attach start",panel)
		_check("rope_end","Attach end",panel,true)
		if settings.rope_end: _target("end_actor","end_bone","End attachment",panel); _vector("end_offset","End offset",panel)
	if kind in [1,4,5]: _pins()
	if kind==8:
		_number("particles","Guide budget",panel,1,128,1,false)
		_number("stretch","Stretch resistance",panel,0,1)
		_number("bend","Bend resistance",panel,0,1)
		_number("recovery","Return to groom",panel,0,100)
		_vector("wind","Wind force",panel)
		_number("iterations","Constraint iterations",panel,1,24,1,false)
		_heading("Roots follow the animated surface. Bakes store guide points, not every strand.")
		var correct:=Button.new(); correct.text="Edit guide motion…"; panel.add_child(correct); correct.pressed.connect(func():
			var editor:=_editor()
			if editor!=null: preload("res://Workspaces/ModelWorkspace/growth/growth_motion_ui.gd").open(editor,actor,inspector))
	if kind in [1,4]: _heading("Point collisions against rigid colliders. Self-collision is not supported.")
	var collision:=_fold("Collision")
	if kind in [0,2] and int(settings.body_mode)==0:
		var water:=_fold("Water response"); _check("water_interaction","Environment water",water); _number("water_buoyancy","Buoyancy strength",water,0.,10.); _number("water_drag","Water drag",water,0.,10.)
	_check("collision","Collision enabled",collision)
	if kind in [0,2]:
		_choice("shape","Collision shape",["Automatic","Box","Sphere","Capsule","Cylinder","Convex hull","Static triangle mesh"],collision)
		_number("bounce","Bounciness",collision,0,1)
		_number("friction","Friction",collision,0,2)
		_check("collision_only","Collision only (hide mesh)",collision)
	elif kind!=6: _number("radius","Collision radius",collision,.002,10)
	_number("layer","Collision layer bits",collision,1,2147483647,1,false)
	_number("mask","Collision mask bits",collision,0,2147483647,1,false)
	if kind in [0,1,2,3,4,5]:
		var surface:=_fold("Powder surface")
		_check("powder_accumulation","Allow powder accumulation",surface)
		_number("powder_adhesion","Powder adhesion (N/grain)",surface,0,2,.001)
		_number("powder_max_coating","Maximum attached coating (m)",surface,.001,10)
	var advanced:=_fold("Advanced")
	if kind==6:
		_target("attachment","attachment_bone","Source attachment",advanced); _vector("pivot","Source offset",advanced)
		_vector("velocity","Initial / emission velocity",advanced); _check("inherit_velocity","Inherit source velocity",advanced)
		_heading("Rigid contacts are one-way. Bone / deformable contacts use approximate point proxies.")
	_vector("gravity_direction","Gravity direction",advanced)
	if kind in [0,2]: _vector("velocity","Initial velocity",advanced); _vector("angular_velocity","Initial angular velocity (degrees/s)",advanced); _check("inherit_velocity","Inherit animated velocity",advanced); _number("angular_damping","Angular damping",advanced,0,100)
	if kind in [1,4,5]:
		_number("particles","Maximum simulation points",advanced,8,256,1,false) if kind!=5 else _number("rope_points","Rope simulation points",advanced,3,96,1,false)
		_number("iterations","Constraint iterations",advanced,1,24,1,false); _vector("wind","Wind force",advanced)
	_number("steps","Fixed steps / scene second",advanced,30,240,1,false)
	_number("end","Stop at source seconds (-1 = no stop)",advanced,-1,86400)
	_events()
	_actions()
func _bones() -> void:
	var bones: Array=actor.values.get(&"rig_bones",[])
	if bones.is_empty():
		_heading("Select the model's Skeleton Rig actor to choose bones. Import or rig a model first.")
		for candidate: ActorData in model.actors:
			if candidate.values.get(&"rig_bones",[]).is_empty(): continue
			var select:=Button.new(); select.text="Select "+candidate.display_name; panel.add_child(select)
			select.pressed.connect(func():
				var clip: ActorClip=model.clip_for_actor_id(candidate.id)
				if clip!=null: model.select(clip.id); inspector.call_deferred("select_main_tab","Actor"); inspector.call_deferred("select_section","Physics"))
		return
	var search:=LineEdit.new(); search.placeholder_text="Search bones…"; search.text=str(actor.get_meta("physics_bone_search","")); panel.add_child(search)
	var tree:=Tree.new(); tree.name="PhysicsBones"; tree.hide_root=true; tree.select_mode=Tree.SELECT_MULTI; tree.custom_minimum_size.y=150; panel.add_child(tree)
	var root:=tree.create_item(); var items:=[]
	for i in bones.size():
		var item:=tree.create_item(items[int(bones[i].parent)] if int(bones[i].parent)>=0 and int(bones[i].parent)<items.size() else root)
		item.set_cell_mode(0,TreeItem.CELL_MODE_CHECK); item.set_text(0,str(bones[i].name)); item.set_metadata(0,i); item.set_editable(0,true); item.set_checked(0,settings.bones.has(str(bones[i].name))); items.append(item)
	var filter:=func(text: String):
		actor.set_meta("physics_bone_search",text)
		for item: TreeItem in items: item.visible=text.is_empty() or item.get_text(0).to_lower().contains(text.to_lower())
		for item: TreeItem in items:
			if item.visible:
				var parent:=item.get_parent()
				while parent!=null: parent.visible=true; parent=parent.get_parent()
	search.text_changed.connect(filter); filter.call(search.text)
	tree.item_edited.connect(func():
		var selected: Array=KiwiPhysicsSettings.authored(actor).bones.duplicate(); var edited:=tree.get_edited(); var name:=edited.get_text(0)
		if edited.is_checked(0) and not selected.has(name): selected.append(name)
		elif not edited.is_checked(0): selected.erase(name)
		_change("bones",selected,true))
	var selected_names:=func() -> Array:
		var names:=[]; var item:=tree.get_next_selected(null)
		while item!=null: names.append(item.get_text(0)); item=tree.get_next_selected(item)
		return names
	var controls:=HFlowContainer.new(); panel.add_child(controls)
	for action: String in ["All","None","Selected","Children","Chain","Mirror"]:
		var button:=Button.new(); button.text=action; controls.add_child(button)
		button.pressed.connect(func():
			var chosen: Array=selected_names.call(); var affected: Array=KiwiPhysicsSettings.authored(actor).bones.duplicate()
			if chosen.is_empty() and action not in ["All","None"]: chosen=affected.duplicate()
			if action=="All":
				affected.clear(); chosen.clear()
				for bone: Dictionary in bones: chosen.append(str(bone.name))
			if action=="None": affected.clear(); chosen.clear()
			if action=="Children":
				for i in bones.size():
					var parent:=int(bones[i].parent); var include:=false
					while parent>=0:
						if chosen.has(str(bones[parent].name)): include=true; break
						parent=int(bones[parent].parent)
					if include: chosen.append(str(bones[i].name))
			if action=="Chain":
				for name: String in chosen.duplicate():
					var index:=-1
					for i in bones.size():
						if str(bones[i].name)==name: index=i; break
					if index<0: continue
					var parent:=int(bones[index].parent); var path:=[]
					while parent>=0 and parent<bones.size():
						path.append(str(bones[parent].name))
						if chosen.has(str(bones[parent].name)):
							for link in path:
								if not chosen.has(link): chosen.append(link)
							break
						parent=int(bones[parent].parent)
					while index>=0:
						var children:=[]
						for i in bones.size():
							if int(bones[i].parent)==index: children.append(i)
						if children.size()!=1: break
						index=children[0]
						if not chosen.has(str(bones[index].name)): chosen.append(str(bones[index].name))
			if action=="Mirror":
				for name: String in chosen.duplicate():
					for pair in [[".L",".R"],["_L","_R"],["Left","Right"],["left","right"]]:
						var mirror:=name.replace(pair[0],pair[1]) if name.contains(pair[0]) else name.replace(pair[1],pair[0])
						for bone: Dictionary in bones:
							if str(bone.name)==mirror and not chosen.has(mirror): chosen.append(mirror)
			for name in chosen:
				if not affected.has(name): affected.append(name)
			_change("bones",affected,true))
	var overrides:=_fold("Selected bone settings")
	inspector._add_label(overrides,"Applies to highlighted bones, or all checked bones.")
	var enabled:=CheckButton.new(); enabled.text="Bone physics enabled"; enabled.button_pressed=true; overrides.add_child(enabled)
	var amend_bones:=func(key: String,value: Variant) -> Dictionary:
		var names: Array=selected_names.call()
		if names.is_empty(): names=KiwiPhysicsSettings.authored(actor).bones
		var data: Dictionary=KiwiPhysicsSettings.authored(actor).bone_settings.duplicate(true)
		for name in names:
			if not data.has(name): data[name]={}
			data[name][key]=value
		return data
	enabled.toggled.connect(func(value: bool): _change("bone_settings",amend_bones.call("enabled",value)))
	for key: String in ["influence","stiffness","damping","gravity","mass","limit","radius"]:
		inspector._add_label(overrides,key.capitalize())
		var number:=DragNumber.new(); number.step=.01; number.min_value=0; number.max_value=1 if key=="influence" else 1000; number.set_value_no_signal(float(settings[key])); overrides.add_child(number)
		_structured_number(number,"bone_settings",func(value: float): return amend_bones.call(key,value))
		var refresh:=func():
			var names: Array=selected_names.call()
			if names.is_empty(): names=KiwiPhysicsSettings.authored(actor).bones
			if names.is_empty() or number.dragging: return
			var config:=KiwiPhysicsSettings.sample(actor,actor.animation_time if not is_nan(actor.animation_time) else 0.0)
			number.set_value_no_signal(float(config.bone_settings.get(names[0],{}).get(key,config[key])))
		tree.multi_selected.connect(func(_item: TreeItem,_column: int,_selected: bool): refresh.call())
		inspector._updaters.append(refresh)
func _structured_number(input: DragNumber, field: String, amend: Callable) -> void:
	var gesture:={"before":{},"active":false}
	input.interaction_started.connect(func(): gesture.before=KiwiPhysicsSettings.authored(actor); gesture.active=true)
	input.preview_changed.connect(func(value: float):
		var data:=KiwiPhysicsSettings.authored(actor); data[field]=amend.call(value); actor.values[&"physics"]=data; model.changed.emit())
	input.drag_committed.connect(func(value: float):
		if gesture.active: actor.values[&"physics"]=gesture.before; gesture.active=false
		_change(field,amend.call(value)))
	input.drag_cancelled.connect(func():
		if gesture.active: actor.values[&"physics"]=gesture.before; gesture.active=false; model.changed.emit())
	input.value_changed.connect(func(value: float): _change(field,amend.call(value)))
	input.interaction_ended.connect(func():
		if gesture.active and is_equal_approx(input.value,input._origin): actor.values[&"physics"]=gesture.before; gesture.active=false; model.changed.emit())
func _events() -> void:
	var parent:=_fold("Forces and impulses")
	var add:=Button.new(); add.text="＋ Force / impulse event"; parent.add_child(add)
	add.pressed.connect(func():
		var events: Array=KiwiPhysicsSettings.authored(actor).forces.duplicate(true)
		events.append({"time":maxf(0,actor.animation_time) if not is_nan(actor.animation_time) else 0.0,"duration":0.0,"impulse":Vector3(0,3,0),"force":Vector3.ZERO}); _change("forces",events,true))
	for index in settings.forces.size():
		var event: Dictionary=settings.forces[index]; var group:=VBoxContainer.new(); parent.add_child(group)
		var remove:=Button.new(); remove.text="× Event %d"%(index+1); group.add_child(remove)
		remove.pressed.connect(func(): var events: Array=KiwiPhysicsSettings.authored(actor).forces.duplicate(true); events.remove_at(index); _change("forces",events,true))
		for field: String in ["time","duration","impulse","force"]:
			inspector._add_label(group,{"time":"Source time (s)","duration":"Force duration (s)","impulse":"Impulse (X / Y / Z)","force":"Force (X / Y / Z)"}[field])
			var row:=HBoxContainer.new(); group.add_child(row)
			for axis in (3 if field in ["impulse","force"] else 1):
				var input:=DragNumber.new(); input.step=.01; input.allow_greater=true; input.allow_lesser=field in ["impulse","force"]; input.size_flags_horizontal=Control.SIZE_EXPAND_FILL; row.add_child(input)
				input.set_value_no_signal(event.get(field,Vector3.ZERO)[axis] if field in ["impulse","force"] else float(event.get(field,0)))
				_structured_number(input,"forces",func(value: float) -> Array:
					var events: Array=KiwiPhysicsSettings.authored(actor).forces.duplicate(true)
					if index>=events.size(): return events
					if field in ["impulse","force"]: events[index][field][axis]=value
					else: events[index][field]=value
					return events)
func _editor() -> Control:
	for editor in inspector.get_tree().get_nodes_in_group("actor_timeline_editors"):
		if editor.model==model: return editor
	return null
func _pins() -> void:
	var controls:=_fold("Point pins")
	var editor:=_editor()
	var pick:=CheckButton.new(); pick.text="Pick pins in viewport"; pick.button_pressed=actor.get_meta("editor_physics_pin_mode",false); controls.add_child(pick)
	pick.toggled.connect(func(value: bool): actor.set_meta("editor_physics_pin_mode",value))
	var point:=DragNumber.new(); point.min_value=0; point.max_value=255; point.step=1; point.set_value_no_signal(0); controls.add_child(point)
	var add:=Button.new(); add.text="Pin simulation point"; controls.add_child(add)
	add.pressed.connect(func():
		if editor==null or not editor.physics.prototypes.has(actor.id): return
		var prototype: Dictionary=editor.physics.prototypes[actor.id]
		if prototype.graph.is_empty(): prototype.graph=KiwiPhysicsGeometry.particles(prototype.geometry,int(settings.particles),editor.physics.animated_world(actor.id,model.playhead_time))
		if not prototype.graph.get("error","").is_empty(): return
		var points: PackedVector3Array=editor.physics.display_states.get(actor.id,{}).get("points",prototype.graph.rest)
		var index:=clampi(int(point.value),0,points.size()-1); var pins: Array=KiwiPhysicsSettings.authored(actor).pins.duplicate(true)
		if not points.is_empty(): KiwiPhysicsSettings.pin(editor,actor,index,points[index]); inspector._queue_rebuild_selected())
	for index in settings.pins.size():
		var pin: Dictionary=settings.pins[index]; var remove:=Button.new(); remove.text="× Point %d · %s"%[pin.get("point",0),"World" if str(pin.get("actor","")).is_empty() else "Attached"]; controls.add_child(remove)
		remove.pressed.connect(func(): var pins: Array=KiwiPhysicsSettings.authored(actor).pins.duplicate(true); pins.remove_at(index); _change("pins",pins,true))
func _actions() -> void:
	var editor:=_editor()
	if editor==null: return
	var status:=Label.new(); status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; panel.add_child(status)
	panel.move_child(status,mini(4,panel.get_child_count()-1)); status.add_theme_font_size_override("font_size",12); status.text=editor.physics.status
	editor.physics.status_changed.connect(status.set_text)
	inspector._updaters.append(func(): status.text=editor.physics.status)
	var controls:=HFlowContainer.new(); panel.add_child(controls)
	for action: String in ["Bake…","Clear cache","Recalculate","Freeze"]:
		var button:=Button.new(); button.text=action; controls.add_child(button)
		button.pressed.connect(_action.bind(action,button,status))
	if KiwiGrowthPhysics.data(actor)!=null:
		var clear:=Button.new(); clear.text="Clear bake"; controls.add_child(clear); clear.pressed.connect(func():
			var before:=KiwiPhysicsSettings.authored(actor); var after:=before.duplicate(true); after.mode=int(before.bake.get("source_mode",1)); after.bake={}
			model.history.create_action("Clear growth bake"); model.history.add_do_method(KiwiPhysicsSettings.assign.bind(model,actor,after)); model.history.add_undo_method(KiwiPhysicsSettings.assign.bind(model,actor,before)); model.history.commit_action())
func _action(action: String, button: Button, status: Label) -> void:
	var editor:=_editor()
	if editor==null: return
	if action=="Freeze": editor.physics.freeze(model,actor); return
	if action=="Bake…" and (KiwiGrowthPhysics.data(actor)!=null or int(settings.type)==9):
		var control:=preload("res://scripts/actors/physics/destruction/destruction_workflow_control.gd").new(); inspector.add_child(control); control.host=inspector; control.actor=actor; control.status=status; control.bake_dialog(editor)
		var dialog: Node=control.find_child("DestructionBakeDialog",true,false)
		if dialog!=null: dialog.tree_exited.connect(control.queue_free)
		return
	if action in ["Clear cache","Recalculate"]:
		if action=="Recalculate" and int(KiwiPhysicsSettings.authored(actor).mode)==4: _change("mode",int(KiwiPhysicsSettings.authored(actor).bake.get("source_mode",1)),true)
		editor.physics.signature=""; editor.physics.mark_dirty(); editor._evaluate_runtimes(); return
	var popup:=ConfirmationDialog.new(); popup.title="Bake timeline physics"; popup.ok_button_text="Bake"; inspector.add_child(popup)
	var fields:=VBoxContainer.new(); popup.add_child(fields)
	inspector._add_label(fields,"Scene start (seconds)"); var start:=DragNumber.new(); start.min_value=0; start.max_value=86400; fields.add_child(start)
	inspector._add_label(fields,"Scene end (seconds)"); var end:=DragNumber.new(); end.min_value=.01; end.max_value=86400; end.set_value_no_signal(editor.video_duration); fields.add_child(end)
	popup.confirmed.connect(func():
		button.disabled=true
		var error: String=await editor.physics.bake(editor,actor,start.value,end.value)
		if is_instance_valid(button): button.disabled=false
		if is_instance_valid(status): status.text=error if not error.is_empty() else "Physics baked."
		if is_instance_valid(popup): popup.queue_free())
	popup.canceled.connect(popup.queue_free); popup.popup_centered(Vector2i(300,180))
