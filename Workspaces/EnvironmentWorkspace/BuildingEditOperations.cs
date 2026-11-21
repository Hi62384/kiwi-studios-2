using Godot;
using System;
using System.Collections.Generic;
using Settings=Godot.Collections.Dictionary;

public partial class BuildingEditOperations : RefCounted
{
    private readonly Dictionary<ulong,Settings> _pending=new();
    private readonly BuildingSessionOperations _buildings=new();
    private readonly BuildingSourceOperations _sources=new();
    private readonly BuildingGeometryOperations _geometry=new();
    private readonly ModelDocumentOperations _documents=new();
    private static Resource Document(RefCounted session)=>session.Get("document").As<Resource>();
    private static Settings EmptyCancelled()=>new() {["errors"]=Array.Empty<string>(),["warnings"]=Array.Empty<string>(),["cancelled"]=true};
    private static Settings Error(string message)=>new() {["errors"]=new[]{message},["warnings"]=Array.Empty<string>()};
    private static bool Current(RefCounted session,Settings state)=>Document(session)==state["document"].As<Resource>()&&session.Get("revision").AsInt64()==state["revision"].AsInt64();
    public Settings pending(RefCounted session)=>_pending.TryGetValue(session.GetInstanceId(),out var state)?state:new Settings();
    public Resource? source(RefCounted session,string id)
    {var state=pending(session);if(state.Count>0&&state["id"].AsString()==id&&Current(session,state))return state["desired"].As<Resource>();return _buildings.source(_documents.component(Document(session),id));}
    public void cancel(RefCounted session)
    {var state=pending(session);if(state.Count==0)return;state["job"].As<BuildingGenerationJob>().cancel();_pending.Remove(session.GetInstanceId());session.Set("pending_source_cancel",default(Callable));if(Current(session,state))session.Set("dirty",state["was_dirty"]);session.EmitSignal("changed");}
    public Settings start(RefCounted session,string id,Resource authored,string label)
    {
        var document=Document(session);var root=_documents.component(document,id);if(root==null)return new Settings {["result"]=Error("The building no longer exists.")};if(session.Get("_gesture").AsGodotDictionary().Count>0)return new Settings {["result"]=Error("Finish the current transform or stroke before editing building settings.")};var previous=pending(session);bool wasDirty=session.Get("dirty").AsBool();
        if(previous.Count>0){previous["job"].As<BuildingGenerationJob>().cancel();if(previous["revision"].AsInt64()==session.Get("revision").AsInt64())wasDirty=previous["was_dirty"].AsBool();}else session.Call("_invoke_pending_source_cancel");var desired=_sources.copy(authored);desired.Set("source_id",id);var job=new BuildingGenerationJob();var state=new Settings {["job"]=job,["desired"]=desired,["id"]=id,["root"]=root,["document"]=document,["revision"]=session.Get("revision"),["was_dirty"]=wasDirty,["success"]=true,["label"]=label};_pending[session.GetInstanceId()]=state;var weak=GodotObject.WeakRef(session)!;session.Set("pending_source_cancel",Callable.From(()=>{var owner=weak.GetRef().As<RefCounted>();if(owner!=null)cancel(owner);}));session.Set("dirty",true);job.start(desired);session.EmitSignal("changed");return state;
    }
    public bool poll(RefCounted session,Settings state)
    {var job=state["job"].As<BuildingGenerationJob>();if(!Current(session,state)||_documents.component(Document(session),state["id"].AsString())!=state["root"].As<Resource>())job.cancel();return job.complete();}
    public Settings finish(RefCounted session,Settings state)
    {
        var job=state["job"].As<BuildingGenerationJob>();var result=job.collect();var active=pending(session);if(active.Count==0||active["job"].As<BuildingGenerationJob>()!=job)return EmptyCancelled();_pending.Remove(session.GetInstanceId());session.Set("pending_source_cancel",default(Callable));string id=state["id"].AsString(),label=state["label"].AsString();var root=state["root"].As<Resource>();bool current=Current(session,state);
        if((result.TryGetValue("cancelled",out var cancelled)&&cancelled.AsBool())||!current||_documents.component(Document(session),id)!=root){if(current)session.Set("dirty",state["was_dirty"]);return EmptyCancelled();}if(!result.TryGetValue("document",out var generated)||generated.As<Resource>()==null||result["errors"].AsStringArray().Length>0){state["success"]=false;session.Set("dirty",state["was_dirty"]);return result;}
        var document=Document(session);bool environment=document.HasMethod("component_kind")&&document.Call("component_kind",id).AsString()=="building";var desired=state["desired"].As<Resource>();result["source_key"]=_buildings.source_key(desired);
        if(environment)
        {
            var values=root.Get("parameters").AsGodotDictionary();var mesh=root.Get("mesh").As<Resource>();long stamp=_geometry.mesh_key(mesh,2),expected=values.TryGetValue("_architecture_mesh",out var previousHash)?previousHash.AsInt64():stamp;if(root.Get("binding").As<Resource>()!=null||root.Get("growth").As<Resource>()!=null||root.Get("modifiers").AsGodotArray().Count>0||stamp!=expected){state["success"]=false;session.Set("dirty",state["was_dirty"]);return Error("This building has a custom mesh, rig or groom. Preserve or reset that override before expanding generated detail.");}
            session.Call("begin");if(values.ContainsKey("world_owner"))GD.Load<GDScript>("res://Workspaces/EnvironmentWorkspace/world/world_session.gd").Call("detach_building",session,id);values["_architecture_generated_mesh"]=stamp;values.Remove("world_lazy_building");var expanded=_buildings.update(session,id,desired,label,true,true,result);if(expanded["errors"].AsStringArray().Length>0){session.Call("cancel");state["success"]=false;return expanded;}session.Call("commit",label);return expanded;
        }
        var applied=_buildings.update(session,id,desired,label,false,false,result);if(applied["errors"].AsStringArray().Length>0){state["success"]=false;session.Set("dirty",state["was_dirty"]);}return applied;
    }
}
