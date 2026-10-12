extends RefCounted
## Native filtered pyramid, prepared once from the immutable stroke snapshot.
## Premultiplied filtering avoids dark fringes around transparent artwork.
static func prepare(source: Image,radius: float) -> Image:
	var result: Image=source.duplicate(); result.convert(Image.FORMAT_RGBA8); result.premultiply_alpha()
	var extent:=source.get_size(); var factor:=maxf(2,clampf(radius,2,32))
	result.resize(maxi(1,roundi(extent.x/factor)),maxi(1,roundi(extent.y/factor)),Image.INTERPOLATE_LANCZOS)
	result.resize(extent.x,extent.y,Image.INTERPOLATE_BILINEAR)
	return result

static func composite(base: Image,filtered: Image,ink: Image,area: Rect2i,strength: float,opacity: float,coverage: Callable=Callable(),opaque: bool=false) -> Image:
	if opaque:
		# On photos, native source-over is exactly the desired lerp. Only the
		# brush alpha needs visiting in script, not all four color channels.
		var patch:=base.get_region(area); var bytes:=filtered.get_region(area).get_data(); var mask_bytes:=ink.get_data()
		var amount:=clampf(strength*opacity,0,1)
		if not coverage.is_valid():
			for offset in range(3,bytes.size(),4): bytes[offset]=roundi(mask_bytes[offset]*amount)
		else:
			for y in area.size.y:
				for x in area.size.x:
					var offset: int=(y*area.size.x+x)*4+3
					bytes[offset]=roundi(mask_bytes[offset]*amount*clampf(float(coverage.call(Vector2(area.position+Vector2i(x,y))+Vector2.ONE*.5)),0,1))
		patch.blend_rect(Image.create_from_data(area.size.x,area.size.y,false,Image.FORMAT_RGBA8,bytes),Rect2i(Vector2i.ZERO,area.size),Vector2i.ZERO)
		return patch
	var original:=base.get_region(area).get_data(); var smooth:=filtered.get_region(area).get_data(); var mask:=ink.get_data()
	for y in area.size.y:
		for x in area.size.x:
			var offset: int=(y*area.size.x+x)*4
			var weight:=mask[offset+3]/255.0*clampf(strength*opacity,0,1)
			if coverage.is_valid(): weight*=clampf(float(coverage.call(Vector2(area.position+Vector2i(x,y))+Vector2.ONE*.5)),0,1)
			var old_alpha:=original[offset+3]/255.0; var alpha:=lerpf(old_alpha,smooth[offset+3]/255.0,weight)
			for channel in 3:
				var premultiplied:=lerpf(original[offset+channel]*old_alpha,float(smooth[offset+channel]),weight)
				original[offset+channel]=clampi(roundi(premultiplied/maxf(.00001,alpha)),0,255)
			original[offset+3]=clampi(roundi(alpha*255),0,255)
	return Image.create_from_data(area.size.x,area.size.y,false,Image.FORMAT_RGBA8,original)
