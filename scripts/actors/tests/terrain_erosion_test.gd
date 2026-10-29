extends "res://scripts/actors/tests/surface_growth_test.gd"
func run() -> void:
	var n:=25; var source:=PackedFloat32Array(); source.resize(n*n)
	for z in n:
		for x in n: source[x+z*n]=x*.3+sin(z*.5)*.1
	var original:=source.duplicate(); var hydraulic:=KiwiTerrainErosion.new(); hydraulic.iterations=30; var result:=hydraulic.apply(source,n,Vector2(24,24)); var repeated:=hydraulic.apply(source,n,Vector2(24,24))
	check(source==original and result.heights!=source,"Hydraulic erosion changes actual height data while preserving its input source")
	check(result.heights==repeated.heights and result.sediment==repeated.sediment,"Hydraulic rainfall, transport and sediment are deterministic")
	check(absf(total(result.heights)+total(result.sediment)-total(source))<.02,"Hydraulic erosion conserves ground plus suspended sediment mass")
	var direction:=Vector2.ZERO
	for vector: Vector2 in result.flow: direction+=vector
	check(direction.x<-.1 and total(result.accumulation)>0.,"Hydraulic flow travels downhill and records a usable drainage field")
	check(total(result.erosion)>0. and total(result.deposition)>0.,"Hydraulic transport records both sediment pickup and deposition")
	var finite:=true
	for field in ["heights","water","sediment","erosion","deposition"]:
		for value in result[field]: finite=finite and is_finite(value) and (field=="heights" or value>=-.00001)
	check(finite,"Hydraulic fields remain finite with nonnegative water and sediment")
	var thermal:=KiwiTerrainErosion.new(); thermal.mode=1; thermal.iterations=50; thermal.strength=1.; thermal.mobility=1.; var peak:=PackedFloat32Array(); peak.resize(17*17); peak[8+8*17]=12.; var settled:=thermal.apply(peak,17,Vector2(16,16))
	check(settled.heights[8+8*17]<8. and total(settled.deposition)>1.,"Thermal erosion relaxes steep peaks and deposits material below them")
	check(absf(total(settled.heights)-total(peak))<.001,"Thermal movement conserves physical terrain material")
	hydraulic.mask={"center":Vector2.ZERO,"radius":5.,"falloff":.3}; var masked:=hydraulic.apply(source,n,Vector2(24,24)); var protected:=true
	for z in n:
		for x in n:
			if Vector2(x-12,z-12).length()>5.: protected=protected and masked.heights[x+z*n]==source[x+z*n]
	check(protected and masked.heights!=source,"Regional erosion changes its masked region and protects outside terrain")
	var canceled:=hydraulic.apply(source,n,Vector2(24,24),func(): return true); check(canceled.cancelled and canceled.heights==source,"Canceling erosion returns the unchanged source rather than partial committed geometry")
	var terrain:=KiwiEnvironmentTerrain.new(); terrain.resolution=33; terrain.amplitude=15.; terrain.generation=KiwiTerrainGenerator.preset(2); terrain.prepare(); var before:=terrain._base.duplicate(); thermal.iterations=10; terrain.erosion=[thermal]; terrain.prepare()
	check(terrain._base!=before and terrain.derived_fields.has(thermal.operation_id),"Terrain generation evaluates ordered erosion operations into its native geometry and derived fields")
	terrain.erosion.clear(); terrain.prepare(); check(terrain._base==before,"Removing erosion restores the original procedural source non-destructively")
	print("TERRAIN EROSION hydraulic_25x25_30_steps_ms=",result.milliseconds," thermal_17x17_50_steps_ms=",settled.milliseconds," mass_error=",total(result.heights)+total(result.sediment)-total(source)); print("TERRAIN EROSION: %d checks, %d failures"%[checks,failures]); quit(failures)
func total(values: PackedFloat32Array) -> float:
	var sum:=0.
	for value in values: sum+=value
	return sum
