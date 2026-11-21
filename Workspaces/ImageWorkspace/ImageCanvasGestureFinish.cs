using Godot;
using System;
using Settings=Godot.Collections.Dictionary;
public partial class ImageCanvasSelectionOperations
{
    public Settings prepare_finish(Control canvas,Vector2 point)
    {
        var warp=canvas.Get("warp_tool").As<RefCounted>();if(warp.Get("active").AsBool()){_warpInteraction.finish(warp);return new Settings();}string action=canvas.Get("_drag").AsString();if(action is "object_preview" or "edge_pending")return new Settings();flush_edge_motion(canvas);canvas.Get("snap_guides_x").AsGodotArray().Clear();canvas.Get("snap_guides_y").AsGodotArray().Clear();var corrector=canvas.Get("_corrector").As<RefCounted>();if(action=="paint"&&corrector!=null){corrector.Call("_native").As<StrokeCorrectorKernel>().add(point,Time.GetTicksUsec()/1000000.0);flush_corrected_stroke(canvas);}
        if(action=="shape_stroke"){canvas.Set("_shape_end",constrain_shape_point(canvas,point,Input.IsKeyPressed(Key.Shift)));string mode=canvas.Get("_active_mode").AsString();if(mode=="line")confirm_stroke(canvas);else{canvas.Set("_drag","stroke_edit");canvas.Set("_shape_handle",-1);canvas.EmitSignal("hint_changed",mode=="circle"?"Diagonal handles: curvature · Edges: size · Center: move · Enter applies · Right-click cancels":"Drag tangent handles: bend · Endpoints: stretch · Center: move · Enter applies · Right-click cancels");}canvas.QueueRedraw();return new Settings();}
        bool created=canvas.Get("_paint_created_layer").AsBool();canvas.Set("_drag","");var document=canvas.Get("document").As<Resource>();var selected=canvas.Get("selected").AsGodotArray();
        if(action is "pixel_select" or "pixel_box" or "pixel_lasso")
        {
            if(action=="pixel_box")update_pixel_box(canvas,point);else if(action=="pixel_lasso"){AppendPoint(canvas,point);apply_pixel_lasso(canvas,false);}var selection=canvas.Get("selection").As<Image>();
            if(action is "pixel_box" or "pixel_lasso")
            {
                using var coverage=Image.CreateEmpty(selection.GetWidth(),selection.GetHeight(),false,Image.Format.Rgba8);if(action=="pixel_box"){var start=canvas.Get("_start").AsVector2();var rect=new Rect2(start,point-start).Abs();var area=new Rect2I((Vector2I)rect.Position.Floor(),(Vector2I)(point-start).Abs().Ceil()).Intersection(canvas.Get("pixel_domain").AsRect2I());coverage.FillRect(area,Colors.White);}else{canvas.Set("selection",coverage);apply_pixel_lasso(canvas,true);canvas.Set("selection",selection);}var feathered=_alpha.feather(coverage,canvas.Get("selection_falloff").AsDouble());selection=_alpha.blend(canvas.Get("_pixel_alpha_base").As<Image>(),feathered,canvas.Get("selection_alpha").AsDouble(),canvas.Get("_erase_modifier").AsBool()||canvas.Get("pixel_mode").AsString()=="erase",Vector2I.Zero);canvas.Set("selection",selection);if(feathered!=coverage)feathered.Dispose();
            }
            document.Set("pixel_selection",ImageTexture.CreateFromImage(selection));document.Set("pixel_selection_owner",selected[selected.Count-1]);var owner=_documents.layer_for_id(document,selected[selected.Count-1].AsString());document.Set("pixel_selection_reference",owner!=null?Variant.From(_layers.copy_layer(owner)):default(Variant));document.Set("pixel_selection_reference_world",owner!=null?_documents.world_transform(document,owner):Transform2D.Identity);canvas.EmitSignal("gesture_finished");update_selection_preview(canvas);canvas.Set("_erase_modifier",false);canvas.Set("_points",Array.Empty<Vector2>());canvas.Set("_pixel_area_base",default(Variant));canvas.Set("_pixel_area_previous",new Rect2I());return new Settings();
        }
        var result=new Settings{["action"]=action,["point"]=point,["created"]=created,["bake"]=false};var item=canvas.Get("_paint_layer").As<Resource>();var image=canvas.Get("_paint_image").As<Image>();
        if(action=="paint"&&item!=null&&image!=null)
        {
            var properties=item.Get("properties").AsGodotDictionary();if(Get(properties,"generated_stroke",false).AsBool()){var used=image.GetUsedRect();if(used.Size.X>0&&used.Size.Y>0){image=image.GetRegion(used);canvas.Set("_paint_image",image);canvas.Set("_paint_data",image.GetData());item.Set("position",(Vector2)used.Position);item.Set("dimensions",(Vector2)used.Size);using var blank=Image.CreateEmpty(used.Size.X,used.Size.Y,false,Image.Format.Rgba8);blank.Fill(Colors.Transparent);item.Set("paint_base",ImageTexture.CreateFromImage(blank));}properties.Remove("generated_stroke");}
            replace_paint_texture(canvas);var stamps=canvas.Get("_material_stamps").As<RefCounted>();var region=canvas.Get("_material_region").As<Resource>();if(stamps!=null)_stampOperations.commit(stamps,region!);
            if(region!=null&&canvas.Get("_material_bake_after").AsBool())
            {
                canvas.Set("_material_busy",true);result["document"]=document;result["item"]=item;result["bake"]=true;var renderer=canvas.Get("repair_tool").AsGodotObject().Get("workspace").AsGodotObject().Get("renderer").AsGodotObject();renderer.Call("sync",document);
            }
            else if((canvas.Get("tool").AsString()=="eraser"||canvas.Get("_erase_modifier").AsBool())&&item.Get("live_paint").AsGodotArray().Count>0&&canvas.Get("_stroke_ink").AsGodotObject()!=null&&canvas.Get("_live_eraser").AsGodotObject()==null)
            {
                using var mask=Image.CreateEmpty(image.GetWidth(),image.GetHeight(),false,Image.Format.Rgba8);var ink=canvas.Get("_stroke_ink").As<Image>();mask.BlitRect(ink,new Rect2I(Vector2I.Zero,ink.GetSize()),canvas.Get("_ink_origin").AsVector2I());var bytes=mask.GetData();var frame=_documents.world_transform(document,item);var scale=item.Get("dimensions").AsVector2()/(Vector2)mask.GetSize();var selection=new SelectionSampler(canvas);bool selectedOnly=canvas.Get("paint_selection_only").AsBool();double opacity=canvas.Get("brush_opacity").AsDouble();for(int y=0;y<mask.GetHeight();y++)for(int x=0;x<mask.GetWidth();x++){int at=(y*mask.GetWidth()+x)*4+3;bytes[at]=Byte(bytes[at]*opacity*(selectedOnly?selection.Coverage(frame*new Vector2(x,y)*scale):1));}mask.SetData(mask.GetWidth(),mask.GetHeight(),false,Image.Format.Rgba8,bytes);_layers.erase_live_paint(item,mask);
            }
        }
        return result;
    }
    public void complete_finish(Control canvas,Settings request)
    {
        var document=canvas.Get("document").As<Resource>();if(request["bake"].AsBool())
        {
            if(document!=request["document"].AsGodotObject()||canvas.Get("_paint_layer").AsGodotObject()!=request["item"].AsGodotObject()){canvas.Set("_material_busy",false);canvas.Set("_material_region",default(Variant));return;}if(_documents.live_material_for_id(document,canvas.Get("_material_previous_template").AsString())!=null)document.Set("active_live_material_id",canvas.Get("_material_previous_template"));canvas.Set("_material_busy",false);
        }
        string action=request["action"].AsString();var point=request["point"].AsVector2();var selected=canvas.Get("selected").AsGodotArray();bool moved=canvas.Get("_moved").AsBool();if(action is "move" or "rotate" or "paint" or "vertex"||action.StartsWith("resize",StringComparison.Ordinal))
        {
            string pending=canvas.Get("_pending_single").AsString();if(action=="move"&&!moved&&pending.Length>0){canvas.EmitSignal("gesture_cancelled");SelectSingle(selected,pending);canvas.EmitSignal("selection_changed");}else if(action=="paint"||moved)canvas.EmitSignal("gesture_finished");else canvas.EmitSignal("gesture_cancelled");
        }
        else if(action=="box")
        {
            int operation=canvas.Get("_selection_operation").AsInt32();if(operation==0)selected.Clear();var start=canvas.Get("_start").AsVector2();var rect=new Rect2(start,point-start).Abs();foreach(var value in document.Get("layers").AsGodotArray()){var layer=value.As<Resource>();if(layer.Get("kind").AsString()=="group"||!_documents.can_edit(document,layer))continue;if(rect.Intersects(_documents.world_transform(document,layer)*new Rect2(Vector2.Zero,layer.Get("dimensions").AsVector2()))){var id=layer.Get("id");if(operation==-1)selected.Remove(id);else if(!selected.Contains(id))selected.Add(id);}}canvas.EmitSignal("selection_changed");
        }
        else if(action=="lasso_crop")
        {
            var points=canvas.Get("_points").AsVector2Array();if(points.Length>2){var bounds=new Rect2(points[0],Vector2.Zero);foreach(var vertex in points)bounds=bounds.Expand(vertex);canvas.EmitSignal("create_requested","lasso_crop",bounds,points);}
        }
        else if(action is "crop" or "shape"){var start=canvas.Get("_start").AsVector2();var rect=new Rect2(start,point-start).Abs();if(rect.Size.X>2&&rect.Size.Y>2)canvas.EmitSignal("create_requested",action,rect,Array.Empty<Vector2>());}
        if(canvas.Get("tool").AsString()!="path")canvas.Set("_points",Array.Empty<Vector2>());ClearPaintObjects(canvas);canvas.Set("_pending_single","");canvas.Set("_paint_created_layer",false);canvas.EmitSignal("hint_changed","");if(request["created"].AsBool())canvas.EmitSignal("selection_changed");if(canvas.Get("painting_mode").AsString()=="material")canvas.Get("repair_tool").AsGodotObject().Get("workspace").AsGodotObject().Call("_refresh_context");
    }
}
