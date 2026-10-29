extends VBoxContainer
var host: ActorInspector
var actor: ActorData
var workflow:=false
var status: Label
func setup(inspector: ActorInspector,data: ActorData,actions: bool=false) -> void:
	host=inspector; actor=data; workflow=actions
	status=Label.new(); status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; status.add_theme_font_size_override("font_size",12)
	if workflow:
		var flow:=HFlowContainer.new(); add_child(flow)
		for title in ["Preview","Recalculate","Freeze","Bake group…","Clear bake","Reset to original"]: button(flow,title,run.bind(title))
		var assets:=HBoxContainer.new(); add_child(assets); button(assets,"Capture setup",capture); button(assets,"Apply setup",apply_setup)
		var baked:=HFlowContainer.new(); add_child(baked); button(baked,"Capture baked assembly",capture_baked); button(baked,"Instantiate baked assembly",instantiate_baked)
	else:
		var row:=HBoxContainer.new(); add_child(row); button(row,"Direct fragments…",open_fragments)
		var viewport:=CheckButton.new(); viewport.name="DirectFragmentsViewport"; viewport.text="Pick"; viewport.tooltip_text="Pick fragments in the viewport; Shift-click adds to the group. Drag the target handle to guide them."; viewport.button_pressed=actor.get_meta("damage_fragment_tool",false); row.add_child(viewport)
		viewport.toggled.connect(func(value: bool): actor.set_meta("damage_fragment_tool",value); actor.set_meta("damage_viewport_tool",value))
	add_child(status)
func button(parent: Node,title: String,action: Callable) -> Button:
	var b:=Button.new(); b.text=title; b.name=title.validate_node_name(); parent.add_child(b); b.pressed.connect(action); return b
func editor() -> ActorTimelineEditor:
	for node in get_tree().get_nodes_in_group("actor_timeline_editors"):
		if node.model==host.model: return node
	return null
func capture() -> void:
	var view:=editor()
	if view==null: return
	var setup:=KiwiDestructionAuthoring.capture_setup(view.physics,actor)
	KiwiDestructionAuthoring.edit(host.model,actor,&"destruction_setup",ActorObjectReference.from_object(setup),"Capture reusable destruction setup")
	status.text="Setup captured. Expand Reusable setup to save it to the project or copy it."
	host._queue_rebuild_selected()
func apply_setup() -> void:
	var reference: Variant=actor.get_value(&"destruction_setup"); var setup:=ActorAnimation.resolve_reference(reference) if reference is ActorObjectReference else null; var view:=editor()
	if view!=null: status.text=KiwiDestructionAuthoring.apply_setup(host.model,view.physics,actor,setup)
func capture_baked() -> void:
	var view:=editor()
	if view==null: return
	var result:=KiwiBakeEditing.portable_scene(view)
	if not str(result.error).is_empty(): status.text=result.error; return
	var setup:=KiwiDestructionAuthoring.capture_setup(view.physics,actor); setup.values.baked_assembly=result.scene
	KiwiDestructionAuthoring.edit(host.model,actor,&"destruction_setup",ActorObjectReference.from_object(setup),"Capture reusable baked assembly")
	status.text="Baked interacting rigid assembly captured. Save Reusable setup to reuse it. New contacts require recalculation."; host._queue_rebuild_selected()
func instantiate_baked() -> void:
	var reference: Variant=actor.get_value(&"destruction_setup"); var setup:=ActorAnimation.resolve_reference(reference) if reference is ActorObjectReference else null; var view:=editor()
	var assembly: ActorSceneData=setup.get_value(&"baked_assembly") if setup!=null else null
	if view==null or assembly==null: status.text="Load a setup containing a baked assembly first."; return
	var clip:=host.model.instantiate_scene(assembly,host.registry.get_definition(&"point_3d"),view.canvas.playhead,host.model.selected_layer,str(setup.get_value(&"name","Baked assembly")),"Instantiate baked rigid assembly")
	status.text="Baked assembly inserted. Move its parent to place it; new physical contacts require recalculation." if clip!=null else "Could not instantiate the baked assembly."
func run(title: String) -> void:
	var view:=editor()
	if view==null: return
	if title=="Preview": actor.set_meta("damage_pattern_preview",false); view.playing=not view.playing
	elif title=="Freeze": view.physics.freeze(host.model,actor)
	elif title=="Bake group…": bake_dialog(view)
	elif title=="Clear bake":
		var before:=KiwiPhysicsSettings.authored(actor); var after:=before.duplicate(true); after.mode=int(before.bake.get("source_mode",1)); after.bake={}
		host.model.history.create_action("Clear physics bake"); host.model.history.add_do_method(KiwiPhysicsSettings.assign.bind(host.model,actor,after)); host.model.history.add_undo_method(KiwiPhysicsSettings.assign.bind(host.model,actor,before)); host.model.history.commit_action()
	elif title=="Reset to original":
		var ops: Dictionary=actor.get_value(&"destruction_operations",{}).duplicate(true)
		for op: Dictionary in ops.values(): op.enabled=false
		KiwiDestructionDefinition.edit(host.model,actor,ops,"Disable destruction stack")
		status.text="Operations disabled; source preserved. Re-enable an operation to restore its setup."
	elif title=="Recalculate":
		if int(KiwiPhysicsSettings.authored(actor).mode) in [3,4]: KiwiPhysicsSettings.edit(host.model,actor,"mode",int(KiwiPhysicsSettings.authored(actor).bake.get("source_mode",1)))
		view.physics.signature=""; view.physics.mark_dirty(); view._evaluate_runtimes(); status.text="Simulation reset. Unchanged prepared fracture geometry is reused."
func bake_dialog(view: ActorTimelineEditor) -> void:
	var dialog:=ConfirmationDialog.new(); dialog.name="DestructionBakeDialog"; dialog.title="Bake interacting simulation"; dialog.ok_button_text="Bake"; add_child(dialog)
	var fields:=VBoxContainer.new(); dialog.add_child(fields)
	var label:=Label.new(); label.text="All configured physics actors are baked together."; fields.add_child(label)
	var external:=CheckButton.new(); external.name="ExternalBakeStorage"; external.text="Stream chunks to project (bounded memory)"; fields.add_child(external)
	var interval:=CheckButton.new(); interval.name="RecalculateBakeInterval"; interval.text="Reuse verified prefix; recalculate from playhead"; interval.disabled=not KiwiPhysicsSettings.authored(actor).bake.get("cache") is KiwiPhysicsBakeCache; fields.add_child(interval)
	var inputs: Array[DragNumber]=[]
	for row in [["Start (scene seconds)",0.0],["End (scene seconds)",view.video_duration],["Samples per second",float(view.physics.rate)]]:
		var line:=HBoxContainer.new(); fields.add_child(line); var text:=Label.new(); text.text=row[0]; text.size_flags_horizontal=Control.SIZE_EXPAND_FILL; line.add_child(text)
		var input:=DragNumber.new(); input.name=str(row[0]).validate_node_name(); input.min_value=0; input.max_value=240 if inputs.size()==2 else 86400; input.step=1 if inputs.size()==2 else .01; input.set_value_no_signal(row[1]); line.add_child(input); inputs.append(input)
	interval.toggled.connect(func(enabled: bool):
		if not enabled: return
		var bake: Dictionary=KiwiPhysicsSettings.authored(actor).bake
		inputs[0].value=float(bake.get("from",0)); inputs[1].value=float(bake.get("to",view.video_duration)); inputs[2].value=float(bake.get("rate",view.physics.rate)))
	var progress:=ProgressBar.new(); progress.show_percentage=true; fields.add_child(progress); var info:=Label.new(); info.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; fields.add_child(info)
	dialog.dialog_hide_on_ok=false; var running:={"value":false}; var feedback:=status
	dialog.confirmed.connect(func():
		if running.value: return
		running.value=true; dialog.get_ok_button().disabled=true
		var options:={"external":external.button_pressed}
		if interval.button_pressed: options.reuse=KiwiPhysicsSettings.authored(actor).bake; options.recalculate_from=view.canvas.playhead
		var result:=await view.physics.bake_group(view,inputs[0].value,inputs[1].value,int(inputs[2].value),func(done: int,total: int,bytes: int):
			if is_instance_valid(progress): progress.value=100.0*done/total; info.text="%d / %d samples · %.2f MiB compressed"%[done,total,bytes/1048576.0],options)
		if is_instance_valid(dialog):
			running.value=false; dialog.get_ok_button().disabled=false; info.text=result if not result.is_empty() else "Bake saved. Source settings and correction keys remain editable."
		if is_instance_valid(feedback): feedback.text=result if not result.is_empty() else "Interacting group baked."
	)
	dialog.canceled.connect(func():
		if running.value: view.physics.cancel_bake()
		else: dialog.queue_free())
	dialog.tree_exiting.connect(func():
		if running.value and is_instance_valid(view): view.physics.cancel_bake())
	dialog.popup_centered(Vector2i(430,260))
func open_fragments() -> void:
	var view:=editor()
	if view==null: return
	var fragments: Array=view.physics.display_states.get(actor.id,{}).get("destruction_fragments",[])
	if fragments.is_empty(): status.text="Scrub past a fracture first, then select the resulting pieces."; return
	var dialog:=AcceptDialog.new(); dialog.title="Fragment direction & animation corrections"; dialog.name="FragmentDirector"; add_child(dialog)
	var fields:=VBoxContainer.new(); dialog.add_child(fields); var mode:=OptionButton.new(); mode.add_item("Simulation guidance — recalculates physics"); mode.add_item("Animation-only corrections — preserves bake"); fields.add_child(mode)
	var list:=ItemList.new(); list.name="FragmentList"; list.select_mode=ItemList.SELECT_MULTI; list.custom_minimum_size=Vector2(420,110); fields.add_child(list); var ids:=[]
	for i in fragments.size():
		var key:=KiwiDestructionAuthoring.fragment_key(actor.id,fragments[i].id); ids.append(key); list.add_item("Piece %d · %.3f kg"%[i+1,fragments[i].mass]); list.set_item_metadata(i,key)
		if (actor.get_meta("damage_selected_fragments",[]) as Array).has(key): list.select(i,false)
	if list.get_selected_items().is_empty(): list.select(0); actor.set_meta("damage_selected_fragments",[ids[0]])
	var selected_ids:=func() -> Array:
		var chosen:=[]
		for i in list.get_selected_items(): chosen.append(ids[i])
		actor.set_meta("damage_selected_fragments",chosen); return chosen
	list.multi_selected.connect(func(_index: int,_selected: bool): selected_ids.call())
	var options:=VBoxContainer.new(); fields.add_child(options)
	var rebuild:=func():
		for child in options.get_children(): options.remove_child(child); child.queue_free()
		var field: StringName=&"destruction_fragments" if mode.selected==0 else &"destruction_overrides"
		if mode.selected==0:
			var choose:=OptionButton.new(); choose.add_item("Physical"); choose.add_item("Force-guided (collisions retained)"); choose.add_item("Animated target (not collision solved)"); options.add_child(choose)
			var chosen: Array=selected_ids.call(); var first: Dictionary=actor.values.get(field,{}).get(chosen[0],{}) if not chosen.is_empty() else {}; choose.select(clampi(int(first.get("mode",0)),0,2))
			choose.item_selected.connect(func(index: int): KiwiDestructionAuthoring.edit_fragments(host.model,actor,field,selected_ids.call(),"mode",index))
			var collision:=CheckButton.new(); collision.text="Fragment collisions"; collision.button_pressed=first.get("collision",true); options.add_child(collision); collision.toggled.connect(func(value: bool): KiwiDestructionAuthoring.edit_fragments(host.model,actor,field,selected_ids.call(),"collision",value))
		for key: String in (["target","velocity","angular_velocity","impulse","impulse_time","pin_until","from","to","strength","damping","mass_scale"] if mode.selected==0 else ["offset","rotation","time_offset","time_scale","freeze_time"]):
			var chosen: Array=selected_ids.call(); var first: Dictionary=actor.values.get(field,{}).get(chosen[0],{}) if not chosen.is_empty() else {}; var fallback: Variant=KiwiDestructionAuthoring.fragment_defaults().get(key,Vector3.ZERO); var initial: Variant=first.get(key,fallback)
			if key in ["time_offset","time_scale","freeze_time"]: initial=first.get(key,1.0 if key=="time_scale" else (-1.0 if key=="freeze_time" else 0.0))
			var row:=HBoxContainer.new(); options.add_child(row); var label:=Label.new(); label.text=key.replace("_"," ").capitalize(); label.custom_minimum_size.x=120; row.add_child(label)
			button(row,"◇",func(): KiwiDestructionAuthoring.key_fragments(host.model,actor,field,selected_ids.call(),key,initial))
			for axis in (3 if initial is Vector3 else 1):
				var input:=DragNumber.new(); input.name="Fragment_"+key+"_"+str(axis); input.step=.01; input.allow_greater=true; input.allow_lesser=true; input.size_flags_horizontal=Control.SIZE_EXPAND_FILL; row.add_child(input); input.set_value_no_signal(initial[axis] if initial is Vector3 else float(initial))
				var convert:=func(value: float) -> Variant:
					if not initial is Vector3: return value
					var current: Array=selected_ids.call(); var vector: Vector3=ActorAnimation.sampled_value(actor,PackedStringArray([str(field),str(current[0]),key]),actor.animation_time,initial) if not current.is_empty() else initial; vector[axis]=value; return vector
				input.value_changed.connect(func(value: float): KiwiDestructionAuthoring.edit_fragments(host.model,actor,field,selected_ids.call(),key,convert.call(value)))
				# No per-motion commits: a numeric drag produces one undoable edit.
				input.drag_committed.connect(func(value: float): KiwiDestructionAuthoring.edit_fragments(host.model,actor,field,selected_ids.call(),key,convert.call(value)))
		var note:=Label.new(); note.text="Offsets are visual animation overrides; they do not recalculate collisions." if mode.selected==1 else "Targets use world coordinates. Release retains the last animated velocity."; note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; options.add_child(note)
	mode.item_selected.connect(func(_index: int): rebuild.call()); list.multi_selected.connect(func(_index: int,_selected: bool): rebuild.call()); rebuild.call()
	dialog.confirmed.connect(dialog.queue_free); dialog.canceled.connect(dialog.queue_free); dialog.popup_centered(Vector2i(640,640))
