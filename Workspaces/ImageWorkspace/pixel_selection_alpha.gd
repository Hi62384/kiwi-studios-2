extends RefCounted
## Coverage masks store alpha continuously. All compositing lerps against the
## pre-gesture mask, so overlapping brush stamps do not exceed target alpha.
static func stamp(diameter: float,falloff: float) -> Image:
	var image:=Image.create(64,64,false,Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var radius:=(Vector2(x+.5,y+.5)-Vector2.ONE*32).length()/32
			var a:=1.0 if radius<1 else 0.0
			if falloff>0:
				var t:=clampf((1-radius)/falloff,0,1); a=t*t*(3-2*t)
			image.set_pixel(x,y,Color(1,1,1,a))
	var size:=maxi(1,ceili(diameter)); image.resize(size,size,Image.INTERPOLATE_BILINEAR)
	return image

static func blend(base: Image,coverage: Image,amount: float,subtract: bool,origin: Vector2i=Vector2i.ZERO) -> Image:
	var result:=base.duplicate()
	var region:=Rect2i(origin,coverage.get_size()).intersection(Rect2i(Vector2i.ZERO,base.get_size()))
	if not region.has_area(): return result
	var prior:=base.get_region(region).get_data(); var mask:=coverage.get_region(Rect2i(region.position-origin,region.size)).get_data()
	for offset in range(3,prior.size(),4):
		var weight:=mask[offset]/255.0
		var old:=prior[offset]/255.0
		var alpha:=lerpf(old,0,weight*amount) if subtract else lerpf(old,amount,weight)
		prior[offset]=roundi(clampf(alpha,0,1)*255)
		prior[offset-3]=255; prior[offset-2]=255; prior[offset-1]=255
	result.blit_rect(Image.create_from_data(region.size.x,region.size.y,false,Image.FORMAT_RGBA8,prior),Rect2i(Vector2i.ZERO,region.size),region.position)
	return result

static func blend_region(result: Image,base: Image,coverage: Image,area: Rect2i,amount: float,subtract: bool) -> void:
	area=area.intersection(Rect2i(Vector2i.ZERO,result.get_size()))
	if not area.has_area(): return
	var patch:=blend(base.get_region(area),coverage.get_region(area),amount,subtract)
	result.blit_rect(patch,Rect2i(Vector2i.ZERO,area.size),area.position)

static func feather(mask: Image,falloff: float) -> Image:
	if falloff<=0: return mask
	var small: Image=mask.duplicate(); var scale:=minf(1,256.0/maxi(mask.get_width(),mask.get_height()))
	if scale<1: small.resize(maxi(1,roundi(mask.get_width()*scale)),maxi(1,roundi(mask.get_height()*scale)),Image.INTERPOLATE_NEAREST)
	var size:=small.get_size(); var bytes:=small.get_data(); var distance:=PackedFloat32Array(); distance.resize(size.x*size.y)
	var maximum:=0.0
	for i in distance.size(): distance[i]=100000.0 if bytes[i*4+3]>0 else 0.0
	for y in size.y:
		for x in size.x:
			var i:=y*size.x+x
			if distance[i]==0: continue
			if x==0 or y==0: distance[i]=1
			if x>0: distance[i]=minf(distance[i],distance[i-1]+1)
			if y>0: distance[i]=minf(distance[i],distance[i-size.x]+1)
	for y in range(size.y-1,-1,-1):
		for x in range(size.x-1,-1,-1):
			var i:=y*size.x+x
			if distance[i]==0: continue
			if x==size.x-1 or y==size.y-1: distance[i]=1
			if x+1<size.x: distance[i]=minf(distance[i],distance[i+1]+1)
			if y+1<size.y: distance[i]=minf(distance[i],distance[i+size.x]+1)
			maximum=maxf(maximum,distance[i])
	var width:=maxf(1,maximum*falloff)
	for i in distance.size():
		var t:=clampf(distance[i]/width,0,1); bytes[i*4+3]=roundi(bytes[i*4+3]*t*t*(3-2*t))
	small=Image.create_from_data(size.x,size.y,false,Image.FORMAT_RGBA8,bytes)
	if scale<1: small.resize(mask.get_width(),mask.get_height(),Image.INTERPOLATE_BILINEAR)
	return small
