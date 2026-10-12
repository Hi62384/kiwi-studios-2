class_name KiwiImageWarpData
extends Resource
## Serializable geometry; source artwork remains owned by the image layer.
@export var enabled:=true
@export var grid_size:=Vector2i(65,65)
@export var displacement:=PackedVector2Array()
@export var freeze:=PackedFloat32Array()
@export var mesh_resolution:=4
@export var mesh_points:=PackedVector2Array()
@export var pins: Array[Dictionary]=[]
@export var restriction:=PackedFloat32Array()
@export var baseline:=PackedVector2Array()
var revision:=0
var _cached_revision:=-1
var _field:=PackedVector2Array()
var _texture: ImageTexture
var _mesh_active:=false
var _pin_sources:=PackedVector2Array()
var _pin_deltas:=PackedVector2Array()
var _pin_radii:=PackedFloat32Array()
var _pin_locked:=PackedByteArray()

func initialize(extent: Vector2) -> void:
	var ratio:=extent/maxf(1,maxf(extent.x,extent.y))
	grid_size=Vector2i((ratio*64).ceil()).max(Vector2i(16,16))+Vector2i.ONE
	displacement.resize(grid_size.x*grid_size.y); freeze.resize(displacement.size())
	reset_mesh(4); touch()

func copy_warp() -> KiwiImageWarpData:
	var result:=KiwiImageWarpData.new()
	result.enabled=enabled; result.grid_size=grid_size
	result.displacement=displacement.duplicate(); result.freeze=freeze.duplicate()
	result.mesh_resolution=mesh_resolution; result.mesh_points=mesh_points.duplicate()
	result.pins.assign(pins.duplicate(true)); result.restriction=restriction.duplicate()
	result.baseline=baseline.duplicate()
	result.revision=revision
	return result

func touch() -> void: revision+=1

func refine_for_brush(extent: Vector2,diameter: float) -> void:
	var desired:=clampi(ceili(maxf(extent.x,extent.y)/maxf(.5,diameter*.12)),64,256)
	var current:=maxi(grid_size.x,grid_size.y)-1
	if desired<=current: return
	var next:=mini(256,int(pow(2,ceili(log(desired)/log(2)))))
	var previous_size:=grid_size; var previous:=displacement.duplicate()
	var old_freeze:=freeze.duplicate(); var old_restriction:=restriction.duplicate(); var old_baseline:=baseline.duplicate()
	grid_size=Vector2i((extent/maxf(extent.x,extent.y)*next).ceil()).max(Vector2i(16,16))+Vector2i.ONE
	displacement.resize(grid_size.x*grid_size.y); freeze.resize(displacement.size())
	if not old_restriction.is_empty(): restriction.resize(displacement.size())
	if not old_baseline.is_empty(): baseline.resize(displacement.size())
	for i in displacement.size():
		var p:=node_uv(i); displacement[i]=sample_grid(previous,previous_size,p)
		freeze[i]=sample_scalar(old_freeze,previous_size,p)
		if not old_restriction.is_empty(): restriction[i]=sample_scalar(old_restriction,previous_size,p)
		if not old_baseline.is_empty(): baseline[i]=sample_grid(old_baseline,previous_size,p)
	_texture=null; touch()

static func sample_scalar(values: PackedFloat32Array,size: Vector2i,uv: Vector2) -> float:
	if values.is_empty(): return 0
	var p:=uv.clamp(Vector2.ZERO,Vector2.ONE)*Vector2(size-Vector2i.ONE); var x:=floori(p.x); var y:=floori(p.y)
	var right:=mini(size.x-1,x+1); var bottom:=mini(size.y-1,y+1)
	return lerpf(lerpf(values[y*size.x+x],values[y*size.x+right],p.x-x),lerpf(values[bottom*size.x+x],values[bottom*size.x+right],p.x-x),p.y-y)
func node_uv(index: int) -> Vector2: return Vector2(index%grid_size.x,index/grid_size.x)/Vector2(grid_size-Vector2i.ONE)
func mesh_origin(index: int) -> Vector2: return Vector2(index%mesh_resolution,index/mesh_resolution)/float(mesh_resolution-1)

func reset_mesh(resolution: int) -> void:
	mesh_resolution=clampi(resolution,2,16); mesh_points.resize(mesh_resolution*mesh_resolution)
	for i in mesh_points.size(): mesh_points[i]=mesh_origin(i)
	touch()

func change_resolution(resolution: int) -> void:
	var previous:=mesh_points.duplicate(); var previous_resolution:=mesh_resolution
	reset_mesh(resolution)
	for i in mesh_points.size():
		var uv:=mesh_origin(i)
		mesh_points[i]=sample_grid(previous,Vector2i(previous_resolution,previous_resolution),uv)
	touch()

static func sample_grid(values: PackedVector2Array,size: Vector2i,uv: Vector2) -> Vector2:
	if values.is_empty(): return Vector2.ZERO
	var at:=uv.clamp(Vector2.ZERO,Vector2.ONE)*Vector2(size-Vector2i.ONE)
	var x:=floori(at.x); var y:=floori(at.y); var right:=mini(size.x-1,x+1); var bottom:=mini(size.y-1,y+1)
	return values[y*size.x+x].lerp(values[y*size.x+right],at.x-x).lerp(values[bottom*size.x+x].lerp(values[bottom*size.x+right],at.x-x),at.y-y)

func forward_controls(uv: Vector2) -> Vector2:
	var result:=uv
	if _mesh_active: result+=sample_grid(mesh_points,Vector2i(mesh_resolution,mesh_resolution),uv)-uv.clamp(Vector2.ZERO,Vector2.ONE)
	var sum:=Vector2.ZERO; var anchors:=Vector2.ZERO; var anchor_weight:=0.0
	for i in _pin_sources.size():
		var center:=_pin_sources[i]; var radius:=_pin_radii[i]
		var distance:=uv.distance_to(center)
		if distance>=radius: continue
		var falloff:=1-distance/radius
		# Independent, smooth compact-support displacements: an unmoved pin
		# contributes zero, rather than renormalizing every existing pin.
		var influence:=pow(falloff,4)*(1+4*distance/radius)
		sum+=_pin_deltas[i]*influence
		if _pin_locked[i]!=0:
			var weight:=influence/maxf(.0000001,distance*distance)
			anchors+=_pin_deltas[i]*weight; anchor_weight+=weight
	if anchor_weight>0: sum=sum.lerp(anchors/anchor_weight,anchor_weight/(1+anchor_weight))
	result+=sum
	return result

func rebuild() -> void:
	if _cached_revision==revision and _texture!=null: return
	_field.resize(displacement.size())
	var controls_active:=not pins.is_empty()
	_mesh_active=false; _pin_sources.clear(); _pin_deltas.clear(); _pin_radii.clear(); _pin_locked.clear()
	for pin in pins:
		_pin_sources.append(pin.source); _pin_deltas.append(Vector2(pin.target)-Vector2(pin.source)); _pin_radii.append(maxf(.001,pin.radius))
		_pin_locked.append(1 if pin.get("locked",false) else 0)
	for i in mesh_points.size():
		if mesh_points[i].distance_squared_to(mesh_origin(i))>.000000001: controls_active=true; _mesh_active=true; break
	if not controls_active and freeze.count(0.0)==freeze.size() and (restriction.is_empty() or restriction.count(1.0)==restriction.size()):
		_field=displacement.duplicate()
		var direct_image:=Image.create_from_data(grid_size.x,grid_size.y,false,Image.FORMAT_RGF,_field.to_byte_array())
		if _texture==null: _texture=ImageTexture.create_from_image(direct_image)
		else: _texture.update(direct_image)
		_cached_revision=revision; return
	var bytes:=PackedByteArray(); bytes.resize(displacement.size()*8)
	for i in displacement.size():
		var p:=node_uv(i); var q:=p
		if controls_active:
			# Relaxed inverse solve handles overlapping controls without forward
			# splatting holes. The GPU smoothly interpolates this coarse field.
			for iteration in 5:
				var error:=p-forward_controls(q)
				if error.length_squared()<.000000001: break
				q+=error*.8
		var offset:=q-p+sample_grid(displacement,grid_size,q)
		var allowed:=1.0-clampf(freeze[i],0,1)
		if restriction.size()==displacement.size(): allowed*=clampf(restriction[i],0,1)
		_field[i]=(baseline[i] if baseline.size()==displacement.size() else Vector2.ZERO).lerp(offset,allowed)
		bytes.encode_float(i*8,_field[i].x); bytes.encode_float(i*8+4,_field[i].y)
	var image:=Image.create_from_data(grid_size.x,grid_size.y,false,Image.FORMAT_RGF,bytes)
	if _texture==null: _texture=ImageTexture.create_from_image(image)
	else: _texture.update(image)
	_cached_revision=revision

func texture() -> Texture2D:
	rebuild(); return _texture

func forward(uv: Vector2) -> Vector2:
	rebuild()
	var p:=uv
	for iteration in 5: p=uv-sample_grid(_field,grid_size,p)
	return p

func capture_baseline() -> void:
	rebuild(); baseline=_field.duplicate()

func inverse_offset(index: int) -> Vector2: return _field[index] if index<_field.size() else Vector2.ZERO

func reset_all() -> void:
	displacement.fill(Vector2.ZERO); reset_mesh(mesh_resolution)
	baseline.clear(); restriction.clear()
	for pin in pins: pin.target=pin.source
	touch()
