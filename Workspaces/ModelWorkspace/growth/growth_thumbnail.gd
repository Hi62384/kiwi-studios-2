extends RefCounted
static var cache: Dictionary={}
static func texture(style: KiwiGrowthStyle=null,material: KiwiGrowthMaterial=null) -> Texture2D:
	var colors: Array=[]
	if material!=null: colors=[material.root_color,material.tip_color,material.mode,material.pattern,material.feather_pattern,[material.gradient.colors,material.gradient.offsets] if material.gradient!=null else []]
	var key:=hash([style.values if style!=null else {},style.title if style!=null else "",colors])
	if cache.has(key): return cache[key]
	var data:=KiwiSurfaceGrowthData.new(); var kind:=2 if style!=null and style.title in ["Down","Contour","Flight","Tail","Stylized feathers"] else 0; data.settings=KiwiSurfaceGrowth.defaults(kind); data.growth_style=style; data.source_points=PackedVector3Array([Vector3.ZERO,Vector3.RIGHT,Vector3.BACK])
	var stops:=""
	if material!=null and material.gradient!=null:
		for i in range(material.gradient.get_point_count()-1,-1,-1): stops+='<stop offset="%s" stop-color="#%s"/>'%[1.-material.gradient.get_offset(i),material.gradient.get_color(i).to_html(false)]
	else:
		stops='<stop offset="0" stop-color="#%s"/><stop offset="1" stop-color="#%s"/>'%[(material.tip_color if material!=null else Color("c7f2e9")).to_html(false),(material.root_color if material!=null else Color("38bda2")).to_html(false)]
	var svg:='<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128"><defs><linearGradient id="g" x1="0" y1="0" x2="0" y2="1">'+stops+'</linearGradient></defs><rect x="1" y="1" width="126" height="126" rx="16" fill="#15212d" stroke="#416071"/>'
	for index in (4 if kind==2 else 8):
		var root:={"id":index,"triangle":Vector3i(0,1,2),"bary":Vector3(.3,.4,.3),"normal":Vector3.UP,"random":Vector4(.5,float(index)/8.,.4,.5),"position":Vector3.ZERO,"density_rank":0.}
		var points:=KiwiSurfaceGrowth.curve(data,root); var length:=0.; var width:=0.
		for point: Vector3 in points: length=maxf(length,point.length()); width=maxf(width,absf(point.x))
		var scale:=minf(78./maxf(.01,length),15./maxf(.001,width)); var line:=""; var base:=22.+index*(24. if kind==2 else 11.)
		for point: Vector3 in points: line+="%.2f,%.2f "%[base+point.x*scale,108.-point.y*scale]
		if kind==2:
			var polygon:=""
			for direction in [-1,1]:
				for i in points.size():
					var at:=i if direction<0 else points.size()-1-i; var t:=float(at)/maxi(1,points.size()-1); var point: Vector3=points[at]; polygon+="%.2f,%.2f "%[base+point.x*scale+direction*sin(pow(t,.65)*PI)*8.,108.-point.y*scale]
			svg+='<polygon points="'+polygon+'" fill="url(#g)"/>'
		svg+='<polyline points="'+line+'" fill="none" stroke="'+('#e9d6b3' if kind==2 else 'url(#g)')+'" stroke-width="'+('1.2' if kind==2 else '2.8')+'" stroke-linecap="round"/>'
	if material!=null: svg+='<circle cx="105" cy="23" r="10" fill="#'+material.root_color.to_html(false)+'" stroke="#e2eee9"/>'
	svg+='</svg>'; var image:=Image.new(); image.load_svg_from_string(svg); var result:=ImageTexture.create_from_image(image)
	if cache.size()>128: cache.clear()
	cache[key]=result; return result
