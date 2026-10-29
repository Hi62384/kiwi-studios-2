extends VBoxContainer
var host: ActorInspector
var actor: ActorData
var selected:=""
var layout:=-1
var queued:=false
var callbacks: Array[Callable]=[]
func setup(inspector: ActorInspector,data: ActorData) -> void:
	host=inspector; actor=data; name="DestructionOperations"; build(); host._updaters.append(sync)
func sync() -> void:
	if not is_instance_valid(self) or not is_inside_tree() or queued: return
	var operations: Dictionary=actor.get_value(&"destruction_operations",{})
	if hash(operations.keys())!=layout: queued=true; build.call_deferred()
func build() -> void:
	queued=false
	for callback in callbacks: host._updaters.erase(callback)
	callbacks.clear(); var updater_start:=host._updaters.size()
	for child in get_children(): remove_child(child); child.queue_free()
	var row:=HBoxContainer.new(); add_child(row)
	var kinds:=OptionButton.new(); kinds.name="DamageType"; kinds.size_flags_horizontal=Control.SIZE_EXPAND_FILL; kinds.fit_to_longest_item=false
	for title in KiwiDestructionGeometry.TYPES: kinds.add_item(title)
	row.add_child(kinds)
	var preview:=CheckButton.new(); preview.text="Preview cuts"; preview.name="PreviewFracturePattern"; preview.button_pressed=actor.get_meta("damage_pattern_preview",false); add_child(preview)
	preview.toggled.connect(func(value: bool): actor.set_meta("damage_pattern_preview",value); actor.set_meta("damage_viewport_tool",value))
	var add:=Button.new(); add.name="AddDamageOperation"; add.text="＋"; add.tooltip_text="Add a non-destructive operation at the current timeline time"; row.add_child(add)
	add.pressed.connect(func():
		var operations: Dictionary=actor.get_value(&"destruction_operations",{}).duplicate(true); selected=ActorData.new_id()
		operations[selected]=KiwiDestructionDefinition.operation(kinds.selected,maxf(0,actor.animation_time if not is_nan(actor.animation_time) else 0)); KiwiDestructionDefinition.edit(host.model,actor,operations,"Add damage operation"); actor.set_meta("damage_selected_operation",selected); build())
	var operations: Dictionary=actor.get_value(&"destruction_operations",{})
	layout=hash(operations.keys())
	if selected.is_empty(): selected=str(actor.get_meta("damage_selected_operation",""))
	if not operations.has(selected): selected=str(operations.keys()[0]) if not operations.is_empty() else ""
	var keys:=operations.keys()
	for i in keys.size():
		var id:=str(keys[i]); var op: Dictionary=operations[id]; var line:=HBoxContainer.new(); add_child(line)
		var enabled:=CheckBox.new(); enabled.button_pressed=op.get("enabled",true); line.add_child(enabled)
		enabled.toggled.connect(func(value: bool): change(id,"enabled",value))
		var select:=Button.new(); select.text=KiwiDestructionGeometry.TYPES[int(op.type)]; select.toggle_mode=true; select.button_pressed=id==selected; select.size_flags_horizontal=Control.SIZE_EXPAND_FILL; select.clip_text=true; line.add_child(select)
		select.pressed.connect(func(): selected=id; actor.set_meta("damage_selected_operation",id); build())
		for direction in [-1,1]:
			var move:=Button.new(); move.text="↑" if direction<0 else "↓"; move.disabled=i+direction<0 or i+direction>=keys.size(); line.add_child(move)
			move.pressed.connect(func():
				var error:=KiwiDestructionAuthoring.operation_action(host.model,actor,id,"Up" if direction<0 else "Down")
				if not error.is_empty():
					var message:=AcceptDialog.new(); message.title="Operation order"; message.dialog_text=error; add_child(message); message.popup_centered(); message.confirmed.connect(message.queue_free)
				build())
		var remove:=Button.new(); remove.text="×"; remove.tooltip_text="Remove operation and restore its source geometry"; line.add_child(remove)
		remove.pressed.connect(func(): var updated: Dictionary=actor.get_value(&"destruction_operations",{}).duplicate(true); updated.erase(id); KiwiDestructionDefinition.edit(host.model,actor,updated,"Remove damage operation"); build())
	if operations.has(selected):
		var edit_id:=selected
		var op: Dictionary=operations[selected]
		var actions:=HBoxContainer.new(); add_child(actions)
		for action: String in ["Duplicate","Reset"]:
			var button:=Button.new(); button.text=action; button.name="Damage"+action; actions.add_child(button); button.pressed.connect(func(): KiwiDestructionAuthoring.operation_action(host.model,actor,edit_id,action); build())
		var path_button:=CheckButton.new(); path_button.text="Draw fracture path"; path_button.button_pressed=actor.get_meta("damage_path_tool",false); add_child(path_button)
		path_button.toggled.connect(func(value: bool): actor.set_meta("damage_path_tool",value); actor.set_meta("damage_fragment_tool",false); actor.set_meta("damage_viewport_tool",true))
		var resistance:=CheckBox.new(); resistance.text="Physical resistance"; resistance.tooltip_text="On: cutting energy is resisted by the local physical material. Off: direct geometry editing."; resistance.button_pressed=op.get("physical",false); add_child(resistance); resistance.toggled.connect(func(value: bool): change(selected,"physical",value))
		var handle:=Button.new(); handle.name="DamageViewportHandle"; handle.text="◎  Position in viewport"; handle.toggle_mode=true; handle.button_pressed=actor.get_meta("damage_viewport_tool",false); add_child(handle)
		handle.toggled.connect(func(value: bool): actor.set_meta("damage_viewport_tool",value); actor.set_meta("damage_fragment_tool",false); actor.set_meta("damage_selected_operation",selected))
		var kind:=int(op.type); var parameters: Array[String]=["time"]
		if kind in [3,4,6,7,8,9,10,11,12,13]: parameters.append("radius")
		if kind in [3,4,5,7,8,9,10,11,12]: parameters.append("amount")
		if kind==9: parameters.append("falloff")
		if kind in [1,2]: parameters.append_array(["pieces","seed","irregularity"])
		if kind in [0,1,2,5,14]: parameters.append_array(["impulse","direction_bias"])
		if kind==14: parameters.append("energy")
		if op.get("physical",false): parameters.append("energy")
		for field in parameters:
			var line:=HBoxContainer.new(); add_child(line); var label:=Label.new(); label.text={"time":"Start (s)","amount":"Depth / angle (rad)","pieces":"Fracture pieces","impulse":"Separation speed"}.get(field,field.capitalize()); label.size_flags_horizontal=Control.SIZE_EXPAND_FILL; label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS; label.tooltip_text=label.text; line.add_child(label)
			var property:=ActorProperty.create(StringName(field),label.text,op.get(field,1.0),true)
			if field not in ["pieces","seed"]: host._add_keyframe_button(line,actor,property,PackedStringArray(["destruction_operations",selected,field]),op.get(field,1.0))
			var number:=DragNumber.new(); number.name="Damage_"+field; number.allow_greater=true; number.allow_lesser=field=="amount"; number.step=1 if field in ["pieces","seed"] else .01; number.set_value_no_signal(float(op.get(field,1))); add_child(number)
			var state:={"before":{}}
			host._updaters.append(func():
				if not is_instance_valid(number) or number.dragging: return
				var path:=PackedStringArray(["destruction_operations",selected,field]); var value: Variant=ActorAnimation.sampled_value(actor,path,actor.animation_time if not is_nan(actor.animation_time) else 0,ActorAnimation.value_at_path(actor,path))
				if value is float or value is int: number.set_value_no_signal(float(value)))
			number.interaction_started.connect(func(): state.before=ActorData.copy_value(actor.get_value(&"destruction_operations",{})))
			number.preview_changed.connect(func(value: float): change(edit_id,field,value,true))
			number.drag_committed.connect(func(value: float): commit_drag(edit_id,field,value,state.before))
			number.drag_cancelled.connect(func(): cancel_drag(edit_id,field,state.before))
			number.value_changed.connect(func(value: float): change(edit_id,field,value))
		for field in ["position","direction"]:
			var heading:=HBoxContainer.new(); add_child(heading); var label:=Label.new(); label.text=field.capitalize(); label.size_flags_horizontal=Control.SIZE_EXPAND_FILL; heading.add_child(label)
			host._add_keyframe_button(heading,actor,ActorProperty.create(StringName(field),field.capitalize(),op.get(field,Vector3.ZERO),true),PackedStringArray(["destruction_operations",selected,field]),op.get(field,Vector3.ZERO))
			for axis in 3:
				var axes:=HBoxContainer.new(); add_child(axes); var axis_label:=Label.new(); axis_label.text=["X","Y","Z"][axis]; axes.add_child(axis_label)
				var number:=DragNumber.new(); number.name="Damage_"+field+"_"+str(axis); number.allow_greater=true; number.allow_lesser=true; number.step=.01; number.size_flags_horizontal=Control.SIZE_EXPAND_FILL; number.set_value_no_signal(op.get(field,Vector3.ZERO)[axis]); axes.add_child(number)
				var vector_at_value:=func(value: float) -> Vector3:
					var path:=PackedStringArray(["destruction_operations",edit_id,field]); var vector: Vector3=ActorAnimation.sampled_value(actor,path,actor.animation_time if not is_nan(actor.animation_time) else 0,ActorAnimation.value_at_path(actor,path)); vector[axis]=value; return vector
				var state:={"before":{}}
				number.interaction_started.connect(func(): state.before=ActorData.copy_value(actor.get_value(&"destruction_operations",{})))
				number.preview_changed.connect(func(value: float): change(edit_id,field,vector_at_value.call(value),true))
				number.drag_committed.connect(func(value: float): commit_drag(edit_id,field,vector_at_value.call(value),state.before))
				number.drag_cancelled.connect(func(): cancel_drag(edit_id,field,state.before))
				number.value_changed.connect(func(value: float): change(edit_id,field,vector_at_value.call(value)))
				host._updaters.append(func():
					if not is_instance_valid(number) or number.dragging: return
					var path:=PackedStringArray(["destruction_operations",selected,field]); var value: Variant=ActorAnimation.sampled_value(actor,path,actor.animation_time if not is_nan(actor.animation_time) else 0,ActorAnimation.value_at_path(actor,path))
					if value is Vector3: number.set_value_no_signal(value[axis]))
	var status:=Label.new(); status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; status.add_theme_font_size_override("font_size",12); add_child(status)
	var snapshot:=Button.new(); snapshot.text="Save evaluated mesh…"; snapshot.tooltip_text="Save the actual deformed/fractured geometry at this playhead as an ordinary mesh resource. The source and editable operations are preserved."; add_child(snapshot); snapshot.pressed.connect(func(): preload("res://scripts/actors/physics/physics_mesh_snapshot.gd").prompt(self,host.model,actor))
	var update:=func():
		if not is_instance_valid(status): return
		for editor in get_tree().get_nodes_in_group("actor_timeline_editors"):
			if editor.model==host.model: status.text=str(editor.physics.display_states.get(actor.id,{}).get("destruction_error","Closed convex solids: cuts/carving/fracture. Open sheets: tears. Original geometry is preserved."))
	host._updaters.append(update); update.call()
	host._prepare_buttons()
	callbacks.assign(host._updaters.slice(updater_start))
func _exit_tree() -> void:
	if is_instance_valid(host):
		for callback in callbacks: host._updaters.erase(callback)
func commit_drag(id: String,key: String,value: Variant,before: Dictionary) -> void:
	var path:=PackedStringArray(["destruction_operations",id,key])
	if actor.animation_track(path)!=null:
		host.model.commit_animation_value(actor,path,value)
		return
	actor.values[&"destruction_operations"]=ActorData.copy_value(before)
	change(id,key,value)
func cancel_drag(id: String,key: String,before: Dictionary) -> void:
	actor.animation_previews.erase(" / ".join(PackedStringArray(["destruction_operations",id,key])))
	actor.values[&"destruction_operations"]=ActorData.copy_value(before)
	actor.emit_changed(); host.model.changed.emit()
func change(id: String,key: String,value: Variant,preview: bool=false) -> void:
	var path:=PackedStringArray(["destruction_operations",id,key])
	if actor.animation_track(path)!=null:
		if preview: host.model.preview_animation_value(actor,path,value)
		else: host.model.commit_animation_value(actor,path,value)
		return
	var operations: Dictionary=actor.get_value(&"destruction_operations",{}).duplicate(true)
	if not operations.has(id): return
	operations[id][key]=value
	if preview: actor.values[&"destruction_operations"]=operations; host.model.changed.emit()
	else: KiwiDestructionDefinition.edit(host.model,actor,operations)
	if key=="physical": build.call_deferred()
