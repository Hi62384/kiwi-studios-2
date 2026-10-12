extends RefCounted
const Number=preload("res://Workspaces/SceneWorkspace/scripts/Timeline/drag_number.gd")
const Picker=preload("res://Workspaces/ImageWorkspace/image_warp_picker.gd")
const MODES=["spot","heal","clone","pattern_heal","pattern_fill","procedural","patch"]
const NAMES=["Spot heal","Healing brush","Clone stamp","Pattern heal","Pattern fill","Procedural texture","Patch repair"]
const HINTS={
	"spot":"Paint over defects · no sample needed",
	"heal":"1 Sample source → 2 Paint to heal",
	"clone":"1 Sample source → 2 Paint a copy",
	"pattern_heal":"Sample clean texture → Paint to extend",
	"pattern_fill":"Load / sample → Paint or Preview",
	"procedural":"Generate → Paint / New layer",
	"patch":"Select pixels → Preview → Apply",
}

static func build(studio: KiwiImageWorkspace) -> void:
	load("res://Workspaces/ImageWorkspace/texture_repair_ui.gd").build(studio)

static func number(parent: Node,caption: String,value: float,minimum: float,maximum: float,step: float,changed: Callable) -> void:
	var label:=Label.new(); label.text=caption; label.add_theme_font_size_override("font_size",11); parent.add_child(label)
	var input:=Number.new(); input.min_value=minimum; input.max_value=maximum; input.step=step; input.value=value; input.custom_minimum_size.x=65; parent.add_child(input)
	input.value_changed.connect(changed); input.preview_changed.connect(changed)
static func setting(parent: Node,caption: String,value: float,changed: Callable) -> void:
	var label:=Label.new(); label.text=caption; label.tooltip_text=caption; label.add_theme_font_size_override("font_size",11); parent.add_child(label)
	var slider:=HSlider.new(); slider.min_value=0; slider.max_value=1; slider.step=.01; slider.value=value; slider.custom_minimum_size=Vector2(66,28); slider.tooltip_text=caption; parent.add_child(slider)
	slider.value_changed.connect(changed)
static func option(parent: Node,captions: Array,ids: Array,current: String,changed: Callable) -> void:
	var node:=parent
	while node!=null and not node is KiwiImageWorkspace: node=node.get_parent()
	if node==null: return
	var studio:=node as KiwiImageWorkspace
	Picker.build(studio,parent,"RepairOption","CHOOSE",ids,captions,current,func(index: int): changed.call(ids[index]); studio._refresh_context())

static func options(studio: KiwiImageWorkspace) -> void:
	var tool=studio.canvas.repair_tool
	var popup:=PopupPanel.new(); studio.add_child(popup); popup.add_theme_stylebox_override("panel",studio._box(Color("152330"),Color("456476"),10,12))
	var column:=VBoxContainer.new(); column.custom_minimum_size=Vector2(360,240); popup.add_child(column)
	var header:=Label.new(); header.text="REPAIR · ADVANCED"; column.add_child(header)
	var ranges:={"texture_preservation":Vector3(0,2,.01),"search_radius":Vector3(1,12,1),"patch_size":Vector3(3,64,1),"boundary_feather":Vector3(0,16,.1)}
	if tool.repair_source=="sample":
		ranges.erase("search_radius"); ranges.erase("patch_size"); ranges.sample_size=Vector3(4,512,1)
	if tool.repair_method=="exact" and tool.repair_source=="sample": ranges.erase("texture_preservation")
	for key in ranges:
		var row:=HBoxContainer.new(); column.add_child(row); var range: Vector3=ranges[key]
		number(row,key.replace("_"," ").capitalize(),tool.config.get(key,range.x),range.x,range.y,range.z,func(next: float): tool.configure(key,next))
	for entry in [["Pressure controls size","pressure"],["Clip to source opacity","clip_alpha"],["Repair on a new layer","new_layer"]]:
		var check:=CheckButton.new(); check.text=entry[0]; check.button_pressed=tool.config.get(entry[1],false); column.add_child(check); check.toggled.connect(func(next: bool): tool.configure(entry[1],next))
	studio._button(column,"Done",popup.hide,"Keep repair settings","check")
	popup.popup_hide.connect(popup.queue_free); popup.popup_centered()

static func load_pattern(studio: KiwiImageWorkspace) -> void:
	var property:=ActorProperty.new(); property.options={"extensions":KiwiImageWorkspace.IMAGE_EXTENSIONS+["tres","res"],"native_resource_types":["KiwiImagePatternPreset","Texture2D"],"file_picker":true}
	var chosen:=await ActorProjectFilePicker.pick(studio,property,"Load pattern image or preset")
	if chosen.is_empty() or chosen==ActorProjectFilePicker.EMPTY_RESOURCE: return
	var tool=studio.canvas.repair_tool
	if chosen.get_extension() in ["tres","res"]:
		var resource:=ResourceLoader.load(chosen)
		if resource is KiwiImagePatternPreset and resource.texture!=null: tool.source_image=resource.texture.get_image(); tool.config.merge(resource.settings,true); if resource.recipe!=null: tool.recipe=resource.recipe.copy_recipe()
		elif resource is Texture2D: tool.source_image=resource.get_image()
	else: tool.source_image=Image.load_from_file(chosen)
	if tool.source_image!=null:
		tool.source_area=Rect2i(Vector2i.ZERO,tool.source_image.get_size()); tool.pattern_path=chosen; tool.config.source_mode="manual"; studio._refresh_context()

static func save_pattern(studio: KiwiImageWorkspace) -> void:
	var tool=studio.canvas.repair_tool
	if tool.source_image==null: studio.status.text="Sample a texture or load a pattern first"; return
	var destination:=await ActorProjectResourceSaveDialog.pick(studio,"Save pattern preset","Pattern","tres",false)
	if destination.get("cancelled",true): return
	var preset:=KiwiImagePatternPreset.new(); preset.settings=tool.config.duplicate(true)
	var sample: Image=tool.source_image.get_region(tool.source_area)
	var sampling: Dictionary=tool.config.duplicate(); sampling.sample_points=tool.source_points
	for y in sample.get_height():
		for x in sample.get_width():
			if not preload("res://Workspaces/ImageWorkspace/image_texture_synthesis.gd").inside_sample(Vector2(tool.source_area.position+Vector2i(x,y))+Vector2.ONE*.5,tool.source_area,sampling): sample.set_pixel(x,y,Color.TRANSPARENT)
	preset.settings.sample_shape="rectangle"
	preset.texture=ImageTexture.create_from_image(sample); preset.recipe=tool.recipe.copy_recipe() if tool.mode=="procedural" else null
	ResourceSaver.save(preset,destination.path)
	if LocalProjectFilesystem.node!=null: LocalProjectFilesystem.update_root_folder()
