using Godot;
using System;
using System.Linq;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class WorldSessionOperations : RefCounted
{
    private readonly WorldSourceOperations _sources=new();
    private static Variant Get(Settings values,string key,Variant fallback=default)=>values.TryGetValue(key,out var value)?value:fallback;
    private static Resource Document(RefCounted session)=>session.Get("document").As<Resource>();
    private static Resource? Component(Resource document,string id)=>document.Call("component",id).As<Resource>();
    public Resource? source(Resource? item)
    {if(item==null)return null;var value=Get(item.Get("parameters").AsGodotDictionary(),"world_source");if(value.VariantType!=Variant.Type.Object||value.AsGodotObject() is not Resource resource)return null;return resource.GetScript().As<Script>()?.ResourcePath=="res://Workspaces/EnvironmentWorkspace/world/WorldSource.cs"?resource:null;}
    public void preserve_reservations(Resource? current,Resource desired)
    {if(current==null)return;var target=desired.Get("plot_overrides").AsGodotDictionary();foreach(var pair in current.Get("plot_overrides").AsGodotDictionary())if(!target.ContainsKey(pair.Key)&&Get(pair.Value.AsGodotDictionary(),"reserved",false).AsBool())target[pair.Key]=pair.Value.AsGodotDictionary().Duplicate(true);}
    public Resource? development_snapshot(RefCounted session,string id,Resource desired)
    {
        var original=Document(session);var root=Component(original,id);var current=source(root);if(current==null||_sources.development_signature(current)!=_sources.development_signature(desired)||!root!.Get("parameters").AsGodotDictionary().ContainsKey("world_graph"))return null;
        var document=new KiwiModelDocument();var components=document.Get("components").AsGodotArray();components.Add(root.Call("copy_component"));foreach(var value in original.Get("components").AsGodotArray()){var item=value.As<Resource>();var parameters=item.Get("parameters").AsGodotDictionary();string key=Get(parameters,"world_key","").AsString();if(!Get(parameters,"world_generated",false).AsBool()||Get(parameters,"world_owner","").AsString()!=id||key.StartsWith(":forest:",StringComparison.Ordinal)||key.StartsWith(":props:",StringComparison.Ordinal))continue;components.Add(item.Call("copy_component"));}return document;
    }
    public Resource add_road(Resource authored,Vector3 start,Vector3 end)
    {
        var next=_sources.copy(authored);string id=Guid.NewGuid().ToString("N"),from=id+":a",to=id+":b";var nodes=next.Get("nodes").AsGodotDictionary();nodes[from]=start;nodes[to]=end;var roads=next.Get("roads").AsGodotArray();var road=new RoadSectionOperations().defaults("Residential Street");road.Merge(new Settings {["id"]=id,["name"]="Road "+(roads.Count+1),["from"]=from,["to"]=to,["points"]=new[]{start,end},["enabled"]=true,["locked"]=false,["max_grade"]=.12},true);roads.Add(road);road["follow_terrain"]=true;
        foreach(var pair in authored.Get("nodes").AsGodotDictionary())if(pair.Value.AsVector3().DistanceTo(start)<.001){nodes.Remove(from);road["from"]=pair.Key;start=pair.Value.AsVector3();break;}foreach(var pair in authored.Get("nodes").AsGodotDictionary())if(pair.Value.AsVector3().DistanceTo(end)<.001){nodes.Remove(to);road["to"]=pair.Key;end=pair.Value.AsVector3();break;}road["points"]=new[]{start,end};return next;
    }
    public string independence_error(RefCounted session,string id)
    {var document=Document(session);var building=Component(document,id);if(building==null)return "Select a generated building first.";var parameters=building.Get("parameters").AsGodotDictionary();var authored=source(Component(document,Get(parameters,"world_owner","").AsString()));return authored==null||Get(parameters,"world_plot","").AsString().Length==0?"This building is already independent.":"";}
    public string keep_independent(RefCounted session,string id)
    {string error=independence_error(session,id);if(error.Length>0)return error;session.Call("begin");detach_building(session,id);session.Call("commit","Keep generated building independent");return "";}
    public void detach_building(RefCounted session,string id)
    {
        var document=Document(session);var building=Component(document,id);if(building==null)return;var parameters=building.Get("parameters").AsGodotDictionary();var world=Component(document,Get(parameters,"world_owner","").AsString());var authored=source(world);string plot=Get(parameters,"world_plot","").AsString();if(authored==null||plot.Length==0)return;var next=_sources.copy(authored);next.Get("plot_overrides").AsGodotDictionary()[plot]=new Settings {["reserved"]=true};world!.Get("parameters").AsGodotDictionary()["world_source"]=next;
        foreach(var value in document.Get("components").AsGodotArray()){var item=value.As<Resource>();string itemId=item.Get("id").AsString();if(itemId!=id&&!document.Call("is_descendant",itemId,id).AsBool())continue;var data=item.Get("parameters").AsGodotDictionary();foreach(string key in new[]{"world_generated","world_owner","world_key","world_mesh_key","world_mesh_version","world_pose","world_global_pose","world_parent","world_manual_parent","world_structure","world_materials","world_architecture_source_key","world_generated_visible","world_manual_pose","world_lazy_building"})data.Remove(key);}
    }
    public bool starter_terrain(RefCounted session,Resource item,Resource terrain)
    {
        var settings=session.Call("environment").As<Resource>().Get("component_settings").AsGodotDictionary();return item.Get("title").AsString()=="Terrain"&&item.Get("parent_id").AsString().Length==0&&item.Get("transform").AsTransform3D()==Transform3D.Identity&&item.Get("modifiers").AsGodotArray().Count==0&&settings[item.Get("id")].AsGodotDictionary().Count==3&&terrain.Get("dimensions").AsVector2()==new Vector2(32,32)&&terrain.Get("resolution").AsInt32()==65&&terrain.Get("seed").AsInt64()==1&&terrain.Get("amplitude").AsDouble()==0&&terrain.Get("base_height").AsDouble()==0&&terrain.Get("generation").AsGodotObject()==null&&terrain.Get("erosion").AsGodotArray().Count==0&&terrain.Get("caves").AsGodotArray().Count==0&&terrain.Get("hydrology").AsGodotObject()==null&&terrain.Get("biomes").AsGodotObject()==null&&terrain.Get("edits").AsFloat32Array().All(value=>value==0)&&terrain.Get("material_mask").AsFloat32Array().All(value=>value==0);
    }
    public Resource add(RefCounted session,Vector3 position,bool includeTerrain,bool adaptStarterTerrain)
    {
        var authored=new WorldSource();_sources.configure_regions(authored);authored.Set("road_material",new StandardMaterial3D {AlbedoColor=new Color("393f44"),Roughness=.95f});new RoadSectionOperations().prepare(authored);var root=new KiwiModelComponent();root.Set("id",authored.Get("world_id"));root.Set("title","World");var parameters=root.Get("parameters").AsGodotDictionary();parameters["world_source"]=authored;parameters["editor_proxy"]=true;var dimensions=authored.Get("dimensions").AsVector2();root.Set("mesh",ModelPrimitives.Box(new Vector3(dimensions.X,.05f,dimensions.Y)).Build());root.Set("transform",new Transform3D(Basis.Identity,position));
        session.Call("begin");var document=Document(session);document.Get("components").AsGodotArray().Add(root);var environment=session.Call("environment").As<Resource>();environment.Get("component_settings").AsGodotDictionary()[root.Get("id")]=new Settings {["kind"]="group"};
        if(includeTerrain)
        {
            foreach(var value in document.Get("components").AsGodotArray())
            {
                var item=value.As<Resource>();var terrain=environment.Call("terrain",item.Get("id")).As<Resource>();if(terrain==null)continue;authored.Set("terrain_id",item.Get("id"));root.Set("transform",document.Call("world_transform",item));
                if(adaptStarterTerrain&&document.Get("components").AsGodotArray().Count==2&&starter_terrain(session,item,terrain)){terrain.Set("dimensions",authored.Get("dimensions"));terrain.Set("resolution",129);terrain.Call("prepare");item.Set("mesh",terrain.Call("editable_mesh"));item.Set("parent_id",root.Get("id"));item.Set("transform",Transform3D.Identity);item.Set("title","World terrain");authored.Set("owned_terrain_id",item.Get("id"));}else authored.Set("dimensions",terrain.Get("dimensions").AsVector2().Max(Vector2.One*16));break;
            }
            if(authored.Get("terrain_id").AsString().Length==0){var terrain=GD.Load<GDScript>("res://Workspaces/EnvironmentWorkspace/environment_terrain.gd").New().As<Resource>();terrain.Set("dimensions",authored.Get("dimensions"));terrain.Set("resolution",129);var ground=environment.Call("add_terrain",terrain).As<Resource>();ground.Set("parent_id",root.Get("id"));ground.Set("title","World terrain");authored.Set("terrain_id",ground.Get("id"));authored.Set("owned_terrain_id",ground.Get("id"));}
            _sources.configure_regions(authored);dimensions=authored.Get("dimensions").AsVector2();root.Set("mesh",ModelPrimitives.Box(new Vector3(dimensions.X,.05f,dimensions.Y)).Build());
        }
        var selected=session.Get("selected").AsGodotArray();selected.Clear();selected.Add(root.Get("id"));session.Call("commit","Add procedural world");return root;
    }
}
