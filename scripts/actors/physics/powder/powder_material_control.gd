extends VBoxContainer
## Compact recipe browser inside the existing inspector, not another workspace.
func setup(model: ActorTimeline,actor: ActorData,refresh: Callable) -> void:
	name="PowderMaterialBrowser"
	var row:=HBoxContainer.new(); add_child(row)
	var choice:=OptionButton.new(); choice.name="PowderPreset"; choice.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	for i in KiwiPowderMaterial.NAMES.size(): choice.add_icon_item(thumbnail(i),KiwiPowderMaterial.NAMES[i])
	var current_reference:=actor.get_value(&"powder_material") as ActorObjectReference; var current:=ActorAnimation.resolve_reference(current_reference) if current_reference!=null else null
	if current!=null: choice.select(maxi(0,KiwiPowderMaterial.NAMES.find(str(current.get_value(&"preset_origin","")))))
	row.add_child(choice)
	var options:=HBoxContainer.new(); add_child(options)
	var mode:=OptionButton.new(); mode.name="PowderPresetMode"
	for title in ["Both","Appearance only","Physics only"]: mode.add_item(title)
	mode.tooltip_text="Apply physical defaults, visual appearance, or both. Existing actor source and timeline timing are preserved."; mode.size_flags_horizontal=Control.SIZE_EXPAND_FILL; options.add_child(mode)
	var apply_button:=Button.new(); apply_button.name="ApplyPowderPreset"; apply_button.text="✓"; apply_button.tooltip_text="Apply selected recipe"; apply_button.custom_minimum_size.x=30; row.add_child(apply_button)
	apply_button.pressed.connect(func():
		KiwiPowderMaterial.apply(model,model.selected_actors() if model.selected_actors().has(actor) else [actor],ActorObjectReference.from_object(KiwiPowderMaterial.preset(choice.selected)),mode.selected); refresh.call())
	var actions:=MenuButton.new(); actions.text="⋯"; actions.tooltip_text="Create from current settings, adopt saved physics or restore defaults"; options.add_child(actions)
	for title in ["Create material from current settings","Adopt saved physics defaults","Restore built-in recipe","Save attached deposits as mesh…","Reactivate deposits now"]: actions.get_popup().add_item(title)
	actions.get_popup().id_pressed.connect(func(action: int):
		match action:
			0: KiwiPowderMaterial.apply(model,[actor],ActorObjectReference.from_object(KiwiPowderMaterial.capture(actor)),1)
			1: KiwiPowderMaterial.apply(model,[actor],actor.get_value(&"powder_material") as ActorObjectReference,2)
			2:
				var reference:=actor.get_value(&"powder_material") as ActorObjectReference; var object:=ActorAnimation.resolve_reference(reference) if reference!=null else null
				var index:=KiwiPowderMaterial.NAMES.find(str(object.get_value(&"preset_origin","Sand"))) if object!=null else 0
				KiwiPowderMaterial.apply(model,[actor],ActorObjectReference.from_object(KiwiPowderMaterial.preset(maxi(0,index))),0)
			3: preload("res://scripts/actors/physics/physics_mesh_snapshot.gd").prompt(self,model,actor,true)
			4:
				for editor in get_tree().get_nodes_in_group("actor_timeline_editors"):
					if editor.model==model: model.edit_property(actor,editor.registry.get_definition(&"powder"),&"powder_clear_at",maxf(0,actor.animation_time if not is_nan(actor.animation_time) else 0))
		refresh.call())
	var note:=Label.new(); note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; note.add_theme_font_size_override("font_size",12)
	note.text="Independent actor physics"; note.tooltip_text="Recipes provide defaults. Existing actor physical controls remain authoritative. Grain shapes are visual; collisions remain spherical."; add_child(note)

static func thumbnail(index: int) -> Texture2D:
	var data:=KiwiPowderMaterial.preset(index); var image:=Image.create(40,30,false,Image.FORMAT_RGBA8); image.fill(Color("182430"))
	var rng:=KiwiPowderSource.rng_for(index,100)
	for grain in 7:
		var center:=Vector2(rng.randf_range(5,35),rng.randf_range(5,25)); var radius:=rng.randf_range(2,5); var color: Color=data.values.powder_color.lerp(data.values.powder_secondary,rng.randf())
		for y in range(maxi(0,int(center.y-radius)),mini(30,int(center.y+radius)+1)):
			for x in range(maxi(0,int(center.x-radius)),mini(40,int(center.x+radius)+1)):
				var delta:=Vector2(x,y)-center
				if delta.length()<radius*(1.0 if index==4 else .85+.15*cos(delta.angle()*[5,4,7,6,1,4,6][index])): image.set_pixel(x,y,color*(.7+.3*(1-delta.y/radius)))
	return ImageTexture.create_from_image(image)
