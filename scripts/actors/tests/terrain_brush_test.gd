extends "res://scripts/actors/tests/surface_growth_test.gd"
func run() -> void:
	var stamp:=Image.create(8,8,false,Image.FORMAT_RGBA8); stamp.fill(Color.WHITE)
	for mode in 13:
		var terrain:=KiwiEnvironmentTerrain.new(); terrain.resolution=33; terrain.dimensions=Vector2(16,16); terrain.prepare(); var middle:=16+16*33; terrain.apply_samples({middle:2.3}); var before:=terrain.edits.duplicate(); var result:=terrain.sculpt(Vector2.ZERO,3.,.8,1.,mode,.75,{"target":1.,"terrace_step":.5,"stamp":stamp})
		check(not result.after.is_empty() and terrain.edits!=before,"%s changes real terrain samples"%KiwiEnvironmentViewport.BRUSH_TOOLS[mode])
		var changed:=terrain.edits.duplicate(); terrain.apply_samples(result.before); check(terrain.edits==before,"%s has exact sparse undo data"%KiwiEnvironmentViewport.BRUSH_TOOLS[mode]); terrain.apply_samples(result.after); check(terrain.edits==changed,"%s has exact sparse redo data"%KiwiEnvironmentViewport.BRUSH_TOOLS[mode])
		if mode==11: check(absf(total(before)-total(terrain.edits))<.00001,"Local erode brush moves material downhill without deleting terrain mass")
	var circle:=KiwiEnvironmentTerrain.new(); circle.resolution=33; circle.dimensions=Vector2(16,16); circle.prepare(); var square:=circle.duplicate(true) as KiwiEnvironmentTerrain; circle.sculpt(Vector2.ZERO,2.,1.,.01,0); square.sculpt(Vector2.ZERO,2.,1.,.01,0,0.,{"square":true})
	check(square.sample(Vector2(1.5,1.5)).height>0. and circle.sample(Vector2(1.5,1.5)).height==0.,"Square brush uses its square footprint rather than the circular radius")
	print("TERRAIN BRUSH: %d checks, %d failures"%[checks,failures]); quit(failures)
func total(values: PackedFloat32Array) -> float:
	var result:=0.
	for value in values: result+=value
	return result
