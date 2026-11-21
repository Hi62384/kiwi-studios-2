using Godot;
using System;
using System.Collections.Generic;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;
public partial class ImageRepairInteractionOperations
{
    public bool handle(RefCounted owner,InputEvent input)
    {
        var canvas=Canvas(owner);var config=Config(owner);var material=owner.Get("material").As<Resource>();
        if(input is InputEventMouseMotion motion)
        {
            if(canvas.Get("_drag").AsString()=="pan")return false;canvas.Set("_mouse",motion.Position);var source=owner.Get("source_image").As<Image>();
            if(owner.Get("sampling").AsBool()&&source!=null)
            {
                var item=layer(owner);var p=canvas.Call("to_document",motion.Position).AsVector2();if(item!=null&&config["sample_mode"].AsString()=="current")p=to_pixel(owner,p,item);var start=owner.Get("_sample_start").AsVector2();if(start.DistanceTo(p)>=2)owner.Set("_sample_region_dragged",true);
                if(owner.Get("_patch_drag").AsBool()){var patch=owner.Get("_patch_rect").AsRect2I();var shifted=new Rect2I(patch.Position+(Vector2I)(p-start).Round(),patch.Size);var area=shifted.Intersection(new Rect2I(Vector2I.Zero,source.GetSize()));owner.Set("source_area",area);owner.Set("source_point",((Rect2)area).GetCenter());canvas.QueueRedraw();refresh_selection_preview(owner);return true;}
                var points=new List<Vector2>(owner.Get("source_points").AsVector2Array()){p};owner.Set("source_points",points.ToArray());owner.Set("source_area",new Rect2I((Vector2I)start.Min(p),(Vector2I)(start-p).Abs().Ceil()).Intersection(new Rect2I(Vector2I.Zero,source.GetSize())));
            }
            else if(owner.Get("active").AsBool()&&!owner.Get("ending").AsBool()&&!owner.Get("selection_preview").AsBool())
            {
                var item=owner.Get("_owner").As<Resource>();var point=to_pixel(owner,canvas.Call("to_document",motion.Position).AsVector2(),item);var last=owner.Get("_last").AsVector2();float distance=point.DistanceTo(last);int steps=Math.Clamp(Mathf.CeilToInt(distance/Math.Max(1,config["size"].AsDouble()*.2)),1,128);
                if(owner.Get("main_mode").AsString()=="texture"&&material.Get("application").AsString()!="continuous"){double spacing=Math.Max(1,config["size"].AsDouble()*material.Get("spacing").AsDouble());if(distance<spacing){canvas.QueueRedraw();return true;}steps=Math.Clamp(Mathf.FloorToInt(distance/spacing),1,128);}
                var points=new List<Vector2>(owner.Get("_points").AsVector2Array());var pressures=new List<float>(owner.Get("_pressures").AsFloat32Array());for(int i=1;i<=steps;i++){points.Add(last.Lerp(point,(float)i/steps));pressures.Add(motion.PenInverted||motion.Pressure>0?motion.Pressure:1);}
                owner.Set("_points",points.ToArray());owner.Set("_pressures",pressures.ToArray());owner.Set("_last",point);owner.Set("_pending",true);
                if(owner.Get("_editable_texture").AsBool()&&material.Get("alignment").AsString()=="stroke"&&material.Get("follow_direction").AsBool()&&points.Count>1){var current=item.Get("properties").AsGodotDictionary()["texture_material"].As<Resource>();double direction=(points[^1]-points[^2]).Angle()+Mathf.DegToRad(material.Get("rotation").AsDouble());current.Set("rotation",Mathf.RadToDeg(Mathf.LerpAngle(Mathf.DegToRad(current.Get("rotation").AsDouble()),direction,1-material.Get("direction_smoothing").AsDouble()*.95)));}
            }
            canvas.QueueRedraw();return true;
        }
        if(input is not InputEventMouseButton button)return false;canvas.Set("_mouse",button.Position);
        if(button.ButtonIndex is MouseButton.WheelUp or MouseButton.WheelDown){if(button.Pressed&&button.ShiftPressed){config["size"]=Math.Clamp(config["size"].AsDouble()*(button.ButtonIndex==MouseButton.WheelUp?1.1:1/1.1),2,1024);owner.EmitSignal("settings_changed");return true;}return false;}
        if(button.ButtonIndex==MouseButton.Middle||Input.IsKeyPressed(Key.Space))return false;
        if(button.ButtonIndex==MouseButton.Right&&button.Pressed){cancel(owner);owner.Set("sampling",false);return true;}if(button.ButtonIndex!=MouseButton.Left)return false;
        if(!button.Pressed)
        {
            owner.Set("_sample_down",false);if(owner.Get("sampling").AsBool()){owner.Set("sampling",false);owner.Set("_patch_drag",false);var area=owner.Get("source_area").AsRect2I();if(area.Size.X<2||area.Size.Y<2){int extent=Math.Max(2,config["sample_size"].AsInt32());owner.Set("source_area",new Rect2I((Vector2I)owner.Get("source_point").AsVector2()-Vector2I.One*extent/2,Vector2I.One*extent).Intersection(new Rect2I(Vector2I.Zero,owner.Get("source_image").As<Image>().GetSize())));}else if(owner.Get("_sample_region_dragged").AsBool())owner.Set("source_point",((Rect2)area).GetCenter());refresh_selection_preview(owner);owner.EmitSignal("settings_changed");return true;}
            if(owner.Get("selection_preview").AsBool())return true;finish(owner);return true;
        }
        if(owner.Get("selection_preview").AsBool()&&owner.Get("active").AsBool()&&!button.AltPressed&&!owner.Get("pick_source").AsBool())return true;
        var target=layer(owner);if(target==null||!_documents.can_edit(canvas.Get("document").As<Resource>(),target)){canvas.EmitSignal("hint_changed","Select an unlocked raster layer");return true;}
        if(target.Get("texture").AsGodotObject()==null||Array.IndexOf(new[]{"image","paint","basic"},target.Get("kind").AsString())<0){canvas.EmitSignal("hint_changed","Rasterize this layer to repair individual pixels");return true;}
        if(target.Get("warp").AsGodotObject()!=null){canvas.EmitSignal("hint_changed","Bake the layer's warp before repairing its pixels");return true;}
        bool texture=owner.Get("main_mode").AsString()=="texture";if(!texture&&Get(target.Get("properties").AsGodotDictionary(),"texture_material").AsGodotObject()!=null){canvas.EmitSignal("hint_changed","Bake this material layer before repairing pixels");return true;}
        var documentPoint=canvas.Call("to_document",button.Position).AsVector2();
        if(!texture&&(button.AltPressed||owner.Get("pick_source").AsBool()))
        {
            owner.Set("pick_source",false);owner.Set("_sample_down",true);if(owner.Get("mode").AsString()=="patch"&&config["source_mode"].AsString()=="manual"&&config["sample_mode"].AsString()=="current"&&canvas.Get("selection").AsGodotObject()!=null){owner.Call("begin_patch_source",documentPoint,target);return true;}owner.Call("sample_source",documentPoint);return true;
        }
        if(texture){owner.Set("mode","pattern_fill");if(owner.Get("source_image").AsGodotObject()==null){owner.Call("refresh_material");canvas.EmitSignal("hint_changed","Preparing material…");return true;}}
        else owner.Set("mode",owner.Get("repair_source").AsString()=="nearby"?"spot":owner.Get("repair_method").AsString()=="exact"?"clone":"heal");
        string mode=owner.Get("mode").AsString();if(mode=="procedural"){var recipe=owner.Get("recipe").As<Resource>();long key=GD.Hash(new GArray{recipe.Get("kind"),recipe.Get("settings")});if(owner.Get("_cached_procedural").AsGodotObject()==null||key!=owner.Get("_procedural_key").AsInt64()){canvas.EmitSignal("hint_changed","Generate the procedural texture preview first");generate(owner,"");return true;}var source=owner.Get("_cached_procedural").As<Image>();owner.Set("source_image",source);owner.Set("source_area",new Rect2I(Vector2I.Zero,source.GetSize()));}
        if((mode is "clone" or "heal" or "pattern_fill")&&owner.Get("source_image").AsGodotObject()==null){canvas.EmitSignal("hint_changed","Alt-click to sample a source, or load a pattern");return true;}begin(owner,target,to_pixel(owner,documentPoint,target),false);return true;
    }
}
