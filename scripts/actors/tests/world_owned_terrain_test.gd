extends "res://scripts/actors/tests/surface_growth_test.gd"
const Worlds=preload("res://Workspaces/EnvironmentWorkspace/world/world_session.gd")
func run() -> void:
	var session:=KiwiEnvironmentSession.new(); var root_component:=Worlds.add(session,Vector3(20,4,30),true); var id:=root_component.id; var source:=Worlds.source(root_component); var terrain_id: String=source.terrain_id; var ground:=session.document.component(terrain_id)
	check(session.document.components.size()==2 and ground!=null and source.owned_terrain_id==terrain_id and ground.parent_id==id,"New user worlds create and own one native terrain within the world hierarchy")
	check(session.environment().terrain(terrain_id).dimensions==source.dimensions and session.document.world_transform(ground).origin==Vector3(20,4,30),"World terrain dimensions and coordinates match the world source")
	check(session.environment().component_kind(id)=="group" and root_component.mesh.bounds().size.x==256.,"World bounds provide an editor framing proxy without becoming a rendered asset")
	session.undo(); var empty:=session.document.components.is_empty(); session.redo(); check(empty and session.document.components.size()==2 and session.environment().validate().is_empty(),"World and initial terrain creation undo/redo as one atomic action")
	session.selected=[id]; session.duplicate_selected(); var copy:=session.primary(); var authored:=Worlds.source(copy)
	check(authored.owned_terrain_id!=terrain_id and authored.terrain_id==authored.owned_terrain_id and session.document.component(authored.owned_terrain_id).parent_id==copy.id,"Duplicating an owned world remaps the terrain ownership and hierarchy")
	session.selected=[copy.id]; session.delete_selected(); check(session.document.component(authored.owned_terrain_id)==null and session.document.component(terrain_id)!=null,"Deleting one world removes only its own terrain and preserves independent worlds")
	var other:=KiwiEnvironmentSession.new(); var existing:=other.add_terrain(); var linked:=Worlds.add(other,Vector3.ZERO,true); var linked_source:=Worlds.source(linked)
	check(linked_source.terrain_id==existing.id and linked_source.owned_terrain_id.is_empty() and other.document.components.size()==2,"Creating a world reuses existing native terrain without duplicating or claiming ownership of it")
	other.selected=[linked.id]; other.delete_selected(); check(other.document.component(existing.id)!=null,"Deleting a world preserves externally linked terrain")
	var starter:=KiwiEnvironmentSession.new(); var default_ground:=starter.add_terrain(); var upgraded:=Worlds.add(starter,Vector3.ZERO,true,true); var upgraded_id:=upgraded.id
	check(Worlds.source(upgraded).owned_terrain_id==default_ground.id and starter.environment().terrain(default_ground.id).dimensions==Vector2(256,256) and starter.document.component(default_ground.id).parent_id==upgraded_id,"The normal new-environment starter ground upgrades to usable world size without creating overlapping terrain")
	starter.undo(); check(starter.document.component(upgraded_id)==null and starter.document.component(default_ground.id).parent_id.is_empty() and starter.environment().terrain(default_ground.id).dimensions==Vector2(32,32),"Undoing starter-ground adoption restores the original terrain dimensions and ownership")
	print("WORLD OWNED TERRAIN: %d checks, %d failures"%[checks,failures]); quit(failures)
