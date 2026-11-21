using Godot;
using System;
using System.Collections.Generic;
using System.Linq;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class EnvironmentBuildingStreamOperations : RefCounted
{
    private static Variant Get(Settings values,Variant key,Variant fallback=default)=>values.TryGetValue(key,out var value)?value:fallback;
    private static Node3D? Runtime(RefCounted state)=>state.Get("runtime").As<Node3D>();
    private static Settings Entries(RefCounted state)=>state.Get("entries").AsGodotDictionary();
    private static GArray Retired(RefCounted state)=>state.Get("retired").AsGodotArray();
    private static bool Live(GodotObject? value)=>value!=null&&GodotObject.IsInstanceValid(value);
    private static GDScript Script(string name)=>GD.Load<GDScript>("res://Workspaces/EnvironmentWorkspace/architecture/"+name+".gd");
    private static EnvironmentRuntimeOperations Operations()=>(EnvironmentRuntimeOperations)((MigrationBootstrap)Engine.GetSingleton("KiwiNativeServices")).service("environment_runtime");
    private static void Message(Node3D runtime,string kind,string text){var values=runtime.Get(kind).AsStringArray().ToList();values.Add(text);runtime.Set(kind,values.ToArray());}
    public string failure(RefCounted state)
    {foreach(var value in Entries(state).Values){string error=Get(value.AsGodotDictionary(),"error", "").AsString();if(error.Length>0)return error;}return "";}
    public void sync(RefCounted state,Resource item,Node3D node,Settings metadata)=>Sync(state,item,node,metadata,Operations());
    internal void Sync(RefCounted state,Resource item,Node3D node,Settings metadata,EnvironmentRuntimeOperations operations)
    {
        var runtime=Runtime(state)!;var authored=Script("building_session").Call("source",item).As<Resource>();if(authored==null){Message(runtime,"errors",item.Get("title").AsString()+": missing building source.");return;}
        long stamp=Script("building_geometry").Call("mesh_key",item.Get("mesh")).AsInt64();var parameters=item.Get("parameters").AsGodotDictionary();bool custom=item.Get("binding").As<Resource>()!=null||item.Get("growth").As<Resource>()!=null||item.Get("modifiers").AsGodotArray().Count>0||stamp!=Get(parameters,"_architecture_mesh",stamp).AsInt64();var entries=Entries(state);string id=item.Get("id").AsString();
        if(custom){if(entries.TryGetValue(id,out var previous)){retire(state,previous.AsGodotDictionary());entries.Remove(id);}operations.asset(runtime,item,node,metadata);Message(runtime,"warnings",item.Get("title").AsString()+": using its authored mesh override instead of procedural building detail.");return;}
        var source=Script("building_source").Call("copy",authored).As<Resource>();var slots=item.Get("surface_materials").AsGodotArray();if(!slots.RecursiveEqual(Get(parameters,"_architecture_materials",slots).AsGodotArray())){var materials=source.Get("materials").AsGodotArray();while(materials.Count<slots.Count)materials.Add(default);for(int index=0;index<slots.Count;index++)materials[index]=slots[index];}
        long key=unchecked((uint)GD.Hash(new GArray {Script("building_session").Call("_source_key",source),slots}));var entry=Get(entries,id,new Settings()).AsGodotDictionary();
        if(entry.Count>0&&(entry["key"].AsInt64()!=key||entry["node"].As<Node3D>()!=node)){retire(state,entry);entries.Remove(id);entry=new Settings();}
        if(entry.Count==0){entry=new Settings {["id"]=id,["key"]=key,["node"]=node,["source"]=source,["document"]=default,["job"]=default,["detail"]=default,["bytes"]=0,["used"]=0,["near"]=false,["error"]=""};entries[id]=entry;}
        var shell=node.GetNodeOrNull<MeshInstance3D>("BuildingDistanceShell");long meshKey=operations.native_asset_key(item);if(shell==null){foreach(var child in node.GetChildren())child.Free();shell=new MeshInstance3D {Name="BuildingDistanceShell"};node.AddChild(shell);shell.SetMeta("kiwi_physics_excluded",true);}if(shell.GetMeta("source_key",-1).AsInt64()!=meshKey){shell.Mesh=item.Call("render_mesh",runtime.Get("_material_scope")).As<Mesh>();shell.SetMeta("source_key",meshKey);}entry["shell"]=shell;entry["collision"]=Get(metadata,"collision",true).AsBool();
    }
    public void retire(RefCounted state,Settings entry)
    {var job=Get(entry,"job").As<RefCounted>();if(job!=null){job.Call("cancel");Retired(state).Add(job);}var detail=Get(entry,"detail").As<Node3D>();if(Live(detail))detail!.Free();}
    public void dispose(RefCounted state)
    {foreach(var value in Entries(state).Values)retire(state,value.AsGodotDictionary());var retired=Retired(state);foreach(var value in retired){var job=value.As<RefCounted>();job.Call("cancel");job.Call("collect");}Entries(state).Clear();retired.Clear();state.Set("cache_bytes",0);}
    public bool ready(RefCounted state,bool needPhysics)
    {
        state.Set("physics_full",needPhysics);process(state);if(failure(state).Length>0)return false;foreach(var value in Entries(state).Values){var entry=value.AsGodotDictionary();if(!needPhysics&&!Get(entry,"wanted",false).AsBool())continue;var detail=Get(entry,"detail").As<Node3D>();if(detail==null||detail.Get("pending_assets").AsGodotDictionary().Count>0||detail.Get("pending_chunks").AsGodotDictionary().Count>0)return false;}return true;
    }
    public Settings policy(RefCounted state,Settings entry)
    {
        var runtime=Runtime(state)!;var index=runtime.Get("component_index").AsGodotDictionary();var item=Get(index,entry["id"].AsString()).As<Resource>();var owner=item!=null?Get(index,Get(item.Get("parameters").AsGodotDictionary(),"world_owner", "").AsString()).As<Resource>():null;var source=owner!=null?Get(owner.Get("parameters").AsGodotDictionary(),"world_source").As<Resource>():null;
        return new Settings {["distance"]=source?.Get("building_detail_distance")??180.0,["active"]=source?.Get("max_active_buildings")??64,["cache"]=source!=null?source.Get("building_cache_mb").AsInt64()*1048576:134217728};
    }
}
