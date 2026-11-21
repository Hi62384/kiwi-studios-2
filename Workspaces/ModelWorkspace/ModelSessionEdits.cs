using Godot;
using System;
using System.Linq;
using System.Collections.Generic;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class ModelSessionEdits : RefCounted
{
    private readonly ModelPrimitives _primitives=new();
    private readonly ModelMeshOperations _meshes=new();
    private readonly ModelGeometryOperations _geometry=new();
    private readonly ModelComponentOperations _components=new();
    private readonly ModelModifiers _modifiers=new();
    private readonly ModelReferenceRemap _remap=new();
    private static Resource Doc(RefCounted owner)=>owner.Get("document").As<Resource>();
    private static string Text(Resource item,string key)=>item.Get(key).AsString();
    private static Godot.Collections.Array<string> Selected(RefCounted owner)=>owner.Get("selected").AsGodotArray<string>();
    private static Resource? Primary(RefCounted owner)=>owner.Call("primary").As<Resource>();
    private static void Changed(RefCounted owner)=>owner.EmitSignal("changed");
    private static void ResetElements(RefCounted owner)=>owner.Set("elements",Array.Empty<int>());
    private static void Action(RefCounted owner,string title,Action operation)
    {owner.Call("begin");try{operation();owner.Call("commit",title);}catch{owner.Call("cancel");throw;}}
    private static Resource EmptyComponent()=>new KiwiModelComponent();
    public void select(RefCounted owner,string id,bool additive)
    {
        var selected=Selected(owner);if(!additive)selected.Clear();if(id.Length>0){if(selected.Contains(id))selected.Remove(id);else selected.Add(id);}ResetElements(owner);Changed(owner);
    }
    public Resource add(RefCounted owner,string kind,Settings parameters,Vector3 position)
    {
        var architecture=GD.Load<GDScript>("res://Workspaces/EnvironmentWorkspace/architecture/architectural_component.gd");if(architecture.Call("accepts",kind).AsBool())return architecture.Call("add",owner,kind,parameters,position).As<Resource>();
        if(kind=="Building")return GD.Load<GDScript>("res://Workspaces/EnvironmentWorkspace/architecture/building_session.gd").Call("add",owner,position,parameters.TryGetValue("levels",out var levels)?levels.AsInt32():1).As<Resource>();
        var clusters=GD.Load<GDScript>("res://Workspaces/ModelWorkspace/natural_cluster.gd");if(clusters.Call("kinds").AsGodotArray().Any(value=>value.AsString()==kind))return clusters.Call("add",owner,kind,parameters,position).As<Resource>();
        var item=EmptyComponent();item.Set("id",Guid.NewGuid().ToString("N"));item.Set("title",kind);item.Set("generator",kind);var settings=_primitives.defaults(kind);settings.Merge(parameters,true);item.Set("parameters",settings);item.Set("mesh",_primitives.create(kind,settings));item.Set("transform",new Transform3D(Basis.Identity,position));
        var natural=GD.Load<GDScript>("res://Workspaces/ModelWorkspace/natural_generator.gd");if(natural.Call("accepts",kind).AsBool())item.Set("surface_materials",natural.Call("materials",kind,settings));
        Action(owner,"Add "+kind,()=>{Doc(owner).Get("components").AsGodotArray().Add(item);var selected=Selected(owner);selected.Clear();selected.Add(Text(item,"id"));ResetElements(owner);});return item;
    }
    public int[] selected_vertices(RefCounted owner)
    {
        var item=Primary(owner);if(item==null||item.Get("mesh").As<Resource>() is not Resource mesh)return Array.Empty<int>();string mode=owner.Get("mode").AsString();if((item.Get("skin_mesh").As<Mesh>()!=null||item.Get("binding").As<Resource>()!=null)&&mode!="Object")return Array.Empty<int>();
        int[] elements=owner.Get("elements").AsInt32Array();int count=mesh.Call("_vertex_count").AsInt32();if(mode=="Vertex")return elements.Where(index=>index>=0&&index<count).ToArray();var used=new Dictionary<int,bool>();
        if(mode=="Edge")
        {var edges=_meshes.edges(mesh);foreach(int index in elements)if(index>=0&&index<edges.Count){used[edges[index]["a"].AsInt32()]=true;used[edges[index]["b"].AsInt32()]=true;}}
        else if(mode=="Face")
        {var faces=mesh.Get("faces").AsGodotArray();foreach(int f in elements)if(f>=0&&f<faces.Count)foreach(int vertex in faces[f].AsInt32Array())used[vertex]=true;}
        else for(int i=0;i<count;i++)used[i]=true;
        return used.Keys.ToArray();
    }
}
