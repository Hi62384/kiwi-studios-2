class_name KiwiImageDocument
extends Resource
## Native image composition; Save writes this alongside its flattened output.

@export var version: int = 1
@export var canvas_size := Vector2i(1280, 720)
@export var layers: Array[KiwiImageLayer] = []
@export var output_path: String = ""
@export var preview: Texture2D
@export var workspace_state: Dictionary = {}
@export var selections: Dictionary = {}
@export var pixel_selection: Texture2D
@export var pixel_selection_owner: String=""
# The mask is kept in the canvas space in which it was painted.  Keeping the
# owner's state from that moment lets the selection follow perspective yaw
# without destructively rasterising (and clipping) it after every transform.
@export var pixel_selection_reference: KiwiImageLayer
@export var pixel_selection_reference_world := Transform2D.IDENTITY


func layer_for_id(id: String) -> KiwiImageLayer:
	for layer in layers:
		if layer.id == id: return layer
	return null


func children(parent: String = "") -> Array[KiwiImageLayer]:
	var result: Array[KiwiImageLayer] = []
	for layer in layers:
		if layer.parent_id == parent: result.append(layer)
	return result


func is_descendant(id: String, ancestor: String) -> bool:
	var layer := layer_for_id(id)
	var seen := {}
	while layer != null and not layer.parent_id.is_empty() and not seen.has(layer.id):
		seen[layer.id] = true
		if layer.parent_id == ancestor: return true
		layer = layer_for_id(layer.parent_id)
	return false


func world_transform(layer: KiwiImageLayer) -> Transform2D:
	var result := layer.local_transform()
	var current := layer_for_id(layer.parent_id)
	var seen := {layer.id: true}
	while current != null and not seen.has(current.id):
		seen[current.id] = true
		result = current.local_transform() * result
		current = layer_for_id(current.parent_id)
	return result


func can_edit(layer: KiwiImageLayer) -> bool:
	if not layer.visible or layer.locked or not isolation_allows(layer): return false
	var parent := layer_for_id(layer.parent_id)
	while parent != null:
		if not parent.visible or parent.locked: return false
		parent = layer_for_id(parent.parent_id)
	return true


func isolation_allows(layer: KiwiImageLayer) -> bool:
	if layer.isolated: return true
	for other in layers:
		if other.isolated: return false
	return true


func selected_roots(ids: Array[String]) -> Array[KiwiImageLayer]:
	var result: Array[KiwiImageLayer] = []
	for layer in layers:
		if not ids.has(layer.id): continue
		var nested := false
		for id in ids:
			if is_descendant(layer.id, id): nested = true; break
		if not nested: result.append(layer)
	return result


func snapshot() -> KiwiImageDocument:
	var copy := KiwiImageDocument.new()
	copy.canvas_size = canvas_size
	copy.output_path = output_path
	copy.preview = preview
	copy.workspace_state = workspace_state.duplicate(true)
	copy.selections = selections.duplicate()
	copy.pixel_selection=pixel_selection; copy.pixel_selection_owner=pixel_selection_owner
	copy.pixel_selection_reference=pixel_selection_reference.copy_layer() if pixel_selection_reference!=null else null
	copy.pixel_selection_reference_world=pixel_selection_reference_world
	for layer in layers: copy.layers.append(layer.copy_layer())
	return copy


func resize_layer(layer: KiwiImageLayer, dimensions: Vector2) -> void:
	var ratio := dimensions / layer.dimensions.max(Vector2.ONE)
	if layer.kind=="text": layer.properties.text_scale=float(layer.properties.get("text_scale",1.0))*sqrt(absf(ratio.x*ratio.y))
	if not children(layer.id).is_empty():
		for child in layers:
			if is_descendant(child.id, layer.id):
				child.position *= ratio
				child.dimensions *= ratio
				if child.kind=="text": child.properties.text_scale=float(child.properties.get("text_scale",1.0))*sqrt(absf(ratio.x*ratio.y))
	layer.dimensions = dimensions
