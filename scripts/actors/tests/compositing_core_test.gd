extends SceneTree
const Document=preload("res://Workspaces/CompositingWorkspace/compositing_document.gd")
const Layer=preload("res://Workspaces/CompositingWorkspace/composite_layer.gd")
const Graph=preload("res://Workspaces/CompositingWorkspace/composite_graph.gd")
const CompositeNodeScript=preload("res://Workspaces/CompositingWorkspace/composite_graph_node.gd")
const Connection=preload("res://Workspaces/CompositingWorkspace/composite_graph_connection.gd")
const Evaluator=preload("res://Workspaces/CompositingWorkspace/compositing_evaluator.gd")
var checks:=0
var failures:=0
func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1; push_error(label)
	print("PASS " if ok else "FAIL ",label)
func run() -> void:
	var document=Document.new(); document.canvas_size=Vector2i(2,1); document.title="Composite Test"; var background=document.add_layer(Layer.Kind.SOLID,"Background"); background.color=Color.RED; var foreground=document.add_layer(Layer.Kind.SOLID,"Foreground"); foreground.color=Color(0.,0.,1.,.5)
	check(document.validate().is_empty(),"Composition document stores a valid reusable layer stack and render settings")
	var evaluator=Evaluator.new(); var output=evaluator.evaluate(document,0.); var pixel: Color=output.image.get_pixel(0,0)
	check(output.is_valid() and output.image.get_format()==Image.FORMAT_RGBAF and pixel.is_equal_approx(Color(.5,0.,.5,1.)),"Float-buffer layer evaluation applies straight-alpha Over in linear light")
	var layer_opacity: float=foreground.opacity; foreground.opacity=.5; evaluator.clear_cache(); output=evaluator.evaluate(document,0.); pixel=output.image.get_pixel(0,0)
	check(is_equal_approx(pixel.b,.25) and is_equal_approx(pixel.r,.75),"Layer opacity scales source coverage without modifying its source color"); foreground.opacity=layer_opacity
	var grade=document.add_layer(Layer.Kind.ADJUSTMENT,"Exposure"); grade.settings={"exposure":1.,"contrast":1.,"saturation":1.}; evaluator.clear_cache(); output=evaluator.evaluate(document,0.)
	check(output.image.get_pixel(0,0).r>.99,"Adjustment layers process the accumulated image non-destructively")
	var graph=Graph.new(); var solid=CompositeNodeScript.new(); solid.kind="Solid Color"; solid.settings={"color":Color.GREEN}; var sink=CompositeNodeScript.new(); sink.kind="Output"; graph.nodes.append(solid); graph.nodes.append(sink); graph.output_node=sink.id; var edge=Connection.new(); edge.from_node=solid.id; edge.from_port="image"; edge.to_node=sink.id; edge.to_port="image"; graph.connections.append(edge)
	check(graph.validate().is_empty(),"Typed graph accepts a compatible image connection")
	evaluator.clear_cache(); var graph_output=evaluator.evaluate_graph(document,graph,0.)
	check(graph_output!=null and graph_output.image.get_pixel(1,0).is_equal_approx(Color.GREEN) and evaluator.nodes_evaluated==2,"Graph source and output nodes execute through the same float image buffer")
	var cycle=Connection.new(); cycle.from_node=sink.id; cycle.from_port="image"; cycle.to_node=solid.id; cycle.to_port="image"; graph.connections.append(cycle)
	check(not graph.validate().is_empty(),"Typed graph rejects cyclic dependencies before evaluation")
	graph.connections.clear(); var source=CompositeNodeScript.new(); source.kind="Layer Source"; source.settings={"layer_id":background.id}; var grade_node=CompositeNodeScript.new(); grade_node.kind="Color Grade"; grade_node.settings={"exposure":1.,"contrast":1.,"saturation":1.}; var graph_output_node=CompositeNodeScript.new(); graph_output_node.kind="Output"; graph.nodes.clear(); graph.nodes.append(source); graph.nodes.append(grade_node); graph.nodes.append(graph_output_node); graph.output_node=graph_output_node.id
	var edge_a=Connection.new(); edge_a.from_node=source.id; edge_a.from_port="image"; edge_a.to_node=grade_node.id; edge_a.to_port="image"; var edge_b=Connection.new(); edge_b.from_node=grade_node.id; edge_b.from_port="output"; edge_b.to_node=graph_output_node.id; edge_b.to_port="image"; graph.connections.clear(); graph.connections.append(edge_a); graph.connections.append(edge_b); document.graphs.clear(); document.graphs.append(graph); background.processing_graph_id=graph.id; foreground.visible=false; grade.visible=false; evaluator.clear_cache()
	output=evaluator.evaluate(document,0.); check(output!=null and output.image.get_pixel(0,0).r>1.9,"Layer-linked processing graph evaluates non-destructively through the shared layer engine")
	var graph_direct=evaluator.evaluate_graph(document,graph,0.); check(graph_direct!=null and evaluator.graph_cache_hits>0,"Graph output cache is reused across direct node preview and layer-stack evaluation")
	var mask_node=CompositeNodeScript.new(); mask_node.kind="Mask"; var blur_node=CompositeNodeScript.new(); blur_node.kind="Blur"
	check(CompositeNodeScript.port_type("Alpha Extract","mask")==CompositeNodeScript.port_type("Mask","mask") and CompositeNodeScript.has_input("Blur","image"),"Mask and blur nodes expose explicit compatible graph ports")
	var key_buffer=Evaluator.new(); var key_input=load("res://Workspaces/CompositingWorkspace/composite_buffer.gd").new(); key_input.image=Image.create(2,1,false,Image.FORMAT_RGBAF); key_input.image.set_pixel(0,0,Color.GREEN); key_input.image.set_pixel(1,0,Color.RED); var keyed=key_buffer._chroma_key(key_input,{"key_color":Color.GREEN,"tolerance":.1,"softness":.1,"spill":0.})
	check(keyed.image.get_pixel(0,0).a<.01 and keyed.image.get_pixel(1,0).a>.99,"Chroma key removes the selected color while retaining non-keyed foreground detail")
	var luma_input=load("res://Workspaces/CompositingWorkspace/composite_buffer.gd").new(); luma_input.image=Image.create(3,1,false,Image.FORMAT_RGBAF); luma_input.image.set_pixel(0,0,Color.BLACK); luma_input.image.set_pixel(1,0,Color(.5,.5,.5,1.)); luma_input.image.set_pixel(2,0,Color.WHITE); var luma_key=key_buffer._luma_key(luma_input,{"low":.2,"high":.8,"softness":.05})
	check(luma_key.image.get_pixel(0,0).a<.01 and luma_key.image.get_pixel(1,0).a>.99 and luma_key.image.get_pixel(2,0).a<.01,"Luma key isolates a brightness band with soft threshold edges")
	var blur_input=load("res://Workspaces/CompositingWorkspace/composite_buffer.gd").new(); blur_input.image=Image.create(2,1,false,Image.FORMAT_RGBAF); blur_input.image.set_pixel(0,0,Color.RED); blur_input.image.set_pixel(1,0,Color(0.,0.,1.,0.)); var blurred=key_buffer._blur(blur_input,1)
	check(blurred.image.get_pixel(0,0).is_equal_approx(Color(1.,0.,0.,.5)),"Blur filters premultiplied coverage without bleeding hidden transparent colors")
	check(is_equal_approx(key_buffer._curve_sample([Vector2(0,0),Vector2(.5,.25),Vector2(1,1)],.5),.25),"Color curve evaluation interpolates the authored control points")
	var animated_doc=Document.new(); var animated_layer=animated_doc.add_layer(Layer.Kind.SOLID,"Animated Transform"); animated_doc.set_layer_key(animated_layer.id,"position",0.,Vector2(0.,0.)); animated_doc.set_layer_key(animated_layer.id,"position",2.,Vector2(10.,4.)); animated_doc.set_layer_key(animated_layer.id,"opacity",0.,0.); animated_doc.set_layer_key(animated_layer.id,"opacity",2.,1.)
	var animated_sample=evaluator._animated_layer(animated_doc,animated_layer,1.)
	check(animated_doc.sample_layer_value(animated_layer.id,"position",1.,animated_layer.position).is_equal_approx(Vector2(5.,2.)) and is_equal_approx(float(animated_doc.sample_layer_value(animated_layer.id,"opacity",1.,animated_layer.opacity)),.5) and animated_sample.position.is_equal_approx(Vector2(5.,2.)) and is_equal_approx(animated_sample.opacity,.5),"Layer transform and opacity keyframes interpolate and evaluate at the playhead")
	var grouped=Document.new(); grouped.canvas_size=Vector2i(2,1); grouped.layers.clear(); var group_background=grouped.add_layer(Layer.Kind.SOLID,"Red"); group_background.color=Color.RED; var group_foreground=grouped.add_layer(Layer.Kind.SOLID,"Half Blue"); group_foreground.color=Color(0.,0.,1.,.5); var group_layer=grouped.add_layer(Layer.Kind.GROUP,"Isolated Group"); group_background.parent_id=group_layer.id; group_foreground.parent_id=group_layer.id; evaluator.clear_cache(); var grouped_result=evaluator.evaluate(grouped,0.)
	check(grouped_result!=null and grouped_result.image.get_pixel(0,0).is_equal_approx(Color(.5,0.,.5,1.)),"Isolated group renders children together using the same alpha compositing rules")
	grouped.solo_layer_id=group_foreground.id; evaluator.clear_cache(); var solo_result=evaluator.evaluate(grouped,0.)
	check(solo_result!=null and solo_result.image.get_pixel(0,0).is_equal_approx(Color(0.,0.,1.,.5)),"Soloing a nested layer preserves its alpha and traverses its group ancestors")
	check(is_equal_approx(evaluator._mask_coverage(Color(.5,.5,.5,1.)),.5),"Grayscale masks retain continuous coverage instead of requiring opaque alpha only")
	var masked=Document.new(); masked.canvas_size=Vector2i(4,1); masked.layers.clear(); var masked_red=masked.add_layer(Layer.Kind.SOLID,"Masked Red"); masked_red.color=Color.RED; var mask_image=Image.create(2,1,false,Image.FORMAT_RGBA8); mask_image.fill(Color.TRANSPARENT); mask_image.set_pixel(0,0,Color.WHITE); var mask_layer=masked.add_layer(Layer.Kind.MASK,"Small Mask"); mask_layer.source_image=ImageTexture.create_from_image(mask_image); mask_layer.visible=false; masked_red.mask_id=mask_layer.id; evaluator.clear_cache(); var masked_result=evaluator.evaluate(masked,0.)
	check(masked_result!=null and masked_result.image.get_pixel(1,0).a>.9 and masked_result.image.get_pixel(0,0).a==0.,"Layer masks transform their source into canvas space and preserve soft alpha coverage")
	var design=Document.new(); design.canvas_size=Vector2i(32,24); design.layers.clear(); var ellipse=design.add_layer(Layer.Kind.SHAPE,"Ellipse"); ellipse.settings={"shape":"ellipse","size":Vector2i(16,16)}; ellipse.position=Vector2(16,12); evaluator.clear_cache(); var shape_result=evaluator.evaluate(design,0.)
	check(shape_result!=null and shape_result.image.get_pixel(16,12).a>.9 and shape_result.image.get_pixel(8,4).a==0.,"Shape layers rasterize editable geometry into the shared float compositor")
	var text_layer=design.add_layer(Layer.Kind.TEXT,"Caption"); text_layer.settings={"text":"Kiwi","font_size":10,"size":Vector2i(32,16)}; text_layer.position=Vector2(16,12); evaluator.clear_cache(); var text_result=evaluator.evaluate(design,0.); var has_glyph:=false
	if text_result!=null:
		for y in text_result.image.get_height():
			for x in text_result.image.get_width():
				if text_result.image.get_pixel(x,y).a>0.1: has_glyph=true
	check(text_result!=null and has_glyph,"Text layers rasterize editable text with the system fallback font")
	var linked_path: String="user://linked_comp_"+ActorData.new_id()+".tres"; var child_doc=Document.new(); child_doc.canvas_size=Vector2i(2,1); child_doc.layers.clear(); var child_color=child_doc.add_layer(Layer.Kind.SOLID,"Child Green"); child_color.color=Color.GREEN; ResourceSaver.save(child_doc,linked_path)
	var parent_doc=Document.new(); parent_doc.canvas_size=Vector2i(2,1); parent_doc.layers.clear(); var linked_layer=parent_doc.add_layer(Layer.Kind.LINKED_COMPOSITION,"Linked Child"); linked_layer.source_path=linked_path; linked_layer.end_time=parent_doc.duration; evaluator.clear_cache(); var nested_result=evaluator.evaluate(parent_doc,0.)
	check(nested_result!=null and nested_result.image.get_pixel(0,0).is_equal_approx(Color.GREEN),"Linked compositions evaluate the referenced editable document without flattening its source resource")
	var cycle_path: String="user://linked_cycle_"+ActorData.new_id()+".tres"; var cycle_doc=Document.new(); cycle_doc.layers.clear(); var cycle_layer=cycle_doc.add_layer(Layer.Kind.LINKED_COMPOSITION,"Cycle"); cycle_layer.source_path=cycle_path; ResourceSaver.save(cycle_doc,cycle_path); var cycle_loaded=ResourceLoader.load(cycle_path,"",ResourceLoader.CACHE_MODE_IGNORE) as KiwiCompositingDocument; evaluator.clear_cache(); var cycle_result=evaluator.evaluate(cycle_loaded,0.)
	check(cycle_result==null and evaluator.last_error.contains("cycle"),"Recursive linked-composition dependencies fail with a cycle diagnostic instead of recursing")
	var saved_path: String="user://compositing_core_"+ActorData.new_id()+".tres"; var saved:=ResourceSaver.save(document,saved_path); var loaded: Resource=ResourceLoader.load(saved_path,"",ResourceLoader.CACHE_MODE_IGNORE)
	check(saved==OK and loaded is KiwiCompositingDocument and (loaded as KiwiCompositingDocument).validate().is_empty(),"Composition resources preserve editable layers when saved and loaded")
	DirAccess.remove_absolute(saved_path); DirAccess.remove_absolute(linked_path); DirAccess.remove_absolute(cycle_path); print("COMPOSITING CORE: %d checks, %d failures"%[checks,failures]); quit(failures)
