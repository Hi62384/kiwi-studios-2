class_name ActorTransformImage2DRuntime
extends ActorUIRuntime

var renderer := KiwiTransformationRenderer.new()
var session := KiwiTransformationSession.new()
var premultiplied := ShaderMaterial.new()

func _ready() -> void:
	super._ready()
	add_child(renderer)
	renderer.cache.prepared.connect(func():
		if active: evaluate(_time, _values))
	var shader := Shader.new()
	shader.code = "shader_type canvas_item; render_mode unshaded,blend_premul_alpha; void fragment(){COLOR=texture(TEXTURE,UV);}"
	premultiplied.shader = shader
	visual.material = premultiplied

func set_active(value: bool) -> void:
	super.set_active(value)
	renderer.viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if value else SubViewport.UPDATE_DISABLED

func evaluate_transform(values: Dictionary) -> void:
	super.evaluate_transform(values)
	# Keep the referenced document alive even outside the actor's visible clip,
	# so inspecting an inactive actor doesn't repeatedly reload its artwork.
	var asset := ActorTransformationStates.load_asset(actor)
	if asset.document != null and session.document != asset.document:
		renderer.clear_views()
		session.document = asset.document

func evaluate(time: float, values: Dictionary) -> void:
	super.evaluate(time, values)
	var asset := ActorTransformationStates.load_asset(actor)
	if asset.document == null:
		visual.texture = null
		if not renderer.views.is_empty(): renderer.clear_views()
		return
	if session.document != asset.document:
		renderer.clear_views()
		session.document = asset.document
	renderer.sync(session, time, ActorTransformationStates.samples(actor, session.document, time, values))
	visual.texture = renderer.texture()
	visual.material = premultiplied
	visual.queue_redraw()
