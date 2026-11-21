using Godot;
using System.Linq;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class RoadNetworkOperations
{
    public Settings populate(Resource document,Resource source,Settings layout,Settings graphData,Settings cancellation)
        =>Populate(document,source,layout,graphData,Cancellation(cancellation));
    private Settings Populate(Resource document,Resource source,Settings layout,Settings graphData,System.Func<bool> cancelled)
    {
        var forests=new WorldForestOperations().Build(document,source,layout,graphData,cancelled);
        if(Get(forests,"cancelled",false).AsBool())return forests;
        var props=new WorldPropOperations().Build(document,source,layout,graphData,cancelled);
        if(Get(props,"cancelled",false).AsBool())return props;
        forests["settings"].AsGodotDictionary().Merge(props["settings"].AsGodotDictionary());
        forests["errors"]=forests["errors"].AsStringArray().Concat(props["errors"].AsStringArray()).ToArray();
        forests["warnings"]=forests["warnings"].AsStringArray().Concat(props["warnings"].AsStringArray()).ToArray();
        return forests;
    }
    public Resource item(Resource document,string id,string title,string parent,Resource mesh,Material? material,string owner)
    {
        if(owner.Length==0)owner=parent;
        var component=new KiwiModelComponent();
        component.Set("id",id);component.Set("title",title);component.Set("parent_id",parent);component.Set("mesh",mesh);
        var materials=component.Get("surface_materials").AsGodotArray();materials.Clear();materials.Add(material!=null?Variant.From(material):default);
        var parameters=component.Get("parameters").AsGodotDictionary();parameters["world_generated"]=true;parameters["world_owner"]=owner;
        parameters["world_key"]=id.StartsWith(owner,System.StringComparison.Ordinal)?id[owner.Length..]:id;
        parameters["world_pose"]=component.Get("transform");parameters["world_structure"]=component.Get("structural").AsGodotDictionary().Duplicate(true);
        parameters["world_materials"]=materials.Duplicate();parameters["world_mesh_key"]=unchecked((uint)GD.Hash(new GArray {mesh.Get("vertices"),mesh.Get("faces")}));
        document.Get("components").AsGodotArray().Add(component);return component;
    }
}
