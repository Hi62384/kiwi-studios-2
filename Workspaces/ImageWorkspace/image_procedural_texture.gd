extends RefCounted
const TYPES={"Noise":["white","smooth","perlin","simplex","fractal","cellular"],"Surfaces":["grain","speckles","paper","fabric","stone","dirt","clouds","scratches","stipple"],"Geometry":["stripes","dots","checkerboard","grid","waves","triangles"]}

static func generate(recipe: KiwiImageTextureRecipe,size: Vector2i,cancelled: Callable=Callable()) -> Image:
	var noise:=recipe.configure_noise(); var config:=recipe.settings
	var result:=Image.create(maxi(1,size.x),maxi(1,size.y),false,Image.FORMAT_RGBA8)
	var frequency:=float(config.get("frequency",.035))/maxf(.01,float(config.get("scale",1)))
	noise.frequency=frequency
	var angle:=deg_to_rad(float(config.get("rotation",0)))
	var density:=float(config.get("density",.5)); var kind:=recipe.kind
	var seed:=int(config.get("seed",0)); var rng:=RandomNumberGenerator.new(); rng.seed=seed
	var primary: Color=config.get("primary",Color.BLACK); var secondary: Color=config.get("secondary",Color.WHITE)
	for y in result.get_height():
		if cancelled.is_valid() and cancelled.call(): return result
		for x in result.get_width():
			var p:=Vector2(x,y).rotated(angle)
			var value:=noise.get_noise_2d(p.x,p.y)*.5+.5
			if config.get("seamless",true):
				var u:=float(x)/maxi(1,size.x-1); var v:=float(y)/maxi(1,size.y-1)
				var dx:=Vector2(maxi(1,size.x-1),0).rotated(angle); var dy:=Vector2(0,maxi(1,size.y-1)).rotated(angle)
				var a:=noise.get_noise_2d(p.x,p.y); var b:=noise.get_noise_2d(p.x-dx.x,p.y-dx.y)
				var c:=noise.get_noise_2d(p.x-dy.x,p.y-dy.y); var d:=noise.get_noise_2d(p.x-dx.x-dy.x,p.y-dx.y-dy.y)
				value=lerpf(lerpf(a,b,u),lerpf(c,d,u),v)*.5+.5
			var q:=p*frequency
			match kind:
				"white","grain": value=rng.randf()
				"speckles","stipple": value=1.0 if rng.randf()<density*.2 else 0.0
				"paper": value=.75+value*.15+rng.randf()*.1
				"fabric": value=.5+.2*sin(q.x*TAU)*sin(q.y*TAU)+value*.1
				"stone": value=pow(clampf(value,0,1),2)
				"dirt": value=value*.7+rng.randf()*.3
				"clouds": value=smoothstep(.25,.75,value)
				"scratches": value=1.0 if fposmod(q.x+noise.get_noise_2d(0,p.y)*.1,1)<density*.03 else .1
				"stripes": value=1.0 if fposmod(q.x,1)<density else 0.0
				"checkerboard": value=float(posmod(floori(q.x)+floori(q.y),2))
				"grid": value=1.0 if minf(fposmod(q.x,1),fposmod(q.y,1))<density*.2 else 0.0
				"waves": value=.5+.5*sin(q.x*TAU+sin(q.y*TAU))
				"dots": value=1.0 if (Vector2(fposmod(q.x,1),fposmod(q.y,1))-Vector2.ONE*.5).length()<density*.5 else 0.0
				"triangles": value=1.0 if fposmod(q.x,1)+fposmod(q.y,1)<density*2 else 0.0
			value=clampf((value-.5)*float(config.get("contrast",1))+.5+float(config.get("brightness",0)),0,1)
			if config.get("invert",false): value=1-value
			result.set_pixel(x,y,primary.lerp(secondary,value))
	if config.get("seamless",true):
		# Cross-fade a narrow wrapping band for random/geometric components too.
		# This preserves their interior detail while guaranteeing tile borders.
		var band:=maxi(1,mini(size.x,size.y)/12)
		for y in result.get_height():
			for i in band:
				var a:=result.get_pixel(i,y); var b:=result.get_pixel(size.x-1-i,y)
				var center:=a.lerp(b,.5); var weight:=1-smoothstep(0,float(band),float(i))
				result.set_pixel(i,y,a.lerp(center,weight)); result.set_pixel(size.x-1-i,y,b.lerp(center,weight))
		for x in result.get_width():
			for i in band:
				var a:=result.get_pixel(x,i); var b:=result.get_pixel(x,size.y-1-i)
				var center:=a.lerp(b,.5); var weight:=1-smoothstep(0,float(band),float(i))
				result.set_pixel(x,i,a.lerp(center,weight)); result.set_pixel(x,size.y-1-i,b.lerp(center,weight))
		for y in result.get_height(): result.set_pixel(size.x-1,y,result.get_pixel(0,y))
		for x in result.get_width(): result.set_pixel(x,size.y-1,result.get_pixel(x,0))
	return result
