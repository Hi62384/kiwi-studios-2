using Godot;
using System.Collections.Generic;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class AudioJobsOperations : RefCounted
{
    internal static void DiscardUndeliveredResult(Variant result)
    {
        if (result.VariantType != Variant.Type.Dictionary) return;
        var values = result.AsGodotDictionary();
        if (values.TryGetValue("staged", out var staged) && staged.VariantType == Variant.Type.Object
            && staged.AsGodotObject() is KiwiAudioPortableStage stage)
            stage.release();
    }

    public void request(Node owner,string kind,Variant operation,long generation,bool replace)
    {
        var queue=owner.Get("_queue").AsGodotArray();var current=owner.Get("_current").AsGodotDictionary();if(replace){for(int index=queue.Count-1;index>=0;index--)if(queue[index].AsGodotDictionary()["kind"].AsString()==kind)queue.RemoveAt(index);if(current.TryGetValue("kind",out var active)&&active.AsString()==kind)current["work"].AsGodotObject().Call("cancel");}queue.Add(new Settings {["kind"]=kind,["operation"]=operation,["generation"]=generation,["work"]=owner.Call("_new_work")});
    }
    public void cancel_kind(Node owner,string kind)
    {
        var queue=owner.Get("_queue").AsGodotArray();for(int index=queue.Count-1;index>=0;index--)if(queue[index].AsGodotDictionary()["kind"].AsString()==kind)queue.RemoveAt(index);var current=owner.Get("_current").AsGodotDictionary();if(current.TryGetValue("kind",out var active)&&active.AsString()==kind)current["work"].AsGodotObject().Call("cancel");
    }
    public bool busy(Node owner)=>owner.Get("_thread").AsGodotObject()!=null||owner.Get("_queue").AsGodotArray().Count>0;
    public void cancel_all(Node owner){owner.Get("_queue").AsGodotArray().Clear();var current=owner.Get("_current").AsGodotDictionary();if(current.Count>0)current["work"].AsGodotObject().Call("cancel");}
    public void process(Node owner)
    {
        var thread=owner.Get("_thread").As<GodotThread>();var current=owner.Get("_current").AsGodotDictionary();if(thread!=null){var status=current["work"].AsGodotObject().Call("status").AsGodotDictionary();owner.EmitSignal("progress_changed",status["progress"],status["description"]);if(thread.IsAlive())return;var result=thread.WaitToFinish();var entry=current;owner.Set("_thread",default(Variant));owner.Set("_current",new Settings());thread.Dispose();if(!entry["work"].AsGodotObject().Call("is_cancelled").AsBool()&&owner.GetSignalConnectionList("completed").Count>0)owner.EmitSignal("completed",entry["kind"],entry["generation"],result);else DiscardUndeliveredResult(result);}var queue=owner.Get("_queue").AsGodotArray();if(owner.Get("_thread").AsGodotObject()==null&&queue.Count>0){current=queue[0].AsGodotDictionary();queue.RemoveAt(0);owner.Set("_current",current);thread=new GodotThread();owner.Set("_thread",thread);var error=(Error)owner.Call("_start_work",thread,current["operation"],current["work"]).AsInt32();if(error!=Error.Ok){owner.EmitSignal("completed",current["kind"],current["generation"],new Settings {["error"]="Could not start audio worker."});owner.Set("_thread",default(Variant));owner.Set("_current",new Settings());thread.Dispose();}}
    }
    public void exit_tree(Node owner){cancel_all(owner);var thread=owner.Get("_thread").As<GodotThread>();if(thread!=null){var result=thread.WaitToFinish();DiscardUndeliveredResult(result);thread.Dispose();}owner.Set("_thread",default(Variant));owner.Set("_current",new Settings());}
}
