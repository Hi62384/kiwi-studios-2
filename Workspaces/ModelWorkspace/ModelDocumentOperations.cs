using Godot;
using System;
using System.Collections.Generic;
using System.Linq;
using Settings=Godot.Collections.Dictionary;

public partial class ModelDocumentOperations : RefCounted
{
    private readonly ModelComponentOperations _components=new();
    private readonly RigMath _rig=new();
    private readonly RigBindingGeometry _bindings=new();
    private static string Text(Resource source,string key)=>source.Get(key).AsString();
    private static Resource[] Components(Resource source)=>source.Get("components").AsGodotArray().Select(value=>value.As<Resource>()).ToArray();
    internal static Dictionary<string,Resource> Lookup(Resource source)
    {var result=new Dictionary<string,Resource>();foreach(var item in Components(source))result[Text(item,"id")]=item;return result;}
    public Texture2D? thumbnail(Resource source)
    {
        var cached=source.Get("_thumbnail").As<Texture2D>();if(cached!=null)return cached;byte[] png=source.Get("preview_png").AsByteArray();
        if(png.Length>0){using var image=new Image();if(image.LoadPngFromBuffer(png)==Error.Ok){cached=ImageTexture.CreateFromImage(image);source.Set("_thumbnail",cached);}}
        return cached??source.Get("preview").As<Texture2D>();
    }
    public Resource? component(Resource source,string id)
    {foreach(Variant value in source.Get("components").AsGodotArray()){var item=value.As<Resource>();if(Text(item,"id")==id)return item;}return null;}
    internal static bool Descendant(Dictionary<string,Resource> lookup,string id,string ancestor)
    {
        lookup.TryGetValue(id,out var item);var seen=new HashSet<string>();
        while(item!=null&&seen.Add(Text(item,"id"))){string parent=Text(item,"parent_id");if(parent==ancestor)return true;lookup.TryGetValue(parent,out item);}return false;
    }
    public bool is_descendant(Resource source,string id,string ancestor)=>Descendant(Lookup(source),id,ancestor);
    public Transform3D world_transform(Resource source,Resource item)
    {
        return WorldTransform(Lookup(source),item);
    }
    internal static Transform3D WorldTransform(Dictionary<string,Resource> lookup,Resource item)
    {
        var result=item.Get("transform").AsTransform3D();var seen=new HashSet<string>{Text(item,"id")};lookup.TryGetValue(Text(item,"parent_id"),out var ancestor);
        while(ancestor!=null&&seen.Add(Text(ancestor,"id"))){result=ancestor.Get("transform").AsTransform3D()*result;lookup.TryGetValue(Text(ancestor,"parent_id"),out ancestor);}return result;
    }
    internal static bool Accessible(Dictionary<string,Resource> lookup,Resource? item,bool editable)
    {
        var seen=new HashSet<string>();
        while(item!=null&&seen.Add(Text(item,"id"))){if(!item.Get("visible").AsBool()||(editable&&item.Get("locked").AsBool()))return false;lookup.TryGetValue(Text(item,"parent_id"),out item);}return true;
    }
    public bool visible_component(Resource source,Resource? item)=>Accessible(Lookup(source),item,false);
    public bool editable_component(Resource source,Resource? item)=>Accessible(Lookup(source),item,true);
    public Settings hierarchy_state(Resource source,Godot.Collections.Array<string> chosen)
    {
        var lookup=Lookup(source);var poses=new Settings();var visible=new Settings();var selected=new Settings();var chosenIds=new HashSet<string>(chosen);
        foreach(var item in Components(source))
        {
            if(poses.ContainsKey(Text(item,"id")))continue;var chain=new List<Resource>();var seen=new HashSet<string>();Resource? current=item;
            while(current!=null&&!poses.ContainsKey(Text(current,"id"))&&seen.Add(Text(current,"id"))){chain.Add(current);lookup.TryGetValue(Text(current,"parent_id"),out current);}
            Transform3D pose=current!=null&&poses.TryGetValue(Text(current,"id"),out var found)?found.AsTransform3D():Transform3D.Identity;
            bool shown=current==null||!visible.TryGetValue(Text(current,"id"),out var shownValue)||shownValue.AsBool();bool included=current!=null&&selected.TryGetValue(Text(current,"id"),out var selectedValue)&&selectedValue.AsBool();
            for(int index=chain.Count-1;index>=0;index--){var part=chain[index];string id=Text(part,"id");pose*=part.Get("transform").AsTransform3D();shown&=part.Get("visible").AsBool();included|=chosenIds.Contains(id);poses[id]=pose;visible[id]=shown;selected[id]=included;}
        }
        return new Settings{["poses"]=poses,["visible"]=visible,["selected"]=selected};
    }
    public string[] validate(Resource source)
    {
        var errors=new List<string>();var ids=new HashSet<string>();var items=Components(source);var lookup=Lookup(source);
        foreach(var item in items)
        {
            string id=Text(item,"id");if(id.Length==0||!ids.Add(id))errors.Add("Missing or duplicate component identity");var transform=item.Get("transform").AsTransform3D();
            if(!transform.Origin.IsFinite()||!transform.Basis.IsFinite()||Mathf.Abs(transform.Basis.Determinant())<.0000001)errors.Add("Invalid component transform");
            if(item.Get("mesh").As<Resource>()!=null)errors.AddRange(source.Call("_component_geometry_errors",item).AsStringArray());
            if(item.Get("is_skeleton").AsBool())errors.AddRange(_rig.validate(item.Get("bones").AsGodotArray()));
        }
        foreach(var item in items)
        {
            var growth=item.Get("growth").As<Resource>();if(growth!=null&&(!lookup.TryGetValue(Text(growth,"source_id"),out var growthSource)||growthSource.Get("growth").As<Resource>()!=null))errors.Add("Missing or invalid surface-growth source");
            string parent=Text(item,"parent_id"),id=Text(item,"id");if(parent.Length>0&&(!ids.Contains(parent)||Descendant(lookup,parent,id)||parent==id))errors.Add("Invalid component hierarchy");
            var binding=item.Get("binding").As<Resource>();if(binding==null)continue;if(!lookup.TryGetValue(Text(item,"skeleton_id"),out var armature)||!armature.Get("is_skeleton").AsBool())errors.Add("Missing bound armature");else errors.AddRange(_bindings.validate(binding,armature));
        }
        return errors.ToArray();
    }
    private static bool GrowthMaterial(Resource resource)
    {
        var script=resource.GetScript().As<Script>();while(script!=null){if((script.ResourcePath=="res://Workspaces/ModelWorkspace/growth/growth_material.gd"||script.ResourcePath=="res://Workspaces/ModelWorkspace/growth/KiwiGrowthMaterial.cs"))return true;script=script.GetBaseScript();}return false;
    }
    public Resource snapshot(Resource source)
    {
        var result=new KiwiModelDocument();foreach(string property in new[]{"version","preview","preview_png"})result.Set(property,source.Get(property));result.Set("workspace_state",source.Get("workspace_state").AsGodotDictionary().Duplicate(true));
        var shared=new Dictionary<ulong,Variant>();var resultComponents=result.Get("components").AsGodotArray();
        foreach(var item in Components(source))
        {
            var copy=_components.copy_component(item,false);var growth=item.Get("growth").As<Resource>();
            if(growth!=null)
            {
                var copyGrowth=copy.Get("growth").As<Resource>();var appearance=growth.Get("appearance").As<Resource>();
                if(appearance!=null){ulong id=appearance.GetInstanceId();if(shared.TryGetValue(id,out var material))copyGrowth.Set("appearance",material);else shared[id]=copyGrowth.Get("appearance");}
                var regions=growth.Get("regions").AsGodotArray();var copiedRegions=copyGrowth.Get("regions").AsGodotArray();
                for(int index=0;index<regions.Count;index++)
                {
                    if(!regions[index].AsGodotDictionary().TryGetValue("material",out var original)||original.AsGodotObject() is not Resource material||!GrowthMaterial(material))continue;
                    ulong id=material.GetInstanceId();var region=copiedRegions[index].AsGodotDictionary();if(shared.TryGetValue(id,out var existing))region["material"]=existing;else shared[id]=region["material"];
                }
            }
            resultComponents.Add(copy);
        }
        return result;
    }
    public Settings transform_values(Transform3D transform)
    {
        Vector3 rotation=transform.Basis.GetRotationQuaternion().GetEuler(),scale=transform.Basis.Scale;Basis basis=Basis.FromEuler(rotation)*Basis.FromScale(scale);
        return new Settings{[new StringName("position")]=transform.Origin,[new StringName("rotation")]=rotation*(180/Mathf.Pi),[new StringName("scale")]=scale,[new StringName("model_basis_residual")]=basis.Inverse()*transform.Basis};
    }
}
