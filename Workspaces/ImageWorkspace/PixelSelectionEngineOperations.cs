using Godot;
using System;
using Settings=Godot.Collections.Dictionary;
public partial class PixelSelectionEngineOperations:RefCounted
{
    private static Variant Get(Settings data,string key,Variant fallback=default)=>data.TryGetValue(key,out var value)?value:fallback;
    public void prepare(Node owner,Image image,Rect2I area)
    {
        long generation=owner.Get("_generation").AsInt64()+1;owner.Set("_generation",generation);owner.Set("_request",owner.Get("_request").AsInt64()+1);owner.Set("source",image);owner.Set("domain",area);owner.Set("edges",default(Variant));owner.Set("objects",default(Variant));owner.Set("_pending",new Settings{["kind"]="analyze",["generation"]=generation,["image"]=image,["domain"]=area});
    }
    public void invalidate(Node owner){owner.Set("_generation",owner.Get("_generation").AsInt64()+1);owner.Set("_request",owner.Get("_request").AsInt64()+1);owner.Get("_pending").AsGodotDictionary().Clear();foreach(string key in new[]{"edges","objects","source"})owner.Set(key,default(Variant));}
    public void cancel_request(Node owner){owner.Set("_request",owner.Get("_request").AsInt64()+1);var pending=owner.Get("_pending").AsGodotDictionary();if(Get(pending,"kind","").AsString()!="analyze")pending.Clear();}
    public long request(Node owner,string kind,Vector2 seed,double threshold,double width,Settings coverage)
    {
        long token=owner.Get("_request").AsInt64()+1;owner.Set("_request",token);owner.Set("_pending",new Settings{["kind"]=kind,["generation"]=owner.Get("_generation"),["request"]=token,["seed"]=seed,["threshold"]=threshold,["width"]=width,["coverage"]=coverage});return token;
    }
    public void process(Node owner)
    {
        var thread=owner.Get("_thread").As<GodotThread>();if(thread!=null&&!thread.IsAlive()){using var completed=thread.WaitToFinish();var result=completed.AsGodotDictionary();owner.Set("_thread",default(Variant));thread.Dispose();thread=null;var job=owner.Get("_job").AsGodotDictionary();if(job["generation"].AsInt64()==owner.Get("_generation").AsInt64()){string kind=job["kind"].AsString();if(kind=="analyze"){owner.Set("edges",result["edges"]);owner.Set("objects",result["objects"]);owner.EmitSignal("analyzed");}else{if(result.ContainsKey("objects"))owner.Set("objects",result["objects"]);if(job["request"].AsInt64()==owner.Get("_request").AsInt64())owner.EmitSignal("proposed",Get(result,"mask"),kind,owner.Get("_request"));}}}var pending=owner.Get("_pending").AsGodotDictionary();var source=owner.Get("source").As<Image>();var edges=owner.Get("edges").AsGodotObject();if(thread!=null||pending.Count==0&&(source==null||edges!=null))return;var domain=owner.Get("domain").AsRect2I();if(source==null||!domain.HasArea()){pending.Clear();return;}Settings next;if(edges==null){next=new Settings{["kind"]="analyze",["generation"]=owner.Get("_generation")};if(Get(pending,"kind","").AsString()=="analyze")pending.Clear();}else{next=pending;owner.Set("_pending",new Settings());}next["image"]=source;next["domain"]=domain;next["edges"]=owner.Get("edges");next["objects"]=owner.Get("objects");owner.Set("_job",next);thread=new GodotThread();owner.Set("_thread",thread);thread.Start(Callable.From<Variant>(()=>work(next)));
    }
    public Settings work(Settings job)
    {
        string kind=job["kind"].AsString();if(kind=="analyze"){var field=new KiwiPixelEdgeField();field.Call("build",job["image"],job["domain"]);return new Settings{["edges"]=field,["objects"]=default(Variant)};}if(kind=="object"){var segmenter=job["objects"].As<RefCounted>();if(segmenter==null){segmenter=new KiwiPixelObjectSegmenter();segmenter.Call("build",job["image"],job["domain"]);}var proposed=segmenter.Call("propose",job["seed"],job["threshold"]).As<Image>();var finished=finish_mask(proposed,job);return new Settings{["mask"]=finished==null?default(Variant):Variant.From(finished),["objects"]=segmenter};}var magnet=new KiwiPixelEdgeMagnet();magnet.Set("field",job["edges"]);using var paths=new PixelEdgeMagnetOperations();var path=paths.connected(magnet,job["seed"].AsVector2(),job["threshold"].AsDouble());if(path.Length==0)return new Settings();var domain=job["domain"].AsRect2I();var mask=Image.CreateEmpty(domain.Size.X,domain.Size.Y,false,Image.Format.Rgba8);for(int index=0;index<path.Length;index++)path[index]-=(Vector2)domain.Position;paths.paint_band(mask,path,job["width"].AsDouble(),new Rect2I(Vector2I.Zero,domain.Size),Colors.White,false);var result=finish_mask(mask,job);return new Settings{["mask"]=result==null?default(Variant):Variant.From(result)};
    }
    public Image? finish_mask(Image? mask,Settings job)
    {
        var coverage=Get(job,"coverage",new Settings()).AsGodotDictionary();if(mask==null||coverage.Count==0)return mask;using var alpha=new PixelSelectionAlphaOperations();var feathered=alpha.feather(mask,coverage["falloff"].AsDouble());var result=alpha.blend(coverage["base"].As<Image>(),feathered,coverage["alpha"].AsDouble(),coverage["subtract"].AsBool(),coverage["origin"].AsVector2I());if(feathered.GetInstanceId()!=mask.GetInstanceId())feathered.Dispose();return result;
    }
    public void exit_tree(Node owner){var thread=owner.Get("_thread").As<GodotThread>();if(thread==null)return;using var result=thread.WaitToFinish();owner.Set("_thread",default(Variant));thread.Dispose();}
}
