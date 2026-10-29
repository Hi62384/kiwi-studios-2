class_name KiwiGrowthAppearanceUI
extends RefCounted
static func styles(workspace: KiwiModelWorkspace,parent: Node,data: KiwiSurfaceGrowthData) -> void:
	workspace._label(parent,"GROWTH STYLE")
	var presets:=OptionButton.new(); presets.name="GrowthStylePreset"; presets.fit_to_longest_item=false; parent.add_child(presets); presets.add_item("Choose a style…")
	for title: String in KiwiGrowthStyle.PRESETS: presets.add_icon_item(KiwiGrowthStyle.preset(title).thumbnail(),title)
	presets.item_selected.connect(func(index: int):
		if index>0: workspace.session.action("Apply growth style",func(): data.growth_style=KiwiGrowthStyle.preset(presets.get_item_text(index)); data.revision+=1))
	if data.growth_style==null:
		workspace._button(parent,"Load style…",func(): load_style(workspace,data)); return
	workspace._label(parent,data.growth_style.title)
	name_field(workspace,parent,data.growth_style)
	for row in [["thickness","Root thickness",.0001,2.,.001],["tip_thickness","Tip thickness (-1 = taper)",-1.,2.,.001],["taper","Taper",0.,1.,.01],["twist","Twist",-12.,12.,.01],["frizz","Frizz",0.,2.,.01],["frizz_frequency","Frizz frequency",.1,24.,.1],["flatten","Cross-section depth",.05,1.,.01],["feather_asymmetry","Vane asymmetry",-.8,.8,.01]]:
		var field: String=row[0]; var base:=KiwiSurfaceGrowth.base_settings(data)
		workspace._number(parent,row[1],float(base.get(field,1. if field=="flatten" else (-1. if field=="tip_thickness" else 0.))),row[2],row[3],row[4],func(value: float): data.growth_style.values[field]=value; data.revision+=1)
	var shape:=OptionButton.new(); shape.fit_to_longest_item=false; parent.add_child(shape)
	for title in ["Ribbon","Card lock","Rounded strand","Tube"]: shape.add_item(title)
	shape.select(int(data.growth_style.values.get("cross_section",0))); shape.item_selected.connect(func(index: int): workspace.session.action("Growth cross-section",func(): data.growth_style.values.cross_section=index; data.revision+=1))
	var row:=HFlowContainer.new(); parent.add_child(row)
	workspace._button(row,"Clear style",func(): workspace.session.action("Clear growth style",func(): data.growth_style=null; data.revision+=1))
	workspace._button(row,"Save style…",func(): save_style(workspace,data))
	workspace._button(row,"Duplicate",func(): workspace.session.action("Duplicate growth style",func(): var copy:=data.growth_style.duplicate(true) as KiwiGrowthStyle; copy.asset_id=ActorData.new_id(); copy.title+=" copy"; data.growth_style=copy))
	if KiwiGrowthStyle.PRESETS.has(data.growth_style.title): workspace._button(row,"Reset preset",func(): workspace.session.action("Reset growth style preset",func(): data.growth_style=KiwiGrowthStyle.preset(data.growth_style.title); data.revision+=1))
	workspace._button(row,"Load style…",func(): load_style(workspace,data))
static func load_style(workspace: KiwiModelWorkspace,data: KiwiSurfaceGrowthData) -> void:
	var property:=ActorProperty.new(); property.options={"extensions":["tres","res"]}
	var path:=await ActorProjectFilePicker.pick(workspace,property,"Load growth style")
	if path.is_empty() or path==ActorProjectFilePicker.EMPTY_RESOURCE: return
	var loaded:=ResourceLoader.load(path) as KiwiGrowthStyle
	if loaded==null: workspace.canvas.notice.emit("Choose a Growth Style resource."); return
	workspace.session.action("Load growth style",func(): data.growth_style=loaded.duplicate(true); data.revision+=1)
static func save_style(workspace: KiwiModelWorkspace,data: KiwiSurfaceGrowthData) -> void:
	var dialog:=FileDialog.new(); dialog.title="Save growth style"; dialog.file_mode=FileDialog.FILE_MODE_SAVE_FILE; dialog.access=FileDialog.ACCESS_FILESYSTEM; dialog.current_dir=ActorProjectFilePicker.root_directory(); dialog.current_file=data.growth_style.title+".tres"; dialog.filters=PackedStringArray(["*.tres ; Growth style"]); workspace.add_child(dialog)
	dialog.file_selected.connect(func(path: String):
		if not FileOperations.is_path_inside(ActorProjectFilePicker.root_directory(),path): workspace.canvas.notice.emit("Choose a location inside the project."); return
		var result:=ResourceSaver.save(data.growth_style,path); workspace.canvas.notice.emit("Style saved." if result==OK else "Could not save style."); dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free); dialog.popup_centered(Vector2i(700,500))
static func build(workspace: KiwiModelWorkspace,parent: Node,data: KiwiSurfaceGrowthData) -> void:
	if data.appearance==null: KiwiSurfaceGrowth.render(data)
	var material:=data.appearance
	workspace._label(parent,"RENDERING & MATERIAL")
	name_field(workspace,parent,material)
	var presets:=OptionButton.new(); presets.name="GrowthAppearancePreset"; presets.fit_to_longest_item=false; parent.add_child(presets); presets.add_item("Appearance presets…")
	for title: String in KiwiGrowthMaterial.PRESETS: presets.add_icon_item(KiwiGrowthMaterial.preset(title).thumbnail(),title)
	presets.item_selected.connect(func(index: int):
		if index>0: workspace.session.action("Apply growth appearance preset",func(): data.appearance=KiwiGrowthMaterial.preset(presets.get_item_text(index))))
	var mode:=OptionButton.new(); mode.name="GrowthRenderingMode"; mode.fit_to_longest_item=false; parent.add_child(mode)
	for title in ["Realistic","Stylized / M2DO","Custom material"]: mode.add_item(title)
	mode.select(material.mode); mode.item_selected.connect(func(index: int): workspace.session.action("Growth rendering mode",func(): material.mode=index))
	if material.mode==2:
		workspace._label(parent,"Custom shading supplies its own appearance. Geometry and root attachment remain editable.")
		asset_actions(workspace,parent,data); return
	var coverage:=OptionButton.new(); coverage.fit_to_longest_item=false; parent.add_child(coverage)
	for title in ["Stable cutout / automatic translucency","Alpha hash coverage","Alpha to coverage · needs MSAA"]: coverage.add_item(title)
	coverage.select(material.coverage); coverage.item_selected.connect(func(index: int): workspace.session.action("Growth coverage",func(): material.coverage=index))
	var lod:=CheckButton.new(); lod.name="GrowthAutomaticLOD"; lod.text="Distance detail"; lod.button_pressed=data.rendering.get("automatic_lod",true); parent.add_child(lod); lod.toggled.connect(func(value: bool): workspace.session.action("Growth distance detail",func(): data.rendering.automatic_lod=value))
	if lod.button_pressed:
		for row in [["near","Full detail distance",.1,1000.],["far","Far detail distance",.2,10000.],["minimum_density","Distant coverage",.05,1.]]:
			var field: String=row[0]; workspace._number(parent,row[1],float(data.rendering.get(field,4. if field=="near" else (16. if field=="far" else .15))),row[2],row[3],.01,func(value: float): data.rendering[field]=value)
	var section:=OptionButton.new(); section.fit_to_longest_item=false; parent.add_child(section)
	var titles:=["Color & highlights","Coat pattern","Feather appearance","Textures","Stylized shading","Root-to-tip gradient"]
	for title: String in titles: section.add_item(title)
	section.select(int(workspace.get_meta("growth_material_section",0)))
	section.item_selected.connect(func(index: int): workspace.set_meta("growth_material_section",index); workspace._refresh_pending=true)
	var colors: Array=[]; var numbers: Array=[]
	match section.selected:
		0:
			colors=[["root_color","Roots"],["tip_color","Tips"],["highlight_color","Highlights"],["emission","Emission"]]
			numbers=[["roughness","Roughness",.04,1.],["specular","Primary highlight",0.,1.],["secondary_highlight","Secondary highlight",0.,1.],["highlight_shift","Highlight shift",-.8,.8],["backlight","Backlighting",0.,1.],["opacity","Coverage",0.,1.],["variation","Strand color variation",0.,1.]]
		1:
			var pattern:=OptionButton.new(); pattern.fit_to_longest_item=false; parent.add_child(pattern)
			for title in ["No pattern","Stripes","Spots","Speckles","Mottle","Patches"]: pattern.add_item(title)
			pattern.select(material.pattern); pattern.item_selected.connect(func(index: int): workspace.session.action("Growth coat pattern",func(): material.pattern=index))
			colors=[["pattern_color","Pattern color"]]; numbers=[["pattern_scale","Pattern scale",.01,100.],["pattern_rotation","Pattern rotation",-PI,PI],["pattern_mix","Pattern blend",0.,1.],["pattern_seed","Pattern seed",0.,10000.]]
		2:
			colors=[["shaft_color","Shaft color"],["left_vane_color","Left vane tint"],["right_vane_color","Right vane tint"],["feather_pattern_color","Marking color"]]; numbers=[["feather_detail","Vane detail",0.,1.],["iridescence","Iridescence",0.,1.],["shaft_roughness","Shaft roughness",.04,1.],["feather_pattern_scale","Marking scale",.1,40.],["feather_pattern_width","Marking width",0.,1.]]
			var pattern:=OptionButton.new(); pattern.fit_to_longest_item=false; parent.add_child(pattern)
			for title in ["No markings","Bands","Spots","Edges","Tips","Speckles"]: pattern.add_item(title)
			pattern.select(material.feather_pattern); pattern.item_selected.connect(func(index: int): workspace.session.action("Feather markings",func(): material.feather_pattern=index))
		3:
			for field: String in ["albedo_texture","roughness_texture","normal_texture","alpha_texture"]:
				var row:=HBoxContainer.new(); parent.add_child(row)
				workspace._button(row,field.trim_suffix("_texture").capitalize()+"…",func():
					var property:=ActorProperty.new(); property.object_type=&"image"; property.options={"extensions":["png","jpg","jpeg","webp","tres","res"],"accepted_object_types":["image","noise_image"],"native_resource_types":["Texture2D"]}
					var path:=await ActorProjectFilePicker.pick(workspace,property,"Choose growth texture")
					if path.is_empty(): return
					var texture: Texture2D=null
					if path!=ActorProjectFilePicker.EMPTY_RESOURCE:
						if path.get_extension() in ["tres","res"]:
							var loaded:=ResourceLoader.load(path); texture=ActorImageGenerator.texture_for_object(loaded) if loaded is ActorObjectData else loaded as Texture2D
						else:
							var image:=Image.load_from_file(path)
							if image!=null: image.generate_mipmaps(); texture=ImageTexture.create_from_image(image)
					workspace.session.action("Growth texture",func():
						material.set(field,texture)
						if path!=ActorProjectFilePicker.EMPTY_RESOURCE: material.texture_sources[field]=path
						else: material.texture_sources.erase(field)))
				workspace._button(row,"×",func(): workspace.session.action("Clear growth texture",func(): material.set(field,null); material.texture_sources.erase(field)))
				workspace._button(row,"Noise",func(): workspace.session.action("Create growth noise texture",func():
					var texture:=NoiseTexture2D.new(); texture.width=256; texture.height=256; texture.generate_mipmaps=true; texture.noise=FastNoiseLite.new(); texture.noise.frequency=.025; material.set(field,texture); material.texture_sources.erase(field)))
				var generated:=material.get(field) as NoiseTexture2D
				if generated!=null and generated.noise is FastNoiseLite:
					var noise:=generated.noise as FastNoiseLite
					workspace._number(parent,field.trim_suffix("_texture").capitalize()+" frequency",noise.frequency,.0001,1,.001,func(value: float): noise.frequency=value)
					workspace._number(parent,"Noise seed",noise.seed,0,1000000,1,func(value: float): noise.seed=int(value))
					var normal:=CheckButton.new(); normal.text="Noise as normal map"; normal.button_pressed=generated.as_normal_map; parent.add_child(normal); normal.toggled.connect(func(value: bool): workspace.session.action("Growth noise normal map",func(): generated.as_normal_map=value))
			for field: String in ["texture_scale","texture_offset"]:
				for axis in 2: workspace._number(parent,field.capitalize()+" "+["X","Y"][axis],material.get(field)[axis],-100,100,.01,func(value: float): var vector: Vector2=material.get(field); vector[axis]=value; material.set(field,vector))
			numbers=[["texture_rotation","Texture rotation",-PI,PI]]
		4:
			colors=[["outline_color","Outline color"]]; numbers=[["bands","Lighting bands",1.,8.],["edge_softness","Band softness",0.,.49],["outline","Vane / card edge width",0.,.4]]
		5:
			if material.gradient==null:
				workspace._button(parent,"Create multicolor gradient",func(): workspace.session.action("Create growth gradient",func(): material.gradient=Gradient.new(); material.gradient.colors=PackedColorArray([material.root_color,material.tip_color])))
			else:
				for index in material.gradient.get_point_count():
					var color:=ColorPickerButton.new(); color.color=material.gradient.get_color(index); color.custom_minimum_size.y=24; parent.add_child(color)
					var before:={"color":color.color}
					color.color_changed.connect(func(value: Color): material.gradient.set_color(index,value))
					color.popup_closed.connect(func(): var after:=color.color; material.gradient.set_color(index,before.color); workspace.session.action("Growth gradient color",func(): material.gradient.set_color(index,after)); before.color=after)
					var low:=material.gradient.get_offset(index-1)+.001 if index>0 else 0.; var high:=material.gradient.get_offset(index+1)-.001 if index<material.gradient.get_point_count()-1 else 1.
					workspace._number(parent,"Stop position",material.gradient.get_offset(index),low,high,.001,func(value: float): material.gradient.set_offset(index,value))
					if material.gradient.get_point_count()>2: workspace._button(parent,"Remove stop",func(): workspace.session.action("Remove gradient stop",func(): material.gradient.remove_point(index)))
				workspace._button(parent,"Add gradient stop",func(): workspace.session.action("Add gradient stop",func():
					var at:=.5; var widest:=0.
					for index in material.gradient.get_point_count()-1:
						var width:=material.gradient.get_offset(index+1)-material.gradient.get_offset(index)
						if width>widest: widest=width; at=(material.gradient.get_offset(index)+material.gradient.get_offset(index+1))*.5
					material.gradient.add_point(at,material.gradient.sample(at))))
				workspace._button(parent,"Use root / tip colors",func(): workspace.session.action("Remove growth gradient",func(): material.gradient=null))
	for row: Array in colors:
		workspace._label(parent,row[1]); var input:=ColorPickerButton.new(); input.name="Growth"+str(row[0]).to_pascal_case(); input.color=material.get(row[0]); input.custom_minimum_size.y=24; parent.add_child(input)
		var before:={"value":input.color}; input.picker_created.connect(func(): input.get_picker().color_mode=ColorPicker.MODE_RGB)
		input.popup_closed.connect(func():
			var after:=input.color; material.set(row[0],before.value); workspace.session.action("Growth "+str(row[1]),func(): material.set(row[0],after)); before.value=after)
		input.color_changed.connect(func(value: Color): material.set(row[0],value))
	for row: Array in numbers:
		var field: String=row[0]; workspace._number(parent,row[1],float(material.get(field)),row[2],row[3],1. if field in ["bands","pattern_seed"] else .01,func(value: float): material.set(field,int(value) if field=="bands" else value))
	asset_actions(workspace,parent,data)
static func asset_actions(workspace: KiwiModelWorkspace,parent: Node,data: KiwiSurfaceGrowthData) -> void:
	var material:=data.appearance; var actions:=HFlowContainer.new(); parent.add_child(actions)
	workspace._button(actions,"Save material…",func(): save(workspace,data))
	workspace._button(actions,"Load material…",func():
		var property:=ActorProperty.new(); property.options={"extensions":["tres","res"]}
		var path:=await ActorProjectFilePicker.pick(workspace,property,"Load growth material")
		if path.is_empty() or path==ActorProjectFilePicker.EMPTY_RESOURCE: return
		var loaded:=ResourceLoader.load(path) as KiwiGrowthMaterial
		if loaded==null: workspace.canvas.notice.emit("Choose a Growth Material resource."); return
		workspace.session.action("Load growth material",func(): data.appearance=loaded.copy_material(true)))
	workspace._button(actions,"Link material…",func():
		var property:=ActorProperty.new(); property.options={"extensions":["tres","res"]}; var path:=await ActorProjectFilePicker.pick(workspace,property,"Link shared growth material")
		if path.is_empty() or path==ActorProjectFilePicker.EMPTY_RESOURCE: return
		var loaded:=ResourceLoader.load(path) as KiwiGrowthMaterial
		if loaded==null: workspace.canvas.notice.emit("Choose a Growth Material resource."); return
		workspace.session.action("Link growth material",func(): loaded.linked_source=path; data.appearance=loaded))
	workspace._button(actions,"Make unique",func(): workspace.session.action("Make growth material unique",func(): data.appearance=material.copy_material(true)))
	workspace._button(actions,"Duplicate",func(): workspace.session.action("Duplicate growth material",func(): data.appearance=material.copy_material(true); data.appearance.title+=" copy"))
	if not material.linked_source.is_empty():
		workspace._label(parent,"Shared material · "+material.linked_source.get_file())
		workspace._button(parent,"Save linked material",func():
			if FileOperations.is_path_inside(ActorProjectFilePicker.root_directory(),ProjectSettings.globalize_path(material.linked_source)): workspace.canvas.notice.emit("Material saved." if ResourceSaver.save(material,material.linked_source)==OK else "Could not save material."))
	if material.mode==2:
		workspace._button(parent,"Load custom material…",func():
			var property:=ActorProperty.new(); property.object_type=&"material"; property.options={"extensions":["tres","res"],"accepted_object_types":["material","shader_material","natural_material"],"native_resource_types":["Material"]}
			var path:=await ActorProjectFilePicker.pick(workspace,property,"Custom growth material")
			if path.is_empty(): return
			var resource: Resource=null if path==ActorProjectFilePicker.EMPTY_RESOURCE else ResourceLoader.load(path); var loaded:=KiwiGrowthMaterial.from_asset(resource)
			if resource!=null and loaded==null: workspace.canvas.notice.emit("Choose a spatial material or Spatial ShaderMaterial."); return
			workspace.session.action("Custom growth material",func(): material.custom=loaded; material.custom_asset=resource as ActorObjectData))
static func save(workspace: KiwiModelWorkspace,data: KiwiSurfaceGrowthData) -> void:
	var dialog:=FileDialog.new(); dialog.title="Save growth material"; dialog.file_mode=FileDialog.FILE_MODE_SAVE_FILE; dialog.access=FileDialog.ACCESS_FILESYSTEM; dialog.current_dir=ActorProjectFilePicker.root_directory(); dialog.current_file=data.appearance.title.validate_filename()+".tres"; dialog.filters=PackedStringArray(["*.tres ; Growth material"]); workspace.add_child(dialog)
	dialog.file_selected.connect(func(path: String):
		if not FileOperations.is_path_inside(ActorProjectFilePicker.root_directory(),path): workspace.canvas.notice.emit("Choose a location inside the project."); return
		var result:=ResourceSaver.save(data.appearance,path); workspace.canvas.notice.emit("Material saved." if result==OK else "Could not save material."); dialog.queue_free()
		if result==OK and LocalProjectFilesystem.node!=null: LocalProjectFilesystem.update_root_folder())
	dialog.canceled.connect(dialog.queue_free); dialog.popup_centered(Vector2i(700,500))
static func name_field(workspace: KiwiModelWorkspace,parent: Node,resource: Resource) -> void:
	var input:=LineEdit.new(); input.text=str(resource.get("title")); input.placeholder_text="Preset name"; input.tooltip_text="Saved presets appear in project files, where they can also be renamed or deleted."; input.size_flags_horizontal=Control.SIZE_EXPAND_FILL; parent.add_child(input)
	var commit:=func():
		var title:=input.text.strip_edges().left(64)
		if not title.is_empty() and title!=str(resource.get("title")): workspace.session.action("Rename growth preset",func(): resource.set("title",title))
	input.text_submitted.connect(func(_value: String): commit.call()); input.focus_exited.connect(commit)
