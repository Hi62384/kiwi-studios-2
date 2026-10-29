extends RefCounted
## Material/distance changes reuse installed CPU topology and placement sources.
const Worlds=preload("res://Workspaces/EnvironmentWorkspace/world/world_session.gd")
const Sections=preload("res://Workspaces/EnvironmentWorkspace/world/road_section.gd")
const Forests=preload("res://Workspaces/EnvironmentWorkspace/world/world_forests.gd")
static func snapshot(session: KiwiEnvironmentSession,id: String,desired: Resource) -> Dictionary:
	var original:=session.document.component(id); var current:=Worlds.source(original)
	if current==null or not original.parameters.has("world_graph") or current.geometry_signature()!=desired.geometry_signature(): return {}
	var source_errors: PackedStringArray=desired.validate()
	if not source_errors.is_empty(): return {"document":null,"errors":source_errors,"warnings":PackedStringArray(),"signature":desired.signature()}
	var document:=KiwiModelDocument.new(); var root:=original.copy_component(); root.parameters.world_source=desired; document.components.append(root); var settings: Dictionary={}; var edges: Dictionary={}
	for edge: Dictionary in original.parameters.world_graph.edges: edges[str(edge.id)]=edge
	for item in session.document.components:
		if not item.parameters.get("world_generated",false) or str(item.parameters.get("world_owner",""))!=id: continue
		var part:=item.copy_component(); document.components.append(part); var metadata: Dictionary=session.environment().component_settings.get(item.id,{"kind":"asset","collision":true}).duplicate(true); settings[part.id]=metadata; var material: Material; var replace:=false
		if item.parameters.has("world_road"):
			var edge: Dictionary=edges.get(str(item.parameters.world_road),{})
			if not edge.is_empty(): material=Sections.material(desired,edge); replace=true
		else:
			var parent:=session.document.component(item.parent_id); var key:=str(item.parameters.get("world_key","")); var detail:=str(item.parameters.get("road_detail",""))
			if not detail.is_empty():
				var edge: Dictionary=edges.get(str(parent.parameters.get("world_road","")),{}) if parent!=null else {}; material=Sections.material(desired,edge,detail); replace=true
			elif key.begins_with(":junction:"): material=desired.road_material; replace=true
			elif key.begins_with(":portals:") or (parent!=null and parent.parameters.has("world_road") and (key.ends_with(":railings") or key.ends_with(":supports"))): material=desired.shoulder_material if desired.shoulder_material!=null else desired.road_material; replace=true
		if replace:
			part.surface_materials.assign([material]); part.parameters.world_materials=part.surface_materials.duplicate()
		var scatter:=metadata.get("scatter") as KiwiEnvironmentScatter
		if scatter!=null:
			var rules:=scatter.duplicate(true) as KiwiEnvironmentScatter; metadata.scatter=rules; var hash_value:=preload("res://Workspaces/EnvironmentWorkspace/terrain/terrain_data_hash.gd"); var defaults: Dictionary=part.parameters.get("world_scatter_defaults",{}).duplicate(true)
			if defaults.has("render_distance") and int(defaults.render_distance)==hash_value.value(scatter.render_distance):
				var cap:=300.
				if part.parameters.has("world_forest"):
					var key:=str(part.parameters.get("world_key","")); var tail:=key.get_slice(":",key.get_slice_count(":")-1); cap=[500.,350.,200.,120.][clampi(int(tail),0,3)]
				rules.render_distance=minf(float(desired.render_distance),cap) if desired.render_distance>0. else 0.; defaults.render_distance=hash_value.value(rules.render_distance); part.parameters.world_scatter_defaults=defaults
	var included: Dictionary={}
	for item in document.components: included[item.id]=true
	root.parent_id=""
	for part in document.components:
		# The update transaction restores manual parents from the live document.
		# External ancestors are intentionally absent from this source snapshot.
		if not part.parent_id.is_empty() and not included.has(part.parent_id): part.parent_id=id
	return {"document":document,"settings":settings,"errors":document.validate(),"warnings":PackedStringArray(),"development_reused":true,"visual_only":true,"signature":desired.signature()}
