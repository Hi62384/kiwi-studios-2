using Godot;
using System;
using Settings=Godot.Collections.Dictionary;

public partial class WorldEditOperations : RefCounted
{
    private readonly WorldSessionOperations _worlds=new();
    private readonly WorldPlacementOperations _placement=new();
    private readonly WorldTerrainOperations _terrain=new();
    private readonly WorldSourceOperations _sources=new();
    private static Variant Get(Settings values,string key,Variant fallback=default)=>values.TryGetValue(key,out var value)?value:fallback;
    private static long Key(RefCounted session)=>unchecked((long)session.GetInstanceId());
    private static Settings Pending(Settings pending,long key)=>pending.TryGetValue(key,out var value)?value.AsGodotDictionary():new Settings();
    private static Resource Document(RefCounted session)=>session.Get("document").As<Resource>();
    private static bool Current(RefCounted session,Settings state)=>Document(session)==state["document"].As<Resource>()&&session.Get("revision").AsInt64()==state["revision"].AsInt64();
    private static Settings Cancelled()=>new() {["errors"]=Array.Empty<string>(),["warnings"]=Array.Empty<string>(),["cancelled"]=true};
    private static Settings Immediate(Settings result)=>new() {["done"]=true,["result"]=result};
    private static Settings Failed(string error)=>Immediate(new Settings {["errors"]=new[]{error},["warnings"]=Array.Empty<string>()});
    public Resource? source(RefCounted session,string id,Settings pending)
    {var state=Pending(pending,Key(session));if(state.Count>0&&state["id"].AsString()==id&&Current(session,state))return state["desired"].As<Resource>();return _worlds.source(Document(session).Call("component",id).As<Resource>());}
    public void cancel(RefCounted session,Settings pending)
    {
        var state=Pending(pending,Key(session));if(state.Count==0)return;state["job"].As<WorldGenerationJob>().cancel();pending.Remove(Key(session));session.Set("pending_source_cancel",default(Callable));if(Current(session,state))session.Set("dirty",state["was_dirty"]);session.EmitSignal("changed");
    }
    public Settings begin_request(RefCounted session,string id,Resource authored,string label,Settings pending,Settings callback)
    {
        var document=Document(session);var root=document.Call("component",id).As<Resource>();if(root==null||session.Get("_gesture").AsGodotDictionary().Count>0)return Failed("Finish the current edit before generating this world.");var previous=Pending(pending,Key(session));bool wasDirty=session.Get("dirty").AsBool();
        if(previous.Count>0){wasDirty=previous["was_dirty"].AsBool();cancel(session,pending);}else{var existing=session.Get("pending_source_cancel");GD.Load<GDScript>("res://Workspaces/EnvironmentWorkspace/world/world_edit.gd").Call("_invoke_cancel",new Settings {["callback"]=existing});}
        var desired=_sources.copy(authored);desired.Set("world_id",id);_worlds.preserve_reservations(_worlds.source(root),desired);var fieldResult=GD.Load<GDScript>("res://Workspaces/EnvironmentWorkspace/world/world_terrain_field.gd").Call("capture",session,id,desired).AsGodotDictionary();new RoadSectionOperations().prepare(desired);string occupancyError=_placement.capture(session,id,desired);if(occupancyError.Length>0)return Failed(occupancyError);string fieldError=fieldResult["error"].AsString();if(fieldError.Length>0)return Failed(fieldError);
        var field=fieldResult["field"].As<RefCounted>();desired.Set("terrain_field",field!=null?Variant.From(field):default);desired.Set("terrain_dependency_key",field!=null?field.Get("key").AsInt64():0);_placement.follow_controls(desired);var plan=_terrain.tunnels_plan(session,id,desired);string planError=Get(plan,"error","").AsString();if(planError.Length>0)return Failed(planError);var portalPoints=Get(plan,"portal_points",new Settings()).AsGodotDictionary();var frames=Get(plan,"portal_frames",new Settings()).AsGodotDictionary();
        foreach(var value in desired.Get("roads").AsGodotArray()){var road=value.AsGodotDictionary();if(portalPoints.TryGetValue(road["id"],out var points)){road["portal_points"]=points;road["portal_frames"]=frames[road["id"]];}}
        if(!plan.ContainsKey("settings")){var visual=new WorldVisualEditOperations().snapshot(session,id,desired);if(visual.Count>0)return Immediate(_worlds.update(session,id,desired,label,visual));}
        var job=new WorldGenerationJob();var state=new Settings {["job"]=job,["desired"]=desired,["document"]=Document(session),["revision"]=session.Get("revision"),["id"]=id,["root"]=root,["was_dirty"]=wasDirty,["success"]=true,["label"]=label,["plan"]=plan};pending[Key(session)]=state;session.Set("pending_source_cancel",callback["callback"]);session.Set("dirty",true);job.start(desired,plan,_worlds.development_snapshot(session,id,desired));session.EmitSignal("changed");return state;
    }
    public void poll(RefCounted session,Settings state)
    {
        var job=state["job"].As<WorldGenerationJob>();if(!Current(session,state)){job.cancel();return;}var desired=state["desired"].As<Resource>();var field=desired.Get("terrain_field").As<RefCounted>();if(field!=null&&!field.Call("valid",session).AsBool()){job.cancel();return;}var plan=state["plan"].AsGodotDictionary();if(plan.ContainsKey("source")){var terrain=session.Call("environment").As<Resource>().Call("terrain",plan["id"]).As<Resource>();if(terrain==null||terrain!=plan["source"].As<Resource>()||terrain.Call("signature").AsInt64()!=plan["signature"].AsInt64())job.cancel();}
    }
    public Settings finish(RefCounted session,Settings state,Settings pending)
    {
        var job=state["job"].As<WorldGenerationJob>();var result=job.collect();if(Get(Pending(pending,Key(session)),"job").AsGodotObject()!=job)return Cancelled();pending.Remove(Key(session));session.Set("pending_source_cancel",default(Callable));string id=state["id"].AsString();
        if(Get(result,"cancelled",false).AsBool()||!Current(session,state)||Document(session).Call("component",id).As<Resource>()!=state["root"].As<Resource>()){if(Current(session,state))session.Set("dirty",state["was_dirty"]);return Cancelled();}
        if(Get(result,"document").AsGodotObject()==null||result["errors"].AsStringArray().Length>0){state["success"]=false;session.Set("dirty",state["was_dirty"]);return result;}
        var desired=state["desired"].As<Resource>();result["signature"]=_sources.signature(desired);var applied=_worlds.update(session,id,desired,state["label"].AsString(),result);if(applied["errors"].AsStringArray().Length>0){state["success"]=false;session.Set("dirty",state["was_dirty"]);}return applied;
    }
}
