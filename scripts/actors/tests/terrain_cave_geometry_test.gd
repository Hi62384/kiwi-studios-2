extends "res://scripts/actors/tests/surface_growth_test.gd"
const Mesher=preload("res://Workspaces/EnvironmentWorkspace/terrain/terrain_volume_mesher.gd")
func run() -> void:
	var terrain:=KiwiEnvironmentTerrain.new(); terrain.resolution=17; terrain.dimensions=Vector2(16,16); var cave:=KiwiTerrainCave.new(); cave.radius=1.5; cave.radius_variation=0.; cave.roughness=0.; cave.junction_smoothing=.2; cave.paths=[PackedVector3Array([Vector3(0,1,-6),Vector3(0,-3,0)])]; cave.chambers=PackedVector4Array([Vector4(0,-3,0,2.)]); cave.prepare()
	check(cave.validate().is_empty() and cave.distance(Vector3(0,-3,0))<0. and cave.distance(Vector3(5,-3,0))>0.,"Editable tunnel and chamber define a real connected 3D void")
	var mesher:=Mesher.new(); var result:=mesher.build(terrain,Vector2i.ZERO,[cave],.5,100000)
	check(str(result.get("error","")).is_empty() and result.indices.size()>0 and result.vertices.size()>0,"Terrain and cave void extract into actual triangle geometry")
	var mesh:=native(result); var triangles:=mesh.generate_triangle_mesh(); var floor_hit:=triangles.intersect_ray(Vector3(0,-3,0),Vector3.DOWN); var roof_hit:=triangles.intersect_ray(Vector3(0,-3,0),Vector3.UP); var wall_hit:=triangles.intersect_ray(Vector3(0,-3,0),Vector3.RIGHT)
	check(not floor_hit.is_empty() and absf(floor_hit.position.y+5.)<.2,"Camera rays inside the chamber hit its actual floor")
	check(not roof_hit.is_empty() and absf(roof_hit.position.y+1.)<.2,"Camera rays inside the chamber hit its actual ceiling")
	check(not wall_hit.is_empty() and absf(wall_hit.position.x-2.)<.2,"Camera rays inside the chamber hit its actual walls")
	var entrance:=triangles.intersect_ray(Vector3(0,4,-6),Vector3.DOWN)
	check(not entrance.is_empty() and entrance.position.y<-.3,"The tunnel cuts a real opening through the surface instead of leaving an intact ground plane")
	var consistent:=true
	for index in range(0,result.indices.size(),3):
		var a: int=result.indices[index]; var b: int=result.indices[index+1]; var c: int=result.indices[index+2]; consistent=consistent and (result.vertices[b]-result.vertices[a]).cross(result.vertices[c]-result.vertices[a]).dot(result.normals[a]+result.normals[b]+result.normals[c])<=.00001
	check(consistent,"Extracted cave triangles follow Godot's clockwise orientation toward the air space")
	var repeated:=Mesher.new().build(terrain,Vector2i.ZERO,[cave],.5,100000); check(result.vertices==repeated.vertices and result.indices==repeated.indices,"Cave geometry is deterministic from identical saved field settings")
	var limited:=Mesher.new().build(terrain,Vector2i.ZERO,[cave],.5,100); check(not str(limited.get("error","")).is_empty(),"Volumetric meshing rejects work above its real voxel budget")
	check(Mesher.new().build(terrain,Vector2i.ZERO,[cave],.5,100000,func(): return true).get("cancelled",false),"Volumetric generation supports cancellation before committing partial geometry")
	var network:=KiwiTerrainCave.network(Vector3(0,0,-8),5.,12.,3,73); var other:=KiwiTerrainCave.network(Vector3(0,0,-8),5.,12.,3,73); check(network.paths==other.paths and network.chambers==other.chambers,"Connected procedural cave networks retain deterministic branch and chamber structure")
	var branches_connected:=true
	for index in range(1,network.paths.size()): branches_connected=branches_connected and network.paths[0].has(network.paths[index][0])
	check(branches_connected,"Every generated branch starts on an existing tunnel junction")
	print("TERRAIN CAVE vertices=",result.vertices.size()," triangles=",result.indices.size()/3," cells=",result.cells," build_ms=",result.milliseconds); print("TERRAIN CAVE GEOMETRY: %d checks, %d failures"%[checks,failures]); quit(failures)
func native(data: Dictionary) -> ArrayMesh:
	var arrays:=[]; arrays.resize(Mesh.ARRAY_MAX); arrays[Mesh.ARRAY_VERTEX]=data.vertices; arrays[Mesh.ARRAY_NORMAL]=data.normals; arrays[Mesh.ARRAY_TEX_UV]=data.uv; arrays[Mesh.ARRAY_INDEX]=data.indices; var mesh:=ArrayMesh.new(); mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays); return mesh
