using Godot;
using System;
using System.Collections.Generic;
using System.Linq;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class EnvironmentBiomeTool : RefCounted
{
    private readonly TerrainBiomeOperations _biomes=new();
    private static Variant Get(Settings values,string key,Variant fallback=default)=>values.TryGetValue(key,out var value)?value:fallback;
    private static Control? Canvas(RefCounted tool)=>tool.Get("canvas").As<Control>();
    private static Settings Stroke(RefCounted tool)=>tool.Get("_stroke").AsGodotDictionary();
    public Settings target(RefCounted tool)
    {
        var canvas=Canvas(tool);var session=canvas?.Call("environment_session").As<RefCounted>();if(session==null)return new Settings();var selected=session.Call("primary").As<Resource>();if(selected==null)return new Settings();var terrain=session.Call("environment").As<Resource>().Call("terrain",selected.Get("id")).As<Resource>();
        if(terrain==null||terrain.Get("biomes").As<Resource>() is not Resource biomes||terrain.Get("biome_data").AsGodotDictionary().Count==0)return new Settings();string id=tool.Get("biome_id").AsString();
        foreach(var entry in biomes.Get("definitions").AsGodotArray()){var definition=entry.AsGodotDictionary();if(!Get(definition,"enabled",true).AsBool()||Get(definition,"domain","surface").AsString()!="surface")continue;if(id.Length==0||definition["id"].AsString()==id){tool.Set("biome_id",definition["id"]);return new Settings {["id"]=selected.Get("id"),["terrain"]=terrain};}}return new Settings();
    }
    public bool input(RefCounted tool,InputEvent inputEvent)
    {
        var canvas=Canvas(tool);if(canvas==null)return false;string mode=canvas.Get("environment_tool").AsString();if(mode is not ("Paint biome" or "Erase biome"))return false;var stroke=Stroke(tool);
        if(stroke.Count>0&&((inputEvent is InputEventKey key&&key.Pressed&&(key.Keycode==Key.Escape||key.CtrlPressed&&key.Keycode is Key.Z or Key.Y))||(inputEvent is InputEventMouseButton right&&right.Pressed&&right.ButtonIndex==MouseButton.Right))){cancel(tool);return true;}
        if(canvas.Get("_navigating").AsBool()||canvas.Get("_panning").AsBool()||canvas.Get("_orbiting").AsBool())return false;
        if(inputEvent is InputEventMouseMotion motion)
        {
            var hit=canvas.Call("pick_terrain",motion.Position).AsGodotDictionary();canvas.Set("_brush_hit",hit);if(stroke.Count>0&&hit.Count>0&&hit["id"].AsString()==stroke["id"].AsString())dab(tool,hit["local"].AsVector3(),motion.CtrlPressed,false);canvas.Get("overlay").As<Control>().QueueRedraw();return Stroke(tool).Count>0;
        }
        if(inputEvent is not InputEventMouseButton button||button.ButtonIndex!=MouseButton.Left)return false;
        if(!button.Pressed){if(stroke.Count==0)return false;cancel(tool);if(stroke["changed"].AsBool())canvas.EmitSignal("biomes_replaced",stroke["id"].AsString(),stroke["source"]);canvas.EmitSignal("gesture_finished");return true;}
        var info=target(tool);var picked=canvas.Call("pick_terrain",button.Position).AsGodotDictionary();canvas.Set("_brush_hit",picked);if(info.Count==0||picked.Count==0||picked["id"].AsString()!=info["id"].AsString())return false;
        canvas.GrabFocus();var terrain=info["terrain"].As<Resource>();var source=terrain.Get("biomes").As<Resource>().Duplicate(true);string biome=tool.Get("biome_id").AsString();var masks=source.Get("paint_masks").AsGodotDictionary();var mask=Get(masks,biome,Array.Empty<float>()).AsFloat32Array();int n=terrain.Get("resolution").AsInt32();
        if(mask.Length!=n*n)
        {
            int old=(int)Math.Round(Math.Sqrt(mask.Length),MidpointRounding.AwayFromZero);
            if(mask.Length>0&&old*old==mask.Length)
            {var bytes=new byte[mask.Length*sizeof(float)];Buffer.BlockCopy(mask,0,bytes,0,bytes.Length);using var image=Image.CreateFromData(old,old,false,Image.Format.Rf,bytes);image.Resize(n,n,Image.Interpolation.Bilinear);bytes=image.GetData();mask=new float[n*n];Buffer.BlockCopy(bytes,0,mask,0,bytes.Length);}
            else mask=new float[n*n];
        }
        masks[biome]=mask;var original=terrain.Get("biome_data").AsGodotDictionary().Duplicate();var weights=new Settings();foreach(var entry in original["weights"].AsGodotDictionary())weights[entry.Key]=entry.Value.AsFloat32Array();original["weights"]=weights;var point=picked["local"].AsVector3();
        tool.Set("_stroke",new Settings {["id"]=info["id"],["terrain"]=terrain,["source"]=source,["original"]=original,["noises"]=_biomes.noise_fields(source,terrain.Get("seed").AsInt64(),"surface"),["last"]=new Vector2(point.X,point.Z),["changed"]=false,["revision"]=0});canvas.Set("_painting",true);dab(tool,point,button.CtrlPressed,true);return true;
    }
    public void dab(RefCounted tool,Vector3 point,bool invert,bool first)
    {
        var canvas=Canvas(tool)!;var stroke=Stroke(tool);var terrain=stroke["terrain"].As<Resource>();var source=stroke["source"].As<Resource>();var center=new Vector2(point.X,point.Z);var last=stroke["last"].AsVector2();double radius=Math.Max(.01,canvas.Get("brush_radius").AsDouble()),spacing=Math.Max(.01,canvas.Get("brush_radius").AsDouble()*canvas.Get("brush_spacing").AsDouble());
        if(!first&&center.DistanceTo(last)<spacing)return;int count=Math.Clamp((int)Math.Ceiling(center.DistanceTo(last)/spacing),1,32);var changed=new HashSet<int>();string biome=tool.Get("biome_id").AsString();var masks=source.Get("paint_masks").AsGodotDictionary();var mask=masks[biome].AsFloat32Array();bool erase=(canvas.Get("environment_tool").AsString()=="Erase biome")!=invert;
        int n=terrain.Get("resolution").AsInt32();var dimensions=terrain.Get("dimensions").AsVector2();bool symmetryX=canvas.Get("brush_symmetry_x").AsBool(),symmetryZ=canvas.Get("brush_symmetry_z").AsBool(),square=canvas.Get("brush_square").AsBool();double strength=canvas.Get("brush_strength").AsDouble(),falloff=Math.Max(.01,canvas.Get("brush_falloff").AsDouble());
        for(int index=1;index<=count;index++)
        {
            var p=last.Lerp(center,index/(float)count);var centers=new List<Vector2>{p};var reflected=new Vector2(-p.X,p.Y);if(symmetryX&&!centers.Contains(reflected))centers.Add(reflected);if(symmetryZ)foreach(var existing in centers.ToArray()){reflected=new Vector2(existing.X,-existing.Y);if(!centers.Contains(reflected))centers.Add(reflected);}
            foreach(var at in centers)
            {
                var grid=(at/dimensions+Vector2.One*.5f)*(n-1);var extent=Vector2.One*(float)radius/(dimensions/(n-1));var low=(grid-extent).Floor();var high=(grid+extent).Ceil();
                for(int z=Math.Max(0,(int)low.Y);z<=Math.Min(n-1,(int)high.Y);z++)for(int x=Math.Max(0,(int)low.X);x<=Math.Min(n-1,(int)high.X);x++)
                {
                    var offset=new Vector2((float)((x/(double)(n-1)-.5)*dimensions.X),(float)((z/(double)(n-1)-.5)*dimensions.Y))-at;double distance=square?Math.Max(Math.Abs(offset.X),Math.Abs(offset.Y)):offset.Length();if(distance>radius)continue;int sample=x+z*n;
                    double value=Math.Clamp(mask[sample]+strength*Math.Pow(Math.Max(0,1-distance/radius),falloff)*(erase?-1:1),0,1);if(Mathf.IsEqualApprox(value,mask[sample]))continue;mask[sample]=(float)value;changed.Add(sample);
                }
            }
        }
        masks[biome]=mask;stroke["last"]=center;if(changed.Count==0)return;stroke["changed"]=true;long revision=tool.Get("_preview_revision").AsInt64()+1;tool.Set("_preview_revision",revision);
        var indices=new GArray();foreach(int index in changed)indices.Add(index);_biomes.refresh_samples(source,terrain,indices,stroke["noises"].AsGodotDictionary());terrain.Get("biome_data").AsGodotDictionary()["preview_revision"]=revision;canvas.Call("request_sync");
    }
    public void cancel(RefCounted tool)
    {
        var stroke=Stroke(tool);if(stroke.Count==0)return;stroke["terrain"].As<Resource>().Set("biome_data",stroke["original"]);tool.Set("_stroke",new Settings());var canvas=Canvas(tool)!;canvas.Set("_painting",false);canvas.Call("request_sync");canvas.Get("overlay").As<Control>().QueueRedraw();
    }
}
