extends "res://scripts/actors/tests/surface_growth_test.gd"
const Session=preload("res://Workspaces/EnvironmentWorkspace/environment_session.gd")
func run() -> void:
	var session:=Session.new(); var item:=session.add_terrain(); var terrain:=session.environment().terrain(item.id); var id:=item.id
	check(session.environment().validate().is_empty() and item.mesh.vertices.size()==65*65,"Environment document creates real terrain geometry with a valid component identity")
	terrain.prepare(); var flat:=terrain.sample(Vector2.ZERO); check(absf(flat.height)<.00001 and flat.normal.y>.99,"Flat terrain has correct height and upward normals")
	session.regenerate_terrain(id,{"seed":31,"amplitude":4.}); terrain=session.environment().terrain(id); var generated:=terrain.editable_mesh().vertices; session.regenerate_terrain(id,{"seed":32}); terrain=session.environment().terrain(id); var other:=terrain.editable_mesh().vertices; session.regenerate_terrain(id,{"seed":31}); terrain=session.environment().terrain(id)
	check(generated!=other and generated==terrain.editable_mesh().vertices,"Terrain seeds produce deterministic physical height geometry")
	var old: float=terrain.sample(Vector2.ZERO).height; session.begin_terrain(id); session.sculpt(Vector2.ZERO,3.,2.,1.,0); session.sculpt(Vector2.ZERO,3.,1.,1.,0); session.finish_terrain(); var raised: float=terrain.sample(Vector2.ZERO).height
	check(raised>old+2.9,"Terrain brush changes actual height samples and editable vertices live")
	session.undo(); terrain=session.environment().terrain(id); check(absf(terrain.sample(Vector2.ZERO).height-old)<.00001,"An entire multi-dab terrain stroke undoes as one sparse transaction")
	session.redo(); terrain=session.environment().terrain(id); check(absf(terrain.sample(Vector2.ZERO).height-raised)<.00001,"Sparse terrain history redoes exact authored heights")
	session.begin_terrain(id); session.sculpt(Vector2.ZERO,2.,1.,1.,1); session.finish_terrain(true); check(absf(terrain.sample(Vector2.ZERO).height-raised)<.00001,"Canceling a terrain stroke restores its original samples")
	var a:=terrain.chunk_mesh(Vector2i(0,0)); var b:=terrain.chunk_mesh(Vector2i(1,0)); var av: PackedVector3Array=a.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]; var bv: PackedVector3Array=b.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]; var seams:=true
	for z in 33: seams=seams and av[32+z*33]==bv[z*33]
	check(seams,"Terrain chunk boundaries share identical edge positions")
	terrain.dirty_chunks.clear(); session.begin_terrain(id); session.sculpt(Vector2(-10,-10),1.,.1,1.,0); session.finish_terrain(); check(terrain.dirty_chunks.size()<4,"A local sculpt marks only intersecting terrain chunks")
	var edit:=terrain.edits.duplicate(); session.regenerate_terrain(id,{"amplitude":6.}); terrain=session.environment().terrain(id); check(terrain.edits==edit,"Regenerating procedural terrain preserves separate authored sculpt edits")
	var group:=session.add_group("Forest"); session.reparent_components([id],group.id); check(session.environment().component(id).parent_id==group.id,"Environment components reuse Kiwi parenting and world transforms")
	var path:="user://environment-document.tres"; check(ResourceSaver.save(session.environment(),path)==OK,"Complete editable environment saves as a project resource")
	var loaded:=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE) as KiwiEnvironmentDocument
	check(loaded!=null and loaded.environment_id==session.environment().environment_id and loaded.terrain(id).edits==terrain.edits and loaded.component(id).parent_id==group.id,"Terrain data, stable identities and hierarchy survive save/reopen")
	var snapshot:=session.environment().snapshot() as KiwiEnvironmentDocument; var copied:=snapshot.terrain(id).edits; copied[0]=123.; snapshot.terrain(id).edits=copied
	check(snapshot.terrain(id).edits[0]==123. and session.environment().terrain(id).edits[0]!=123.,"Undo snapshots isolate owned terrain arrays from live editing")
	var authored:=terrain.edits.duplicate(); session.regenerate_terrain(id,{},true); terrain=session.environment().terrain(id)
	check(terrain.edits.size()==terrain.resolution*terrain.resolution and Array(terrain.edits).max()==0.,"Reset sculpt edits rebuilds valid zeroed sample storage even when noise parameters are unchanged")
	session.undo(); check(session.environment().terrain(id).edits==authored,"Reset sculpt edits restores the previous authored samples through undo")
	DirAccess.remove_absolute(path); session._undo.clear(); session._redo.clear(); print("ENVIRONMENT DOCUMENT: %d checks, %d failures"%[checks,failures]); quit(failures)
