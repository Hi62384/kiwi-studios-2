extends RefCounted
## An editable generator layer, preserving sculpted samples and all previous rules.
const Buildings=preload("res://Workspaces/EnvironmentWorkspace/architecture/building_session.gd")
static func set_modifier(session: KiwiEnvironmentSession,id: String,terrain_id: String,feather: float=1.,remove: bool=false) -> String:
	var root:=session.document.component(id); var source:=Buildings.source(root); var terrain:=session.environment().terrain(terrain_id); var ground:=session.document.component(terrain_id)
	if source==null or terrain==null or ground==null or not session.document.editable_component(ground): return "Choose an editable building and terrain."
	var world:=session.document.world_transform(ground)
	if absf(world.basis.determinant())<.000001: return "A zero-size terrain cannot receive a foundation modifier."
	var relative:=world.affine_inverse()*session.document.world_transform(root); var floor: Dictionary=source.floors[0]; var height:=float(floor.get("elevation",0.))-float(source.slab_thickness); var origin:=relative*Vector3(0,height,0); var plane:=Plane(origin,relative*Vector3(1,height,0),relative*Vector3(0,height,1))
	if absf(plane.normal.y)<.2: return "The foundation is too steep relative to this terrain."
	var polygon:=PackedVector2Array()
	for point in floor.get("footprint",source.footprint): var position: Vector3=relative*Vector3(point.x,height,point.y); polygon.append(Vector2(position.x,position.z))
	var generator:=terrain.generation.duplicate(true) as KiwiTerrainGenerator if terrain.generation!=null else KiwiTerrainGenerator.new()
	if terrain.generation==null: generator.medium_weight=0.; generator.fine_weight=0.
	generator.foundation_edits=terrain.edits.duplicate()
	var layers: Array[Dictionary]=[]
	for layer in generator.layers:
		if layer.get("foundation_owner","")!=id: layers.append(layer)
	if not remove: layers.append({"id":"foundation:"+id,"foundation_owner":id,"type":"Foundation","enabled":true,"polygon":polygon,"plane":plane,"feather":maxf(0.,feather),"surface_target":true})
	generator.layers=layers
	if not layers.any(func(layer: Dictionary): return layer.get("surface_target",false)): generator.foundation_edits=PackedFloat32Array()
	var errors:=generator.validate()
	if not errors.is_empty(): return errors[0]
	session.regenerate_terrain(terrain_id,{"generation":generator})
	return ""
static func remove_for_owners(session: KiwiEnvironmentSession,removed: Dictionary) -> void:
	# Called inside the existing deletion transaction, so terrain and hierarchy undo together.
	for item in session.document.components:
		if removed.has(item.id): continue
		var terrain:=session.environment().terrain(item.id)
		if terrain==null: continue
		var layers: Array[Dictionary]=[]
		var original_layers: Array=terrain.generation.layers if terrain.generation!=null else []
		for layer in original_layers:
			if layer.get("type","")=="Foundation" and (removed.has(str(layer.get("foundation_owner",""))) or removed.has(str(layer.get("world_road_owner","")))): continue
			layers.append(layer)
		var caves: Array[KiwiTerrainCave]=[]
		for cave: KiwiTerrainCave in terrain.caves:
			if cave.has_meta("world_road_owner") and removed.has(str(cave.get_meta("world_road_owner"))): continue
			caves.append(cave)
		if layers.size()==original_layers.size() and caves.size()==terrain.caves.size(): continue
		if terrain.generation!=null:
			terrain.generation=terrain.generation.duplicate(true) as KiwiTerrainGenerator; terrain.generation.layers=layers
			if not layers.any(func(layer: Dictionary): return layer.get("surface_target",false)): terrain.generation.foundation_edits=PackedFloat32Array()
		terrain.caves=caves; terrain.prepare(); terrain.prepare_water(); terrain.prepare_biomes(); terrain.prepare_volumes(); terrain.prepare_cave_biomes(); terrain.revision+=1; item.mesh=terrain.editable_mesh()
static func refresh_links(session: KiwiEnvironmentSession) -> void:
	for item in session.document.components:
		var terrain:=session.environment().terrain(item.id)
		if terrain==null or terrain.generation==null: continue
		var ground_pose:=session.document.world_transform(item)
		if absf(ground_pose.basis.determinant())<.000001: continue
		var layers: Array[Dictionary]=[]; var changed:=false
		for original in terrain.generation.layers:
			var layer: Dictionary=original.duplicate(true)
			if layer.get("type","")=="Foundation":
				var root:=session.document.component(str(layer.get("foundation_owner",""))); var source:=Buildings.source(root)
				if source!=null:
					layer.surface_target=true
					var relative:=ground_pose.affine_inverse()*session.document.world_transform(root); var floor: Dictionary=source.floors[0]; var height:=float(floor.get("elevation",0.))-float(source.slab_thickness); var plane:=Plane(relative*Vector3(0,height,0),relative*Vector3(1,height,0),relative*Vector3(0,height,1))
					if absf(plane.normal.y)<.2:
						layer.foundation_blocked=true; layer.enabled=false
					else:
						var polygon:=PackedVector2Array()
						for point in floor.get("footprint",source.footprint): var position: Vector3=relative*Vector3(point.x,height,point.y); polygon.append(Vector2(position.x,position.z))
						if layer.get("foundation_blocked",false): layer.erase("foundation_blocked"); layer.enabled=true
						layer.plane=plane; layer.polygon=polygon
			changed=changed or layer!=original; layers.append(layer)
		if not changed: continue
		terrain.generation=terrain.generation.duplicate(true) as KiwiTerrainGenerator; terrain.generation.layers=layers; terrain.generation.foundation_edits=terrain.edits.duplicate(); terrain.prepare(); terrain.prepare_water(); terrain.prepare_biomes(); terrain.prepare_volumes(); terrain.prepare_cave_biomes(); terrain.revision+=1; item.mesh=terrain.editable_mesh()
