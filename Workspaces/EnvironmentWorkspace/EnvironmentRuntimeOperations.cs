using Godot;
using System;
using System.Collections.Generic;
using System.Linq;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class EnvironmentRuntimeOperations : RefCounted
{
    private readonly EnvironmentCollisionRuntime _collision=new();
    private readonly EnvironmentWeatherRuntime _weather=new();
    private readonly ModelNaturalRender _natural=new();
    private readonly TerrainMeshLod _lod=new();
    private readonly TerrainDataOperations _terrainData=new();
    private readonly TerrainBiomeRender _biome=new();
    private readonly TerrainPaintRender _paint=new();
    private readonly EnvironmentWaterRender _water=new();
    private readonly EnvironmentInstanceStream _instances=new();
    private readonly EnvironmentBuildingStreamOperations _buildings=new();
    private static Variant Get(Settings values,Variant key,Variant fallback=default)=>values.TryGetValue(key,out var value)?value:fallback;
    private static Settings State(Node3D owner,string key)=>owner.Get(key).AsGodotDictionary();
    private static Resource? Document(Node3D owner)=>owner.Get("document").As<Resource>();
    private static RefCounted Stream(Node3D owner)=>owner.Get("building_stream").As<RefCounted>();
    private static GDScript Assets()=>GD.Load<GDScript>("res://Workspaces/EnvironmentWorkspace/environment_assets.gd");
    private static bool Live(GodotObject? value)=>value!=null&&GodotObject.IsInstanceValid(value);
    private static long Hash(Variant value)=>unchecked((uint)GD.Hash(value));
    private static void Append(Node3D owner,string key,string message)
    {var values=owner.Get(key).AsStringArray().ToList();values.Add(message);owner.Set(key,values.ToArray());}
    private static void Error(Node3D owner,string message)=>Append(owner,"errors",message);
    private static void Warning(Node3D owner,string message)=>Append(owner,"warnings",message);
    private static void CancelJobs(Node3D owner)
    {var retired=owner.Get("_retired_scatter").AsGodotArray();var jobs=State(owner,"scatter_jobs");foreach(var value in jobs.Values){var job=value.AsGodotDictionary()["job"].As<RefCounted>();job.Call("cancel");retired.Add(job);}jobs.Clear();}
    public void configure(Node3D owner,Resource source)
    {
        if(Document(owner)!=source){foreach(string key in new[]{"pending_chunks","pending_assets","_material_scope","_scatter_mesh_scope","_asset_lod_scope","stream_nodes"})State(owner,key).Clear();CancelJobs(owner);}owner.Set("document",source);sync(owner);
    }
    public void cancel_scatter_generation(Node3D owner)=>CancelJobs(owner);
    public void release(Node3D owner)
    {
        _weather.release(owner);_collision.release(owner);_buildings.dispose(Stream(owner));CancelJobs(owner);var retired=owner.Get("_retired_scatter").AsGodotArray();foreach(var value in retired){var job=value.As<RefCounted>();job.Call("cancel");job.Call("collect");}retired.Clear();
    }
    public bool geometry_ready(Node3D owner,bool physicsFull)=>_buildings.ready(Stream(owner),physicsFull)&&State(owner,"pending_assets").Count==0&&State(owner,"pending_chunks").Count==0;
    public void sync_lighting(Node3D owner)
    {
        var document=Document(owner);if(document==null)return;bool enabled=owner.Get("include_lighting").AsBool();var sun=owner.Get("sun").As<DirectionalLight3D>();if(enabled&&sun==null){sun=new DirectionalLight3D {Name="EnvironmentSun"};owner.AddChild(sun);owner.Set("sun",sun);}if(sun==null)return;
        var settings=document.Get("sunlight").AsGodotDictionary();sun.Visible=enabled&&Get(settings,"enabled",true).AsBool();sun.RotationDegrees=Get(settings,"rotation",new Vector3(-45,-30,0)).AsVector3();sun.LightColor=Get(settings,"color",Colors.White).AsColor();sun.LightEnergy=Get(settings,"energy",1.5).AsSingle();sun.ShadowEnabled=Get(settings,"shadows",true).AsBool();
    }
    public void sync(Node3D owner)
    {
        var document=Document(owner);if(document==null)return;sync_lighting(owner);owner.Set("errors",Array.Empty<string>());owner.Set("warnings",Array.Empty<string>());owner.Set("chunks_rebuilt",0);owner.Set("instances",0);var live=new HashSet<string>(StringComparer.Ordinal);var hierarchy=document.Call("hierarchy_state").AsGodotDictionary();var index=State(owner,"component_index");index.Clear();var components=document.Get("components").AsGodotArray();foreach(var value in components){var item=value.As<Resource>();index[item.Get("id")]=item;}
        var nodes=State(owner,"nodes");var signatures=State(owner,"signatures");var hidden=State(owner,"preview_hidden");var metadata=document.Get("component_settings").AsGodotDictionary();var pending=State(owner,"pending_assets");
        foreach(var value in components)
        {
            var item=value.As<Resource>();string id=item.Get("id").AsString();live.Add(id);var settings=Get(metadata,id,new Settings {["kind"]="asset"}).AsGodotDictionary();string kind=Get(settings,"kind","asset").AsString();var node=Get(nodes,id).As<Node3D>();
            if(node==null){node=new Node3D {Name=item.Get("title").AsString().ValidateNodeName()};owner.AddChild(node);nodes[id]=node;}
            if(node.GetMeta("environment_kind", "").AsString()!=kind){if(node.HasMeta("scatter_stream")){node.RemoveMeta("scatter_stream");State(owner,"stream_nodes").Remove(node.GetInstanceId());}foreach(var child in node.GetChildren())child.Free();node.SetMeta("environment_kind",kind);signatures.Remove(id);}
            node.Transform=hierarchy["poses"].AsGodotDictionary()[id].AsTransform3D();node.Visible=hierarchy["visible"].AsGodotDictionary()[id].AsBool()&&!hidden.ContainsKey(id);node.SetMeta("kiwi_physics_excluded",!node.Visible||!Get(settings,"collision",true).AsBool());
            switch(kind)
            {
                case "terrain":terrain(owner,item,node,settings);break;
                case "scatter":scatter(owner,item,node,settings);break;
                case "building":_buildings.Sync(Stream(owner),item,node,settings,this);break;
                case "asset":if(owner.Get("progressive").AsBool()&&item.Get("mesh").As<Resource>()!=null&&Get(settings,"source", "").AsString().Length==0){if(Get(signatures,id,-1).AsInt64()!=native_asset_key(item))pending[id]=new Settings {["item"]=item,["node"]=node};}else{pending.Remove(id);asset(owner,item,node,settings);}break;
            }
            world_render(owner,item,node);
        }
        foreach(var key in nodes.Keys.ToArray())if(!live.Contains(key.AsString())){nodes[key].As<Node3D>().QueueFree();nodes.Remove(key);signatures.Remove(key);pending.Remove(key);}if(State(owner,"_material_scope").Count>256)State(owner,"_material_scope").Clear();
    }
    public void process(Node3D owner,double delta)
    {
        var building=Stream(owner);if(building.Get("entries").AsGodotDictionary().Count>0)_buildings.process(building);double streamTime=owner.Get("_stream_time").AsDouble()+delta;owner.Set("_stream_time",streamTime);
        var camera=owner.GetViewport().GetCamera3D();var priority=owner.Get("priority_camera").As<Camera3D>();if(camera==null&&Live(priority))camera=priority;var pose=camera?.GlobalTransform??Transform3D.Identity;bool visible=owner.IsVisibleInTree();
        if(streamTime>=.2||camera!=owner.Get("_stream_camera").As<Camera3D>()||pose!=owner.Get("_stream_pose").AsTransform3D()||owner.GlobalTransform!=owner.Get("_stream_root").AsTransform3D()||visible!=owner.Get("_stream_visible").AsBool())
        {
            owner.Set("_stream_time",0.0);owner.Set("_stream_camera",camera!=null?Variant.From(camera):default);owner.Set("_stream_pose",pose);owner.Set("_stream_root",owner.GlobalTransform);owner.Set("_stream_visible",visible);var streams=State(owner,"stream_nodes");foreach(var key in streams.Keys.ToArray()){var node=streams[key].As<Node3D>();if(!Live(node)||!node.HasMeta("scatter_stream")){streams.Remove(key);continue;}_instances.refresh(owner,node);}
        }
        if(owner.Get("animate_preview").AsBool()&&visible)
        {
            double time=owner.Get("preview_time").AsDouble()+delta;owner.Set("preview_time",time);_natural.time(owner,time,new Settings());foreach(var value in State(owner,"nodes").Values){var water=value.As<Node3D>().GetNodeOrNull<MeshInstance3D>("Water");if(water?.MaterialOverride is ShaderMaterial material&&material.GetMeta("terrain_water",false).AsBool())material.SetShaderParameter("liquid_time",time);if(water?.GetNodeOrNull<MultiMeshInstance3D>("Spray")?.MaterialOverride is ShaderMaterial spray)spray.SetShaderParameter("liquid_time",time);}
        }
        poll_scatter(owner);ulong started=Time.GetTicksUsec();bool processed=false;long budget=owner.Get("upload_budget_usec").AsInt64();var chunks=State(owner,"pending_chunks");var nodes=State(owner,"nodes");
        while(chunks.Count>0&&(!processed||Time.GetTicksUsec()-started<(ulong)Math.Max(0,budget)))
        {
            string id=next_chunk(owner);var task=chunks[id].AsGodotDictionary();chunks.Remove(id);var node=task["node"].As<Node3D>();var chunk=task["chunk"].As<MeshInstance3D>();var document=Document(owner);
            if(!Live(node)||!Live(chunk)||Get(nodes,task["id"]).As<Node3D>()!=node||document==null||document.Call("terrain",task["id"]).As<Resource>()!=task["terrain"].As<Resource>())continue;
            _collision.build_chunk(owner,task["terrain"].As<Resource>(),task["coordinate"].AsVector2I(),chunk,task["key"].AsInt64());_collision.assign_chunk_materials(chunk,task["material"].As<Material>(),task["paint"].As<Material>(),task["collision"].AsBool());processed=true;
        }
        var pending=State(owner,"pending_assets");while(pending.Count>0&&(!processed||Time.GetTicksUsec()-started<(ulong)Math.Max(0,budget)))
        {
            var id=pending.Keys.First();var task=pending[id].AsGodotDictionary();pending.Remove(id);var document=Document(owner);var node=task["node"].As<Node3D>();var item=task["item"].As<Resource>();if(document==null||!Live(node)||Get(nodes,id).As<Node3D>()!=node||Get(State(owner,"component_index"),id).As<Resource>()!=item)continue;
            var metadata=Get(document.Get("component_settings").AsGodotDictionary(),id,new Settings {["kind"]="asset"}).AsGodotDictionary();if(Get(metadata,"kind","asset").AsString()!="asset")continue;asset(owner,item,node,metadata);world_render(owner,item,node);processed=true;
        }
    }
    public string next_chunk(Node3D owner)
    {
        var pending=State(owner,"pending_chunks");string chosen=pending.Keys.First().AsString();var camera=owner.Get("priority_camera").As<Camera3D>();if(!Live(camera))return chosen;double best=double.PositiveInfinity;
        foreach(var pair in pending){var task=pair.Value.AsGodotDictionary();var node=task["node"].As<Node3D>();if(!Live(node))continue;var source=task["terrain"].As<Resource>();var cell=task["coordinate"].AsVector2I()*32+Vector2I.One*16;int n=source.Get("resolution").AsInt32();var point=node.GlobalTransform*source.Call("position",Math.Min(cell.X,n-1),Math.Min(cell.Y,n-1)).AsVector3();double distance=point.DistanceSquaredTo(camera!.GlobalPosition);if(distance<best){best=distance;chosen=pair.Key.AsString();}}
        return chosen;
    }
}
