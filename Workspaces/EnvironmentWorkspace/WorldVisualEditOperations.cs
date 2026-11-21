using Godot;
using System;
using System.Linq;
using System.Collections.Generic;
using Settings=Godot.Collections.Dictionary;

public partial class WorldVisualEditOperations : RefCounted
{
    private readonly ModelDocumentOperations _models=new();
    private readonly ModelComponentOperations _components=new();
    private readonly RoadSectionOperations _sections=new();
    private readonly WorldSourceOperations _sources=new();
    private readonly EnvironmentDataHash _hash=new();
    private static Settings Parameters(Resource item)=>item.Get("parameters").AsGodotDictionary();
    private static Variant Get(Settings values,string key,Variant fallback=default)=>values.TryGetValue(key,out var value)?value:fallback;
    public Settings snapshot(RefCounted session,string id,Resource desired)
    {
        var installed=session.Get("document").As<Resource>();var original=_models.component(installed,id);var current=original==null?null:Get(Parameters(original),"world_source").As<Resource>();if(current==null||current.GetScript().As<Script>()?.ResourcePath!="res://Workspaces/EnvironmentWorkspace/world/WorldSource.cs"||!Parameters(original!).ContainsKey("world_graph")||_sources.geometry_signature(current)!=_sources.geometry_signature(desired))return new();var errors=_sources.validate(desired);if(errors.Length>0)return new Settings {["document"]=default,["errors"]=errors,["warnings"]=Array.Empty<string>(),["signature"]=_sources.signature(desired)};
        var document=new KiwiModelDocument();var root=_components.copy_component(original!,false);Parameters(root)["world_source"]=desired;var parts=document.Get("components").AsGodotArray();parts.Add(root);var settings=new Settings();var edges=new Dictionary<string,Settings>(StringComparer.Ordinal);foreach(var value in Parameters(original!)["world_graph"].AsGodotDictionary()["edges"].AsGodotArray()){var edge=value.AsGodotDictionary();edges[edge["id"].AsString()]=edge;}
        var allSettings=installed.Get("component_settings").AsGodotDictionary();foreach(var value in installed.Get("components").AsGodotArray())
        {
            var item=value.As<Resource>();var parameters=Parameters(item);if(!Get(parameters,"world_generated",false).AsBool()||Get(parameters,"world_owner","").AsString()!=id)continue;string componentId=item.Get("id").AsString();var part=_components.copy_component(item,false);parts.Add(part);var metadata=Get(allSettings,componentId,new Settings {["kind"]="asset",["collision"]=true}).AsGodotDictionary().Duplicate(true);settings[part.Get("id")]=metadata;Material? material=null;bool replace=false;
            if(parameters.TryGetValue("world_road",out var roadId)){if(edges.TryGetValue(roadId.AsString(),out var edge)){material=_sections.material(desired,edge,"surface");replace=true;}}
            else
            {
                var parent=_models.component(installed,item.Get("parent_id").AsString());string key=Get(parameters,"world_key","").AsString(),detail=Get(parameters,"road_detail","").AsString();
                if(detail.Length>0){var edge=parent!=null&&edges.TryGetValue(Get(Parameters(parent),"world_road","").AsString(),out var road)?road:new Settings();material=_sections.material(desired,edge,detail);replace=true;}
                else if(key.StartsWith(":junction:",StringComparison.Ordinal)){material=desired.Get("road_material").As<Material>();replace=true;}
                else if(key.StartsWith(":portals:",StringComparison.Ordinal)||parent!=null&&Parameters(parent).ContainsKey("world_road")&&(key.EndsWith(":railings",StringComparison.Ordinal)||key.EndsWith(":supports",StringComparison.Ordinal))){material=desired.Get("shoulder_material").As<Material>()??desired.Get("road_material").As<Material>();replace=true;}
            }
            if(replace){var materials=part.Get("surface_materials").AsGodotArray();materials.Clear();materials.Add(material!=null?Variant.From(material):default);Parameters(part)["world_materials"]=materials.Duplicate();}
            var scatter=Get(metadata,"scatter").As<Resource>();if(scatter!=null)
            {
                var rules=scatter.Duplicate(true);metadata["scatter"]=rules;var defaults=Get(Parameters(part),"world_scatter_defaults",new Settings()).AsGodotDictionary().Duplicate(true);if(defaults.TryGetValue("render_distance",out var stored)&&stored.AsInt64()==_hash.value(scatter.Get("render_distance"))){double cap=300;if(Parameters(part).ContainsKey("world_forest")){var key=Get(Parameters(part),"world_key","").AsString();string tail=key.Split(':')[^1];int.TryParse(tail,out int index);cap=new[]{500.0,350,200,120}[Math.Clamp(index,0,3)];}double distance=desired.Get("render_distance").AsDouble();rules.Set("render_distance",distance>0?Math.Min(distance,cap):0);defaults["render_distance"]=_hash.value(rules.Get("render_distance"));Parameters(part)["world_scatter_defaults"]=defaults;}
            }
        }
        var included=new HashSet<string>(parts.Select(value=>value.As<Resource>().Get("id").AsString()),StringComparer.Ordinal);root.Set("parent_id","");foreach(var value in parts){var part=value.As<Resource>();string parent=part.Get("parent_id").AsString();if(parent.Length>0&&!included.Contains(parent))part.Set("parent_id",id);}return new Settings {["document"]=document,["settings"]=settings,["errors"]=_models.validate(document),["warnings"]=Array.Empty<string>(),["development_reused"]=true,["visual_only"]=true,["signature"]=_sources.signature(desired)};
    }
}
