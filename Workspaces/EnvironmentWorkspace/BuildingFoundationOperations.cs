using Godot;
using System;
using System.Collections.Generic;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class BuildingFoundationOperations : RefCounted
{
    private readonly BuildingSessionOperations _buildings=new();
    private static Variant Get(Settings values,string key,Variant fallback=default)=>values.TryGetValue(key,out var value)?value:fallback;
    private static Resource Document(RefCounted session)=>session.Get("document").As<Resource>();
    private static Resource? Terrain(Resource document,string id)=>document.Call("terrain",id).As<Resource>();
    private static void ReplaceArray(Resource owner,string property,GArray values)
    {var typed=owner.Get(property).AsGodotArray().Duplicate();typed.Clear();foreach(var value in values)typed.Add(value);owner.Set(property,typed);}
    private static bool SurfaceTarget(GArray layers)
    {foreach(var value in layers)if(Get(value.AsGodotDictionary(),"surface_target",false).AsBool())return true;return false;}
    private static (Plane Plane,Vector2[] Polygon) Project(Resource source,Transform3D relative)
    {
        var floor=source.Get("floors").AsGodotArray()[0].AsGodotDictionary();float height=(float)(Get(floor,"elevation",0.0).AsDouble()-source.Get("slab_thickness").AsDouble());var plane=new Plane(relative*new Vector3(0,height,0),relative*new Vector3(1,height,0),relative*new Vector3(0,height,1));var points=Get(floor,"footprint",source.Get("footprint")).AsVector2Array();var polygon=new Vector2[points.Length];for(int index=0;index<points.Length;index++){var position=relative*new Vector3(points[index].X,height,points[index].Y);polygon[index]=new Vector2(position.X,position.Z);}return(plane,polygon);
    }
    private static void Rebuild(Resource terrain,Resource item)
    {foreach(string method in new[]{"prepare","prepare_water","prepare_biomes","prepare_volumes","prepare_cave_biomes"})terrain.Call(method);terrain.Set("revision",terrain.Get("revision").AsInt64()+1);item.Set("mesh",terrain.Call("editable_mesh"));}
    public string set_modifier(RefCounted session,string id,string terrainId,double feather,bool remove)
    {
        var document=Document(session);var lookup=ModelDocumentOperations.Lookup(document);lookup.TryGetValue(id,out var root);lookup.TryGetValue(terrainId,out var ground);var source=_buildings.source(root);var terrain=Terrain(document,terrainId);if(source==null||terrain==null||ground==null||!ModelDocumentOperations.Accessible(lookup,ground,true))return "Choose an editable building and terrain.";var world=ModelDocumentOperations.WorldTransform(lookup,ground);if(Math.Abs(world.Basis.Determinant())<.000001)return "A zero-size terrain cannot receive a foundation modifier.";var projected=Project(source,world.AffineInverse()*ModelDocumentOperations.WorldTransform(lookup,root!));if(Math.Abs(projected.Plane.Normal.Y)<.2)return "The foundation is too steep relative to this terrain.";var previous=terrain.Get("generation").As<Resource>();var generator=previous!=null?previous.Duplicate(true):GD.Load<GDScript>("res://Workspaces/EnvironmentWorkspace/terrain/terrain_generator.gd").New().As<Resource>();if(previous==null){generator.Set("medium_weight",0.0);generator.Set("fine_weight",0.0);}generator.Set("foundation_edits",terrain.Get("edits"));var layers=new GArray();foreach(var value in generator.Get("layers").AsGodotArray())if(Get(value.AsGodotDictionary(),"foundation_owner", "").AsString()!=id)layers.Add(value);if(!remove)layers.Add(new Settings {["id"]="foundation:"+id,["foundation_owner"]=id,["type"]="Foundation",["enabled"]=true,["polygon"]=projected.Polygon,["plane"]=projected.Plane,["feather"]=Math.Max(0,feather),["surface_target"]=true});ReplaceArray(generator,"layers",layers);if(!SurfaceTarget(layers))generator.Set("foundation_edits",Array.Empty<float>());var errors=generator.Call("validate").AsStringArray();if(errors.Length>0)return errors[0];session.Call("regenerate_terrain",terrainId,new Settings {["generation"]=generator});return "";
    }
    public void remove_for_owners(RefCounted session,Settings removed)
    {
        var document=Document(session);foreach(var value in document.Get("components").AsGodotArray())
        {
            var item=value.As<Resource>();string id=item.Get("id").AsString();if(removed.ContainsKey(id))continue;var terrain=Terrain(document,id);if(terrain==null)continue;var generation=terrain.Get("generation").As<Resource>();var original=generation!=null?generation.Get("layers").AsGodotArray():new GArray();var layers=new GArray();foreach(var layerValue in original){var layer=layerValue.AsGodotDictionary();if(Get(layer,"type", "").AsString()=="Foundation"&&(removed.ContainsKey(Get(layer,"foundation_owner", "").AsString())||removed.ContainsKey(Get(layer,"world_road_owner", "").AsString())))continue;layers.Add(layerValue);}var caves=new GArray();var originalCaves=terrain.Get("caves").AsGodotArray();foreach(var caveValue in originalCaves){var cave=caveValue.As<Resource>();if(cave.HasMeta("world_road_owner")&&removed.ContainsKey(cave.GetMeta("world_road_owner").AsString()))continue;caves.Add(cave);}if(layers.Count==original.Count&&caves.Count==originalCaves.Count)continue;if(generation!=null){generation=generation.Duplicate(true);ReplaceArray(generation,"layers",layers);if(!SurfaceTarget(layers))generation.Set("foundation_edits",Array.Empty<float>());terrain.Set("generation",generation);}ReplaceArray(terrain,"caves",caves);Rebuild(terrain,item);
        }
    }
    public void refresh_links(RefCounted session)
    {
        var document=Document(session);var lookup=ModelDocumentOperations.Lookup(document);foreach(var item in lookup.Values)
        {
            var terrain=Terrain(document,item.Get("id").AsString());if(terrain==null)continue;var generator=terrain.Get("generation").As<Resource>();if(generator==null)continue;var groundPose=ModelDocumentOperations.WorldTransform(lookup,item);if(Math.Abs(groundPose.Basis.Determinant())<.000001)continue;var layers=new GArray();bool changed=false;foreach(var value in generator.Get("layers").AsGodotArray())
            {
                var original=value.AsGodotDictionary();var layer=original.Duplicate(true);if(Get(layer,"type", "").AsString()=="Foundation")
                {
                    lookup.TryGetValue(Get(layer,"foundation_owner", "").AsString(),out var root);var source=_buildings.source(root);if(source!=null){layer["surface_target"]=true;var projected=Project(source,groundPose.AffineInverse()*ModelDocumentOperations.WorldTransform(lookup,root!));if(Math.Abs(projected.Plane.Normal.Y)<.2){layer["foundation_blocked"]=true;layer["enabled"]=false;}else{if(Get(layer,"foundation_blocked",false).AsBool()){layer.Remove("foundation_blocked");layer["enabled"]=true;}layer["plane"]=projected.Plane;layer["polygon"]=projected.Polygon;}}
                }
                changed|=!layer.RecursiveEqual(original);layers.Add(layer);
            }
            if(!changed)continue;generator=generator.Duplicate(true);ReplaceArray(generator,"layers",layers);generator.Set("foundation_edits",terrain.Get("edits"));terrain.Set("generation",generator);Rebuild(terrain,item);
        }
    }
}
