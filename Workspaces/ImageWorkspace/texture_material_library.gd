extends RefCounted
const CATEGORIES={
	"Metal":["Brushed Steel","Stainless Steel","Polished Metal","Rough Iron","Cast Iron","Aluminum","Copper","Bronze","Gold","Silver","Galvanized Steel","Rusted Metal","Scratched Metal","Hammered Metal","Diamond Plate Metal"],
	"Wood":["Oak","Pine","Walnut","Mahogany","Birch","Bamboo","Plywood","Tree Bark","Weathered Wood","Painted Wood","Wood Planks","Knotty Wood","Rough Timber","Dark Aged Wood"],
	"Fabric":["Cotton","Denim","Linen","Wool","Silk","Velvet","Leather","Suede","Burlap","Knitted Fabric","Woven Fabric","Canvas Fabric","Corduroy","Fleece","Mesh Fabric"],
	"Stone":["Granite","Marble","Limestone","Sandstone","Slate","Concrete","Rough Concrete","Brick","Stone Bricks","Cobblestone","Asphalt","Cracked Stone","Polished Stone","Pebbled Stone","Ceramic Tiles"],
	"Ground":["Grass","Moss","Dirt","Mud","Cracked Mud","Sand","Gravel","Pebbles","Snow","Ice","Rock Ground","Forest Floor","Dry Earth","Wet Soil","Fallen Leaves","Organic Debris"],
	"Organic":["Skin Pores","Reptile Scales","Fish Scales","Fur","Feather Pattern","Leaf Surface","Leaf Veins","Tree Bark","Bone","Shell","Organic Membrane"],
	"Weathering":["Rust","Dust","Dirt Buildup","Scratches","Cracks","Peeling Paint","Paint Chips","Water Stains","Oil Stains","Grime","Corrosion","Surface Erosion","Burn Marks","Mold","Surface Pitting"],
	"Illustration":["Comic Halftone","Dots","Stippling","Crosshatching","Hatching","Pencil Grain","Ink Grain","Scribble Texture","Hand-Drawn Shading","Paper Grain","Cartoon Speckles","Watercolor Granulation","Chalk Texture","Marker Texture"],
	"Geometry":["Stripes","Checkerboard","Dots","Grid","Hexagons","Triangles","Diamonds","Waves","Zigzags","Repeating Circles","Brick Pattern","Tiles","Honeycomb","Cross Pattern"],
	"Noise":["White Noise","Value Noise","Smooth Noise","Perlin Noise","Simplex Noise","Cellular Noise","Voronoi Noise","Fractal Brownian Motion","Ridged Noise","Billow Noise","Turbulence","Domain Warped Noise","Worley Distance Noise","Multiscale Grain"],
}
const STRUCTURE={
	"Metal":["density","roughness","distortion","detail"],"Wood":["density","knots","distortion","detail"],
	"Fabric":["density","thickness","distortion","detail"],"Stone":["density","thickness","distortion","detail"],
	"Ground":["density","roughness","distortion","detail"],"Organic":["density","thickness","distortion","detail"],
	"Weathering":["density","thickness","distortion","detail"],"Illustration":["density","thickness","distortion","detail"],
	"Geometry":["density","thickness","distortion","detail"],"Noise":["frequency","octaves","gain","lacunarity"],
}
static func slug(value: String) -> String: return value.to_lower().replace(" ","_")
static func controls(id: String) -> Array:
	var group:=category(id); var index:=variant(id)
	if group=="Noise" and index==0: return ["density"]
	if group=="Geometry" and index in [0,1,5,6,7,8]: return ["density","distortion"]
	if group=="Stone" and index in [0,2,3,4,5,6,10,12]: return ["density","distortion","detail"]
	return STRUCTURE.get(group,[])

static func control_label(id: String,key: String) -> String:
	var common:={"density":"Detail density","thickness":"Feature width","roughness":"Surface roughness","distortion":"Structure distortion","detail":"Fine detail","knots":"Knot density","frequency":"Frequency","octaves":"Octaves","gain":"Noise gain","lacunarity":"Lacunarity"}
	var labels:={"Wood":{"density":"Grain frequency","knots":"Knots","distortion":"Grain warp","detail":"Fiber detail"},"Fabric":{"density":"Weave density","thickness":"Thread thickness","distortion":"Thread irregularity","detail":"Fiber grain"},"Metal":{"density":"Brush density","detail":"Micro-scratches","roughness":"Surface roughness"}}
	return labels.get(category(id),{}).get(key,common.get(key,key.capitalize()))
static func ids() -> Array[String]:
	var result: Array[String]=[]
	for category in CATEGORIES:
		for name in CATEGORIES[category]: result.append(category.to_lower()+"/"+slug(name))
	return result
static func category(id: String) -> String: return id.get_slice("/",0).capitalize()
static func variant(id: String) -> int:
	var group:=category(id)
	if not CATEGORIES.has(group): return 0
	for i in CATEGORIES[group].size():
		if slug(CATEGORIES[group][i])==id.get_slice("/",1): return i
	return 0
static func create(id: String) -> KiwiTextureMaterial:
	var result:=KiwiTextureMaterial.new(); result.material_id=id
	var group:=category(id); var index:=variant(id)
	result.label=str(CATEGORIES.get(group,["Image"])[index])
	var palettes={"Metal":[Color("656e77"),Color("d1dde3")],"Wood":[Color("50321e"),Color("ba8951")],"Fabric":[Color("233b60"),Color("7291af")],"Stone":[Color("484946"),Color("b4b2a7")],"Ground":[Color("423520"),Color("768d3e")],"Organic":[Color("375b39"),Color("b1bd70")],"Weathering":[Color("4b2416"),Color("c67a39")],"Illustration":[Color("18212a"),Color("f1e7cd")],"Geometry":[Color("274d64"),Color("8bddd0")],"Noise":[Color("182530"),Color("d4e5e9")]}
	var colors: Array=palettes.get(group,[Color.BLACK,Color.WHITE])
	result.parameters={"primary":colors[0],"secondary":colors[1],"density":1.0,"thickness":.15,"roughness":.45,"distortion":.35,"detail":.6,"knots":.35,"contrast":1.0,"brightness":0.0,"seed":index*137,"frequency":.035,"octaves":4,"gain":.5,"lacunarity":2.0,"tileable":true}
	if group=="Metal":
		if index==6: result.parameters.primary=Color("63321e"); result.parameters.secondary=Color("deac7e")
		if index==7: result.parameters.primary=Color("554325"); result.parameters.secondary=Color("bba061")
		if index==8: result.parameters.primary=Color("866217"); result.parameters.secondary=Color("ffe6a0")
		result.parameters.roughness=.2 if index in [1,2,5,8,9] else .7
		if index==11: result.parameters.primary=Color("5d686c"); result.parameters.secondary=Color("ac562f")
	if group=="Wood":
		result.parameters.density=[1.0,.7,1.4,1.6,.8,2.0,1.1,1.5,1.0,1.0,.8,1.0,.6,1.2][index]
		result.parameters.knots=.8 if index in [1,11,12] else .25
		if index in [2,3,13]: result.parameters.primary=Color("28170e"); result.parameters.secondary=Color("795232")
		if index in [1,4,5]: result.parameters.primary=Color("95753e"); result.parameters.secondary=Color("e0c79a")
	if group=="Fabric": result.texture_size=24.0; result.parameters.density=1.4 if index in [0,2,4,5] else .7
	if group=="Fabric":
		if index in [0,2,8,11]: result.parameters.primary=Color("82735b"); result.parameters.secondary=Color("d8c9a4")
		if index in [3,13]: result.parameters.primary=Color("454646"); result.parameters.secondary=Color("a5a7a3")
		if index in [6,7]: result.parameters.primary=Color("352018"); result.parameters.secondary=Color("885739")
		if index==5: result.parameters.primary=Color("291c39"); result.parameters.secondary=Color("705985")
	if group=="Stone" and index in [7,8,9,14]: result.texture_size=128
	if group=="Ground" and index in [8,9]: result.parameters.primary=Color("b4cdd3"); result.parameters.secondary=Color("f0fafb")
	if group=="Ground":
		if index in [2,3,4,12,13]: result.parameters.primary=Color("3d281b"); result.parameters.secondary=Color("94754a")
		if index==5: result.parameters.primary=Color("b08b50"); result.parameters.secondary=Color("efd29b")
		if index in [6,7,10]: result.parameters.primary=Color("46463f"); result.parameters.secondary=Color("aaa58f")
	if group=="Organic":
		if index==0: result.parameters.primary=Color("b18366"); result.parameters.secondary=Color("e8c6a9")
		if index in [3,4,7]: result.parameters.primary=Color("483022"); result.parameters.secondary=Color("b29761")
		if index==8: result.parameters.primary=Color("a59f81"); result.parameters.secondary=Color("ece5c7")
		if index==9: result.parameters.primary=Color("9d7163"); result.parameters.secondary=Color("ecd1bd")
	if group=="Weathering":
		if index in [1,2,9,11]: result.parameters.primary=Color("38332c"); result.parameters.secondary=Color("a49573")
		if index in [7,8,12]: result.parameters.primary=Color("161a1d"); result.parameters.secondary=Color("555143")
		if index==13: result.parameters.primary=Color("26352a"); result.parameters.secondary=Color("718d55")
	if group=="Weathering": result.blending="detail"
	if group=="Geometry": result.parameters.distortion=0.0
	return result
