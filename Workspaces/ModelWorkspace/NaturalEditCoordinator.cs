using Godot;
using System;
using System.Linq;
using System.Collections.Generic;
using System.Threading.Tasks;
using Settings=Godot.Collections.Dictionary;

public partial class NaturalEditCoordinator : Node
{
    private Control? _workspace;
    private readonly HashSet<NaturalGenerationJob> _jobs=new();
    private int _generation;
    private bool _closed;
    private static Variant Value(Settings settings,string key,Variant fallback)=>settings.TryGetValue(key,out var value)?value:fallback;
    private static bool Same(GodotObject? a,GodotObject? b)=>GodotObject.IsInstanceValid(a)&&GodotObject.IsInstanceValid(b)&&a!.GetInstanceId()==b!.GetInstanceId();
    private bool Live()=>!_closed&&GodotObject.IsInstanceValid(this)&&IsInsideTree()&&GodotObject.IsInstanceValid(_workspace)&&_workspace!.IsInsideTree()&&!_workspace.IsQueuedForDeletion();
    private Settings Current()=>_workspace!.GetMeta("natural_edit",new Settings()).AsGodotDictionary();
    private RefCounted Session()=>_workspace!.Get("session").As<RefCounted>();
    public void configure(Control workspace)=>_workspace=workspace;
    public override void _EnterTree()=>_closed=false;
    public override void _ExitTree()
    {
        _closed=true;++_generation;
        if(GodotObject.IsInstanceValid(_workspace))cancel();
        var jobs=_jobs.ToArray();foreach(var job in jobs)job.cancel();foreach(var job in jobs)job.collect();_jobs.Clear();
    }
    public void request(string id,string key,Variant value,bool finished)
    {
        if(!Live())return;var session=Session();var document=session.Get("document").As<Resource>();var source=document.Call("component",id).As<Resource>();if(source==null)return;
        var previous=Current();var parameters=source.Get("parameters").AsGodotDictionary().Duplicate(true);
        if(previous.Count>0){previous["job"].As<NaturalGenerationJob>().cancel();if(previous["id"].AsString()==id)parameters=previous["parameters"].AsGodotDictionary().Duplicate(true);}
        parameters[key]=value;session.Call("begin");var job=new NaturalGenerationJob();var state=new Settings{["job"]=job,["id"]=id,["parameters"]=parameters,["finished"]=finished,["applied"]=false,["session"]=session,["document"]=document,["source"]=source,["label"]="Change natural "+key,["was_dirty"]=Value(previous,"was_dirty",session.Get("dirty")),["revision"]=Value(previous,"revision",session.Get("revision"))};
        session.Set("dirty",true);_workspace!.EmitSignal("document_changed");_workspace.SetMeta("natural_edit",state);_jobs.Add(job);job.start(source.Get("generator").AsString(),parameters);_ = Collect(state,job,_generation,GetTree());
    }
    public void finish()
    {
        var state=Current();if(state.Count==0){Session().Call("commit","Change natural source");return;}state["finished"]=true;
        if(state["applied"].AsBool()){state["session"].As<RefCounted>().Call("commit",state["label"]);_workspace!.SetMeta("natural_edit",new Settings());}
    }
    public void cancel()
    {
        var state=Current();if(state.Count>0){state["job"].As<NaturalGenerationJob>().cancel();restore_dirty(state);}_workspace!.SetMeta("natural_edit",new Settings());Session().Call("cancel");
    }
    public void restore_dirty(Settings state)
    {var session=state["session"].As<RefCounted>();if(session.Get("revision").AsInt64()==state["revision"].AsInt64())session.Set("dirty",state["was_dirty"]);}
    private bool Stale(Settings state)
    {
        var owned=state["session"].As<RefCounted>();var document=state["document"].As<Resource>();return !Same(Session(),owned)||!Same(owned.Get("document").As<Resource>(),document)||!Same(document.Call("component",state["id"]).As<Resource>(),state["source"].As<Resource>());
    }
    private async Task Collect(Settings state,NaturalGenerationJob job,int generation,SceneTree tree)
    {
        try
        {
            // Even a cached result installs on a later frame, never during request().
            await ToSignal(tree,SceneTree.SignalName.ProcessFrame);bool stale=false;
            while(generation==_generation&&!job.complete())
            {
                if(!Live()||!Same(Value(Current(),"job",default).AsGodotObject(),job)||Stale(state)){job.cancel();stale=true;}
                await ToSignal(tree,SceneTree.SignalName.ProcessFrame);
            }
            if(generation!=_generation)return;var result=job.collect();_jobs.Remove(job);var owned=state["session"].As<RefCounted>();var document=state["document"].As<Resource>();
            if(!Live()){restore_dirty(state);if(Same(owned.Get("document").As<Resource>(),document))owned.Call("cancel");return;}
            if(!Same(Value(Current(),"job",default).AsGodotObject(),job))return;
            if(stale||Stale(state)){_workspace!.SetMeta("natural_edit",new Settings());restore_dirty(state);if(Same(owned.Get("document").As<Resource>(),document))owned.Call("cancel");else owned.EmitSignal("changed");return;}
            if(!result.TryGetValue("mesh",out var mesh)||mesh.VariantType!=Variant.Type.Object||mesh.AsGodotObject()==null)
            {_workspace!.Get("status").As<Label>().Text=Value(result,"error","Could not generate geometry.").AsString();_workspace.SetMeta("natural_edit",new Settings());restore_dirty(state);owned.Call("cancel");return;}
            var source=state["source"].As<Resource>();source.Set("parameters",state["parameters"]);source.Set("mesh",mesh);state["applied"]=true;_workspace!.Get("canvas").As<Control>().Call("request_sync");
            if(state["finished"].AsBool()){owned.Call("commit",state["label"]);_workspace.SetMeta("natural_edit",new Settings());}
        }
        catch(Exception error)
        {
            job.cancel();if(generation!=_generation)return;job.collect();_jobs.Remove(job);
            if(Live()&&Same(Value(Current(),"job",default).AsGodotObject(),job)){_workspace!.SetMeta("natural_edit",new Settings());restore_dirty(state);state["session"].As<RefCounted>().Call("cancel");_workspace.Get("status").As<Label>().Text="Natural generation failed: "+error.Message;}
            GD.PushError(error.ToString());
        }
    }
}
