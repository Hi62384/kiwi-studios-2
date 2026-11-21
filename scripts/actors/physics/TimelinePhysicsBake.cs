using Godot;
using System;
using GArray=Godot.Collections.Array;
using Settings=Godot.Collections.Dictionary;
public partial class TimelinePhysicsOperations
{
    private static bool BakeEditorValid(Control editor,RefCounted model)=>GodotObject.IsInstanceValid(editor)&&editor.IsInsideTree()&&editor.Get("model").AsGodotObject()==model;
    public Settings bake_begin(RefCounted owner,Control editor,Resource actor,double start,double end)
    {
        string error=!double.IsFinite(start)||!double.IsFinite(end)||end<=start||start<0?"Choose a valid non-negative bake interval.":owner.Get("_baking_actor").AsString().Length>0||Map(owner,"_baking_actors").Count>0?"A physics bake is already running.":"";double requestedCount=Math.Ceiling((end-start)*owner.Get("rate").AsDouble())+1;int count=double.IsFinite(requestedCount)&&requestedCount>=0&&requestedCount<=4096?(int)requestedCount:4097;if(error.Length==0&&count>4096)error="Bake at most 4,096 fixed-step frames per interval.";var job=new Settings{["error"]=error};if(error.Length>0)return job;var canvas=editor.Get("canvas").AsGodotObject();job["model"]=editor.Get("model");job["actor"]=actor;job["start"]=start;job["end"]=end;job["count"]=count;job["saved_time"]=canvas.Get("playhead");job["saved_playing"]=editor.Get("playing");job["frames"]=new GArray();job["expected"]="";job["bytes"]=0;editor.Set("playing",false);owner.Set("_baking_actor",actor.Get("id"));owner.Set("signature","");mark_dirty(owner);return job;
    }
    public bool bake_valid(Control editor,Settings job){var model=job["model"].As<RefCounted>();var actor=job["actor"].As<Resource>();return BakeEditorValid(editor,model)&&model.Call("actor_for_id",actor.Get("id")).AsGodotObject()==actor;}
    public void bake_seek(RefCounted owner,Control editor,Settings job,int index){editor.Get("canvas").AsGodotObject().Set("playhead",Math.Min(job["end"].AsDouble(),job["start"].AsDouble()+index/owner.Get("rate").AsDouble()));editor.Call("_evaluate_runtimes");}
    public string bake_sample(RefCounted owner,Settings job)
    {
        string signature=owner.Get("signature").AsString();if(job["expected"].AsString().Length==0)job["expected"]=signature;if(signature!=job["expected"].AsString())return "Scene changed during bake; no bake was saved.";string id=job["actor"].As<Resource>().Get("id").AsString();if(!Map(owner,"display_states").ContainsKey(id))return "Enable physics before baking.";var frame=snapshot(new Settings{[id]=Map(owner,"display_states")[id]})[id];long bytes=job["bytes"].AsInt64()+GD.VarToBytes(frame).Length;job["bytes"]=bytes;if(bytes>67108864)return "Bake exceeds the 64 MiB per-actor limit. Shorten the interval or lower simulation resolution.";job["frames"].AsGodotArray().Add(frame);return "";
    }
    private void BakeHistory(RefCounted model,Resource actor,Settings before,Settings after){var history=model.Get("history").As<UndoRedo>();var action=new PhysicsSettingsHistoryAction(model,actor,before,after);history.AddDoMethod(new Callable(action,nameof(PhysicsSettingsHistoryAction.restore_after)));history.AddUndoMethod(new Callable(action,nameof(PhysicsSettingsHistoryAction.restore_before)));history.AddDoReference(action);}
    public string bake_finish(RefCounted owner,Control editor,Settings job,string error)
    {
        if(!bake_valid(editor,job)){owner.Set("_baking_actor","");return "Scene closed or changed during bake; nothing was saved.";}var actor=job["actor"].As<Resource>();var before=_settings.authored(actor);var model=job["model"].As<RefCounted>();if(error.Length==0){int mode=before["mode"].AsInt32(),source=mode is 3 or 4?Get(before["bake"].AsGodotDictionary(),"source_mode",1).AsInt32():mode;var after=before.Duplicate(true);after["bake"]=new Settings{["signature"]=job["expected"],["source_mode"]=source,["from"]=job["start"],["to"]=job["end"],["rate"]=owner.Get("rate"),["frames"]=job["frames"]};after["mode"]=4;if(GD.VarToBytes(after["bake"]).Length>67108864)error="Bake exceeds the 64 MiB per-actor limit. Shorten the interval or lower simulation resolution.";else{var history=model.Get("history").As<UndoRedo>();history.CreateAction("Bake Physics");BakeHistory(model,actor,before,after);history.CommitAction();}}owner.Set("_baking_actor","");owner.Set("signature","");mark_dirty(owner);editor.Get("canvas").AsGodotObject().Set("playhead",job["saved_time"]);editor.Set("playing",job["saved_playing"]);editor.Call("_evaluate_runtimes");return error;
    }
}
