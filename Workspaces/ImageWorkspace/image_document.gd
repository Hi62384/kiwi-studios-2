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
@export var selection_masks: Dictionary = {}
@export var active_selection_mask: String = ""
@export var pixel_selection: Texture2D
@export var pixel_selection_owner: String=""
# The mask is kept in the canvas space in which it was painted.  Keeping the
# owner's state from that moment lets the selection follow perspective yaw
# without destructively rasterising (and clipping) it after every transform.
@export var pixel_selection_reference: KiwiImageLayer
@export var pixel_selection_reference_world := Transform2D.IDENTITY
@export var live_materials: Array[KiwiLiveMaterialTemplate] = []
@export var active_live_material_id: String = ""
@export var live_edit_enabled: bool = false


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
	var has_isolation := false
	for other in layers:
		if not other.isolated: continue
		has_isolation = true
		if is_descendant(layer.id, other.id): return true
		# Groups render their children into a single source. The ancestor container
		# must stay visible to show an isolated child, while its siblings stay hidden.
		if layer.kind == "group" and is_descendant(other.id, layer.id): return true
	return not has_isolation


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
	copy.version = version
	copy.canvas_size = canvas_size
	copy.output_path = output_path
	copy.preview = preview
	copy.workspace_state = workspace_state.duplicate(true)
	copy.selections = selections.duplicate()
	copy.selection_masks=selection_masks.duplicate(true); copy.active_selection_mask=active_selection_mask
	copy.pixel_selection=pixel_selection; copy.pixel_selection_owner=pixel_selection_owner
	copy.pixel_selection_reference=pixel_selection_reference.copy_layer() if pixel_selection_reference!=null else null
	copy.pixel_selection_reference_world=pixel_selection_reference_world
	copy.active_live_material_id = active_live_material_id
	copy.live_edit_enabled = live_edit_enabled
	for template in live_materials: copy.live_materials.append(template.copy_template())
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


func create_live_material(material: KiwiTextureMaterial, label: String = "") -> KiwiLiveMaterialTemplate:
	var template := KiwiLiveMaterialTemplate.new()
	template.id = ActorData.new_id()
	template.material = material.copy_material()
	template.material.coverage = null
	template.material.source = null
	template.label = label if not label.strip_edges().is_empty() else material.label
	live_materials.append(template)
	active_live_material_id = template.id
	version = maxi(version, 2)
	return template


func live_material_for_id(template_id: String) -> KiwiLiveMaterialTemplate:
	for template in live_materials:
		if template.id == template_id: return template
	return null


func set_live_material(template_id: String, material: KiwiTextureMaterial) -> bool:
	var template := live_material_for_id(template_id)
	if template == null or material == null: return false
	# Preset and active brush instances never alias the saved document instance.
	template.material = material.copy_material()
	template.material.coverage = null
	template.material.source = null
	return true


func live_material_has_artwork(template_id: String) -> bool:
	for layer in layers:
		for region in layer.live_paint:
			if region.template_id == template_id and region.coverage != null:
				var pixels := region.coverage.get_image()
				if pixels != null and pixels.get_used_rect().has_area(): return true
	return false


func add_live_region(layer: KiwiImageLayer, template_id: String, coverage: Texture2D = null,
		mapping: Transform2D = Transform2D.IDENTITY) -> KiwiLivePaintRegion:
	if layer == null or live_material_for_id(template_id) == null: return null
	# Freeze the preceding raster paint at exactly its existing stack position.
	# A transparent top bitmap remains available to the ordinary color brush.
	var size := Vector2i(layer.dimensions.ceil()).max(Vector2i.ONE)
	var has_raster := false
	if layer.texture != null:
		size = Vector2i(layer.texture.get_size())
		var pixels := layer.texture.get_image()
		has_raster = pixels != null and pixels.get_used_rect().has_area()
	if has_raster:
		var frozen := KiwiLivePaintRegion.new()
		frozen.id = ActorData.new_id()
		frozen.raster = layer.texture
		layer.live_paint.append(frozen)
		var blank := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
		blank.fill(Color(0, 0, 0, 0))
		layer.texture = ImageTexture.create_from_image(blank)
		# Restore-paint operates on the current raster segment. The old base is
		# already in the ordered stack and must never be duplicated above it.
		layer.paint_base = layer.texture
	elif layer.texture == null:
		var blank := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
		blank.fill(Color(0, 0, 0, 0))
		layer.texture = ImageTexture.create_from_image(blank)
		layer.paint_base = layer.texture
	# Consecutive strokes on one template share coverage, avoiding one draw call
	# per brush event. A different material/raster segment preserves paint order.
	if coverage == null and not layer.live_paint.is_empty():
		var previous: KiwiLivePaintRegion = layer.live_paint[-1]
		if previous.template_id == template_id and previous.coordinates == null and live_material_for_id(template_id).material.application == "continuous" and previous.mapping.is_equal_approx(mapping):
			return previous
	var region := KiwiLivePaintRegion.new()
	region.id = ActorData.new_id()
	region.template_id = template_id
	region.mapping = mapping
	if coverage == null:
		var mask_image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
		mask_image.fill(Color(0, 0, 0, 0))
		coverage = ImageTexture.create_from_image(mask_image)
	region.coverage = coverage
	layer.live_paint.append(region)
	version = maxi(version, 2)
	return region


func delete_live_material(template_id: String) -> bool:
	var template := live_material_for_id(template_id)
	if template == null: return false
	for layer in layers:
		for index in range(layer.live_paint.size() - 1, -1, -1):
			if layer.live_paint[index].template_id == template_id:
				layer.live_paint.remove_at(index)
	live_materials.erase(template)
	if active_live_material_id == template_id:
		active_live_material_id = live_materials[0].id if not live_materials.is_empty() else ""
	return true


func pack_live_material_textures() -> void:
	# Only call on a save snapshot. Portable lossless buffers keep coverage compact
	# without changing alpha, and do not touch the currently editable GPU textures.
	var packed: Dictionary = {}
	for layer in layers:
		for region in layer.live_paint:
			for field in ["coverage", "raster"]:
				var texture: Texture2D = region.get(field)
				if not texture is ImageTexture or not texture.resource_path.is_empty(): continue
				var key := texture.get_instance_id()
				if not packed.has(key):
					var compact := PortableCompressedTexture2D.new()
					compact.keep_compressed_buffer = true
					compact.create_from_image(texture.get_image(), PortableCompressedTexture2D.COMPRESSION_MODE_LOSSLESS)
					packed[key] = compact
				region.set(field, packed[key])
