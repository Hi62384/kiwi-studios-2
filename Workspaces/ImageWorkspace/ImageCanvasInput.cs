using Godot;
using System;
using System.Collections.Generic;
using GArray=Godot.Collections.Array;
public partial class ImageCanvasSelectionOperations
{
    private static void SelectSingle(GArray selected,Variant id){selected.Clear();selected.Add(id);}
    private static void AppendPoint(Control canvas,Vector2 point){var points=canvas.Get("_points").AsVector2Array();Array.Resize(ref points,points.Length+1);points[^1]=point;canvas.Set("_points",points);}
    public void input_canvas(Control canvas,InputEvent input)
    {
        if(canvas.Get("_material_busy").AsBool()||canvas.Get("document").AsGodotObject()==null)return;string tool=canvas.Get("tool").AsString();if(tool=="warp"&&_warpInteraction.handle(canvas.Get("warp_tool").As<RefCounted>(),input)){canvas.AcceptEvent();return;}if(tool=="repair"&&_repairInteraction.handle(canvas.Get("repair_tool").As<RefCounted>(),input)){canvas.AcceptEvent();return;}
        if(tool=="path"&&input is InputEventMouseButton pathButton&&(pathButton.ButtonIndex is MouseButton.Left or MouseButton.Right))
        {
            canvas.Set("_mouse",pathButton.Position);var at=to_document(canvas,pathButton.Position);var points=new List<Vector2>(canvas.Get("_points").AsVector2Array());int index=canvas.Get("_polygon_index").AsInt32();float zoom=canvas.Get("zoom").AsSingle();
            if(pathButton.ButtonIndex==MouseButton.Right&&pathButton.Pressed){if(index>=0){points=new List<Vector2>(canvas.Get("_polygon_before").AsVector2Array());canvas.Set("_points",points.ToArray());index=-1;}else for(int i=0;i<points.Count;i++)if(points[i].DistanceTo(at)*zoom<10){points.RemoveAt(i);canvas.Set("_points",points.ToArray());canvas.EmitSignal("polygon_committed",points.ToArray());break;}}
            else if(pathButton.ButtonIndex==MouseButton.Left){if(pathButton.Pressed){canvas.GrabFocus();canvas.Set("_polygon_before",points.ToArray());index=-1;for(int i=0;i<points.Count;i++)if(points[i].DistanceTo(at)*zoom<10){index=i;break;}if(index<0){var candidate=snap_polygon_point(canvas,at,pathButton.CtrlPressed);index=polygon_insert(canvas,candidate);points.Insert(index,candidate);}canvas.Set("_points",points.ToArray());}else{if(index>=0)canvas.EmitSignal("polygon_committed",points.ToArray());index=-1;}}
            canvas.Set("_polygon_index",index);canvas.QueueRedraw();canvas.AcceptEvent();return;
        }
        if(tool=="path"&&input is InputEventMouseMotion pathMotion){canvas.Set("_mouse",pathMotion.Position);int index=canvas.Get("_polygon_index").AsInt32();if(index>=0){var points=canvas.Get("_points").AsVector2Array();points[index]=snap_polygon_point(canvas,to_document(canvas,pathMotion.Position),pathMotion.CtrlPressed);canvas.Set("_points",points);}canvas.QueueRedraw();return;}
        if(input is InputEventMouseButton button)HandleMouseButton(canvas,tool,button);else if(input is InputEventMouseMotion motion)HandleMouseMotion(canvas,tool,motion);
    }
    private void HandleMouseButton(Control canvas,string tool,InputEventMouseButton button)
    {
        canvas.Set("_mouse",button.Position);var point=to_document(canvas,button.Position);string drag=canvas.Get("_drag").AsString(),pixelMode=canvas.Get("pixel_mode").AsString();bool magnet=canvas.Get("edge_magnet").AsBool(),box=canvas.Get("pixel_box_select").AsBool();
        if(button.ButtonIndex==Godot.MouseButton.Right&&button.Pressed&&((tool is "crop" or "lasso_crop")||tool=="pixel_select"&&(pixelMode is "crop" or "lasso_crop")||(drag is "shape_stroke" or "stroke_edit" or "pixel_box" or "pixel_lasso"))){cancel_gesture(canvas);canvas.AcceptEvent();return;}
        if((button.ButtonIndex is Godot.MouseButton.WheelUp or Godot.MouseButton.WheelDown)&&button.Pressed)
        {
            bool up=button.ButtonIndex==Godot.MouseButton.WheelUp;if(button.AltPressed&&canvas.Get("brush_type").AsString()=="stroke_correct"){double scale=Math.Clamp(canvas.Get("correction_scale").AsDouble()*(up?1.1:1/1.1),.1,16);canvas.Set("correction_scale",scale);canvas.EmitSignal("correction_scale_changed",scale);canvas.AcceptEvent();return;}
            if(button.ShiftPressed&&(tool=="fill"||tool=="pixel_select"&&pixelMode=="fill"&&!magnet)){double threshold=Math.Clamp(canvas.Get("fill_threshold").AsDouble()+(up?.01:-.01),0,1);canvas.Set("fill_threshold",threshold);canvas.EmitSignal("threshold_changed",threshold);canvas.AcceptEvent();return;}
            if(button.ShiftPressed&&((tool is "brush" or "eraser")||tool=="pixel_select"&&((pixelMode is "brush" or "erase")&&!box||pixelMode=="fill"&&magnet))){double size=canvas.Get("brush_size").AsDouble();size=Math.Clamp(size+Math.Max(1,size*.12)*(up?1:-1),1,500);canvas.Set("brush_size",size);canvas.EmitSignal("brush_size_changed",size);canvas.QueueRedraw();canvas.AcceptEvent();return;}set_zoom(canvas,canvas.Get("zoom").AsDouble()*(up?1.15:1/1.15),button.Position);canvas.AcceptEvent();return;
        }
        if(button.ButtonIndex==Godot.MouseButton.Middle||button.ButtonIndex==Godot.MouseButton.Left&&Input.IsKeyPressed(Key.Space))
        {
            if(button.Pressed){canvas.Set("_pan_previous_drag",drag);canvas.Set("_drag","pan");}else{canvas.Set("_drag",canvas.Get("_pan_previous_drag"));canvas.Set("_pan_previous_drag","");if(canvas.Get("_drag").AsString()=="object_preview"&&canvas.Get("_smart_ready").AsBool()&&canvas.Get("_smart_apply_when_ready").AsBool())commit_object_selection(canvas);}canvas.Set("_last",button.Position);canvas.AcceptEvent();return;
        }
        if(button.ButtonIndex!=Godot.MouseButton.Left)return;if(button.Pressed)canvas.GrabFocus();
        if(drag=="stroke_edit")
        {
            if(button.Pressed){canvas.Set("_shape_handle",-1);var shapeHandles=shape_handles(canvas);for(int i=0;i<shapeHandles.Count;i++)if(shape_screen_handle(canvas,shapeHandles[i].AsVector2()).DistanceTo(button.Position)<14){canvas.Set("_shape_handle",i);canvas.Set("_shape_grab_offset",shapeHandles[i].AsVector2()-point);break;}if(canvas.Get("_shape_handle").AsInt32()<0)confirm_stroke(canvas);}else canvas.Set("_shape_handle",-1);canvas.AcceptEvent();return;
        }
        if(!button.Pressed){canvas.Call("_finish",point);canvas.QueueRedraw();canvas.AcceptEvent();return;}
        canvas.Set("_start",point);canvas.Set("_last",point);canvas.Set("_moved",false);canvas.Set("_pending_single","");canvas.Set("_selection_operation",button.CtrlPressed?-1:button.ShiftPressed?1:0);if(tool is "brush" or "fill" or "pixel_select")set_erase_modifier(canvas,button.CtrlPressed);var selected=canvas.Get("selected").AsGodotArray();var document=canvas.Get("document").As<Resource>();
        if(tool=="move")
        {
            var clicked=hit(canvas,point);if(button.DoubleClick&&clicked!=null&&clicked.Get("kind").AsString()=="text"){SelectSingle(selected,clicked.Get("id"));canvas.EmitSignal("selection_changed");canvas.EmitSignal("text_edit_requested");canvas.AcceptEvent();return;}
            if(selected.Count>0){var bounds=selection_bounds(canvas);canvas.Set("_bounds",bounds);float zoom=canvas.Get("zoom").AsSingle();var screen=new Rect2(origin(canvas)+bounds.Position*zoom,bounds.Size*zoom);var visible=handles(canvas,screen);int nearest=-1;float distance=9;for(int i=0;i<visible.Count;i++){float next=visible[i].AsVector2().DistanceTo(button.Position);if(next<distance){nearest=i;distance=next;}}if(nearest>=0){begin_transform(canvas,"resize"+nearest);return;}if(rotation_handle(canvas,screen).DistanceTo(button.Position)<10){begin_transform(canvas,"rotate");return;}}
            var layer=hit(canvas,point);if(layer==null){canvas.Set("_drag","box");return;}if(button.DoubleClick&&layer.Get("kind").AsString()=="text"){SelectSingle(selected,layer.Get("id"));canvas.EmitSignal("selection_changed");canvas.EmitSignal("text_edit_requested");return;}var id=layer.Get("id");if(button.CtrlPressed||button.ShiftPressed){if(selected.Contains(id))selected.Remove(id);else selected.Add(id);}else if(selected.Contains(id)&&selected.Count>1)canvas.Set("_pending_single",id);else SelectSingle(selected,id);canvas.EmitSignal("selection_changed");if(selected.Count==0)return;if(button.AltPressed)canvas.EmitSignal("duplicate_requested");canvas.Set("_bounds",selection_bounds(canvas));begin_transform(canvas,"move");
        }
        else if(tool is "brush" or "eraser" or "fill"){canvas.Set("_active_mode",Input.IsPhysicalKeyPressed(Key.O)?"circle":Input.IsPhysicalKeyPressed(Key.Q)?"curve":button.ShiftPressed?"line":"freehand");canvas.Call("_begin_paint",point);}
        else if(tool=="pixel_select"){if(pixelMode is "crop" or "lasso_crop"){canvas.Set("_drag",pixelMode);if(pixelMode=="lasso_crop")canvas.Set("_points",new[]{point});}else begin_pixel_selection(canvas,point,button.ShiftPressed);}
        else if(tool=="picker")
        {
            var preview=canvas.Get("preview").As<Texture2D>();if(preview!=null){using var bitmap=preview.GetImage();var size=(Vector2)document.Get("canvas_size").AsVector2I();if(bitmap!=null&&new Rect2(Vector2.Zero,size).HasPoint(point)){var sample=bitmap.GetPixelv((Vector2I)(point*(Vector2)bitmap.GetSize()/size));if(sample.A>0){sample.R/=sample.A;sample.G/=sample.A;sample.B/=sample.A;}canvas.EmitSignal("color_sampled",sample);}}
        }
        else if(tool=="text")canvas.EmitSignal("create_requested","text",new Rect2(point,new Vector2(420,220)),Array.Empty<Vector2>());
        else{canvas.Set("_drag",tool);if(tool=="lasso_crop")canvas.Set("_points",new[]{point});}canvas.QueueRedraw();canvas.AcceptEvent();
    }
    private void HandleMouseMotion(Control canvas,string tool,InputEventMouseMotion motion)
    {
        canvas.Set("_mouse",motion.Position);var point=to_document(canvas,motion.Position);string drag=canvas.Get("_drag").AsString(),mode=canvas.Get("pixel_mode").AsString();bool magnet=canvas.Get("edge_magnet").AsBool(),box=canvas.Get("pixel_box_select").AsBool();if(drag.Length==0&&tool=="pixel_select"&&magnet&&(mode is "brush" or "fill")&&!box&&canvas.Get("smart_selection").AsGodotObject().Get("edges").AsGodotObject()!=null)canvas.Set("_edge_hover_pending",true);
        if(drag=="pan"){canvas.Set("pan",canvas.Get("pan").AsVector2()+motion.Position-canvas.Get("_last").AsVector2());canvas.Set("_last",motion.Position);}
        else if(drag is "move" or "rotate"||drag.StartsWith("resize",StringComparison.Ordinal))transform(canvas,point,motion.ShiftPressed,motion.CtrlPressed);
        else if(drag=="paint"){set_erase_modifier(canvas,tool=="brush"&&motion.CtrlPressed);var corrector=canvas.Get("_corrector").As<RefCounted>();if(corrector!=null)corrector.Call("_native").As<StrokeCorrectorKernel>().add(point,Time.GetTicksUsec()/1000000.0);else{paint_line(canvas,canvas.Get("_last").AsVector2(),point,true);canvas.EmitSignal("gesture_changed");}canvas.Set("_last",point);}
        else if(drag=="pixel_select"){set_erase_modifier(canvas,motion.CtrlPressed);if((mode is "brush" or "erase")&&!box){canvas.Set("_edge_motion_pending",true);canvas.Set("_edge_motion_point",point);}else{pixel_brush_line(canvas,canvas.Get("_last").AsVector2(),point);canvas.Set("_last",point);update_selection_preview(canvas);}}
        else if(drag=="pixel_box"){set_erase_modifier(canvas,motion.CtrlPressed);canvas.Set("_last",point);update_pixel_box(canvas,point);}
        else if(drag=="pixel_lasso"){set_erase_modifier(canvas,motion.CtrlPressed);canvas.Set("_last",point);var points=canvas.Get("_points").AsVector2Array();if(points[^1].DistanceTo(point)>2/canvas.Get("zoom").AsSingle())AppendPoint(canvas,point);}
        else if(drag=="shape_stroke"){var end=constrain_shape_point(canvas,point,motion.ShiftPressed);canvas.Set("_shape_end",end);var start=canvas.Get("_start").AsVector2();var chord=end-start;canvas.Set("_shape_control",start.Lerp(end,1f/3)+new Vector2(-chord.Y,chord.X)*.5f);canvas.Set("_shape_control_end",start.Lerp(end,2f/3)+new Vector2(-chord.Y,chord.X)*.5f);}
        else if(drag=="stroke_edit")move_shape_handle(canvas,point+canvas.Get("_shape_grab_offset").AsVector2(),motion.ShiftPressed);
        else if(drag=="vertex")
        {
            var document=canvas.Get("document").As<Resource>();var selected=canvas.Get("selected").AsGodotArray();var layer=_documents.layer_for_id(document,selected[selected.Count-1].AsString())!;var properties=layer.Get("properties").AsGodotDictionary();var vertices=properties["points"].AsVector2Array();var dimensions=layer.Get("dimensions").AsVector2();var size=Get(properties,"path_size",dimensions).AsVector2();vertices[canvas.Get("_vertex_index").AsInt32()]=(_documents.world_transform(document,layer).AffineInverse()*point)*size/dimensions;properties["points"]=vertices;canvas.Set("_moved",true);canvas.EmitSignal("gesture_changed");
        }
        else if(drag.Length>0){canvas.Set("_last",point);if(drag=="lasso_crop"){var points=canvas.Get("_points").AsVector2Array();if(points.Length==0||points[^1].DistanceTo(point)>3/canvas.Get("zoom").AsSingle())AppendPoint(canvas,point);}}canvas.QueueRedraw();
    }
    public bool can_drop_data(Variant data){if(data.VariantType!=Variant.Type.Dictionary)return false;var payload=data.AsGodotDictionary();return payload.ContainsKey("files")||payload.ContainsKey("paths");}
    public void drop_data(Control canvas,Vector2 at,Godot.Collections.Dictionary data)
    {
        var payload=Get(data,"files",Get(data,"paths",new GArray()));string[] paths;if(payload.VariantType==Variant.Type.PackedStringArray)paths=payload.AsStringArray();else{var values=payload.AsGodotArray();paths=new string[values.Count];for(int i=0;i<paths.Length;i++)paths[i]=values[i].AsString();}canvas.EmitSignal("files_dropped",paths,to_document(canvas,at));
    }
    public bool selected_pixel(Control canvas,Vector2 point,bool warped)=>selection_coverage(canvas,point,warped)>0;
    public bool paint_pixel_allowed(Control canvas,Vector2 point,bool warped)=>!canvas.Get("paint_selection_only").AsBool()||canvas.Get("selection").AsGodotObject()!=null&&selection_coverage(canvas,point,warped)>0;

}
