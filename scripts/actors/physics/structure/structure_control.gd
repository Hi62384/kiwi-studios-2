extends VBoxContainer
var host: ActorInspector
var actor: ActorData
var selected:=""
var signature:=0
var candidates: Array[Dictionary]=[]
var tolerance:=.05
var callbacks: Array[Callable]=[]
func setup(inspector: ActorInspector,data: ActorData) -> void:
	host=inspector; actor=data; name="StructuralConnections"; build(); host._updaters.append(sync)
func editor() -> ActorTimelineEditor:
	for node in get_tree().get_nodes_in_group("actor_timeline_editors"):
		if node.model==host.model: return node
	return null
func pose(data: ActorData) -> Transform3D:
	var view:=editor()
	return view.physics.animated_world(data.id,view.canvas.playhead) if view!=null else Transform3D(Basis.IDENTITY,data.values.get(&"position",Vector3.ZERO))
func sync() -> void:
	if not is_inside_tree(): return
	var links: Dictionary=actor.get_value(&"structure_connections",{})
	if signature!=hash([links.keys(),links.get(selected,{}).get("type",0)]): build.call_deferred()
func build() -> void:
	if not is_instance_valid(host): return
	for callback in callbacks: host._updaters.erase(callback)
	callbacks.clear(); var updater_start:=host._updaters.size()
	for child in get_children(): remove_child(child); child.queue_free()
	var links: Dictionary=actor.get_value(&"structure_connections",{})
	if selected.is_empty(): selected=str(actor.get_meta("structure_selected",""))
	if not links.has(selected): selected=str(links.keys()[0]) if not links.is_empty() else ""
	signature=hash([links.keys(),links.get(selected,{}).get("type",0)])
	if links.has(selected):
		var id:=selected; var viewport:=Button.new(); viewport.name="StructuralViewport"; viewport.text="◎  Edit joint in viewport"; viewport.toggle_mode=true; viewport.button_pressed=actor.get_meta("structure_tool",false); add_child(viewport); viewport.toggled.connect(func(value: bool): actor.set_meta("structure_tool",value); actor.set_meta("structure_selected",id))
	var group:=Button.new(); group.text="＋  Assemble selection"; group.tooltip_text="Enable structural elements on selected meshes without changing their scene parenting or geometry."; add_child(group)
	group.pressed.connect(func():
		var actors: Array[ActorData]=[]; var changes: Array[Dictionary]=[]; var id:=ActorData.new_id()
		for data in host.model.selected_actors():
			if data.type_id in [&"basic_shape",&"basic_mesh"]: actors.append(data); changes.append({&"structure_enabled":true,&"structure_assembly":id})
		if not actors.is_empty(): KiwiStructure.commit(host.model,actors,changes,"Create structural assembly"))
	var target:=OptionButton.new(); target.name="StructuralTarget"; target.fit_to_longest_item=false; add_child(target); var targets: Array[ActorData]=[]
	for data in host.model.actors:
		if data!=actor and data.type_id in [&"basic_shape",&"basic_mesh"]: target.add_item(data.display_name); targets.append(data)
	var row:=HBoxContainer.new(); add_child(row); var kinds:=OptionButton.new(); kinds.size_flags_horizontal=Control.SIZE_EXPAND_FILL; kinds.fit_to_longest_item=false; row.add_child(kinds)
	for title in KiwiStructure.TYPES: kinds.add_item(title)
	var create:=Button.new(); create.name="ConnectStructure"; create.text="＋"; create.tooltip_text="Connect this actor to the chosen target. Connections are explicit, not inferred from parenting."; create.disabled=targets.is_empty(); row.add_child(create)
	create.pressed.connect(func():
		var other:=targets[target.selected]; selected=KiwiStructure.connect_actors(host.model,actor,other,(pose(actor).origin+pose(other).origin)*.5,pose(actor),pose(other),kinds.selected); actor.set_meta("structure_selected",selected); build.call_deferred())
	var auto_row:=HBoxContainer.new(); add_child(auto_row); var gap:=DragNumber.new(); gap.name="ConnectionTolerance"; gap.min_value=0; gap.max_value=10; gap.step=.01; gap.value=tolerance; gap.suffix="m"; gap.size_flags_horizontal=Control.SIZE_EXPAND_FILL; gap.tooltip_text="Boundary tolerance for candidate review. Finding candidates never welds objects automatically."; auto_row.add_child(gap)
	gap.value_changed.connect(func(value: float): tolerance=value); gap.drag_committed.connect(func(value: float): tolerance=value)
	var find:=Button.new(); find.text="Find nearby"; auto_row.add_child(find)
	find.pressed.connect(func():
		var bounds:={}; var actors: Array[ActorData]=[]; var view:=editor()
		if view==null: return
		for data in host.model.selected_actors():
			if data.type_id not in [&"basic_shape",&"basic_mesh"]: continue
			var runtime:=view._runtime_for_clip(host.model.clip_for_actor_id(data.id).id)
			if runtime==null: continue
			actors.append(data); bounds[data.id]=pose(data)*KiwiPhysicsGeometry.capture(runtime,{}).bounds
		candidates=KiwiStructure.candidates(actors,bounds,tolerance); build.call_deferred())
	for candidate in candidates:
		var accept:=Button.new(); accept.text="Link "+candidate.a.display_name+" ↔ "+candidate.b.display_name; accept.clip_text=true; accept.tooltip_text="Review bounds-based candidate (gap %.3f m). Click to explicitly add this joint."%candidate.gap; add_child(accept)
		accept.pressed.connect(func(): KiwiStructure.connect_actors(host.model,candidate.a,candidate.b,candidate.point,pose(candidate.a),pose(candidate.b),kinds.selected); candidates.erase(candidate); build.call_deferred())
	for key: String in links:
		var line:=HBoxContainer.new(); add_child(line); var other:=host.model.actor_for_id(str(links[key].get("target","")))
		var button:=Button.new(); button.text=("⚭  "+other.display_name) if other!=null else "⚠ Missing target"; button.toggle_mode=true; button.button_pressed=key==selected; button.size_flags_horizontal=Control.SIZE_EXPAND_FILL; button.clip_text=true; line.add_child(button)
		button.pressed.connect(func(): selected=key; actor.set_meta("structure_selected",key); build.call_deferred())
		var remove:=Button.new(); remove.text="×"; remove.tooltip_text="Remove connection and its keyframes"; line.add_child(remove)
		remove.pressed.connect(func(): var updated: Dictionary=ActorData.copy_value(actor.values.structure_connections); updated.erase(key); KiwiStructure.commit(host.model,[actor],[{&"structure_connections":updated}],"Remove structural connection"); build.call_deferred())
	for other in host.model.actors:
		for key: String in other.get_value(&"structure_connections",{}):
			if str(other.values.structure_connections[key].get("target",""))!=actor.id: continue
			var incoming:=Button.new(); incoming.text="↖  From "+other.display_name; incoming.clip_text=true; add_child(incoming)
			incoming.pressed.connect(func(): other.set_meta("structure_selected",key); host.model.select(host.model.clip_for_actor_id(other.id).id))
	if links.has(selected):
		var id:=selected; var link: Dictionary=links[id]
		var kind:=OptionButton.new(); kind.fit_to_longest_item=false; add_child(kind)
		for title in KiwiStructure.TYPES: kind.add_item(title)
		kind.select(int(link.type)); kind.item_selected.connect(func(value: int): KiwiStructure.set_value(host.model,actor,id,"type",value); build.call_deferred())
		for field in ["enabled","prevent_failure","exclude_collision"]: toggle(id,field,link.get(field,true))
		for field in ["strength","breaking_force","breaking_torque","stiffness","initial_damage","break_at"]:
			if field=="breaking_torque" and int(link.type) in [3,4]: continue
			number(id,field,float(link.get(field,0)))
		if int(link.type) in [3,4]: number(id,"length",float(link.length))
		if int(link.type)==2: number(id,"limit",float(link.limit))
		if int(link.type)==3: toggle(id,"tension_only",bool(link.tension_only))
		var advanced:=Button.new(); advanced.text="Joint details  ▾"; advanced.toggle_mode=true; add_child(advanced); var details:=VBoxContainer.new(); details.hide(); add_child(details); advanced.toggled.connect(details.set_visible)
		for field in ["angular_stiffness","tension","compression","shear","bending","damping","damage_rate"]:
			if field in ["angular_stiffness","bending"] and int(link.type) in [3,4]: continue
			number(id,field,float(link.get(field,1)),details)
		toggle(id,"material_strength",bool(link.get("material_strength",false)),details)
		for field in ["pivot","target_pivot","orientation"]:
			for axis in 3: number(id,field,link.get(field,Vector3.ZERO)[axis],details,axis)
	var status:=Label.new(); status.name="StructuralStatus"; status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; status.add_theme_font_size_override("font_size",12); add_child(status)
	var update:=func():
		if not is_instance_valid(status): return
		var view:=editor(); var state: Dictionary=view.physics.display_states.get(actor.id,{}).get("structural",{}) if view!=null else {}
		var joint: Dictionary=state.get("links",{}).get(selected,{})
		status.text=("Supported" if state.get("supported",false) else "Unanchored / contact-dependent")+" · Approximate joint loads\n%.1f N · %.1f N·m · %.0f%% used\n%s"%[joint.get("load",0),joint.get("torque",0),100*float(joint.get("utilization",0)),joint.get("reason","")]
	host._updaters.append(update); update.call(); host._prepare_buttons()
	callbacks.assign(host._updaters.slice(updater_start))
func _exit_tree() -> void:
	if is_instance_valid(host):
		for callback in callbacks: host._updaters.erase(callback)
func toggle(id: String,key: String,value: bool,parent: Control=null) -> void:
	if parent==null: parent=self
	var row:=HBoxContainer.new(); parent.add_child(row)
	var button:=CheckBox.new(); button.text=key.replace("_"," ").capitalize(); button.button_pressed=value; button.size_flags_horizontal=Control.SIZE_EXPAND_FILL; row.add_child(button); button.toggled.connect(func(next: bool): KiwiStructure.set_value(host.model,actor,id,key,next))
	host._add_keyframe_button(row,actor,ActorProperty.create(StringName(key),button.text,value,true),PackedStringArray(["structure_connections",id,key]),value)
	host._updaters.append(func():
		if is_instance_valid(button): button.set_pressed_no_signal(bool(ActorAnimation.sampled_value(actor,PackedStringArray(["structure_connections",id,key]),actor.animation_time if not is_nan(actor.animation_time) else 0,actor.values.structure_connections.get(id,{}).get(key,value)))))
func number(id: String,key: String,value: float,parent: Control=null,axis: int=-1) -> void:
	if parent==null: parent=self
	var row:=HBoxContainer.new(); parent.add_child(row); var label:=Label.new(); label.text={"breaking_force":"Breaking force (N)","breaking_torque":"Breaking torque (N·m)","stiffness":"Stiffness (N/m)","break_at":"Break at source time (−1: off)","orientation":"Orientation (degrees)"}.get(key,key.replace("_"," ").capitalize())+(" "+["X","Y","Z"][axis] if axis>=0 else ""); label.size_flags_horizontal=Control.SIZE_EXPAND_FILL; label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS; label.tooltip_text=label.text; row.add_child(label)
	var path:=PackedStringArray(["structure_connections",id,key]); var fallback: Variant=value if axis<0 else actor.values.structure_connections[id][key]
	if axis<=0: host._add_keyframe_button(row,actor,ActorProperty.create(StringName(key),label.text,fallback,true),path,fallback)
	var field:=DragNumber.new(); field.name="Structure_"+key+("_"+str(axis) if axis>=0 else ""); field.allow_greater=true; field.allow_lesser=key in ["break_at","pivot","target_pivot","orientation"]; field.step=.01; field.set_value_no_signal(value); parent.add_child(field)
	var before:={"values":{}}; var convert:=func(next: float) -> Variant:
		if axis<0: return next
		var vector: Vector3=ActorAnimation.sampled_value(actor,path,actor.animation_time if not is_nan(actor.animation_time) else 0,ActorAnimation.value_at_path(actor,path)); vector[axis]=next; return vector
	field.interaction_started.connect(func(): before.values=ActorData.copy_value(actor.values))
	field.preview_changed.connect(func(next: float): KiwiStructure.set_value(host.model,actor,id,key,convert.call(next),true))
	field.drag_committed.connect(func(next: float):
		var final: Variant=convert.call(next)
		if actor.animation_track(path)==null: actor.values=before.values
		KiwiStructure.set_value(host.model,actor,id,key,final))
	field.drag_cancelled.connect(func(): actor.values=before.values; actor.animation_previews.erase(" / ".join(path)); actor.emit_changed(); host.model.changed.emit())
	field.value_changed.connect(func(next: float): KiwiStructure.set_value(host.model,actor,id,key,convert.call(next)))
	host._updaters.append(func():
		if not is_instance_valid(field) or field.dragging: return
		var sampled: Variant=ActorAnimation.sampled_value(actor,path,actor.animation_time if not is_nan(actor.animation_time) else 0,ActorAnimation.value_at_path(actor,path))
		if sampled!=null: field.set_value_no_signal(float(sampled if axis<0 else sampled[axis])))
