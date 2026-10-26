class_name KiwiTransformationExamples
extends RefCounted
const NAMES := ["Blinking eye","Talking mouth","Bouncing ball","Layered face","Bleeding cut"]
static func image(kind: String, amount: float=1.) -> Image:
	var result := Image.create(160,120,false,Image.FORMAT_RGBA8); result.fill(Color(0,0,0,0))
	for y in 120:
		for x in 160:
			var p := Vector2(x+.5,y+.5); var center := Vector2(80,60); var color := Color(0,0,0,0)
			if kind=="eye":
				var q := (p-center)/Vector2(61,maxf(3,32*amount))
				if q.length_squared()<1.:
					color=Color("132433") if q.length()>.88 else Color("fcf9e9")
					if p.distance_to(center)<12*amount: color=Color("54babc")
					if p.distance_to(center)<5*amount: color=Color("132433")
			elif kind=="mouth":
				var q := (p-center)/Vector2(45+15*amount,maxf(3,40*amount))
				if q.length_squared()<1.:
					color=Color("c23851") if q.length()>.84 else Color("381a34")
					if q.y<-.15 and absf(q.x)<.7 and amount>.2: color=Color("fff3db")
					if ((p-Vector2(80,77))/Vector2(29,13)).length_squared()<1. and amount>.2: color=Color("ef718b")
			elif kind=="ball":
				var d := p.distance_to(center)
				if d<43: color=Color("d8773f") if d>39 else Color("ffc977")
				if p.distance_to(Vector2(65,46))<10: color=Color("ffefb6")
			elif kind=="blood":
				var q := (p-Vector2(80,20+30*amount))/Vector2(22-9*amount,15+40*amount)
				if q.length_squared()<1.: color=Color("a41f49") if q.length()>.8 else Color("e34557")
			elif kind=="cut":
				var q := (p-center)/Vector2(64,maxf(2,18*amount))
				if q.length_squared()<1.: color=Color("aa2847") if q.length()>.75 else Color("411b39")
			elif kind=="brow":
				if absf(p.y-(55.+pow((p.x-80.)/55.,2.)*12.))<5 and absf(p.x-80)<58: color=Color("5b3f48")
			result.set_pixel(x,y,color)
	return result
static func component(document: KiwiTransformationImage2D, title: String, position: Vector2, dimensions: Vector2) -> KiwiTransformationComponent:
	var item := KiwiTransformationImage2D.make_component(Vector2i(160,120),title); item.base_size=dimensions; item.states[0].artwork.position=position; item.states[0].artwork.dimensions=dimensions; document.components.append(item); return item
static func state(item: KiwiTransformationComponent, title: String, bitmap: Image) -> KiwiTransformationState:
	var result := item.states[0].copy_state(true); result.title=title; result.artwork.texture=ImageTexture.create_from_image(bitmap); result.artwork.paint_base=result.artwork.texture; item.states.append(result); return result
static func key(item: KiwiTransformationComponent, at: float, state: KiwiTransformationState, mode: String="Smooth morph") -> KiwiTransformationKey:
	var result := KiwiTransformationKey.new(); result.id=ActorData.new_id(); result.time=at; result.state_id=state.id; result.mode=mode; item.keys.append(result); return result
static func finish(item: KiwiTransformationComponent, states: Array[KiwiTransformationState]) -> void:
	item.states.assign(states); item.default_state_id=states[0].id
static func create(title: String) -> KiwiTransformationImage2D:
	var document := KiwiTransformationImage2D.new(); document.canvas_size=Vector2i(640,400); document.duration=3.; document.metadata.example=title
	if title=="Bleeding cut":
		var cut := component(document,"Cut",Vector2(170,45),Vector2(300,100)); var closed := state(cut,"Closed",image("cut",.05)); var open := state(cut,"Open",image("cut",1.)); finish(cut,[closed,open]); key(cut,0,closed); key(cut,.5,open); key(cut,3,open)
		var blood := component(document,"Blood",Vector2(240,75),Vector2(160,240)); var empty := state(blood,"Empty",Image.create(160,120,false,Image.FORMAT_RGBA8)); var gathering := state(blood,"Gathering",image("blood",0)); var stream := state(blood,"Stream",image("blood",1)); empty.pivot=Vector2(.5,.1); gathering.pivot=empty.pivot; stream.pivot=empty.pivot; finish(blood,[empty,gathering,stream]); key(blood,0,empty); var reveal := key(blood,.7,gathering,"Reveal"); reveal.reveal_path=PackedVector2Array([Vector2(.5,.1),Vector2(.5,.95)]); reveal.reveal_width=.35; key(blood,1.7,stream); key(blood,3,stream)
		var drop := component(document,"Blood drop",Vector2(295,210),Vector2(50,70)); var hidden := state(drop,"Hidden",Image.create(160,120,false,Image.FORMAT_RGBA8)); var formed := state(drop,"Formed",image("blood",.7)); var falling := formed.copy_state(true); falling.title="Falling"; falling.artwork.position+=Vector2(0,110); falling.artwork.opacity=0.; drop.states.append(falling); finish(drop,[hidden,formed,falling]); key(drop,0,hidden); key(drop,1.4,hidden); key(drop,1.7,formed); key(drop,2.8,falling); key(drop,3,hidden,"Step")
	elif title=="Bouncing ball":
		var ball := component(document,"Ball",Vector2(230,40),Vector2(180,180)); var top := state(ball,"Airborne",image("ball")); var floor := top.copy_state(true); floor.title="Squash"; floor.artwork.position=Vector2(205,265); floor.artwork.dimensions=Vector2(230,100); floor.pivot=Vector2(.5,1); var stretch := top.copy_state(true); stretch.title="Stretch"; stretch.artwork.position=Vector2(250,150); stretch.artwork.dimensions=Vector2(140,210); ball.states.append_array([floor,stretch]); finish(ball,[top,floor,stretch]); key(ball,0,top); key(ball,1.,floor); key(ball,1.3,stretch); key(ball,2.,top); key(ball,3.,top)
	else:
		if title=="Layered face":
			var face := component(document,"Face",Vector2(90,5),Vector2(460,380)); var face_state := state(face,"Base",image("ball")); finish(face,[face_state])
		if title in ["Blinking eye","Layered face"]:
			for i in (2 if title=="Layered face" else 1):
				var eye := component(document,"Eye "+str(i+1),Vector2(145+i*180,90) if title=="Layered face" else Vector2(170,110),Vector2(170,100) if title=="Layered face" else Vector2(300,180)); var open := state(eye,"Open",image("eye")); var closed := state(eye,"Closed",image("eye",.08)); finish(eye,[open,closed]); key(eye,0,open); key(eye,.75+i*.2,open); key(eye,1.+i*.2,closed); key(eye,1.25+i*.2,open); key(eye,3,open)
		if title in ["Talking mouth","Layered face"]:
			var mouth := component(document,"Mouth",Vector2(230,210) if title=="Layered face" else Vector2(170,90),Vector2(180,120) if title=="Layered face" else Vector2(300,220)); var states: Array[KiwiTransformationState]=[]
			for data in [["Closed",.06],["Open",1.],["Smile",.3],["O shape",.65]]: states.append(state(mouth,data[0],image("mouth",data[1])))
			finish(mouth,states)
			for i in 5: key(mouth,i*.6,states[i%4])
		if title=="Layered face":
			for i in 2:
				var brow := component(document,"Brow "+str(i+1),Vector2(145+i*180,50),Vector2(170,70)); var neutral := state(brow,"Neutral",image("brow")); var raised := neutral.copy_state(true); raised.title="Raised"; raised.artwork.position.y-=25; raised.artwork.rotation=(-.12 if i==0 else .12); brow.states.append(raised); finish(brow,[neutral,raised]); key(brow,0,neutral); key(brow,1.5,raised); key(brow,3,neutral)
	return document
