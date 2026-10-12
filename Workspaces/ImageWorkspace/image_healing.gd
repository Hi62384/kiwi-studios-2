extends RefCounted
## Healing transfers high-frequency source detail and adapts low-frequency
## color. Spot healing searches clean surrounding patches, not blurred pixels.
static func mean(image: Image,area: Rect2i,excluded: Rect2i=Rect2i()) -> Color:
	area=area.intersection(Rect2i(Vector2i.ZERO,image.get_size()))
	var sum:=Color(0,0,0,0); var count:=0
	var step:=maxi(1,maxi(area.size.x,area.size.y)/12)
	for y in range(area.position.y,area.end.y,step):
		for x in range(area.position.x,area.end.x,step):
			if excluded.has_point(Vector2i(x,y)): continue
			var color:=image.get_pixel(x,y)
			if color.a<.01: continue
			sum+=color; count+=1
	if count==0 and excluded.has_area(): return mean(image,area)
	return sum/maxi(1,count)

static func adapt(sample: Color,source_mean: Color,destination_mean: Color,preserve: float) -> Color:
	var result:=destination_mean+(sample-source_mean)*preserve
	result.a=sample.a
	return Color(clampf(result.r,0,1),clampf(result.g,0,1),clampf(result.b,0,1),result.a)

static func spot_patch(image: Image,area: Rect2i,settings: Dictionary,excluded: Rect2i) -> Image:
	var extent:=area.size; var rng:=RandomNumberGenerator.new(); rng.seed=hash([area,settings.get("seed",0)])
	var radius:=maxi(extent.x,extent.y)*int(settings.get("search_radius",3))
	var best:=area.position; var score:=INF; var found:=false
	for candidate_index in 96:
		if settings.get("cancelled",Callable()).is_valid() and settings.cancelled.call(): return image.get_region(area)
		# Evenly distributed concentric candidates avoid unlucky random-only searches.
		var angle:=candidate_index*2.39996323
		var distance:=maxi(extent.x,extent.y)*1.5+radius*sqrt(float(candidate_index)/96)
		var source:=area.position+Vector2i(Vector2(cos(angle),sin(angle))*distance)+Vector2i(rng.randi_range(-2,2),rng.randi_range(-2,2))
		var candidate:=Rect2i(source,extent)
		if not Rect2i(Vector2i.ZERO,image.get_size()).encloses(candidate) or candidate.intersects(excluded): continue
		var error:=0.0; var count:=0
		var margin:=maxi(2,mini(8,mini(extent.x,extent.y)/3))
		for y in range(-margin,extent.y+margin,maxi(1,extent.y/6)):
			for x in range(-margin,extent.x+margin,maxi(1,extent.x/6)):
				var target:=area.position+Vector2i(x,y); var sampled:=source+Vector2i(x,y)
				if excluded.has_point(target) or not Rect2i(Vector2i.ZERO,image.get_size()).has_point(target) or not Rect2i(Vector2i.ZERO,image.get_size()).has_point(sampled): continue
				var a:=image.get_pixelv(target); var b:=image.get_pixelv(sampled)
				if a.a<.05 or b.a<.05: continue
				error+=preload("res://Workspaces/ImageWorkspace/image_texture_synthesis.gd").difference(a,b); count+=1
		if count>0 and error/count<score: score=error/count; best=source; found=true
	if not found: return image.get_region(area)
	var patch:=image.get_region(Rect2i(best,extent))
	var source_mean:=mean(image,Rect2i(best,extent))
	var target_mean:=mean(image,Rect2i(area.position-extent/2,extent*2),excluded)
	for y in patch.get_height():
		for x in patch.get_width(): patch.set_pixel(x,y,adapt(patch.get_pixel(x,y),source_mean,target_mean,float(settings.get("texture_preservation",1))))
	return patch
