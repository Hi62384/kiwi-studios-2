extends RefCounted
## Saved distant geometry follows actual floor outlines and the authored roof.
static func mesh(source: Resource) -> KiwiModelMesh:
	var result:=KiwiModelMesh.new()
	for floor: Dictionary in source.floors:
		var polygon: PackedVector2Array=floor.get("footprint",source.footprint); var height:=float(floor.get("height",3.)); var body:=KiwiModelPrimitives.prism(polygon,height); result.append_mesh(body,Transform3D(Basis.IDENTITY,Vector3.UP*(float(floor.get("elevation",0.))+height*.5)))
	if source.foundation_depth>0.: result.append_mesh(KiwiModelPrimitives.prism(source.footprint,float(source.foundation_depth)),Transform3D(Basis.IDENTITY,Vector3.DOWN*float(source.foundation_depth)*.5))
	var warnings:=PackedStringArray(); var roof:=preload("res://Workspaces/EnvironmentWorkspace/architecture/building_geometry.gd").roof_mesh(source,warnings)
	if roof!=null and not source.floors.is_empty():
		var last: Dictionary=source.floors[-1]; result.append_mesh(roof,Transform3D(Basis.IDENTITY,Vector3.UP*(float(last.elevation)+float(last.get("height",3.)))),2)
	return result
