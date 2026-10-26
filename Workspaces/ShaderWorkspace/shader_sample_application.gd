extends RefCounted
## The library uses the existing actor reference/UndoRedo path. In particular,
## a canvas or fog shader never masquerades as a spatial surface material.

static func target_for(tree: SceneTree, kind: String) -> Dictionary:
	var editor := tree.get_first_node_in_group("actor_timeline_editors")
	if editor == null:
		return {"reason": "Open a scene and select a compatible actor."}
	return target_for_model(editor.model, editor.registry, kind)

static func target_for_model(model: ActorTimeline, registry: ActorRegistry, kind: String) -> Dictionary:
	var actor := model.selected_actor()
	if actor == null:
		return {"reason": "Select a compatible scene actor first."}
	var definition := registry.get_definition(actor.type_id)
	if definition == null:
		return {"reason": "The selected actor has no material definition."}
	if kind == "particles":
		return {"reason": "This actor system does not expose a GPU particle process-shader slot. Copy, save, or open this shader for GPUParticles."}
	var key: StringName = &"environment" if kind == "sky" else &"material"
	var property := definition.find_property(key)
	var object_type: StringName = &"shader_material"
	if kind == "canvas_item": object_type = &"canvas_shader_material"
	elif kind == "fog": object_type = &"fog_shader_material"
	var object_definition := registry.get_object_definition(&"environment" if kind == "sky" else object_type)
	if property == null or object_definition == null:
		return {"reason": "%s has no compatible %s material slot." % [actor.display_name, kind]}
	var candidate := ActorObjectReference.from_object(object_definition.create_object())
	if not property.accepts(candidate):
		return {"reason": "%s does not accept %s shaders." % [actor.display_name, kind]}
	return {"model": model, "registry": registry, "actor": actor, "definition": definition,
		"key": key, "object_type": object_type, "kind": kind,
		"label": actor.display_name + " / " + property.label,
		"existing": actor.get_value(key) != null}

static func apply_to_target(target: Dictionary, source: String, sample_name: String) -> String:
	if not target.has("actor"):
		return str(target.get("reason", "No compatible target."))
	var model: ActorTimeline = target.model
	var actor: ActorData = target.actor
	# Revalidate selection and compatibility after the confirmation dialog.
	var current := target_for_model(model, target.registry, str(target.kind))
	if not current.has("actor") or current.actor != actor:
		return "The selected actor changed. Select the target again before applying."
	if RegEx.create_from_string("(?m)^\\s*shader_type\\s+" + str(target.kind) + "\\s*;").search(source) == null:
		return "The shader source is incompatible with this material slot."
	var shader := Shader.new()
	shader.resource_name = sample_name
	shader.code = source
	var shader_definition := (target.registry as ActorRegistry).get_object_definition(target.object_type)
	var object := shader_definition.create_object()
	object.values[&"shader_path"] = shader
	var reference := ActorObjectReference.from_object(object)
	if str(target.kind) == "sky":
		var previous_reference: Variant = actor.get_value(&"environment")
		var previous := ActorAnimation.resolve_reference(previous_reference) if previous_reference is ActorObjectReference else null
		var environment: ActorObjectData = previous.copy_object() if previous != null else (target.registry as ActorRegistry).get_object_definition(&"environment").create_object()
		environment.values[&"background_mode"] = 3
		environment.values[&"sky_material"] = reference
		reference = ActorObjectReference.from_object(environment)
	model.edit_property(actor, target.definition, target.key, reference)
	return ""
