using Godot;
using System;
using System.Linq;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class TransformationMorphCacheOperations : RefCounted
{
    private static Texture2D Artwork(Resource state)=>state.Get("artwork").AsGodotObject().Get("texture").As<Texture2D>();
    public string signature(Resource first,Resource last,Resource? key)
    {var pointsA=key!=null?key.Get("points_a"):Variant.From(new GArray());var pointsB=key!=null?key.Get("points_b"):Variant.From(new GArray());var settings=key!=null?key.Call("settings"):Variant.From(new Settings());return first.Get("id").AsString()+"/"+last.Get("id").AsString()+"/"+Artwork(first).GetInstanceId()+"/"+Artwork(last).GetInstanceId()+"/"+unchecked((uint)GD.Hash(new GArray {pointsA,pointsB,settings}));}
    public Image? analysis_image(Texture2D texture,int limit)
    {using var source=texture.GetImage();if(source==null||source.IsEmpty())return null;var image=(Image)source.Duplicate();double scale=Math.Min(1,(double)limit/Math.Max(image.GetWidth(),image.GetHeight()));if(scale<1)image.Resize(Math.Max(1,(int)Math.Round(image.GetWidth()*scale,MidpointRounding.AwayFromZero)),Math.Max(1,(int)Math.Round(image.GetHeight()*scale,MidpointRounding.AwayFromZero)),Image.Interpolation.Bilinear);return image;}
    public Settings get_pair(Node owner,Resource first,Resource last,Resource? key)
    {
        string id=signature(first,last,key);var entries=owner.Get("entries").AsGodotDictionary();if(entries.TryGetValue(id,out var existing))return existing.AsGodotDictionary();var requests=owner.Get("requests").AsGodotArray();bool queued=false;foreach(var raw in requests)if(raw.AsGodotDictionary()["id"].AsString()==id){queued=true;break;}if(owner.Get("active").AsString()!=id&&!queued){while(requests.Count>=8)requests.RemoveAt(0);bool high=key!=null&&key.Get("quality").AsString()=="High";string baseId=Artwork(first).GetInstanceId()+"/"+Artwork(last).GetInstanceId()+"/"+(high?"true":"false");requests.Add(new Settings {["id"]=id,["base_id"]=baseId,["a"]=Variant.From(analysis_image(Artwork(first),high?192:128)),["b"]=Variant.From(analysis_image(Artwork(last),high?192:128)),["pa"]=key!=null?key.Get("points_a"):Variant.From(Array.Empty<Vector2>()),["pb"]=key!=null?key.Get("points_b"):Variant.From(Array.Empty<Vector2>()),["settings"]=key!=null?key.Call("settings"):Variant.From(new Settings())});}return new Settings();
    }
    public void process(Node owner)
    {
        var worker=owner.Get("worker").As<Godot.GodotThread>();var entries=owner.Get("entries").AsGodotDictionary();var cache=owner.Get("basis_cache").AsGodotDictionary();if(worker!=null){if(worker.IsAlive())return;var result=worker.WaitToFinish().AsGodotDictionary();owner.Set("preparation_usec",owner.Get("preparation_usec").AsInt64()+(result.TryGetValue("analysis_us",out var elapsed)?elapsed.AsInt64():0));foreach(string name in new[]{"field_a","field_b"})if(result.TryGetValue(name,out var raw)&&raw.VariantType==Variant.Type.Object&&raw.AsGodotObject() is Image image)result[name]=ImageTexture.CreateFromImage(image);if(result.TryGetValue("basis",out var saved)){var basis=saved.AsGodotDictionary();basis["field_a"]=result["field_a"];basis["field_b"]=result["field_b"];cache[owner.Get("active_basis")]=basis;result.Remove("basis");Trim(cache,8);}entries[owner.Get("active")]=result;owner.Set("worker",default(Variant));owner.Set("active","");worker.Dispose();owner.EmitSignal("prepared");Trim(entries,24);}
        var requests=owner.Get("requests").AsGodotArray();if(requests.Count==0)return;var task=requests[0].AsGodotDictionary();requests.RemoveAt(0);owner.Set("active",task["id"]);owner.Set("active_basis",task["base_id"]);worker=new Godot.GodotThread();owner.Set("worker",worker);owner.Set("analysis_count",owner.Get("analysis_count").AsInt64()+1);var basisForTask=cache.TryGetValue(task["base_id"],out var found)?found.AsGodotDictionary():new Settings();if(basisForTask.Count==0)owner.Set("field_analysis_count",owner.Get("field_analysis_count").AsInt64()+1);
        var error=worker.Start(Callable.From<Settings>(()=>{using var morph=new TransformationMorphOperations();return morph.prepare(task["a"].As<Image>(),task["b"].As<Image>(),task["pa"].AsVector2Array(),task["pb"].AsVector2Array(),task["settings"].AsGodotDictionary(),basisForTask);}));if(error!=Error.Ok){entries[owner.Get("active")]=new Settings {["valid"]=false,["empty_a"]=false,["empty_b"]=false,["reason"]="Morph preparation unavailable: crossfade fallback."};owner.Set("worker",default(Variant));owner.Set("active","");worker.Dispose();owner.EmitSignal("prepared");}
    }
    private static void Trim(Settings entries,int count){while(entries.Count>count)entries.Remove(entries.Keys.First());}
    public void exit_tree(Node owner){var worker=owner.Get("worker").As<Godot.GodotThread>();if(worker!=null){worker.WaitToFinish();owner.Set("worker",default(Variant));worker.Dispose();}}
}
