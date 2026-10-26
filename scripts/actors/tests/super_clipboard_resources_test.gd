extends SceneTree
var checks:=0
var failures:=0
func _initialize() -> void: run.call_deferred()
func check(ok: bool,title: String) -> void:
	checks+=1
	if not ok: failures+=1; push_error(title)
	print("PASS " if ok else "FAIL ",title)
func run() -> void:
	var store:=KiwiClipboardStore.new("user://clipboard_resource_tests_"+ActorData.new_id())
	var bitmap:=Image.create(6,5,false,Image.FORMAT_RGBA8); bitmap.fill(Color.TURQUOISE)
	var document:=KiwiImageDocument.new(); document.output_path="C:/a-different-project/deleted-original.png"; var layer:=KiwiImageLayer.create("image",Vector2i(6,5)); layer.texture=ImageTexture.create_from_image(bitmap); document.layers.append(layer)
	var image_id:=store.save(document,"Layered image")
	check(not image_id.is_empty(),"Image documents preserve embedded image data without requiring an old output file")
	var copy:=ResourceLoader.load(store.entry_path(image_id),"",ResourceLoader.CACHE_MODE_IGNORE) as KiwiImageDocument
	check(copy.layers.size()==1 and copy.layers[0].texture.get_image().get_pixel(2,2).b>.7 and copy.output_path.is_empty(),"Layer pixels survive saving, while the old output destination is not reused")
	var session:=KiwiModelSession.new(); var parent:=session.add("Cube",{}); var child:=session.add("Sphere",{}); child.parent_id=parent.id
	var model_id:=store.save(session.document,"Hierarchical model"); var model:=ResourceLoader.load(store.entry_path(model_id),"",ResourceLoader.CACHE_MODE_IGNORE) as KiwiModelDocument
	check(model.components.size()==2 and model.components[1].parent_id==model.components[0].id,"3D model component geometry and parenting survive clipboard serialization")
	var shader_path:=store.root.path_join("Source.gdshader"); var file:=FileAccess.open(shader_path,FileAccess.WRITE); file.store_string("// Surface shader with a comment\nshader_type spatial;\nvoid fragment(){ ALBEDO=vec3(0.2,0.5,0.8); }\n"); file.close()
	var shader_id:=store.save(shader_path,"Surface shader")
	check(not shader_id.is_empty() and store.entry_path(shader_id).ends_with(".gdshader"),"File-backed shaders retain a compatible .gdshader format")
	DirAccess.remove_absolute(shader_path)
	check((ResourceLoader.load(store.entry_path(shader_id),"",ResourceLoader.CACHE_MODE_IGNORE) as Shader).code.contains("ALBEDO"),"Stored shader code works after the source file is deleted")
	var audio:=AudioStreamWAV.new(); audio.format=AudioStreamWAV.FORMAT_16_BITS; audio.mix_rate=8000; audio.data=PackedByteArray([0,0,5,0,10,0,5,0])
	var audio_id:=store.save(audio,"Embedded sound"); var sound:=ResourceLoader.load(store.entry_path(audio_id),"",ResourceLoader.CACHE_MODE_IGNORE) as AudioStreamWAV
	check(sound!=null and sound.data==audio.data,"Embedded audio stream samples persist independently of source files")
	var noise:=NoiseTexture2D.new(); noise.width=32; noise.height=32; noise.noise=FastNoiseLite.new(); noise.noise.seed=37
	var material:=ShaderMaterial.new(); material.shader=Shader.new(); material.shader.code="shader_type spatial; uniform sampler2D detail; void fragment(){ALBEDO=texture(detail,UV).rgb;}"; material.set_shader_parameter("detail",noise)
	var mat_id:=store.save(material,"Procedural material"); var mat:=ResourceLoader.load(store.entry_path(mat_id),"",ResourceLoader.CACHE_MODE_IGNORE) as ShaderMaterial
	check(mat.get_shader_parameter("detail") is NoiseTexture2D and mat.get_shader_parameter("detail").noise.seed==37,"Native shader materials preserve editable noise texture dependencies")
	check(store.entry_path("../../outside").is_empty(),"Clipboard item identities cannot be used for path traversal")
	var text:=ActorObjectData.new(); text.type_id=&"text_settings"; text.values={&"text":"C:/this is text, not a file"}
	check(not store.save(text,"Literal text").is_empty(),"Text and shader comments are not mistaken for dependency paths")
	var wrong:=store.save(store.root.path_join("Missing.obj"),"Unsupported")
	check(wrong.is_empty() and not store.error.is_empty(),"Unsupported or missing resources report an explicit error")
	store.close(); session._undo.clear(); session._redo.clear()
	print("SUPER CLIPBOARD RESOURCES: %d checks, %d failures"%[checks,failures]); quit(failures)
