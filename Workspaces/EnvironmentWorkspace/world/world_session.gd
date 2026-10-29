extends RefCounted
const Source=preload("res://Workspaces/EnvironmentWorkspace/world/world_source.gd")
const Roads=preload("res://Workspaces/EnvironmentWorkspace/world/road_network.gd")
static func source(item: KiwiModelComponent) -> Resource:
	var value: Variant=item.parameters.get("world_source") if item!=null else null
	return value if value is Resource and value.get_script()==Source else null
static func add(session: KiwiEnvironmentSession,position: Vector3=Vector3.ZERO,include_terrain: bool=false,adapt_starter_terrain: bool=false) -> KiwiModelComponent:
	var authored: Resource=Source.new(); authored.configure_regions(); var material:=StandardMaterial3D.new(); material.albedo_color=Color("393f44"); material.roughness=.95; authored.road_material=material
	preload("res://Workspaces/EnvironmentWorkspace/world/road_section.gd").prepare(authored)
	var root:=KiwiModelComponent.new(); root.id=authored.world_id; root.title="World"; root.parameters.world_source=authored; root.parameters.editor_proxy=true; root.mesh=KiwiModelPrimitives.box(Vector3(authored.dimensions.x,.05,authored.dimensions.y)); root.transform.origin=position
	session.action("Add procedural world",func():
		session.document.components.append(root); session.environment().component_settings[root.id]={"kind":"group"}
		if include_terrain:
			for item in session.document.components:
				var terrain:=session.environment().terrain(item.id)
				if terrain==null: continue
				authored.terrain_id=item.id; root.transform=session.document.world_transform(item)
				if adapt_starter_terrain and session.document.components.size()==2 and _starter_terrain(session,item,terrain):
					terrain.dimensions=authored.dimensions; terrain.resolution=129; terrain.prepare(); item.mesh=terrain.editable_mesh(); item.parent_id=root.id; item.transform=Transform3D.IDENTITY; item.title="World terrain"; authored.owned_terrain_id=item.id
				else: authored.dimensions=terrain.dimensions.max(Vector2.ONE*16.)
				break
			if authored.terrain_id.is_empty():
				var terrain:=KiwiEnvironmentTerrain.new(); terrain.dimensions=authored.dimensions; terrain.resolution=129; var ground:=session.environment().add_terrain(terrain); ground.parent_id=root.id; ground.title="World terrain"; authored.terrain_id=ground.id; authored.owned_terrain_id=ground.id
			authored.configure_regions(); root.mesh=KiwiModelPrimitives.box(Vector3(authored.dimensions.x,.05,authored.dimensions.y))
		session.selected=[root.id])
	return root
static func _starter_terrain(session: KiwiEnvironmentSession,item: KiwiModelComponent,terrain: KiwiEnvironmentTerrain) -> bool:
	return item.title=="Terrain" and item.parent_id.is_empty() and item.transform==Transform3D.IDENTITY and item.modifiers.is_empty() and session.environment().component_settings[item.id].size()==3 and terrain.dimensions==Vector2(32,32) and terrain.resolution==65 and terrain.seed==1 and terrain.amplitude==0. and terrain.base_height==0. and terrain.generation==null and terrain.erosion.is_empty() and terrain.caves.is_empty() and terrain.hydrology==null and terrain.biomes==null and terrain.edits.count(0.)==terrain.edits.size() and terrain.material_mask.count(0.)==terrain.material_mask.size()
static func development_snapshot(session: KiwiEnvironmentSession,id: String,desired: Resource) -> KiwiModelDocument:
	var root:=session.document.component(id); var current:=source(root)
	if current==null or current.development_signature()!=desired.development_signature() or not root.parameters.has("world_graph"): return null
	var document:=KiwiModelDocument.new(); document.components.append(root.copy_component())
	for item in session.document.components:
		var key:=str(item.parameters.get("world_key",""))
		if not item.parameters.get("world_generated",false) or str(item.parameters.get("world_owner",""))!=id or key.begins_with(":forest:") or key.begins_with(":props:"): continue
		document.components.append(item.copy_component())
	return document
static func update(session: KiwiEnvironmentSession,id: String,authored: Resource,label: String="Edit world",prepared: Dictionary={}) -> Dictionary:
	var root:=session.document.component(id)
	if root==null: return {"errors":PackedStringArray(["The world no longer exists."]),"warnings":PackedStringArray()}
	var desired: Resource=authored.copy(); desired.world_id=id; var current:=source(root)
	preserve_reservations(current,desired)
	if current!=null and current.signature()==desired.signature() and not prepared.has("terrain_result"): return {"errors":PackedStringArray(),"warnings":PackedStringArray()}
	if current!=null:
		if current.terrain_id!=desired.terrain_id and current.roads.any(func(road: Dictionary): return str(road.get("mode","Ground"))=="Tunnel"): return {"errors":PackedStringArray(["Change tunnel roads to Ground before switching their terrain reference."]),"warnings":PackedStringArray()}
		var conflict:=_locked_conflict(current,desired)
		if not conflict.is_empty(): return {"errors":PackedStringArray([conflict]),"warnings":PackedStringArray()}
	var output: Dictionary=prepared if prepared.get("signature")==desired.signature() else Roads.generate(desired)
	if output.get("document")==null or not output.errors.is_empty(): return output
	var terrain_plan: Dictionary=load("res://Workspaces/EnvironmentWorkspace/world/world_terrain.gd").tunnels_plan(session,id,desired)
	if not str(terrain_plan.get("error","")).is_empty(): return {"errors":PackedStringArray([str(terrain_plan.error)]),"warnings":PackedStringArray()}
	if terrain_plan.has("settings") and not output.has("terrain_result"): return {"errors":PackedStringArray(["Tunnel changes require the background world editor so terrain and road geometry can commit together."]),"warnings":PackedStringArray()}
	var parts: Array[KiwiModelComponent]=[]; var replacement: Dictionary={}; var removed: Dictionary={}; var poses: Dictionary={}; var existing: Dictionary={}; var mapping: Dictionary={}
	var generated_hierarchy: Dictionary=output.document.hierarchy_state(); var generated_root: Transform3D=generated_hierarchy.poses[id]; var generated_inverse:=generated_root.affine_inverse() if absf(generated_root.basis.determinant())>.0000000001 else Transform3D.IDENTITY
	for item in session.document.components:
		if item.parameters.get("world_generated",false) and str(item.parameters.get("world_owner",item.parent_id))==id: existing[str(item.parameters.get("world_key",item.id.trim_prefix(id)))]=item
	for part: KiwiModelComponent in output.document.components:
		if part.id==id: continue
		var stamp:=preload("res://Workspaces/EnvironmentWorkspace/world/world_mesh_stamp.gd"); part.parameters.world_mesh_key=stamp.value(part.mesh); part.parameters.world_mesh_version=2
		var old: KiwiModelComponent=existing.get(str(part.parameters.world_key))
		var generated_id:=part.id
		if old!=null and output.get("development_reused",false):
			if old.parameters.has("world_global_pose"): part.parameters.world_global_pose=old.parameters.world_global_pose
			else: part.parameters.erase("world_global_pose")
		else: part.parameters.world_global_pose=generated_inverse*(generated_hierarchy.poses[generated_id] as Transform3D)
		if old!=null:
			part.id=old.id
			var manual_pose: bool=old.parameters.get("world_manual_pose",false) or old.transform!=old.parameters.get("world_pose",Transform3D.IDENTITY)
			if manual_pose: part.transform=old.transform; part.parameters.world_manual_pose=true
			if old.parameters.get("world_manual_visible",false) or old.visible!=bool(old.parameters.get("world_generated_visible",true)): part.visible=old.visible; part.parameters.world_manual_visible=true
			part.locked=old.locked; part.title=old.title; part.modifiers=old.modifiers.duplicate(true)
			if old.structural!=old.parameters.get("world_structure",{}): part.structural=old.structural.duplicate(true)
			if old.surface_materials!=old.parameters.get("world_materials",old.surface_materials): part.surface_materials=old.surface_materials.duplicate()
			if not output.get("development_reused",false) and old.parameters.has("architecture_source") and old.parameters.has("world_architecture_source_key") and preload("res://Workspaces/EnvironmentWorkspace/architecture/building_session.gd")._source_key(old.parameters.architecture_source)!=int(old.parameters.world_architecture_source_key): return {"errors":PackedStringArray(["This building has local source edits. Keep it independent before regenerating its settlement."]),"warnings":PackedStringArray()}
			var version:=int(old.parameters.get("world_mesh_version",1)); var key: int=stamp.value(old.mesh); var shape_changed: bool=stamp.value(old.mesh,1)!=stamp.value(part.mesh,1)
			if shape_changed and (old.binding!=null or old.skin_mesh!=null or old.growth!=null): return {"errors":PackedStringArray(["A rigged or groomed building needs an explicit rebind before its source geometry changes."]),"warnings":PackedStringArray()}
			part.binding=old.binding.copy_binding() if old.binding!=null else null; part.skin=old.skin; part.skin_mesh=old.skin_mesh; part.skeleton_id=old.skeleton_id; part.growth=old.growth.copy_data() if old.growth!=null else null
			var manual_mesh: bool=stamp.value(old.mesh,version)!=int(old.parameters.get("world_mesh_key",stamp.value(old.mesh,version)))
			# Legacy baselines did not include UVs. Preserve differing UVs/material
			# slots when the generated topology has stayed exactly the same.
			if version<2 and not shape_changed and key!=int(part.parameters.world_mesh_key): manual_mesh=true
			if manual_mesh: part.mesh=old.mesh; part.parameters.world_mesh_key=old.parameters.get("world_mesh_key",key); part.parameters.world_mesh_version=version
			elif key==int(part.parameters.world_mesh_key): part.mesh=old.mesh
		parts.append(part); replacement[part.id]=true
		mapping[generated_id]=part.id
	mapping[id]=id
	for item in session.document.components:
		if not mapping.has(item.id): mapping[item.id]=item.id
	for part in parts:
		part.parent_id=mapping.get(part.parent_id,part.parent_id); preload("res://Workspaces/ModelWorkspace/model_reference_remap.gd").component(part,mapping)
		var expected_parent:=part.parent_id
		var old: KiwiModelComponent=existing.get(str(part.parameters.world_key))
		if old!=null and output.get("development_reused",false): expected_parent=str(old.parameters.get("world_parent",expected_parent))
		part.parameters.world_parent=expected_parent
		if old!=null and (old.parameters.get("world_manual_parent",false) or old.parent_id!=str(old.parameters.get("world_parent",expected_parent))):
			part.parent_id=old.parent_id; part.transform=old.transform; part.parameters.world_manual_parent=true; part.parameters.world_manual_pose=true
	var protected_sources: Dictionary={}
	for component in session.document.components:
		if component.growth!=null: protected_sources[component.growth.source_id]=true
	for old: KiwiModelComponent in existing.values():
		if replacement.has(old.id): continue
		var owner:=str(old.parameters.get("architecture_owner",""))
		if old.parameters.has("architecture_source"): owner=old.id
		if owner.is_empty() and not protected_sources.has(old.id): continue
		var stamp:=preload("res://Workspaces/EnvironmentWorkspace/world/world_mesh_stamp.gd"); var version:=int(old.parameters.get("world_mesh_version",1)); var edited: bool=old.transform!=old.parameters.get("world_pose",old.transform) or old.surface_materials!=old.parameters.get("world_materials",old.surface_materials) or old.structural!=old.parameters.get("world_structure",old.structural) or not old.modifiers.is_empty() or stamp.value(old.mesh,version)!=int(old.parameters.get("world_mesh_key",stamp.value(old.mesh,version))) or old.binding!=null or old.skin_mesh!=null or old.growth!=null or protected_sources.has(old.id)
		if old.parameters.has("architecture_source") and old.parameters.has("world_architecture_source_key"): edited=edited or preload("res://Workspaces/EnvironmentWorkspace/architecture/building_session.gd")._source_key(old.parameters.architecture_source)!=int(old.parameters.world_architecture_source_key)
		if edited: return {"errors":PackedStringArray(["This layout change would remove a customized or bound building component. Keep its building independent before regenerating."]),"warnings":PackedStringArray()}
	var generated_settings: Dictionary={}
	for generated_id in output.get("settings",{}): generated_settings[mapping.get(generated_id,generated_id)]=output.settings[generated_id]
	for item in session.document.components:
		if item.parameters.get("world_generated",false) and str(item.parameters.get("world_owner",item.parent_id))==id: removed[item.id]=true
	for part in parts:
		if removed.has(part.parent_id) and not replacement.has(part.parent_id):
			var old:=session.document.component(part.id)
			if old!=null: part.transform=session.document.world_transform(root).affine_inverse()*session.document.world_transform(old)
			part.parent_id=id; part.parameters.world_manual_parent=true; part.parameters.world_manual_pose=true
	var parents: Dictionary={}
	for item in session.document.components:
		if not removed.has(item.id): parents[item.id]=item.parent_id
	for part in parts: parents[part.id]=part.parent_id
	for identity in parents:
		var cursor:=str(identity); var visited: Dictionary={}
		while not cursor.is_empty():
			if visited.has(cursor) or not parents.has(cursor): return {"errors":PackedStringArray(["Regeneration would create an invalid parent hierarchy. Reparent the affected component before regenerating."]),"warnings":PackedStringArray()}
			visited[cursor]=true; cursor=str(parents[cursor])
	for item in session.document.components:
		if not removed.has(item.id) and removed.has(item.parent_id) and not replacement.has(item.parent_id): poses[item.id]=session.document.world_transform(item)
	session.action(label,func():
		root.parameters=output.document.component(id).parameters; root.parameters.editor_proxy=true; root.mesh=KiwiModelPrimitives.box(Vector3(desired.dimensions.x,.05,desired.dimensions.y)); var retained: Array[KiwiModelComponent]=[]
		if output.has("terrain_result"):
			var generated: Dictionary=output.terrain_result; session.environment().component_settings[generated.id].terrain=generated.terrain; session.document.component(generated.id).mesh=generated.mesh
		for item in session.document.components:
			if not removed.has(item.id): retained.append(item)
			elif not replacement.has(item.id): session.environment().component_settings.erase(item.id)
		for part in parts:
			var settings: Dictionary=generated_settings.get(part.id,{"kind":"building" if part.parameters.get("world_lazy_building",false) else "asset","collision":true})
			var old_rules:=session.environment().component_settings.get(part.id,{}).get("scatter") as KiwiEnvironmentScatter
			if old_rules!=null and settings.get("scatter") is KiwiEnvironmentScatter:
				var old: KiwiModelComponent=existing.get(str(part.parameters.world_key)); preload("res://Workspaces/EnvironmentWorkspace/world/world_forests.gd").preserve(old_rules,settings.scatter,old.parameters.get("world_scatter_defaults",{}))
			retained.append(part); session.environment().component_settings[part.id]=settings
		session.document.components=retained
		var inverse:=session.document.world_transform(root).affine_inverse()
		for child_id in poses:
			var child:=session.document.component(child_id); child.parent_id=id; child.transform=inverse*poses[child_id]
		session.selected.assign(session.selected.filter(func(identity: String): return session.document.component(identity)!=null)))
	return output
static func preserve_reservations(current: Resource,desired: Resource) -> void:
	if current==null: return
	for plot in current.plot_overrides:
		if not desired.plot_overrides.has(plot) and current.plot_overrides[plot].get("reserved",false): desired.plot_overrides[plot]=current.plot_overrides[plot].duplicate(true)
static func _locked_conflict(current: Resource,desired: Resource) -> String:
	for region: Dictionary in current.regions:
		if not region.get("locked",false): continue
		if current.terrain_dependency_key!=desired.terrain_dependency_key: return "Unlock "+str(region.name)+" before regenerating it against changed terrain or water."
		if current.connect_settlements!=desired.connect_settlements or current.connection_bridges!=desired.connection_bridges or current.connection_road_type!=desired.connection_road_type or current.connection_overrides!=desired.connection_overrides: return "Unlock "+str(region.name)+" before changing global settlement-connection rules."
		for area: Dictionary in current.occupied+desired.occupied:
			if current.occupied.has(area) and desired.occupied.has(area): continue
			var bounds: Rect2=region.bounds; var rectangle:=PackedVector2Array([bounds.position,Vector2(bounds.end.x,bounds.position.y),bounds.end,Vector2(bounds.position.x,bounds.end.y)])
			if not Geometry2D.intersect_polygons(rectangle,area.polygon).is_empty(): return "Unlock "+str(region.name)+" before refreshing changed existing-object footprints inside it."
		if current.dimensions!=desired.dimensions or current.region_size!=desired.region_size: return "Unlock "+str(region.name)+" before changing world or region bounds."
		for road: Dictionary in current.roads:
			var replacement: Dictionary={}
			for candidate: Dictionary in desired.roads:
				if candidate.id==road.id: replacement=candidate; break
			if replacement==road: continue
			if _touches(road.points,region.bounds): return "Unlock "+str(region.name)+" before editing or removing its roads."
		for road: Dictionary in desired.roads:
			if not current.roads.any(func(old: Dictionary): return old.id==road.id) and _touches(road.points,region.bounds): return "Unlock "+str(region.name)+" before adding roads through it."
		for settlement: Dictionary in current.settlements:
			var position: Vector3=settlement.center; var radius:=float(settlement.get("radius",48.)); var bounds:=Rect2(Vector2(position.x,position.z)-Vector2.ONE*radius,Vector2.ONE*radius*2.)
			if not bounds.intersects(region.bounds): continue
			var same: bool=desired.settlements.any(func(next: Dictionary): return next==settlement)
			if not same: return "Unlock "+str(region.name)+" before changing its settlement."
		for settlement: Dictionary in desired.settlements:
			if current.settlements.any(func(old: Dictionary): return old.id==settlement.id): continue
			var position: Vector3=settlement.center; var radius:=float(settlement.get("radius",48.))
			if Rect2(Vector2(position.x,position.z)-Vector2.ONE*radius,Vector2.ONE*radius*2.).intersects(region.bounds): return "Unlock "+str(region.name)+" before adding a settlement through it."
		for forest: Dictionary in current.forests:
			if (forest.bounds as Rect2).intersects(region.bounds) and not desired.forests.any(func(next: Dictionary): return next==forest): return "Unlock "+str(region.name)+" before changing its forests."
		for forest: Dictionary in desired.forests:
			if (forest.bounds as Rect2).intersects(region.bounds) and not current.forests.any(func(old: Dictionary): return old.id==forest.id): return "Unlock "+str(region.name)+" before adding a forest through it."
		for rule: Dictionary in current.prop_rules:
			if (rule.bounds as Rect2).intersects(region.bounds) and not desired.prop_rules.any(func(next: Dictionary): return next==rule): return "Unlock "+str(region.name)+" before changing its object placement."
		for rule: Dictionary in desired.prop_rules:
			if (rule.bounds as Rect2).intersects(region.bounds) and not current.prop_rules.any(func(old: Dictionary): return old.id==rule.id): return "Unlock "+str(region.name)+" before adding object placement through it."
	return ""
static func _touches(points: PackedVector3Array,bounds: Rect2) -> bool:
	var corners:=PackedVector2Array([bounds.position,Vector2(bounds.end.x,bounds.position.y),bounds.end,Vector2(bounds.position.x,bounds.end.y)])
	for index in points.size():
		var point:=Vector2(points[index].x,points[index].z)
		if bounds.has_point(point): return true
		if index==0: continue
		for border in 4:
			if Geometry2D.segment_intersects_segment(Vector2(points[index-1].x,points[index-1].z),point,corners[border],corners[(border+1)%4])!=null: return true
	return false
static func add_road(authored: Resource,start: Vector3,end: Vector3) -> Resource:
	var next: Resource=authored.copy(); var id:=ActorData.new_id(); var from:=id+":a"; var to:=id+":b"; next.nodes[from]=start; next.nodes[to]=end; var road:=preload("res://Workspaces/EnvironmentWorkspace/world/road_section.gd").defaults(); road.merge({"id":id,"name":"Road "+str(next.roads.size()+1),"from":from,"to":to,"points":PackedVector3Array([start,end]),"enabled":true,"locked":false,"max_grade":.12},true); next.roads.append(road)
	road.follow_terrain=true
	# Reuse actual endpoint identity when extending or connecting roads, including
	# collinear roads for which segment-intersection tests have no unique crossing.
	for node in authored.nodes:
		if (authored.nodes[node] as Vector3).distance_to(start)<.001: next.nodes.erase(from); road.from=node; road.points[0]=authored.nodes[node]; break
	for node in authored.nodes:
		if (authored.nodes[node] as Vector3).distance_to(end)<.001: next.nodes.erase(to); road.to=node; road.points[-1]=authored.nodes[node]; break
	return next
static func keep_independent(session: KiwiEnvironmentSession,id: String) -> String:
	var error:=independence_error(session,id)
	if not error.is_empty(): return error
	session.action("Keep generated building independent",func(): detach_building(session,id))
	return ""
static func independence_error(session: KiwiEnvironmentSession,id: String) -> String:
	var building:=session.document.component(id)
	if building==null: return "Select a generated building first."
	var world:=session.document.component(str(building.parameters.get("world_owner",""))); var authored:=source(world); var plot:=str(building.parameters.get("world_plot",""))
	if authored==null or plot.is_empty(): return "This building is already independent."
	return ""
static func detach_building(session: KiwiEnvironmentSession,id: String) -> void:
	var building:=session.document.component(id); var world:=session.document.component(str(building.parameters.get("world_owner",""))); var authored:=source(world); var plot:=str(building.parameters.get("world_plot",""))
	if authored==null or plot.is_empty(): return
	var next: Resource=authored.copy(); next.plot_overrides[plot]={"reserved":true}
	world.parameters.world_source=next
	for item in session.document.components:
		if item.id!=id and not session.document.is_descendant(item.id,id): continue
		for key in ["world_generated","world_owner","world_key","world_mesh_key","world_mesh_version","world_pose","world_global_pose","world_parent","world_manual_parent","world_structure","world_materials","world_architecture_source_key","world_generated_visible","world_manual_pose","world_lazy_building"]: item.parameters.erase(key)

