using Godot;
using System;
public partial class ImageCanvasSelectionOperations
{
    public void set_erase_modifier(Control canvas,bool enabled)
    {
        string drag=canvas.Get("_drag").AsString();if(canvas.Get("_material_region").AsGodotObject()!=null&&drag=="paint"||canvas.Get("_erase_modifier").AsBool()==enabled)return;
        var ink=canvas.Get("_pixel_alpha_ink").As<Image>();var selection=canvas.Get("selection").As<Image>();if(drag=="pixel_select"&&ink!=null&&selection!=null){canvas.Set("_pixel_alpha_base",selection.Duplicate());ink.Fill(Colors.Transparent);}
        var image=canvas.Get("_paint_image").As<Image>();if(drag=="paint"&&image!=null)
        {
            if(canvas.Get("_corrector").AsGodotObject()!=null)flush_corrected_stroke(canvas);canvas.Set("_corrector",default(Variant));canvas.Set("_paint_data",image.GetData());canvas.Set("_stroke_base",image.Duplicate());canvas.Set("_soften_source",default(Variant));canvas.Set("_live_eraser",default(Variant));canvas.Get("_stroke_ink").As<Image>().Fill(Colors.Transparent);foreach(string key in new[]{"_stroke_dirty","_corrected_tail_bounds","_corrected_all_bounds"})canvas.Set(key,new Rect2I());canvas.Set("_corrected_started",false);canvas.Set("_corrected_stamp_distance",0.0);
            if(!enabled&&canvas.Get("tool").AsString()=="brush"&&canvas.Get("_active_mode").AsString()=="freehand"&&canvas.Get("brush_type").AsString()=="stroke_correct"&&canvas.Get("correction_strength").AsDouble()>0){var corrector=new KiwiStrokeCorrector();canvas.Set("_corrector",corrector);corrector.Call("_native").As<StrokeCorrectorKernel>().begin(canvas.Get("_last").AsVector2(),canvas.Get("correction_strength").AsDouble(),canvas.Get("brush_size").AsDouble(),Time.GetTicksUsec()/1000000.0,canvas.Get("correction_scale").AsDouble());}
        }
        canvas.Set("_erase_modifier",enabled);
    }
    public Rect2I corrected_path_bounds(Control canvas,Vector2[] path)
    {
        if(path.Length==0)return new Rect2I();var item=canvas.Get("_paint_layer").As<Resource>();var image=canvas.Get("_paint_image").As<Image>();var inverse=_documents.world_transform(canvas.Get("document").As<Resource>(),item).AffineInverse();var ratio=(Vector2)image.GetSize()/item.Get("dimensions").AsVector2();var bounds=new Rect2((inverse*path[0])*ratio,Vector2.Zero);foreach(var point in path)bounds=bounds.Expand((inverse*point)*ratio);var stamps=canvas.Get("_material_stamps").AsGodotObject();var radius=Vector2.One*canvas.Get("brush_size").AsSingle()*ratio*.5f*(stamps!=null?(float)_stampOperations.radius_factor((RefCounted)stamps):1)+Vector2.One*3;return new Rect2I((Vector2I)(bounds.Position-radius).Floor(),(Vector2I)(bounds.Size+radius*2).Ceil()).Intersection(new Rect2I(Vector2I.Zero,image.GetSize()));
    }
    public void paint_corrected_path(Control canvas,Vector2[] path,bool commit)
    {
        if(path.Length==0)return;var stamps=canvas.Get("_material_stamps").AsGodotObject();double interval=stamps!=null?_stampOperations.interval((RefCounted)stamps,canvas):Math.Max(1,canvas.Get("brush_size").AsDouble()*.15),distance=canvas.Get("_corrected_stamp_distance").AsDouble();var stamped=Vector2.Inf;if(!canvas.Get("_corrected_started").AsBool()){paint_line(canvas,path[0],path[0],false);stamped=path[0];if(commit)canvas.Set("_corrected_started",true);}var inverse=stamps!=null?_documents.world_transform(canvas.Get("document").As<Resource>(),canvas.Get("_paint_layer").As<Resource>()).AffineInverse():Transform2D.Identity;
        for(int i=1;i<path.Length;i++){if(stamps!=null)stamps.Set("direction",inverse.BasisXform(path[i]-path[i-1]).Angle());double length=path[i-1].DistanceTo(path[i]),travel=interval-distance;while(travel<=length&&length>.00001){stamped=path[i-1].Lerp(path[i],(float)(travel/length));paint_line(canvas,stamped,stamped,false);travel+=interval;}distance=(distance+length)%interval;}
        if(commit)canvas.Set("_corrected_stamp_distance",distance);else if(!stamped.IsEqualApprox(path[^1]))paint_line(canvas,path[^1],path[^1],false);
    }
    public void flush_corrected_stroke(Control canvas)
    {
        var corrector=canvas.Get("_corrector").As<RefCounted>();if(corrector==null||canvas.Get("_paint_layer").AsGodotObject()==null||canvas.Get("_paint_image").AsGodotObject()==null)return;var patch=corrector.Call("_native").As<StrokeCorrectorKernel>().update();if(patch.Count==0)return;var stamps=canvas.Get("_material_stamps").AsGodotObject();if(stamps!=null)_stampOperations.restore_tail((RefCounted)stamps);
        if(patch.TryGetValue("replace",out var replace)){var shape=replace.AsVector2Array();var area=corrected_path_bounds(canvas,shape);var all=canvas.Get("_corrected_all_bounds").AsRect2I();if(all.HasArea())area=area.Merge(all);if(!area.HasArea())return;canvas.Get("_stroke_ink").As<Image>().FillRect(area,Colors.Transparent);canvas.Set("_corrected_started",false);canvas.Set("_corrected_stamp_distance",0.0);paint_corrected_path(canvas,shape,false);canvas.Set("_stroke_dirty",area);upload_native_paint(canvas);canvas.Set("_corrected_all_bounds",area);canvas.EmitSignal("gesture_changed");return;}
        paint_corrected_path(canvas,patch["fixed"].AsVector2Array(),true);var tail=patch["tail"].AsVector2Array();var tailBounds=corrected_path_bounds(canvas,tail);var region=tailBounds;foreach(string key in new[]{"_corrected_tail_bounds","_stroke_dirty"}){var area=canvas.Get(key).AsRect2I();if(area.HasArea())region=region.HasArea()?region.Merge(area):area;}
        if(region.HasArea()){var stable=canvas.Get("_stroke_ink").As<Image>();if(stamps!=null)_stampOperations.capture_tail((RefCounted)stamps,region);using var temporary=stable.GetRegion(region);canvas.Set("_stroke_ink",temporary);canvas.Set("_ink_origin",region.Position);try{paint_corrected_path(canvas,tail,false);canvas.Set("_stroke_dirty",region);upload_native_paint(canvas);}finally{canvas.Set("_stroke_ink",stable);canvas.Set("_ink_origin",Vector2I.Zero);}}
        canvas.Set("_corrected_tail_bounds",tailBounds);if(region.HasArea()){var all=canvas.Get("_corrected_all_bounds").AsRect2I();canvas.Set("_corrected_all_bounds",all.HasArea()?all.Merge(region):region);}canvas.EmitSignal("gesture_changed");
    }
    public void confirm_stroke(Control canvas){if(canvas.Get("_drag").AsString() is not ("shape_stroke" or "stroke_edit"))return;var path=shape_path(canvas);for(int i=1;i<path.Length;i++)paint_line(canvas,path[i-1],path[i],false);if(canvas.Get("_erase_modifier").AsBool())upload_paint(canvas);else upload_native_paint(canvas);canvas.Set("_drag","paint");canvas.Call("_finish",canvas.Get("_shape_end"));}
    public void paint_curve(Control canvas,Vector2 from,Vector2 control,Vector2 to){var previous=from;for(int i=0;i<33;i++){float t=i/32f;var next=from*(1-t)*(1-t)+control*2*(1-t)*t+to*t*t;paint_line(canvas,previous,next,false);previous=next;}upload_native_paint(canvas);}
    public Vector2 curve_control(Control canvas,Vector2 from,Vector2 to)
    {
        var points=canvas.Get("_stroke_points").AsVector2Array();if(points.Length<2||from.DistanceSquaredTo(to)<1)return from.Lerp(to,.5f);var chord=to-from;float length=chord.LengthSquared(),distance=-1,bestT=.5f;var best=from.Lerp(to,.5f);foreach(var point in points){float t=Math.Clamp((point-from).Dot(chord)/length,.12f,.88f),next=point.DistanceSquaredTo(from+chord*t);if(next>distance){distance=next;best=point;bestT=t;}}float inverse=2*(1-bestT)*bestT;return(best-from*(1-bestT)*(1-bestT)-to*bestT*bestT)/Math.Max(inverse,.001f);
    }
}
