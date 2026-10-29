extends HBoxContainer
func setup(host: ActorInspector,actor: ActorData) -> void:
	name="DamageMaterialPresets"
	var choice:=OptionButton.new(); choice.name="DamageMaterialPreset"; choice.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	for title in KiwiDestructionMaterial.NAMES: choice.add_item(title)
	var current:=KiwiDestructionMaterial.resolve(actor.values)
	if current!=null: choice.select(maxi(0,KiwiDestructionMaterial.NAMES.find(str(current.get_value(&"material_name","")))))
	add_child(choice)
	var apply:=Button.new(); apply.name="ApplyDamageMaterial"; apply.text="✓"; apply.tooltip_text="Apply selected physical material preset"; apply.custom_minimum_size.x=30; add_child(apply)
	apply.pressed.connect(func(): host._edit_property(actor,host.registry.get_definition(actor.type_id),&"destruction_material",ActorObjectReference.from_object(KiwiDestructionMaterial.preset(choice.selected))); host._queue_rebuild_selected())
