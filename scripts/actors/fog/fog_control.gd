extends VBoxContainer
const Appearance=preload("res://scripts/actors/fog/fog_appearance.gd")
static func layer_actions(host: ActorInspector,actor: ActorData,object: ActorObjectData,property: ActorProperty,parent: VBoxContainer) -> void:
	var index:=int(str(property.id).trim_prefix("layer_")); var row:=HBoxContainer.new(); parent.add_child(row)
	for direction in [-1,1]:
		var button:=Button.new(); button.text="↑" if direction<0 else "↓"; button.tooltip_text="Move appearance influence"; button.disabled=index+direction<0 or index+direction>3; row.add_child(button)
		button.pressed.connect(func():
			var other:=StringName("layer_%d"%(index+direction)); var a: Variant=object.get_value(property.id); var b: Variant=object.get_value(other)
			host.model.history.create_action("Reorder fog influences")
			host.model.history.add_do_method(host.model._set_object_property.bind(object,property.id,b)); host.model.history.add_do_method(host.model._set_object_property.bind(object,other,a))
			host.model.history.add_undo_method(host.model._set_object_property.bind(object,property.id,a)); host.model.history.add_undo_method(host.model._set_object_property.bind(object,other,b)); host.model.history.commit_action(); host._queue_rebuild_selected())
func setup(host: ActorInspector,actor: ActorData) -> void:
	var atmosphere:=HBoxContainer.new(); add_child(atmosphere)
	var presets:=OptionButton.new(); presets.fit_to_longest_item=false; presets.size_flags_horizontal=Control.SIZE_EXPAND_FILL; presets.tooltip_text="Clouds, mist and atmosphere · retains painted density as a mask"; atmosphere.add_child(presets)
	for title: String in preload("res://scripts/actors/fog/fog_cloud_presets.gd").TITLES: presets.add_item(title)
	var create:=Button.new(); create.text="Set atmosphere"; atmosphere.add_child(create)
	create.pressed.connect(func(): preload("res://scripts/actors/fog/fog_cloud_presets.gd").apply(host.model,actor,presets.selected); host._queue_rebuild_selected())
	var row:=HBoxContainer.new(); add_child(row)
	var choice:=OptionButton.new(); choice.size_flags_horizontal=Control.SIZE_EXPAND_FILL; choice.fit_to_longest_item=false; row.add_child(choice)
	for title in Appearance.PRESETS: choice.add_item(title)
	var apply:=Button.new(); apply.text="Apply"; row.add_child(apply)
	apply.pressed.connect(func(): host._edit_property(actor,host.registry.get_definition(actor.type_id),&"appearance",ActorObjectReference.from_object(Appearance.preset(choice.selected))); host._queue_rebuild_selected())
	var info:=Label.new(); info.text="Appearance presets preserve volume shape and painted density.\nCustom fog shaders bypass built-in appearance.\nScattering direction is in World Environment."; info.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; info.add_theme_font_size_override("font_size",12); add_child(info)
	if RenderingServer.get_current_rendering_method()!=&"forward_plus": info.text="Volumetric fog requires the Forward+ renderer.\n"+info.text
	var status:=Label.new(); status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; status.modulate=Color("ffce83"); add_child(status)
	host._updaters.append(func():
		for editor in host.get_tree().get_nodes_in_group("actor_timeline_editors"):
			if editor.model!=host.model: continue
			var clip:=host.model.clip_for_actor_id(actor.id)
			if clip==null: continue
			var runtime: Node=editor._runtime_for_clip(clip.id)
			if runtime!=null and runtime.content is FogVolume: status.text="\n".join(PackedStringArray([str(runtime.content.get_meta("fog_boundary_error","")),str(runtime.content.get_meta("fog_ground_error",""))])).strip_edges())
