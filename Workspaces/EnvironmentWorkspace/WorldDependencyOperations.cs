using Godot;
using System;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class WorldDependencyOperations : RefCounted
{
    private readonly WorldSourceOperations _sources=new();
    private readonly WorldPlacementOperations _placement=new();
    private readonly EnvironmentDataHash _hash=new();
    private static RefCounted Session(Control owner)=>owner.Get("session").As<RefCounted>();
    private static Variant Get(Settings values,string key,Variant fallback=default)=>values.TryGetValue(key,out var value)?value:fallback;
    public Settings state(Control owner)
    {
        var session=Session(owner);var value=owner.GetMeta("world_dependencies",new Settings()).AsGodotDictionary();if(Get(value,"session").As<RefCounted>()!=session){value=new Settings {["session"]=session,["time"]=0L,["history"]=session.Get("history_revision"),["seen"]=new Settings(),["failed"]=new Settings(),["pause"]=new Settings()};owner.SetMeta("world_dependencies",value);}return value;
    }
    public void suspend(Control owner)
    {var value=state(owner);var undo=Session(owner).Get("_undo").AsGodotArray();value["pause"]=new Settings {["depth"]=undo.Count,["entry"]=undo.Count>0?undo[^1]:Variant.From(new Settings())};}
    internal static bool SameEntry(Variant a,Variant b)=>a.VariantType==Variant.Type.Dictionary&&b.VariantType==Variant.Type.Dictionary?a.AsGodotDictionary().RecursiveEqual(b.AsGodotDictionary()):a.Equals(b);
    public void poll(Control owner)
    {
        var value=state(owner);var session=Session(owner);var undo=session.Get("_undo").AsGodotArray();long history=session.Get("history_revision").AsInt64();if(value["history"].AsInt64()!=history){value["history"]=history;suspend(owner);}var pause=value["pause"].AsGodotDictionary();if(pause.Count>0){if(pause["depth"].AsInt32()==undo.Count&&(undo.Count==0||SameEntry(undo[^1],pause["entry"])))return;value["pause"]=new Settings();}long now=(long)Time.GetTicksMsec();if(now-value["time"].AsInt64()<250||session.Call("_pending_source_valid").AsBool()||session.Get("_gesture").AsGodotDictionary().Count>0)return;value["time"]=now;long revision=session.Get("revision").AsInt64();var seen=value["seen"].AsGodotDictionary();var failed=value["failed"].AsGodotDictionary();
        foreach(var component in session.Get("document").As<Resource>().Get("components").AsGodotArray())
        {
            var item=component.As<Resource>();var parameters=item.Get("parameters").AsGodotDictionary();var current=Get(parameters,"world_source").As<Resource>();if(current==null||current.GetScript().As<Script>()?.ResourcePath!="res://Workspaces/EnvironmentWorkspace/world/WorldSource.cs"||!current.Get("auto_update_dependencies").AsBool()||!parameters.ContainsKey("world_graph")||current.Get("terrain_id").AsString().Length==0)continue;string id=item.Get("id").AsString();var field=current.Get("terrain_field").As<RefCounted>();bool terrainChanged=field==null||!(field is WorldTerrainField snapshot?snapshot.valid(session):field.Call("valid",session).AsBool()),objectsChanged=Get(seen,id,-1L).AsInt64()!=revision;if(!terrainChanged&&!objectsChanged)continue;
            var desired=_sources.copy(current);var captured=GD.Load<GDScript>("res://Workspaces/EnvironmentWorkspace/world/world_terrain_field.gd").Call("capture",session,id,desired).AsGodotDictionary();if(captured["error"].AsString().Length>0)continue;var nextField=captured["field"].As<RefCounted>();long key=unchecked((uint)GD.Hash(new GArray {nextField.Get("key"),revision,_sources.signature(current)}));if(Get(failed,id,0L).AsInt64()==key)continue;string error=_placement.capture(session,id,desired);if(error.Length>0){failed[id]=key;owner.Get("status").As<Label>().Text=error;continue;}seen[id]=revision;if(nextField.Get("key").AsInt64()==current.Get("terrain_dependency_key").AsInt64()&&_hash.value(desired.Get("occupied"))==_hash.value(current.Get("occupied"))){current.Set("terrain_field",nextField);continue;}update(owner,session,id,desired,key);return;
        }
    }
    public void update(Control owner,RefCounted session,string id,Resource desired,long key)
    {var job=new WorldDependencyUpdateJob();owner.AddChild(job);job.start(owner,session,id,desired,key);}
    public long cost(Settings snapshot)
    {long count=0;foreach(var value in snapshot["document"].As<Resource>().Get("components").AsGodotArray()){var mesh=value.As<Resource>().Get("mesh").As<Resource>();if(mesh!=null)count+=mesh.Get("vertices").AsVector3Array().Length;}return count;}
}
