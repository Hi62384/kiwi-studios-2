extends "res://scripts/actors/tests/surface_growth_test.gd"
const Source=preload("res://Workspaces/EnvironmentWorkspace/architecture/building_source.gd")
const Styles=preload("res://Workspaces/EnvironmentWorkspace/architecture/building_styles.gd")
const Builder=preload("res://Workspaces/EnvironmentWorkspace/architecture/building_geometry.gd")
const Layout=preload("res://Workspaces/EnvironmentWorkspace/architecture/building_layout.gd")
const Buildings=preload("res://Workspaces/EnvironmentWorkspace/architecture/building_session.gd")
func run() -> void:
	var source: Resource=Layout.generate(Source.rectangular(8,12),5).source; var fingerprints: Dictionary={}
	for name: String in Styles.PRESETS:
		var styled: Resource=Styles.apply(source,name); var generated:=Builder.generate(styled); var valid: bool=generated.errors.is_empty(); var detail_faces:=0; var shape: Array=[]
		if valid:
			for component: KiwiModelComponent in generated.document.components:
				if component.mesh!=null: shape.append(hash([component.mesh.vertices,component.mesh.faces])); valid=valid and component.mesh.validate().is_empty()
				if component.parameters.get("architecture_type","")=="facade": detail_faces+=component.mesh.faces.size()
		check(valid and styled.floors[0].rooms==source.floors[0].rooms,"%s generates valid geometry while preserving room regions"%name)
		check(styled.facade_detail==0 or detail_faces>0,"%s creates real editable facade details"%name)
		fingerprints[hash(shape)]=true
	check(fingerprints.size()>=9,"Styles change actual architecture geometry rather than only material colors")
	check(source.style=="Custom" and source.facade_detail==0,"Applying presets leaves the original source snapshot untouched")
	var medieval: Resource=Styles.apply(source,"Medieval"); var wall: Dictionary=medieval.floors[0].walls[0]; var facade:=Styles.facade(medieval,medieval.floors[0],wall)
	check(facade.bounds().end.z<0.,"Exterior facade geometry stays outside the footprint instead of covering interior rooms")
	var session:=KiwiModelSession.new(); var root:=Buildings.add(session); var original: Resource=Buildings.source(root); Buildings.update(session,root.id,Styles.apply(original,"Fantasy"),"Apply style"); session.undo()
	check(Buildings.source(session.document.component(root.id)).style=="Custom","Style application undoes through normal source history")
	print("ARCHITECTURE STYLES: %d checks, %d failures"%[checks,failures]); quit(failures)
