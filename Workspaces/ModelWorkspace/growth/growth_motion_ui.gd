extends RefCounted
static func open(editor: ActorTimelineEditor,actor: ActorData,owner: Node) -> void:
	var prototype: Dictionary=editor.physics.prototypes.get(actor.id,{})
	if not prototype.has("growth"): return
	var popup:=AcceptDialog.new(); popup.title="Growth motion corrections"; popup.name="GrowthMotionCorrections"; owner.add_child(popup); var column:=VBoxContainer.new(); popup.add_child(column)
	var note:=Label.new(); note.text="Animation-only corrections. Changed contacts require a new simulation."; note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; column.add_child(note)
	var list:=ItemList.new(); list.select_mode=ItemList.SELECT_MULTI; list.custom_minimum_size=Vector2(420,120); column.add_child(list)
	for control: Dictionary in prototype.growth.controls: list.add_item(str(control.id)); list.set_item_metadata(list.item_count-1,str(control.id))
	if list.item_count>0: list.select(0)
	var chosen:=func() -> Array:
		var result:=[]
		for index in list.get_selected_items(): result.append(str(list.get_item_metadata(index)))
		return result
	var scroll:=ScrollContainer.new(); scroll.custom_minimum_size=Vector2(420,330); column.add_child(scroll); var fields:=VBoxContainer.new(); fields.size_flags_horizontal=Control.SIZE_EXPAND_FILL; scroll.add_child(fields)
	var rebuild:=func():
		for child in fields.get_children(): fields.remove_child(child); child.queue_free()
		var ids: Array=chosen.call()
		if ids.is_empty(): return
		var values: Dictionary=ActorAnimation.sampled_values(actor,actor.animation_time).get(&"growth_overrides",{}).get(ids[0],{})
		for row in [["from","From (source s)",0.,0.,86400.],["to","Until (-1 = end)",-1.,-1.,86400.],["blend","Boundary blend (s)",.1,0.,10.],["influence","Correction strength",1.,0.,1.],["time_scale","Time scale",1.,0.,10.],["time_offset","Time offset (scene s)",0.,-86400.,86400.],["freeze_time","Freeze at scene s (-1 = off)",-1.,-1.,86400.],["offset","Root-local offset",Vector3.ZERO,-100.,100.],["rotation","Root-local rotation",Vector3.ZERO,-360.,360.]]:
			var field: String=row[0]; var label:=Label.new(); label.text=row[1]; fields.add_child(label); var line:=HBoxContainer.new(); fields.add_child(line); var current: Variant=values.get(field,row[2])
			for axis in (3 if current is Vector3 else 1):
				var input:=DragNumber.new(); input.size_flags_horizontal=Control.SIZE_EXPAND_FILL; input.min_value=row[3]; input.max_value=row[4]; input.step=.01; input.set_value_no_signal(current[axis] if current is Vector3 else current); line.add_child(input)
				var convert:=func(value: float) -> Variant:
					if not current is Vector3: return value
					var selected: Array=chosen.call(); var vector: Vector3=ActorAnimation.sampled_value(actor,PackedStringArray(["growth_overrides",str(selected[0]),field]),actor.animation_time,current) if not selected.is_empty() else current; vector[axis]=value; return vector
				input.value_changed.connect(func(value: float):
					if not input.dragging: KiwiDestructionAuthoring.edit_fragments(editor.model,actor,&"growth_overrides",chosen.call(),field,convert.call(value)))
				input.drag_committed.connect(func(value: float): KiwiDestructionAuthoring.edit_fragments(editor.model,actor,&"growth_overrides",chosen.call(),field,convert.call(value)))
			var key:=Button.new(); key.text="◇"; key.tooltip_text="Keyframe selected guides"; line.add_child(key); key.pressed.connect(func(): KiwiDestructionAuthoring.key_fragments(editor.model,actor,&"growth_overrides",chosen.call(),field,row[2]))
	list.multi_selected.connect(func(_index: int,_selected: bool): rebuild.call()); rebuild.call()
	popup.confirmed.connect(popup.queue_free); popup.canceled.connect(popup.queue_free); popup.popup_centered(Vector2i(470,540))
