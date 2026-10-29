extends PopupPanel
## Bounded, cancelable CPU diagnostic. Pixel uploads happen only on the UI thread.
class SliceJob extends RefCounted:
	var terrain: KiwiEnvironmentTerrain
	var height:=0.
	var pixels:=PackedByteArray()
	var task:=-1
	var mutex:=Mutex.new()
	var stopped:=false
	func cancel() -> void: mutex.lock(); stopped=true; mutex.unlock()
	func canceled() -> bool:
		mutex.lock(); var value:=stopped; mutex.unlock(); return value
	func start(source: KiwiEnvironmentTerrain,y: float) -> void:
		terrain=source.duplicate(false) as KiwiEnvironmentTerrain; terrain.edits=source.edits.duplicate(); terrain.volume_chunks={}; terrain.generation=source.generation.duplicate(true) if source.generation!=null else null; terrain.erosion=[]; terrain.caves=[]
		for operation in source.erosion: terrain.erosion.append(operation.duplicate(true))
		for cave in source.caves: terrain.caves.append(cave.duplicate(true))
		height=y; task=WorkerThreadPool.add_task(_run,false,"Terrain density slice")
	func _run() -> void:
		terrain.prepare(canceled)
		if canceled(): return
		var sampler:=preload("res://Workspaces/EnvironmentWorkspace/terrain/terrain_volume_mesher.gd").new(); sampler.terrain=terrain
		for cave in terrain.caves:
			if cave.enabled: cave.prepare(); sampler.caves.append(cave); sampler.cave_bounds.append(cave.bounds())
		pixels.resize(96*96*4)
		for z in 96:
			for x in 96:
				if x%8==0 and canceled(): return
				var point: Vector3=Vector3((float(x)/95.-.5)*terrain.dimensions.x,height,(float(z)/95.-.5)*terrain.dimensions.y); var distance: float=sampler.density(point); var color:=Color("ba9568") if distance<0. else Color("3fbbb4")
				color=color.lerp(Color("ecf5f0"),1.-smoothstep(0.,maxf(.05,terrain.voxel_height*.3),absf(distance))); var index: int=(x+z*96)*4; pixels[index]=roundi(color.r*255.); pixels[index+1]=roundi(color.g*255.); pixels[index+2]=roundi(color.b*255.); pixels[index+3]=255
	func complete() -> bool: return task>=0 and WorkerThreadPool.is_task_completed(task)
	func collect() -> void:
		if task>=0: WorkerThreadPool.wait_for_task_completion(task); task=-1
var source: KiwiEnvironmentTerrain
var preview:=TextureRect.new()
var progress:=Label.new()
var _job: SliceJob
var _retired: Array[SliceJob]=[]
func _ready() -> void:
	var margin:=MarginContainer.new(); add_child(margin)
	for side in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+side,12)
	var column:=VBoxContainer.new(); margin.add_child(column); column.custom_minimum_size=Vector2(620,420); var row:=HBoxContainer.new(); column.add_child(row); var title:=Label.new(); title.text="DENSITY SLICE"; title.size_flags_horizontal=Control.SIZE_EXPAND_FILL; row.add_child(title); var close:=Button.new(); close.text="×"; row.add_child(close); close.pressed.connect(hide)
	var controls:=HBoxContainer.new(); column.add_child(controls); var caption:=Label.new(); caption.text="Height (Y)"; controls.add_child(caption); var height:=DragNumber.new(); height.min_value=-100000.; height.max_value=100000.; height.step=.1; height.custom_minimum_size.x=140; controls.add_child(height); height.value_changed.connect(_generate); height.drag_committed.connect(_generate)
	progress.size_flags_horizontal=Control.SIZE_EXPAND_FILL; controls.add_child(progress); var legend:=Label.new(); legend.text="Brown: solid    Teal: air    White: boundary"; column.add_child(legend); preview.custom_minimum_size=Vector2(600,340); preview.expand_mode=TextureRect.EXPAND_IGNORE_SIZE; preview.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED; column.add_child(preview); popup_hide.connect(queue_free); _generate(0.)
func _generate(height: float) -> void:
	if source==null: return
	if _job!=null: _job.cancel(); _retired.append(_job)
	_job=SliceJob.new(); _job.start(source,height); progress.text="Sampling…"
func _process(_delta: float) -> void:
	for index in range(_retired.size()-1,-1,-1):
		if _retired[index].complete(): _retired[index].collect(); _retired.remove_at(index)
	if _job==null or not _job.complete(): return
	_job.collect()
	if not _job.canceled() and _job.pixels.size()==96*96*4: preview.texture=ImageTexture.create_from_image(Image.create_from_data(96,96,false,Image.FORMAT_RGBA8,_job.pixels)); progress.text="Y = %.2f m"%_job.height
	_job=null
func _exit_tree() -> void:
	if _job!=null: _job.cancel(); _retired.append(_job)
	for job in _retired: job.cancel(); job.collect()
	_retired.clear(); _job=null
